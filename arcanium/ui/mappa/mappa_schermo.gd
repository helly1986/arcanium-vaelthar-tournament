extends Control

## La SCHERMATA DELLA MAPPA DELLA RUN (design-mappa-run, decisioni dell'autore
## del 2026-10-22: pergamena illustrata, medaglioni nelle cornici della UI
## nuova, sentieri a inchiostro, si sale dal basso verso il boss).
##
## Mostra la regione in cui si trova il giocatore (Torneo.regione_attuale): i
## nodi raggiungibili si accendono, quelli fatti restano segnati, il sentiero
## percorso e' d'oro. Toccando un nodo raggiungibile se ne legge il tipo e ci
## si entra: i combattimenti aprono il dungeon, gli altri la loro schermata
## (AZIONI); un tipo senza schermata si completa subito.

const MappaRun := preload("res://arcanium/systems/mappa_run.gd")
const Ornati := preload("res://arcanium/ui/theme/ornati.gd")
const MenuStyle := preload("res://arcanium/ui/game_menu/er_style.gd")

const DUNGEON := "res://arcanium/levels/dungeon/dungeon_prova.tscn"
const MENU := "res://arcanium/ui/main_menu/main_menu.tscn"
## Le schermate dei nodi che non si combattono (una per tipo, nello stesso
## posto: nodo_<tipo>.tscn). Ognuna chiama Torneo.completa() e poi `chiusa`.
const CARTELLA_NODI := "res://arcanium/ui/mappa/"
## Il fondo dipinto di ogni territorio (assets/ui/mappa/<territorio>.jpg).
const CARTELLA_FONDI := "res://assets/ui/mappa/"

const PASSO_PIANO := 132.0
const PASSO_CORSIA := 230.0
const LATO_NODO := 92.0
const INCHIOSTRO := Color(0.16, 0.11, 0.07, 0.85)
const ORO := Color(0.86, 0.68, 0.32)

var _torneo : Node
var _tipi : Dictionary
var _regione : int = 0
var _tela : Control
var _scorri : ScrollContainer
var _bottoni : Dictionary = {}
var _scheda : Control
var _intestazione : Label
var _stato : Label
var _sotto_titolo : Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_torneo = get_node_or_null("/root/Torneo")
	_tipi = MappaRun.tipi()
	if _torneo != null and _torneo.mappa.is_empty():
		_torneo.inizia()
	_costruisci()
	_aggiorna()
	if _torneo != null and _torneo.nodo_corrente != "":
		## Si torna sulla mappa con un nodo aperto (una schermata di nodo
		## lasciata a meta'): lo si riapre.
		_entra.call_deferred(_torneo.nodo_corrente)


func _costruisci() -> void:
	for c in get_children():
		c.queue_free()
	_regione = _torneo.regione_attuale() if _torneo != null else 0
	var reg : Dictionary = _torneo.regione(mini(_regione, 3)) if _torneo != null else {}

	var fondo := ColorRect.new()
	fondo.color = Color(0.23, 0.18, 0.12)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)
	var dipinto := TextureRect.new()
	dipinto.name = "Fondo"
	dipinto.set_anchors_preset(Control.PRESET_FULL_RECT)
	dipinto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dipinto.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var percorso := CARTELLA_FONDI + String(reg.get("territorio", "")) + ".jpg"
	if ResourceLoader.exists(percorso):
		dipinto.texture = load(percorso)
	dipinto.modulate = Color(0.85, 0.8, 0.72)
	add_child(dipinto)
	## Un velo scuro ai bordi: la pergamena alla luce di una candela.
	var velo := ColorRect.new()
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec2 d = UV - vec2(0.5);\n\tfloat v = smoothstep(0.35, 0.85, length(d * vec2(1.1, 0.9)));\n\tCOLOR = vec4(0.03, 0.02, 0.015, v * 0.85);\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	velo.material = mat
	add_child(velo)

	_scorri = ScrollContainer.new()
	_scorri.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scorri.offset_top = 96
	_scorri.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scorri)
	_tela = Control.new()
	_tela.name = "Tela"
	_tela.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tela.custom_minimum_size = Vector2(0, (MappaRun.PIANI + 1) * PASSO_PIANO + 140)
	_tela.draw.connect(_disegna_sentieri)
	_scorri.add_child(_tela)

	var testa := VBoxContainer.new()
	testa.set_anchors_preset(Control.PRESET_TOP_WIDE)
	testa.offset_top = 14
	testa.add_theme_constant_override("separation", 2)
	add_child(testa)
	_intestazione = Ornati.titolo("", 26)
	_intestazione.name = "Territorio"
	testa.add_child(_intestazione)
	_sotto_titolo = Label.new()
	_sotto_titolo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sotto_titolo.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	testa.add_child(_sotto_titolo)
	_stato = Label.new()
	_stato.name = "Stato"
	_stato.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stato.offset_left = -260
	_stato.offset_right = -24
	_stato.offset_top = 18
	_stato.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stato.add_theme_color_override("font_color", Color(0.92, 0.86, 0.74))
	add_child(_stato)

	_bottoni.clear()
	if reg.is_empty():
		return
	for p in (reg["piani"] as Array).size():
		for id in reg["piani"][p]:
			var b := _medaglione(reg["nodi"][id])
			_tela.add_child(b)
			_bottoni[id] = b


