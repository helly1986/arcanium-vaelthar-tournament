extends CanvasLayer

## ═══════════════════════════════════════════════════════════════════════════
## MODALE DI EQUIPAGGIAMENTO — scegliere guardando, non a tentativi
## ═══════════════════════════════════════════════════════════════════════════
##
## Prima, cambiare pezzo era "Invio cicla al successivo": premevi e qualcosa
## cambiava, ma per sapere COSA avevi messo dovevi guardare lo slot dopo, e per
## confrontare due armi dovevi passarci attraverso e ricordartele. Un ciclo alla
## cieca va bene con due pezzi, non con un guardaroba.
##
## Qui si sceglie come si sceglie in un negozio: a sinistra cosa hai, a destra
## cosa stai guardando — illustrazione grande, numeri, e la lore sotto. Il pezzo
## si equipaggia solo quando confermi, quindi puoi girare fra le alternative
## senza cambiare niente finché non hai deciso.
##
## ─── Le scelte, e il perché ─────────────────────────────────────────────────
##
## L'ANTEPRIMA È IL DETTAGLIO DELLA VOCE SELEZIONATA, non di quella equipaggiata.
## Muovendoti nella lista cambia tutto il pannello destro: è il confronto vero,
## quello che ti fa dire "questa ha più potenza ma scala peggio".
##
## IL PEZZO EQUIPAGGIATO È MARCATO nella lista, e resta selezionabile. Toglierlo
## dalle alternative sarebbe più "pulito" ma ti impedirebbe di rileggerne i
## numeri mentre confronti — che è esattamente il momento in cui servono.
##
## LA CORNICE DELL'ILLUSTRAZIONE HA ALTEZZA FISSA anche quando l'immagine manca
## (stessa regola del grimorio): senza, scorrendo la lista il pannello si
## allungherebbe e accorcerebbe a ogni voce e l'occhio perderebbe il punto.
##
## I PEZZI CHIUSI DA UN LUCCHETTO RESTANO IN LISTA (`EquipmentLoadout.sbloccato`:
## l'arco prima del tomo dell'Arcieria). Si vedono, col lucchetto e il nome della
## tecnica che manca, e non si mettono: la modale resta aperta. Toglierli dalla
## lista sarebbe più "pulito" ma nasconderebbe la domanda giusta — «ho un arco,
## perché non lo posso usare?» — e la risposta sta proprio qui accanto.


## Alta abbastanza da valere come illustrazione, bassa abbastanza da lasciare
## spazio ai numeri e alla lore sotto senza scroll.
const ALTEZZA_ILLUSTRAZIONE := 220.0
const LARGHEZZA_LISTA := 300.0
const LARGHEZZA_DETTAGLIO := 420.0

## Equipaggiato: il menu si ridisegna. Chiuso senza scegliere: nessun cambiamento.
signal equipaggiato(slot_id : String)
signal chiusa

var slot_id : String = ""
var etichetta_slot : String = ""
var alternative : Array = []       ## risorse compatibili con lo slot
var equipaggiato_ora : Resource = null

var _sel : int = 0
var _lista : VBoxContainer
var _dettaglio : VBoxContainer


func _ready() -> void:
	## Sopra il menu di gioco (10): è un suo figlio logico, ma deve coprirlo.
	layer = 15

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var lastra := PanelContainer.new()
	lastra.add_theme_stylebox_override("panel", MenuStyle.sfondo())
	lastra.set_anchors_preset(Control.PRESET_FULL_RECT)
	lastra.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(lastra)

	var centro := CenterContainer.new()
	lastra.add_child(centro)

	var pagina := PanelContainer.new()
	pagina.add_theme_stylebox_override("panel", MenuStyle.pagina(24))
	centro.add_child(pagina)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pagina.add_child(col)

	col.add_child(MenuStyle.intestazione(etichetta_slot))
	col.add_child(MenuStyle.separatore())

	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 22)
	col.add_child(riga)

	_lista = VBoxContainer.new()
	_lista.custom_minimum_size = Vector2(LARGHEZZA_LISTA, 0)
	_lista.add_theme_constant_override("separation", 2)
	riga.add_child(_lista)

	riga.add_child(VSeparator.new())

	_dettaglio = VBoxContainer.new()
	_dettaglio.custom_minimum_size = Vector2(LARGHEZZA_DETTAGLIO, 0)
	_dettaglio.add_theme_constant_override("separation", 8)
	riga.add_child(_dettaglio)

	col.add_child(MenuStyle.separatore())
	var aiuto : Label = MenuStyle.testo(
		MenuStyle.spaziato("Su/Giù scegli     Invio equipaggia     Esc annulla"),
		MenuStyle.CORPO_AIUTO, MenuStyle.TESTO_FIOCO)
	aiuto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(aiuto)

	## Parte dal pezzo che hai addosso: è il termine di paragone di ogni
	## confronto, quindi è da lì che si guarda.
	for i in alternative.size():
		if alternative[i] == equipaggiato_ora:
			_sel = i
			break
	_disegna()


