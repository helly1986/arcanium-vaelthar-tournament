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


func _init() -> void:
	await process_frame
	var s : Array = await _prepara()
	var nemico : Node = s[2]
	await _proposte(nemico.health_system)
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
