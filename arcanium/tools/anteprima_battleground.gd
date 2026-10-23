extends SceneTree

## Il BATTLEGROUND fotografato: 1_schiera.png lo schieramento sopra il dungeon,
## 2_campo.png le truppe in campo accanto al giocatore.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_battleground.gd -- <cartella>

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	root.size = Vector2i(1920, 1080)
	var torneo : Node = root.get_node("Torneo")
	torneo.inizia(21)
	for reg in torneo.mappa["regioni"]:
		for id in reg["nodi"]:
			if reg["nodi"][id]["tipo"] == "battleground" and torneo.nodo_corrente == "":
				torneo.nodo_corrente = id
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	var du : Node = scena.get_node("Dungeon")
	du.obiettivo = 0
	root.add_child(scena)
	for k in 10:
		await process_frame
	await _foto("1_schiera", 0.5)
	du._schiera.scelte = [0, 0, 0]
	du._schiera.conferma()
	await _foto("2_campo", 1.5)
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
