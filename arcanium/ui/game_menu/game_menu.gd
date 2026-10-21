extends CanvasLayer

## Menu di gioco a sezioni — porting di GameMenu.js (Arcanium-Lite). Autoload
## (stile CrystalBank/ArcaniumInventory) così è raggiungibile da qualunque scena
## col tasto I, senza dover essere istanziato dentro l'arena.
##
## Non bloccante: il mondo resta vivo dietro (il player legge is_blocking() per
## congelare SOLO l'input di movimento/attacco — i colpi nemici continuano a
## passare, come in Lite). Niente pausa: è un soulslike, il giocatore non ha
## diritto a fermare il mondo nemmeno dalle Impostazioni (Esc).
##
## Esc apre/chiude anche le Impostazioni quando il menu sezioni è chiuso —
## stesso pannello della Fase 2 (main menu), qui senza mettere in pausa.

const SECTIONS := ["stats", "inventory", "grimorio", "tecniche", "quests"]
const SECTION_LABELS := {"stats": "Stats", "inventory": "Inventory", "grimorio": "Grimoire", "tecniche": "Techniques", "quests": "Quests"}

## Larghezza dei testi lunghi (lore, note) fuori dal grimorio. È DICHIARATA e
## non dedotta: un autowrap senza misura, dentro un contenitore che si dimensiona
## sul contenuto, trova larghezza minima zero e manda a capo OGNI CARATTERE.
const LARGHEZZA_DETTAGLIO := 420.0
## La colonna della tecnica scelta (scheda Tecniche): piu' larga del dettaglio
## dell'inventario perche' porta "come si esegue" per intero, ma non tutto lo
## schermo.
const LARGHEZZA_TECNICA := 640.0
## I tipi d'arma (`object_type`) come si dicono al giocatore, per la riga
## "apre l'equipaggiamento" di una tecnica che chiude un armadio.
const TIPI_ARMA_LABELS := {"BOW": "bows", "SLASH": "swords", "HEAVY": "heavy weapons"}

const CATEGORY_LABELS := {
	"arma": "Weapons", "sigillo": "Sigils", "armatura": "Armor",
	"talismano": "Talismans", "consumabile": "Consumables", "curiosita": "Curiosities",
}

## Pannello Equipaggiamento (kit iniziale Dawnkeep "della Prima Veglia") — solo
## display, non è ancora un vero sistema di swap: mostra ciò che il player ha
## realmente indosso/in mano nella scena (arma+sigillo via WeaponSystem/GadgetSystem,
## armatura sempre indossata, scudo in GadgetSystem).
const EQUIP_SLOTS := ["arma_primaria", "arma_secondaria", "armatura_alta", "armatura_bassa",
	"bracciali", "scudo",
	"talismano_1", "talismano_2", "talismano_3", "talismano_4"]
const EQUIP_SLOT_LABELS := {
	"arma_primaria": "Main weapon", "arma_secondaria": "Arcane sigil",
	"armatura_alta": "Chest", "armatura_bassa": "Legs",
	"bracciali": "Bracers", "scudo": "Shield",
	"talismano_1": "Talisman I", "talismano_2": "Talisman II",
	"talismano_3": "Talisman III", "talismano_4": "Talisman IV",
}
const EQUIP_SLOT_EMPTY_ICON := {
	"arma_primaria": "⚔", "arma_secondaria": "◈",
	"armatura_alta": "⬒", "armatura_bassa": "⬓", "bracciali": "⌒", "scudo": "🛡",
	"talismano_1": "○", "talismano_2": "○", "talismano_3": "○", "talismano_4": "○",
}
const STARTER_EQUIPMENT := {
	"arma_primaria": preload("res://arcanium/resources/weapons/lama_prima_veglia.tres"),
	"arma_secondaria": preload("res://arcanium/resources/equipment/sigillo_prima_veglia.tres"),
	"armatura_alta": preload("res://arcanium/resources/equipment/corazza_prima_veglia.tres"),
	"armatura_bassa": preload("res://arcanium/resources/equipment/gambali_prima_veglia.tres"),
	"bracciali": preload("res://arcanium/resources/equipment/bracciali_prima_veglia.tres"),
	"scudo": preload("res://arcanium/resources/equipment/scudo_prima_veglia.tres"),
}
## preload per PATH e non per class_name: la registrazione dei class_name
## dipende dallo scan dell'editor, che su questo progetto non attecchisce
## sempre e lascia "Identifier not declared" su script validi.
const GrimoireBook := preload("res://arcanium/ui/game_menu/grimoire_book.gd")
## Le tecniche di guerra: il catalogo lo scandisce la risorsa (`catalogo()`),
## qui si mostrano quelle APPRESE e si riapre il loro tomo.
const TecnicaGuerra := preload("res://arcanium/resources/tecnica_guerra.gd")
const SettingsMenuScene := preload("res://arcanium/ui/settings_menu/settings_menu.tscn")

