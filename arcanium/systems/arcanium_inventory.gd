extends Node

## Inventario del giocatore — porting di Inventory.js (Arcanium-Lite).
## Autoload persistente (stile CrystalBank): sopravvive ai cambi scena ed è
## l'unica fonte dati per GameMenu e futuri pickup.
##
## slots: [{def: ArcaniumItemResource, count: int}] — stacking per id.

signal changed
## Emesso a ogni acquisizione REALE (non alla dotazione iniziale): l'Announcer ci
## si aggancia e annuncia l'oggetto da sé, così un pickup nuovo non ha bisogno di
## ricordarsi di notificare.
signal item_added(def : ArcaniumItemResource, count : int)
## Il giocatore ha appena imparato una tecnica di guerra da un tomo — la PRIMA
## volta: una seconda copia dello stesso tomo entra nello zaino come oggetto e
## basta. Il popup che la insegna ci si aggancia (vedi `ui/tomo/tomo_modal.gd`).
signal tecnica_appresa(tecnica : Resource)
## Il consumabile in mano è cambiato (ciclo col quick-slot).
signal active_changed(def : ArcaniumItemResource)
## ─── Compatibilità col sistema oggetti del template ─────────────────────────
## Il template ha il suo `InventorySystem` appeso al player, con la sua lista e
## i suoi conteggi: due magazzini paralleli che si contraddicevano (il riposo
## ricaricava questo, la HUD leggeva quello, e il giocatore restava a secco con
## il menu che dichiarava tre pozioni). Ora il magazzino è UNO SOLO — questo — e
## il nodo del template è ridotto a un ponte: gli passiamo la lista con questi
## due segnali, che sono quelli che HUD e `ItemSystem` già ascoltano.
signal inventory_updated(lista : Array)
signal item_used(def : ArcaniumItemResource)

const CATEGORIES := ["arma", "sigillo", "armatura", "talismano", "consumabile", "curiosita"]
const VigoreMinion := preload("res://arcanium/systems/summons/vigore_minion.gd")

var slots : Array = []
var active_index := 0   # indice DENTRO i consumabili (quick-slot)

func _ready() -> void:
	## Un solo punto di rilancio verso i consumatori del formato template, così
	## nessuna modifica all'inventario può dimenticarsi di aggiornarli.
	changed.connect(_notify_template)
	_dotazione_iniziale()


## Con cosa si comincia. In una funzione sola perché serve all'avvio E a ogni
## partita nuova.
func _dotazione_iniziale() -> void:
	var fiala : ArcaniumItemResource = load("res://arcanium/resources/items/fiala_sangue_eco.tres")
	if fiala:
		## `silent`: la dotazione di partenza non è una conquista. Senza questo,
		## il gioco si apre con un popup "Ottenuto Fiala di Sangue d'Eco" prima
		## ancora che il player abbia fatto qualcosa.
		add(fiala, fiala.start_count, true)


## Svuota lo zaino e rimette la dotazione iniziale (nuova partita).
##
## ⚠️ Questo magazzino NON viene salvato su disco: sopravvive solo perché è un
## autoload, e un autoload attraversa il cambio scena. Quindi cancellare il file
## di salvataggio non lo svuota, e una partita nuova ripartiva con tutto quello
## che si era raccolto nella precedente.
func clear_all() -> void:
	slots.clear()
	active_index = 0
	_dotazione_iniziale()
	changed.emit()