## Il medaglione di un nodo: la cornice, il segno del tipo, il nome sotto.
func _medaglione(n : Dictionary) -> Control:
	var tipo : Resource = _tipi.get(n["tipo"])
	var b := Button.new()
	b.name = String(n["id"])
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(LATO_NODO, LATO_NODO)
	b.size = b.custom_minimum_size
	var vuoto := StyleBoxEmpty.new()
	for stato in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(stato, vuoto)
	var disco := Panel.new()
	disco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disco.set_anchors_preset(Control.PRESET_FULL_RECT)
	disco.offset_left = 14
	disco.offset_top = 14
	disco.offset_right = -14
	disco.offset_bottom = -14
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.04)
	sb.set_corner_radius_all(64)
	disco.add_theme_stylebox_override("panel", sb)
	b.add_child(disco)
	var cornice := TextureRect.new()
	cornice.texture = Ornati.MEDAGLIONE
	cornice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cornice.set_anchors_preset(Control.PRESET_FULL_RECT)
	cornice.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cornice.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	b.add_child(cornice)
	var segno := Label.new()
	segno.name = "Segno"
	segno.text = tipo.icona if tipo != null else "?"
	segno.mouse_filter = Control.MOUSE_FILTER_IGNORE
	segno.set_anchors_preset(Control.PRESET_FULL_RECT)
	segno.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	segno.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	segno.add_theme_font_size_override("font_size", 30 if n["tipo"] != "boss" else 38)
	segno.add_theme_color_override("font_color", tipo.colore if tipo != null else Color.WHITE)
	b.add_child(segno)
	var nome := Label.new()
	nome.name = "Nome"
	nome.text = tipo.nome if tipo != null else String(n["tipo"])
	nome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nome.position = Vector2(-30, LATO_NODO - 6)
	nome.size = Vector2(LATO_NODO + 60, 22)
	nome.add_theme_font_size_override("font_size", 14)
	nome.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	nome.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	nome.add_theme_constant_override("outline_size", 5)
	b.add_child(nome)
	b.pressed.connect(_su_nodo.bind(String(n["id"])))
	return b


func _posizione(n : Dictionary) -> Vector2:
	var larghezza : float = maxf(_tela.size.x, size.x)
	var x := larghezza * 0.5 + (int(n["corsia"]) - 1) * PASSO_CORSIA
	var y := _tela.custom_minimum_size.y - 90.0 - int(n["piano"]) * PASSO_PIANO
	return Vector2(x, y)


