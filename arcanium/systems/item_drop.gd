extends Node
class_name ItemDrop

## Drop di un oggetto alla morte del nemico, con probabilità. Gemello di
## CrystalBounty (che accredita cristalli certi): questo tira un dado e, se
## passa, aggiunge un ArcaniumItemResource all'inventario del giocatore.
##
## Il .tres dell'item vive in res://arcanium/resources/items/<item_id>.tres
## (stesso schema di InventoryManager.add_item). Per ora è un drop "silenzioso"
## nell'inventario (nessun oggetto raccoglibile a terra): coerente con l'attuale
## flusso item del progetto, dove i pickup fisici sono contenuto futuro.

## Id dell'item (= nome file .tres senza estensione).
@export var item_id : String = ""
## Probabilità di drop, 0..1 (0.05 = 5%).
@export_range(0.0, 1.0, 0.01) var drop_chance : float = 0.05
## HealthSystem del nemico. Se null, cerca tra i fratelli.
@export var health_system : HealthSystem

var _rolled : bool = false

func _ready() -> void:
	if health_system == null:
		health_system = _find_health_system()
	if health_system and health_system.has_signal("died"):
		health_system.died.connect(_on_died)

func _find_health_system() -> HealthSystem:
	var host := get_parent()
	if host == null:
		return null
	for c in host.get_children():
		if c is HealthSystem:
			return c
	return null

func _on_died() -> void:
	if _rolled or item_id == "":
		return
	_rolled = true
	if randf() > drop_chance:
		return
	var path := "res://arcanium/resources/items/%s.tres" % item_id
	if not ResourceLoader.exists(path):
		push_warning("ItemDrop: item inesistente: " + path)
		return
	var def : ArcaniumItemResource = load(path)
	if def == null:
		return
	## Il possesso della versione equipaggiabile lo concede l'inventario stesso
	## (`ArcaniumInventory._concedi_equipaggiabile`): il ponte item→armadio stava
	## qui, ma qui copriva SOLO i drop dei nemici, e la stessa dimenticanza si è
	## ripresentata con la ricompensa del prologo.
	var inv := get_node_or_null("/root/ArcaniumInventory")
	if inv:
		inv.add(def, 1)