## ═══════════════════════════════════════════════════════════════════════════
## SALVATAGGIO
## ═══════════════════════════════════════════════════════════════════════════
##
## ⚠️ Questo magazzino non veniva salvato affatto. Non si notava perché
## l'autoload è vivo per tutta la sessione: le pozioni raccolte c'erano ancora
## dopo un cambio scena, e sembrava che il salvataggio funzionasse. Sembrava.
## Chiudendo il gioco tornavano quelle di partenza.
##
## Si salvano i PERCORSI, non le risorse: un `.tres` tolto dal progetto dopo un
## salvataggio non deve piantare il caricamento — si perde quell'oggetto, non la
## partita. È la stessa regola di `EquipmentLoadout.from_dict`.
func to_dict() -> Dictionary:
	var voci : Array = []
	for s in slots:
		if s.def != null and s.def.resource_path != "":
			voci.append({"path": s.def.resource_path, "count": int(s.count)})
	return {"voci": voci, "attivo": active_index}


func from_dict(d : Dictionary) -> void:
	if d == null or d.is_empty():
		return
	slots.clear()
	for v in d.get("voci", []):
		var percorso := str(v.get("path", ""))
		if percorso == "" or not ResourceLoader.exists(percorso):
			continue
		var def = load(percorso)
		if def != null:
			## ⚠️ Si riempie `slots` DIRETTAMENTE invece di passare da `add()`:
			## `add()` chiama il ponte `_concedi_equipaggiabile`, e ricaricando
			## una partita rimetterebbe nell'armadio anche l'equipaggiabile di
			## un oggetto che nel frattempo si era VENDUTO. Il possesso lo
			## ripristina `EquipmentLoadout` per conto suo, dal suo pezzo di
			## salvataggio.
			slots.append({"def": def, "count": int(v.get("count", 1))})
	active_index = int(d.get("attivo", 0))
	changed.emit()


func add(def : ArcaniumItemResource, count : int = 1, silent : bool = false) -> void:
	_concedi_equipaggiabile(def)
	_insegna_tecnica(def, silent)
	for s in slots:
		if s.def.id == def.id:
			s.count += count
			changed.emit()
			if not silent:
				item_added.emit(def, count)
			return
	slots.append({"def": def, "count": count})
	changed.emit()
	if not silent:
		item_added.emit(def, count)

## Se dell'oggetto esiste anche la versione EQUIPAGGIABILE, entrarne in possesso
## nell'inventario significa poterla anche impugnare. Le due risorse vivono in
## cartelle diverse — `items/` per l'inventario, `weapons/`+`equipment/` per
## l'armadio — e sono legate dallo stesso `id`.
##
## ⚠️ Sta QUI e non in chi consegna l'oggetto perché è già stato dimenticato una
## volta: quando il possesso è diventato esplicito (vedi `equipment_loadout.gd`,
## prima bastava che il .tres esistesse su disco) il ponte è stato aggiunto solo
## al drop dei nemici. La Spada del Senza Nome, che arriva dal PrologueDirector,
## finiva così fra gli oggetti ma non fra le armi equipaggiabili — su una partita
## nuova la ricompensa del primo boss non si poteva impugnare. Con il ponte qui
## dentro passa da un punto solo qualunque strada l'oggetto prenda.
func _concedi_equipaggiabile(def : ArcaniumItemResource) -> void:
	if def == null or def.id == "":
		return
	var loadout := get_node_or_null("/root/EquipmentLoadout")
	if loadout == null or not loadout.has_method("acquire"):
		return
	for dir_path in ["res://arcanium/resources/weapons/",
			"res://arcanium/resources/equipment/"]:
		var path : String = dir_path + def.id + ".tres"
		if ResourceLoader.exists(path):
			loadout.acquire(load(path))
			return


