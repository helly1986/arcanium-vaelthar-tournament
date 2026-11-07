extends Node3D

## ═══════════════════════════════════════
## PROPAGAZIONE DELL'EQUILIBRIO — l'onda dell'asta di Zarine
## ═══════════════════════════════════════
##
## Lucida Tecnica dell'Asta del Contrappeso (idea dell'autore, 2026-11-07): Zarine
## sbatte l'asta a terra e dal terreno emerge un'onda sismica divisa a meta', come
## il suo vestito: SINISTRA OSCURA, DESTRA LUCENTE. Colpisce tutti quelli che il
## fronte raggiunge, una volta sola, con molti danni e lo status della meta' in cui
## stanno.
##
## Nasce all'impatto (LucidaTecnica.impatto) con l'orientamento di chi colpisce, che
## guarda +Z: la sua sinistra e' +X nello spazio di questo nodo.
##
## ─── Chi prende cosa ────────────────────────────────────
## Il danno e' quello dell'arma, che scala con le Marche, per `danno_mult`: lo passa
## il caster in `potenza`. Il tipo e lo status dipendono dalla meta':
##   lucente — SACRO, Frattura: incassa di piu' per un po';
##   oscura  — EROSIONE, l'Emorragia che scatta subito: un morso alla vita massima.
## (L'Erosione dell'Eco qui non serve: toglie Arcanium e fiato, che i nemici non hanno.)
##
## ─── I bersagli ─────────────────────────────────────────
## Come il campo degli incantesimi: il gruppo "targets" e la distanza, senza
## Area3D. Chi puo' essere ferito lo decide `Fazioni`. Un bersaglio troppo piu' in
## alto o in basso non lo prende: l'onda corre sul terreno.
##
## ─── Corre sul suolo, non sulla mappa ───────────────────
## All'impatto sonda il terreno con una griglia di raggi e tiene solo le celle
## collegate al punto d'impatto (`_mappa_il_suolo`): i baratri e i muri la fermano,
## per il danno, per gli spuntoni e per lo shader.

const Fazioni := preload("res://arcanium/systems/fazioni.gd")
const SoloMondo := preload("res://arcanium/systems/lucide/solo_mondo.gd")
const Scossa := preload("res://arcanium/systems/vfx/scossa.gd")
const Suoni := preload("res://arcanium/systems/vfx/suoni.gd")
const SchiantoATerra := preload("res://arcanium/systems/vfx/schianto_a_terra.gd")
const OMBRA := preload("res://arcanium/systems/lucide/onda_equilibrio.gdshader")
const Faville := preload("res://arcanium/systems/lucide/faville.gd")

const RAGGIO := 7.5
const VELOCITA := 13.0
## Quanto dura il suolo acceso dopo che il fronte e' arrivato in fondo.
const SPEGNIMENTO := 1.1
const DISLIVELLO := 2.2
const SPUNTONI := 72
const FAVILLE := 150

const FRATTURA_MULT := 1.35
const FRATTURA_DURATA := 15.0
## L'accumulo di Emorragia: la soglia e' 100, l'onda la fa scattare da sola.
const EMORRAGIA := 100.0
const POISE := 60.0
## La griglia del suolo: mezza larghezza in celle, e quanto e' grande una cella.
const CELLE := 14
const CELLA := 0.6
## Chi e' solido per l'onda: il layer del mondo.
const MASCHERA_MONDO := 1

## Chi l'ha lanciata, e il danno gia' scalato sulle Marche. Li scrive il caster.
var lanciatore : Node = null
var potenza : float = 0.0

var _t := 0.0
var _colpiti : Array = []
var _ombra : ShaderMaterial
var _spuntoni : MultiMesh
var _dati_spuntoni : Array = []
var _faville
## 1 per le celle su cui l'onda arriva.
var _suolo : PackedByteArray = PackedByteArray()


class Colpo extends Resource:
	var power : float = 0.0
	var damage_type : String = "SACRO"
	var inflicts_fracture : bool = false
	var fracture_multiplier : float = 1.0
	var fracture_duration : float = 0.0
	var laceration_buildup : float = 0.0
	var poise_damage : float = 0.0
	var scossa : float = 0.0


func _ready() -> void:
	_mappa_il_suolo()
	_costruisci_suolo()
	_costruisci_spuntoni()
	_costruisci_faville()
	SchiantoATerra.al_punto(get_parent(), global_position, Vector3.UP, 1.3)
	Scossa.nel_mondo(global_position, Scossa.DEVASTANTE)
	Suoni.nel_mondo(self, Suoni.SCHIANTO_MASSO)


