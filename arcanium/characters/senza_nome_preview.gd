extends Node3D

## Anteprima di verifica del Senza Nome retargettato: riproduce in loop l'idle
## dal suo AnimationPlayer, per controllare a vista scala/orientamento/retarget
## prima di assemblare la scena-nemico completa (AnimationTree + AI + ragdoll).
## Temporaneo — verrà sostituito dalla scena-nemico vera.

@export var idle_anim : String = "IdleCombat"
## Correzione dello scarto interno della mesh (Meshy non guarda esattamente -Z).
## Regolabile: se dopo il look_at resta storto, si dialla questo valore in gradi.
@export var facing_offset_deg : float = 0.0

func _ready() -> void:
	var ap := _find_anim_player(self)
	if ap == null:
		push_warning("SenzaNomePreview: nessun AnimationPlayer trovato.")
	elif ap.has_animation(idle_anim):
		var anim := ap.get_animation(idle_anim)
		anim.loop_mode = Animation.LOOP_LINEAR
		ap.play(idle_anim)

	# Guarda il player (esatto), poi applica l'offset di scarto mesh.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var t := player.global_position
		t.y = global_position.y  # niente inclinazione verticale
		if global_position.distance_to(t) > 0.01:
			look_at(t, Vector3.UP)
		rotate_y(deg_to_rad(facing_offset_deg))

func _find_anim_player(n : Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null
