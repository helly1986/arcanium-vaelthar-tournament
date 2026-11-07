extends SceneTree

## Cancello della MATRICE DELLE INTERAZIONI fra status (docs/18_INTERAZIONI_STATUS.md), con
## un nemico vero e l'imbuto vero dei colpi (_final_damage e _route_statuses).
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_interazioni.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const VITA := 100000

var _falliti := 0


class Colpo extends Resource:
	var power : float = 100.0
	var damage_type : String = "FISICO"


func _ok(cond : bool, cosa : String) -> void:
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _prepara() -> Array:
	root.get_node("SaveManager")._house = "dawnkeep"
	root.get_node("EquipmentLoadout").clear_all()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 15:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	var nemico : CharacterBody3D = null
	for n in get_nodes_in_group("targets"):
		if n != pl and n is CharacterBody3D and n.get("health_system") != null:
			if nemico == null:
				nemico = n
			else:
				n.set_physics_process(false)
	nemico.set_physics_process(false)
	nemico.health_system.total_health = VITA
	nemico.health_system.current_health = VITA
	nemico.health_system.set("_health_f", float(VITA))
	nemico.global_position = pl.global_transform * Vector3(0.0, 0.0, 2.0)
	return [scena, pl, nemico]


## Tutto da capo: nessuno status, nessuna barra, vita piena.
func _pulisci(hs : Node) -> void:
	var host = hs.status_host
	for e in host._effects.values():
		host.cura(e.id)
		if "extra" in e:
			e.extra = 0.0
	hs.set("_health_f", float(hs.total_health))
	hs.current_health = hs.total_health


func _colpo(tipo : String, power : float = 100.0) -> Colpo:
	var c := Colpo.new()
	c.damage_type = tipo
	c.power = power
	return c


func _attivo(host, id : String) -> bool:
	var e = host.get_effect(id)
	return e != null and e.is_active()


func _barra(host, id : String) -> float:
	var e = host.get_effect(id)
	return e.accumulo() if e != null else 0.0


