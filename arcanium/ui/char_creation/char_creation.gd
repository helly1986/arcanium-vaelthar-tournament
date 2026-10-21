extends Control

## Schermata di creazione personaggio — scelta Casata + genere, con anteprima
## delle Sette Marche di partenza. Solo UI: niente cambio scena né salvataggio,
## ci pensa il main menu tramite i segnali `confirmed`/`cancelled`.

signal confirmed(house_id : String, gender : String)
signal cancelled

const HouseCatalog := preload("res://arcanium/systems/house_catalog.gd")

## Ordine delle Sette Marche (le chiavi sono le sigle interne di HouseCatalog);
## nomi e sigle come li legge il giocatore stanno in MarcheStats.
const MARCHE_ORDER := ["CON", "EMP", "VOL", "BON", "PER", "SAC", "RES"]
const MarcheStats := preload("res://arcanium/resources/marche_stats.gd")

var _selected_house : String = HouseCatalog.DEFAULT_HOUSE
var _house_buttons : Dictionary = {}   # house_id -> Button
var _marche_value_labels : Dictionary = {}   # sigla -> Label
var _confirm_btn : Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.anchor_left = 0.1
	card.anchor_top = 0.1
	card.anchor_right = 0.9
	card.anchor_bottom = 0.9
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	vbox.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	body.add_child(_build_house_list())

	var sep := VSeparator.new()
	body.add_child(sep)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	right.add_child(_build_marche_panel())
	right.add_child(_build_gender_panel())

	vbox.add_child(_build_footer())

	_select_house(_selected_house)

func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.08, 0.92)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	return sb

func _build_header() -> Control:
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Choose your House"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Create your Archmage"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.58, 0.65))
	box.add_child(subtitle)
	return box

## ─── Lista casate ───────────────────────────────────────────────────────────
func _build_house_list() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for house_id in HouseCatalog.ORDER:
		list.add_child(_build_house_row(house_id))

	return scroll

func _build_house_row(house_id : String) -> Control:
	var data : Dictionary = HouseCatalog.HOUSES[house_id]
	var state : String = data.get("state", "locked")
	var playable := state == "unlocked"

	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0, 64)
	btn.disabled = not playable
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal", _house_row_style(data, false))
	btn.add_theme_stylebox_override("hover", _house_row_style(data, false))
	btn.add_theme_stylebox_override("pressed", _house_row_style(data, true))
	btn.add_theme_stylebox_override("disabled", _house_row_style(data, false, true))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(row)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(4, 0)
	accent.color = Color(data.get("color", "#ffffff")) if playable else Color(0.4, 0.4, 0.4)
	row.add_child(accent)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = data.get("name", house_id)
	name_lbl.add_theme_font_size_override("font_size", 16)
	if not playable:
		name_lbl.add_theme_color_override("font_color", Color(0.55, 0.53, 0.58))
	name_row.add_child(name_lbl)

	if not playable:
		var lock_lbl := Label.new()
		lock_lbl.text = tr("  —  Coming soon") if state == "locked" else tr("  —  New Game+ only")
		lock_lbl.add_theme_font_size_override("font_size", 12)
		lock_lbl.add_theme_color_override("font_color", Color(0.55, 0.4, 0.4) if state == "ng_plus" else Color(0.5, 0.48, 0.55))
		name_row.add_child(lock_lbl)

	var motto_lbl := Label.new()
	motto_lbl.text = data.get("motto", "")
	motto_lbl.add_theme_font_size_override("font_size", 11)
	motto_lbl.add_theme_color_override("font_color", Color(0.55, 0.53, 0.6) if playable else Color(0.42, 0.4, 0.45))
	motto_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(motto_lbl)

	var affinity_lbl := Label.new()
	affinity_lbl.text = data.get("affinity", "")
	affinity_lbl.add_theme_font_size_override("font_size", 11)
	affinity_lbl.add_theme_color_override("font_color", Color(0.5, 0.48, 0.55) if playable else Color(0.4, 0.38, 0.42))
	info.add_child(affinity_lbl)

	if playable:
		btn.pressed.connect(_select_house.bind(house_id))

	_house_buttons[house_id] = btn
	return btn

