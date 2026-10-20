extends Node3D

## Una PORTA del mini-dungeon: chiude una stanza finche' qualcuno non le arriva
## vicino, poi sprofonda nel pavimento.
##
## Finche' e' chiusa blocca il passo (collisione) e la vista: la guida
## (guida_dungeon.gd) ne conosce gli attraversamenti, e chi sta dentro non
## vede chi sta fuori. Si apre da sola quando il giocatore le arriva a
## `DISTANZA_APERTURA`; i nemici non la aprono (restano nella loro stanza).

const Misura := preload("res://arcanium/levels/dungeon/misura_pezzo.gd")

## Il modello del battente; senza, una lastra scura.
var scena : PackedScene
var larghezza : float = 4.0
var altezza : float = 3.0
var guida : Node
## Gli attraversamenti che chiude: coppie [cella dentro, cella fuori].
var attraversamenti : Array = []

const DISTANZA_APERTURA := 3.0
const DURATA_APERTURA := 0.9
const SPESSORE := 0.35

var aperta := false
var _battente : Node3D
var _corpo : StaticBody3D


func _ready() -> void:
	add_to_group("porta_dungeon")
	_battente = Node3D.new()
	add_child(_battente)
	if scena != null:
		var m : Node3D = scena.instantiate()
		_battente.add_child(m)
		var box := Misura.ingombro(m)
		if box.size.x > 0.0 and box.size.y > 0.0:
			m.scale = Vector3(larghezza / box.size.x, altezza / box.size.y, SPESSORE / maxf(box.size.z, 0.01))
			m.position = -Vector3(box.get_center().x * m.scale.x, box.position.y * m.scale.y, box.get_center().z * m.scale.z)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(larghezza, altezza, SPESSORE)
		mi.mesh = bm
		mi.position.y = altezza * 0.5
		_battente.add_child(mi)
	_corpo = StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(larghezza, altezza, SPESSORE)
	forma.shape = b
	forma.position.y = altezza * 0.5
	_corpo.add_child(forma)
	add_child(_corpo)
	_blocca(true)


func _physics_process(_delta : float) -> void:
	if aperta:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D and p.has_method("interact"):
			var d := Vector2((p as Node3D).global_position.x - global_position.x, (p as Node3D).global_position.z - global_position.z)
			if d.length() < DISTANZA_APERTURA:
				apri()
				return


func apri() -> void:
	if aperta:
		return
	aperta = true
	_blocca(false)
	_corpo.queue_free()
	var tw := create_tween()
	tw.tween_property(_battente, "position:y", -altezza - 0.2, DURATA_APERTURA).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_battente.hide)


func _blocca(si : bool) -> void:
	if guida == null:
		return
	for coppia in attraversamenti:
		guida.blocca(coppia[0], coppia[1], si)
