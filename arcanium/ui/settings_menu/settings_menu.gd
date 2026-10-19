extends Control

## Pannello Impostazioni — porting di MainMenu.js/_settingsHTML (Arcanium-Lite).
## Video/Comandi/Gameplay restano placeholder onesti ("— presto disponibile —"),
## come in Lite. In Audio, "Volume generale" e "Musica" sono slider REALI sui bus
## Master/Music; "Effetti sonori" e "Ambient" restano placeholder finché non
## esiste un bus SFX dedicato.

signal closed

## Il menu principale è anche la scena d'avvio del progetto: si legge da lì,
## così resta un posto solo da cambiare.
const MAIN_MENU := "res://arcanium/ui/main_menu/main_menu.tscn"

const TABS := ["Video", "Audio", "Comandi", "Gameplay"]

const PLACEHOLDER_ROWS := {
	"Video": ["Qualità ombre", "Effetti (FX)", "V-Sync"],
	"Comandi": ["Attacco", "Affondo", "Gadget", "Schivata / Scatto", "Interagisci", "Lock-on"],
	"Gameplay": ["Difficoltà", "Vibrazione", "Suggerimenti", "Auto-lock bersaglio"],
}

## Righe REALI: tolte dai placeholder e collegate a un parametro vivo. Elencate
## qui perché il pannello le costruisce a parte, prima dei placeholder rimasti.
const REAL_ROWS := {
	"Video": ["Modalità finestra", "Risoluzione", "Acqua"],
	"Gameplay": ["Camera in lock-on"],
}

## Secondi per confermare un cambio di video prima che torni indietro da solo.
const SECONDI_CONFERMA := 10

var _tab_buttons : Dictionary = {}
var _panels : Dictionary = {}
var _current_tab := "Audio"

var _scelta_modo : OptionButton
var _scelta_risoluzione : OptionButton
var _conferma_in_corso := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	## Lastra a SCHERMO INTERO, come l'inventario: le impostazioni non
	## galleggiano sul gioco, lo sostituiscono, e il mondo resta appena
	## percepibile sotto (MenuStyle.FONDO è nero al 93%). Prima era una card al
	## 75% con un velo sopra, che accanto al menu di gioco leggeva come un'altra
	## applicazione.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuStyle.sfondo())
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)

	## Stessi margini larghi e asimmetrici del menu di gioco: il contenuto sta in
	## una colonna centrale e il bordo dello schermo resta vuoto.
	var margine := MarginContainer.new()
	margine.add_theme_constant_override("margin_left", 90)
	margine.add_theme_constant_override("margin_right", 90)
	margine.add_theme_constant_override("margin_top", 54)
	margine.add_theme_constant_override("margin_bottom", 40)
	card.add_child(margine)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margine.add_child(vbox)

	vbox.add_child(_build_header())
	vbox.add_child(_build_tabs())

	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	vbox.add_child(content)
	for tab in TABS:
		var panel := _build_panel(tab)
		panel.visible = (tab == _current_tab)
		content.add_child(panel)
		_panels[tab] = panel

	var piede := HBoxContainer.new()
	var note := Label.new()
	note.text = "Le voci in grigio sono placeholder — verranno collegate ai parametri reali."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.58, 0.65))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	piede.add_child(note)
	piede.add_child(_build_quit_button())
	vbox.add_child(piede)

	_select_tab(_current_tab)

## Lo STESSO pannello serve sia in partita sia dal menu principale, quindi la
## via d'uscita non può essere una sola: dal menu principale "torna al menu
## principale" non vuol dire niente, e la cosa sensata è chiudere il gioco.
## Fuori da un desktop, invece, non c'è niente da chiudere: su web l'uscita non
## porta da nessuna parte e il bottone semplicemente non compare.
func _build_quit_button() -> Control:
	if _siamo_nel_menu_principale():
		if not _e_desktop():
			return Control.new()
		return _bottone("Esci dal gioco", "Uscire dal gioco?",
			"La partita in corso resta salvata all'ultimo checkpoint.",
			"Esci", _esci_dal_gioco)
	return _bottone("Torna al menu principale", "Tornare al menu principale?",
		"I progressi dall'ultimo checkpoint andranno persi.",
		"Torna al menu", _torna_al_menu)


