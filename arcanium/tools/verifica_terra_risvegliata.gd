extends SceneTree

## Cancello di TERRA RISVEGLIATA, la Lucida Tecnica della vanga di Aurin, col player vero
## nel dungeon e un nemico vero:
##   1. la vanga la dichiara, e lanciarla costa quello che dice;
##   2. all'impatto gli spiriti scelgono il bersaglio PIU' VICINO fra quelli visibili, non
##      chi e' lontano, e nemmeno i propri;
##   3. addosso a lui rallentano davvero il suo movimento, e consumano per 5 secondi;
##   4. se non muore, niente premio: il danno in totale e' quello dell'arma per danno_mult;
##   5. se muore per gli spiriti, Aurin riprende tutto l'Arcanium speso e la meta' del danno
##      inflitto come vita; a vita piena non va oltre il massimo.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_terra_risvegliata.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const VANGA := "res://arcanium/resources/weapons/vanga_raccoglitore.tres"

var _falliti := 0


class Bersaglio extends Node3D:
	func hit(_da, _info) -> void:
		pass


func _ok(cond : bool, cosa : String) -> void:
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _onda(scena : Node, pl : Node3D, t : Resource, potenza : float) -> Node3D:
	var o : Node3D = t.impatto.instantiate()
	o.lanciatore = pl
	o.potenza = potenza
	o.costo = t.costo
	o.transform = Transform3D(pl.global_transform.basis, pl.global_position)
	scena.add_child(o)
	return o


func _init() -> void:
	await process_frame
	root.get_node("SaveManager")._house = "verath"
	root.get_node("EquipmentLoadout").clear_all()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 15:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	var caster : Node = pl.lucida_tecnica_caster
	var vitali : Node = pl.vitals
	var vanga : Resource = load(VANGA)

	## 1.
	var t : Resource = caster.tecnica_corrente()
	_ok(t != null and t == vanga.lucida_tecnica and t.name == "Terra Risvegliata", "la vanga insegna la tecnica")
	var arc0 : float = vitali.arcanium
	_ok(caster.lancia(), "il gesto parte")
	_ok(is_equal_approx(arc0 - vitali.arcanium, t.costo), "ha speso %.0f Arcanium" % t.costo)
	var onde := []
	var attesa := 0.0
	while attesa < 2.5:
		await physics_frame
		attesa += 1.0 / 60.0
		for n in scena.get_children():
			if String(n.name).begins_with("TerraRisvegliata") and not onde.has(n):
				onde.append(n)
	_ok(onde.size() == 1, "all'impatto nasce un'ondata sola (%d)" % onde.size())

	## Un nemico vero, lontano da tutto il resto.
	var nemico : CharacterBody3D = null
	for n in get_nodes_in_group("targets"):
		if n != pl and n is CharacterBody3D and n.get("health_system") != null:
			nemico = n
			break
	if nemico == null:
		_ok(false, "nessun nemico vero nel dungeon")
		quit(1)
		return
	## Tutti fermi: un altro che insegue il player diventerebbe lui il piu' vicino.
	for n in get_nodes_in_group("targets"):
		if n != pl and n is CharacterBody3D:
			n.set_physics_process(false)
			if n != nemico:
				n.global_position += Vector3.UP * 50.0
	var salute : Node = nemico.health_system
	salute.total_health = 2000
	salute.current_health = 2000
	salute.set("_health_f", 2000.0)
	var vicino_a : Vector3 = pl.global_transform * Vector3(0.0, 0.0, 3.0)
	nemico.global_position = vicino_a

	## 2. Il piu' vicino: un altro, finto, sta piu' lontano; un amico sta piu' vicino.
	var lontano := Bersaglio.new()
	scena.add_child(lontano)
	lontano.add_to_group("targets")
	lontano.global_position = pl.global_transform * Vector3(0.0, 0.0, 6.0)
	var amico := Bersaglio.new()
	scena.add_child(amico)
	amico.add_to_group("targets")
	amico.add_to_group("player")
	amico.global_position = pl.global_transform * Vector3(0.0, 0.0, 1.0)
	var o := _onda(scena, pl, t, 100.0)
	_ok(o._bersaglio == nemico, "sceglie il piu' vicino, non i propri e non chi e' lontano")

	## 3.
	var host : Node = salute.status_host
	var aspetta := 0.0
	while aspetta < 3.0 and (host.get_effect("spiriti") == null or not host.get_effect("spiriti").is_active()):
		await physics_frame
		aspetta += 1.0 / 60.0
	var spiriti = host.get_effect("spiriti")
	_ok(spiriti != null and spiriti.is_active(), "gli spiriti arrivano e lo prendono (dopo %.2f s)" % aspetta)
	_ok(host.moltiplicatore_velocita() < 1.0, "il suo moltiplicatore di velocita' scende a %.2f" % host.moltiplicatore_velocita())
	## Il movimento vero: stessa velocita' chiesta, meno strada.
	nemico.velocity = Vector3(2.0, 0.0, 0.0)
	nemico._scorri()
	var reale : Vector3 = nemico.get_real_velocity()
	_ok(is_equal_approx(nemico.velocity.x, 2.0) and absf(reale.x) < 2.0 * host.moltiplicatore_velocita() + 0.05,
			"si muove piu' piano davvero (chiede 2,0 m/s, va a %.2f)" % absf(reale.x))

	## 4.
	var dopo_il_morso : float = float(salute.current_health)
	var quanto_prima : float = vitali.arcanium
	await create_timer(5.5).timeout
	var perso := 2000.0 - float(salute.current_health)
	_ok(not spiriti.is_active(), "dopo 5 secondi se ne vanno")
	_ok(absf(perso - 100.0) < 2.0, "il danno in totale e' quello chiesto (%.1f su 100)" % perso)
	_ok(is_equal_approx(vitali.arcanium, minf(vitali.max_arcanium, quanto_prima)) or vitali.arcanium >= quanto_prima,
			"senza morte l'Arcanium non torna indietro da solo oltre la rigenerazione")
	print("  vita dopo il primo morso: %.0f" % dopo_il_morso)

	## 5. Ora muore: 30 di vita per 100 di danno.
	salute.total_health = 2000
	salute.current_health = 30
	salute.set("_health_f", 30.0)
	var vita_mia : Node = pl.health_system
	vita_mia.drain(60.0)
	var mia_prima : float = float(vita_mia.current_health)
	vitali.drena_arcanium(vitali.arcanium)
	lontano.remove_from_group("targets")
	var o2 := _onda(scena, pl, t, 100.0)
	_ok(o2._bersaglio == nemico, "stesso bersaglio per il premio")
	var fino := 0.0
	while fino < 4.0 and int(salute.current_health) > 0:
		await physics_frame
		fino += 1.0 / 60.0
	await process_frame
	_ok(int(salute.current_health) <= 0, "muore per gli spiriti (dopo %.2f s)" % fino)
	_ok(is_equal_approx(vitali.arcanium, t.costo) or (vitali.arcanium >= t.costo and vitali.arcanium < t.costo + 1.0),
			"riprende tutto l'Arcanium speso (%.1f)" % vitali.arcanium)
	var rientrata : float = float(vita_mia.current_health) - mia_prima
	_ok(rientrata >= 14.0 and rientrata <= 16.0, "rientra la meta' del danno inflitto come vita (+%.0f su 30)" % rientrata)
	vita_mia.heal(10000.0)
	_ok(int(vita_mia.current_health) == int(vita_mia.total_health), "la cura si ferma al massimo")

	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
