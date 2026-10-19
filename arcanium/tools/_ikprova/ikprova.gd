extends Node3D
## Due Fanti affiancati sullo stesso terreno, idle in corso: a sinistra con
## l'IK dei piedi SPENTO, a destra ACCESO.
## ⚠️ Si GUARDA. `get_bone_global_pose()` da fuori restituisce la posa
## dell'ANIMAZIONE, non quella che esce dai modificatori (docs/05 §5-bis).
const FANTE := "res://arcanium/characters/sylvorn_fante.tscn"

func _ready() -> void:
	await get_tree().process_frame
	for i in 2:
		var e = (load(FANTE) as PackedScene).instantiate()
		e.name = "Fante%d" % i
		add_child(e)
		e.global_position = Vector3(-0.75 + 1.5 * i, 0.0, 0.0)
		# ⚠️ NON si spegne `set_physics_process`: senza `move_and_slide()` il
		# corpo non e' mai `is_on_floor()`, e quello e' proprio uno dei due
		# interruttori dell'IK. Spegnendolo si disattiva la cosa da misurare.
		var ik := e.find_child("IkPiedi", true, false)
		if ik != null:
			(ik as SkeletonModifier3D).active = (i == 1)
		var ap : AnimationPlayer = e.find_child("AnimationPlayer", true, false)
		if ap != null and ap.has_animation("sword/sword_idle_01"):
			ap.play("sword/sword_idle_01")
			ap.seek(0.6, true)
	# ⚠️ 3.8 cm su 1.8 m sono il 2%: a quella scala non si giudica niente.
	# Si ESAGERA finche' diventa evidente (docs/05 §5-bis, trappola 2), e
	# tanto vale esagerare con la cosa per cui l'IK esiste davvero: terreno
	# diseguale. Uno scalino di 12 cm sotto il piede destro di ognuno.
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in 2:
		# lo scalino va messo sotto il piede VERO, letto a runtime
		var e := get_node("Fante%d" % i)
		var sk : Skeleton3D = e.find_child("Skeleton3D", true, false)
		var pie : Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightFoot"))).origin
		var s := StaticBody3D.new()
		s.collision_layer = 1
		add_child(s)
		s.global_position = Vector3(pie.x, 0.06, pie.z)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.34, 0.12, 0.5)
		cs.shape = bs
		s.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bs.size
		mi.mesh = bm
		s.add_child(mi)
	_scatta()

func _scatta() -> void:
	for _i in 12:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://arcanium/tools/_ikprova/vista.png")
	print("SPENTO a sinistra, ACCESO a destra")
	get_tree().quit()
