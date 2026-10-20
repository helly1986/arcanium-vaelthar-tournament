extends CanvasLayer

## La schermata di FINE SCONTRO del mini-dungeon: vittoria (uscita trovata,
## dungeon ripulito) o sconfitta (caduto nel baratro, morto in battaglia).
##
## Un velo che scurisce, il titolo grande, il perche', tre numeri (tempo,
## nemici abbattuti, forzieri aperti) e due scelte. Il mondo sotto va in pausa;
## questa schermata no (PROCESS_MODE_ALWAYS). Mouse, tastiera e pad: il primo
## pulsante ha il fuoco, la croce e le frecce lo spostano, A/Invio conferma.
##
## Non decide cosa succede dopo: emette `scelto(azione)` con "riprova" (stesso
## dungeon), "nuovo" (un altro seme) o "prossimo" (dopo una vittoria), e chi la
## mostra fa il resto (costruttore_dungeon.gd).

signal scelto(azione : String)

const ORO := Color(0.86, 0.72, 0.42)
const SANGUE := Color(0.72, 0.16, 0.12)
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")

var vittoria := false
var _pulsanti : Array[Button] = []
var _scelto := false


## `dati`: {"titolo_motivo": String, "tempo": float, "abbattuti": int,
## "nemici": int, "forzieri": int, "forzieri_tot": int}
func mostra(vinto : bool, dati : Dictionary) -> void:
	vittoria = vinto
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var radice := Control.new()
	radice.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(radice)
	var velo := ColorRect.new()
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.color = Color(0.02, 0.0, 0.0, 0.0) if not vinto else Color(0.0, 0.0, 0.02, 0.0)
	radice.add_child(velo)

	var colonna := VBoxContainer.new()
	colonna.set_anchors_preset(Control.PRESET_CENTER)
	colonna.grow_horizontal = Control.GROW_DIRECTION_BOTH
	colonna.grow_vertical = Control.GROW_DIRECTION_BOTH
	colonna.alignment = BoxContainer.ALIGNMENT_CENTER
	colonna.add_theme_constant_override("separation", 18)
	colonna.modulate.a = 0.0
	radice.add_child(colonna)

	var titolo := Label.new()
	titolo.text = _spaziato("VITTORIA" if vinto else "SCONFITTA")
	titolo.add_theme_font_override("font", FONT_TITOLO)
	titolo.add_theme_font_size_override("font_size", 72)
	titolo.add_theme_color_override("font_color", ORO if vinto else SANGUE)
	titolo.add_theme_color_override("font_outline_color", Color.BLACK)
	titolo.add_theme_constant_override("outline_size", 10)
	titolo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	colonna.add_child(titolo)

	var motivo := Label.new()
	motivo.text = String(dati.get("titolo_motivo", ""))
	motivo.add_theme_font_size_override("font_size", 26)
	motivo.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76))
	motivo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	colonna.add_child(motivo)

	var riga := HBoxContainer.new()
	riga.alignment = BoxContainer.ALIGNMENT_CENTER
	riga.add_theme_constant_override("separation", 48)
	colonna.add_child(riga)
	var t : float = dati.get("tempo", 0.0)
	riga.add_child(_voce("Tempo", "%d:%02d" % [int(t) / 60, int(t) % 60]))
	riga.add_child(_voce("Nemici abbattuti", "%d / %d" % [dati.get("abbattuti", 0), dati.get("nemici", 0)]))
	riga.add_child(_voce("Forzieri aperti", "%d / %d" % [dati.get("forzieri", 0), dati.get("forzieri_tot", 0)]))

	var spazio := Control.new()
	spazio.custom_minimum_size = Vector2(0, 16)
	colonna.add_child(spazio)
	var bottoni := HBoxContainer.new()
	bottoni.alignment = BoxContainer.ALIGNMENT_CENTER
	bottoni.add_theme_constant_override("separation", 24)
	colonna.add_child(bottoni)
	if vinto:
		_pulsante(bottoni, "Prossimo dungeon", "prossimo")
		_pulsante(bottoni, "Rigioca questo", "riprova")
	else:
		_pulsante(bottoni, "Riprova", "riprova")
		_pulsante(bottoni, "Nuovo dungeon", "nuovo")

	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(velo, "color:a", 0.78, 0.6)
	tw.parallel().tween_property(colonna, "modulate:a", 1.0, 0.8).set_delay(0.2)
	await tw.finished
	if not _pulsanti.is_empty() and is_instance_valid(_pulsanti[0]):
		_pulsanti[0].grab_focus()


func _voce(nome : String, valore : String) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var a := Label.new()
	a.text = nome.to_upper()
	a.add_theme_font_size_override("font_size", 13)
	a.add_theme_color_override("font_color", Color(0.6, 0.57, 0.52))
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var b := Label.new()
	b.text = valore
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.93, 0.9, 0.84))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	return v


func _pulsante(dove : Control, testo : String, azione : String) -> void:
	var b := Button.new()
	b.text = testo
	b.custom_minimum_size = Vector2(240, 54)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func(): _scegli(azione))
	dove.add_child(b)
	_pulsanti.append(b)


## Il pad: A (menu_confirm) preme il pulsante col fuoco, la croce lo sposta
## (ui_left/right ce l'hanno gia').
func _unhandled_input(event : InputEvent) -> void:
	if _scelto:
		return
	if event.is_action_pressed("menu_confirm") or event.is_action_pressed("ui_accept"):
		for b in _pulsanti:
			if b.has_focus():
				_scegli_da(b)
				get_viewport().set_input_as_handled()
				return


func _scegli_da(b : Button) -> void:
	b.pressed.emit()


func _scegli(azione : String) -> void:
	if _scelto:
		return
	_scelto = true
	scelto.emit(azione)


func _spaziato(s : String) -> String:
	return " ".join(s.split(""))
