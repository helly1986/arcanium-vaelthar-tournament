extends RefCounted

## I PEZZI ORNATI della UI nuova (design-ui-nuova: dark fantasy ornato, cornici
## Flux in assets/ui/cornici): il pulsante coi terminali e il pannello con gli
## angoli lavorati. Li usano la selezione del campione e la mappa della run.

const PANNELLO := preload("res://assets/ui/cornici/pannello.png")
const PULSANTE := preload("res://assets/ui/cornici/pulsante.png")
const MEDAGLIONE := preload("res://assets/ui/cornici/medaglione.png")
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")


## Il pulsante coi terminali ornati: il testo sta fra i terminali, non sopra.
static func bottone(testo : String, minimo : Vector2) -> Button:
	var b := Button.new()
	b.text = testo
	b.custom_minimum_size = minimo
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 19)
	for stato in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxTexture.new()
		sb.texture = PULSANTE
		sb.texture_margin_left = 70
		sb.texture_margin_right = 70
		sb.texture_margin_top = 30
		sb.texture_margin_bottom = 30
		sb.content_margin_left = 62
		sb.content_margin_right = 52
		match stato:
			"hover", "focus":
				sb.modulate_color = Color(1.35, 1.25, 1.05)
			"pressed":
				sb.modulate_color = Color(0.8, 0.75, 0.7)
			"disabled":
				sb.modulate_color = Color(0.55, 0.55, 0.55)
		b.add_theme_stylebox_override(stato, sb)
	return b


## Un riquadro col pannello ornato e un fondo scuro dentro: i figli vanno nel
## Control ritornato da `contenuto(box)`, gia' dentro gli angoli.
static func pannello(minimo : Vector2 = Vector2.ZERO) -> Control:
	var box := Control.new()
	box.custom_minimum_size = minimo
	var cornice := NinePatchRect.new()
	cornice.name = "Cornice"
	cornice.texture = PANNELLO
	for lato in ["left", "right", "top", "bottom"]:
		cornice.set("patch_margin_" + lato, 96)
	cornice.set_anchors_preset(Control.PRESET_FULL_RECT)
	cornice.modulate = Color(1, 1, 1, 0.92)
	cornice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cornice)
	var fondo := ColorRect.new()
	fondo.color = Color(0.03, 0.025, 0.03, 0.8)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.offset_left = 22
	fondo.offset_top = 22
	fondo.offset_right = -22
	fondo.offset_bottom = -22
	fondo.show_behind_parent = true
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fondo)
	var dentro := MarginContainer.new()
	dentro.name = "Contenuto"
	dentro.set_anchors_preset(Control.PRESET_FULL_RECT)
	## Dentro gli ornamenti degli angoli della cornice.
	dentro.add_theme_constant_override("margin_left", 64)
	dentro.add_theme_constant_override("margin_top", 62)
	dentro.add_theme_constant_override("margin_right", 52)
	dentro.add_theme_constant_override("margin_bottom", 62)
	box.add_child(dentro)
	return box


static func contenuto(box : Control) -> Control:
	return box.get_node("Contenuto")


## Un titolo in Cinzel, oro, spaziato.
static func titolo(testo : String, dimensione : int = 26) -> Label:
	var l := Label.new()
	l.text = testo
	l.add_theme_font_override("font", FONT_TITOLO)
	l.add_theme_font_size_override("font_size", dimensione)
	l.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
