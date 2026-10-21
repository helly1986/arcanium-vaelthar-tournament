extends CanvasLayer

## La schermata di FINE SCONTRO del mini-dungeon: vittoria (uscita trovata,
## dungeon ripulito) o sconfitta (caduto nel baratro, morto in battaglia).
##
## Un velo che scurisce, il titolo grande, il perche', tre numeri (tempo,
## nemici abbattuti, forzieri aperti) e due scelte. Il mondo sotto va in pausa;
## questa schermata no (PROCESS_MODE_ALWAYS). Mouse, tastiera e pad: il primo
## pulsante ha il fuoco, la croce e le frecce lo spostano, A/Invio conferma.
##
## Le scelte (decise dall'autore il 2026-10-20):
##   vittoria: solo «Avanti» ("prossimo");
##   sconfitta: «Riprova» ("riprova", stesso scontro), «Abbandona»
##   ("abbandona"), e se si ha la Pietra del Varco anche «Prosegui» ("varco":
##   al prossimo incontro senza ripetere questo, perk compreso);
##   eliminazione (la terza sconfitta, torneo.gd): solo «Torna al menu»
##   ("eliminato"), senza perk ne' Pietra.
## Sotto i numeri, l'Arcanium alla souls: quanto e' in palio dopo una
## sconfitta, quanto e' perso per sempre, quanto si e' ripreso vincendo.
## Non decide cosa succede dopo: emette `scelto(azione)` e chi la mostra fa il
## resto (costruttore_dungeon.gd).

signal scelto(azione : String)

const ORO := Color(0.86, 0.72, 0.42)
const SANGUE := Color(0.72, 0.16, 0.12)
## Il colore dell'Arcanium, lo stesso dei cristalli nell'HUD (arcanium_hud.gd).
const ARCANIUM := Color("#8b6cff")
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")

var vittoria := false
## La terza sconfitta: la run e' finita.
var eliminato := false
## Il perk scelto per la rivincita (id di perk_rivincita.gd), "" se nessuno.
var perk_scelto := ""
var _pulsanti : Array[Button] = []
var _scelto := false
var _perk_offerti : Array = []
var _colonna : VBoxContainer


## `dati`: {"titolo_motivo": String, "tempo": float, "abbattuti": int,
## "nemici": int, "forzieri": int, "forzieri_tot": int, "pietre_varco": int,
## "perk": Array, "torneo": Dictionary}. `torneo` e' l'esito di torneo.gd:
## sconfitta {"sconfitte", "sconfitte_max", "in_palio", "perso_per_sempre",
## "eliminato"}, vittoria {"recuperato"}.
func mostra(vinto : bool, dati : Dictionary) -> void:
	vittoria = vinto
	var torneo : Dictionary = dati.get("torneo", {})
	eliminato = not vinto and bool(torneo.get("eliminato", false))
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
	_colonna = colonna
	_perk_offerti = [] if eliminato else dati.get("perk", [])

	var titolo := Label.new()
	titolo.text = _spaziato(tr("VICTORY") if vinto else (tr("ELIMINATED") if eliminato else tr("DEFEAT")))
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
	riga.add_child(_voce("Time", "%d:%02d" % [int(t) / 60, int(t) % 60]))
	riga.add_child(_voce("Enemies slain", "%d / %d" % [dati.get("abbattuti", 0), dati.get("nemici", 0)]))
	riga.add_child(_voce("Chests opened", "%d / %d" % [dati.get("forzieri", 0), dati.get("forzieri_tot", 0)]))
	if torneo.has("sconfitte"):
		riga.add_child(_voce("Defeats", "%d / %d" % [torneo["sconfitte"], torneo["sconfitte_max"]]))
	_righe_arcanium(colonna, vinto, torneo)

	var spazio := Control.new()
	spazio.custom_minimum_size = Vector2(0, 16)
	colonna.add_child(spazio)
	var bottoni := HBoxContainer.new()
	bottoni.alignment = BoxContainer.ALIGNMENT_CENTER
	bottoni.add_theme_constant_override("separation", 24)
	colonna.add_child(bottoni)
	if vinto:
		_pulsante(bottoni, "Continue", "prossimo")
	elif eliminato:
		_pulsante(bottoni, "Back to menu", "eliminato")
	else:
		_pulsante(bottoni, "Retry", "riprova")
		var pietre : int = dati.get("pietre_varco", 0)
		if pietre > 0:
			_pulsante(bottoni, tr("Move on  ◈ %d") % pietre, "varco")
			var nota := Label.new()
			nota.text = "Break the Riftstone: skip to the next fight and keep your perk"
			if int(torneo.get("in_palio", 0)) > 0:
				nota.text = "Break the Riftstone: skip to the next fight, keep your perk, and recover your Arcanium"
			nota.add_theme_font_size_override("font_size", 15)
			nota.add_theme_color_override("font_color", Color(0.55, 0.7, 0.95))
			nota.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			colonna.add_child(nota)
		_pulsante(bottoni, "Forfeit", "abbandona")

	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(velo, "color:a", 0.78, 0.6)
	tw.parallel().tween_property(colonna, "modulate:a", 1.0, 0.8).set_delay(0.2)
	await tw.finished
	if not _pulsanti.is_empty() and is_instance_valid(_pulsanti[0]):
		_pulsanti[0].grab_focus()