## Se l'oggetto è un tomo (`insegna` non vuoto), entrarne in possesso significa
## SAPERE la tecnica. Lo stato "appresa" è un flag in `PlayerFlags` — la stessa
## strada dei summon (`unlock_flag`), già serializzata da `SaveManager`: qui non
## si salva niente, si alza un flag.
##
## ⚠️ Sta QUI, accanto a `_concedi_equipaggiabile`, e per la stessa ragione:
## il tomo può arrivare da un baule, da un drop, da una bottega, da un dialogo.
## Cablare l'insegnamento nel baule vorrebbe dire che le altre tre strade lo
## dimenticano — la dimenticanza che la Spada del Senza Nome ha già pagato.
##
## Si insegna UNA volta: una seconda copia dello stesso tomo è un oggetto in
## più, non una lezione in più. E `silent` (la dotazione iniziale) alza il flag
## ma non emette: un popup didattico prima ancora di aver mosso un passo
## sarebbe la stessa cosa del "Ottenuto Fiala" all'avvio che `silent` esiste
## per evitare.
##
## `from_dict` (ricaricare una partita) NON passa di qui — riempie `slots`
## direttamente — e va bene così: il flag è già nel salvataggio.
func _insegna_tecnica(def : ArcaniumItemResource, silent : bool) -> void:
	if def == null or def.insegna == null:
		return
	var tecnica : Resource = def.insegna
	## Duck-typing sulla risorsa, come `SpellSelection` fa con `unlock_flag`:
	## un `get()` su una proprietà assente torna null, non una stringa.
	var grezzo = tecnica.get("unlock_flag")
	var flag : String = grezzo if grezzo is String else ""
	if flag == "":
		push_warning("ArcaniumInventory: '%s' insegna una tecnica senza unlock_flag — non apprendibile." % def.id)
		return
	var flags := get_node_or_null("/root/PlayerFlags")
	if flags == null:
		return
	if flags.has(flag):
		return
	flags.set_flag(flag)
	if not silent:
		tecnica_appresa.emit(tecnica)

## Il giocatore possiede almeno un esemplare di `id`? Serve ai dialoghi
## (condizione `item:`): certe battute esistono solo se hai l'oggetto in mano —
## chiedere a Solan se ha mai visto un'arma come la tua non ha senso finché una
## spada non ce l'hai.
func has_item(id : String) -> bool:
	for s in slots:
		if s.def != null and s.def.id == id and s.count > 0:
			return true
	return false

# ─── Quick-slot dei consumabili ─────────────────────────────────────────────

## TUTTI gli slot consumabili, anche quelli a zero. `slots_in_category` filtra
## `count > 0` ed è giusto così per il menu, ma il quick-slot deve continuare a
## mostrare la Fiala vuota: una fiala che sparisce dalla barra quando la finisci
## fa credere di averla persa.
func consumable_slots() -> Array:
	return slots.filter(func(s): return category_of(s.def) == "consumabile")

func active_slot() -> Dictionary:
	var cs := consumable_slots()
	if cs.is_empty():
		return {}
	active_index = clampi(active_index, 0, cs.size() - 1)
	return cs[active_index]

## Scorre il consumabile in mano. Ciclico: da fondo lista si torna al primo.
func cycle_active(delta : int) -> void:
	var cs := consumable_slots()
	if cs.size() <= 1:
		return
	active_index = (active_index + delta + cs.size()) % cs.size()
	var s : Dictionary = cs[active_index]
	active_changed.emit(s.def)
	changed.emit()

## Beve/usa il consumabile in mano. È il punto UNICO da cui passa il consumo:
## il ponte del template chiama qui invece di scalare un proprio contatore.
func use_active(player : Node) -> bool:
	var s := active_slot()
	if s.is_empty() or int(s.count) <= 0:
		return false
	var def : ArcaniumItemResource = s.def
	if use_slot(s, player):
		item_used.emit(def)
		return true
	return false

## Lista in formato template per HUD e `ItemSystem`: le RISORSE, col conteggio
## scritto sopra e l'attiva in testa (quei consumatori leggono `inventory[0]`
## come "oggetto in mano").
##
## ⚠️ Scrivere `def.count` muta una risorsa condivisa e cachata — è brutto, ma è
## il contratto del template (`ItemResource.count`), e averne una copia sarebbe
## peggio: tornerebbero due verità diverse, che è il bug da cui siamo partiti.
func compat_inventory() -> Array:
	var cs := consumable_slots()
	var out : Array = []
	for i in cs.size():
		var s : Dictionary = cs[(active_index + i) % cs.size()]
		s.def.count = int(s.count)
		out.append(s.def)
	return out

