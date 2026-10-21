extends SceneTree

## I MENU fotografati, per guardarli: menu principale, impostazioni (Video e
## Controls), creazione del personaggio, menu di gioco (Stats, Inventory,
## Grimoire) e la modale d'equipaggiamento sopra un dungeon.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_menu.gd -- <cartella>

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame

	var mm : Node = load("res://arcanium/ui/main_menu/main_menu.tscn").instantiate()
	root.add_child(mm)
	await _foto("1_menu_principale")
	mm.queue_free()

	var sm : Node = load("res://arcanium/ui/settings_menu/settings_menu.tscn").instantiate()
	root.add_child(sm)
	sm._select_tab("Video")
	await _foto("2_impostazioni_video")
	sm._select_tab("Controls")
	await _foto("3_impostazioni_comandi")
	sm.queue_free()

	var cc : Node = load("res://arcanium/ui/char_creation/char_creation.tscn").instantiate()
	root.add_child(cc)
	await _foto("4_creazione")
	cc.queue_free()

	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 20:
		await process_frame
	var gm : Node = root.get_node("GameMenu")
	gm.open_at("stats")
	await _foto("5_menu_stats")
	gm.open_at("inventory")
	await _foto("6_menu_inventario")
	gm.open_at("grimorio")
	await _foto("7_menu_grimorio")
	gm.open_at("inventory")
	await process_frame
	gm._apri_modale_equip("arma_primaria")
	await _foto("8_modale_equip")
	quit()


func _foto(nome : String) -> void:
	await create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
