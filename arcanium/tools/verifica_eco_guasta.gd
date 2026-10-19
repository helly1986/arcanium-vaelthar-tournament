extends Node3D

## L'Eco Radicata Guasta contro il giocatore vero, nell'arena di prova.
##
##   "C:/Godot/Godot_v4.7.1-stable_win64_console.exe" --path . --rendering-method mobile res://arcanium/tools/verifica_eco_guasta.tscn -- [cartella_scatti]
##
## Nell'arena di prova (arena_prova.tscn: l'arena del prologo col solo
## giocatore), l'Eco a 7 m. Kalvorn e i suoi posti (conca, percorso, nido della
## quest) non ci sono piu': restano le domande sull'Eco. Domande:
##   1. nasce col corpo di spirito (shader) e con le sue clip?
##   2. in 40 s usa tutte e tre le mosse, e ognuna fa quello che dice —
##      artigli e radice feriscono, il sorso toglie Arcanium e la cura?
##   3. la radice si SCHIVA: uscendo dal cerchio dopo che e' apparso, niente
##      danno; e Radice e sorso sono IMPARABILI (entrano in parata e in
##      guardia), gli Artigli no;
##   4. muore dissolvendosi, e sparisce;
##   5. l'Eco EVOCATA (la tua) ha lo stesso corpo e lancia la Radice sui nemici.
## Con una cartella, fotografa ogni mossa all'istante del contatto.
##
## ⚠️ MAI --headless: le catture vogliono il renderer vero. Il giocatore e' immortale: si cura a ogni
## fotogramma, e il danno si conta PRIMA della cura.

const LIVELLO := "res://arcanium/levels/arena_prova.tscn"
const ECO := "res://arcanium/characters/eco_radicata_guasta.tscn"
const SpellCaster := preload("res://arcanium/systems/spells/spell_caster.gd")

