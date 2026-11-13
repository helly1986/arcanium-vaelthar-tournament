extends SceneTree

## Il MINI-DUNGEON fotografato con la camera di gioco: il giocatore viene
## portato al centro di alcune stanze (le piu' grandi per prime) e si scatta.
##   stanza_<i>.png  una per stanza, con la camera del giocatore.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_dungeon.gd -- <cartella> [seme] [quante] [profilo]
## (profilo: un .tres di profilo_dungeon.gd, per esempio
## res://arcanium/levels/dungeon/profilo_dimora.tres)

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	var seme := int(args[1]) if args.size() > 1 else 3
	var quante := int(args[2]) if args.size() > 2 else 4
	await process_frame
	root.size = Vector2i(1920, 1080)
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	var du : Node = scena.get_node("Dungeon")
	du.set("seme", seme)
	du.set("mostra_fine", false)
	if args.size() > 3:
		du.set("profilo", load(args[3]))
	root.add_child(scena)
	for k in 10:
		await process_frame
	## I nemici fermi: si guarda il luogo, non lo scontro.
	for e in root.get_tree().get_nodes_in_group("targets"):
		e.set("ai_enabled", false)
		e.set_physics_process(false)
	var player : Node3D = scena.get_node("Player")
	var pianta = du.get("pianta")
	var ordine : Array = range(pianta.stanze.size())
	ordine.sort_custom(func(a, b): return pianta.stanze[a]["rect"].get_area() > pianta.stanze[b]["rect"].get_area())
	for n in mini(quante, ordine.size()):
		var i : int = ordine[n]
		var celle : Array = pianta.celle_di(i)
		var r : Rect2i = pianta.stanze[i]["rect"]
		var mezzo : Vector2i = r.position + r.size / 2
		var c : Vector2i = celle[0]
		for x in celle:
			if pianta.camminabile(x) and Vector2(x - mezzo).length() < Vector2(c - mezzo).length():
				c = x
		player.global_position = pianta.centro(c) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		await _foto("stanza_%d" % n, 1.2)
	quit()


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
