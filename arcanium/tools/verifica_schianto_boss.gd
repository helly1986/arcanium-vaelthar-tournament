extends Node3D

## CANCELLO DI VERIFICA degli agganci: che il Senza Nome sull'Arena Senza Fuoco
## alzi davvero pietre grigie, e che la camera tremi.
##
## ⚠️ Non è una ripetizione della verifica sulla Traccia Perduta. Lì si tarava
## l'EFFETTO; qui si controlla una cosa diversa e che può rompersi da sola: che
## il raggio verso il basso trovi il PAVIMENTO DELL'ARENA. Il suolo dell'arena è
## geometria costruita dal builder, non Terrain3D, e se i suoi corpi non stanno
## sul layer "World" lo schianto non nasce proprio — senza errori, senza niente
## a schermo, che è il tipo di guasto che sopravvive a qualunque test di codice.
##
## Lancio (niente --headless: serve la finestra per renderizzare):
##   Godot_v4.7-stable_win64.exe --path . res://arcanium/tools/verifica_schianto_boss.tscn --resolution 1600x900

const LIVELLO := "res://arcanium/levels/arena_senza_fuoco.tscn"
## Dove finiscono gli scatti: primo argomento utente, o la cartella utente.
var FUORI : String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()

const ISO_OFFSET := Vector3(0, 25.18, 25.18)
const ISO_FOV := 50.0
const ISO_ZOOM := 0.82

var _cam : Camera3D


func _ready() -> void:
	add_child(load(LIVELLO).instantiate())
	_cam = Camera3D.new()
	_cam.fov = ISO_FOV
	add_child(_cam)
	_cam.make_current()

	for _i in 30:
		await get_tree().physics_frame

	var boss : Node3D = null
	for n in get_tree().get_nodes_in_group("targets"):
		if n.get_class() == "CharacterBody3D" and n.name.to_lower().contains("senza"):
			boss = n
	if boss == null:
		## Ripiego: il primo nodo che sa forzare una mossa.
		for n in _tutti(self):
			if n.has_method("debug_force_move"):
				boss = n
				break
	if boss == null:
		push_error("Senza Nome non trovato nella scena.")
		get_tree().quit(1)
		return
	print("[boss] trovato: %s a %s" % [boss.name, boss.global_position])

	## Il pavimento c'è, sotto di lui, sul layer che lo schianto interroga?
	var q := PhysicsRayQueryParameters3D.create(
			boss.global_position + Vector3.UP * 1.5,
			boss.global_position + Vector3.DOWN * 6.0, 1)
	q.exclude = [boss.get_rid()]
	var colpo := get_world_3d().direct_space_state.intersect_ray(q)
	if colpo.is_empty():
		push_error("NESSUN PAVIMENTO sul layer World sotto al boss: lo schianto non nascera' mai.")
	else:
		print("[boss] pavimento trovato: %s a y=%.2f" % [colpo["collider"].name, colpo["position"].y])

	## Si chiama direttamente l'imbuto delle scariche: `_burst_vfx` è il punto in
	## cui è stato messo l'aggancio, e attendere che l'AI scelga da sola la mossa
	## giusta renderebbe il test non ripetibile.
	boss._burst_vfx(3.4)
	print("[boss] trauma dopo la scarica: %.3f" % Scossa._trauma)

	for quando in [0.15, 0.55, 1.40]:
		await _dopo(quando)
		await _scatta("boss_schianto_%.2f.png" % quando, boss.global_position)

	get_tree().quit()


func _tutti(n : Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_tutti(c))
	return out


func _dopo(s : float) -> void:
	await get_tree().create_timer(s).timeout


func _scatta(nome : String, centro : Vector3) -> void:
	_cam.global_position = centro + ISO_OFFSET * ISO_ZOOM
	_cam.look_at(centro, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(FUORI + "/" + nome)
	print("[boss] %s" % nome)
