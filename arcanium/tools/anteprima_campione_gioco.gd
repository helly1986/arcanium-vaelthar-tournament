extends SceneTree

## Il CAMPIONE IN GIOCO fotografato nel dungeon vero, con la camera di gioco:
## per ogni casata chiesta <casata>_1_fermo.png (idle) e <casata>_2_colpo.png
## (a meta' del primo attacco), e per ognuna un ritaglio ingrandito attorno al
## giocatore (_vicino, da una camera di fronte a lui). Stampa anche quante ossa e mesh ha il corpo e che clip
## suona da fermo.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_campione_gioco.gd -- <cartella> [casate]

var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	var casate : Array = Array(args.slice(1)) if args.size() > 1 else ["dawnkeep"]
	await process_frame
	var salva : Node = root.get_node("SaveManager")
	for casa in casate:
		salva._house = String(casa)
		var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
		scena.get_node("Dungeon").seme = 0
		root.add_child(scena)
		for k in 40:
			await process_frame
		var pl : Node = scena.get_node("Player")
		var corpo : Node = pl.get_node_or_null("CorpoCampione")
		var sk : Skeleton3D = pl.get_node("protagonist/BaseArmature/GeneralSkeleton")
		var visibili := sk.get_children().filter(func(m): return m is MeshInstance3D and m.visible).map(func(m): return m.name)
		print("CAMPIONE %s: %s, %d ossa, mesh visibili %s" % [casa,
				corpo.campione.nome if corpo != null and corpo.campione != null else "nessuno",
				sk.get_bone_count(), str(visibili)])
		var ap : AnimationPlayer = pl.get_node("protagonist/AnimationPlayer")
		var idle := ap.get_animation("MeleeLib/LightIdle")
		print("  LightIdle: %d tracce, prima %s" % [idle.get_track_count(), idle.track_get_path(0)])
		await create_timer(1.5, true, false, true).timeout
		var albero = pl.animation_tree
		var arma_albero = albero.get("current_weapon_tree")
		print("  stato: %s, arma: %s" % [albero.base_state_machine.get_current_node(),
				arma_albero.get_current_node() if arma_albero != null else "-"])
		await _foto("%s_1_fermo" % casa, 0.2, pl)
		pl.attack()
		await _foto("%s_2_colpo" % casa, 0.3, pl)
		root.remove_child(scena)
		scena.queue_free()
		await process_frame
	quit()


func _foto(nome : String, attesa : float, pl : Node3D) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_dove.path_join(nome + ".png"))
	## Il primo piano: una camera vicina di fronte al giocatore, per leggere la
	## posa (la nebbia di guerra puo' velarla: per l'aspetto fa fede l'altra).
	var gioco := root.get_viewport().get_camera_3d()
	var vicina := Camera3D.new()
	pl.add_child(vicina)
	var avanti := pl.global_transform.basis.z.normalized()
	vicina.global_position = pl.global_position + avanti * 3.2 + Vector3(0, 1.3, 0)
	vicina.look_at(pl.global_position + Vector3(0, 0.95, 0))
	vicina.fov = 40.0
	vicina.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var z := root.get_texture().get_image()
	z = z.get_region(Rect2i(z.get_width() / 2 - z.get_height() / 2, 0, z.get_height(), z.get_height()))
	z.save_png(_dove.path_join(nome + "_vicino.png"))
	vicina.current = false
	vicina.queue_free()
	if gioco != null:
		gioco.current = true
	print("ANTEPRIMA: ", nome)
