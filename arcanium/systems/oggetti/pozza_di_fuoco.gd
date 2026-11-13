extends Node3D

## LA POZZA DI FUOCO dell'ampolla infiammabile (2026-11-13).
##
## Nasce dove l'ampolla si rompe (ampolla_lanciata.gd). Lo SCOPPIO colpisce subito chi sta
## vicino (danno di fuoco, Bruciatura, un po' di equilibrio); poi il liquido resta a
## terra e brucia per `DURATA` secondi: chi ci sta dentro accumula Bruciatura a ogni tick,
## senza colpi (come il bruciato di Ilwen, lascito_bruciante.gd). Il fuoco e' rosso, non
## spirituale.
##
## Il fuoco amico e' spento (Fazioni.colpibile): la pozza non brucia chi l'ha lanciata
## ne' i suoi.

const Fazioni := preload("res://arcanium/systems/fazioni.gd")
const Faville := preload("res://arcanium/systems/lucide/faville.gd")
const Scossa := preload("res://arcanium/systems/vfx/scossa.gd")
const OMBRA := preload("res://arcanium/systems/oggetti/pozza_fuoco.gdshader")

const RAGGIO := 2.0
const DURATA := 6.0
const SPEGNIMENTO := 1.2
const TICK := 0.25
## Lo scoppio: chi e' entro questo raggio prende il colpo.
const RAGGIO_SCOPPIO := 2.4
const DANNO_SCOPPIO := 22.0
const BRUCIATURA_SCOPPIO := 45.0
const POISE_SCOPPIO := 8.0
## Stando dentro: 48 al secondo, la Bruciatura scatta in circa due secondi.
const BRUCIATURA_TICK := 12.0
const MASCHERA_MONDO := 1

const SUONO_ROTTURA := "res://audio/SoundFX/clack/clack_3.wav"
const SUONO_SCHIZZO := "res://audio/SoundFX/slosh/slosh_2.wav"
const SUONO_FUOCO := "res://audio/SoundFX/fire/fire_01_loop.wav"

var lanciatore : Node = null

var _t := 0.0
var _al_tick := 0.0
var _disco : ShaderMaterial
var _luce : OmniLight3D
var _fiamme : GPUParticles3D
var _fumo : GPUParticles3D
var _faville
var _crepitio : AudioStreamPlayer3D


class Colpo extends Resource:
	var power : float = 0.0
	var damage_type : String = "FUOCO"
	var burn_buildup : float = 0.0
	var burn_spirituale : bool = false
	var poise_damage : float = 0.0
	var scossa : float = 0.02


func _ready() -> void:
	_a_terra()
	_costruisci()
	_scoppio()


## La pozza sta sul pavimento sotto il punto di rottura: l'ampolla puo' rompersi contro
## un nemico o un muro, a mezz'aria.
func _a_terra() -> void:
	var spazio := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3,
			global_position + Vector3.DOWN * 4.0, MASCHERA_MONDO)
	var colpo := spazio.intersect_ray(q)
	if not colpo.is_empty():
		global_position = colpo["position"]


func _physics_process(delta : float) -> void:
	_t += delta
	var vita := clampf((DURATA - _t) / SPEGNIMENTO, 0.0, 1.0)
	_disco.set_shader_parameter("vita", vita)
	_disco.set_shader_parameter("fiammata", clampf(1.0 - _t / 0.35, 0.0, 1.0))
	_luce.light_energy = (2.6 + 3.0 * clampf(1.0 - _t / 0.4, 0.0, 1.0)) * vita * (0.82 + 0.18 * sin(_t * 19.0) * sin(_t * 7.3))
	_fiamme.amount_ratio = vita
	if _crepitio != null:
		_crepitio.volume_db = linear_to_db(maxf(vita, 0.001)) - 4.0
	if vita > 0.0 and randf() < 0.6:
		var giro := randf_range(0.0, TAU)
		var d := sqrt(randf()) * RAGGIO * 0.8
		_faville.emetti(Vector3(cos(giro) * d, 0.15, sin(giro) * d),
				Vector3(randf_range(-0.4, 0.4), randf_range(1.6, 3.2), randf_range(-0.4, 0.4)),
				randf_range(0.6, 1.2), Color(1.0, randf_range(0.35, 0.6), 0.1))
	if _t < DURATA:
		_al_tick -= delta
		if _al_tick <= 0.0:
			_al_tick += TICK
			_scotta()
	elif _t > DURATA + 1.6:
		queue_free()


