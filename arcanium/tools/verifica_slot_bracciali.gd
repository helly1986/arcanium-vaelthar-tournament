extends SceneTree

## ⛔ CANCELLO: i tre pezzi d'armatura si possono equipaggiare davvero?
##
## Il montaggio 3D si guarda a schermo, ma il giro dell'INVENTARIO no: e' fatto
## di liste di slot ripetute in quattro file diversi, e basta dimenticarne una
## perche' un pezzo esista nel gioco e non compaia nel menu. Qui si verifica il
## giro intero senza aprire una finestra.
##
##     godot --headless --script res://arcanium/tools/verifica_slot_bracciali.gd

const SLOT := ["armatura_alta", "armatura_bassa", "bracciali"]

var guasti := 0


func _sia(condizione: bool, cosa: String) -> void:
	if condizione:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


func _init() -> void:
	var Loadout = load("res://arcanium/systems/equipment_loadout.gd")
	var Menu = load("res://arcanium/ui/game_menu/game_menu.gd")
	var Indossata = load("res://arcanium/systems/armatura_indossata.gd")

	print("=== gli slot sono dichiarati dove serve ===")
	for s in SLOT:
		_sia(Loadout.EQUIP_SLOTS.has(s), "EquipmentLoadout.EQUIP_SLOTS ha '%s'" % s)
		_sia(Menu.EQUIP_SLOTS.has(s), "GameMenu.EQUIP_SLOTS ha '%s'" % s)
		_sia(Menu.EQUIP_SLOT_LABELS.has(s), "GameMenu ha l'etichetta di '%s'" % s)
		_sia(Menu.EQUIP_SLOT_EMPTY_ICON.has(s), "GameMenu ha l'icona di '%s'" % s)
		_sia(Loadout.STARTER.has(s), "il kit iniziale contiene '%s'" % s)

	print()
	print("=== le risorse esistono, e dichiarano lo slot giusto ===")
	for s in SLOT:
		var percorso : String = Loadout.STARTER[s]
		var res = load(percorso)
		_sia(res != null, "si carica %s" % percorso.get_file())
		if res == null:
			continue
		_sia(res.equip_slot == s,
			"'%s' dichiara equip_slot='%s' (trovato '%s')" % [res.name, s, res.equip_slot])
		_sia(res.worn_model != null, "'%s' ha un worn_model" % res.name)
		var pezzi : PackedStringArray = res.worn_pieces
		_sia(pezzi.size() > 0, "'%s' dichiara %d piastre: %s" % [res.name, pezzi.size(), str(pezzi)])
		## ⚠️ L'ILLUSTRAZIONE d'inventario e' facile da dimenticare: il pezzo
		## funziona lo stesso, il menu ripiega sul glifo, e ce ne si accorge
		## guardando il menu — cioe' tardi. Qui si vede subito.
		_sia(res.image != null, "'%s' ha l'illustrazione d'inventario" % res.name)

	print()
	print("=== le piastre dichiarate esistono davvero nel .glb ===")
	for s in SLOT:
		var res = load(Loadout.STARTER[s])
		if res == null or res.worn_model == null:
			continue
		var radice = res.worn_model.instantiate()
		var presenti := {}
		for mi in radice.find_children("*", "MeshInstance3D", true, false):
			presenti[mi.name] = true
		for nome in res.worn_pieces:
			_sia(presenti.has(nome), "'%s' e' dentro %s" % [nome, res.worn_model.resource_path.get_file()])
		radice.free()

	print()
	print("=== nessuna piastra e' rivendicata da DUE slot ===")
	## Il difetto che questo cancello ha colto la prima volta che e' girato: la
	## corazza si portava dietro anche PV_Braccial_L/R. Finche' i bracciali non
	## avevano uno slot loro andava bene; con lo slot, le stesse due piastre
	## venivano montate DUE VOLTE, e togliere i bracciali non le toglieva.
	var padrone := {}
	for s in SLOT:
		var res = load(Loadout.STARTER[s])
		if res == null:
			continue
		for nome in res.worn_pieces:
			_sia(not padrone.has(nome),
				"'%s' e' rivendicata solo da '%s'%s"
				% [nome, s, "" if not padrone.has(nome) else " (gia' presa da '%s')" % padrone[nome]])
			padrone[nome] = s

	print()
	print("=== il ponte zaino -> armadio ===")
	## ⚠️ Le due famiglie di risorse sono legate SOLO dall'`id`:
	## `items/<id>.tres` (lo zaino, con la categoria) e
	## `equipment/<id>.tres` (l'armadio). `ArcaniumInventory._concedi_equipaggiabile`
	## cerca il secondo partendo dal primo, e se l'id non combacia il ponte tace:
	## l'oggetto entra nello zaino e non diventa mai equipaggiabile.
	for s in SLOT:
		var percorso : String = Loadout.STARTER[s]
		var nome_file := percorso.get_file().get_basename()
		var gemello := "res://arcanium/resources/items/%s.tres" % nome_file
		if not ResourceLoader.exists(gemello):
			print("  --    '%s' non ha un gemello nello zaino (kit iniziale, va bene)" % nome_file)
			continue
		var item = load(gemello)
		_sia(item != null, "si carica items/%s.tres" % nome_file)
		if item == null:
			continue
		_sia(item.id == nome_file,
			"l'id dello zaino combacia col file dell'armadio ('%s' vs '%s')" % [item.id, nome_file])
		_sia(item.category == "armatura",
			"'%s' e' in categoria 'armatura' (trovato '%s')" % [item.item_name, item.category])

	print()
	print("=== chi veste il corpo guarda tutti e tre gli slot ===")
	var nodo = Indossata.new()
	for s in SLOT:
		_sia(Array(nodo.slots).has(s), "ArmaturaIndossata.slots ha '%s'" % s)
	nodo.free()


	## ⚠️ Niente `quit()` qui: la prova a RUNTIME sta in `_initialize()`, che
	## Godot chiama dopo, quando l'albero esiste e si possono montare gli
	## autoload. Uscire qui la salterebbe in silenzio.