var is_open := false
var settings_open := false
var _section := "inventory"
var _sel := 0
var _flat : Array = []   # [{slot, category}]

## ─── Equipaggiamento ────────────────────────────────────────────────────────
## Prima era una costante `preload`: cinque risorse fisse, senza modo di
## cambiarle. Qui diventano stato — cosa si POSSIEDE e cosa si INDOSSA — che è il
## minimo perché "scorri e cambia" abbia senso.
##
## Lo stato e gli effetti vivono in EquipmentLoadout (autoload): qui restano
## solo il fuoco e la selezione, che sono cose della vista.
## Colonna con il fuoco nella sezione inventario: "equip" o "items".
var _focus := "equip"
var _equip_sel := 0
## ─── Tecniche ───────────────────────────────────────────────────────────────
## Le tecniche di guerra apprese, nell'ordine del catalogo, e quella scelta.
## Si rileggono da qui: Invio riapre il tomo (TomoModal) con la dimostrazione,
## come la prima volta — il popup che insegna e' lo stesso che ripassa.
var _tecniche : Array = []
var _tecnica_sel := 0

var _panel : PanelContainer
var _tab_buttons : Dictionary = {}
var _content : VBoxContainer
var _inventory : Node
var _settings_panel : Control
## Il tomo della sezione Grimorio, ricreato a ogni _render (vedi _render_grimoire).
var _grimoire : Control
var _footer : Label

## Vero se un qualsiasi pannello (sezioni o impostazioni) è aperto: il player
## lo usa per congelare movimento/combattimento.
func is_blocking() -> bool:
	return is_open or settings_open

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# La lastra copre TUTTO lo schermo: il menu non galleggia sul gioco, lo
	# sostituisce, e il mondo resta appena percepibile sotto. Vede MenuStyle.
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", MenuStyle.sfondo())
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)

	# Margini larghi e asimmetrici: il contenuto sta in una colonna centrale, il
	# bordo dello schermo resta vuoto. È quello che fa sembrare la pagina "un
	# tomo aperto" invece di una finestra riempita fino agli angoli.
	var margine := MarginContainer.new()
	margine.add_theme_constant_override("margin_left", 90)
	margine.add_theme_constant_override("margin_right", 90)
	margine.add_theme_constant_override("margin_top", 54)
	margine.add_theme_constant_override("margin_bottom", 40)
	_panel.add_child(margine)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margine.add_child(vbox)

	vbox.add_child(_build_tabs())
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	vbox.add_child(_content)

	vbox.add_child(MenuStyle.separatore())
	_footer = MenuStyle.testo("", MenuStyle.CORPO_AIUTO, MenuStyle.TESTO_FIOCO)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_footer)

	visible = false
	_inventory = get_node("/root/ArcaniumInventory")
	_inventory.changed.connect(_render)

## Schede: maiuscolo spaziato, separate da un punto, con la sola ATTIVA
## sottolineata in oro. Niente pulsanti con lo sfondo — un riquadro premuto
## legge come una toolbar, e qui serve l'indice di un tomo.
func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for sec in SECTIONS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 5)

		var btn := Button.new()
		btn.text = MenuStyle.spaziato(SECTION_LABELS[sec])
		btn.toggle_mode = true
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", MenuStyle.CORPO_SEZIONE)
		for stato in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(stato, StyleBoxEmpty.new())
		btn.pressed.connect(func(): _select_section(sec))
		col.add_child(btn)

		# Il filo sotto la scheda attiva: si accende cambiandone il colore, non
		# aggiungendo o togliendo il nodo (evita salti di layout).
		var filo := ColorRect.new()
		filo.custom_minimum_size = Vector2(0, 2)
		col.add_child(filo)

		row.add_child(col)
		_tab_buttons[sec] = {"btn": btn, "filo": filo}
	return row


