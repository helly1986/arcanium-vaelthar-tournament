extends SceneTree

## L'HUD NUOVO fotografato sul giocatore vero dentro un dungeon:
##   1_hud.png        a riposo;
##   2_accumuli.png   dopo un colpo, con Congelamento e Lacerazione in carica
##                    in basso al centro;
##   3_scatto.png     lo scatto del Congelamento: la scritta rossa.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_hud.gd -- <cartella>

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 30:
		await process_frame
	root.get_node("CrystalBank").add(340)
	await _foto("1_hud", 0.5)
	var hud : Control = get_first_node_in_group("arcanium_hud")
	var pl : Node = scena.get_node("Player")
	pl.health_system._on_damage_signal({"power": 42.0, "damage_type": "FISICO"})
	var host = hud.status_host
	host.build_frozen(55.0)
	host.build_laceration(30.0)
	await _foto("2_accumuli", 0.25)
	host.apply_frozen()
	await _foto("3_scatto", 0.3)
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
