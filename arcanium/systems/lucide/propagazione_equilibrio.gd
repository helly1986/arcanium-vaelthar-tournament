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
##   oscura  — EROSIONE, l'Erosione dell'Eco che scatta subito.
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
const Scossa := preload("res://arcanium/systems/vfx/scossa.gd")
const Suoni := preload("res://arcanium/systems/vfx/suoni.gd")
const SchiantoATerra := preload("res://arcanium/systems/vfx/schianto_a_terra.gd")
const OMBRA := preload("res://arcanium/systems/lucide/onda_equilibrio.gdshader")

const RAGGIO := 7.5
const VELOCITA := 13.0
## Quanto dura il suolo acceso dopo che il fronte e' arrivato in fondo.
const SPEGNIMENTO := 1.1
const DISLIVELLO := 2.2
const SPUNTONI := 72
const FAVILLE := 150

const FRATTURA_MULT := 1.35
const FRATTURA_DURATA := 15.0
## L'Erosione si accumula colpo su colpo (40 su 100): quest'onda la fa scattare.
const EROSIONE_ACCUMULI := 3
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
var _faville : MultiMesh
var _dati_faville : Array = []
var _prossima_favilla := 0
## 1 per le celle su cui l'onda arriva.
var _suolo : PackedByteArray = PackedByteArray()


class Colpo extends Resource:
	var power : float = 0.0
	var damage_type : String = "SACRO"
	var inflicts_fracture : bool = false
	var fracture_multiplier : float = 1.0
	var fracture_duration : float = 0.0
	var builds_echo : bool = false
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
	for j in lato:
		for i in lato:
			var mondo := to_global(Vector3((i - CELLE) * CELLA, 0.0, (j - CELLE) * CELLA))
			var q := PhysicsRayQueryParameters3D.create(mondo + Vector3.UP * 1.2, mondo + Vector3.DOWN * 1.2, MASCHERA_MONDO)
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
		c.builds_echo = true
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
	_anima(fronte, delta)
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
		var c := colpo_per(n.global_position)
		n.hit(lanciatore, c)
		if c.builds_echo:
			_fai_scattare_erosione(n)


## Un accumulo lo mette il colpo stesso (`builds_echo`), gli altri si aggiungono qui.
func _fai_scattare_erosione(n : Node) -> void:
	var salute = n.get("health_system")
	var host = salute.get("status_host") if salute != null else null
	if host == null or not host.has_method("build_echo"):
		return
	for _k in EROSIONE_ACCUMULI - 1:
		host.build_echo()


# ─── Quello che si vede ─────────────────────────────────────────────────────

func _anima(fronte : float, delta : float) -> void:
	var arrivo := RAGGIO / VELOCITA
	var vita := clampf(1.0 - (_t - arrivo) / SPEGNIMENTO, 0.0, 1.0)
	_ombra.set_shader_parameter("fronte", _t * VELOCITA)
	_ombra.set_shader_parameter("vita", vita)
	_anima_spuntoni()
	_emetti_faville(fronte)
	_anima_faville(delta)


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
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.2
	var alone := GradientTexture2D.new()
	alone.fill = GradientTexture2D.FILL_RADIAL
	alone.fill_from = Vector2(0.5, 0.5)
	alone.fill_to = Vector2(1.0, 0.5)
	var scala := Gradient.new()
	scala.set_color(0, Color.WHITE)
	scala.set_color(1, Color(1, 1, 1, 0))
	alone.gradient = scala
	var materiale := StandardMaterial3D.new()
	materiale.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materiale.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materiale.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	materiale.vertex_color_use_as_albedo = true
	materiale.albedo_texture = alone
	materiale.no_depth_test = false
	_faville = MultiMesh.new()
	_faville.transform_format = MultiMesh.TRANSFORM_3D
	_faville.use_colors = true
	_faville.mesh = quad
	_faville.instance_count = FAVILLE
	for i in FAVILLE:
		_dati_faville.append({"vita": 0.0, "dura": 1.0, "dove": Vector3.ZERO, "v": Vector3.ZERO, "colore": Color.WHITE})
		_faville.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Faville"
	mi.multimesh = _faville
	mi.material_override = materiale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _emetti_faville(fronte : float) -> void:
	if fronte >= RAGGIO:
		return
	for _k in 6:
		var angolo := randf_range(0.0, TAU)
		var dove := Vector3(cos(angolo) * fronte, 0.1, sin(angolo) * fronte)
		if not _sul_suolo(dove):
			continue
		var d : Dictionary = _dati_faville[_prossima_favilla]
		_prossima_favilla = (_prossima_favilla + 1) % FAVILLE
		var a_sinistra := dove.x > 0.0
		d["dove"] = dove
		d["v"] = Vector3(cos(angolo) * randf_range(0.5, 2.0), randf_range(1.6, 4.2), sin(angolo) * randf_range(0.5, 2.0))
		d["dura"] = randf_range(0.5, 1.05)
		d["vita"] = d["dura"]
		d["colore"] = Color(0.5, 0.2, 0.95) if a_sinistra else Color(1.0, 0.86, 0.5)


func _anima_faville(delta : float) -> void:
	for i in FAVILLE:
		var d : Dictionary = _dati_faville[i]
		var vita : float = d["vita"]
		if vita <= 0.0:
			continue
		vita -= delta
		d["vita"] = vita
		if vita <= 0.0:
			_faville.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		d["v"] = d["v"] * (1.0 - 1.4 * delta) + Vector3.DOWN * 1.1 * delta
		d["dove"] = d["dove"] + d["v"] * delta
		var quota : float = vita / d["dura"]
		_faville.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * lerpf(0.4, 1.1, quota)), d["dove"]))
		var c : Color = d["colore"]
		c.a = quota
		_faville.set_instance_color(i, c)
