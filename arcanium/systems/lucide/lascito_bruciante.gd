extends Node3D

## ═══════════════════════════════════════
## LASCITO DEL BRUCIANTE — il fascio dell'arco di Ilwen
## ═══════════════════════════════════════
##
## Lucida Tecnica dell'Arco di Spirito Sylvorn (idea dell'autore, 2026-11-07): Ilwen
## scocca, ma la freccia non viene dalla faretra: e' un fascio di teal bruciante
## evocato dall'arco. E' largo, prende piu' nemici vicini, dura 3 secondi con danni
## continui e accumulo di Bruciatura, e sotto al suo passaggio lascia il terreno
## bruciato.
##
## Nasce al rilascio dall'incocco dell'arco. Ilwen resta ferma finche' non e' concluso, e
## un colpo subito lo interrompe (LucidaTecnica.ferma, `spegni`). Mira al bersaglio
## agganciato, o dritto; va in orizzontale. Un muro lo ferma; sopra un baratro passa, ma
## li' non brucia niente.
##
## Il BRUCIATO resta a terra 5 secondi dopo il fascio, e non e' solo da vedere: fa salire
## la Bruciatura a qualunque nemico ci resti dentro abbastanza a lungo.
##
## Come per l'onda di Zarine, il danno e' quello dell'arma, che scala con le Marche,
## per il `danno_mult` della tecnica: qui vale PER COLPO, uno ogni `TICK`.

const Fazioni := preload("res://arcanium/systems/fazioni.gd")
const SoloMondo := preload("res://arcanium/systems/lucide/solo_mondo.gd")
const Scossa := preload("res://arcanium/systems/vfx/scossa.gd")
const Suoni := preload("res://arcanium/systems/vfx/suoni.gd")
const Faville := preload("res://arcanium/systems/lucide/faville.gd")
const OMBRA_FASCIO := preload("res://arcanium/systems/lucide/fascio_bruciante.gdshader")
const OMBRA_BRUCIATO := preload("res://arcanium/systems/lucide/bruciato_teal.gdshader")

const LUNGHEZZA := 22.0
const RAGGIO := 1.25
const VELOCITA := 70.0
const DURATA := 3.0
## Il fascio si spegne in fretta; il bruciato resta ancora un po'.
const SPEGNIMENTO := 0.35
const BRUCIATO_DOPO := 5.0
## L'accumulo al colpo di chi sta sul bruciato: 40 al secondo, poco piu' di due secondi e
## mezzo per farlo scattare. Uscirne in tempo basta.
const BRUCIATO_ACCUMULO := 10.0
const BRUCIATO_LARGO := 1.45
const TICK := 0.25
const BRUCIATURA := 16.0
const POISE := 4.0
const SOPRA := 1.3
const SOTTO := 3.2
const MASCHERA_MONDO := 1
const CELLA := 0.6
const MEZZA_STRISCIA := 2.2

var lanciatore : Node = null
var potenza : float = 0.0

var _t := 0.0
var _al_tick := 0.0
var _lunghezza := LUNGHEZZA
var _quota_suolo := 0.0
var _fascio : ShaderMaterial
var _nucleo : ShaderMaterial
var _bruciato : ShaderMaterial
var _faville
var _luce : OmniLight3D
## Quando finisce il fascio: DURATA, o prima se chi l'ha lanciato viene interrotto.
var _fine := DURATA
var _al_tick_bruciato := 0.0
var _celle : PackedByteArray = PackedByteArray()
var _celle_larghe := 0
var _celle_lunghe := 0


class Colpo extends Resource:
	var power : float = 0.0
	var damage_type : String = "FUOCO"
	var burn_buildup : float = 0.0
	var poise_damage : float = 0.0
	## Un filo: senza, ogni colpo del fascio farebbe tremare la camera di default.
	var scossa : float = 0.01


func _ready() -> void:
	_prendi_la_mira()
	_misura()
	_costruisci()
	Scossa.nel_mondo(global_position, Scossa.MEDIO)
	Suoni.nel_mondo(self, Suoni.CARICA_ARCANA)