var _esito := 0
var _cartella := ""
var _fx := {"ArtigliEtere": 0, "RadiceCheAfferra": 0, "SorsoEco": 0}
var _colpi := 0
var _pl : Node3D
var _hp_prima := -1.0
var _bevuto_in_parata := 0.0


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
	## Nell'arena di prova, lontano dalle colonne: l'Eco nasce a 7 m verso est.
	var centro := Vector3(-1.0, 0.0, 7.0)
	centro.y = _suolo(centro) + 0.1
	_pl.global_position = centro
	## Una camera VICINA e ferma, di tre quarti sul duello: quella di gioco sta
	## a venti metri e degli effetti non si vede niente.
	var cam := get_viewport().get_camera_3d()
	if cam != null and _cartella != "":
		cam.top_level = true
		cam.process_mode = Node.PROCESS_MODE_DISABLED
		if cam.get_parent() != null:
			cam.get_parent().process_mode = Node.PROCESS_MODE_DISABLED
		cam.look_at_from_position(centro + Vector3(3.5, 5.5, 7.5), centro + Vector3(3.5, 0.6, 0.0), Vector3.UP)
	await _attendi(3.0)

	## 1. Nasce.
	var eco := (load(ECO) as PackedScene).instantiate() as Node3D
	lv.add_child(eco)
	var p_eco := centro + Vector3(7.0, 0.0, 0.0)
	p_eco.y = _suolo(p_eco) + 0.05
	eco.global_position = p_eco
	await _attendi(0.5)
	var ap := eco.get("anim_player") as AnimationPlayer
	_ok(ap != null and ap.has_animation("artigli") and ap.has_animation("radice") and ap.has_animation("beve"),
		"l'Eco ha le sue clip (artigli, radice, beve)")
	var corpo : Node = eco.get("model")
	var mats : Array = corpo.get("_materiali") if corpo != null else []
	_ok(mats.size() > 0 and (mats[0] as ShaderMaterial).shader != null, "ha il corpo di spirito (%d materiali a shader)" % mats.size())

	## 2. Combatte: 40 s, giocatore fermo al centro.
	var vit = _pl.get("vitals")
	var mosse := {}
	var arc_bevuto := 0.0
	var t := 0.0
	var ultimo_contatto := {}
	while t < 40.0 and is_instance_valid(eco):
		var arc0 : float = float(vit.arcanium) if vit != null else 0.0
		await _attendi(0.1)
		t += 0.1
		_pl.global_position = centro
		if vit != null:
			arc_bevuto += maxf(arc0 - float(vit.arcanium), 0.0)
			vit.refill_all()
		var m = eco.get("_active_move")
		if m != null:
			mosse[m.anim] = true
			if _cartella != "" and not ultimo_contatto.has(m.anim):
				var cont : float = eco.EcoClip.CONTATTI[m.anim][0]
				if float(eco.call("_clip_pos")) >= cont - 0.02:
					ultimo_contatto[m.anim] = true
					await _scatta("eco_%s" % m.anim)
	print("      mosse usate: %s; colpi al giocatore %d; Arcanium bevuto %.1f; effetti %s" % [mosse.keys(), _colpi, arc_bevuto, _fx])
	_ok(mosse.has("artigli") and mosse.has("radice") and mosse.has("beve"), "usa tutte e tre le mosse")
	_ok(_fx["ArtigliEtere"] > 0 and _fx["RadiceCheAfferra"] > 0 and _fx["SorsoEco"] > 0, "ogni mossa ha il suo effetto")
	_ok(_colpi > 0, "artigli e radice feriscono (%d colpi)" % _colpi)
	_ok(arc_bevuto > 0.0, "il sorso toglie Arcanium (%.1f)" % arc_bevuto)

	## 3. La radice si schiva: si forza la mossa, e appena appare il cerchio il
	## giocatore esce di 3 m.
	var colpi0 := _colpi
	var radici0 : int = _fx["RadiceCheAfferra"]
	_pl.global_position = centro
	eco.global_position = p_eco
	await _attendi(2.5)
	eco.call("debug_force_move", "R1")
	var t3 := 0.0
	while t3 < 3.0 and _fx["RadiceCheAfferra"] == radici0:
		await _attendi(0.05)
		t3 += 0.05
		_pl.global_position = centro
	var fuori := centro + Vector3(0.0, 0.0, 3.2)
	fuori.y = _suolo(fuori) + 0.1
	var colpi_prima := _colpi
	var t4 := 0.0
	while t4 < 1.6:
		await _attendi(0.05)
		t4 += 0.05
		_pl.global_position = fuori
	_ok(_fx["RadiceCheAfferra"] > radici0, "la radice e' partita (cerchio apparso)")
	_ok(_colpi == colpi_prima, "uscendo dal cerchio la radice non colpisce (%d colpi)" % (_colpi - colpi_prima))

	## 3b. IMPARABILI e IMPARRIABILI: col giocatore in parata perfetta e in
	## guardia, la Radice entra e il sorso beve; gli Artigli invece si parano.
	_ok(await _in_parata(eco, "R1", centro, p_eco) > 0, "la Radice che Afferra entra anche in parata e in guardia")
	await _in_parata(eco, "B1", centro, centro + Vector3(2.0, 0.0, 0.0))
	_ok(_bevuto_in_parata > 0.0, "l'Eco che Beve beve anche in parata e in guardia (%.1f)" % _bevuto_in_parata)
	_ok(await _in_parata(eco, "A1", centro, centro + Vector3(1.6, 0.0, 0.0)) == 0, "gli Artigli d'Etere invece si parano")

	## 4. Muore.
	var hs = eco.get("health_system")
	if hs != null and hs.has_method("apply_damage"):
		hs.apply_damage(999.0, "FISICO")
	elif eco.has_method("hit"):
		pass
	var t5 := 0.0
	var dissolta := false
	while t5 < 6.0 and is_instance_valid(eco):
		await _attendi(0.1)
		t5 += 0.1
		if is_instance_valid(eco) and float(eco.get("model").get("dissolvi")) > 0.5:
			dissolta = true
	_ok(dissolta, "muore dissolvendosi")
	_ok(not is_instance_valid(eco), "e sparisce (%.1f s)" % t5)

	## 5. L'Eco EVOCATA, la tua: stesso corpo, la Radice contro i nemici. Si
	## istanzia come la istanzia lo spell_caster (campi dalla risorsa prima di
	## add_child), accanto al giocatore, con una Guasta ferma a 4 m.
	var ris : Resource = load("res://arcanium/resources/summons/eco_radicata.tres")
	var minion := (ris.get("minion_scene") as PackedScene).instantiate() as Node3D
	for campo in SpellCaster.CAMPI_MINION:
		if campo in ris and campo in minion:
			minion.set(campo, ris.get(campo))
	lv.add_child(minion)
	minion.global_position = centro + Vector3(1.2, 0.0, 0.0)
	var bersaglio := (load(ECO) as PackedScene).instantiate() as Node3D
	bersaglio.set("ai_enabled", false)
	lv.add_child(bersaglio)
	var pb := centro + Vector3(5.0, 0.0, 0.0)
	pb.y = _suolo(pb) + 0.05
	bersaglio.global_position = pb
	var radici_prima : int = _fx["RadiceCheAfferra"]
	var hs_b = bersaglio.get("health_system")
	await _attendi(0.5)
	var vita0 : float = float(hs_b.get("current_health"))
	var t6 := 0.0
	var scattata := false
	while t6 < 8.0 and float(hs_b.get("current_health")) >= vita0:
		await _attendi(0.1)
		t6 += 0.1
		_pl.global_position = centro
		if _cartella != "" and not scattata and _fx["RadiceCheAfferra"] > radici_prima:
			scattata = true
			await _attendi(0.4)
			await _scatta("eco_evocata")
	var corpo_m = minion.get("_corpo")
	_ok(corpo_m != null and (corpo_m.get("_materiali") as Array).size() > 0, "l'Eco evocata ha il corpo di spirito")
	_ok(_fx["RadiceCheAfferra"] > radici_prima, "l'Eco evocata lancia la Radice sul nemico")
	_ok(float(hs_b.get("current_health")) < vita0, "e la radice lo ferisce (%.0f -> %.0f in %.1f s)" % [vita0, float(hs_b.get("current_health")), t6])

	print("\n%s" % ("TUTTO A POSTO" if _esito == 0 else "QUALCOSA NON VA"))
	get_tree().quit(_esito)


