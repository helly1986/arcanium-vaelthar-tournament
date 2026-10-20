extends StaticBody3D

## Un FORZIERE del mini-dungeon, normale o raro.
##
## Si apre con il tasto d'interazione (il giocatore lo trova col suo sensore:
## gruppo `interactable` e metodo `activate`). Aperto, manda `aperto(raro)`:
## cosa contiene lo decide la Fase 4 del piano (banco e oggetti); qui si
## vede solo che si e' aperto.

const Misura := preload("res://arcanium/levels/dungeon/misura_pezzo.gd")

signal aperto(raro : bool)

var scena : PackedScene
var raro := false
## L'animazione d'apertura, se il modello ce l'ha.
const ANIM_APERTURA := "Apri"
## Lato maggiore del forziere in pianta, in metri.
const LATO := 1.2

var _modello : Node3D
var _luce : OmniLight3D
var aperto_gia := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("forziere_dungeon")
	collision_layer = 1 | 8
	_modello = Node3D.new()
	add_child(_modello)
	var box := AABB(Vector3(-0.6, 0, -0.4), Vector3(1.2, 0.8, 0.8))
	if scena != null:
		var m : Node3D = scena.instantiate()
		_modello.add_child(m)
		var b := Misura.ingombro(m)
		if b.size.x > 0.0:
			var s := LATO / maxf(b.size.x, b.size.z)
			m.scale = Vector3.ONE * s
			m.position = -Vector3(b.get_center().x * s, b.position.y * s, b.get_center().z * s)
			box = AABB(Vector3(-b.size.x * s * 0.5, 0, -b.size.z * s * 0.5), b.size * s)
	var forma := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	forma.shape = bs
	forma.position = box.get_center()
	add_child(forma)
	## Il raro si fa notare: una luce azzurra (il colore dell'Arcanium).
	if raro:
		_luce = OmniLight3D.new()
		_luce.light_color = Color(0.4, 0.7, 1.0)
		_luce.light_energy = 1.4
		_luce.omni_range = 3.5
		_luce.position.y = 1.0
		add_child(_luce)


func activate(_chi : Node) -> void:
	if aperto_gia:
		return
	aperto_gia = true
	remove_from_group("interactable")
	print("DUNGEON: forziere %s aperto" % ("RARO" if raro else "normale"))
	aperto.emit(raro)
	## Il baule di Kalvorn ha il coperchio incernierato e l'animazione "Apri"
	## (arcanium/tools/baule_apribile.py): si apre davvero e resta li'.
	for ap in _modello.find_children("*", "AnimationPlayer", true, false):
		var player := ap as AnimationPlayer
		if player.has_animation(ANIM_APERTURA):
			player.play(ANIM_APERTURA)
			if _luce != null:
				create_tween().tween_property(_luce, "light_energy", 0.0, 0.8)
			return
	## Un forziere in un pezzo solo si apre "a sparire": un sobbalzo, poi
	## rimpicciolisce.
	var tw := create_tween()
	tw.tween_property(_modello, "position:y", 0.25, 0.15)
	tw.tween_property(_modello, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
