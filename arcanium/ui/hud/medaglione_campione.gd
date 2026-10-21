extends Control
class_name MedaglioneCampione

## Il MEDAGLIONE dell'HUD, accanto alle barre (design-ui-nuova, 2026-10-21):
## la cornice assets/ui/cornici/medaglione.png (Flux, seme 23) e dentro il
## volto del campione, ritagliato a cerchio (ritratto_tondo.gdshader).
##
## Il ritratto e' assets/ui/ritratti/<casata>.png: basta mettere il file e
## compare. Finche' non c'e', al suo posto il sigillo nel colore della casata.

const CORNICE := preload("res://assets/ui/cornici/medaglione.png")
const SHADER_TONDO := preload("res://arcanium/ui/hud/ritratto_tondo.gdshader")
const HouseCatalog := preload("res://arcanium/systems/house_catalog.gd")
const CARTELLA_RITRATTI := "res://assets/ui/ritratti/"

@export var lato : float = 84.0
## Vuota: la casata del salvataggio (SaveManager), o quella di partenza.
@export var casata : String = ""

var ritratto : TextureRect
var sigillo : Label


func _ready() -> void:
	custom_minimum_size = Vector2(lato, lato)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var id := _casata()
	var dati : Dictionary = HouseCatalog.HOUSES.get(id, {})
	## Il centro della cornice e' vuoto: un disco scuro dentro l'anello d'oro.
	var disco := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.03, 0.04, 0.95)
	sb.set_corner_radius_all(int(lato))
	disco.add_theme_stylebox_override("panel", sb)
	_dentro(disco, 0.16)
	add_child(disco)

	var percorso := CARTELLA_RITRATTI + id + ".png"
	if ResourceLoader.exists(percorso):
		ritratto = TextureRect.new()
		ritratto.texture = load(percorso)
		ritratto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ritratto.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var mat := ShaderMaterial.new()
		mat.shader = SHADER_TONDO
		ritratto.material = mat
		_dentro(ritratto, 0.15)
		add_child(ritratto)
	else:
		sigillo = Label.new()
		sigillo.text = "◈"
		sigillo.add_theme_font_size_override("font_size", int(lato * 0.38))
		sigillo.add_theme_color_override("font_color", Color(String(dati.get("color", "#8fbfe0"))))
		sigillo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sigillo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_dentro(sigillo, 0.0)
		add_child(sigillo)

	var cornice := TextureRect.new()
	cornice.texture = CORNICE
	cornice.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cornice.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dentro(cornice, 0.0)
	add_child(cornice)


func _casata() -> String:
	if casata != "":
		return casata
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("get_house"):
		var h := String(sm.call("get_house"))
		if HouseCatalog.HOUSES.has(h):
			return h
	return HouseCatalog.DEFAULT_HOUSE


## Riempie il medaglione lasciando un margine (frazione del lato).
func _dentro(c : Control, margine : float) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := lato * margine
	c.offset_left = m
	c.offset_top = m
	c.offset_right = -m
	c.offset_bottom = -m
