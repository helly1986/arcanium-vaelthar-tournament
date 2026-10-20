extends Node3D

## Il colpo che una bocca da muro spara verso la piastra: palla di fuoco o
## dardo. Va dritto; colpisce il primo corpo con la vita che incontra (anche
## un nemico: attirarli sulle piastre e' una tattica) e si spegne contro muri e
## arredo. Il veleno lascia un danno nel tempo.

const Colpo := preload("res://arcanium/levels/dungeon/colpo_trappola.gd")
const Fuoco := preload("res://arcanium/levels/dungeon/fuoco_dungeon.gd")

var direzione := Vector3.FORWARD
var velocita := 10.0
var colpo : RefCounted
## Veleno: danno al secondo e durata, dopo il colpo.
var veleno_al_secondo := 0.0
var veleno_durata := 0.0
var colore := Color(1, 0.5, 0.2)
## "palla" o "dardo".
var forma := "dardo"
var autore : Node

const RAGGIO := 0.3
const VITA := 2.5

var _t := 0.0
var _escludi : Array[RID] = []


func _ready() -> void:
	look_at(global_position + direzione, Vector3.UP)
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colore
	mat.emission_enabled = true
	mat.emission = colore
	mat.emission_energy_multiplier = 3.0
	if forma == "palla":
		var s := SphereMesh.new()
		s.radius = 0.28
		s.height = 0.56
		mi.mesh = s
		var f := Fuoco.new()
		f.colore = colore
		f.energia = 2.5
		f.portata = 6.0
		f.grandezza = 0.7
		add_child(f)
	else:
		var b := BoxMesh.new()
		b.size = Vector3(0.05, 0.05, 0.55)
		mi.mesh = b
		var luce := OmniLight3D.new()
		luce.light_color = colore
		luce.light_energy = 1.2
		luce.omni_range = 2.5
		add_child(luce)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(delta : float) -> void:
	_t += delta
	if _t > VITA:
		queue_free()
		return
	var passo := direzione * velocita * delta
	var spazio := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sfera := SphereShape3D.new()
	sfera.radius = RAGGIO
	q.shape = sfera
	q.transform = Transform3D(Basis(), global_position + passo)
	q.collision_mask = 1 | 2 | 4
	q.exclude = _escludi
	for r in spazio.intersect_shape(q, 8):
		var corpo : Object = r["collider"]
		if corpo is Node and (corpo.get("health_system") != null):
			colpo.colpisci(corpo, autore)
			if veleno_al_secondo > 0.0:
				_avvelena(corpo)
			queue_free()
			return
		if corpo is StaticBody3D:
			queue_free()
			return
	global_position += passo


func _avvelena(corpo : Node) -> void:
	var hs = corpo.get("health_system")
	if hs == null or not hs.has_method("drain"):
		return
	var t := Timer.new()
	t.wait_time = 1.0
	var restano := [int(veleno_durata)]
	var al_s := veleno_al_secondo
	t.timeout.connect(func():
		if not is_instance_valid(hs) or restano[0] <= 0:
			t.queue_free()
			return
		hs.drain(al_s, "VELENO")
		restano[0] -= 1)
	corpo.add_child(t)
	t.start()
