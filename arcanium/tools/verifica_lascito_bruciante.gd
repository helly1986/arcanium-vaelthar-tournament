extends SceneTree

## Cancello del LASCITO DEL BRUCIANTE, la Lucida Tecnica dell'arco di Ilwen, col player
## vero nel dungeon:
##   1. l'arco la dichiara, costa 20 Arcanium e 30 stamina, senza risorse si rifiuta;
##   2. al rilascio nasce un fascio solo, davanti a chi tira;
##   3. dura 3 secondi: chi ci sta dentro prende colpi continui di FUOCO con la
##      Bruciatura, chi e' di lato, dietro o della propria parte no;
##   4. un nemico vero perde vita e la sua barra di Bruciatura sale fino a scattare;
##   5. la Bruciatura consuma vita per la sua durata, poi finisce;
##   6. il danno scala con le Marche dell'arma.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_lascito_bruciante.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ARCO := "res://arcanium/resources/weapons/arco_di_spirito_sylvorn.tres"

var _falliti := 0


class Bersaglio extends Node3D:
	var colpi : Array = []
	func hit(_da, info) -> void:
		colpi.append(info)


func _ok(cond : bool, cosa : String) -> void:
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _bersaglio(scena : Node, pl : Node3D, locale : Vector3, gruppo : String = "") -> Bersaglio:
	var b := Bersaglio.new()
	scena.add_child(b)
	b.add_to_group("targets")
	if gruppo != "":
		b.add_to_group(gruppo)
	b.global_position = pl.global_transform * locale
	return b