func _bersagli() -> Array:
	var fuori : Array = []
	for raw in get_tree().get_nodes_in_group("targets"):
		var n := raw as Node3D
		if n != null and Fazioni.colpibile(n, lanciatore):
			fuori.append(n)
	return fuori


func _scoppio() -> void:
	for n in _bersagli():
		var d : Vector3 = n.global_position - global_position
		if Vector2(d.x, d.z).length() > RAGGIO_SCOPPIO or absf(d.y) > 2.0:
			continue
		var c := Colpo.new()
		c.power = DANNO_SCOPPIO
		c.burn_buildup = BRUCIATURA_SCOPPIO
		c.poise_damage = POISE_SCOPPIO
		n.hit(lanciatore, c)
	Scossa.nel_mondo(global_position, Scossa.MEDIO)
	_suono(SUONO_ROTTURA, 2.0)
	_suono(SUONO_SCHIZZO, 0.0)
	_crepitio = _suono(SUONO_FUOCO, -4.0)
	add_child(_vampata())
	add_child(_schegge())
	for _k in 26:
		var giro := randf_range(0.0, TAU)
		_faville.emetti(Vector3(0, 0.2, 0), Vector3(cos(giro) * randf_range(1.0, 4.0), randf_range(2.0, 5.0),
				sin(giro) * randf_range(1.0, 4.0)), randf_range(0.5, 1.1), Color(1.0, 0.7, 0.25))


## Chi sta nella pozza accumula Bruciatura: non e' un colpo, non lo fa sobbalzare.
func _scotta() -> void:
	for n in _bersagli():
		var d : Vector3 = n.global_position - global_position
		if Vector2(d.x, d.z).length() > RAGGIO * 0.85 or absf(d.y) > 1.0:
			continue
		var salute = n.get("health_system")
		var host = salute.get("status_host") if salute != null else null
		if host != null and host.has_method("build_burn"):
			host.build_burn(BRUCIATURA_TICK, false)


# ─── Quello che si vede ─────────────────────────────────────────────────────

func _costruisci() -> void:
	var piano := PlaneMesh.new()
	piano.size = Vector2(RAGGIO * 2.0, RAGGIO * 2.0)
	_disco = ShaderMaterial.new()
	_disco.shader = OMBRA
	_disco.set_shader_parameter("raggio", RAGGIO)
	_disco.set_shader_parameter("seme", randf() * 50.0)
	var mi := MeshInstance3D.new()
	mi.name = "Pozza"
	mi.mesh = piano
	mi.material_override = _disco
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.04
	mi.rotation.y = randf() * TAU
	add_child(mi)
	_fiamme = _lingue()
	add_child(_fiamme)
	_fumo = _fumo_nero()
	add_child(_fumo)
	_faville = Faville.new()
	_faville.name = "Faville"
	add_child(_faville)
	_faville.prepara(120, 0.07)
	_luce = OmniLight3D.new()
	_luce.name = "Luce"
	_luce.light_color = Color(1.0, 0.5, 0.18)
	_luce.omni_range = 7.0
	_luce.omni_attenuation = 1.3
	_luce.position.y = 0.8
	add_child(_luce)


## Le lingue di fuoco sul disco: billboard additivi a goccia, alti e stretti, che salgono
## e si stringono. Tante piccole fiamme su tutta la pozza, non un falo' al centro.
func _lingue() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Fiamme"
	p.amount = 70
	p.lifetime = 0.8
	p.randomness = 0.5
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	## Una sfera schiacciata: le fiamme nascono su TUTTA la macchia, non sul bordo.
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = RAGGIO * 0.78
	m.emission_shape_scale = Vector3(1.0, 0.04, 1.0)
	m.lifetime_randomness = 0.45
	m.direction = Vector3.UP
	m.spread = 8.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.5
	m.gravity = Vector3(0, 1.2, 0)
	m.scale_min = 0.45
	m.scale_max = 1.7
	m.scale_curve = _curva([Vector2(0.0, 0.3), Vector2(0.25, 1.0), Vector2(1.0, 0.0)])
	m.color_ramp = _rampa([[0.0, Color(1.0, 0.9, 0.55, 1.0)], [0.35, Color(1.0, 0.5, 0.12, 0.9)], [1.0, Color(0.6, 0.08, 0.02, 0.0)]])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.turbulence_noise_scale = 2.0
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.38, 0.75)
	quad.material = _materiale_goccia(BaseMaterial3D.BLEND_MODE_ADD)
	p.draw_pass_1 = quad
	return p