## Accende la scheda corrente: testo in oro pieno e filo acceso, le altre fioche.
func _paint_tabs() -> void:
	for sec in SECTIONS:
		var attiva : bool = (sec == _section)
		var btn : Button = _tab_buttons[sec]["btn"]
		var filo : ColorRect = _tab_buttons[sec]["filo"]
		btn.button_pressed = attiva
		var colore : Color = MenuStyle.ORO if attiva else MenuStyle.TESTO_FIOCO
		for stato in ["font_color", "font_pressed_color", "font_hover_color",
				"font_focus_color"]:
			btn.add_theme_color_override(stato, colore)
		filo.color = MenuStyle.ORO if attiva else Color(0, 0, 0, 0)

## ─── Equipaggiamento: cosa indosso, cosa possiedo ───────────────────────────

## Lo stato dell'equipaggiamento NON vive nel menu: vive in EquipmentLoadout,
## che e' anche chi ne applica gli effetti (resistenze).
## Il menu e' una vista sopra quel sistema.
func _loadout() -> Node:
	return get_node_or_null("/root/EquipmentLoadout")

func _equipped_in(slot_id : String):
	var l := _loadout()
	return l.equipped_in(slot_id) if l else STARTER_EQUIPMENT.get(slot_id)


## Tutto ciò che il player può mettere in QUESTO slot. Si scandiscono le
## cartelle delle risorse una volta sola e si tiene il risultato in cache: senza,
## si rileggerebbe il disco a ogni frame di render del menu.
func _owned_for_slot(slot_id : String) -> Array:
	var l := _loadout()
	return l.owned_for_slot(slot_id) if l else []


## Passa al pezzo successivo fra quelli compatibili con lo slot. Resta come
## scorciatoia programmatica; il gesto del giocatore ora passa dalla modale, che
## mostra cosa sta per mettersi addosso invece di farglielo scoprire dopo.
func _equip_next(slot_id : String, dir : int) -> void:
	var l := _loadout()
	if l:
		l.cycle(slot_id, dir)
	_render()


## Modale di scelta del pezzo: illustrazione, numeri e lore prima di decidere.
## Il ciclo alla cieca ("Invio mette il successivo") funzionava con due pezzi;
## con un guardaroba costringeva a passare attraverso tutto e a ricordarsi i
## numeri di ciò che si era già scartato.
const EquipModal := preload("res://arcanium/ui/game_menu/equip_modal.gd")
var _equip_modal : CanvasLayer = null

func _apri_modale_equip(slot_id : String) -> void:
	if _equip_modal != null and is_instance_valid(_equip_modal):
		return
	var scelte := _owned_for_slot(slot_id)
	## Sui TALISMANI si deve poter anche non portare niente: quattro slot senza
	## via d'uscita sarebbero una gabbia, e un talismano situazionale si mette e
	## si toglie. `null` in lista è la voce "Nessuno". Sulle armi non si aggiunge:
	## a mani nude non ci si va per scelta.
	var l := _loadout()
	var svuotabile : bool = l != null and l.has_method("famiglia") \
		and str(l.call("famiglia", slot_id)) == "talismano"
	if svuotabile and (not scelte.is_empty() or _equipped_in(slot_id) != null):
		scelte = [null] + scelte
	if scelte.is_empty():
		return   # niente da scegliere: aprire una lista vuota è solo un vicolo
	_equip_modal = EquipModal.new()
	_equip_modal.name = "EquipModal"
	_equip_modal.set("slot_id", slot_id)
	_equip_modal.set("etichetta_slot", EQUIP_SLOT_LABELS.get(slot_id, slot_id))
	_equip_modal.set("alternative", scelte)
	_equip_modal.set("equipaggiato_ora", _equipped_in(slot_id))
	_equip_modal.connect("equipaggiato", func(_s): _render())
	_equip_modal.connect("chiusa", func(): _equip_modal = null)
	add_child(_equip_modal)


