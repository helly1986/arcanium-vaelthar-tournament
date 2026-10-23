extends SceneTree

## Le SCHERMATE DEI NODI della mappa fotografate sopra la mappa: riposo,
## tesoro, mercante, imprevisto (<tipo>.png).
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_nodi_mappa.gd -- <cartella> [seme]

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	root.size = Vector2i(1920, 1080)
	var torneo : Node = root.get_node("Torneo")
	torneo.inizia(int(args[1]) if args.size() > 1 else 7)
	torneo.sconfitte = 1
	root.get_node("CrystalBank").add(420)
	var m : Node = load("res://arcanium/ui/mappa/mappa_schermo.tscn").instantiate()
	root.add_child(m)
	for tipo in ["riposo", "tesoro", "mercante", "imprevisto"]:
		for reg in torneo.mappa["regioni"]:
			for id in reg["nodi"]:
				if reg["nodi"][id]["tipo"] == tipo and torneo.nodo_corrente == "":
					torneo.nodo_corrente = id
		var s : Node = load("res://arcanium/ui/mappa/nodo_%s.tscn" % tipo).instantiate()
		m.add_child(s)
		await _foto(tipo, 0.4)
		s.free()
		torneo.nodo_corrente = ""
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