## Dall'incocco dell'arco, verso il bersaglio agganciato o dritto; +Z e' l'avanti.
func _prendi_la_mira() -> void:
	var origine : Vector3 = global_position
	var arcieria : Node = lanciatore.get_node_or_null("ArcieriaPlayer") if lanciatore != null else null
	if arcieria != null and arcieria.has_method("bocca"):
		origine = arcieria.bocca()
	var avanti : Vector3 = global_transform.basis.z
	if lanciatore != null and lanciatore.has_method("aim_direction_from"):
		avanti = lanciatore.aim_direction_from(origine, avanti)
	avanti.y = 0.0
	avanti = avanti.normalized() if avanti.length_squared() > 0.001 else Vector3.BACK
	global_transform = Transform3D(Basis(Vector3.UP, atan2(avanti.x, avanti.z)), origine)
	_quota_suolo = (lanciatore as Node3D).global_position.y if lanciatore is Node3D else origine.y - 1.35


func _misura() -> void:
	var spazio := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, to_global(Vector3.BACK * LUNGHEZZA), MASCHERA_MONDO,
			SoloMondo.esclusi(get_tree(), lanciatore))
	var colpo := spazio.intersect_ray(q)
	if not colpo.is_empty():
		_lunghezza = maxf(2.0, global_position.distance_to(colpo["position"]) + 0.4)


func _physics_process(delta : float) -> void:
	_t += delta
	var fronte := minf(_t * VELOCITA, _lunghezza + 1.6)
	if _t <= _fine:
		_al_tick -= delta
		if _al_tick <= 0.0:
			_al_tick += TICK
			_brucia(fronte)
	_al_tick_bruciato -= delta
	if _al_tick_bruciato <= 0.0:
		_al_tick_bruciato += TICK
		_scotta(fronte)
	_anima(fronte)
	if _t > _fine + BRUCIATO_DOPO:
		queue_free()


## Chi l'ha lanciato e' stato interrotto: il fascio si spegne, il bruciato resta i suoi
## secondi.
func spegni() -> void:
	_fine = minf(_fine, _t)


## Chi sta sul terreno bruciato accumula Bruciatura, senza colpi: non e' un'arma, e non
## deve farlo sobbalzare.
func _scotta(fronte : float) -> void:
	for raw in get_tree().get_nodes_in_group("targets"):
		var n := raw as Node3D
		if n == null or not Fazioni.colpibile(n, lanciatore):
			continue
		var l : Vector3 = to_local(n.global_position)
		if l.z < 0.0 or l.z > minf(fronte, _lunghezza) or absf(l.x) > BRUCIATO_LARGO:
			continue
		if absf(n.global_position.y - _quota_suolo) > 1.0 or not _sul_bruciato(l):
			continue
		var salute = n.get("health_system")
		var host = salute.get("status_host") if salute != null else null
		if host != null and host.has_method("build_burn"):
			host.build_burn(BRUCIATO_ACCUMULO)


func _sul_bruciato(l : Vector3) -> bool:
	var i := int(round((l.x + MEZZA_STRISCIA) / CELLA))
	var j := int(round(l.z / CELLA))
	return i >= 0 and j >= 0 and i < _celle_larghe and j < _celle_lunghe and _celle[j * _celle_larghe + i] == 255


func _brucia(fronte : float) -> void:
	for raw in get_tree().get_nodes_in_group("targets"):
		var n := raw as Node3D
		if n == null or not Fazioni.colpibile(n, lanciatore):
			continue
		var l : Vector3 = to_local(n.global_position)
		if l.z < 0.0 or l.z > minf(fronte, _lunghezza) or absf(l.x) > RAGGIO + 0.4:
			continue
		if l.y > SOPRA or l.y < -SOTTO:
			continue
		var c := Colpo.new()
		c.power = potenza
		c.burn_buildup = BRUCIATURA
		c.poise_damage = POISE
		n.hit(lanciatore, c)


# ─── Quello che si vede ─────────────────────────────────────────────────────

func _anima(fronte : float) -> void:
	var vita := clampf(1.0 - (_t - _fine) / SPEGNIMENTO, 0.0, 1.0)
	for m in [_fascio, _nucleo]:
		m.set_shader_parameter("fronte", fronte)
		m.set_shader_parameter("vita", vita)
	_bruciato.set_shader_parameter("fronte", fronte)
	## Le braci restano accese per tutto il tempo in cui il bruciato scotta.
	_bruciato.set_shader_parameter("braci", clampf((_fine + BRUCIATO_DOPO - _t) / 1.5, 0.15, 1.0))
	_bruciato.set_shader_parameter("vita", clampf((_fine + BRUCIATO_DOPO - _t) / 1.0, 0.0, 1.0))
	_luce.light_energy = 3.2 * vita * (0.85 + 0.15 * sin(_t * 23.0))
	if vita > 0.0:
		for _k in 4:
			var z := randf_range(0.5, minf(fronte, _lunghezza))
			var giro := randf_range(0.0, TAU)
			var dove := Vector3(cos(giro) * RAGGIO * 0.9, sin(giro) * RAGGIO * 0.9, z)
			_faville.emetti(dove, Vector3(cos(giro), absf(sin(giro)) + 0.8, randf_range(-0.5, 2.0)) * randf_range(0.7, 2.0),
					randf_range(0.4, 0.95), Color(0.3, 1.0, 0.9))