func _select_section(sec : String) -> void:
	_section = sec
	_render()

func _unhandled_input(event : InputEvent) -> void:
	# Lock totale durante la morte per veleno: né inventario né impostazioni.
	var p := get_tree().get_first_node_in_group("player")
	if p and p.get("input_fully_locked"):
		return
	## Con la modale di equipaggiamento aperta il menu non ascolta più: la
	## modale sta SOPRA e consuma l'input da sé. Senza questo, le frecce
	## muoverebbero il cursore in tutti e due i pannelli insieme.
	if _equip_modal != null and is_instance_valid(_equip_modal):
		return
	## E lo stesso col tomo riaperto dalle Tecniche: sta sopra e si chiude da
	## se'; un Esc letto anche qui chiuderebbe il menu insieme al tomo.
	var tomo := get_node_or_null("/root/TomoModal")
	if tomo != null and tomo.has_method("e_aperto") and tomo.e_aperto():
		return
	if event.is_action_pressed("toggle_game_menu"):
		if settings_open:
			return
		_set_open(not is_open)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if is_open:
			_set_open(false)
		elif settings_open:
			_close_settings()
		else:
			_open_settings()
		get_viewport().set_input_as_handled()
		return
	## B del pad: chiude e basta. Non sta in `ui_cancel` perche' a menu chiuso
	## B e' la schivata, e aprirebbe le impostazioni a ogni capriola.
	if event.is_action_pressed("menu_back") and is_blocking():
		if settings_open:
			_close_settings()
		else:
			_set_open(false)
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if event.is_action_pressed("menu_tab_prev"):
		_cycle_section(-1)
	elif event.is_action_pressed("menu_tab_next"):
		_cycle_section(1)
	elif _section == "inventory" and event.is_action_pressed("inv_prev"):
		_move_selection(-1)
	elif _section == "inventory" and event.is_action_pressed("inv_next"):
		_move_selection(1)
	elif _section == "inventory" and event.is_action_pressed("ui_left"):
		# Le due colonne (equipaggiamento / oggetti) si scambiano il fuoco con
		# le frecce laterali: senza, gli slot equipaggiati non erano
		# raggiungibili in alcun modo e si potevano solo guardare.
		_focus = "equip"
		_render()
	elif _section == "inventory" and event.is_action_pressed("ui_right"):
		_focus = "items"
		_render()
	elif _section == "inventory" and event.is_action_pressed("menu_confirm"):
		if _focus == "equip":
			_apri_modale_equip(EQUIP_SLOTS[_equip_sel])
		else:
			_use_selected()
	elif _section == "tecniche" and (event.is_action_pressed("inv_prev") or event.is_action_pressed("ui_up")):
		_muovi_tecnica(-1)
	elif _section == "tecniche" and (event.is_action_pressed("inv_next") or event.is_action_pressed("ui_down")):
		_muovi_tecnica(1)
	elif _section == "tecniche" and event.is_action_pressed("menu_confirm"):
		_rileggi_tecnica()
	elif _section == "grimorio" and _grimoire != null:
		# Il tomo si sfoglia con le frecce laterali, che è il gesto giusto per
		# "gira pagina". Le su/giù ci sono comunque perché è il modo in cui si
		# naviga OGNI altra sezione, e costringere a cambiare mano solo qui
		# sarebbe un'incoerenza gratuita.
		if event.is_action_pressed("ui_right") or event.is_action_pressed("inv_next"):
			_grimoire.sfoglia(1)
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("inv_prev"):
			_grimoire.sfoglia(-1)

