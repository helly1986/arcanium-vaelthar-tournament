extends Control
class_name SpellBar

## Barra incantesimi/oggetti in basso al centro dello schermo. Port pulito
## di Arcanium-Lite/src/ui/SpellBar.js (NON copiato, ricostruito in GDScript)
## con lo stile "pannelli scuri semitrasparenti" già usato in arcanium_hud.gd.
##
## Due sezioni affiancate, separate da un piccolo divisore verticale, piu' i
## cristalli in coda:
##   SPELL      (azzurro) — 4 slot: J / RB / LT / RT  (slot 1 = Shard di Ghiaccio,
##                           illustrato con assets/ui/iceshard.jpg copiato in
##                           res://arcanium/ui/hud/icons/)
##   OGGETTI    (ambra)   — 3 slot, il primo sul tasto R
## Le EVOCAZIONI non ci sono piu' (decisione dell'autore del 2026-10-21): non
## sono del campione, avranno la loro modalita', il battleground.
##
## Ogni slot mostra: illustrazione o icona testuale, tasto, e supporta:
##   - stato "vuoto" (placeholder "—" o "?", attenuato)
##   - selezione corrente (bordo luminoso) via set_selected(kind, index)
##   - cooldown (velo scuro dall'alto che si ritira) via set_cooldown(kind, index, ratio)
##
## Il contratto con l'altro stream (sistema di selezione incantesimi) è un nodo
## con class_name SpellSelection che espone current_spell e il
## signal selection_changed(kind:String, resource). bind_selection() si collega
## SOLO se quel signal esiste: la SpellBar funziona anche senza, mostrando i
## placeholder configurati qui sotto.

const ICON_ICE := preload("res://arcanium/ui/hud/icons/iceshard.jpg")
const ICON_TECH := preload("res://arcanium/ui/hud/icons/technique.jpg")

const COL_SPELL := Color("#6f9dff")
const COL_ITEM := Color("#e0a45a")
const COL_CRYSTAL := Color("#8b6cff")
## Bordo dello slot ATTIVO: giallo, che pulsa. Uno solo alla volta.
const COL_ACTIVE := Color("#ffd24a")

const SLOT_SIZE := Vector2(58, 58)

## Definizione statica delle sezioni: kind → { color, label, slots: [{key, icon|img, title}] }
## icon = testo (emoji/placeholder), img = Texture2D per l'illustrazione.
var _sections := {
	"spell": {
		"color": COL_SPELL, "label": "SPELL",
		"slots": [
			{"key": "J", "img": ICON_ICE, "title": "Ice Shard"},
			{"key": "RB", "icon": "—", "title": ""},
			{"key": "LT", "icon": "—", "title": ""},
			{"key": "RT", "icon": "—", "title": ""},
		],
	},
	## OGGETTI: sostituisce la vecchia "TECNICA" (la lucida tecnica è stata
	## rimossa). Gli slot partono vuoti e li riempie `bind_inventory` dagli
	## oggetti reali dell'InventorySystem (pozione, firebomba...). Il tasto R usa
	## l'oggetto attivo; si cicla con 1/2.
	"items": {
		"color": COL_ITEM, "label": "ITEMS",
		"slots": [
			{"key": "R", "icon": "?", "title": ""},
			{"key": "", "icon": "?", "title": ""},
			{"key": "", "icon": "?", "title": ""},
		],
	},
}

var _panel : PanelContainer
## _slots[kind][index] = { root: PanelContainer, cooldown: ColorRect, sb_normal, sb_selected, title }
var _slots : Dictionary = {}
var _selected_kind : String = ""
var _selected_index : int = -1

var _dialogue_ui : Node = null

## Sorgenti opzionali agganciate dall'HUD/player.
var _inventory : Node = null
var _crystal_label : Label = null
var _selection : Node = null


func _ready() -> void:
	# La SpellBar deve occupare l'intero rect del genitore, così il pannello
	# ancorato basso-centro al suo interno cade davvero in fondo allo schermo.
	# ⚠️ `set_anchors_preset` da solo lasciava questo Control a dimensione (0,0)
	# (il pannello interno finiva a coordinate NEGATIVE, fuori schermo in alto a
	# sinistra: la barra non si vedeva). Servono anchor E offset insieme, più un
	# aggancio a `resized`/`ready` del genitore perché la dimensione venga presa
	# anche quando il layout del genitore è pronto DOPO questo _ready.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent := get_parent()
	if parent is Control:
		parent.resized.connect(_fit_to_parent)
	_fit_to_parent()

	_build_bar()
	_connect_dialogue_overlap()