func _proposte(hs : Node) -> void:
	var host = hs.status_host
	var Burn := preload("res://arcanium/systems/status/burn_effect.gd")
	## P1 l'acqua spegne.
	_pulisci(hs)
	host.build_burn(200.0)
	_ok(_attivo(host, "burn"), "brucia")
	host.bagna()
	_ok(not _attivo(host, "burn"), "P1: l'acqua spegne la Bruciatura")
	## P2 il fuoco asciuga e attecchisce a meta'.
	_pulisci(hs)
	host.bagna()
	host.build_burn(40.0)
	_ok(not _attivo(host, "bagnato"), "P2: il fuoco asciuga")
	_ok(is_equal_approx(_barra(host, "burn"), 0.2), "P2: e accumula a meta' (%.2f)" % _barra(host, "burn"))
	_pulisci(hs)
	host.bagna()
	hs._route_statuses(_colpo("FUOCO"))
	_ok(not _attivo(host, "bagnato"), "P2: anche il solo danno di fuoco asciuga")
	## P3 l'acqua gela prima.
	_pulisci(hs)
	host.bagna()
	host.build_frozen(40.0)
	_ok(is_equal_approx(_barra(host, "frozen"), 0.6), "P3: da Bagnato il Congelamento accumula ×1,5")
	## P4 il gelo spegne.
	_pulisci(hs)
	host.build_burn(200.0)
	host.build_frozen(10.0)
	_ok(not _attivo(host, "burn"), "P4: il gelo spegne la Bruciatura")
	## P5 il Ghiacciato eredita.
	_pulisci(hs)
	host.build_frozen(200.0)
	_ok(is_equal_approx(host.damage_multiplier_for("TAGLIO"), 1.2), "Congelato: Taglio ×1,2")
	host.build_frozen(200.0)
	_ok(host.is_ghiacciato(), "Ghiacciato")
	host.cura("frozen")
	_ok(is_equal_approx(host.damage_multiplier_for("TAGLIO"), 1.2), "P5: Taglio ×1,2 anche finito il Congelamento")
	_ok(is_equal_approx(host.damage_multiplier_for("PERFORAZIONE"), 1.2), "P5: Perforazione ×1,2")
	## P6 frantumare.
	host.build_frozen(200.0)
	_ok(is_equal_approx(host.damage_multiplier_for("SCHIANTO"), 2.0), "P6: Schianto ×2 sul Ghiacciato, anche se e' ancora congelato")
	var prima : float = hs.get("_health_f")
	hs._on_damage_signal(_colpo("SCHIANTO"))
	_ok(is_equal_approx(prima - hs.get("_health_f"), 200.0), "P6: il colpo fa il doppio (%.0f)" % (prima - hs.get("_health_f")))
	_ok(not host.is_ghiacciato(), "P6: e il ghiaccio si rompe")
	## P7 scarica nel ghiaccio.
	_pulisci(hs)
	host.build_frozen(200.0)
	host.build_frozen(200.0)
	prima = hs.get("_health_f")
	host.build_shock(500.0)
	_ok(is_equal_approx(prima - hs.get("_health_f"), VITA * 0.25), "P7: lo Shock nel ghiaccio toglie il 25%")
	_ok(not host.is_ghiacciato(), "P7: e chiude il Ghiacciato")
	_ok(host.get_effect("shock").extra > 0.0, "P7: la soglia sale lo stesso")
	## P8 la Frattura amplifica i morsi.
	_pulisci(hs)
	host.build_burn(200.0)
	prima = hs.get("_health_f")
	await create_timer(1.05).timeout
	var senza : float = prima - hs.get("_health_f")
	_pulisci(hs)
	host.apply_fracture(1.35, 15.0)
	host.build_burn(200.0)
	prima = hs.get("_health_f")
	await create_timer(1.05).timeout
	var con : float = prima - hs.get("_health_f")
	_ok(absf(con / senza - 1.35) < 0.02, "P8: la Frattura amplifica la Bruciatura (×%.2f)" % (con / senza))
	## P9 e P10 gli spiriti.
	_pulisci(hs)
	var spiriti = host.affida_spiriti(1000.0, null, 0.0)
	_ok(is_equal_approx(spiriti._nutrimento(), 1.0), "Spiriti da soli: ×1")
	host.build_laceration(500.0)
	_ok(is_equal_approx(spiriti._nutrimento(), 1.25), "P9: il sangue li chiama")
	host.cura("laceration")
	host.build_burn(200.0)
	_ok(is_equal_approx(spiriti._nutrimento(), 1.0), "P10: il fuoco rosso non li nutre")
	host.cura("burn")
	host.build_burn(500.0, true)
	_ok(is_equal_approx(spiriti._nutrimento(), 1.25), "P10: quello spirituale si'")
	## P11 fulmine sull'acqua.
	_pulisci(hs)
	host.bagna()
	_ok(is_equal_approx(host.damage_multiplier_for("FULMINE"), 1.25), "P11: Fulmine su Bagnato ×1,25")
	_ok(is_equal_approx(host.damage_multiplier_for("TAGLIO"), 1.0), "P11: gli altri no")
	## P12 il freddo irrigidisce.
	var guardia = host.get_effect("poise_break")
	if guardia != null:
		_pulisci(hs)
		guardia.meter = 0.0
		host.build_poise(10.0)
		var asciutta : float = guardia.meter
		guardia.meter = 0.0
		host.build_frozen(200.0)
		host.build_poise(10.0)
		_ok(is_equal_approx(guardia.meter, asciutta * 1.5), "P12: da Congelato la Guardia sale ×1,5")
		guardia.meter = 0.0
	## D3 il fuoco spirituale.
	_pulisci(hs)
	host.build_burn(50.0, true)
	_ok(is_equal_approx(_barra(host, "burn"), 0.35), "D3: il fuoco spirituale accumula piu' lento")
	_ok(host.get_effect("burn").color == Burn.TEAL, "D3: e resta teal")
	host.build_burn(500.0, true)
	prima = hs.get("_health_f")
	await create_timer(1.05).timeout
	var teal : float = prima - hs.get("_health_f")
	_ok(absf(teal / senza - 1.5) < 0.02, "D3: ma fa piu' danno (×%.2f)" % (teal / senza))
	## D8 il Sacro purifica.
	_pulisci(hs)
	host.affida_spiriti(1000.0, null, 0.0)
	host.build_frozen(50.0)
	host.build_laceration(50.0)
	host.build_shock(50.0)
	hs._route_statuses(_colpo("SACRO"))
	_ok(not _attivo(host, "spiriti"), "D8: il Sacro scaccia gli Spiriti")
	_ok(_barra(host, "frozen") == 0.0 and _barra(host, "laceration") == 0.0 and _barra(host, "shock") == 0.0,
			"D8: e annulla gli accumuli")
	_pulisci(hs)