func _open_settings() -> void:
	settings_open = true
	_settings_panel = SettingsMenuScene.instantiate()
	_settings_panel.closed.connect(_close_settings)
	add_child(_settings_panel)
	## ⚠️ Questo nodo è un CanvasLayer tenuto `visible = false` quando il menu è
	## chiuso, e le impostazioni gli finiscono SOTTO: senza riaccenderlo il
	## pannello esisteva, riceveva i click e mostrava il cursore, ma non
	## disegnava un pixel. Il sintomo — "il menu non si vede ma il mouse compare"
	## — sembra un problema di rendering e invece è il contenitore spento.
	visible = true
	## Il pannello del menu resta acceso solo se il menu è davvero aperto: da
	## solo, il fondo delle impostazioni ha già la sua lastra scura.
	if _panel:
		_panel.visible = is_open

func _close_settings() -> void:
	settings_open = false
	if _settings_panel:
		_settings_panel.queue_free()
		_settings_panel = null
	if _panel:
		_panel.visible = true
	visible = is_open

## Apre il menu su una sezione precisa. Serve a chi lo chiama da fuori (il menu
## di riposo al Cono manda a "stats"): senza, l'unico modo di aprirlo era il
## tasto, che riapre sempre sull'ultima sezione vista.
func open_at(sezione : String) -> void:
	if SECTIONS.has(sezione):
		_section = sezione
	_set_open(true)


func _set_open(open : bool) -> void:
	is_open = open
	visible = open
	if open:
		_render()

func _cycle_section(dir : int) -> void:
	var i := SECTIONS.find(_section)
	_section = SECTIONS[(i + dir + SECTIONS.size()) % SECTIONS.size()]
	_render()

func _move_selection(dir : int) -> void:
	if _section == "inventory" and _focus == "equip":
		_equip_sel = (_equip_sel + dir + EQUIP_SLOTS.size()) % EQUIP_SLOTS.size()
		_render()
		return
	if _flat.is_empty():
		return
	_sel = (_sel + dir + _flat.size()) % _flat.size()
	_render()

func _use_selected() -> void:
	if _sel >= _flat.size():
		return
	var player := get_tree().get_first_node_in_group("player")
	_inventory.use_slot(_flat[_sel].slot, player)

## ─── Render ──────────────────────────────────────────────────────────────
func _render() -> void:
	_paint_tabs()
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	# Azzerato PRIMA di ricostruire: i figli appena liberati lasciano un
	# riferimento che non è null ma non è più valido, e `_grimoire.sfoglia()`
	# su quello è un crash a scoppio ritardato al primo tasto premuto.
	_grimoire = null
	_aggiorna_piede()
	match _section:
		"inventory": _render_inventory()
		"stats": _render_stats()
		"grimorio": _render_grimoire()
		"tecniche": _render_tecniche()
		_: _render_quests()

## I tasti in fondo cambiano con la sezione. Un piede fisso che dice "Invio
## conferma" nel Grimorio, dove non c'è niente da confermare, insegna un comando
## che non esiste — e fa dubitare di tutti gli altri.
func _aggiorna_piede() -> void:
	if _footer == null:
		return
	var comandi : String = "↑↓ navigate     Enter confirm"
	match _section:
		"grimorio": comandi = "← → turn page"
		"tecniche": comandi = "↑↓ navigate     Enter reread the tome" if not _tecniche.is_empty() else ""
		"stats", "quests": comandi = ""
	var righe : Array[String] = ["Q/E section"]
	if comandi != "":
		righe.append(comandi)
	righe.append("I / Esc close")
	_footer.text = MenuStyle.spaziato("     ".join(righe))


func _build_equip_slot(slot_id : String, selezionato : bool = false) -> Control:
	var res = _equipped_in(slot_id)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", MenuStyle.riga(selezionato))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var icon_lbl : Label = MenuStyle.testo(
		res.icon if res else EQUIP_SLOT_EMPTY_ICON.get(slot_id, "—"), 22,
		MenuStyle.ORO if res else MenuStyle.TESTO_FIOCO)
	icon_lbl.custom_minimum_size = Vector2(30, 0)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(icon_lbl)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	info.add_child(MenuStyle.testo(
		MenuStyle.spaziato(EQUIP_SLOT_LABELS.get(slot_id, slot_id)),
		MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))
	info.add_child(MenuStyle.testo(res.name if res else "—", MenuStyle.CORPO_VOCE))

	if res:
		box.tooltip_text = res.lore

	return box

