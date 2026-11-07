extends Node3D

## ═══════════════════════════════════════
## TERRA RISVEGLIATA — gli spiriti della vanga di Aurin
## ═══════════════════════════════════════
##
## Lucida Tecnica della Vanga del Raccoglitore (idea dell'autore, 2026-11-07): Aurin
## scava nel pavimento e ne tira fuori un'ondata di spiriti negromantici lucenti, che si
## scaraventano sul bersaglio piu' vicino. Addosso a lui rallentano e consumano per 5
## secondi (status_host.gd, spiriti_effect.gd). Se muore per quel danno, Aurin riprende
## l'Arcanium speso e la meta' del danno come vita, e gli spiriti gli tornano addosso.
##
## Il bersaglio si sceglie all'impatto e resta quello: il piu' vicino entro `PORTATA` che
## si possa vedere. Se non c'e', gli spiriti salgono e si perdono. Passano attraverso le
## cose: sono spiriti, ma non si sceglie chi sta dietro un muro.
##
## Il danno totale e' quello dell'arma, che scala con le Marche, per `danno_mult`.
##
## Gli spiriti hanno il colore della CASATA di chi scava, schiarito perche' siano lucenti;
## senza casata, il viola dell'Arcanium.

const Fazioni := preload("res://arcanium/systems/fazioni.gd")
const SoloMondo := preload("res://arcanium/systems/lucide/solo_mondo.gd")
const Scossa := preload("res://arcanium/systems/vfx/scossa.gd")
const Suoni := preload("res://arcanium/systems/vfx/suoni.gd")
const SchiantoATerra := preload("res://arcanium/systems/vfx/schianto_a_terra.gd")
const Faville := preload("res://arcanium/systems/lucide/faville.gd")
const OMBRA_TERRA := preload("res://arcanium/systems/lucide/terra_smossa.gdshader")
const HouseCatalog := preload("res://arcanium/systems/house_catalog.gd")

const PORTATA := 16.0
const DISLIVELLO := 3.0
const MASCHERA_MONDO := 1
const SPIRITI := 12
## L'ondata esce in questo tempo, uno dopo l'altro.
const USCITA := 0.55
const SALITA := 0.3
const VELOCITA := 15.0
const STERZO := 7.0
const ALTEZZA_BERSAGLIO := 1.05
const SCIA := 16
const DURATA_TERRA := 7.5
const VIOLA_ARCANIUM := Color(0.75, 0.3, 1.0)

enum Stato { DENTRO, SALE, VOLA, ADDOSSO, TORNA, VIA, SPENTO }

var lanciatore : Node = null
var potenza : float = 0.0
var costo : float = 0.0

var _bersaglio : Node3D = null
var _morso_dato := false
var _t := 0.0
var _spiriti : Array = []
var _teste : MultiMesh
var _scie : ImmediateMesh
var _faville
var _luce : OmniLight3D
var _terra : ShaderMaterial
var COLORE := VIOLA_ARCANIUM


func _ready() -> void:
	COLORE = _colore_della_casata()
	_bersaglio = _piu_vicino()
	_costruisci()
	SchiantoATerra.al_punto(get_parent(), global_position, Vector3.UP, 0.8)
	Scossa.nel_mondo(global_position, Scossa.PESANTE)
	Suoni.nel_mondo(self, Suoni.VERATH_SPETTRALE)
	for i in SPIRITI:
		var giro := randf_range(0.0, TAU)
		_spiriti.append({
			"stato": Stato.DENTRO,
			"esce": USCITA * float(i) / float(SPIRITI - 1) + randf_range(0.0, 0.05),
			"dove": global_position,
			"v": Vector3.ZERO,
			"giro": giro,
			"quota": randf_range(0.35, 1.75),
			"raggio": randf_range(0.5, 0.95),
			"velocita_giro": randf_range(2.6, 4.4) * (1.0 if i % 2 == 0 else -1.0),
			"scia": PackedVector3Array(),
			"lato": randf_range(0.8, 1.2),
		})