## Ricopia la dimensione del genitore. Chiamata anche su `resized` del genitore:
## se il layout del genitore matura dopo il nostro _ready, senza questo la barra
## resterebbe a (0,0).
func _fit_to_parent() -> void:
	var parent := get_parent()
	if parent is Control:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		size = (parent as Control).size


## ─── Costruzione ────────────────────────────────────────────────────────────
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.05, 0.55)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.set_border_width_all(1)
	return sb

func _build_bar() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# La barra sta ATTACCATA AL FONDO (convenzione: la barra azioni è l'ultima
	# cosa in basso). La BossBar ora le sta SOPRA (spostata in
	# arena_senza_fuoco.tscn), non più sotto.
	_panel.offset_bottom = -18
	add_child(_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(hbox)

	var kinds := ["spell", "items"]
	for i in kinds.size():
		var kind : String = kinds[i]
		hbox.add_child(_build_section(kind, _sections[kind]))
		hbox.add_child(_make_separator())

	# Contatore Arcanium CRISTALLIZZATO integrato in coda alla barra (prima era
	# un pannello a sé in basso a destra, ora tutto è in un unico modulo).
	hbox.add_child(_build_crystal_counter())

func _build_section(kind : String, data : Dictionary) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = data.label
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", data.color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row)

	_slots[kind] = {}
	for idx in data.slots.size():
		var slot_def : Dictionary = data.slots[idx]
		row.add_child(_build_slot(kind, idx + 1, slot_def, data.color))

	return vbox

func _build_slot(kind : String, index : int, def : Dictionary, accent : Color) -> Control:
	var root := PanelContainer.new()
	root.custom_minimum_size = SLOT_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var is_empty : bool = (def.get("icon", "") in ["?", "—"]) and not def.has("img")
	var sb_normal := _slot_style(accent, false, is_empty)
	var sb_selected := _slot_style(accent, true, is_empty)
	root.add_theme_stylebox_override("panel", sb_normal)

	var stack := Control.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)

	# Illustrazione (TextureRect) SEMPRE presente, così bind_inventory può
	# riempirla a runtime anche negli slot partiti come testuali (gli oggetti).
	var tex := TextureRect.new()
	tex.name = "Img"
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 4
	tex.offset_top = 4
	tex.offset_right = -4
	tex.offset_bottom = -4
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.visible = def.has("img")
	if def.has("img"):
		tex.texture = def.img
	if def.get("title", "") != "":
		tex.tooltip_text = def.title
	stack.add_child(tex)

	# Icona testuale di ripiego, visibile quando non c'è illustrazione.
	var icon_lbl := Label.new()
	icon_lbl.name = "Icon"
	icon_lbl.text = def.get("icon", "?")
	icon_lbl.add_theme_font_size_override("font_size", 22)
	var icon_col := Color(1, 1, 1, 0.85) if not is_empty else Color(1, 1, 1, 0.25)
	icon_lbl.add_theme_color_override("font_color", icon_col)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_lbl.offset_bottom = 0
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_lbl.visible = not def.has("img")
	stack.add_child(icon_lbl)

	# Overlay di cooldown: velo scuro che scende dall'alto, altezza = ratio.
	var cooldown := ColorRect.new()
	cooldown.color = Color(0, 0, 0, 0.65)
	cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cooldown.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cooldown.anchor_bottom = 0.0
	cooldown.offset_bottom = 0.0
	stack.add_child(cooldown)

	# (Le etichette-tasto J/RB/LT/RT ecc. sono state rimosse: non riflettevano
	# più i controlli reali — si casta col destro e si cicla con ,/. )

	# Bordo ATTIVO giallo pulsante: overlay separato, mostrato su UN SOLO slot
	# alla volta (quello selezionato). Tenuto fuori dallo stile normale così può
	# pulsare via modulate senza ricostruire lo StyleBox ogni frame.
	var border := Panel.new()
	border.name = "ActiveBorder"
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0, 0, 0, 0)
	bs.set_corner_radius_all(8)
	bs.border_color = COL_ACTIVE
	bs.set_border_width_all(3)
	bs.shadow_color = Color(COL_ACTIVE.r, COL_ACTIVE.g, COL_ACTIVE.b, 0.6)
	bs.shadow_size = 6
	border.add_theme_stylebox_override("panel", bs)
	border.visible = false
	stack.add_child(border)

	# Badge conteggio (alto a destra), usato dagli oggetti. Nascosto finché
	# bind_inventory non lo popola.
	var count_lbl := Label.new()
	count_lbl.name = "Count"
	count_lbl.add_theme_font_size_override("font_size", 13)
	count_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	count_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	count_lbl.add_theme_constant_override("shadow_offset_x", 1)
	count_lbl.add_theme_constant_override("shadow_offset_y", 1)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	count_lbl.offset_right = -4
	count_lbl.offset_top = 2
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_lbl.visible = false
	stack.add_child(count_lbl)

	_slots[kind][index] = {
		"root": root, "cooldown": cooldown, "img": tex, "icon": icon_lbl,
		"count": count_lbl, "border": border,
		"sb_normal": sb_normal, "sb_selected": sb_selected,
		"title": def.get("title", ""),
	}
	return root

