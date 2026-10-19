extends Node
class_name InventorySystem

## PONTE verso `ArcaniumInventory` — NON è più un inventario.
##
## Il template nasceva con la sua lista e i suoi conteggi ("refreshed at each
## spawn", diceva il commento originale). Arcanium ne ha uno proprio, autoload e
## persistente, ed erano due magazzini paralleli che si contraddicevano: il
## riposo al Cono ricaricava quello di Arcanium, la HUD leggeva questo, e il
## giocatore restava a secco mentre il menu dichiarava tre pozioni.
##
## Ora il magazzino è UNO SOLO (`ArcaniumInventory`). Questo nodo resta perché
## `ItemSystem` (oggetto appeso alla cintura, lancio dei bombe) e la barra della
## HUD parlano il dialetto del template: qui si traduce, e basta. Non tiene
## stato, non decide niente, non possiede oggetti.

@export var signaling_node : Node3D
@export var change_item_signal : String = "item_change_started"
@export var use_item_signal  : String = "item_used"

## Rispecchia i consumabili di ArcaniumInventory, con l'oggetto in mano in testa.
## `ItemSystem` legge `inventory[0]` come "oggetto corrente": è il motivo per cui
## l'attivo va per primo e non nell'ordine di raccolta.
var inventory : Array = []
var current_item

signal item_used
signal inventory_updated(Array)

var _inv : Node = null


func _ready() -> void:
	if signaling_node:
		if signaling_node.has_signal(change_item_signal):
			signaling_node.connect(change_item_signal, _on_change_item_signal)
		if signaling_node.has_signal(use_item_signal):
			signaling_node.connect(use_item_signal, _on_item_used_signal)

	_inv = get_node_or_null("/root/ArcaniumInventory")
	if _inv == null:
		push_warning("InventorySystem: ArcaniumInventory assente, la barra oggetti resterà vuota.")
		return
	_inv.changed.connect(_rispecchia)
	_inv.item_used.connect(func(def): item_used.emit(def))
	_rispecchia()


## Ricopia la lista dall'inventario vero e la ripropone nel formato che i
## consumatori del template si aspettano.
func _rispecchia() -> void:
	if _inv == null:
		return
	inventory = _inv.call("compat_inventory")
	current_item = inventory[0] if inventory.size() > 0 else null
	inventory_updated.emit(inventory)


## Il player ha premuto "usa oggetto": decide l'inventario vero, che scala il
## conteggio ed emette `item_used` — noi lo rilanciamo per `ItemSystem`, che se
## l'oggetto è lanciabile ne istanzia la versione fisica.
func _on_item_used_signal() -> void:
	if _inv == null:
		return
	var player := get_parent()
	if not _inv.call("use_active", player):
		## Niente scorte: si segnala comunque, così chi ascolta può far suonare
		## il "vuoto" invece di non dare alcun riscontro.
		item_used.emit(null)


## Il tasto "cambia oggetto" del template: scorre il quick-slot. I tasti dedicati
## (`item_prev`/`item_next`) li gestisce direttamente ArcaniumInventory.
func _on_change_item_signal() -> void:
	if _inv:
		_inv.call("cycle_active", 1)


## Riporta i consumabili al conteggio iniziale (riposo, viaggio, respawn).
## Delega: il conteggio non vive più qui.
func restore_counts() -> void:
	if _inv and _inv.has_method("restore_consumables"):
		_inv.call("restore_consumables")


## Conservato per compatibilità con chi lo chiamava: un oggetto raccolto entra
## nell'inventario vero.
func add_item(_new_item : ItemResource) -> void:
	if _inv and _new_item is ArcaniumItemResource:
		_inv.call("add", _new_item, 1)