## Il giro vero, con i due autoload montati a mano. Serve perche' il ponte
## zaino->armadio non si vede leggendo i file: e' una ricerca per `id` fatta a
## runtime, e l'unico modo di sapere se funziona e' metterci dentro l'oggetto.
var _fatto := false


## ⚠️⚠️ Gli AUTOLOAD DEL PROGETTO ESISTONO anche in un `--headless --script`.
##
## Costato mezz'ora: il collaudo si montava un `EquipmentLoadout` suo e ci
## guardava dentro, ma `ArcaniumInventory` — che cerca il loadout per percorso
## assoluto — trovava quello VERO. Il ponte funzionava benissimo e consegnava
## all'armadio giusto; era il collaudo a guardare nell'armadio sbagliato. La
## sonda che l'ha colto e' stata `inv.get_node(...) == lo`, che ha risposto
## false. Quando un cancello fallisce, il primo sospettato e' il cancello.
##
## E non puo' stare in `_initialize()`: li' l'albero non e' ancora ATTIVO e
## `get_node("/root/...")` fallisce con "absolute paths from outside the active
## scene tree". Al primo frame di `_process` lo e'.
func _process(_dt : float) -> bool:
	if _fatto:
		return true
	_fatto = true
	print()
	print("=== a RUNTIME: l'oggetto entra nello zaino e diventa equipaggiabile ===")
	var lo = root.get_node_or_null("EquipmentLoadout")
	var inv = root.get_node_or_null("ArcaniumInventory")
	_sia(lo != null, "l'autoload EquipmentLoadout c'e'")
	_sia(inv != null, "l'autoload ArcaniumInventory c'e'")
	if lo == null or inv == null:
		print("  senza autoload il giro non si puo' provare: salto")
		quit(1 if guasti > 0 else 0)
		return true

	## si parte da un caso onesto: il kit iniziale gli ha gia' dato tutto,
	## quindi prima si spoglia
	lo._posseduti.clear()
	lo.equipped.erase("bracciali")
	_sia(lo.owned_for_slot("bracciali").is_empty(), "si parte senza bracciali posseduti")
	_sia(lo.equipped_in("bracciali") == null, "si parte senza bracciali indossati")

	## e ora l'oggetto entra dallo ZAINO, che e' la strada di un drop o di una
	## ricompensa: nessuno tocca l'armadio a mano.
	var item = load("res://arcanium/resources/items/bracciali_prima_veglia.tres")
	inv.add(item, 1, true)
	_sia(inv.has_item("bracciali_prima_veglia"), "i bracciali sono nello zaino")

	var posseduti : Array = lo.owned_for_slot("bracciali")
	if posseduti.size() != 1:
		## Tre cause diverse, e vanno distinte: il catalogo non vede il pezzo,
		## il possesso non e' stato registrato, o i percorsi non combaciano.
		print("      catalogo: %s"
			% str(lo.catalog_for_slot("bracciali").map(func(r): return r.resource_path)))
		print("      posseduti: %s" % str(lo._posseduti.keys()))
	_sia(posseduti.size() == 1,
		"il ponte li ha resi equipaggiabili (%d nell'armadio)" % posseduti.size())
	if posseduti.size() == 1:
		_sia(posseduti[0].equip_slot == "bracciali", "e finiscono nello slot 'bracciali'")
		lo.equip("bracciali", posseduti[0])
		var addosso = lo.equipped_in("bracciali")
		_sia(addosso != null and addosso.name == posseduti[0].name,
			"si equipaggiano: addosso c'e' '%s'" % (addosso.name if addosso else "niente"))

	print()
	if guasti == 0:
		print("TUTTO A POSTO: %d slot equipaggiabili end-to-end, zaino compreso." % SLOT.size())
	else:
		print("%d CONTROLLI FALLITI" % guasti)
	quit(1 if guasti > 0 else 0)
	return true