## Forza una mossa col giocatore FERMO in parata perfetta e in guardia, e
## conta i colpi che entrano. L'Eco si mette dove serve alla mossa.
func _in_parata(eco : Node3D, mossa : String, dove_pl : Vector3, dove_eco : Vector3) -> int:
	_pl.global_position = dove_pl
	dove_eco.y = _suolo(dove_eco) + 0.05
	eco.global_position = dove_eco
	eco.look_at(Vector3(dove_pl.x, eco.global_position.y, dove_pl.z), Vector3.UP)
	eco.rotate_y(PI)
	var vit = _pl.get("vitals")
	## La mossa forzata parte solo a Eco libera: si riprova finche' non parte.
	var partita := false
	var tf := 0.0
	while not partita and tf < 6.0:
		await _attendi(0.1)
		tf += 0.1
		_pl.global_position = dove_pl
		partita = bool(eco.call("debug_force_move", mossa))
	if not partita:
		push_error("la mossa %s non e' partita" % mossa)
	if vit != null:
		vit.refill_all()
	var arc0 : float = float(vit.arcanium) if vit != null else 0.0
	var c0 := _colpi
	var t := 0.0
	while t < 3.5:
		_pl.set("guarding", true)
		_pl.set("parry_active", true)
		_pl.global_position = dove_pl
		await _attendi(0.05)
		t += 0.05
	_pl.set("guarding", false)
	_pl.set("parry_active", false)
	_bevuto_in_parata = arc0 - (float(vit.arcanium) if vit != null else 0.0)
	return _colpi - c0


func _nuovo(n : Node) -> void:
	for k in _fx:
		if str(n.name).begins_with(k):
			_fx[k] += 1


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
