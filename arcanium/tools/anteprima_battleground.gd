extends SceneTree

## Il BATTLEGROUND fotografato (arcanium/levels/battleground/battleground.tscn):
##   1_schiera.png  lo schieramento sopra la piana;
##   2_campo.png    la piana dall'alto con le due armate, appena schierate;
##   3_scontro.png  qualche secondo dopo, con la camera di gioco;
##   4_rivale.png   l'arcimago rivale da vicino, con l'arma della sua casata.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_battleground.gd -- <cartella> [seme run]

var _dove := ""
const LARGO_X := 30.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	root.size = Vector2i(1920, 1080)
	root.get_node("SaveManager")._house = "dawnkeep"
	var torneo : Node = root.get_node("Torneo")
	torneo.inizia(int(args[1]) if args.size() > 1 else 21)
	for reg in torneo.mappa["regioni"]:
		for id in reg["nodi"]:
			if reg["nodi"][id]["tipo"] == "battleground" and torneo.nodo_corrente == "":
				torneo.nodo_corrente = id
	var scena : Node = load("res://arcanium/levels/battleground/battleground.tscn").instantiate()
	var du : Node = scena.get_node("Campo")
	root.add_child(scena)
	for k in 10:
		await process_frame
	await _foto("1_schiera", 0.5)
	du._schiera.conferma()
	var gioco := root.get_viewport().get_camera_3d()
	var alto := Camera3D.new()
	scena.add_child(alto)
	alto.global_position = Vector3(0, 46, 34)
	alto.look_at(Vector3(0, 0, 2))
	alto.fov = 55.0
	alto.current = true
	await _foto("2_campo", 0.6)
	await _foto("3_alto_dopo", 4.0)
	alto.current = false
	if gioco != null:
		gioco.current = true
	await _foto("3_scontro", 0.3)
	var r : Node3D = du.rivale
	## Da solo e fermo, lontano dalla mischia: davanti alla camera si metteva
	## un Fante della sua armata.
	r.set("ai_enabled", false)
	r.global_position = Vector3(-LARGO_X, 0.1, 0)
	r.rotation.y = 0.0
	await process_frame
	var vicina := Camera3D.new()
	scena.add_child(vicina)
	var avanti := r.global_transform.basis.z.normalized()
	vicina.global_position = r.global_position + avanti * 3.4 + Vector3(0, 1.5, 0)
	vicina.look_at(r.global_position + Vector3(0, 1.0, 0))
	vicina.fov = 42.0
	vicina.current = true
	await _foto("4_rivale", 0.3)
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