func _colore_della_casata() -> Color:
	var salva := get_node_or_null("/root/SaveManager")
	var casa : String = String(salva.get_house()) if salva != null and salva.has_method("get_house") else ""
	var scheda : Dictionary = HouseCatalog.get_house(casa) if casa != "" else {}
	if not scheda.has("color"):
		return VIOLA_ARCANIUM
	var c := Color(String(scheda["color"]))
	## Lucente: piu' luminoso e piu' saturo della tinta dello stemma, che su un corpo che
	## brilla si perderebbe in un grigio.
	c.s = clampf(c.s * 2.4, 0.4, 0.85)
	c.v = 1.0
	return c


## Il bersaglio piu' vicino che si possa colpire e vedere.
func _piu_vicino() -> Node3D:
	var meglio : Node3D = null
	var dist := PORTATA
	var spazio := get_world_3d().direct_space_state
	var fuori := SoloMondo.esclusi(get_tree(), lanciatore)
	for raw in get_tree().get_nodes_in_group("targets"):
		var n := raw as Node3D
		if n == null or not Fazioni.colpibile(n, lanciatore) or not _vivo(n):
			continue
		var d : float = global_position.distance_to(n.global_position)
		if d >= dist or absf(n.global_position.y - global_position.y) > DISLIVELLO:
			continue
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0,
				n.global_position + Vector3.UP * 1.0, MASCHERA_MONDO, fuori)
		if not spazio.intersect_ray(q).is_empty():
			continue
		meglio = n
		dist = d
	return meglio


func _vivo(n : Node) -> bool:
	if not is_instance_valid(n):
		return false
	var salute = n.get("health_system")
	return salute == null or float(salute.get("current_health")) > 0.0


func _physics_process(delta : float) -> void:
	_t += delta
	var alcuni := false
	var centro := Vector3.ZERO
	var accesi := 0
	for i in SPIRITI:
		var s : Dictionary = _spiriti[i]
		_passo(s, delta)
		if s["stato"] != Stato.SPENTO:
			alcuni = true
		if s["stato"] != Stato.SPENTO and s["stato"] != Stato.DENTRO:
			centro += s["dove"]
			accesi += 1
		_disegna_testa(i, s)
	_disegna_scie()
	if accesi > 0:
		_luce.global_position = centro / float(accesi) + Vector3.UP * 0.4
		_luce.light_energy = lerpf(_luce.light_energy, 1.1, 0.1)
	else:
		_luce.light_energy = lerpf(_luce.light_energy, 0.0, 0.1)
	_terra.set_shader_parameter("luce", clampf(1.0 - (_t - USCITA) / 1.6, 0.0, 1.0))
	_terra.set_shader_parameter("vita", clampf((DURATA_TERRA - _t) / 1.5, 0.0, 1.0))
	if not alcuni and _t > DURATA_TERRA:
		queue_free()