func _slot_style(accent : Color, selected : bool, is_empty : bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.11, 0.7 if not is_empty else 0.35)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(2)
	if selected:
		sb.border_color = accent
		sb.set_border_width_all(2)
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.5)
		sb.shadow_size = 6
	else:
		sb.border_color = Color(1, 1, 1, 0.08)
		sb.set_border_width_all(1)
	return sb


## ─── API pubblica ───────────────────────────────────────────────────────────

## Evidenzia lo slot ATTIVO con un bordo giallo pulsante. UNO SOLO alla volta:
## mostrare un nuovo attivo spegne il precedente. index è 1-based (J=1, RB=2...).
## index <= 0 deseleziona.
func set_selected(kind : String, index : int) -> void:
	if _selected_kind != "" and _slots.has(_selected_kind) and _slots[_selected_kind].has(_selected_index):
		_slots[_selected_kind][_selected_index].border.visible = false

	_selected_kind = kind
	_selected_index = index
	if kind != "" and _slots.has(kind) and _slots[kind].has(index):
		_slots[kind][index].border.visible = true

## Pulsazione del bordo attivo: alpha che oscilla morbida. Un solo nodo animato
## per volta (quello selezionato), costo trascurabile.
func _process(_delta : float) -> void:
	if _selected_kind == "" or not _slots.has(_selected_kind):
		return
	var slot = _slots[_selected_kind].get(_selected_index)
	if slot == null or not slot.border.visible:
		return
	var a : float = 0.55 + 0.45 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.3))
	slot.border.modulate.a = a

## Imposta l'overlay di cooldown per uno slot. ratio 0 = pronto (nessun velo),
## 1 = appena usato (velo pieno che copre tutto lo slot dall'alto).
func set_cooldown(kind : String, index : int, ratio : float) -> void:
	if not (_slots.has(kind) and _slots[kind].has(index)):
		return
	var r := clampf(ratio, 0.0, 1.0)
	_slots[kind][index].cooldown.anchor_bottom = r

## Collegamento opzionale col sistema di selezione incantesimi (altro stream).
## selection_node può essere null o non avere il signal: in quel caso questa
## funzione non fa nulla e la barra resta sui placeholder statici.
func bind_selection(selection_node : Node) -> void:
	if selection_node == null:
		return
	_selection = selection_node
	if selection_node.has_signal("selection_changed"):
		selection_node.selection_changed.connect(_on_selection_changed)
	# Riempi gli slot SPELL con le risorse realmente note: icona + nome, il
	# resto svuotato.
	if "known_spells" in selection_node:
		_populate_casting_slots("spell", selection_node.known_spells)
	# Evidenzia subito quello attivo.
	if "current_spell" in selection_node and selection_node.current_spell != null:
		_on_selection_changed("spell", selection_node.current_spell)

## Riempie gli slot della sezione di CASTING (spell) con le risorse
## note: slot i = lista[i] (icona + nome), gli slot in più diventano vuoti.
func _populate_casting_slots(kind : String, list : Array) -> void:
	var slots : Dictionary = _slots.get(kind, {})
	for i in slots.size():
		var slot = slots.get(i + 1)
		if slot == null:
			continue
		if i < list.size() and list[i] != null:
			var res = list[i]
			# Illustrazione (come in Arcanium-Lite) se la risorsa la porta,
			# altrimenti ripiego sull'icona testuale.
			var img_tex : Texture2D = res.image if ("image" in res and res.image != null) else null
			if img_tex != null:
				slot.img.texture = img_tex
				slot.img.visible = true
				slot.icon.visible = false
			else:
				slot.img.visible = false
				slot.icon.visible = true
				slot.icon.text = res.icon if ("icon" in res) else "◈"
				slot.icon.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			slot.img.tooltip_text = res.name if ("name" in res) else ""
		else:
			slot.img.visible = false
			slot.icon.visible = true
			slot.icon.text = "—"
			slot.icon.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))

func _make_separator() -> VSeparator:
	var sep := VSeparator.new()
	sep.add_theme_color_override("separator", Color(1, 1, 1, 0.08))
	return sep

