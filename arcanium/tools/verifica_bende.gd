extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: le Bende dell'Eco curano la Lacerazione
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_bende.gd
##
## LORE/ITEMS_LORE: «rimuove Lacerazione — stoppa la barra DoT». Su un corpo
## col sistema di vita e gli stati del giocatore, usando lo zaino vero
## (autoload ArcaniumInventory):
##   1. a barra MEZZA piena le bende la azzerano, e se ne consuma una;
##   2. a Lacerazione SCATTATA la chiudono (niente piu' drain di stamina);
##   3. senza niente da curare NON si consumano.

const BENDE := "res://arcanium/resources/items/bende_eco.tres"

var guasti := 0


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


## Un corpo con vita, stati e vitali come quelli del giocatore.
class Ferito extends Node3D:
	var health_system : Node
	var status_host : Node
	var vitals : Node
	func _init() -> void:
		status_host = (load("res://arcanium/systems/status/status_host.gd") as GDScript).new()
		status_host.name = "StatusHost"
		status_host.set("log_to_console", false)
		add_child(status_host)
		health_system = (load("res://arcanium/systems/arcanium_health_system.gd") as GDScript).new()
		health_system.name = "HealthSystem"
		health_system.set("total_health", 100)
		health_system.set("status_host", status_host)
		add_child(health_system)
		vitals = (load("res://arcanium/systems/player_vitals.gd") as GDScript).new()
		vitals.name = "PlayerVitals"
		vitals.set("status_host", status_host)
		add_child(vitals)


func _initialize() -> void:
	_prova()


func _prova() -> void:
	await process_frame
	var zaino := root.get_node_or_null("ArcaniumInventory")
	_sia(zaino != null, "lo zaino c'e' (autoload)")
	if zaino == null:
		quit(1)
		return
	var bende : ArcaniumItemResource = load(BENDE)
	_sia(bende != null and bende.effect == "cure_status" and bende.stato == "laceration",
		"le Bende dell'Eco curano la Lacerazione")
	zaino.add(bende, 3, true)
	var slot : Dictionary = {}
	for s in zaino.slots_in_category("consumabile"):
		if s.def == bende:
			slot = s
	_sia(not slot.is_empty() and slot.count == 3, "tre bende nello zaino")

	var f := Ferito.new()
	root.add_child(f)
	await process_frame
	var sh : Node = f.status_host

	print("=== 1. BARRA A META' ===")
	sh.build_laceration(60.0)
	var lac : Node = sh.get_effect("laceration")
	_sia(lac != null and lac.meter > 50.0, "la barra sale (%.0f)" % (lac.meter if lac else 0.0))
	_sia(zaino.use_slot(slot, f), "le bende si usano")
	_sia(lac.meter == 0.0, "e la barra torna a zero")
	_sia(slot.count == 2, "se ne consuma una (%d)" % slot.count)

	print("=== 2. LACERAZIONE SCATTATA ===")
	sh.build_laceration(100.0)
	_sia(lac.is_active(), "la Lacerazione scatta")
	_sia(zaino.use_slot(slot, f), "le bende si usano")
	_sia(not lac.is_active(), "e la Lacerazione e' finita")
	_sia(lac.stamina_da_togliere(1.0) == 0.0, "niente piu' drain di stamina")
	_sia(slot.count == 1, "un'altra consumata (%d)" % slot.count)

	print("=== 3. NIENTE DA CURARE ===")
	_sia(not zaino.use_slot(slot, f), "senza Lacerazione le bende non servono")
	_sia(slot.count == 1, "e non si consumano (%d)" % slot.count)

	print("\n%s" % ("PASSATO — 0 problemi" if guasti == 0 else "FALLITO — %d problemi" % guasti))
	quit(0 if guasti == 0 else 1)