func _passo(s : Dictionary, delta : float) -> void:
	var dove : Vector3 = s["dove"]
	match s["stato"]:
		Stato.DENTRO:
			if _t >= s["esce"]:
				s["stato"] = Stato.SALE
				var g : float = s["giro"]
				s["v"] = Vector3(cos(g) * 1.8, 5.5, sin(g) * 1.8)
				s["nato"] = _t
				_faville.emetti(to_local(dove), s["v"] * 0.3, 0.7, COLORE)
			return
		Stato.SALE:
			s["v"] = s["v"] * (1.0 - 2.2 * delta)
			if _t - s["nato"] >= SALITA:
				s["stato"] = Stato.VOLA if _vivo(_bersaglio) else Stato.VIA
				s["nato"] = _t
		Stato.VOLA:
			if not _vivo(_bersaglio):
				s["stato"] = Stato.VIA
				s["nato"] = _t
			else:
				var punta : Vector3 = _bersaglio.global_position + Vector3.UP * ALTEZZA_BERSAGLIO
				s["v"] = (s["v"] as Vector3).lerp((punta - dove).normalized() * VELOCITA, clampf(STERZO * delta, 0.0, 1.0))
				if dove.distance_to(punta) < 0.9:
					s["stato"] = Stato.ADDOSSO
					_morsica()
		Stato.ADDOSSO:
			if not _vivo(_bersaglio):
				s["stato"] = Stato.VIA
				s["nato"] = _t
			elif not _addosso_ancora():
				s["stato"] = Stato.VIA
				s["nato"] = _t
			else:
				s["giro"] = float(s["giro"]) + float(s["velocita_giro"]) * delta
				var g : float = s["giro"]
				var punto : Vector3 = _bersaglio.global_position + Vector3(cos(g) * s["raggio"], s["quota"], sin(g) * s["raggio"])
				s["v"] = (punto - dove) * 9.0
				if randf() < 0.12:
					_faville.emetti(to_local(dove), Vector3.UP * randf_range(0.5, 1.4), 0.5, COLORE)
		Stato.TORNA:
			if not is_instance_valid(lanciatore):
				s["stato"] = Stato.VIA
				s["nato"] = _t
			else:
				var casa : Vector3 = (lanciatore as Node3D).global_position + Vector3.UP * 1.1
				s["v"] = (s["v"] as Vector3).lerp((casa - dove).normalized() * VELOCITA * 1.2, clampf(STERZO * delta, 0.0, 1.0))
				if dove.distance_to(casa) < 0.6:
					s["stato"] = Stato.SPENTO
					for _k in 3:
						_faville.emetti(to_local(casa), Vector3(randf_range(-1.0, 1.0), 1.5, randf_range(-1.0, 1.0)), 0.6, COLORE)
		Stato.VIA:
			s["v"] = (s["v"] as Vector3).lerp(Vector3.UP * 1.8, clampf(3.0 * delta, 0.0, 1.0))
			if _t - s["nato"] > 0.8:
				s["stato"] = Stato.SPENTO
		Stato.SPENTO:
			return
	dove += s["v"] * delta
	## Non vanno dritti: ondeggiano attorno alla loro rotta.
	if s["stato"] == Stato.VOLA or s["stato"] == Stato.TORNA:
		var di_lato := (s["v"] as Vector3).cross(Vector3.UP).normalized()
		dove += di_lato * sin(_t * 9.0 + float(s["giro"])) * 2.6 * delta
		dove.y += cos(_t * 7.0 + float(s["giro"])) * 1.2 * delta
	s["dove"] = dove
	var scia : PackedVector3Array = s["scia"]
	scia.append(dove)
	if scia.size() > SCIA:
		scia.remove_at(0)
	s["scia"] = scia


## Il primo spirito che arriva porta lo status, e da li' valgono i suoi 5 secondi.
func _morsica() -> void:
	if _morso_dato:
		return
	_morso_dato = true
	var salute = _bersaglio.get("health_system")
	var host = salute.get("status_host") if salute != null else null
	if host == null or not host.has_method("affida_spiriti"):
		return
	var effetto = host.affida_spiriti(potenza, lanciatore, costo)
	if effetto != null and not effetto.ucciso.is_connected(_ha_ucciso):
		effetto.ucciso.connect(_ha_ucciso)


func _addosso_ancora() -> bool:
	var salute = _bersaglio.get("health_system")
	var host = salute.get("status_host") if salute != null else null
	var e = host.get_effect("spiriti") if host != null else null
	return e != null and e.is_active()


## Ha ucciso lui: gli spiriti tornano da chi li ha mandati, col premio.
func _ha_ucciso(_inflitto : float) -> void:
	for s in _spiriti:
		if s["stato"] == Stato.ADDOSSO or s["stato"] == Stato.VOLA:
			s["stato"] = Stato.TORNA
			s["nato"] = _t


# ─── Quello che si vede ─────────────────────────────────────────────────────

