extends Node
## Autoload: InventoryManager
## Wrapper sottile su ArcaniumInventory (autoload esistente) per il trigger
## UNLOCK_ITEM del dialogue system. Gli item-reward delle quest (es.
## "mappa_frammenti_mercato") sono contenuto futuro: se la risorsa .tres non
## esiste ancora, avvisiamo e continuiamo (nessun crash).

func add_item(id : String) -> void:
	var path := "res://arcanium/resources/items/%s.tres" % id
	if not ResourceLoader.exists(path):
		push_warning("InventoryManager: item quest non ancora creato: " + id)
		return
	var def : ArcaniumItemResource = load(path)
	if def == null:
		push_warning("InventoryManager: item quest non ancora creato: " + id)
		return
	ArcaniumInventory.add(def, 1)