func _costruisci() -> void:
	_fascio = _cilindro("Fascio", RAGGIO, 0.55, 0.32)
	_nucleo = _cilindro("Nucleo", RAGGIO * 0.42, 1.0, 0.16)
	_nucleo.set_shader_parameter("esterno", Vector3(0.3, 0.95, 0.85))
	_nucleo.set_shader_parameter("interno", Vector3(0.92, 1.0, 0.98))
	_costruisci_bruciato()
	_faville = Faville.new()
	_faville.name = "Faville"
	add_child(_faville)
	_faville.prepara(170, 0.17)
	_luce = OmniLight3D.new()
	_luce.name = "Luce"
	_luce.light_color = Color(0.25, 1.0, 0.88)
	_luce.omni_range = 11.0
	_luce.position = Vector3(0.0, 0.0, minf(5.0, _lunghezza * 0.5))
	add_child(_luce)


func _cilindro(nome : String, raggio : float, forza : float, agitazione : float) -> ShaderMaterial:
	var cilindro := CylinderMesh.new()
	cilindro.top_radius = raggio
	cilindro.bottom_radius = raggio
	cilindro.height = _lunghezza
	cilindro.radial_segments = 18
	cilindro.rings = int(_lunghezza * 1.5)
	cilindro.cap_top = false
	cilindro.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = OMBRA_FASCIO
	m.set_shader_parameter("lunghezza", _lunghezza)
	m.set_shader_parameter("forza", forza)
	m.set_shader_parameter("agitazione", agitazione)
	var mi := MeshInstance3D.new()
	mi.name = nome
	mi.mesh = cilindro
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## La Y del cilindro lungo il +Z del nodo, con la base all'origine.
	mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.BACK * _lunghezza * 0.5)
	add_child(mi)
	return m


func _costruisci_bruciato() -> void:
	var piano := PlaneMesh.new()
	piano.size = Vector2(MEZZA_STRISCIA * 2.0, _lunghezza)
	_bruciato = ShaderMaterial.new()
	_bruciato.shader = OMBRA_BRUCIATO
	_bruciato.set_shader_parameter("lunghezza", _lunghezza)
	_bruciato.set_shader_parameter("margine", MEZZA_STRISCIA)
	_bruciato.set_shader_parameter("suolo", _texture_suolo())
	var mi := MeshInstance3D.new()
	mi.name = "Bruciato"
	mi.mesh = piano
	mi.material_override = _bruciato
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, _quota_suolo - global_position.y + 0.06, _lunghezza * 0.5)
	add_child(mi)


## Dove sotto il fascio c'e' suolo alla quota di chi l'ha lanciato: su un baratro o un
## ripiano diverso non resta il bruciato.
func _texture_suolo() -> ImageTexture:
	var larghe := int(ceil(MEZZA_STRISCIA * 2.0 / CELLA)) + 1
	var lunghe := int(ceil(_lunghezza / CELLA)) + 1
	var spazio := get_world_3d().direct_space_state
	var fuori := SoloMondo.esclusi(get_tree(), lanciatore)
	var pixel := PackedByteArray()
	pixel.resize(larghe * lunghe)
	for j in lunghe:
		for i in larghe:
			var locale := Vector3(-MEZZA_STRISCIA + i * CELLA, 0.0, j * CELLA)
			var mondo := to_global(locale)
			mondo.y = _quota_suolo
			var q := PhysicsRayQueryParameters3D.create(mondo + Vector3.UP * 1.0, mondo + Vector3.DOWN * 1.0, MASCHERA_MONDO, fuori)
			var colpo := spazio.intersect_ray(q)
			pixel[j * larghe + i] = 255 if not colpo.is_empty() and absf(colpo["position"].y - _quota_suolo) < 0.45 else 0
	_celle = pixel
	_celle_larghe = larghe
	_celle_lunghe = lunghe
	return ImageTexture.create_from_image(Image.create_from_data(larghe, lunghe, false, Image.FORMAT_R8, pixel))
