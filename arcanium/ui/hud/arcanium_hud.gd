extends Control
class_name ArcaniumHUD

## HUD di gioco (design-ui-nuova, 2026-10-21), con le zone pensate per il touch:
##  - in alto a sinistra: il medaglione col volto del campione
##    (medaglione_campione.gd) e le tre barre vive (barra_viva.gd): vita,
##    Arcanium Vivo, vigore;
##  - in alto a destra: l'Arcanium Cristallizzato (la valuta della run);
##  - in basso al centro: la barra azioni e, sopra, gli status alterati alla
##    Elden Ring (status_centrali.gd);
##  - in alto al centro resta l'obiettivo dello scontro (lo mette il livello).
## I due angoli in basso restano liberi: su telefono ci vanno levetta e tasti.
##
## Sorgenti (tutte opzionali, assegnabili in editor):
##  - health_system : ArcaniumHealthSystem  → HP
##  - vitals        : PlayerVitals          → stamina, arcanium vivo, cristalli
##  - status_host   : StatusHost            → righe status
##
const BarraViva := preload("res://arcanium/ui/hud/barra_viva.gd")
const MedaglioneCampione := preload("res://arcanium/ui/hud/medaglione_campione.gd")
const StatusCentrali := preload("res://arcanium/ui/hud/status_centrali.gd")
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")
## Il viola dell'Arcanium Cristallizzato, lo stesso della fine scontro.
const COL_CRISTALLI := Color("#8b6cff")
## Quanto sopra il fondo partono gli status: sopra la barra azioni.
const STATUS_DAL_FONDO := 132.0

@export var health_system : ArcaniumHealthSystem
@export var vitals : PlayerVitals
@export var status_host : StatusHost

## Nodo opzionale del sistema di selezione incantesimi (altro stream). Se
## assegnato in editor (o via codice prima di _ready) e ha il signal
## selection_changed(kind, resource), la SpellBar si aggiorna da solo.
@export var spell_selection : Node

var _hp_bar : Control
var _arc_bar : Control
var _sta_bar : Control
var _medaglione : Control
var _status : VBoxContainer
var _cristalli : Label
var _spell_bar : SpellBar

func _ready() -> void:
	add_to_group("arcanium_hud")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_vitals_panel()
	_build_cristalli()
	_build_spell_bar()
	_build_status()
	_connect_sources()

## Accessor pubblico per l'altro stream / debug: la SpellBar vera e propria.
func get_spell_bar() -> SpellBar:
	return _spell_bar

func _build_spell_bar() -> void:
	_spell_bar = SpellBar.new()
	add_child(_spell_bar)
	if spell_selection:
		_spell_bar.bind_selection(spell_selection)

## ─── Costruzione UI ──────────────────────────────────────────────────────────
func _build_vitals_panel() -> void:
	var riga := HBoxContainer.new()
	riga.name = "Vitali"
	riga.add_theme_constant_override("separation", 8)
	riga.set_anchors_preset(Control.PRESET_TOP_LEFT)
	riga.offset_left = 18
	riga.offset_top = 14
	riga.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(riga)
	_medaglione = MedaglioneCampione.new()
	riga.add_child(_medaglione)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	riga.add_child(col)
	_hp_bar = _make_bar(BarraViva.Tipo.SANGUE)
	_arc_bar = _make_bar(BarraViva.Tipo.ARCANIUM)
	_sta_bar = _make_bar(BarraViva.Tipo.VIGORE)
	col.add_child(_hp_bar)
	col.add_child(_arc_bar)
	col.add_child(_sta_bar)

func _make_bar(tipo : int) -> Control:
	var bar : Control = BarraViva.new()
	bar.tipo = tipo
	return bar

## L'Arcanium Cristallizzato in alto a destra: la valuta della run, che si
## perde alla sconfitta (torneo.gd). Prima stava in coda alla barra azioni.
func _build_cristalli() -> void:
	var box := VBoxContainer.new()
	box.name = "Cristalli"
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -22
	box.offset_top = 16
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var titolo := Label.new()
	titolo.text = "Arcanium"
	titolo.uppercase = true
	titolo.add_theme_font_override("font", FONT_TITOLO)
	titolo.add_theme_font_size_override("font_size", 11)
	titolo.add_theme_color_override("font_color", COL_CRISTALLI.lightened(0.25))
	titolo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(titolo)
	_cristalli = Label.new()
	_cristalli.text = "◆ 0"
	_cristalli.add_theme_font_override("font", FONT_TITOLO)
	_cristalli.add_theme_font_size_override("font_size", 24)
	_cristalli.add_theme_color_override("font_color", Color(0.93, 0.89, 0.80))
	_cristalli.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_cristalli.add_theme_constant_override("outline_size", 6)
	_cristalli.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_cristalli)
	var banca := get_node_or_null("/root/CrystalBank")
	if banca != null:
		banca.changed.connect(_su_cristalli)
		_su_cristalli(int(banca.crystals))

func _su_cristalli(quanti : int) -> void:
	_cristalli.text = "◆ %d" % quanti

func _build_status() -> void:
	_status = StatusCentrali.new()
	_status.name = "Status"
	_status.status_host = status_host
	_status.tela = self
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.offset_bottom = -STATUS_DAL_FONDO
	add_child(_status)

## ─── Wiring sorgenti ─────────────────────────────────────────────────────────
func _connect_sources() -> void:
	if health_system:
		health_system.health_updated.connect(_on_health_updated)
		_on_health_updated(health_system.current_health)

	if vitals:
		vitals.stamina_changed.connect(_on_stamina_changed)
		vitals.arcanium_changed.connect(_on_arcanium_changed)

func _on_health_updated(current : int) -> void:
	var total : float = float(health_system.total_health) if health_system else 1.0
	var ratio : float = float(current) / total if total > 0.0 else 0.0
	_hp_bar.set_value(ratio, str(maxi(0, current)))

func _on_stamina_changed(current : float, maximum : float) -> void:
	_sta_bar.set_value(current / maximum if maximum > 0.0 else 0.0, str(int(ceil(current))))

func _on_arcanium_changed(current : float, maximum : float) -> void:
	_arc_bar.set_value(current / maximum if maximum > 0.0 else 0.0, str(int(ceil(current))))
