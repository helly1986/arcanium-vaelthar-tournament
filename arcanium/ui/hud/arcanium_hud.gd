extends Control
class_name ArcaniumHUD

## HUD di gioco di Arcanium. Ricostruisce la UI di Arcanium-Lite in Godot con
## grafica pulita/moderna:
##  - in alto a sinistra: barre HP, ARCANIUM VIVO, STAMINA (impilate) + gli status
##    effect attivi sotto (icona + barra durata);
##  - in basso a destra: contatore Arcanium CRISTALLIZZATO col simbolo ◈.
##
## Sorgenti (tutte opzionali, assegnabili in editor):
##  - health_system : ArcaniumHealthSystem  → HP
##  - vitals        : PlayerVitals          → stamina, arcanium vivo, cristalli
##  - status_host   : StatusHost            → righe status
##
## Colori (non stile Lite): rosso caldo / blu arcano / verde.
const COL_HP := Color("#e0524d")
const COL_ARC := Color("#4f8cff")
const COL_STA := Color("#46c07a")

@export var health_system : ArcaniumHealthSystem
@export var vitals : PlayerVitals
@export var status_host : StatusHost

## Nodo opzionale del sistema di selezione incantesimi (altro stream). Se
## assegnato in editor (o via codice prima di _ready) e ha il signal
## selection_changed(kind, resource), la SpellBar si aggiorna da solo.
@export var spell_selection : Node

var _hp_bar : StatBar
var _arc_bar : StatBar
var _sta_bar : StatBar
var _status_box : VBoxContainer
var _status_rows : Dictionary = {}   # id → StatBar
var _spell_bar : SpellBar

func _ready() -> void:
	add_to_group("arcanium_hud")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_vitals_panel()
	# Il contatore cristalli e gli oggetti NON sono più pannelli separati:
	# vivono dentro la barra azioni (SpellBar), un unico modulo in basso.
	_build_spell_bar()
	_connect_sources()

## Accessor pubblico per l'altro stream / debug: la SpellBar vera e propria.
func get_spell_bar() -> SpellBar:
	return _spell_bar

func _build_spell_bar() -> void:
	_spell_bar = SpellBar.new()
	add_child(_spell_bar)
	if spell_selection:
		_spell_bar.bind_selection(spell_selection)
	# Cristalli: la barra li legge dall'autoload CrystalBank da sola.
	_spell_bar.bind_crystals()

## ─── Costruzione UI ──────────────────────────────────────────────────────────
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.05, 0.55)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.set_border_width_all(1)
	return sb

func _build_vitals_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 24
	panel.offset_top = 24
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_hp_bar = _make_bar("HP", COL_HP)
	_arc_bar = _make_bar("ARC", COL_ARC)
	_sta_bar = _make_bar("STA", COL_STA)
	vbox.add_child(_hp_bar)
	vbox.add_child(_arc_bar)
	vbox.add_child(_sta_bar)

	_status_box = VBoxContainer.new()
	_status_box.add_theme_constant_override("separation", 3)
	vbox.add_child(_status_box)

func _make_bar(text : String, color : Color) -> StatBar:
	var bar := StatBar.new()
	bar.configure(text, color)
	return bar

## ─── Wiring sorgenti ─────────────────────────────────────────────────────────
func _connect_sources() -> void:
	if health_system:
		health_system.health_updated.connect(_on_health_updated)
		_on_health_updated(health_system.current_health)

	if vitals:
		vitals.stamina_changed.connect(_on_stamina_changed)
		vitals.arcanium_changed.connect(_on_arcanium_changed)

	# I cristalli ora li mostra la SpellBar (vedi bind_crystals), non più qui.

func _on_health_updated(current : int) -> void:
	var total : float = float(health_system.total_health) if health_system else 1.0
	var ratio : float = float(current) / total if total > 0.0 else 0.0
	_hp_bar.set_value(ratio, str(maxi(0, current)))

func _on_stamina_changed(current : float, maximum : float) -> void:
	_sta_bar.set_value(current / maximum if maximum > 0.0 else 0.0, str(int(ceil(current))))

func _on_arcanium_changed(current : float, maximum : float) -> void:
	_arc_bar.set_value(current / maximum if maximum > 0.0 else 0.0, str(int(ceil(current))))

## ─── Righe status (poll, così segue applied/expired senza gestione manuale) ──
func _process(_delta : float) -> void:
	if status_host == null:
		return
	var active := status_host.active_statuses()
	var seen := {}
	for s in active:
		seen[s.id] = true
		var row : StatBar = _status_rows.get(s.id, null)
		if row == null:
			row = StatBar.new()
			row.track_height = 8.0
			row.corner = 4.0
			row.font_size = 12
			row.label_width = 24.0
			row.value_width = 0.0
			row.configure(s.icon, s.color)
			_status_box.add_child(row)
			_status_rows[s.id] = row
		row.set_value(s.ratio, "")
	# Le barre di ACCUMULO (Lacerazione): stessa riga, colore spento, e si
	# riempiono invece di svuotarsi. Allo scatto la stessa chiave passa alla
	# riga dello stato attivo.
	for s in status_host.accumuli():
		var chiave : String = "accumulo_" + str(s.id)
		seen[chiave] = true
		var row : StatBar = _status_rows.get(chiave, null)
		if row == null:
			row = StatBar.new()
			row.track_height = 6.0
			row.corner = 3.0
			row.font_size = 11
			row.label_width = 24.0
			row.value_width = 0.0
			row.configure(s.icon, (s.color as Color).darkened(0.35))
			_status_box.add_child(row)
			_status_rows[chiave] = row
		row.set_value(s.ratio, "")
	# rimuovi le righe non più attive
	for id in _status_rows.keys():
		if not seen.has(id):
			_status_rows[id].queue_free()
			_status_rows.erase(id)
