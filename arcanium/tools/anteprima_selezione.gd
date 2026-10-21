extends SceneTree

## La SELEZIONE DEL CAMPIONE fotografata, per guardarla: un'immagine per ogni
## campione chiesto (indici nell'ordine delle casate), <indice>_<casata>.png.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_selezione.gd -- <cartella> [indici] [idle]
##
## Con `idle` il campione non sta nella Posa del menu ma suona la sua idle di
## gioco (la guardia del moveset): serve a guardare i pesi in movimento.

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	var s : Node = load("res://arcanium/ui/selezione_campione/selezione_campione.tscn").instantiate()
	root.add_child(s)
	## Dopo la cartella, gli indici dei campioni da fotografare (default 0 1 3).
	var idle := "idle" in args
	var numeri : Array = Array(args.slice(1)).filter(func(x): return String(x).is_valid_int())
	var indici : Array = numeri.map(func(x): return int(x)) if not numeri.is_empty() else [0, 1, 3]
	for i in indici:
		s._scegli(i)
		if idle and s._corpo != null and s.campioni[i].idle != "":
			for ap in s._corpo.find_children("*", "AnimationPlayer", true, false):
				(ap as AnimationPlayer).stop()
			s._idle(s.campioni[i].idle)
		await _foto("%d_%s%s" % [i, s.campioni[i].casata, "_idle" if idle else ""], 0.8)
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
