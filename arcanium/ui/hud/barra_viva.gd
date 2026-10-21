extends Control
class_name BarraViva

## Barra vitale della HUD nuova (design-ui-nuova, 2026-10-21): etichetta in
## Cinzel a sinistra, il liquido di `barra_viva.gdshader` al centro, il valore
## a destra. La scia del danno viene da BarChip, come nella StatBar di prima.
##
## La CORNICE e' assets/ui/cornici/barra.png (Flux, seme 37, approvata il
## 2026-10-21) in un NinePatchRect: terminali ornati fissi, bordi lunghi che si
## stirano. Il tubo cade nel vano scuro della cornice (misure sotto).
##
## Uso: var b := BarraViva.new(); b.tipo = BarraViva.Tipo.SANGUE; poi
## b.set_value(ratio, "82").

## STATUS: le barre degli status alterati (status_centrali.gd), col colore
## dello status e l'etichetta data da fuori; il liquido e' quello del vigore.
enum Tipo { SANGUE, ARCANIUM, VIGORE, STATUS }

const SHADER := preload("res://arcanium/ui/hud/barra_viva.gdshader")
const CORNICE := preload("res://assets/ui/cornici/barra.png")
## Misure della cornice in pixel di texture (640x73): il vano scuro va dalla
## riga 16 alla 55, i terminali ornati finiscono a 54 px dai lati.
const VANO_ALTO := 16.0
const VANO_BASSO := 55.0
const TERMINALE := 54.0
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")

## [fondo, vivo, luce] per tipo.
const COLORI := {
	Tipo.SANGUE: [Color(0.26, 0.015, 0.03), Color(0.80, 0.10, 0.09), Color(1.0, 0.50, 0.38)],
	Tipo.ARCANIUM: [Color(0.10, 0.04, 0.32), Color(0.52, 0.30, 1.0), Color(0.80, 0.70, 1.0)],
	Tipo.VIGORE: [Color(0.03, 0.18, 0.08), Color(0.30, 0.78, 0.38), Color(0.75, 1.0, 0.70)],
}
const ETICHETTE := {Tipo.SANGUE: "Health", Tipo.ARCANIUM: "Arcanium", Tipo.VIGORE: "Stamina"}
const LIQUIDO := {Tipo.SANGUE: 0, Tipo.ARCANIUM: 1, Tipo.VIGORE: 2, Tipo.STATUS: 2}

@export var tipo : Tipo = Tipo.SANGUE
@export var larghezza_tubo : float = 230.0
@export var altezza_tubo : float = 16.0
@export var larghezza_etichetta : float = 86.0
@export var larghezza_valore : float = 44.0
@export var corpo : int = 13
## Etichetta data da fuori (gli status); vuota: quella del tipo.
@export var etichetta : String = ""
## [fondo, vivo, luce] dati da fuori (gli status); vuoto: quelli del tipo.
var colori : Array = []

var _ratio := 1.0
var _testo := ""
var _chip : BarChip
var _tubo : ColorRect
var _mat : ShaderMaterial
var _cornice : NinePatchRect
## Scala della cornice: il vano alto quanto il tubo.
var _s := 1.0


func _ready() -> void:
	_s = altezza_tubo / (VANO_BASSO - VANO_ALTO)
	var alta := CORNICE.get_height() * _s
	var larga := larghezza_tubo + 2.0 * TERMINALE * _s
	custom_minimum_size = Vector2(larghezza_etichetta + larga + larghezza_valore + 8.0, alta)
	_chip = BarChip.new(_ratio)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("tipo", LIQUIDO[tipo])
	colora(_colori())
	_mat.set_shader_parameter("larghezza_px", larghezza_tubo)
	_mat.set_shader_parameter("altezza_px", altezza_tubo)
	_cornice = NinePatchRect.new()
	_cornice.texture = CORNICE
	_cornice.patch_margin_left = int(TERMINALE + 8.0)
	_cornice.patch_margin_right = int(TERMINALE + 8.0)
	_cornice.patch_margin_top = int(VANO_ALTO)
	_cornice.patch_margin_bottom = CORNICE.get_height() - int(VANO_BASSO)
	_cornice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cornice.position = Vector2(larghezza_etichetta, 0)
	_cornice.size = Vector2(larga / _s, CORNICE.get_height())
	_cornice.scale = Vector2(_s, _s)
	add_child(_cornice)
	_tubo = ColorRect.new()
	_tubo.material = _mat
	_tubo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tubo.position = Vector2(larghezza_etichetta + TERMINALE * _s, VANO_ALTO * _s)
	_tubo.size = Vector2(larghezza_tubo, altezza_tubo)
	add_child(_tubo)
	_aggiorna()


## Cambia i colori del liquido (uno status che passa dall'accumulo alla durata).
func colora(c : Array) -> void:
	colori = c
	if _mat == null:
		return
	_mat.set_shader_parameter("colore_fondo", c[0])
	_mat.set_shader_parameter("colore_vivo", c[1])
	_mat.set_shader_parameter("colore_luce", c[2])
	queue_redraw()


func _colori() -> Array:
	return colori if colori.size() == 3 else COLORI.get(tipo, COLORI[Tipo.VIGORE])


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
	var c : Array = _colori()
	var nome : String = etichetta if etichetta != "" else tr(ETICHETTE.get(tipo, ""))
	draw_string(FONT_TITOLO, Vector2(0, base), nome.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			larghezza_etichetta - 6.0, corpo, (c[2] as Color).lerp(Color(0.9, 0.86, 0.78), 0.55))
	if _testo == "":
		return
	draw_string(FONT_TITOLO, Vector2(_cornice.position.x + _cornice.size.x * _s + 6.0, base), _testo,
			HORIZONTAL_ALIGNMENT_LEFT, larghezza_valore, corpo + 1, Color(0.93, 0.89, 0.80))
