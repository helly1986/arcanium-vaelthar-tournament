extends Node3D

## ═══════════════════════════════════════
## L'INFUSIONE CHE SI VEDE SULL'ARMA
## ═══════════════════════════════════════
##
## Baluardo del Freddo, Comando del Tuono, Infusione della Fucina: stessa meccanica,
## aspetto diverso. Una pellicola sulle mesh dell'arma in mano, faville che ne escono
## lungo la lama, e per il tuono gli archi che le corrono attorno. Lo crea e lo toglie
## LucidaTecnicaCaster; le faville e gli archi stanno in coordinate del mondo, cosi'
## restano indietro quando l'arma si muove.

const Faville := preload("res://arcanium/systems/lucide/faville.gd")
const OMBRA := preload("res://arcanium/systems/lucide/infusione_lama.gdshader")

## "ghiaccio", "tuono" o "fiamma".
var aspetto : String = "ghiaccio"
var colore : Color = Color.WHITE
var nucleo : Color = Color.WHITE
var arma : Node3D = null

var _pellicola : ShaderMaterial
var _mesh : Array[MeshInstance3D] = []
var _lunghezza := 0.8
var _faville
var _luce : OmniLight3D
var _archi : ImmediateMesh
var _ai_archi := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_pellicola = ShaderMaterial.new()
	_pellicola.shader = OMBRA
	_pellicola.set_shader_parameter("colore", Vector3(colore.r, colore.g, colore.b))
	_pellicola.set_shader_parameter("nucleo", Vector3(nucleo.r, nucleo.g, nucleo.b))
	match aspetto:
		"tuono":
			_pellicola.set_shader_parameter("velocita", 3.0)
			_pellicola.set_shader_parameter("scatti", 1.0)
			_pellicola.set_shader_parameter("forza", 0.9)
		"fiamma":
			_pellicola.set_shader_parameter("velocita", 1.8)
			_pellicola.set_shader_parameter("forza", 1.0)
		_:
			_pellicola.set_shader_parameter("velocita", 0.15)
			_pellicola.set_shader_parameter("forza", 0.95)
	_faville = Faville.new()
	_faville.name = "Faville"
	add_child(_faville)
	_faville.prepara(90, 0.11)
	_luce = OmniLight3D.new()
	_luce.name = "Luce"
	_luce.light_color = colore
	_luce.omni_range = 3.2
	_luce.light_energy = 0.9
	add_child(_luce)
	if aspetto == "tuono":
		_archi = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		var mi := MeshInstance3D.new()
		mi.name = "Archi"
		mi.mesh = _archi
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16.0
		add_child(mi)
	rivesti()


## Rimette la pellicola sulle mesh visibili dell'arma: il modello puo' essere cambiato.
func rivesti() -> void:
	_togli_pellicola()
	if not is_instance_valid(arma):
		return
	_lunghezza = 0.25
	for n in arma.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		mi.material_overlay = _pellicola
		_mesh.append(mi)
		var verso_arma := arma.global_transform.affine_inverse() * mi.global_transform
		var box : AABB = verso_arma * mi.get_aabb()
		_lunghezza = maxf(_lunghezza, box.end.y)


func _togli_pellicola() -> void:
	for mi in _mesh:
		if is_instance_valid(mi):
			mi.material_overlay = null
	_mesh.clear()


func spegni() -> void:
	_togli_pellicola()
	queue_free()


func _exit_tree() -> void:
	_togli_pellicola()


func _physics_process(delta : float) -> void:
	if not is_instance_valid(arma):
		return
	var si_vede := arma.is_visible_in_tree()
	_luce.visible = si_vede
	if not si_vede:
		if _archi != null:
			_archi.clear_surfaces()
		return
	_luce.global_position = arma.to_global(Vector3(0.0, _lunghezza * 0.6, 0.0))
	var quante := 2
	if aspetto == "ghiaccio":
		quante = 1
	for _k in quante:
		_emetti()
	if _archi != null:
		_ai_archi -= delta
		if _ai_archi <= 0.0:
			_ai_archi = randf_range(0.05, 0.12)
			_scarica()


func _sulla_lama() -> Vector3:
	return arma.to_global(Vector3(randf_range(-0.03, 0.03), randf_range(0.12, 1.0) * _lunghezza, randf_range(-0.03, 0.03)))


func _emetti() -> void:
	var dove := _sulla_lama()
	match aspetto:
		"fiamma":
			_faville.emetti(dove, Vector3(randf_range(-0.3, 0.3), randf_range(1.2, 2.6), randf_range(-0.3, 0.3)),
					randf_range(0.2, 0.5), colore if randf() < 0.65 else nucleo)
		"tuono":
			_faville.emetti(dove, Vector3(randf_range(-1.8, 1.8), randf_range(-0.6, 1.2), randf_range(-1.8, 1.8)),
					randf_range(0.08, 0.2), nucleo)
		_:
			## Il ghiaccio non sale: la brina cade.
			_faville.emetti(dove, Vector3(randf_range(-0.15, 0.15), randf_range(-0.7, -0.2), randf_range(-0.15, 0.15)),
					randf_range(0.5, 1.0), colore if randf() < 0.5 else nucleo)


## Due o tre archi spezzati fra punti della lama, ridisegnati a scatti.
func _scarica() -> void:
	_archi.clear_surfaces()
	_archi.surface_begin(Mesh.PRIMITIVE_LINES)
	for _a in randi_range(1, 3):
		var da := _sulla_lama()
		var a := _sulla_lama() + Vector3(randf_range(-0.28, 0.28), randf_range(-0.2, 0.2), randf_range(-0.28, 0.28))
		var prima := da
		var passi := 5
		for p in range(1, passi + 1):
			var ora := da.lerp(a, float(p) / float(passi))
			if p < passi:
				ora += Vector3(randf_range(-0.07, 0.07), randf_range(-0.07, 0.07), randf_range(-0.07, 0.07))
			_archi.surface_set_color(nucleo)
			_archi.surface_add_vertex(prima)
			_archi.surface_set_color(nucleo)
			_archi.surface_add_vertex(ora)
			prima = ora
	_archi.surface_end()
