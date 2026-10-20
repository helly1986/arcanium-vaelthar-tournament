extends Node3D

## Un FUOCO del mini-dungeon (torcia o braciere): una fiamma e la sua luce,
## che tremola.
##
## La fiamma sono poche particelle additive (billboard): costano poco anche sul
## telefono. La luce e' una OmniLight senza ombre: sul renderer Mobile ogni
## oggetto ne riceve al massimo 8, per questo pavimento e muri sono divisi a
## blocchi (costruttore_dungeon.gd). Il tremolio e' un rumore lento
## sull'energia e sulla portata, sfasato da fuoco a fuoco.

var colore := Color(1.0, 0.58, 0.25)
var energia := 2.2
var portata := 8.0
## Grandezza della fiamma: 1 una torcia, ~2 un braciere.
var grandezza := 1.0
var sfasamento := 0.0

var _luce : OmniLight3D
var _rumore := FastNoiseLite.new()
var _t := 0.0


func _ready() -> void:
	add_to_group("fuoco_dungeon")
	_luce = OmniLight3D.new()
	_luce.light_color = colore
	_luce.light_energy = energia
	_luce.omni_range = portata
	_luce.omni_attenuation = 1.4
	_luce.position.y = 0.25 * grandezza
	add_child(_luce)
	_rumore.frequency = 2.5
	_rumore.seed = int(sfasamento * 1000.0)
	add_child(_fiamma())


func _process(delta : float) -> void:
	_t += delta
	var n := _rumore.get_noise_1d(_t * 6.0 + sfasamento * 100.0)
	_luce.light_energy = energia * (0.85 + 0.25 * n)
	_luce.omni_range = portata * (0.95 + 0.06 * n)


func _fiamma() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(10 * grandezza)
	p.lifetime = 0.55
	p.local_coords = true
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 0.5 * grandezza
	m.initial_velocity_max = 0.9 * grandezza
	m.gravity = Vector3(0, 0.6, 0)
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.06 * grandezza
	m.scale_min = 0.6
	m.scale_max = 1.0
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 0.5))
	curva.add_point(Vector2(0.3, 1.0))
	curva.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curva
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.3) * grandezza
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _goccia()
	quad.material = mat
	p.draw_pass_1 = quad
	return p


## Una goccia sfumata 32x32: la forma della singola lingua di fuoco.
static func _goccia() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var dx := (x - 15.5) / 15.5
			var dy := (y - 18.0) / 14.0
			var d := sqrt(dx * dx + dy * dy * (0.6 if dy < 0.0 else 1.0))
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
