extends SceneTree

## La MANO DEL CAMPIONE sull'impugnatura, da vicino, in gioco (dungeon vero):
## <casata>_mano_<lato>_<n>.png da davanti, di lato e da sopra, con la presa
## della scheda (presa_mano.gd) e senza (_aperta), per confrontarle.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_mano.gd -- <cartella> [casata] [chiusura]
## `chiusura` sovrascrive quella della scheda, per provare un valore.

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	var casa : String = args[1] if args.size() > 1 else "dawnkeep"
	await process_frame
	root.size = Vector2i(1200, 1200)
	var salva : Node = root.get_node("SaveManager")
	salva._house = casa
	root.get_node("EquipmentLoadout").clear_all()
	salva._tecniche_del_campione()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 40:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	var sk : Skeleton3D = pl.get_node("protagonist/BaseArmature/GeneralSkeleton")
	var presa : Node = sk.get_node_or_null("PresaManoDestra")
	if presa != null and args.size() > 2:
		presa.chiusura = float(args[2])
	print("PRESA: %s" % ("chiusura %.2f, %d pieghe" % [presa.chiusura, presa._pieghe.size()] if presa != null else "nessuna"))
	await create_timer(1.5, true, false, true).timeout
	pl.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 30.0
	scena.add_child(cam)
	cam.current = true
	## Una luce sulla mano: nel dungeon l'avambraccio e' in ombra.
	var luce := OmniLight3D.new()
	luce.omni_range = 2.0
	luce.light_energy = 0.5
	scena.add_child(luce)
	var mano := sk.find_bone("RightHand")
	for giro in ["", "_aperta"]:
		if presa != null:
			presa.active = giro == ""
		await process_frame
		var g := sk.global_transform * sk.get_bone_global_pose(mano)
		var avanti := pl.global_transform.basis.z.normalized()
		var destra := -pl.global_transform.basis.x.normalized()
		var viste := {"davanti": avanti * 0.85, "lato": destra * 0.85, "sopra": Vector3.UP * 0.75 + avanti * 0.35,
				"dentro": -destra * 0.6 + avanti * 0.3, "sotto": Vector3.DOWN * 0.6 + avanti * 0.3}
		luce.global_position = g.origin + avanti * 0.5 + destra * 0.3 + Vector3.UP * 0.3
		for nome in viste:
			cam.global_position = g.origin + viste[nome]
			cam.look_at(g.origin + Vector3(0, -0.06, 0), Vector3.UP if not nome in ["sopra", "sotto"] else avanti)
			await create_timer(0.15, true, false, true).timeout
			await RenderingServer.frame_post_draw
			var f := _dove.path_join("%s_mano_%s%s.png" % [casa, nome, giro])
			root.get_texture().get_image().save_png(f)
			print("ANTEPRIMA: ", f.get_file())
	quit()