## Sonda la griglia e allaga dal centro: resta il suolo alla stessa quota, collegato
## al punto d'impatto. Un raggio che parte dentro un muro non trova niente, e un
## ripiano troppo alto o basso non e' lo stesso piano.
func _mappa_il_suolo() -> void:
	var lato := CELLE * 2 + 1
	var buono := PackedByteArray()
	buono.resize(lato * lato)
	var spazio := get_world_3d().direct_space_state
	var fuori := SoloMondo.esclusi(get_tree(), lanciatore)
	for j in lato:
		for i in lato:
			var mondo := to_global(Vector3((i - CELLE) * CELLA, 0.0, (j - CELLE) * CELLA))
			var q := PhysicsRayQueryParameters3D.create(mondo + Vector3.UP * 1.2, mondo + Vector3.DOWN * 1.2, MASCHERA_MONDO, fuori)
			var colpo := spazio.intersect_ray(q)
			buono[j * lato + i] = 1 if not colpo.is_empty() and absf(colpo["position"].y - global_position.y) < 0.45 else 0
	_suolo.resize(lato * lato)
	_suolo.fill(0)
	## L'impatto cade sempre sul suolo, anche se la cella centrale dice il contrario.
	buono[CELLE * lato + CELLE] = 1
	_suolo[CELLE * lato + CELLE] = 1
	var da_fare : Array[Vector2i] = [Vector2i(CELLE, CELLE)]
	while not da_fare.is_empty():
		var c : Vector2i = da_fare.pop_back()
		for v in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n : Vector2i = c + v
			if n.x < 0 or n.y < 0 or n.x >= lato or n.y >= lato:
				continue
			var k := n.y * lato + n.x
			if buono[k] == 1 and _suolo[k] == 0:
				_suolo[k] = 1
				da_fare.append(n)


## Vero se l'onda arriva sul punto dato, nello spazio di questo nodo.
func _sul_suolo(locale : Vector3) -> bool:
	var i := int(round(locale.x / CELLA)) + CELLE
	var j := int(round(locale.z / CELLA)) + CELLE
	var lato := CELLE * 2 + 1
	return i >= 0 and j >= 0 and i < lato and j < lato and _suolo[j * lato + i] == 1


func _texture_suolo() -> ImageTexture:
	var lato := CELLE * 2 + 1
	var pixel := PackedByteArray()
	pixel.resize(lato * lato)
	for k in lato * lato:
		pixel[k] = 255 if _suolo[k] == 1 else 0
	return ImageTexture.create_from_image(Image.create_from_data(lato, lato, false, Image.FORMAT_R8, pixel))


## La meta' dell'onda in cui sta un punto del mondo: vero se e' quella oscura.
func oscura(punto : Vector3) -> bool:
	return to_local(punto).x > 0.0


func colpo_per(punto : Vector3) -> Colpo:
	var c := Colpo.new()
	c.power = potenza
	c.poise_damage = POISE
	c.scossa = Scossa.PESANTE
	if oscura(punto):
		c.damage_type = "EROSIONE"
		c.laceration_buildup = EMORRAGIA
	else:
		c.damage_type = "SACRO"
		c.inflicts_fracture = true
		c.fracture_multiplier = FRATTURA_MULT
		c.fracture_duration = FRATTURA_DURATA
	return c


func _physics_process(delta : float) -> void:
	_t += delta
	var fronte := minf(_t * VELOCITA, RAGGIO)
	_colpisci(fronte)
	_anima(fronte)
	var arrivo := RAGGIO / VELOCITA
	if _t > arrivo + SPEGNIMENTO:
		queue_free()


func _colpisci(fronte : float) -> void:
	for raw in get_tree().get_nodes_in_group("targets"):
		var n := raw as Node3D
		if n == null or _colpiti.has(n) or not Fazioni.colpibile(n, lanciatore):
			continue
		var dal_centro : Vector3 = n.global_position - global_position
		if absf(dal_centro.y) > DISLIVELLO or Vector2(dal_centro.x, dal_centro.z).length() > fronte:
			continue
		if not _sul_suolo(to_local(n.global_position)):
			continue
		_colpiti.append(n)
		n.hit(lanciatore, colpo_per(n.global_position))


# ─── Quello che si vede ─────────────────────────────────────────────────────

func _anima(fronte : float) -> void:
	var arrivo := RAGGIO / VELOCITA
	var vita := clampf(1.0 - (_t - arrivo) / SPEGNIMENTO, 0.0, 1.0)
	_ombra.set_shader_parameter("fronte", _t * VELOCITA)
	_ombra.set_shader_parameter("vita", vita)
	_anima_spuntoni()
	_emetti_faville(fronte)


func _costruisci_suolo() -> void:
	var piano := PlaneMesh.new()
	piano.size = Vector2.ONE * (RAGGIO + 2.0) * 2.0
	_ombra = ShaderMaterial.new()
	_ombra.shader = OMBRA
	_ombra.set_shader_parameter("raggio", RAGGIO)
	_ombra.set_shader_parameter("suolo", _texture_suolo())
	_ombra.set_shader_parameter("mezzo_suolo", (CELLE + 0.5) * CELLA)
	var mi := MeshInstance3D.new()
	mi.name = "Suolo"
	mi.mesh = piano
	mi.material_override = _ombra
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.07
	add_child(mi)


