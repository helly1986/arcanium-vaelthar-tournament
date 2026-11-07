extends Node3D

## Il teal che si raccoglie sull'arco mentre Ilwen tende, prima del Lascito del
## Bruciante: faville che convergono e una luce che cresce. Il fascio viene da qui, non
## dalla faretra. Vive sull'arma finche' dura la tensione (LucidaTecnica.carica).

const Faville := preload("res://arcanium/systems/lucide/faville.gd")

var _faville
var _luce : OmniLight3D
var _t := 0.0


func _ready() -> void:
	_faville = Faville.new()
	add_child(_faville)
	_faville.prepara(60, 0.12)
	_luce = OmniLight3D.new()
	_luce.light_color = Color(0.25, 1.0, 0.88)
	_luce.omni_range = 4.0
	_luce.light_energy = 0.0
	add_child(_luce)


func _physics_process(delta : float) -> void:
	_t += delta
	_luce.light_energy = minf(_t * 2.2, 2.4)
	var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	## Nascono lontano e corrono verso l'arco, piu' fitte col passare del tempo.
	for _k in int(1 + minf(_t * 2.0, 3.0)):
		var r := randf_range(0.55, 1.0)
		_faville.emetti(dir * r, -dir * r * 2.4 + Vector3.UP * 0.5, 0.4, Color(0.35, 1.0, 0.9))
		dir = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