func _aggiorna() -> void:
	if _torneo == null:
		return
	if _torneo.vinta:
		_fine_run()
		return
	var reg : Dictionary = _torneo.regione(_regione)
	_intestazione.text = MenuStyle.spaziato(tr(String(reg.get("nome", ""))))
	_sotto_titolo.text = tr("Stage %d of %d — %s awaits at the top") % [_regione + 1, (_torneo.mappa["regioni"] as Array).size(), tr(String(reg.get("boss", "")))]
	var banca := get_node_or_null("/root/CrystalBank")
	_stato.text = tr("Defeats %d / %d") % [_torneo.sconfitte, _torneo.sconfitte_max()] + \
			"\n◆ %d" % (int(banca.get("crystals")) if banca != null and "crystals" in banca else 0)
	await get_tree().process_frame
	var aperti : Array = _torneo.raggiungibili()
	for id in _bottoni:
		var b : Button = _bottoni[id]
		var n : Dictionary = reg["nodi"][id]
		b.position = _posizione(n) - b.size * 0.5
		var fatto : bool = id in _torneo.completati
		var aperto : bool = id in aperti
		b.disabled = not aperto
		b.modulate = Color(1, 1, 1) if aperto else (Color(0.8, 0.72, 0.55) if fatto else Color(0.62, 0.58, 0.52, 0.8))
		if aperto:
			var t := b.create_tween().set_loops()
			t.tween_property(b, "scale", Vector2(1.08, 1.08), 0.7).set_trans(Tween.TRANS_SINE)
			t.tween_property(b, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
			b.pivot_offset = b.size * 0.5
	_tela.queue_redraw()
	## Si scorre fino ai nodi aperti.
	if not aperti.is_empty() and _bottoni.has(aperti[0]):
		_scorri.scroll_vertical = int(maxf(0.0, (_bottoni[aperti[0]] as Control).position.y - size.y * 0.55))


func _disegna_sentieri() -> void:
	if _torneo == null:
		return
	var reg : Dictionary = _torneo.regione(_regione)
	if reg.is_empty():
		return
	var fatti : Array = _torneo.completati
	for id in reg["nodi"]:
		var n : Dictionary = reg["nodi"][id]
		for b in n["prossimi"]:
			var da := _posizione(n)
			var a := _posizione(reg["nodi"][b])
			var dir := (a - da).normalized()
			da += dir * LATO_NODO * 0.48
			a -= dir * LATO_NODO * 0.48
			if id in fatti and b in fatti:
				_tela.draw_line(da, a, ORO, 4.0, true)
			else:
				_tela.draw_dashed_line(da, a, INCHIOSTRO, 3.0, 10.0)


## ─── Entrare in un nodo ──────────────────────────────────────────────────────

func _su_nodo(id : String) -> void:
	if _scheda != null:
		_scheda.queue_free()
	var n : Dictionary = _torneo.nodo(id)
	var tipo : Resource = _tipi.get(n["tipo"])
	_scheda = _al_centro(Ornati.pannello(Vector2(540, 340)), "SchedaNodo")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	Ornati.contenuto(_scheda.get_child(0)).add_child(col)
	var titolo := Ornati.titolo(tr(tipo.nome) if tipo != null else "", 24)
	col.add_child(titolo)
	var testo := Label.new()
	testo.text = tr(tipo.descrizione) if tipo != null else ""
	if n["tipo"] == "boss":
		testo.text = tr("%s, champion of this territory. Beat them to move on.") % tr(String(_torneo.regione(int(n["regione"]))["boss"]))
	testo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	testo.custom_minimum_size = Vector2(380, 0)
	testo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(testo)
	var piede := HBoxContainer.new()
	piede.alignment = BoxContainer.ALIGNMENT_CENTER
	piede.add_theme_constant_override("separation", 18)
	col.add_child(piede)
	var indietro := Ornati.bottone("Back", Vector2(170, 50))
	indietro.pressed.connect(func(): _scheda.queue_free(); _scheda = null)
	piede.add_child(indietro)
	var entra := Ornati.bottone("Enter", Vector2(190, 50))
	entra.name = "Entra"
	entra.pressed.connect(func(): _entra(id))
	piede.add_child(entra)
	entra.grab_focus()


## Un riquadro al centro dello schermo, sopra la mappa: un CenterContainer a
## tutto schermo (che ferma anche i tocchi sulla mappa sotto) col riquadro dentro.
func _al_centro(riquadro : Control, nome : String) -> Control:
	var c := CenterContainer.new()
	c.name = nome
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(riquadro)
	add_child(c)
	return c


func _entra(id : String) -> void:
	if _torneo.nodo_corrente != id and not _torneo.scegli(id):
		return
	var n : Dictionary = _torneo.nodo(id)
	var tipo : Resource = _tipi.get(n["tipo"])
	if tipo != null and tipo.combattimento:
		get_tree().change_scene_to_file(DUNGEON)
		return
	var scena := CARTELLA_NODI + "nodo_%s.tscn" % n["tipo"]
	if ResourceLoader.exists(scena):
		var s : Node = load(scena).instantiate()
		s.tree_exited.connect(func(): if is_inside_tree(): _ricostruisci())
		add_child(s)
		return
	## Un tipo senza la sua schermata: si passa oltre.
	_torneo.completa()
	_ricostruisci()


func _ricostruisci() -> void:
	_scheda = null
	_costruisci()
	_aggiorna()


func _fine_run() -> void:
	var box := _al_centro(Ornati.pannello(Vector2(560, 320)), "Vittoria")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	Ornati.contenuto(box.get_child(0)).add_child(col)
	col.add_child(Ornati.titolo(MenuStyle.spaziato(tr("Tournament won")), 26))
	var t := Label.new()
	t.text = tr("Your house's gem goes to the Great Portal of Valdris.")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var b := Ornati.bottone("Main menu", Vector2(220, 50))
	b.pressed.connect(func():
		_torneo.termina()
		get_tree().change_scene_to_file(MENU))
	col.add_child(b)
