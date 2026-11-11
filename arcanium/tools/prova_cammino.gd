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
##   godot --path . --fixed-fps 60 --script res://arcanium/tools/prova_cammino.gd -- <cartella> [casata] [video] [corsa]
##
## Con `corsa` l'input va al massimo: la clip e' root-LightRunning, il foglio
## <casata>_corsa.png. Con `sprint` in piu' si tiene premuta la schivata come
## nel gioco (dopo 0,3 s parte lo sprint, root-Sprint), foglio <casata>_sprint.png;
## con `sprint levetta` lo sprint parte da un clic di L3, come dal pad.
## Con `strafe` e una direzione (`sinistra`, `destra`, `indietro`, `avanti`) si aggancia un
## bersaglio messo 5 m davanti e ci si sposta a input pieno, come da tastiera:
## agganciati e' il passo in guardia; con anche `corsa` si tiene l'azione `corsa`
## (Alt), e con `corsa levetta` si da' un clic di L3 come dal pad. Camera davanti (con
## `lato` di fianco, per le gambe dietro lo scudo), foglio <casata>_strafe_<direzione>.png.
##
## Con `arma=<nome>` (un .tres di arcanium/resources/weapons) si mette in mano un'altra arma
## dall'inventario: le clip seguono il tipo d'arma.
##
## Con `parata` alza lo scudo (il blocco tenuto) e si filma in guardia; `parata fermo` da fermi.
## Con `schivata fermo` si ferma prima di schivare: e' il salto all'indietro.
## Con `schivata` cammina un secondo e schiva (un tocco del tasto): si misura e si filma la
## rotolata, e quanto testa, bacino e dita scendono rispetto al pavimento.
##
## Con `video` cammina due secondi invece di 1,6 e stampa i fotogrammi da
## tenere: si lancia con `--write-movie <cartella>/f.png` (il Movie Maker scrive
## ogni fotogramma a 1/60 s esatto) e si monta con ffmpeg. Lo scatto si vede
## solo in movimento, e i tempi di un salvataggio a mano mentono.

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
	var video := args.has("video")
	var sprint := args.has("sprint")
	var strafe := ""
	for d in ["sinistra", "destra", "indietro", "avanti"]:
		if args.has("strafe") and args.has(d):
			strafe = d
	var corsa := args.has("corsa") or sprint
	var spinta := 1.0 if corsa else SPINTA
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
	## `arma=<nome>` (un .tres di arcanium/resources/weapons): in mano un'altra arma, come
	## dall'inventario. Le clip seguono il tipo d'arma (moveset_nostro.gd, 2026-11-10).
	for arg in args:
		if String(arg).begins_with("arma="):
			var arma : Resource = load("res://arcanium/resources/weapons/%s.tres" % String(arg).trim_prefix("arma="))
			root.get_node("EquipmentLoadout").equip("arma_primaria", arma)
			for k in 20:
				await process_frame
			print("CAMMINO arma in mano: %s (%s)" % [arma.resource_path.get_file(), pl.get("weapon_type")])
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
	var tasto_mossa := "move_up"
	if strafe != "":
		## Il bersaglio 5 m davanti a lui (l'avanti del player e' +Z), agganciato come
		## col tasto: da li' in poi si gira verso di lui e gli si muove attorno.
		var bersaglio := Marker3D.new()
		bersaglio.add_to_group("targets")
		scena.add_child(bersaglio)
		## Di corsa il bersaglio sta a 12 m: a 4,8 m/s attorno a uno a 5 m si gira in tondo
		## e si esce dal tratto libero.
		bersaglio.global_position = pl.global_position + pl.global_basis.z * (12.0 if args.has("corsa") else 5.0) + Vector3.UP
		pl.set_strafe_targeting()
		await _attesa(0.5)
		tasto_mossa = {"sinistra": "move_left", "destra": "move_right", "indietro": "move_down", "avanti": "move_up"}[strafe]
		## Come da tastiera: input pieno, e agganciati si va a passo; la corsa e'
		## l'azione `corsa` tenuta (Alt sinistro).
		spinta = 1.0
		if args.has("corsa") and args.has("levetta"):
			## Dal pad: un clic di L3 (commutazione), non un tasto tenuto.
			var l3 := InputEventJoypadButton.new()
			l3.button_index = JOY_BUTTON_LEFT_STICK
			l3.pressed = true
			Input.parse_input_event(l3)
		elif args.has("corsa"):
			Input.action_press("corsa")
	Input.action_press(tasto_mossa, spinta)
	if strafe != "" and args.has("corsa"):
		## Come la corsa: l'arena finisce presto (lo strafe si fermava contro un muro a
		## 2,3 m/s, 2026-11-09). Si guarda dove va, e si riparte col bersaglio dal punto
		## col rettilineo libero piu' lungo in quella direzione.
		var da := pl.global_position
		await _attesa(0.3)
		var verso := pl.global_position - da
		verso.y = 0.0
		var nuovo := _rettilineo(pl, verso.normalized())
		var bersaglio_ : Node3D = null
		for n in get_nodes_in_group("targets"):
			if n is Marker3D:
				bersaglio_ = n
		bersaglio_.global_position += nuovo - pl.global_position
		pl.global_position = nuovo
		await _attesa(0.7)
	elif strafe != "":
		await _attesa(1.0)
	elif corsa:
		## A 6,5 m/s l'arena finisce presto: si guarda dove corre, e si riparte dal
		## punto con il rettilineo libero piu' lungo in quella direzione.
		var da := pl.global_position
		await _attesa(0.3)
		var verso := pl.global_position - da
		verso.y = 0.0
		pl.global_position = _rettilineo(pl, verso.normalized())
		if sprint and args.has("levetta"):
			## Dal pad: lo sprint parte anche con un clic di L3.
			var l3 := InputEventJoypadButton.new()
			l3.button_index = JOY_BUTTON_LEFT_STICK
			l3.pressed = true
			Input.parse_input_event(l3)
		elif sprint:
			var tasto := InputEventAction.new()
			tasto.action = "dodge_dash"
			tasto.pressed = true
			Input.parse_input_event(tasto)
		await _attesa(0.9 if sprint else 0.6)
	elif args.has("parata"):
		## La guardia con lo scudo (2026-11-11): cammina (o si ferma con `fermo`), poi alza
		## lo scudo col blocco tenuto premuto e si filma cosi'.
		await _attesa(1.0)
		if args.has("fermo"):
			Input.action_release(tasto_mossa)
			await _attesa(0.6)
		var blocco := InputEventAction.new()
		blocco.action = "use_gadget_light"
		blocco.pressed = true
		Input.parse_input_event(blocco)
		Input.action_press("use_gadget_light")
		await _attesa(0.4)
	elif args.has("schivata"):
		## La schivata (2026-11-10): cammina, poi un tocco del tasto (rilasciato prima dei
		## 0,3 s dello sprint) e si misura da li'.
		await _attesa(1.0)
		if args.has("fermo"):
			## Da fermi la schivata e' il salto all'indietro (DODGE_tree/JumpBack).
			Input.action_release(tasto_mossa)
			await _attesa(0.6)
		var tasto := InputEventAction.new()
		tasto.action = "dodge_dash"
		tasto.pressed = true
		Input.parse_input_event(tasto)
		await _attesa(0.05)
		var su := InputEventAction.new()
		su.action = "dodge_dash"
		su.pressed = false
		Input.parse_input_event(su)
		await process_frame
	else:
		await _attesa(2.0)
	## Di fianco, alla sua sinistra: e' il lato dello scudo. Negli strafe, davanti.
	camera.position = Vector3(0.0, 0.9, 3.6) if strafe != "" and not args.has("lato") else Vector3(3.6, 0.9, 0.0)
	camera.look_at(pl.global_position + Vector3(0, 0.85, 0))
	camera.current = true

	var albero = pl.animation_tree
	var blend = albero.get("parameters/MovementStates/%s_tree/MoveStrafe/blend_position" % albero.weapon_type)
	print("CAMMINO %s: strafe %s, sprint %s, blend %s, stato %s, motion_scale %.4f, bacino a %.3f m dal player" % [casa,
			pl.get("strafing"), pl.get("sprinting"), blend, albero.base_state_machine.get_current_node(), sk.motion_scale,
			(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips"))).origin.y - pl.global_position.y])
	var piedi := {"LeftToes": [], "RightToes": []}
	## Quanto scendono testa e dita sotto il player (il pavimento), per la schivata.
	var bassi := {"Head": INF, "LeftToes": INF, "RightToes": INF, "Hips": INF}
	var partenza := pl.global_position
	var scatti : Array[Image] = []
	var frame := 0
	var tick0 := Engine.get_physics_frames()
	var disegno0 := Engine.get_frames_drawn()
	var durata := (60 if corsa or strafe != "" or args.has("schivata") or args.has("parata") else 120) if video else (60 if corsa or strafe != "" else 96)
	while frame < durata:
		await physics_frame
		for p in piedi:
			piedi[p].append((sk.global_transform * sk.get_bone_global_pose(sk.find_bone(p))).origin)
		for b in bassi:
			bassi[b] = minf(bassi[b], (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin.y - pl.global_position.y)
		camera.look_at(pl.global_position + Vector3(0, 0.85, 0))
		if frame % 4 == 0 and scatti.size() < 16:
			camera.look_at(pl.global_position + Vector3(0, 0.85, 0))
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var h := img.get_height()
			img = img.get_region(Rect2i(img.get_width() / 2 - h * 2 / 5, h / 20, h * 4 / 5, h * 9 / 10))
			img.resize(LATO, LATO * 9 / 8)
			scatti.append(img)
		frame += 1
	var secondi := (Engine.get_physics_frames() - tick0) / float(Engine.physics_ticks_per_second)
	print("  %d giri del ciclo di misura, %d tick di fisica" % [durata, Engine.get_physics_frames() - tick0])
	if video:
		print("VIDEO fotogrammi %d-%d" % [disegno0, Engine.get_frames_drawn()])
	if args.has("parata"):
		print("  parata: guarding %s, blend %.2f, clip %s" % [pl.get("guarding"),
				albero.get("parameters/Guarding/blend_amount"),
				albero.tree_root.get_node("GuardingAnim").animation])
	if args.has("schivata"):
		var dodge = albero.get("parameters/DODGE_tree/playback")
		print("  schivata: clip %s / da fermi %s, suonata %s; piu' in basso sul pavimento: %s" % [
				albero.tree_root.get_node("DODGE_tree").get_node("Roll").animation,
				albero.tree_root.get_node("DODGE_tree").get_node("JumpBack").animation,
				dodge.get_current_node() if dodge != null else "?",
				", ".join(bassi.keys().map(func(b): return "%s %.2f m" % [b, bassi[b]]))])
	var strada := pl.global_position - partenza
	strada.y = 0.0
	print("  velocita' %.3f m/s (%.2f m in %.2f s)" % [strada.length() / secondi, strada.length(), secondi])
	for p in piedi:
		_pattinamento(p, piedi[p], strada.length() / float(durata) * 0.75)
	Input.action_release(tasto_mossa)
	_foglio(casa + ("_schivata" if args.has("schivata") else "") + ("_parata" if args.has("parata") else "") + ("_strafe_" + strafe if strafe != "" else ("_sprint" if sprint else ("_corsa" if corsa else ""))), scatti)
	quit()


## Le fasi a terra di un piede e quanto scorre in ciascuna.
## A terra: basso E piu' lento di `lento` (m per frame, tre quarti del corpo), come
## in rifinisci_clip_cascadeur.py: nel passo accostato i piedi si alzano appena.
func _pattinamento(nome : String, punti : Array, lento : float) -> void:
	var basso := INF
	for q in punti:
		basso = minf(basso, (q as Vector3).y)
	var fasi : Array[String] = []
	var peggio := 0.0
	var inizio := -1
	for i in punti.size() + 1:
		var giu := i < punti.size() and (punti[i] as Vector3).y < basso + A_TERRA and _fermo(punti, i, lento)
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
	var p := _dir.path_join("%s.png" % (nome if nome.contains("_") else nome + "_cammino"))
	foglio.save_png(p)
	print("CAMMINO: foglio -> %s" % p)


func _attesa(secondi : float) -> void:
	await create_timer(secondi, true, false, true).timeout


## Il punto di partenza, su una griglia attorno all'origine, con piu' strada
## libera (e pavimento sotto) davanti nella direzione `verso`.
func _rettilineo(pl : Node3D, verso : Vector3) -> Vector3:
	var spazio := pl.get_world_3d().direct_space_state
	var escluso : Array[RID] = [(pl as CollisionObject3D).get_rid()]
	var meglio := pl.global_position
	var libero := 0.0
	for x in range(-24, 25, 2):
		for z in range(-24, 25, 2):
			var da := Vector3(x, pl.global_position.y + 0.8, z)
			var strada := 0.0
			while strada < 16.0:
				var p := da + verso * (strada + 1.0)
				var giu := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 1.5)
				giu.exclude = escluso
				var davanti := PhysicsRayQueryParameters3D.create(da + verso * strada, p)
				davanti.exclude = escluso
				if spazio.intersect_ray(giu).is_empty() or not spazio.intersect_ray(davanti).is_empty():
					break
				strada += 1.0
			if strada > libero:
				libero = strada
				meglio = Vector3(x, pl.global_position.y, z)
	print("  rettilineo: %.0f m liberi da %s" % [libero, meglio])
	return meglio


func _fermo(punti : Array, i : int, lento : float) -> bool:
	var meno := INF
	for j in [i - 1, i + 1]:
		if j >= 0 and j < punti.size():
			var d : Vector3 = (punti[j] as Vector3) - (punti[i] as Vector3)
			d.y = 0.0
			meno = minf(meno, d.length())
	return meno < lento
