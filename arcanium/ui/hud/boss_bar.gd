extends Control
class_name BossBar

## Barra HP del boss, souls-style: nome + lunga barra rossa centrata in basso, con
## "chip" (scia che insegue il fill quando cala di colpo). Port della BossBar di
## Arcanium-Lite. Appare all'aggro (o al primo colpo), sparisce alla morte.
##
## Riferisce il NODO boss (ArcaniumBoss, assegnabile dall'arena); ne ricava
## l'HealthSystem interno e i segnali engaged/died.

@export var boss : Node
@export var boss_name : String = "The Nameless"

const COL_TRACK := Color("#160b0d")
const COL_FILL := Color("#b23a34")
const NAME_SIZE := 18
const TRACK_H := 12.0

var _chip : BarChip
var _ratio : float = 1.0
var _chip_ratio : float = 1.0
var _total : float = 1.0
var _shown : bool = false

var _sb_track : StyleBoxFlat
var _sb_chip : StyleBoxFlat
var _sb_fill : StyleBoxFlat

func _ready() -> void:
	_chip = BarChip.new(1.0)
	modulate.a = 0.0
	_build_styles()
	_wire_boss()

## Aggancia (o RI-aggancia) la barra a un boss a runtime. Necessario per nemici
## generati dal builder / ri-creati al respawn (es. Lupo Alpha): il NodePath fisso
## dello scene-author non li raggiunge. Riconnette HealthSystem+engaged, resetta
## la barra nascosta e aggiorna il nome.
func bind_boss(new_boss : Node, display_name : String = "") -> void:
	_disconnect_boss()
	boss = new_boss
	if display_name != "":
		boss_name = display_name
	_shown = false
	modulate.a = 0.0
	_ratio = 1.0
	_chip_ratio = 1.0
	_wire_boss()

func _wire_boss() -> void:
	if boss == null:
		return
	var hs = boss.health_system if "health_system" in boss else null
	if hs:
		_total = float(hs.total_health)
		if not hs.health_updated.is_connected(_on_health):
			hs.health_updated.connect(_on_health)
		if not hs.died.is_connected(_on_died):
			hs.died.connect(_on_died)
	if boss.has_signal("engaged") and not boss.engaged.is_connected(_show):
		boss.engaged.connect(_show)
	queue_redraw()

func _disconnect_boss() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var hs = boss.health_system if "health_system" in boss else null
	if hs and is_instance_valid(hs):
		if hs.health_updated.is_connected(_on_health):
			hs.health_updated.disconnect(_on_health)
		if hs.died.is_connected(_on_died):
			hs.died.disconnect(_on_died)
	if boss.has_signal("engaged") and boss.engaged.is_connected(_show):
		boss.engaged.disconnect(_show)

func _build_styles() -> void:
	_sb_track = _flat(COL_TRACK)
	_sb_track.border_color = Color(0, 0, 0, 0.6)
	_sb_track.set_border_width_all(1)
	_sb_chip = _flat(COL_FILL.lightened(0.4))
	_sb_fill = _flat(COL_FILL)

func _flat(c : Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(2)
	return sb

func _on_health(current : int) -> void:
	var prima := _ratio
	_ratio = clampf(float(current) / _total, 0.0, 1.0) if _total > 0.0 else 0.0
	# La barra compare quando il boss PERDE vita (anche se colpito senza aggro
	# esplicito). Su una CURA resta com'è: altrimenti rimettere l'Alpha a vita
	# piena dopo un respawn la farebbe ricomparire dall'altra parte del livello,
	# con il player appena rinato al Cono e il boss lontanissimo.
	if _ratio < prima:
		_show()
	queue_redraw()

func _on_died() -> void:
	_hide()

## Nasconde la barra e la riporta a vita piena. Da chiamare quando il
## combattimento si chiude senza che il boss sia caduto — tipicamente perché è
## morto il player: la barra non deve sopravvivere alla schermata di morte.
func reset_bar() -> void:
	_hide()
	_ratio = 1.0
	_chip_ratio = 1.0
	queue_redraw()

func _show() -> void:
	if _shown:
		return
	_shown = true
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)

func _hide() -> void:
	if not _shown:
		return
	_shown = false
	create_tween().tween_property(self, "modulate:a", 0.0, 0.6)

func _process(delta : float) -> void:
	if _chip == null:
		return
	var c := _chip.update(_ratio, delta, 0.45, 0.6)
	if absf(c - _chip_ratio) > 1e-4:
		_chip_ratio = c
		queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	# nome del boss, centrato sopra la barra
	draw_string(font, Vector2(0, NAME_SIZE), boss_name, HORIZONTAL_ALIGNMENT_CENTER,
		size.x, NAME_SIZE, Color(0.86, 0.82, 0.8))

	var track := Rect2(0, NAME_SIZE + 8.0, size.x, TRACK_H)
	draw_style_box(_sb_track, track)
	if _chip_ratio > _ratio:
		draw_style_box(_sb_chip, Rect2(track.position, Vector2(size.x * _chip_ratio, TRACK_H)))
	if _ratio > 0.0:
		draw_style_box(_sb_fill, Rect2(track.position, Vector2(size.x * _ratio, TRACK_H)))
		var hl := Rect2(track.position.x + 1, track.position.y + 1,
			maxf(0.0, size.x * _ratio - 2), TRACK_H * 0.4)
		draw_rect(hl, Color(1, 1, 1, 0.12), true)
