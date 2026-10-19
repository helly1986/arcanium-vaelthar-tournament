extends Node3D

## Il Mago Guerriero Sylvorn contro il giocatore vero, nell'arena di prova.
##
##   "C:/Godot/Godot_v4.7.1-stable_win64_console.exe" --path . --rendering-method mobile res://arcanium/tools/verifica_mago_in_campo.tscn -- [cartella_scatti]
##
## Le mosse una per una le collauda `verifica_mago.gd` (headless, a mano). Qui
## si chiede cio' che solo il gioco vero dice: nell'arena di prova
## (arena_prova.tscn), col giocatore fermo e il Mago a 11 m,
##   1. da solo, in 45 s, sceglie RADICI e RICHIAMO, i cerchi appaiono e le Eco
##      escono — e combattono (l'Eco evocata usa le sue mosse);
##   2. le radici feriscono chi resta fermo;
##   3. chi gli va addosso prende la RESPINTA;
##   4. e lui si gira e riprende la distanza.
## Con una cartella, fotografa ogni mossa all'istante del contatto.
##
## ⚠️ MAI --headless: le catture vogliono il renderer vero. Il giocatore e' immortale: si cura a ogni
## fotogramma, e il danno si conta PRIMA della cura.

const LIVELLO := "res://arcanium/levels/arena_prova.tscn"
const MAGO := "res://arcanium/characters/sylvorn_mago.tscn"

var _esito := 0
var _cartella := ""
var _radici := 0
var _eco_nate : Array = []
var _colpi := 0
var _pl : Node3D
var _hp_prima := -1.0