# ─── Disegno ────────────────────────────────────────────────────────────────

func _disegna() -> void:
	for f in _lista.get_children():
		f.queue_free()
	for f in _dettaglio.get_children():
		f.queue_free()

	if alternative.is_empty():
		_lista.add_child(MenuStyle.testo("Non possiedi nulla per questo slot.",
			MenuStyle.CORPO_VOCE, MenuStyle.TESTO_FIOCO))
		return

	for i in alternative.size():
		_lista.add_child(_voce(alternative[i], i == _sel, alternative[i] == equipaggiato_ora))
	_disegna_dettaglio(alternative[_sel])


## `null` in `alternative` è la voce "Nessuno": la aggiunge chi apre la modale,
## e solo per gli slot dove restare a vuoto è una scelta legittima (i talismani).
## Su un'arma non lo è — a mani nude non ci si va per scelta.
func _voce(res : Resource, selezionata : bool, indossato : bool) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", MenuStyle.riga(selezionata))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	if res == null:
		var vuoto : Label = MenuStyle.testo("○   Nessuno", MenuStyle.CORPO_VOCE,
			MenuStyle.TESTO if selezionata else MenuStyle.TESTO_FIOCO)
		vuoto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(vuoto)
		if indossato:
			row.add_child(MenuStyle.testo("•", MenuStyle.CORPO_VOCE, MenuStyle.ORO))
		return box

	var chiuso := _tecnica_mancante(res) != null
	var ico : Label = MenuStyle.testo(str(res.get("icon")), 20,
		MenuStyle.ORO if selezionata and not chiuso else MenuStyle.TESTO_FIOCO)
	ico.custom_minimum_size = Vector2(28, 0)
	ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(ico)

	var nome : Label = MenuStyle.testo(str(res.get("name")), MenuStyle.CORPO_VOCE,
		MenuStyle.TESTO if selezionata and not chiuso else MenuStyle.TESTO_FIOCO)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nome)

	## Il segno di "indossato" è un punto, non la parola: la lista deve restare
	## una colonna di nomi, e una didascalia per riga la spezzerebbe. Lo stesso
	## per il lucchetto: il perché sta nel dettaglio.
	if chiuso:
		var luc : Label = MenuStyle.testo("🔒", MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO)
		luc.tooltip_text = "Richiede: " + str(_tecnica_mancante(res).get("name"))
		row.add_child(luc)
	elif indossato:
		var seg : Label = MenuStyle.testo("•", MenuStyle.CORPO_VOCE, MenuStyle.ORO)
		seg.tooltip_text = "Equipaggiato"
		row.add_child(seg)

	return box


## La tecnica di guerra che manca per impugnare il pezzo, o null se si può.
## Lo sa l'armadio (`EquipmentLoadout`), qui si chiede soltanto.
func _tecnica_mancante(res : Resource) -> Resource:
	var l := get_node_or_null("/root/EquipmentLoadout")
	if l == null or res == null or not l.has_method("sbloccato"):
		return null
	if bool(l.call("sbloccato", res)):
		return null
	return l.call("tecnica_richiesta", res)


func _disegna_dettaglio(res : Resource) -> void:
	if res == null:
		_dettaglio.add_child(MenuStyle.titolo("Nessuno", 22, MenuStyle.TESTO))
		_dettaglio.add_child(MenuStyle.corpo_ricco(
			"Lo slot resta vuoto. Un talismano in meno addosso è un talismano che potrai cambiare altrove senza tornare indietro.",
			LARGHEZZA_DETTAGLIO, MenuStyle.CORPO_VOCE, MenuStyle.TESTO_FIOCO))
		return
	_dettaglio.add_child(_illustrazione(res))
	_dettaglio.add_child(MenuStyle.titolo(str(res.get("name")), 22, MenuStyle.TESTO))

	## Il lucchetto, per esteso: cosa manca e dove si trova. Sta sopra i
	## numeri, perché finché è chiuso i numeri non contano.
	var manca := _tecnica_mancante(res)
	if manca != null:
		_dettaglio.add_child(MenuStyle.corpo_ricco(
			"🔒  [color=#c8ab6d]Richiede la tecnica di guerra «%s»[/color] — si impara dal suo tomo. Fino ad allora resta nello zaino."
				% str(manca.get("name")),
			LARGHEZZA_DETTAGLIO, MenuStyle.CORPO_VOCE, MenuStyle.TESTO))

	var righe : Array[String] = []
	for v in _statistiche(res):
		righe.append("[color=#8a8070]%s[/color]   %s" % [v[0], v[1]])
	if righe.size() > 0:
		_dettaglio.add_child(MenuStyle.corpo_ricco("\n".join(righe),
			LARGHEZZA_DETTAGLIO, MenuStyle.CORPO_VOCE, MenuStyle.TESTO))

	var lore := str(res.get("lore"))
	if lore.strip_edges() != "":
		_dettaglio.add_child(MenuStyle.separatore())
		_dettaglio.add_child(MenuStyle.corpo_ricco("[i]%s[/i]" % lore,
			LARGHEZZA_DETTAGLIO, MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))


