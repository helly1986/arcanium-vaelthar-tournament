extends Control

## La BASE delle schermate dei nodi della mappa che non si combattono (riposo,
## tesoro, mercante, imprevisto): un pannello ornato al centro sopra la mappa,
## con titolo, testo e una colonna di scelte. La schermata del tipo riempie
## `_costruisci()`; `chiudi()` completa il nodo (Torneo.completa) e la toglie.
## La mappa (mappa_schermo.gd) si ridisegna quando la schermata esce.

const Ornati := preload("res://arcanium/ui/theme/ornati.gd")
const MenuStyle := preload("res://arcanium/ui/game_menu/er_style.gd")

var torneo : Node
## Il nodo della mappa in corso (seme, regione, tipo).
var nodo : Dictionary = {}
## Il generatore del nodo: dal suo seme, cosi' lo stesso nodo da' le stesse
## offerte e lo stesso evento.
var rng := RandomNumberGenerator.new()

var _colonna : VBoxContainer
var _testo : Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	torneo = get_node_or_null("/root/Torneo")
	nodo = torneo.nodo_in_corso() if torneo != null else {}
	rng.seed = int(nodo.get("seme", 0)) * 7 + 13
	var velo := ColorRect.new()
	velo.color = Color(0, 0, 0, 0.55)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(velo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centro)
	var box := Ornati.pannello(Vector2(720, 0))
	centro.add_child(box)
	_colonna = VBoxContainer.new()
	_colonna.add_theme_constant_override("separation", 8)
	Ornati.contenuto(box).add_child(_colonna)
	_costruisci()


## Da riempire: titolo, testo, scelte.
func _costruisci() -> void:
	pass


func titolo(testo : String) -> void:
	_colonna.add_child(Ornati.titolo(MenuStyle.spaziato(tr(testo)), 24))


func testo(t : String) -> Label:
	_testo = Label.new()
	_testo.name = "Testo"
	_testo.text = t
	_testo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_testo.custom_minimum_size = Vector2(560, 0)
	_testo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_testo.add_theme_color_override("font_color", Color(0.9, 0.86, 0.78))
	_colonna.add_child(_testo)
	return _testo


## Una scelta: il pulsante, e sotto in piccolo cosa fa.
func scelta(nome : String, spiegazione : String, azione : Callable, attiva : bool = true) -> Button:
	var b := Ornati.bottone(nome, Vector2(420, 46))
	b.disabled = not attiva
	b.pressed.connect(azione)
	var riga := VBoxContainer.new()
	riga.add_theme_constant_override("separation", 0)
	riga.alignment = BoxContainer.ALIGNMENT_CENTER
	var centro := CenterContainer.new()
	centro.add_child(b)
	riga.add_child(centro)
	if spiegazione != "":
		var s := Label.new()
		s.text = spiegazione
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(560, 0)
		s.add_theme_font_size_override("font_size", 14)
		s.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6) if attiva else Color(0.5, 0.48, 0.44))
		riga.add_child(s)
	_colonna.add_child(riga)
	return b


## Svuota la colonna (per mostrare l'esito di una scelta).
func svuota() -> void:
	for c in _colonna.get_children():
		_colonna.remove_child(c)
		c.queue_free()


## Mostra l'esito e un solo pulsante per tornare alla mappa.
func esito(nome : String, t : String) -> void:
	svuota()
	titolo(nome)
	testo(t)
	var b := scelta(tr("Back to the map"), "", chiudi)
	b.grab_focus()


func chiudi() -> void:
	if torneo != null and torneo.nodo_corrente != "":
		torneo.completa()
	queue_free()


## La tappa del nodo (1-4): le ricompense e i prezzi crescono con lei.
func tappa() -> int:
	return int(nodo.get("regione", 0)) + 1
