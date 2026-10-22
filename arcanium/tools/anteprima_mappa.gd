extends SceneTree

## La MAPPA DELLA RUN fotografata (arcanium/ui/mappa/mappa_schermo.tscn), su una
## run col seme dato:
##   1_inizio.png    la prima regione, col primo piano acceso;
##   2_scheda.png    la scheda di un nodo raggiungibile;
##   3_cammino.png   dopo tre nodi completati, col sentiero d'oro.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_mappa.gd -- <cartella> [seme]

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	var seme := int(args[1]) if args.size() > 1 else 7
	await process_frame
	root.size = Vector2i(1920, 1080)
	var torneo : Node = root.get_node("Torneo")
	torneo.inizia(seme)
	var m : Node = load("res://arcanium/ui/mappa/mappa_schermo.tscn").instantiate()
	root.add_child(m)
	await _foto("1_inizio", 0.6)
	m._su_nodo(torneo.raggiungibili()[0])
	await _foto("2_scheda", 0.3)
	for k in 3:
		torneo.scegli(torneo.raggiungibili()[0])
		torneo.completa()
	m._ricostruisci()
	await _foto("3_cammino", 0.6)
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