func _stati_nuovi(hs : Node) -> void:
	var host = hs.status_host
	## D4 Veleno.
	_pulisci(hs)
	hs._route_statuses(_colpo("VELENO"))
	_ok(_barra(host, "veleno") > 0.0, "D4: ogni colpo di Veleno accumula")
	host.build_veleno(500.0)
	_ok(_attivo(host, "veleno"), "D4: il Veleno scatta")
	var prima : float = hs.get("_health_f")
	await create_timer(1.1).timeout
	_ok(hs.get("_health_f") < prima, "D4: e morde")
	hs.set("_health_f", 1000.0)
	hs.heal(100.0)
	_ok(is_equal_approx(hs.get("_health_f"), 1050.0), "D4: le cure valgono la meta'")
	## D5 Sacro.
	_pulisci(hs)
	hs._route_statuses(_colpo("SACRO"))
	_ok(_barra(host, "accecato") > 0.0, "D5: ogni colpo di Sacro accumula Blinded by Light")
	prima = hs.get("_health_f")
	host.build_accecato(500.0)
	_ok(host.is_accecato(), "D5: scatta")
	_ok(prima - hs.get("_health_f") >= VITA * 0.15, "D5: ingente danno tutto insieme (%.0f)" % (prima - hs.get("_health_f")))
	_ok(is_equal_approx(host.get_effect("accecato").duration, 10.0), "D5: dura 10 s")
	_pulisci(hs)


func _alla_cieca(nemico : Node, pl : Node) -> void:
	var hs : Node = nemico.health_system
	nemico.set_physics_process(true)
	await create_timer(0.2).timeout
	_ok(nemico.target == pl, "ci vede: il bersaglio e' il giocatore")
	hs.status_host.build_accecato(500.0)
	await physics_frame
	await physics_frame
	var punti := {}
	var verso_il_giocatore := 0
	for k in 180:
		await physics_frame
		if nemico.target == pl:
			verso_il_giocatore += 1
		elif is_instance_valid(nemico.target):
			punti[nemico.target.global_position.snapped(Vector3.ONE * 0.1)] = true
	_ok(verso_il_giocatore == 0, "accecato non punta piu' il giocatore (%d fotogrammi)" % verso_il_giocatore)
	_ok(punti.size() >= 2, "e mena a caso (%d punti)" % punti.size())
	hs.status_host.cura("accecato")
	await physics_frame
	await physics_frame
	_ok(nemico.target == pl, "guarito torna a vedere")
	nemico.set_physics_process(false)
	_pulisci(hs)


