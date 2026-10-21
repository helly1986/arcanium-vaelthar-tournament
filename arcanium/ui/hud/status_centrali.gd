extends VBoxContainer
class_name StatusCentrali

## Gli STATUS ALTERATI alla Elden Ring (decisione dell'autore del 2026-10-21):
## in basso al centro, sopra la barra azioni.
##   - l'ACCUMULO compare come barra che si carica, nel colore dello status
##     ma spento;
##   - quando si riempie lo status SCATTA: una grande scritta rossa col suo
##     nome sale e svanisce al centro dello schermo;
##   - finche' l'effetto dura la stessa riga resta, accesa, e si svuota.
## Legge lo StatusHost del giocatore ogni frame (accumuli / active_statuses):
## cosi' segue scatti, rinnovi e scadenze senza agganciarsi a ogni effetto.
##
## La zona e' quella che sul telefono resta libera fra la levetta (a sinistra)
## e i tasti (a destra): vedi design-ui-nuova.

const BarraViva := preload("res://arcanium/ui/hud/barra_viva.gd")
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")
## Il rosso della scritta di scatto, uguale per ogni status (come in Elden Ring).
const ROSSO_SCATTO := Color(0.82, 0.10, 0.08)

var status_host : StatusHost
## Dove mettere la scritta di scatto (il Control a schermo intero dell'HUD).
var tela : Control

## Emesso allo scatto, con il nome mostrato (per chi verifica e per i suoni).
signal scattato(id : String, nome : String)

var _righe := {}     ## id -> BarraViva
var _attivi := {}    ## id degli status attivi al frame prima


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 2)


func _process(_delta : float) -> void:
	if status_host == null:
		return
	var visti := {}
	var ora_attivi := {}
	for s in status_host.active_statuses():
		var id := String(s["id"])
		visti[id] = true
		ora_attivi[id] = true
		var r := _riga(id, s)
		r.colora(_tinte(s["color"], true))
		r.set_value(float(s["ratio"]), "")
		if not _attivi.has(id):
			_scatta(id, String(s.get("label", id)))
	for s in status_host.accumuli():
		var id := String(s["id"])
		if visti.has(id) or float(s["ratio"]) <= 0.001:
			continue
		visti[id] = true
		var r := _riga(id, s)
		r.colora(_tinte(s["color"], false))
		r.set_value(float(s["ratio"]), "")
	for id in _righe.keys():
		if not visti.has(id):
			_righe[id].queue_free()
			_righe.erase(id)
	_attivi = ora_attivi


func righe() -> Dictionary:
	return _righe


func _riga(id : String, s : Dictionary) -> Control:
	if _righe.has(id):
		return _righe[id]
	var r : Control = BarraViva.new()
	r.tipo = BarraViva.Tipo.STATUS
	r.larghezza_tubo = 190.0
	r.altezza_tubo = 10.0
	r.larghezza_etichetta = 150.0
	r.larghezza_valore = 0.0
	r.corpo = 12
	var effetto = status_host.get_effect(id)
	var nome : String = String(effetto.label) if effetto != null else id
	r.etichetta = "%s  %s" % [String(s.get("icon", "")), tr(nome)]
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(r)
	_righe[id] = r
	return r


## Le tinte del liquido dal colore dello status: spente durante l'accumulo,
## accese quando e' scattato.
func _tinte(c : Color, acceso : bool) -> Array:
	if acceso:
		return [c.darkened(0.7), c, c.lightened(0.5)]
	return [c.darkened(0.85), c.darkened(0.35), c.lightened(0.2)]


func _scatta(id : String, nome : String) -> void:
	var testo := tr(nome).to_upper()
	scattato.emit(id, testo)
	if tela == null:
		return
	var l := Label.new()
	l.name = "ScrittaScatto"
	l.text = testo
	l.add_theme_font_override("font", FONT_TITOLO)
	l.add_theme_font_size_override("font_size", 46)
	l.add_theme_color_override("font_color", ROSSO_SCATTO)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position.y += tela.size.y * 0.16
	l.modulate.a = 0.0
	tela.add_child(l)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(1.25, 1.25)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(l, "position:y", l.position.y - 24.0, 0.6)
	tw.tween_callback(l.queue_free)