func _siamo_nel_menu_principale() -> bool:
	var scena := get_tree().current_scene
	return scena != null and scena.scene_file_path == MAIN_MENU


func _e_desktop() -> bool:
	return OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]


## Chiede sempre conferma: sono due azioni che buttano via qualcosa, e stanno a
## un centimetro dai cursori del volume — un click distratto costerebbe caro.
func _bottone(etichetta : String, titolo : String, testo : String,
		conferma : String, azione : Callable) -> Control:
	var btn := Button.new()
	btn.text = etichetta
	btn.pressed.connect(func():
		var chiedi := ConfirmationDialog.new()
		chiedi.title = titolo
		chiedi.dialog_text = testo
		chiedi.ok_button_text = conferma
		chiedi.cancel_button_text = "Resta"
		chiedi.confirmed.connect(azione)
		add_child(chiedi)
		chiedi.popup_centered()
	)
	return btn


func _torna_al_menu() -> void:
	## ⚠️ Se qualcuno ha messo in pausa l'albero, cambiare scena lo lascerebbe in
	## pausa e il menu principale nascerebbe congelato.
	get_tree().paused = false
	closed.emit()
	get_tree().change_scene_to_file(MAIN_MENU)


func _esci_dal_gioco() -> void:
	get_tree().quit()


func _build_header() -> Control:
	var row := HBoxContainer.new()
	var title := MenuStyle.titolo("Impostazioni")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func(): closed.emit())
	row.add_child(close_btn)
	return row

func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for tab in TABS:
		var btn := Button.new()
		btn.text = tab
		btn.toggle_mode = true
		btn.pressed.connect(_select_tab.bind(tab))
		row.add_child(btn)
		_tab_buttons[tab] = btn
	return row

func _select_tab(tab : String) -> void:
	_current_tab = tab
	for t in _tab_buttons.keys():
		_tab_buttons[t].button_pressed = (t == tab)
	for t in _panels.keys():
		_panels[t].visible = (t == tab)