func _ok(cond : bool, testo : String) -> void:
	print(("ok    " if cond else "FAIL  ") + testo)
	if not cond:
		_esito = 1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_cartella = args[0] if args.size() > 0 else ""
	var lv : Node = (load(LIVELLO) as PackedScene).instantiate()
	add_child(lv)
	get_tree().node_added.connect(_nuovo)
	await _attendi(1.0)
	_pl = get_tree().get_first_node_in_group("player") as Node3D
	## Nell'arena di prova, lontano dalle colonne: il Mago a 11 m verso est.
	var centro := Vector3(-1.0, 0.0, 7.0)
	centro.y = _suolo(centro) + 0.1
	_pl.global_position = centro
	var cam := get_viewport().get_camera_3d()
	if cam != null and _cartella != "":
		cam.top_level = true
		cam.process_mode = Node.PROCESS_MODE_DISABLED
		if cam.get_parent() != null:
			cam.get_parent().process_mode = Node.PROCESS_MODE_DISABLED
		cam.look_at_from_position(centro + Vector3(5.5, 8.5, 12.0), centro + Vector3(5.5, 0.6, 0.0), Vector3.UP)
	await _attendi(2.0)

	var mago := (load(MAGO) as PackedScene).instantiate() as Node3D
	lv.add_child(mago)
	var pm := centro + Vector3(11.0, 0.0, 0.0)
	pm.y = _suolo(pm) + 0.05
	mago.global_position = pm
	await _attendi(0.5)

	## 1-2. Combatte: 45 s, giocatore fermo al centro.
	var mosse := {}
	var scattate := {}
	var t := 0.0
	while t < 45.0 and is_instance_valid(mago):
		await _attendi(0.1)
		t += 0.1
		_pl.global_position = centro
		var m = mago.get("_active_move")
		if m != null:
			mosse[m.id] = true
			if _cartella != "" and not scattate.has(m.id):
				var c : PackedFloat32Array = mago.call("_contact_times", m)
				if float(mago.call("_clip_pos")) >= c[0] - 0.35:
					scattate[m.id] = true
					await _scatta("mago_%s" % m.id)
	var eco_vive := _eco_nate.filter(func(e): return is_instance_valid(e))
	var eco_in_mossa := 0
	for e in eco_vive:
		if e.get("_active_move") != null or e.get("_state") != 0:
			eco_in_mossa += 1
	print("      mosse usate: %s; cerchi di radice %d; Eco nate %d; colpi al giocatore %d"
		% [mosse.keys(), _radici, _eco_nate.size(), _colpi])
	_ok(mosse.has("RADICI") and mosse.has("RICHIAMO"), "da solo sceglie RADICI e RICHIAMO")
	_ok(_radici >= 3, "i cerchi delle radici appaiono (%d)" % _radici)
	_ok(_eco_nate.size() >= 2 and _eco_nate.size() <= 3 + 3, "le Eco escono (%d)" % _eco_nate.size())
	_ok(eco_vive.size() <= int(mago.get("richiamo_max")), "mai piu' del tetto vive insieme (%d)" % eco_vive.size())
	_ok(eco_in_mossa > 0, "e combattono (%d su %d non sono ferme)" % [eco_in_mossa, eco_vive.size()])
	_ok(_colpi > 0, "chi resta fermo e' ferito (%d colpi)" % _colpi)

	## 2b. La FRUSTA: via le Eco, il giocatore fermo a 5 m, due frustate forzate.
	for e in eco_vive:
		e.queue_free()
	await _attendi(0.5)
	var a5 := mago.global_position + (centro - mago.global_position).normalized() * 5.0
	a5.y = _suolo(a5) + 0.1
	var sh = _pl.get("health_system").get("status_host") if _pl.get("health_system") != null else null
	var scatti := 0
	var c_fr := _colpi
	for giro in 2:
		var ok_f := false
		var tf2 := 0.0
		while not ok_f and tf2 < 10.0:
			await _attendi(0.1)
			tf2 += 0.1
			_pl.global_position = a5
			ok_f = bool(mago.call("debug_force_move", "FRUSTA"))
		var tt := 0.0
		while tt < 3.2:
			await _attendi(0.05)
			tt += 0.05
			_pl.global_position = a5
			var lac = sh.get_effect("laceration") if sh != null else null
			if lac != null and lac.is_active():
				scatti = 1
			if _cartella != "" and giro == 0 and mago.get("_active_move") != null:
				var pc : float = float(mago.call("_clip_pos"))
				if not scattate.has("FRUSTA_carica") and pc >= 1.0:
					scattate["FRUSTA_carica"] = true
					await _scatta("mago_FRUSTA_carica")
				elif not scattate.has("FRUSTA") and pc >= 1.62:
					scattate["FRUSTA"] = true
					await _scatta("mago_FRUSTA")
		var lac_g = sh.get_effect("laceration") if sh != null else null
		print("      frustata %d: barra %s, attiva %s, status_host %s" % [giro + 1,
			str(lac_g.meter) if lac_g else "-", str(lac_g.is_active()) if lac_g else "-", sh])
	_ok(_colpi > c_fr, "la Frusta di Spine colpisce chi resta fermo (%d colpi)" % (_colpi - c_fr))
	_ok(scatti == 1, "e due frustate fanno scattare la Lacerazione")

	## 3-4. Addosso a lui: il giocatore a 2 m, si forza la Respinta.
	var vicino := mago.global_position + (centro - mago.global_position).normalized() * 2.0
	vicino.y = _suolo(vicino) + 0.1
	var c0 := _colpi
	var partita := false
	var tf := 0.0
	while not partita and tf < 8.0:
		await _attendi(0.1)
		tf += 0.1
		_pl.global_position = vicino
		partita = bool(mago.call("debug_force_move", "RESPINTA"))
	_ok(partita, "la Respinta parte")
	## Chi gli sta addosso lo TALLONA: resta a 2 m da lui fino al contatto,
	## anche se lui si sposta. Dopo il contatto lo si lascia andare.
	var inizio := mago.global_position
	var spostato := 0.0
	var spinto := 0.0
	var t3 := 0.0
	while t3 < 2.5:
		if float(mago.call("_clip_pos")) < 1.3 and mago.get("_active_move") != null:
			var verso := _pl.global_position - mago.global_position
			verso.y = 0.0
			var q := mago.global_position + verso.normalized() * 2.0
			q.y = _suolo(q) + 0.1
			_pl.global_position = q
			spostato = maxf(spostato, Vector2(mago.global_position.x - inizio.x, mago.global_position.z - inizio.z).length())
		await _attendi(0.05)
		t3 += 0.05
		if _pl.has_method("spinta_in_corso"):
			spinto = maxf(spinto, (_pl.call("spinta_in_corso") as Vector3).length())
		if _cartella != "" and not scattate.has("RESPINTA") and float(mago.call("_clip_pos")) >= 1.25:
			scattate["RESPINTA"] = true
			await _scatta("mago_RESPINTA")
	_ok(_colpi > c0, "chi gli sta addosso prende la Respinta (%d colpi)" % (_colpi - c0))
	_ok(spinto > 3.0, "e viene spinto via (%.1f m/s)" % spinto)
	_ok(spostato < 1.0, "e lui, mentre la carica, sta fermo (%.2f m)" % spostato)

	var da_lui := Vector2(mago.global_position.x - _pl.global_position.x, mago.global_position.z - _pl.global_position.z).length()
	var fermo := _pl.global_position
	var t4 := 0.0
	var massimo := da_lui
	while t4 < 6.0:
		await _attendi(0.1)
		t4 += 0.1
		_pl.global_position = fermo
		massimo = maxf(massimo, Vector2(mago.global_position.x - fermo.x, mago.global_position.z - fermo.z).length())
	_ok(massimo > da_lui + 2.0, "e lui riprende la distanza (da %.1f a %.1f m)" % [da_lui, massimo])

	## 5. La stoffa (docs/05 §4-quater): a distanza di combattimento deve
	## simulare. La prima soglia (22 m dalla CAMERA) non si accendeva mai: la
	## camera isometrica sta a ~29 m dal giocatore, a 26 m dal mago.
	var st : Node = mago.get_node_or_null("StoffaSimulata")
	_ok(st != null, "il Mago porta la StoffaSimulata")
	if st != null:
		var d := _pl.global_position.distance_to(mago.global_position)
		_ok(st.attiva(), "col giocatore a %.1f m la stoffa simula (soglia %.0f m)" % [d, st.distanza_attiva])

	print("\n%s" % ("TUTTO A POSTO" if _esito == 0 else "QUALCOSA NON VA"))
	get_tree().quit(_esito)


func _nuovo(n : Node) -> void:
	if str(n.name).begins_with("RadiceCheAfferra"):
		_radici += 1
	if str(n.scene_file_path).ends_with("eco_radicata_guasta.tscn"):
		_eco_nate.append(n)


## Immortale: prima della cura si guarda se ha perso vita (un colpo).
func _attendi(s : float) -> void:
	var fine := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < fine:
		await get_tree().physics_frame
		if _pl != null and is_instance_valid(_pl) and _pl.get("health_system") != null:
			var hs = _pl.health_system
			var hp : float = float(hs.get("current_health"))
			if _hp_prima >= 0.0 and hp < _hp_prima - 0.01:
				_colpi += 1
			hs.heal(1000.0)
			_hp_prima = float(hs.get("current_health"))


func _scatta(nome : String) -> void:
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [_cartella, nome]
	get_viewport().get_texture().get_image().save_png(p)
	print("      scatto ", p)


func _suolo(p : Vector3) -> float:
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(p + Vector3(0, 60, 0), p - Vector3(0, 60, 0), 1))
	return (hit["position"] as Vector3).y if not hit.is_empty() else p.y