## Un filo di fumo scuro sopra le fiamme: e' quello che da' volume da lontano.
func _fumo_nero() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Fumo"
	p.amount = 18
	p.lifetime = 2.2
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = RAGGIO * 0.5
	m.direction = Vector3.UP
	m.spread = 15.0
	m.initial_velocity_min = 0.8
	m.initial_velocity_max = 1.4
	m.gravity = Vector3(0, 0.3, 0)
	m.scale_min = 1.0
	m.scale_max = 2.0
	m.scale_curve = _curva([Vector2(0.0, 0.4), Vector2(1.0, 1.0)])
	m.color_ramp = _rampa([[0.0, Color(0.08, 0.06, 0.05, 0.0)], [0.25, Color(0.1, 0.08, 0.06, 0.35)], [1.0, Color(0.15, 0.13, 0.12, 0.0)]])
	p.process_material = m
	p.position.y = 0.9
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	quad.material = _materiale_goccia(BaseMaterial3D.BLEND_MODE_MIX)
	p.draw_pass_1 = quad
	return p


## La vampata dello scoppio: una palla di fuoco che si allarga e sale, una volta sola.
func _vampata() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Vampata"
	p.amount = 40
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.95
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.25
	m.direction = Vector3.UP
	m.spread = 70.0
	m.initial_velocity_min = 2.5
	m.initial_velocity_max = 5.0
	m.damping_min = 4.0
	m.damping_max = 6.0
	m.gravity = Vector3(0, 2.0, 0)
	m.scale_min = 1.2
	m.scale_max = 2.2
	m.scale_curve = _curva([Vector2(0.0, 0.5), Vector2(0.3, 1.0), Vector2(1.0, 0.2)])
	m.color_ramp = _rampa([[0.0, Color(1.0, 0.95, 0.7, 1.0)], [0.4, Color(1.0, 0.45, 0.1, 0.85)], [1.0, Color(0.3, 0.05, 0.02, 0.0)]])
	p.process_material = m
	p.position.y = 0.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = _materiale_goccia(BaseMaterial3D.BLEND_MODE_ADD)
	p.draw_pass_1 = quad
	p.emitting = true
	return p


## I cocci di vetro: pochi frammenti chiari che schizzano e ricadono.
func _schegge() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Schegge"
	p.amount = 14
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 80.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 4.5
	m.gravity = Vector3(0, -12.0, 0)
	m.angular_velocity_min = -720.0
	m.angular_velocity_max = 720.0
	m.scale_min = 0.5
	m.scale_max = 1.0
	m.color = Color(0.75, 0.85, 0.8, 0.9)
	p.process_material = m
	p.position.y = 0.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = true
	return p


func _materiale_goccia(miscela : int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = miscela
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _goccia()
	mat.disable_receive_shadows = true
	return mat


static var _goccia_cache : Texture2D

## Una goccia morbida e un po' sfrangiata (la fiamma del fuoco del dungeon, con un rumore
## sul bordo perche' non sembri un cerchio stampato).
static func _goccia() -> Texture2D:
	if _goccia_cache != null:
		return _goccia_cache
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var rumore := FastNoiseLite.new()
	rumore.frequency = 0.12
	for y in 48:
		for x in 48:
			var dx := (x - 23.5) / 23.5
			var dy := (y - 27.0) / 21.0
			var d := sqrt(dx * dx + dy * dy * (0.55 if dy < 0.0 else 1.0))
			d += rumore.get_noise_2d(x, y) * 0.25
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_goccia_cache = ImageTexture.create_from_image(img)
	return _goccia_cache


func _curva(punti : Array) -> CurveTexture:
	var c := Curve.new()
	for pt in punti:
		c.add_point(pt)
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


func _rampa(tappe : Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(tappe.map(func(t): return t[0]))
	g.colors = PackedColorArray(tappe.map(func(t): return t[1]))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _suono(percorso : String, volume_db : float) -> AudioStreamPlayer3D:
	var s := load(percorso) as AudioStream
	if s == null:
		return null
	var a := AudioStreamPlayer3D.new()
	a.stream = s
	a.bus = "SFX"
	a.volume_db = volume_db
	a.pitch_scale = randf_range(0.92, 1.08)
	add_child(a)
	a.play()
	return a