func _render_inventory() -> void:
	var groups : Array = _inventory.by_category()
	_flat = []
	for g in groups:
		for slot in g.slots:
			_flat.append({"slot": slot, "category": g.category})
	if _flat.is_empty():
		_sel = 0
	else:
		_sel = ((_sel % _flat.size()) + _flat.size()) % _flat.size()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(row)

	var equip := VBoxContainer.new()
	equip.custom_minimum_size = Vector2(330, 0)
	equip.add_theme_constant_override("separation", 2)
	row.add_child(equip)
	equip.add_child(MenuStyle.intestazione("Equipment"))
	for i in EQUIP_SLOTS.size():
		equip.add_child(_build_equip_slot(EQUIP_SLOTS[i],
			_focus == "equip" and i == _equip_sel))

	# Quante alternative ha lo slot selezionato: senza dirlo, premere Invio su
	# uno slot con un solo pezzo sembra un comando che non funziona.
	if _focus == "equip":
		var slot_id : String = EQUIP_SLOTS[_equip_sel]
		var quante := _owned_for_slot(slot_id).size()
		var aiuto : String = tr("Enter to change  ·  %d available") % quante \
			if quante > 1 else "No alternatives owned"
		var l : Label = MenuStyle.testo(aiuto, MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		equip.add_child(l)

	var sep := VSeparator.new()
	row.add_child(sep)

	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(320, 0)
	row.add_child(list)
	if _flat.is_empty():
		list.add_child(MenuStyle.testo("Inventory empty", MenuStyle.CORPO_VOCE,
			MenuStyle.TESTO_FIOCO))
	else:
		var idx := 0
		for g in groups:
			# Intestazioni di categoria e riga selezionata passano da MenuStyle:
			# prima erano colori scritti a mano (un lilla e un giallo che nella
			# palette non esistono) ed erano l'unico punto del menu in cui il
			# filo d'oro non era d'oro.
			list.add_child(MenuStyle.testo(
				MenuStyle.spaziato(CATEGORY_LABELS.get(g.category, g.category)),
				MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))
			for slot in g.slots:
				var count_str := (" ×%d" % slot.count) if slot.count > 1 else ""
				list.add_child(MenuStyle.testo(
					"%s %s%s" % [slot.def.icon, slot.def.item_name, count_str],
					MenuStyle.CORPO_VOCE,
					MenuStyle.ORO if idx == _sel else MenuStyle.TESTO))
				idx += 1

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	row.add_child(detail)
	if not _flat.is_empty():
		var cur = _flat[_sel]
		var def : ArcaniumItemResource = cur.slot.def
		detail.add_child(MenuStyle.titolo("%s  %s" % [def.icon, def.item_name], 22,
			MenuStyle.TESTO))
		detail.add_child(MenuStyle.testo(
			MenuStyle.spaziato(CATEGORY_LABELS.get(cur.category, cur.category)),
			MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))

		if def.lore != "":
			# Il lore passa a RichTextLabel come nel grimorio: stessa resa, e la
			# possibilità di dare enfasi dentro la frase invece di spezzarla in
			# tre nodi. La larghezza è DICHIARATA — vedi LARGHEZZA_DETTAGLIO.
			detail.add_child(MenuStyle.corpo_ricco(def.lore, LARGHEZZA_DETTAGLIO))

		detail.add_child(MenuStyle.testo(
			"Enter — Use" if def.effect != "none" else "Story item",
			MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))

func _render_stats() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var wielder := player.get_node_or_null("MarcheWielder") if player else null
	var vitals := player.get_node_or_null("PlayerVitals") if player else null
	var health_system = player.health_system if player and "health_system" in player else null
	var stats : MarcheStats = wielder.stats if wielder else MarcheStats.new()

	_content.add_child(MenuStyle.titolo("Archmage of Dawnkeep — House Dawnkeep",
		24, MenuStyle.TESTO))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 32)
	_content.add_child(cols)

	var vitals_box := VBoxContainer.new()
	# Le colonne dichiarano la loro larghezza: senza, si stringono sul contenuto
	# e il filo d'oro sotto l'intestazione — che è lungo quanto la colonna — si
	# riduce a un trattino, o sparisce del tutto se la colonna è vuota.
	vitals_box.custom_minimum_size = Vector2(300, 0)
	cols.add_child(vitals_box)
	vitals_box.add_child(MenuStyle.intestazione("Vitals"))
	if health_system:
		vitals_box.add_child(_stat_row("Health", "%d / %d" % [health_system.current_health, health_system.total_health]))
	if vitals:
		vitals_box.add_child(_stat_row("Stamina", "%d / %d" % [int(ceil(vitals.stamina)), int(vitals.max_stamina)]))
		vitals_box.add_child(_stat_row("Arcanium", "%d / %d" % [int(ceil(vitals.arcanium)), int(vitals.max_arcanium)]))

	var marks_box := VBoxContainer.new()
	marks_box.custom_minimum_size = Vector2(340, 0)
	cols.add_child(marks_box)
	marks_box.add_child(MenuStyle.intestazione("The Seven Marks"))
	for i in MarcheStats.SIGLE.size():
		marks_box.add_child(_stat_row("%s  %s" % [MarcheStats.SIGLE_MOSTRATE[i], tr(MarcheStats.NOMI[i])], str(stats.get_marca(i))))

	_content.add_child(MenuStyle.testo(
		"Level up at the Channeling Cones while resting (coming soon).",
		MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))

