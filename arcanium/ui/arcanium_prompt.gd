extends RefCounted
class_name ArcaniumPrompt

## Stile unico dei testi di gioco a schermo: prompt d'interazione, toast
## tutorial, avvisi.
##
## Convenzione SOTTOTITOLO (YouTube/Netflix): testo chiaro e grande su fascia
## nera semi-opaca. Il fondo scuro non è decorazione — è ciò che rende la
## scritta leggibile su qualunque sfondo. Senza, la sabbia chiara della Traccia
## Perduta e la pietra scura del Crocevia si mangiavano entrambe il testo, per
## motivi opposti, e l'ombra portata da sola non bastava.
##
## Tutto passa da qui: cambiare corpo o colore in un punto solo li cambia in
## tutto il gioco.

const CORPO := 30
const CORPO_PICCOLO := 24
const COL_TESTO := Color(0.97, 0.95, 0.90)
const COL_FONDO := Color(0, 0, 0, 0.72)
const MARGINE_X := 26
const MARGINE_Y := 12


static func sfondo(opacita : float = -1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_FONDO if opacita < 0.0 else Color(0, 0, 0, opacita)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = MARGINE_X
	sb.content_margin_right = MARGINE_X
	sb.content_margin_top = MARGINE_Y
	sb.content_margin_bottom = MARGINE_Y
	return sb


## `larghezza` > 0 accende l'andata a capo su quella misura; a 0 il testo resta
## su UNA riga.
##
## ⚠️ L'autowrap acceso senza una larghezza dichiarata è quello che manda a capo
## OGNI CARATTERE: dentro un contenitore che si dimensiona sul contenuto, la
## larghezza minima del Label è zero, e "Premi T per parlare" diventa una colonna
## di lettere. Un prompt d'interazione è corto e va su una riga sola; solo i testi
## lunghi (i toast tutorial) dichiarano la loro larghezza e vanno a capo.
static func etichetta(testo : String, corpo : int = CORPO,
		larghezza : float = 0.0) -> Label:
	var l := Label.new()
	l.text = testo
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if larghezza > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(larghezza, 0.0)
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
	applica(l, corpo)
	return l


## Applica lo stile a un Label già esistente (per convertire le UI vecchie senza
## ricostruirle).
static func applica(l : Label, corpo : int = CORPO,
		colore : Color = COL_TESTO) -> void:
	l.add_theme_font_size_override("font_size", corpo)
	l.add_theme_color_override("font_color", colore)
	# L'ombra resta SOTTO il fondo nero: aiuta sui bordi delle lettere quando il
	# pannello è semi-trasparente.
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
