extends Control
class_name BarraViva

## Barra vitale della HUD nuova (design-ui-nuova, 2026-10-21): etichetta in
## Cinzel a sinistra, il liquido di `barra_viva.gdshader` al centro, il valore
## a destra. La scia del danno viene da BarChip, come nella StatBar di prima.
##
## La CORNICE qui e' provvisoria, disegnata a codice (un filo di bronzo): quella
## vera e' una texture 9-slice, da generare dopo l'approvazione dei prompt.
##
## Uso: var b := BarraViva.new(); b.tipo = BarraViva.Tipo.SANGUE; poi
## b.set_value(ratio, "82").

enum Tipo { SANGUE, ARCANIUM, VIGORE }

const SHADER := preload("res://arcanium/ui/hud/barra_viva.gdshader")
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")

## [fondo, vivo, luce] per tipo.
const COLORI := {
	Tipo.SANGUE: [Color(0.26, 0.015, 0.03), Color(0.80, 0.10, 0.09), Color(1.0, 0.50, 0.38)],
	Tipo.ARCANIUM: [Color(0.10, 0.04, 0.32), Color(0.52, 0.30, 1.0), Color(0.80, 0.70, 1.0)],
	Tipo.VIGORE: [Color(0.03, 0.18, 0.08), Color(0.30, 0.78, 0.38), Color(0.75, 1.0, 0.70)],
}
const ETICHETTE := {Tipo.SANGUE: "Health", Tipo.ARCANIUM: "Arcanium", Tipo.VIGORE: "Stamina"}
const BRONZO := Color(0.42, 0.31, 0.18)
const BRONZO_LUCE := Color(0.78, 0.62, 0.38)

@export var tipo : Tipo = Tipo.SANGUE
@export var larghezza_tubo : float = 230.0
@export var altezza_tubo : float = 16.0
@export var larghezza_etichetta : float = 86.0
@export var larghezza_valore : float = 44.0
@export var corpo : int = 13

var _ratio := 1.0
var _testo := ""
var _chip : BarChip
var _tubo : ColorRect
var _mat : ShaderMaterial


func _ready() -> void:
	custom_minimum_size = Vector2(larghezza_etichetta + larghezza_tubo + larghezza_valore + 12.0, altezza_tubo + 10.0)
	_chip = BarChip.new(_ratio)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var c : Array = COLORI[tipo]
	_mat.set_shader_parameter("tipo", int(tipo))
	_mat.set_shader_parameter("colore_fondo", c[0])
	_mat.set_shader_parameter("colore_vivo", c[1])
	_mat.set_shader_parameter("colore_luce", c[2])
	_mat.set_shader_parameter("larghezza_px", larghezza_tubo)
	_mat.set_shader_parameter("altezza_px", altezza_tubo)
	_tubo = ColorRect.new()
	_tubo.material = _mat
	_tubo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tubo.position = Vector2(larghezza_etichetta, (custom_minimum_size.y - altezza_tubo) * 0.5)
	_tubo.size = Vector2(larghezza_tubo, altezza_tubo)
	add_child(_tubo)
	_aggiorna()


func set_value(ratio : float, testo : String) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_testo = testo
	_aggiorna()
	queue_redraw()


func _process(delta : float) -> void:
	if _chip == null:
		return
	_chip.update(_ratio, delta)
	_aggiorna()


func _aggiorna() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("valore", _ratio)
	_mat.set_shader_parameter("scia", maxf(_chip.chip, _ratio))


func _draw() -> void:
	var mid := custom_minimum_size.y * 0.5
	var base := mid + corpo * 0.36
	var c : Array = COLORI[tipo]
	draw_string(FONT_TITOLO, Vector2(0, base), tr(ETICHETTE[tipo]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			larghezza_etichetta - 6.0, corpo, (c[2] as Color).lerp(Color(0.9, 0.86, 0.78), 0.55))
	## La cornice provvisoria: un filo di bronzo con la luce sopra.
	var r := Rect2(_tubo.position - Vector2(2, 2), _tubo.size + Vector2(4, 4))
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	sb.set_border_width_all(2)
	sb.border_color = BRONZO
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 3
	draw_style_box(sb, r)
	var luce := StyleBoxFlat.new()
	luce.draw_center = false
	luce.set_corner_radius_all(int(r.size.y * 0.5))
	luce.border_width_top = 1
	luce.border_color = BRONZO_LUCE
	draw_style_box(luce, r)
	draw_string(FONT_TITOLO, Vector2(larghezza_etichetta + larghezza_tubo + 10.0, base), _testo,
			HORIZONTAL_ALIGNMENT_LEFT, larghezza_valore, corpo + 1, Color(0.93, 0.89, 0.80))