func _stat_row(label_text : String, value_text : String) -> Control:
	var row := HBoxContainer.new()
	var l : Label = MenuStyle.testo(label_text, MenuStyle.CORPO_VOCE,
		MenuStyle.TESTO_FIOCO)
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	row.add_child(MenuStyle.testo(value_text, MenuStyle.CORPO_VOCE, MenuStyle.TESTO))
	return row

## ─── Grimorio ────────────────────────────────────────────────────────────
## Il grimorio non è più un elenco dentro questa sezione: è un tomo di pergamena
## sfogliabile che vive per conto suo in grimoire_book.gd — una magia per
## apertura, illustrazione e numeri a sinistra, testo a destra. Qui resta solo
## l'aggancio, che è quanto il menu deve sapere.
##
## Si ricostruisce a ogni _render (cambio di scheda) e ricarica le risorse: il
## giocatore può aver imparato una magia mentre il menu era chiuso, e la
## pagina nuova deve esserci già alla prima apertura.
func _render_grimoire() -> void:
	_grimoire = GrimoireBook.new()
	_grimoire.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_grimoire)

## ─── Tecniche ───────────────────────────────────────────────────────────────
## A sinistra le tecniche apprese, a destra quella scelta: come si esegue (il
## testo per il giocatore) e la lore. Quelle non ancora apprese non compaiono
## né come ombra né come conteggio: un tomo che non si e' trovato non si
## annuncia — lo si trova.
func _render_tecniche() -> void:
	_tecniche = []
	for t in TecnicaGuerra.catalogo():
		if t.has_method("appresa") and t.appresa(get_tree()):
			_tecniche.append(t)
	_content.add_child(MenuStyle.intestazione("War techniques"))
	if _tecniche.is_empty():
		_tecnica_sel = 0
		_content.add_child(MenuStyle.corpo_ricco(
			"[i]No war techniques yet. They're learned from tomes, and tomes are found.[/i]",
			LARGHEZZA_DETTAGLIO, MenuStyle.CORPO_VOCE, MenuStyle.TESTO_FIOCO))
		return
	_tecnica_sel = ((_tecnica_sel % _tecniche.size()) + _tecniche.size()) % _tecniche.size()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(row)

	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(320, 0)
	list.add_theme_constant_override("separation", 2)
	row.add_child(list)
	for i in _tecniche.size():
		var t : Resource = _tecniche[i]
		list.add_child(MenuStyle.testo("%s  %s" % [str(t.get("icon")), str(t.get("name"))],
			MenuStyle.CORPO_VOCE, MenuStyle.ORO if i == _tecnica_sel else MenuStyle.TESTO))

	row.add_child(VSeparator.new())

	## Colonna a larghezza fissa: un testo che corre per tutto lo schermo non
	## si legge, e "come si esegue" e' fatto per essere letto.
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(LARGHEZZA_TECNICA, 0)
	detail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	detail.add_theme_constant_override("separation", 8)
	row.add_child(detail)
	var cur : Resource = _tecniche[_tecnica_sel]
	detail.add_child(MenuStyle.titolo("%s  %s" % [str(cur.get("icon")), str(cur.get("name"))], 22, MenuStyle.TESTO))
	## Cosa apre, se apre qualcosa: l'Arcieria mette in mano gli archi.
	var tipi : PackedStringArray = cur.get("abilita_tipi") if ("abilita_tipi" in cur) else PackedStringArray()
	if not tipi.is_empty():
		var nomi : PackedStringArray = PackedStringArray()
		for tipo in tipi:
			nomi.append(str(TIPI_ARMA_LABELS.get(tipo, tipo)))
		detail.add_child(MenuStyle.testo(MenuStyle.spaziato(tr("Unlocks equipment: ") + ", ".join(PackedStringArray(Array(nomi).map(func(n): return tr(n))))),
			MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))
	var come : String = str(cur.get("come_si_esegue")).strip_edges()
	if come != "":
		detail.add_child(MenuStyle.corpo_ricco(come, LARGHEZZA_TECNICA, MenuStyle.CORPO_VOCE, MenuStyle.TESTO))
	var lore : String = str(cur.get("lore")).strip_edges()
	if lore != "":
		detail.add_child(MenuStyle.corpo_ricco("[i]%s[/i]" % lore, LARGHEZZA_TECNICA,
			MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))
	detail.add_child(MenuStyle.testo("Enter — Reread the tome", MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))