## Blocco "◈ N" in coda alla barra. Riprende icona/stile del vecchio contatore
## in basso a destra, ora integrato qui.
func _build_crystal_counter() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = "CRYSTALS"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COL_CRYSTAL)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, SLOT_SIZE.y)
	vbox.add_child(row)

	var glyph := Label.new()
	glyph.text = "◈"
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color", COL_CRYSTAL)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(glyph)

	_crystal_label = Label.new()
	_crystal_label.text = "0"
	_crystal_label.add_theme_font_size_override("font_size", 20)
	_crystal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_crystal_label)
	return vbox

## Collega il contatore cristalli all'autoload persistente CrystalBank.
func bind_crystals() -> void:
	var bank := get_node_or_null("/root/CrystalBank")
	if bank == null or _crystal_label == null:
		return
	if bank.has_signal("changed"):
		bank.changed.connect(func(amount): _crystal_label.text = str(amount))
	if "crystals" in bank:
		_crystal_label.text = str(bank.crystals)

## Collega gli slot OGGETTI all'InventorySystem: mostra texture + conteggio
## degli oggetti reali (pozione, firebomba...). Degrada in silenzio se il nodo
## non c'è o non espone inventory_updated.
func bind_inventory(inv : Node) -> void:
	if inv == null:
		return
	_inventory = inv
	if inv.has_signal("inventory_updated"):
		inv.inventory_updated.connect(_on_inventory_updated)
	if "inventory" in inv and inv.inventory is Array:
		_on_inventory_updated(inv.inventory)

func _on_inventory_updated(items : Array) -> void:
	var slots : Dictionary = _slots.get("items", {})
	for i in slots.size():
		var slot = slots.get(i + 1)
		if slot == null:
			continue
		if i < items.size() and items[i] != null:
			_fill_item_slot(slot, items[i])
		else:
			_clear_item_slot(slot)

func _fill_item_slot(slot : Dictionary, item) -> void:
	var tex = item.texture if ("texture" in item) else null
	if tex != null:
		slot.img.texture = tex
		slot.img.visible = true
		slot.icon.visible = false
	else:
		slot.icon.text = item.icon if ("icon" in item) else "●"
		slot.icon.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		slot.icon.visible = true
		slot.img.visible = false
	slot.img.tooltip_text = item.item_name if ("item_name" in item) else ""
	var n : int = int(item.count) if ("count" in item) else 0
	slot.count.text = "x%d" % n
	slot.count.visible = true

func _clear_item_slot(slot : Dictionary) -> void:
	slot.img.visible = false
	slot.icon.visible = true
	slot.icon.text = "?"
	slot.icon.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	slot.count.visible = false

func _on_selection_changed(kind : String, resource) -> void:
	if kind != "spell":
		return
	# Ripopola le icone della sezione (non solo la prima volta via bind_selection).
	if _selection != null and ("known_spells" in _selection):
		_populate_casting_slots("spell", _selection.known_spells)

	# L'indice dello slot = posizione della risorsa nella lista nota (1-based).
	# Così ",/." (che spostano current_spell in SpellSelection) muovono il bordo
	# giallo esattamente sullo spell corrispondente.
	var index := 1
	if _selection != null and resource != null:
		var list : Array = _selection.known_spells if ("known_spells" in _selection) else []
		var found := list.find(resource)
		if found >= 0:
			index = found + 1
	set_selected("spell", index)


## ─── Anti-sovrapposizione coi dialoghi ──────────────────────────────────────
## Il pannello dialoghi (arcanium/ui/dialogue/dialogue_ui.gd) è ancorato
## BOTTOM_WIDE, offset_top=-220..offset_bottom=-40: occupa la stessa fascia
## basso-centro della SpellBar. Assunzione: DialogueUI è un autoload/CanvasLayer
## raggiungibile in /root/DialogueUI e a monte DialogueManager in /root/DialogueManager
## emette dialogue_started/dialogue_ended (stessi segnali che DialogueUI ascolta).
## Quando un dialogo è attivo la SpellBar fa fade-out; al termine fa fade-in.
func _connect_dialogue_overlap() -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null:
		return
	if dm.has_signal("dialogue_started"):
		dm.dialogue_started.connect(_on_dialogue_started)
	if dm.has_signal("dialogue_ended"):
		dm.dialogue_ended.connect(_on_dialogue_ended)

func _on_dialogue_started(_npc_id : String = "") -> void:
	create_tween().tween_property(self, "modulate:a", 0.0, 0.25)

func _on_dialogue_ended(_npc_id : String = "") -> void:
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