## I numeri che cambiano una decisione, non tutti quelli che la risorsa possiede:
## un elenco esaustivo si smette di leggere, e le voci che contano si perdono in
## mezzo a quelle che valgono zero. Le voci vuote non compaiono affatto.
func _statistiche(res : Resource) -> Array:
	var out : Array = []
	var pot := int(res.get("base_power")) if ("base_power" in res) else 0
	if pot > 0:
		out.append(["Potenza", str(pot)])
	if res.has_method("scaling_label"):
		var sc := str(res.call("scaling_label"))
		if sc.strip_edges() != "" and sc != "- -":
			out.append(["Scala con", sc])
	var dt := str(res.get("damage_type")) if ("damage_type" in res) else ""
	if dt != "":
		out.append(["Danno", dt.capitalize()])
	var poise := float(res.get("poise_damage")) if ("poise_damage" in res) else 0.0
	if poise > 0.0:
		out.append(["Rottura guardia", "%d" % int(poise)])

	## Le resistenze sono la ragione per cui esistono armatura e talismani: se ci
	## sono, sono LA statistica del pezzo. Il bonus alle evocazioni
	## (`summon_damage_bonus`) resta nei dati per il battleground, ma il campione
	## non evoca: qui non si mostra.
	var resi : Dictionary = res.get("resistances") if ("resistances" in res) else {}
	for k in resi:
		var v := float(resi[k])
		if is_equal_approx(v, 1.0):
			continue
		## Il moltiplicatore è il dato interno; a schermo va la differenza, col
		## segno: "-25%" si legge, "0.75" va tradotto ogni volta.
		out.append(["Resistenza %s" % str(k).capitalize(),
			"%+d%%" % int(round((1.0 - v) * 100.0))])
	return out


func _illustrazione(res : Resource) -> Control:
	var cornice := PanelContainer.new()
	cornice.add_theme_stylebox_override("panel", MenuStyle.pannello(6))
	cornice.custom_minimum_size = Vector2(0, ALTEZZA_ILLUSTRAZIONE)

	var img = res.get("image") if ("image" in res) else null
	if img is Texture2D:
		var tex := TextureRect.new()
		tex.texture = img
		## KEEP_ASPECT_CENTERED e non COVERED: un'illustrazione commissionata non
		## si ritaglia per riempire una cornice.
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.custom_minimum_size = Vector2(0, ALTEZZA_ILLUSTRAZIONE)
		cornice.add_child(tex)
	else:
		## Il simbolo grande al posto dell'illustrazione mancante: dichiara che
		## quel posto è di un'immagine che ancora non c'è, invece di lasciare un
		## buco che sembra un errore.
		var seg : Label = MenuStyle.testo(str(res.get("icon")), 84, MenuStyle.ORO_TENUE)
		seg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cornice.add_child(seg)
	return cornice


# ─── Input ──────────────────────────────────────────────────────────────────

func _unhandled_input(event : InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_game_menu") \
			or event.is_action_pressed("menu_back"):
		_chiudi()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("inv_next"):
		_muovi(1)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("inv_prev"):
		_muovi(-1)
	elif event.is_action_pressed("menu_confirm") or event.is_action_pressed("ui_accept"):
		_conferma()
	else:
		return
	get_viewport().set_input_as_handled()


func _muovi(dir : int) -> void:
	if alternative.size() <= 1:
		return
	_sel = (_sel + dir + alternative.size()) % alternative.size()
	_disegna()


func _conferma() -> void:
	if alternative.is_empty():
		_chiudi()
		return
	var scelto : Resource = alternative[_sel]
	var l := get_node_or_null("/root/EquipmentLoadout")
	if l:
		## "Nessuno" svuota lo slot invece di equipaggiare: e' la via d'uscita
		## dai talismani, senza la quale metterne uno sarebbe irreversibile.
		if scelto == null:
			if l.has_method("unequip"):
				l.call("unequip", slot_id)
		elif l.has_method("equip"):
			## L'armadio può rifiutare (lucchetto): allora non si chiude niente,
			## il dettaglio dice già cosa manca.
			if not bool(l.call("equip", slot_id, scelto)):
				return
	equipaggiato.emit(slot_id)
	_chiudi()


func _chiudi() -> void:
	chiusa.emit()
	queue_free()
