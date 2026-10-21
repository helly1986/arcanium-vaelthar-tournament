extends SceneTree

## La SELEZIONE DEL CAMPIONE fotografata, per guardarla: Edran (Dawnkeep,
## sbloccato), Ilwen (Sylvorn) e Zarine (Aethon), con la preview girata.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_selezione.gd -- <cartella>

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	var s : Node = load("res://arcanium/ui/selezione_campione/selezione_campione.tscn").instantiate()
	root.add_child(s)
	await _foto("1_edran", 0.8)
	s._scegli(1)
	await _foto("2_ilwen", 0.8)
	s._scegli(3)
	s._perno.rotation.y = 0.9
	await _foto("3_zarine", 0.6)
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