func _house_row_style(data : Dictionary, selected : bool, disabled : bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if disabled:
		sb.bg_color = Color(1, 1, 1, 0.015)
	elif selected:
		sb.bg_color = Color(1, 1, 1, 0.1)
	else:
		sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	if selected:
		sb.border_color = Color(data.get("color", "#ffffff"))
		sb.set_border_width_all(2)
	return sb

func _select_house(house_id : String) -> void:
	var data : Dictionary = HouseCatalog.HOUSES.get(house_id, {})
	if data.get("state", "locked") != "unlocked":
		return
	_selected_house = house_id
	for id in _house_buttons.keys():
		var btn : Button = _house_buttons[id]
		var d : Dictionary = HouseCatalog.HOUSES[id]
		var playable : bool = d.get("state", "locked") == "unlocked"
		var sel : bool = (id == _selected_house)
		btn.button_pressed = sel
		if playable:
			btn.add_theme_stylebox_override("normal", _house_row_style(d, sel))
			btn.add_theme_stylebox_override("hover", _house_row_style(d, sel))
			btn.add_theme_stylebox_override("pressed", _house_row_style(d, sel))
	_update_marche_panel()
	if _confirm_btn:
		_confirm_btn.disabled = false

## ─── Pannello Sette Marche ──────────────────────────────────────────────────
func _build_marche_panel() -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.03)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	box.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	box.add_child(vbox)

	var title := Label.new()
	title.text = "The Seven Marks"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.6, 0.58, 0.68))
	vbox.add_child(title)

	for sigla in MARCHE_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var sigla_lbl := Label.new()
		sigla_lbl.text = MarcheStats.SIGLE_MOSTRATE[MarcheStats.SIGLE.find(sigla)]
		sigla_lbl.custom_minimum_size = Vector2(40, 0)
		sigla_lbl.add_theme_color_override("font_color", Color(0.55, 0.53, 0.6))
		row.add_child(sigla_lbl)

		var nome_lbl := Label.new()
		nome_lbl.text = MarcheStats.NOMI[MarcheStats.SIGLE.find(sigla)]
		nome_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nome_lbl)

		var value_lbl := Label.new()
		value_lbl.text = "—"
		value_lbl.add_theme_font_size_override("font_size", 15)
		row.add_child(value_lbl)
		_marche_value_labels[sigla] = value_lbl

	_marche_box_ref = box
	return box

var _marche_box_ref : Control

func _update_marche_panel() -> void:
	var data : Dictionary = HouseCatalog.HOUSES.get(_selected_house, {})
	var marche : Dictionary = data.get("marche", {})
	var max_val := -1
	for sigla in MARCHE_ORDER:
		max_val = max(max_val, int(marche.get(sigla, 0)))
	for sigla in MARCHE_ORDER:
		var value : int = marche.get(sigla, 0)
		var lbl : Label = _marche_value_labels[sigla]
		lbl.text = str(value)
		if value == max_val:
			lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
		else:
			lbl.remove_theme_color_override("font_color")

## ─── Pannello genere ────────────────────────────────────────────────────────
func _build_gender_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Gender"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.6, 0.58, 0.68))
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var male_btn := Button.new()
	male_btn.text = "Male"
	male_btn.toggle_mode = true
	male_btn.button_pressed = true
	male_btn.disabled = true   # fisso per ora, unico genere disponibile
	row.add_child(male_btn)

	var female_box := HBoxContainer.new()
	female_box.add_theme_constant_override("separation", 4)
	row.add_child(female_box)

	var female_btn := Button.new()
	female_btn.text = "Female"
	female_btn.toggle_mode = true
	female_btn.disabled = true
	female_box.add_child(female_btn)

	var female_note := Label.new()
	female_note.text = "Coming soon"
	female_note.add_theme_font_size_override("font_size", 11)
	female_note.add_theme_color_override("font_color", Color(0.5, 0.48, 0.55))
	female_box.add_child(female_note)

	return box

## ─── Footer ─────────────────────────────────────────────────────────────────
func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func(): cancelled.emit())
	row.add_child(back_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Begin"
	_confirm_btn.disabled = false
	_confirm_btn.pressed.connect(func():
		confirmed.emit(_selected_house, "male")
	)
	row.add_child(_confirm_btn)

	return row
