extends Control
class_name CrystalIcon

## Simboletto dell'Arcanium Cristallizzato (◈) disegnato come cristallo sfaccettato,
## per la HUD in basso a destra. Vettoriale così resta nitido a ogni risoluzione.

@export var crystal_color : Color = Color("#8b6cff")
@export var size_px : float = 22.0

func _ready() -> void:
	custom_minimum_size = Vector2(size_px, size_px)

func _draw() -> void:
	var c := size * 0.5
	var w := size_px * 0.34   # semi-larghezza
	var h := size_px * 0.46   # semi-altezza
	var top := c + Vector2(0, -h)
	var bottom := c + Vector2(0, h)
	var left := c + Vector2(-w, -h * 0.15)
	var right := c + Vector2(w, -h * 0.15)

	var base := crystal_color
	var light := base.lightened(0.35)
	var dark := base.darkened(0.30)

	# Faccette: due triangoli superiori (chiaro/base) + due inferiori (scuro).
	draw_colored_polygon(PackedVector2Array([top, left, c]), light)
	draw_colored_polygon(PackedVector2Array([top, right, c]), base)
	draw_colored_polygon(PackedVector2Array([left, bottom, c]), dark)
	draw_colored_polygon(PackedVector2Array([right, bottom, c]), dark.darkened(0.12))

	# Contorno + bagliore centrale.
	var outline := PackedVector2Array([top, right, bottom, left])
	draw_polyline(outline + PackedVector2Array([top]), Color(1, 1, 1, 0.5), 1.0, true)
	draw_line(top, c, Color(1, 1, 1, 0.35), 1.0, true)