func _muovi_tecnica(dir : int) -> void:
	if _tecniche.is_empty():
		return
	_tecnica_sel = (_tecnica_sel + dir + _tecniche.size()) % _tecniche.size()
	_render()


## Riapre il tomo della tecnica scelta: e' lo stesso popup della prima volta,
## con la dimostrazione. Sta sopra il menu (layer 28 contro 10) e si chiude da
## se'; il menu resta aperto sotto, dov'era.
func _rileggi_tecnica() -> void:
	if _tecniche.is_empty():
		return
	var tomo := get_node_or_null("/root/TomoModal")
	if tomo != null and tomo.has_method("apri"):
		tomo.apri(_tecniche[_tecnica_sel])


## Il diario legge da QuestManager invece di essere una riga scritta a mano:
## prima diceva "La Traccia Perduta — non avviata" anche a quest finita.
func _render_quests() -> void:
	_content.add_child(MenuStyle.intestazione("Journal"))

	var quests := get_node_or_null("/root/QuestManager")
	var ids : Array = quests.known_quests() if quests else []
	if ids.is_empty():
		_content.add_child(MenuStyle.corpo_ricco(
			"[i]The journal fills in as the story goes on.[/i]",
			LARGHEZZA_DETTAGLIO, MenuStyle.CORPO_VOCE, MenuStyle.TESTO_FIOCO))
		return

	for id in ids:
		var completa : bool = quests.is_complete(id)
		var stato : String = tr("complete") if completa else tr("in progress")
		_content.add_child(MenuStyle.titolo(
			"%s — %s" % [quests.title_of(id), stato], 22,
			MenuStyle.TESTO_FIOCO if completa else MenuStyle.TESTO))

		var voci : Array = quests.entries_of(id)
		if voci.is_empty():
			_content.add_child(MenuStyle.corpo_ricco(
				"[i]No notes.[/i]", LARGHEZZA_DETTAGLIO,
				MenuStyle.CORPO_VOCE, MenuStyle.TESTO_FIOCO))
			continue
		## Le tappe in ordine cronologico, l'ultima in evidenza: è quella che
		## dice al giocatore cosa sta facendo adesso.
		var righe : PackedStringArray = PackedStringArray()
		for i in voci.size():
			var ultima : bool = (i == voci.size() - 1) and not completa
			righe.append("• [b]%s[/b]" % voci[i] if ultima else "• %s" % voci[i])
		_content.add_child(MenuStyle.corpo_ricco(
			"\n".join(righe), LARGHEZZA_DETTAGLIO,
			MenuStyle.CORPO_VOCE, MenuStyle.TESTO))