func _costruisci() -> void:
	var piano := PlaneMesh.new()
	piano.size = Vector2.ONE * 5.0
	_terra = ShaderMaterial.new()
	_terra.shader = OMBRA_TERRA
	_terra.set_shader_parameter("pallido", Vector3(COLORE.r, COLORE.g, COLORE.b))
	var suolo := MeshInstance3D.new()
	suolo.name = "TerraSmossa"
	suolo.mesh = piano
	suolo.material_override = _terra
	suolo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	suolo.position.y = 0.06
	add_child(suolo)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.5
	var alone := GradientTexture2D.new()
	alone.fill = GradientTexture2D.FILL_RADIAL
	alone.fill_from = Vector2(0.5, 0.5)
	alone.fill_to = Vector2(1.0, 0.5)
	var scala := Gradient.new()
	scala.offsets = PackedFloat32Array([0.0, 0.22, 0.5, 1.0])
	## Bianco al centro: il colore lo mette l'istanza, moltiplicando.
	scala.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.8), Color(0.85, 0.85, 0.85, 0.22), Color(0.6, 0.6, 0.6, 0.0)])
	alone.gradient = scala
	var m_teste := StandardMaterial3D.new()
	m_teste.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_teste.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_teste.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m_teste.vertex_color_use_as_albedo = true
	m_teste.vertex_color_is_srgb = true
	m_teste.albedo_texture = alone
	_teste = MultiMesh.new()
	_teste.transform_format = MultiMesh.TRANSFORM_3D
	_teste.use_colors = true
	_teste.mesh = quad
	_teste.instance_count = SPIRITI
	var mm := MultiMeshInstance3D.new()
	mm.name = "Teste"
	mm.multimesh = _teste
	mm.material_override = m_teste
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Le teste e le scie sono in coordinate del mondo: gli spiriti escono da qui ma
	## corrono dove vuole il bersaglio.
	mm.top_level = true
	add_child(mm)
	mm.global_transform = Transform3D.IDENTITY

	_scie = ImmediateMesh.new()
	var m_scie := StandardMaterial3D.new()
	m_scie.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_scie.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_scie.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_scie.vertex_color_use_as_albedo = true
	m_scie.vertex_color_is_srgb = true
	var mi_scie := MeshInstance3D.new()
	mi_scie.name = "Scie"
	mi_scie.mesh = _scie
	mi_scie.material_override = m_scie
	mi_scie.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi_scie.top_level = true
	mi_scie.extra_cull_margin = 64.0
	add_child(mi_scie)
	mi_scie.global_transform = Transform3D.IDENTITY

	_faville = Faville.new()
	_faville.name = "Faville"
	add_child(_faville)
	_faville.prepara(120, 0.14)
	_luce = OmniLight3D.new()
	_luce.name = "Luce"
	_luce.light_color = COLORE
	_luce.omni_range = 6.0
	_luce.light_energy = 0.0
	_luce.top_level = true
	add_child(_luce)


func _disegna_testa(i : int, s : Dictionary) -> void:
	var acceso : bool = s["stato"] != Stato.SPENTO and s["stato"] != Stato.DENTRO
	if not acceso:
		_teste.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		return
	var battito := 0.85 + 0.15 * sin(_t * 11.0 + float(s["giro"]))
	var scala : float = float(s["lato"]) * battito
	if s["stato"] == Stato.VIA:
		scala *= clampf(1.0 - (_t - float(s["nato"])) / 0.8, 0.0, 1.0)
	_teste.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scala), s["dove"]))
	_teste.set_instance_color(i, COLORE)


## Una striscia per spirito, che si assottiglia e si spegne verso la coda: piena sull'asse
## e trasparente ai bordi, cosi' e' una scia e non una lastra. Di piatto rispetto al suolo:
## la camera guarda dall'alto.
func _disegna_scie() -> void:
	_scie.clear_surfaces()
	var qualcosa := false
	for s in _spiriti:
		var scia : PackedVector3Array = s["scia"]
		if s["stato"] == Stato.SPENTO or scia.size() < 2:
			continue
		if not qualcosa:
			_scie.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			qualcosa = true
		var svanire : float = 1.0
		if s["stato"] == Stato.VIA:
			svanire = clampf(1.0 - (_t - float(s["nato"])) / 0.8, 0.0, 1.0)
		for k in range(1, scia.size()):
			var a : Vector3 = scia[k - 1]
			var b : Vector3 = scia[k]
			var fianco := (b - a).cross(Vector3.UP)
			fianco = fianco.normalized() if fianco.length_squared() > 0.000001 else Vector3.RIGHT
			var qa := float(k - 1) / float(scia.size())
			var qb := float(k) / float(scia.size())
			var la := fianco * 0.26 * qa
			var lb := fianco * 0.26 * qb
			var ca := Color(COLORE, 0.7 * qa * qa * svanire)
			var cb := Color(COLORE, 0.7 * qb * qb * svanire)
			var fa := Color(COLORE, 0.0)
			for lato in [-1.0, 1.0]:
				_vertice(a, ca)
				_vertice(a + la * lato, fa)
				_vertice(b + lb * lato, fa)
				_vertice(a, ca)
				_vertice(b + lb * lato, fa)
				_vertice(b, cb)
	if qualcosa:
		_scie.surface_end()


func _vertice(p : Vector3, c : Color) -> void:
	_scie.surface_set_color(c)
	_scie.surface_add_vertex(p)
