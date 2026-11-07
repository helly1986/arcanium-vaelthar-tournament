extends SceneTree

## Una LUCIDA TECNICA fotografata con la camera di gioco: il campione nel dungeon vero,
## la tecnica lanciata dal suo caster, i fotogrammi dal suo effetto in poi. Il primo e'
## prima dell'effetto, a `anticipo` secondi dal lancio.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_lucida.gd -- <cartella> <casata> [anticipo] [momenti, in secondi]

const NOMI_EFFETTI := ["PropagazioneEquilibrio", "LascitoBruciante", "TerraRisvegliata"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dove : String = args[0]
	var casata : String = args[1] if args.size() > 1 else "aethon"
	var anticipo : float = float(args[2]) if args.size() > 2 else 0.0
	var momenti := []
	for k in range(3, args.size()):
		momenti.append(float(args[k]))
	if momenti.is_empty():
		momenti = [0.08, 0.22, 0.42, 0.62, 0.95, 1.4]
	await process_frame
	root.get_node("SaveManager")._house = casata
	root.get_node("EquipmentLoadout").clear_all()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 60:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	## Un nemico davanti, fermo: per le tecniche che vanno su qualcuno.
	var nemico : Node3D = null
	for n in get_nodes_in_group("targets"):
		if n != pl and n is CharacterBody3D:
			n.set_physics_process(false)
			n.global_position = pl.global_transform * Vector3(2.5, 0.0, 6.0)
			nemico = n
			break
	print("lancia: ", pl.lucida_tecnica_caster.lancia())
	var onda : Node = null
	var attesa := 0.0
	var lancio := Time.get_ticks_msec()
	var foto_prima := anticipo <= 0.0
	while onda == null and attesa < (2.0 if pl.lucida_tecnica_caster.tecnica_corrente().infusione_metodo != "" else 5.0):
		await process_frame
		attesa = (Time.get_ticks_msec() - lancio) / 1000.0
		if not foto_prima and attesa >= anticipo:
			foto_prima = true
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(dove.path_join("onda_prima.png"))
		for n in scena.get_children():
			for nome in NOMI_EFFETTI:
				if String(n.name).begins_with(nome):
					onda = n
	print("impatto dopo %.2f s" % attesa)
	## Le infusioni non hanno un effetto a terra: si colpisce il nemico, per vedere lo
	## status addosso a lui.
	if pl.lucida_tecnica_caster.infusione_attiva() and nemico != null:
		nemico.global_position = pl.global_transform * Vector3(0.9, 0.0, 1.7)
		nemico.health_system.total_health = 100000
		nemico.health_system.current_health = 100000
		nemico.health_system.set("_health_f", 100000.0)
		for k in 8:
			pl.lucida_tecnica_caster.dopo_il_colpo(nemico)
	var inizio := Time.get_ticks_msec()
	for k in momenti.size():
		while (Time.get_ticks_msec() - inizio) / 1000.0 < momenti[k]:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dove.path_join("onda_%d.png" % k))
	quit()
