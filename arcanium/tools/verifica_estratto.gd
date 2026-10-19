extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: l'Estratto di Kalvorn — i minion reggono di piu' per un minuto
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_estratto.gd
##
## Deciso con l'utente il 2026-10-02: «+50% durata minion» = +50% di vita per
## 60 s (i minion non hanno durata, vivono finche' non li uccidono). Con lo
## zaino vero (autoload ArcaniumInventory) e minion col sistema di vita vero:
##   1. usato, il minion in campo passa da 40 a 60 di vita massima, e la
##      quota arriva anche come cura;
##   2. un minion evocato DOPO lo prende entro un quarto di secondo;
##   3. riusato mentre dura, la quota non si somma;
##   4. finito il minuto si toglie: 40 di massimo, vita non oltre;
##   5. si consuma anche senza minion in campo.

const ESTRATTO := "res://arcanium/resources/items/estratto_kalvorn.tres"
const VIGORE := preload("res://arcanium/systems/summons/vigore_minion.gd")

var guasti := 0


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


func _minion(dove : Node, hp : int) -> Node3D:
	var m := Node3D.new()
	m.add_to_group("arcanium_minion")
	var hs : Node = (load("res://arcanium/systems/arcanium_health_system.gd") as GDScript).new()
	hs.name = "HealthSystem"
	hs.set("total_health", hp)
	m.add_child(hs)
	dove.add_child(m)
	return m


func _initialize() -> void:
	_prova()


func _attendi(s : float) -> void:
	var t := 0.0
	while t < s:
		await process_frame
		t += 1.0 / 60.0


func _prova() -> void:
	await process_frame
	var zaino := root.get_node_or_null("ArcaniumInventory")
	var estratto : ArcaniumItemResource = load(ESTRATTO)
	_sia(estratto != null and estratto.effect == "minion_vigore" and is_equal_approx(estratto.amount, 0.5)
		and is_equal_approx(estratto.durata, 60.0), "l'Estratto da' +50% per 60 s")
	zaino.add(estratto, 3, true)
	var slot : Dictionary = {}
	for s in zaino.slots_in_category("consumabile"):
		if s.def == estratto:
			slot = s
	var pl := Node3D.new()
	root.add_child(pl)
	var a := _minion(root, 40)
	await process_frame
	var hs_a : Node = a.get_node("HealthSystem")
	hs_a.apply_damage(10.0)

	print("=== 1. IL MINION IN CAMPO ===")
	_sia(zaino.use_slot(slot, pl), "l'Estratto si usa")
	_sia(hs_a.total_health == 60, "vita massima 40 -> %d" % hs_a.total_health)
	_sia(hs_a.current_health == 50, "e la quota arriva come cura: 30 -> %d" % hs_a.current_health)
	_sia(slot.count == 2, "se ne consuma uno (%d)" % slot.count)

	print("=== 2. UN MINION EVOCATO DOPO ===")
	var b := _minion(root, 40)
	await _attendi(0.4)
	_sia(b.get_node("HealthSystem").total_health == 60, "lo prende anche lui (%d)" % b.get_node("HealthSystem").total_health)

	print("=== 3. RIUSATO ===")
	_sia(zaino.use_slot(slot, pl), "si riusa")
	await _attendi(0.4)
	_sia(hs_a.total_health == 60, "la quota non si somma (%d)" % hs_a.total_health)
	var v : Node = pl.get_node_or_null(VIGORE.NOME)
	_sia(v != null and v.resta() > 59.0, "e il minuto riparte (%.1f s)" % (v.resta() if v else 0.0))

	print("=== 4. FINITO IL MINUTO ===")
	v.set("_resta", 0.05)
	await _attendi(0.2)
	_sia(hs_a.total_health == 40, "vita massima torna a %d" % hs_a.total_health)
	_sia(hs_a.current_health <= 40, "e quella attuale non la supera (%d)" % hs_a.current_health)
	_sia(pl.get_node_or_null(VIGORE.NOME) == null, "l'effetto se ne va")

	print("=== 5. SENZA MINION ===")
	a.queue_free()
	b.queue_free()
	await process_frame
	_sia(zaino.use_slot(slot, pl), "si consuma lo stesso (vale per chi si evoca nel minuto)")
	_sia(slot.count == 0, "ultimo usato (%d)" % slot.count)

	print("\n%s" % ("PASSATO — 0 problemi" if guasti == 0 else "FALLITO — %d problemi" % guasti))
	quit(0 if guasti == 0 else 1)