## Da chiamare dopo ogni modifica: aggiorna chi vive sui segnali del template.
func _notify_template() -> void:
	inventory_updated.emit(compat_inventory())

## Il ciclo del quick-slot passa da qui, come `SpellSelection` fa per magie ed
## evocazioni: l'inventario è un autoload e sa già tutto, non serve rimbalzare
## l'input attraverso il player.
func _unhandled_input(event : InputEvent) -> void:
	if event.is_action_pressed("item_next"):
		cycle_active(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("item_prev"):
		cycle_active(-1)
		get_viewport().set_input_as_handled()


func category_of(def : ArcaniumItemResource) -> String:
	return def.category if def.category != "" else "consumabile"

## Riporta i CONSUMABILI (pozioni) al conteggio iniziale — usato dai Coni di
## Canalizzazione al riposo e dal respawn alla morte (stile falò soulslike).
## Non tocca armi/curiosità: solo ciò che si consuma.
func restore_consumables() -> void:
	for s in slots:
		if category_of(s.def) == "consumabile":
			s.count = s.def.start_count
	changed.emit()

func slots_in_category(cat : String) -> Array:
	return slots.filter(func(s): return category_of(s.def) == cat and s.count > 0)

## Raggruppamento nell'ordine canonico, saltando le categorie vuote.
func by_category() -> Array:
	var out : Array = []
	for cat in CATEGORIES:
		var cat_slots := slots_in_category(cat)
		if cat_slots.size() > 0:
			out.append({"category": cat, "slots": cat_slots})
	return out

## ⚠️ Un consumabile "da falò" (quello con `start_count > 0`: la fiala) NON va
## eliminato quando arriva a zero. `restore_consumables()` ricarica scorrendo gli
## slot: se lo slot sparisce, non trova più niente da ricaricare — cioè le
## pozioni non tornavano MAI, e proprio nel caso normale, perché ti riposi
## esattamente quando le hai finite.
##
## Tenere lo slot a zero non ha controindicazioni: sia il menu sia la HUD
## leggono da `slots_in_category`, che filtra già `count > 0`, quindi uno slot
## vuoto resta invisibile.
func prune() -> void:
	slots = slots.filter(func(s): return s.count > 0 or _e_ricaricabile(s.def))

func _e_ricaricabile(def : ArcaniumItemResource) -> bool:
	return def != null and category_of(def) == "consumabile" and def.start_count > 0

## Usa uno slot consumabile sul player (dal quick-slot o dal GameMenu).
func use_slot(slot : Dictionary, player : Node) -> bool:
	if slot.is_empty() or slot.count <= 0:
		return false
	var def : ArcaniumItemResource = slot.def
	var used := _apply_effect(def, player)
	if used:
		slot.count = maxi(0, slot.count - 1)
		prune()
		changed.emit()
	return used

func _apply_effect(def : ArcaniumItemResource, player : Node) -> bool:
	if def.effect == "heal" and player and "health_system" in player and player.health_system:
		player.health_system.heal(def.amount)
		return true
	## Cura uno stato (Bende dell'Eco → Lacerazione). Se non c'e' niente da
	## curare l'oggetto NON si consuma: non si sprecano le bende per sbaglio.
	if def.effect == "cure_status" and def.stato != "" and player and "health_system" in player and player.health_system:
		var sh = player.health_system.get("status_host")
		if sh != null and sh.has_method("cura"):
			return sh.cura(def.stato)
	## L'Estratto di Kalvorn: i minion reggono di piu' per un minuto. Si
	## consuma anche senza minion in campo: vale per quelli evocati nel minuto.
	if def.effect == "minion_vigore" and player:
		return VigoreMinion.applica(player, def.amount, def.durata)
	return false
