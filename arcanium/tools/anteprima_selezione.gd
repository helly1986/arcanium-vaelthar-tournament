extends SceneTree

## La SELEZIONE DEL CAMPIONE fotografata, per guardarla: un'immagine per ogni
## campione chiesto (indici nell'ordine delle casate), <indice>_<casata>.png.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_selezione.gd -- <cartella> [indici]

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	var s : Node = load("res://arcanium/ui/selezione_campione/selezione_campione.tscn").instantiate()
	root.add_child(s)
	## Dopo la cartella, gli indici dei campioni da fotografare (default 0 1 3).
	var indici : Array = Array(args.slice(1)).map(func(x): return int(x)) if args.size() > 1 else [0, 1, 3]
	for i in indici:
		s._scegli(i)
		await _foto("%d_%s" % [i, s.campioni[i].casata], 0.8)
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