func _init() -> void:
	await process_frame
	root.get_node("SaveManager")._house = "sylvorn"
	root.get_node("EquipmentLoadout").clear_all()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 15:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	var caster : Node = pl.lucida_tecnica_caster
	var vitali : Node = pl.vitals
	var arco : Resource = load(ARCO)

	## 1.
	var t : Resource = caster.tecnica_corrente()
	_ok(t != null and t == arco.lucida_tecnica and t.name == "Lascito del Bruciante", "l'arco insegna la tecnica")
	_ok(is_equal_approx(t.costo, 20.0) and is_equal_approx(t.costo_stamina, 30.0), "costa 20 Arcanium e 30 stamina")
	vitali.spend_arcanium(vitali.arcanium - 10.0)
	_ok(not caster.lancia() and is_equal_approx(vitali.stamina, vitali.max_stamina), "senza Arcanium si rifiuta e non spende")
	vitali.refill_all()

	## I bersagli, davanti (+Z) a chi tira, dove non c'e' un muro: il fascio si ferma.
	var davanti := _bersaglio(scena, pl, Vector3(0.0, 0.0, 2.5))
	var accanto := _bersaglio(scena, pl, Vector3(0.9, 0.0, 3.0))
	var di_lato := _bersaglio(scena, pl, Vector3(4.5, 0.0, 3.0))
	var dietro := _bersaglio(scena, pl, Vector3(0.0, 0.0, -3.0))
	var amico := _bersaglio(scena, pl, Vector3(-0.5, 0.0, 2.0), "player")
	var nemico : Node3D = null
	for n in get_nodes_in_group("targets"):
		if n != pl and n is CharacterBody3D and n.get("health_system") != null:
			nemico = n
			break
	var vita_prima := 0
	if nemico != null:
		nemico.set_physics_process(false)
		## Il nemico del dungeon morirebbe prima dello status: gli si da' piu' vita.
		nemico.health_system.total_health = 2000
		nemico.health_system.current_health = 2000
		nemico.health_system.set("_health_f", 2000.0)
		nemico.global_position = pl.global_transform * Vector3(-0.4, 0.0, 1.8)
		vita_prima = int(nemico.health_system.current_health)

	_ok(caster.lancia(), "il gesto parte")
	var spesi_arc : float = vitali.max_arcanium - vitali.arcanium
	_ok(is_equal_approx(spesi_arc, 20.0), "ha speso 20 Arcanium")
	var fasci := []
	var quando := -1.0
	var attesa := 0.0
	var fino_a := 6.0
	var accumulo_max := 0.0
	while attesa < fino_a:
		await physics_frame
		attesa += 1.0 / 60.0
		for n in scena.get_children():
			if String(n.name).begins_with("LascitoBruciante") and not fasci.has(n):
				fasci.append(n)
				quando = attesa
		if nemico != null and is_instance_valid(nemico) and nemico.health_system.status_host != null:
			nemico.global_position = pl.global_transform * Vector3(-0.4, 0.0, 1.8)
			var b = nemico.health_system.status_host.get_effect("burn")
			if b != null:
				accumulo_max = maxf(accumulo_max, b.accumulo() if not b.is_active() else 1.0)
	_ok(fasci.size() == 1, "al rilascio nasce un fascio solo (%d, dopo %.2f s)" % [fasci.size(), quando])

	## 3. Ogni TICK da 0,25 s per 3 s.
	var n_colpi : int = davanti.colpi.size()
	_ok(n_colpi >= 10 and n_colpi <= 13, "colpi continui per 3 secondi (%d)" % n_colpi)
	_ok(accanto.colpi.size() == n_colpi, "colpisce anche chi gli sta vicino (%d)" % accanto.colpi.size())
	_ok(di_lato.colpi.is_empty() and dietro.colpi.is_empty(), "di lato e dietro non prende")
	_ok(amico.colpi.is_empty(), "i propri non lo prendono")
	if n_colpi > 0:
		var c = davanti.colpi[0]
		_ok(c.damage_type == "FUOCO" and c.burn_buildup > 0.0, "fuoco e accumulo di Bruciatura")
		_ok(is_equal_approx(c.power, float(arco.power) * t.danno_mult), "il danno e' quello dell'arma per %.1f (%.1f a colpo)" % [t.danno_mult, c.power])

	## 4.
	if nemico != null and is_instance_valid(nemico):
		_ok(int(nemico.health_system.current_health) < vita_prima, "un nemico vero perde vita (%d -> %d)" % [vita_prima, int(nemico.health_system.current_health)])
		_ok(accumulo_max >= 1.0, "la sua Bruciatura sale fino a scattare (%.2f)" % accumulo_max)
	else:
		_ok(false, "nessun nemico vero nel dungeon")

	## 5. Su un corpo solo, per i numeri.
	var corpo := Node3D.new()
	var salute := Node.new()
	salute.set_script(_salute_finta())
	salute.name = "HealthSystem"
	corpo.add_child(salute)
	var host := preload("res://arcanium/systems/status/status_host.gd").new()
	corpo.add_child(host)
	scena.add_child(corpo)
	await process_frame
	host.build_burn(60.0)
	var brucia = host.get_effect("burn")
	_ok(brucia != null and not brucia.is_active() and is_equal_approx(brucia.accumulo(), 0.6), "sotto la soglia accumula soltanto")
	host.build_burn(50.0)
	_ok(brucia.is_active(), "alla soglia scatta")
	await create_timer(7.0).timeout
	_ok(not brucia.is_active() and salute.perso > 10.0, "consuma vita per la sua durata, poi finisce (%.1f su %d)" % [salute.perso, salute.total_health])

	## 6.
	var stats : Resource = null
	for n in pl.get_children():
		if n.has_method("refresh") and "stats" in n:
			stats = n.stats
	var prima : int = arco.power_with(stats, 0)
	stats.add_marca(arco.primary_marca, 20)
	var dopo : int = arco.power_with(stats, 0)
	stats.add_marca(arco.primary_marca, -20)
	_ok(dopo > prima, "con 20 punti nella Marca dell'arma (%s) il danno sale: %d -> %d" % [arco.scaling_label(), prima, dopo])

	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)


func _salute_finta() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar total_health := 100\nvar perso := 0.0\nfunc drain(amount, _tipo = \"\"):\n\tperso += amount\n"
	s.reload()
	return s