## Spuntoni di roccia che il fronte fa uscire dal terreno, e che tornano giu': neri
## col taglio viola a sinistra, chiari e dorati a destra. Pochi e grossi, spigolosi,
## che dall'isometrica si leggono.
func _costruisci_spuntoni() -> void:
	var cono := CylinderMesh.new()
	cono.top_radius = 0.0
	cono.bottom_radius = 0.34
	cono.height = 1.0
	cono.radial_segments = 4
	cono.rings = 1
	var ombra_spuntoni := Shader.new()
	ombra_spuntoni.code = """
shader_type spatial;
varying float altezza;
varying vec4 taglio;
void vertex() {
	altezza = VERTEX.y + 0.5;
	taglio = INSTANCE_CUSTOM;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.82;
	EMISSION = taglio.rgb * smoothstep(0.35, 1.0, altezza) * 1.4;
}
"""
	var materiale := ShaderMaterial.new()
	materiale.shader = ombra_spuntoni
	_spuntoni = MultiMesh.new()
	_spuntoni.transform_format = MultiMesh.TRANSFORM_3D
	_spuntoni.use_colors = true
	_spuntoni.use_custom_data = true
	_spuntoni.mesh = cono
	_spuntoni.instance_count = SPUNTONI
	var caso := RandomNumberGenerator.new()
	caso.randomize()
	for i in SPUNTONI:
		var angolo := caso.randf_range(0.0, TAU)
		## Piu' fitti lontano, dove la circonferenza e' piu' lunga.
		var r := sqrt(caso.randf_range(0.04, 0.94)) * RAGGIO
		var dove := Vector3(cos(angolo) * r, 0.0, sin(angolo) * r)
		var a_sinistra := dove.x > 0.0
		## Dove l'onda non arriva lo spuntone non esce: `quando` lontanissimo.
		var arriva := _sul_suolo(dove)
		_spuntoni.set_instance_color(i, Color(0.055, 0.03, 0.09) if a_sinistra else Color(0.8, 0.68, 0.42))
		_spuntoni.set_instance_custom_data(i, Color(0.42, 0.14, 0.82) if a_sinistra else Color(0.75, 0.52, 0.16))
		_dati_spuntoni.append({
			"dove": dove,
			"quando": r / VELOCITA if arriva else 1000.0,
			"alto": caso.randf_range(0.7, 1.7) * lerpf(1.1, 0.55, r / RAGGIO),
			"largo": caso.randf_range(0.7, 1.35),
			"giro": caso.randf_range(0.0, TAU),
			## Pendono verso fuori, spinti dall'onda.
			"asse": Vector3(sin(angolo), 0.0, -cos(angolo)),
			"piega": caso.randf_range(0.12, 0.5),
		})
		_spuntoni.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), dove))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Spuntoni"
	mi.multimesh = _spuntoni
	mi.material_override = materiale
	add_child(mi)


func _anima_spuntoni() -> void:
	const SALITA := 0.11
	const RESTA := 0.32
	const DISCESA := 0.42
	for i in SPUNTONI:
		var d : Dictionary = _dati_spuntoni[i]
		var eta : float = _t - d["quando"]
		var h := 0.0
		if eta > 0.0:
			if eta < SALITA:
				h = ease(eta / SALITA, 0.4)
			elif eta < SALITA + RESTA:
				h = 1.0
			else:
				h = 1.0 - clampf((eta - SALITA - RESTA) / DISCESA, 0.0, 1.0)
		if h <= 0.0:
			_spuntoni.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), d["dove"]))
			continue
		var alto : float = d["alto"]
		var b := Basis(d["asse"], d["piega"]) * Basis(Vector3.UP, d["giro"])
		b = b.scaled_local(Vector3(d["largo"], alto, d["largo"]))
		## Sale dal terreno: la base resta sotto, e' la punta a uscire.
		var dove : Vector3 = d["dove"] + b.y * (h - 0.5) + Vector3.DOWN * 0.04
		_spuntoni.set_instance_transform(i, Transform3D(b, dove))


func _costruisci_faville() -> void:
	_faville = Faville.new()
	_faville.name = "Faville"
	add_child(_faville)
	_faville.prepara(FAVILLE)


func _emetti_faville(fronte : float) -> void:
	if fronte >= RAGGIO:
		return
	for _k in 6:
		var angolo := randf_range(0.0, TAU)
		var dove := Vector3(cos(angolo) * fronte, 0.1, sin(angolo) * fronte)
		if not _sul_suolo(dove):
			continue
		var v := Vector3(cos(angolo) * randf_range(0.5, 2.0), randf_range(1.6, 4.2), sin(angolo) * randf_range(0.5, 2.0))
		_faville.emetti(dove, v, randf_range(0.5, 1.05), Color(0.5, 0.2, 0.95) if dove.x > 0.0 else Color(1.0, 0.86, 0.5))