func _build_panel(tab : String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	if tab == "Audio":
		box.add_child(_build_bus_row("Volume generale", "Master"))
		box.add_child(_build_bus_row("Musica", "Music"))
		box.add_child(_placeholder_row("Effetti sonori"))
		box.add_child(_placeholder_row("Ambient"))
	else:
		if tab == "Gameplay":
			var riga := _build_lock_camera_row()
			if riga:
				box.add_child(riga)
			var riga_zoom := _build_zoom_camera_row()
			if riga_zoom:
				box.add_child(riga_zoom)
		elif tab == "Video":
			for riga in _build_video_rows():
				box.add_child(riga)
		for label in PLACEHOLDER_ROWS[tab]:
			box.add_child(_placeholder_row(label))
	return box


## Modalità finestra e risoluzione. Vanno insieme: la risoluzione conta solo in
## finestra, negli altri modi la detta lo schermo — e infatti la tendina si
## spegne, invece di restare attiva e non fare niente.
func _build_video_rows() -> Array[Control]:
	var prefs := get_node_or_null("/root/GameSettings")
	var display := get_node_or_null("/root/DisplayManager")
	if prefs == null or display == null:
		return [_placeholder_row("Modalità finestra"), _placeholder_row("Risoluzione")] as Array[Control]

	_scelta_modo = OptionButton.new()
	_scelta_modo.custom_minimum_size = Vector2(240, 0)
	## L'ordine segue l'enum, così l'indice È il valore: nessuna tabella di
	## conversione da tenere allineata a mano.
	for i in display.ModoFinestra.size():
		_scelta_modo.add_item(str(display.NOME_MODO.get(i, "?")), i)
	_scelta_modo.select(prefs.modo_finestra)
	_scelta_modo.item_selected.connect(func(idx : int) -> void:
		_cambia_video(idx, prefs.risoluzione)
	)

	_scelta_risoluzione = OptionButton.new()
	_scelta_risoluzione.custom_minimum_size = Vector2(240, 0)
	var buone : Array[Vector2i] = display.risoluzioni_disponibili()
	for i in buone.size():
		var r : Vector2i = buone[i]
		_scelta_risoluzione.add_item("%d × %d" % [r.x, r.y], i)
	_scelta_risoluzione.select(maxi(buone.find(prefs.risoluzione), 0))
	_scelta_risoluzione.item_selected.connect(func(idx : int) -> void:
		_cambia_video(prefs.modo_finestra, buone[idx])
	)

	_aggiorna_abilitazione_risoluzione()
	return [
		_riga_con_scelta("Modalità finestra", _scelta_modo),
		_riga_con_scelta("Risoluzione", _scelta_risoluzione),
		_build_acqua_row(prefs),
	] as Array[Control]


## ─── ACQUA ──────────────────────────────────────────────────────────────────
## Rifrazione e riflesso sul guado. ⚠️ NON passa dalla conferma a tempo come
## finestra e risoluzione: quelle possono lasciarti chiuso fuori dal tuo gioco
## (una risoluzione che il monitor non regge), questa al massimo fa qualche
## fotogramma in meno e si rimette da sola. Un countdown qui sarebbe teatro.
func _build_acqua_row(prefs : Node) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Acqua"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var scelta := OptionButton.new()
	scelta.custom_minimum_size = Vector2(240, 0)
	## L'indice E' il valore, come nelle altre righe: 0 semplice, 1 ricca.
	scelta.add_item("Semplice", 0)
	scelta.add_item("Riflessi e rifrazione", 1)
	scelta.select(1 if bool(prefs.acqua_ricca) else 0)
	scelta.item_selected.connect(func(idx : int) -> void:
		prefs.acqua_ricca = idx == 1
	)
	row.add_child(scelta)
	return row


func _riga_con_scelta(etichetta : String, scelta : Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = etichetta
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(scelta)
	return row


func _aggiorna_abilitazione_risoluzione() -> void:
	var prefs := get_node_or_null("/root/GameSettings")
	var display := get_node_or_null("/root/DisplayManager")
	if _scelta_risoluzione == null or prefs == null or display == null:
		return
	var in_finestra : bool = prefs.modo_finestra == display.ModoFinestra.FINESTRA
	_scelta_risoluzione.disabled = not in_finestra
	_scelta_risoluzione.tooltip_text = "" if in_finestra \
		else "La risoluzione si sceglie solo in modalità Finestra."


## Applica subito e poi chiede conferma con un conto alla rovescia: se il
## giocatore non risponde si torna indietro da soli. È la rete di sicurezza
## classica — una modalità sbagliata può rendere illeggibile proprio il pannello
## che servirebbe per rimediare.
func _cambia_video(nuovo_modo : int, nuova_risoluzione : Vector2i) -> void:
	var prefs := get_node_or_null("/root/GameSettings")
	if prefs == null or _conferma_in_corso:
		return

	var vecchio_modo : int = prefs.modo_finestra
	var vecchia_risoluzione : Vector2i = prefs.risoluzione
	if nuovo_modo == vecchio_modo and nuova_risoluzione == vecchia_risoluzione:
		return

	_conferma_in_corso = true
	prefs.modo_finestra = nuovo_modo
	prefs.risoluzione = nuova_risoluzione
	_aggiorna_abilitazione_risoluzione()

	var dlg := ConfirmationDialog.new()
	dlg.title = "Video"
	dlg.ok_button_text = "Mantieni"
	dlg.cancel_button_text = "Annulla"
	add_child(dlg)

	var rimasti := SECONDI_CONFERMA
	dlg.dialog_text = _testo_conferma(rimasti)

	var tic := Timer.new()
	tic.wait_time = 1.0
	dlg.add_child(tic)

	var chiudi := func(mantieni : bool) -> void:
		if not _conferma_in_corso:
			return
		_conferma_in_corso = false
		tic.stop()
		if not mantieni:
			prefs.modo_finestra = vecchio_modo
			prefs.risoluzione = vecchia_risoluzione
			_rileggi_scelte()
		dlg.queue_free()

	tic.timeout.connect(func() -> void:
		rimasti -= 1
		if rimasti <= 0:
			chiudi.call(false)
		else:
			dlg.dialog_text = _testo_conferma(rimasti)
	)
	dlg.confirmed.connect(func() -> void: chiudi.call(true))
	dlg.canceled.connect(func() -> void: chiudi.call(false))

	dlg.popup_centered()
	tic.start()


func _testo_conferma(secondi : int) -> String:
	return "Mantenere queste impostazioni video?\n\nSi torna indietro fra %d second%s." \
		% [secondi, "o" if secondi == 1 else "i"]


## Rimette le tendine su quello che vale davvero, dopo un ripristino.
func _rileggi_scelte() -> void:
	var prefs := get_node_or_null("/root/GameSettings")
	var display := get_node_or_null("/root/DisplayManager")
	if prefs == null or display == null:
		return
	if _scelta_modo != null:
		_scelta_modo.select(prefs.modo_finestra)
	if _scelta_risoluzione != null:
		var buone : Array[Vector2i] = display.risoluzioni_disponibili()
		_scelta_risoluzione.select(maxi(buone.find(prefs.risoluzione), 0))
	_aggiorna_abilitazione_risoluzione()

## Stile della camera quando sei agganciato. Non è un vezzo: cambia il combat
## feeling più di quanto sembri — dritta è soulslike, obliqua sa di Diablo, di
## lato sa di picchiaduro 2.5D — e c'è chi non vuole proprio che la camera si
## muova da sola.
func _build_lock_camera_row() -> Control:
	var prefs := get_node_or_null("/root/GameSettings")
	if prefs == null:
		return null
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Camera in lock-on"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var scelta := OptionButton.new()
	scelta.custom_minimum_size = Vector2(240, 0)
	## L'ordine delle voci segue l'enum, così l'indice È il valore: nessuna
	## tabella di conversione da tenere allineata a mano.
	for i in prefs.LockCamera.size():
		scelta.add_item(str(prefs.NOME_STILE.get(i, "?")), i)
	scelta.select(prefs.lock_camera)
	scelta.item_selected.connect(func(idx : int): prefs.lock_camera = idx)
	row.add_child(scelta)
	return row

## Come si comporta lo ZOOM. Il classico scala e basta: ci si avvicina e si
## vedono le stesse cose piu' grandi. Il cinematico abbassa l'elevazione mentre
## ci si avvicina, cosi' entra nell'inquadratura cio' che sta in ALTO — chiome,
## ballatoi, la volta di Kalvorn. Su ambientazioni verticali e' la differenza
## fra un ingrandimento e una scoperta.
func _build_zoom_camera_row() -> Control:
	var prefs := get_node_or_null("/root/GameSettings")
	if prefs == null or not ("zoom_camera" in prefs):
		return null
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Zoom camera"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var scelta := OptionButton.new()
	scelta.custom_minimum_size = Vector2(240, 0)
	## Come per il lock-on: l'ordine segue l'enum, quindi l'indice E' il valore e
	## non serve nessuna tabella di conversione da tenere allineata a mano.
	for i in prefs.ZoomCamera.size():
		scelta.add_item(str(prefs.NOME_ZOOM.get(i, "?")), i)
	scelta.select(prefs.zoom_camera)
	scelta.item_selected.connect(func(idx : int): prefs.zoom_camera = idx)
	row.add_child(scelta)
	return row


func _placeholder_row(label_text : String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var placeholder := Label.new()
	placeholder.text = "— presto disponibile —"
	placeholder.add_theme_color_override("font_color", Color(0.5, 0.48, 0.55))
	row.add_child(placeholder)
	return row

func _build_bus_row(label_text : String, bus_name : String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)

	var bus_idx := AudioServer.get_bus_index(bus_name)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_idx)) if bus_idx >= 0 else 1.0
	slider.value_changed.connect(func(v : float):
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(v))
	)
	row.add_child(slider)
	return row