func _giocatore(pl : Node) -> void:
	var hs : Node = pl.health_system
	hs.total_health = VITA
	var host = hs.status_host
	_pulisci(hs)
	## D7 Congelamento e Ghiacciato.
	host.build_frozen(500.0)
	_ok(_attivo(host, "frozen"), "D7: il giocatore si congela")
	_ok(is_equal_approx(host.moltiplicatore_velocita(), 0.4), "D7: e rallenta")
	host.build_frozen(500.0)
	_ok(host.is_ghiacciato(), "D7: e arriva al Ghiacciato")
	await physics_frame
	await physics_frame
	_ok(pl.is_stunned(), "D7: i comandi non passano")
	_ok(not pl.animation_tree.active, "D7: le clip sono ferme")
	var dove : Vector3 = pl.global_position
	pl.velocity = Vector3(5.0, 0.0, 0.0)
	for k in 10:
		await physics_frame
	_ok(Vector2(pl.global_position.x - dove.x, pl.global_position.z - dove.z).length() < 0.01, "D7: non si muove")
	var prima : float = hs.get("_health_f")
	await create_timer(1.1).timeout
	_ok(hs.get("_health_f") < prima, "D7: e perde vita")
	hs._route_statuses(_colpo("FUOCO"))
	await physics_frame
	await physics_frame
	_ok(not host.is_ghiacciato() and pl.animation_tree.active and not pl.is_stunned(), "D7: il fuoco lo scioglie e riparte")
	_pulisci(hs)
	## D5 il lock-on.
	var lock : Node = pl.lock_on_system
	pl.set_strafe_targeting()
	_ok(pl.strafing and lock.is_locked(), "ci vede: il lock-on aggancia")
	host.build_accecato(500.0)
	await physics_frame
	await physics_frame
	_ok(not pl.strafing and not lock.is_locked(), "D5: accecato perde il lock-on")
	pl.set_strafe_targeting()
	_ok(not pl.strafing and not lock.is_locked(), "D5: e non puo' riprenderlo")
	host.cura("accecato")
	pl.set_strafe_targeting()
	_ok(pl.strafing, "guarito lo riprende")
	pl.set_strafe_targeting()
	_pulisci(hs)


func _boss() -> void:
	var boss : Node = load("res://arcanium/characters/senza_nome.tscn").instantiate()
	root.add_child(boss)
	await process_frame
	await process_frame
	var host = boss.health_system.status_host
	_ok(is_equal_approx(host.accumulo_mult, 0.5), "D1: il boss resiste agli accumuli")
	host.build_shock(50.0)
	_ok(is_equal_approx(host.get_effect("shock").accumulo(), 0.25), "D1: la barra sale a meta'")
	host.cura("shock")
	var esenti : Array[String] = ["shock"]
	host.accumuli_esenti = esenti
	host.build_shock(50.0)
	_ok(is_equal_approx(host.get_effect("shock").accumulo(), 0.5), "D1: salvo chi e' vulnerabile al fulmine")
	host.build_frozen(50.0)
	_ok(is_equal_approx(host.get_effect("frozen").accumulo(), 0.25), "D1: e il resto no")
	boss.free()


## P13: i colpi delle piastre portano il loro stato (colpo_trappola.gd).
func _piastre(hs : Node) -> void:
	var Trappola := preload("res://arcanium/levels/dungeon/colpo_trappola.gd")
	var host = hs.status_host
	_pulisci(hs)
	var c : RefCounted = Trappola.new()
	c.burn_buildup = 35.0
	c.damage_type = "FUOCO"
	hs._route_statuses(c)
	_ok(_barra(host, "burn") > 0.0, "P13: la piastra di fuoco accumula Bruciatura")
	c = Trappola.new()
	c.shock_buildup = 35.0
	hs._route_statuses(c)
	_ok(_barra(host, "shock") > 0.0, "P13: quella di fulmine Shock")
	c = Trappola.new()
	c.poison_buildup = 40.0
	hs._route_statuses(c)
	_ok(_barra(host, "veleno") > 0.0, "P13: quella di veleno Veleno")
	_pulisci(hs)


func _init() -> void:
	await process_frame
	var s : Array = await _prepara()
	var pl : Node = s[1]
	var nemico : Node = s[2]
	await _proposte(nemico.health_system)
	await _stati_nuovi(nemico.health_system)
	await _piastre(nemico.health_system)
	await _alla_cieca(nemico, pl)
	await _giocatore(pl)
	await _boss()
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