## Le righe dell'Arcanium: «in palio» e «perso per sempre» dopo una sconfitta,
## «recuperato» dopo la vittoria che lo riprende.
func _righe_arcanium(colonna : Control, vinto : bool, torneo : Dictionary) -> void:
	var testi : Array[String] = []
	if vinto:
		if int(torneo.get("recuperato", 0)) > 0:
			testi.append(tr("◆ %d Arcanium recovered") % torneo["recuperato"])
	else:
		var perso := int(torneo.get("perso_per_sempre", 0))
		var palio := int(torneo.get("in_palio", 0))
		if perso > 0:
			testi.append(tr("◆ %d Arcanium from your last defeat: lost forever") % perso)
		if eliminato:
			if palio > 0:
				testi.append(tr("◆ %d Arcanium lost with the tournament") % palio)
		elif palio > 0:
			testi.append(tr("◆ %d Arcanium at stake: win the rematch to recover it") % palio)
	for k in testi.size():
		var l := Label.new()
		## Un nome per riga: con lo stesso, Godot rinomina la seconda in
		## «@Label@…» e chi le cerca per nome non la trova.
		l.name = "RigaArcanium%d" % k
		l.text = testi[k]
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", ARCANIUM)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		colonna.add_child(l)


func _voce(nome : String, valore : String) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var a := Label.new()
	a.text = tr(nome).to_upper()
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
	b.custom_minimum_size = Vector2(220, 54)
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
	## Dopo una sconfitta, prima di rigiocare si sceglie il perk.
	if not vittoria and azione in ["riprova", "varco"] and not _perk_offerti.is_empty() and perk_scelto == "":
		_mostra_perk(azione)
		return
	_scelto = true
	scelto.emit(azione)


## Al posto dei pulsanti, tre carte: il perk vale per lo scontro che segue.
func _mostra_perk(azione : String) -> void:
	for b in _pulsanti:
		b.get_parent().queue_free()
		break
	_pulsanti.clear()
	for c in _colonna.get_children():
		if c is Label and c.get_index() > 1 and not String(c.name).begins_with("RigaArcanium"):
			c.queue_free()
	var invito := Label.new()
	invito.text = "Choose a perk for the fight ahead"
	invito.add_theme_font_size_override("font_size", 20)
	invito.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
	invito.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_colonna.add_child(invito)
	var carte := HBoxContainer.new()
	carte.alignment = BoxContainer.ALIGNMENT_CENTER
	carte.add_theme_constant_override("separation", 20)
	_colonna.add_child(carte)
	for p in _perk_offerti:
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 150)
		b.focus_mode = Control.FOCUS_ALL
		b.text = "%s
%s

%s" % [p["icona"], tr(p["nome"]), tr(p["testo"])]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 19)
		var id : String = p["id"]
		b.pressed.connect(func():
			perk_scelto = id
			_scegli(azione))
		carte.add_child(b)
		_pulsanti.append(b)
	_pulsanti[0].call_deferred("grab_focus")


func _spaziato(s : String) -> String:
	return " ".join(s.split(""))
