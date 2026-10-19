extends Control
class_name StatBar

## Barra vitale della HUD (HP / Arcanium Vivo / Stamina). Disegnata a mano con
## _draw per pieno controllo: track scuro arrotondato, "scia" di danno (BarChip)
## e fill con highlight superiore. Look pulito/moderno, non stile Lite.
##
## Uso: bar.configure("HP", Color.RED); poi bar.set_value(ratio, "80").

@export var label_text : String = "HP"
@export var label_color : Color = Color.WHITE
@export var fill_color : Color = Color("#e0524d")
@export var track_color : Color = Color("#1a1416")
@export var font_size : int = 13

@export var label_width : float = 42.0
@export var value_width : float = 46.0
@export var track_height : float = 14.0
@export var corner : float = 7.0

var _ratio : float = 1.0
var _value_text : String = ""
var _chip : BarChip
var _chip_ratio : float = 1.0

var _sb_track : StyleBoxFlat
var _sb_chip : StyleBoxFlat
var _sb_fill : StyleBoxFlat

func _ready() -> void:
	custom_minimum_size = Vector2(230, track_height + 8)
	_chip = BarChip.new(_ratio)
	_build_styleboxes()

func configure(text : String, color : Color) -> void:
	label_text = text
	fill_color = color
	if _sb_fill:
		_sb_fill.bg_color = fill_color
		_sb_chip.bg_color = fill_color.lightened(0.35)
	queue_redraw()

func set_value(ratio : float, value_text : String) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_value_text = value_text
	queue_redraw()

func _process(delta : float) -> void:
	if _chip == null:
		return
	var new_chip := _chip.update(_ratio, delta)
	if absf(new_chip - _chip_ratio) > 1e-4:
		_chip_ratio = new_chip
		queue_redraw()

func _build_styleboxes() -> void:
	_sb_track = _flat(track_color)
	_sb_track.border_color = Color(0, 0, 0, 0.55)
	_sb_track.set_border_width_all(1)
	_sb_chip = _flat(fill_color.lightened(0.35))
	_sb_fill = _flat(fill_color)

func _flat(c : Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(corner))
	return sb

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var mid_y := size.y * 0.5
	var baseline := mid_y + font_size * 0.36

	# Etichetta a sinistra.
	draw_string(font, Vector2(0, baseline), label_text, HORIZONTAL_ALIGNMENT_LEFT,
		label_width, font_size, label_color)

	# Track al centro.
	var track_x := label_width
	var track_w := size.x - label_width - value_width
	var track_rect := Rect2(track_x, mid_y - track_height * 0.5, track_w, track_height)
	draw_style_box(_sb_track, track_rect)

	# Scia (chip): resta indietro quando il valore cala di colpo.
	if _chip_ratio > _ratio:
		var chip_rect := Rect2(track_rect.position, Vector2(track_w * _chip_ratio, track_height))
		draw_style_box(_sb_chip, chip_rect)

	# Fill principale + highlight superiore per dare profondità.
	if _ratio > 0.0:
		var fill_rect := Rect2(track_rect.position, Vector2(track_w * _ratio, track_height))
		draw_style_box(_sb_fill, fill_rect)
		var hl := fill_rect
		hl.size.y *= 0.45
		hl.position.x += 1
		hl.size.x = maxf(0.0, hl.size.x - 2)
		draw_rect(hl, Color(1, 1, 1, 0.14), true)

	# Valore a destra.
	draw_string(font, Vector2(size.x - value_width, baseline), _value_text,
		HORIZONTAL_ALIGNMENT_RIGHT, value_width, font_size, Color(1, 1, 1, 0.9))
