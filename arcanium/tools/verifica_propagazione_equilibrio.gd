extends SceneTree

## Cancello della PROPAGAZIONE DELL'EQUILIBRIO, la Lucida Tecnica dell'asta di Zarine,
## col player vero nel dungeon:
##   1. l'Asta del Contrappeso la dichiara, e lanciarla costa 29 Arcanium e 50 stamina;
##   2. senza risorse viene rifiutata e non si spende niente;
##   3. all'impatto nasce l'onda, una sola, sotto l'arma;
##   4. colpisce tutti quelli che il fronte raggiunge, una volta sola: a sinistra di
##      chi colpisce EROSIONE con l'Emorragia, a destra SACRO con la Frattura, anche
##      su un nemico vero;
##   5. chi e' fuori raggio, troppo in alto, oltre il suolo o della propria parte non
##      la prende;
##   6. il danno scala con le Marche dell'arma.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_propagazione_equilibrio.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ASTA := "res://arcanium/resources/weapons/asta_contrappeso.tres"

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
	root.get_node("SaveManager")._house = "aethon"
	root.get_node("EquipmentLoadout").clear_all()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 15:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	var caster : Node = pl.lucida_tecnica_caster
	var vitali : Node = pl.vitals
	var asta : Resource = load(ASTA)

	## 1. e 2.
	var t : Resource = caster.tecnica_corrente()
	_ok(t != null and t == asta.lucida_tecnica and t.name == "Propagazione dell'Equilibrio", "l'asta insegna la tecnica")
	_ok(is_equal_approx(t.costo, 29.0) and is_equal_approx(t.costo_stamina, 50.0), "costa 29 Arcanium e 50 stamina")
	vitali.spend_stamina(vitali.stamina - 40.0)
	var arc0 : float = vitali.arcanium
	_ok(not caster.lancia() and is_equal_approx(vitali.arcanium, arc0) and is_equal_approx(vitali.stamina, 40.0),
			"senza stamina si rifiuta, e non spende niente")
	vitali.refill_all()
	vitali.spend_arcanium(vitali.arcanium - 20.0)
	_ok(not caster.lancia() and is_equal_approx(vitali.stamina, vitali.max_stamina),
			"senza Arcanium si rifiuta, e non spende niente")
	vitali.refill_all()

	## I bersagli, nello spazio di chi colpisce (guarda +Z, la sua sinistra e' +X).
	var sinistra := _bersaglio(scena, pl, Vector3(3.5, 0.0, 1.0))
	var destra := _bersaglio(scena, pl, Vector3(-3.5, 0.0, 1.0))
	var destra2 := _bersaglio(scena, pl, Vector3(-2.0, 0.0, 3.0))
	var lontano := _bersaglio(scena, pl, Vector3(0.0, 0.0, 14.0))
	var in_alto := _bersaglio(scena, pl, Vector3(-2.0, 5.0, 1.0))
	var amico := _bersaglio(scena, pl, Vector3(2.0, 0.0, -2.0), "player")

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
		nemico.global_position = pl.global_transform * Vector3(-1.5, 0.0, 1.0)
		vita_prima = int(nemico.health_system.current_health)

	var potenza : float = float(asta.power)
	_ok(caster.lancia(), "il gesto parte")
	_ok(is_equal_approx(vitali.max_arcanium - vitali.arcanium, 29.0) and vitali.max_stamina - vitali.stamina >= 49.0,
			"ha speso 29 Arcanium e 50 stamina")
	_ok(not caster.lancia(), "una alla volta")
	var onde := []
	var attesa := 0.0
	while attesa < 3.2:
		await physics_frame
		attesa += 1.0 / 60.0
		for n in scena.get_children():
			if String(n.name).begins_with("PropagazioneEquilibrio") and not onde.has(n):
				onde.append(n)
	_ok(onde.size() == 1, "all'impatto nasce un'onda sola (%d)" % onde.size())
	_ok(sinistra.colpi.size() == 1 and destra.colpi.size() == 1 and destra2.colpi.size() == 1,
			"colpisce tutti, una volta sola (%d, %d, %d)" % [sinistra.colpi.size(), destra.colpi.size(), destra2.colpi.size()])
	if sinistra.colpi.size() == 1 and destra.colpi.size() == 1:
		var s = sinistra.colpi[0]
		var d = destra.colpi[0]
		_ok(s.damage_type == "EROSIONE" and s.laceration_buildup >= 100.0 and not s.inflicts_fracture, "a sinistra l'Erosione e l'Emorragia")
		_ok(d.damage_type == "SACRO" and d.inflicts_fracture and d.laceration_buildup <= 0.0, "a destra il Sacro e la Frattura")
		_ok(is_equal_approx(s.power, potenza * t.danno_mult) and is_equal_approx(d.power, s.power),
				"il danno e' quello dell'arma per %.1f (%.0f)" % [t.danno_mult, s.power])
	if nemico != null and is_instance_valid(nemico):
		var frattura = nemico.health_system.status_host.get_effect("fracture") if nemico.health_system.status_host != null else null
		_ok(int(nemico.health_system.current_health) < vita_prima and frattura != null and frattura.is_active(),
				"un nemico vero a destra perde vita e prende la Frattura (%d -> %d)" % [vita_prima, int(nemico.health_system.current_health)])
	else:
		_ok(false, "nessun nemico vero nel dungeon")
	## La meta' oscura sul nemico vero: un'altra onda, con lui alla sinistra.
	if nemico != null and is_instance_valid(nemico):
		var prima_oscura := int(nemico.health_system.current_health)
		var seconda : Node3D = t.impatto.instantiate()
		seconda.lanciatore = pl
		seconda.potenza = 1.0
		seconda.transform = Transform3D(pl.global_transform.basis, pl.global_position)
		nemico.global_position = pl.global_transform * Vector3(1.5, 0.0, 1.0)
		scena.add_child(seconda)
		await create_timer(1.0).timeout
		var emorragia = nemico.health_system.status_host.get_effect("laceration")
		var perso := prima_oscura - int(nemico.health_system.current_health)
		_ok(emorragia != null and emorragia.is_active() and perso > 400, "un nemico vero a sinistra prende l'Emorragia (-%d su 2000)" % perso)
	_ok(lontano.colpi.is_empty(), "fuori raggio non la prende")
	_ok(in_alto.colpi.is_empty(), "troppo in alto non la prende")
	_ok(amico.colpi.is_empty(), "i propri non la prendono")

	## 6. Le Marche: piu' punti nella Marca dell'arma, piu' danno.
	var stats : Resource = null
	for n in pl.get_children():
		if n.has_method("refresh") and "stats" in n:
			stats = n.stats
	var prima : int = asta.power_with(stats, 0)
	stats.add_marca(asta.primary_marca, 20)
	var dopo : int = asta.power_with(stats, 0)
	stats.add_marca(asta.primary_marca, -20)
	_ok(dopo > prima, "con 20 punti nella Marca dell'arma (%s) il danno sale: %d -> %d" % [asta.scaling_label(), prima, dopo])

	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
