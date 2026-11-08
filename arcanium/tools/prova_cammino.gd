extends SceneTree

## La PROVA DEL CAMMINO: il campione cammina in gioco (root-LightWalking, la
## clip fatta in Cascadeur dal 2026-11-08) e si misura se i piedi PATTINANO.
##
## Nell'arena aperta del prologo, l'input a 0,3 (il punto del cammino nella
## blend space MoveStrafe, con la deadzone tolta solo qui): dopo due secondi,
## per un ciclo e mezzo, a ogni frame si segna dove sono le dita dei piedi nel
## mondo. Un piede e' A TERRA quando le dita stanno entro 1,5 cm dal loro punto
## piu' basso; quanto scorrono in orizzontale mentre sono a terra e' il
## pattinamento: root motion e passo che non vanno d'accordo, o un piede che
## scivola nella clip.
##
## Esce anche un foglio di fianco, <casata>_cammino.png, 16 scatti a 1/15 s.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --fixed-fps 60 --script res://arcanium/tools/prova_cammino.gd -- <cartella> [casata]

const ARENA := "res://arcanium/levels/arena_senza_fuoco.tscn"
const SPINTA := 0.3
const A_TERRA := 0.015
const LATO := 300
const COLONNE := 8
const MOSSE := ["move_up", "move_down", "move_left", "move_right"]

var _dir := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else OS.get_user_data_dir()
	var casa := String(args[1]) if args.size() > 1 else "dawnkeep"
	await process_frame
	var salva : Node = root.get_node("SaveManager")
	salva._house = casa
	root.get_node("EquipmentLoadout").clear_all()
	salva._tecniche_del_campione()
	var scena : Node = load(ARENA).instantiate()
	for via in ["SenzaNome", "PrologueDirector", "BossBarLayer"]:
		var n := scena.get_node_or_null(via)
		if n != null:
			scena.remove_child(n)
			n.free()
	root.add_child(scena)
	for k in 40:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	pl.global_position = Vector3(0, pl.global_position.y, -6.0)
	var sk : Skeleton3D = pl.get_node("protagonist/BaseArmature/GeneralSkeleton")
	var luce := OmniLight3D.new()
	pl.add_child(luce)
	luce.position = Vector3(2.0, 1.8, 0.0)
	luce.omni_range = 8.0
	luce.light_energy = 2.5
	var camera := Camera3D.new()
	pl.add_child(camera)
	camera.fov = 32.0
	await _attesa(4.0)

	for m in MOSSE:
		InputMap.action_set_deadzone(m, 0.0)
	Input.action_press("move_up", SPINTA)
	await _attesa(2.0)
	## Di fianco, alla sua sinistra: e' il lato dello scudo.
	camera.position = Vector3(3.6, 0.9, 0.0)
	camera.look_at(pl.global_position + Vector3(0, 0.85, 0))
	camera.current = true

	var albero = pl.animation_tree
	var blend = albero.get("parameters/MovementStates/%s_tree/MoveStrafe/blend_position" % albero.weapon_type)
	print("CAMMINO %s: blend %s, stato %s, motion_scale %.4f, bacino a %.3f m dal player" % [casa, blend,
			albero.base_state_machine.get_current_node(), sk.motion_scale,
			(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips"))).origin.y - pl.global_position.y])
	var piedi := {"LeftToes": [], "RightToes": []}
	var partenza := pl.global_position
	var scatti : Array[Image] = []
	var frame := 0
	var durata := 96
	while frame < durata:
		await physics_frame
		for p in piedi:
			piedi[p].append((sk.global_transform * sk.get_bone_global_pose(sk.find_bone(p))).origin)
		if frame % 4 == 0 and scatti.size() < 16:
			camera.look_at(pl.global_position + Vector3(0, 0.85, 0))
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var h := img.get_height()
			img = img.get_region(Rect2i(img.get_width() / 2 - h * 2 / 5, h / 20, h * 4 / 5, h * 9 / 10))
			img.resize(LATO, LATO * 9 / 8)
			scatti.append(img)
		frame += 1
	var secondi := durata / float(Engine.physics_ticks_per_second)
	var strada := pl.global_position - partenza
	strada.y = 0.0
	print("  velocita' %.3f m/s (%.2f m in %.2f s)" % [strada.length() / secondi, strada.length(), secondi])
	for p in piedi:
		_pattinamento(p, piedi[p])
	Input.action_release("move_up")
	_foglio(casa, scatti)
	quit()


## Le fasi a terra di un piede e quanto scorre in ciascuna.
func _pattinamento(nome : String, punti : Array) -> void:
	var basso := INF
	for q in punti:
		basso = minf(basso, (q as Vector3).y)
	var fasi : Array[String] = []
	var peggio := 0.0
	var inizio := -1
	for i in punti.size() + 1:
		var giu := i < punti.size() and (punti[i] as Vector3).y < basso + A_TERRA
		if giu and inizio < 0:
			inizio = i
		elif not giu and inizio >= 0:
			var a : Vector3 = punti[inizio]
			var corsa := 0.0
			for j in range(inizio + 1, i):
				var d : Vector3 = (punti[j] as Vector3) - (punti[j - 1] as Vector3)
				d.y = 0.0
				corsa += d.length()
			var netto : Vector3 = (punti[i - 1] as Vector3) - a
			netto.y = 0.0
			fasi.append("%d frame, scorre %.1f cm (netto %.1f)" % [i - inizio, corsa * 100.0, netto.length() * 100.0])
			if i - inizio >= 6:
				peggio = maxf(peggio, netto.length())
			inizio = -1
	print("  %s: a terra %s | peggio %.1f cm" % [nome, ", ".join(fasi), peggio * 100.0])


func _foglio(nome : String, scatti : Array[Image]) -> void:
	var alto := LATO * 9 / 8
	var righe := (scatti.size() + COLONNE - 1) / COLONNE
	var foglio := Image.create(LATO * mini(scatti.size(), COLONNE), alto * righe, false, Image.FORMAT_RGB8)
	for i in scatti.size():
		var s := scatti[i]
		s.convert(Image.FORMAT_RGB8)
		foglio.blit_rect(s, Rect2i(0, 0, LATO, alto), Vector2i((i % COLONNE) * LATO, (i / COLONNE) * alto))
	var p := _dir.path_join("%s_cammino.png" % nome)
	foglio.save_png(p)
	print("CAMMINO: foglio -> %s" % p)


func _attesa(secondi : float) -> void:
	await create_timer(secondi, true, false, true).timeout
