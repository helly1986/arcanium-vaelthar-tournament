extends VBoxContainer

## ═══════════════════════════════════════════════════════════════════════════
## IL GRIMORIO — tomo di pergamena sfogliabile, UNA MAGIA PER PAGINA
## ═══════════════════════════════════════════════════════════════════════════
##
## Prima era un elenco: righe con angoli tondi, una sotto l'altra, dentro uno
## ScrollContainer. Un elenco dice "hai queste cose". Un libro dice "queste cose
## sono state SCRITTE da qualcuno" — ed è l'unica delle due letture giusta per
## un grimorio, che nella lore è un oggetto fisico che si tramanda.
##
## ─── Le scelte, e il perché ─────────────────────────────────────────────────
##
## UNA MAGIA PER APERTURA, NON PER FACCIATA. Il libro è aperto: si vedono due
## facciate insieme, e dedicarne una a testa a due magie diverse le metterebbe
## in competizione — l'occhio salta di qua e di là e non legge nessuna delle
## due. Qui l'apertura INTERA è di una magia sola: a sinistra la sua immagine e
## i suoi numeri, a destra il suo testo. È il taglio del bestiario di un
## manuale, ed è quello che rende il gesto di sfogliare significativo: giri
## pagina e cambi argomento, non scorri mezzo elenco.
##
## NIENTE SCROLL. Uno ScrollContainer avrebbe fatto stare tutto, ma sfogliare e
## scorrere sono due gesti diversi e mescolati si annullano: se il contenuto si
## può già scorrere, girare pagina diventa ridondante. Il testo sta nella
## facciata perché la facciata è la misura — se un lore non ci sta, va accorciato
## il lore, non allungata la pagina.
##
## L'INCHIOSTRO COMPARE. A ogni voltata il testo si scrive da sé
## (`visible_ratio`, vedi MenuStyle.svela). Non è decorazione: è ciò che
## trasforma il cambio di pagina da "sostituzione istantanea di contenuto" in
## un evento che ha una durata, e che quindi si nota. Mezzo secondo, non di più:
## chi sfoglia veloce non deve aspettare.
##
## ⚠️ La larghezza delle pagine è DICHIARATA (LARGHEZZA_PAGINA), non dedotta.
## Un RichTextLabel con autowrap dentro un contenitore che si dimensiona sul
## contenuto trova larghezza minima zero e manda a capo ogni singolo carattere:
## il lore diventa una colonna verticale di lettere. Vedi MenuStyle.corpo_ricco.


## La cartella da cui il grimorio si riempie. Le evocazioni
## (`resources/summons/`) non ci sono piu': non sono del campione, avranno il
## battleground (decisione dell'autore del 2026-10-21).
const SPELLS_DIR := "res://arcanium/resources/spells/"

## Larghezza MINIMA di una facciata, non la sua larghezza vera: le due pagine
## sono EXPAND_FILL e si spartiscono la colonna del menu, così il tomo è largo
## quanto la pagina invece di galleggiarci in mezzo. Il minimo serve solo a
## garantire che il RichTextLabel del lore abbia sempre una larghezza > 0 su cui
## mandare a capo (vedi l'avvertenza in testa al file).
const LARGHEZZA_MINIMA_PAGINA := 380.0
## ⚠️ Questi due numeri sono tarati sul BUDGET VERTICALE di 720p, non scelti per
## gusto. Il menu vive dentro margini di 54 in alto e 40 in basso e sopra il tomo
## ci sono le schede, sotto un piede: al grimorio restano ~540px. Con i valori
## originali (520 di pagina, 340 di illustrazione) il tomo ne chiedeva ~625 e il
## piede — "← → sfoglia, 1 di 3" — finiva tagliato fuori dallo schermo insieme
## alla barra dei comandi del menu. Alzandoli si ripresenta lo stesso taglio.
const ALTEZZA_ILLUSTRAZIONE := 250.0
## Il tomo non si allunga fino a riempire lo schermo: prende l'altezza che gli
## serve e si centra. Questo minimo tiene le due facciate della stessa misura
## anche quando la magia ha poco testo — un libro le cui pagine cambiano altezza
## a ogni voltata non sembra un libro.
const ALTEZZA_MINIMA_PAGINA := 430.0

## Nomi leggibili dei tipi di danno. La sigla secca ("CRIO") sta bene in un
## tooltip di debug, non nel tomo che il personaggio ha in mano.
const TIPI_DANNO := {
	"FISICO": "fisico", "TAGLIO": "da taglio", "PERFORAZIONE": "perforante",
	"SCHIANTO": "da schianto", "CRIO": "di gelo", "EROSIONE": "d'erosione",
	"SACRO": "sacro", "FRATTURA": "di frattura", "VELENO": "velenoso",
	"FUOCO": "di fuoco", "FULMINE": "di fulmine",
}

## Voci caricate, in ordine di lettura. Ogni voce è un Dictionary descritto in
## `_descrivi`.
var _voci : Array = []
var _pagina : int = 0

var _apertura : HBoxContainer     ## le due facciate: è ciò che si dissolve
var _piede : Label
var _tween_apertura : Tween


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	ricarica()


## Rilegge le risorse da disco e ridisegna. Da chiamare quando il giocatore può
## aver imparato qualcosa di nuovo (apertura del menu).
func ricarica() -> void:
	var prima : int = _voci.size()
	_voci = _carica_voci()
	if _voci.is_empty():
		_pagina = 0
	elif prima != _voci.size():
		_pagina = clampi(_pagina, 0, _voci.size() - 1)
	else:
		_pagina = clampi(_pagina, 0, _voci.size() - 1)
	_ridisegna(false)


## Gira pagina. Non cicla: un libro ha una prima e un'ultima pagina, e sbattere
## contro il fondo è un'informazione ("non c'è altro"), non un errore.
func sfoglia(direzione : int) -> void:
	if _voci.size() <= 1:
		return
	var nuova := clampi(_pagina + direzione, 0, _voci.size() - 1)
	if nuova == _pagina:
		return
	_pagina = nuova
	_ridisegna(true)


func numero_pagine() -> int:
	return _voci.size()


## ─── Disegno ────────────────────────────────────────────────────────────────

func _ridisegna(animata : bool) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_apertura = null

	add_child(_testata())

	if _voci.is_empty():
		add_child(_pagina_bianca())
		return

	_apertura = HBoxContainer.new()
	_apertura.add_theme_constant_override("separation", 0)
	# Il tomo si prende tutta la larghezza della colonna e SOLO l'altezza che gli
	# serve, centrata. Con EXPAND_FILL in verticale le due facciate si
	# allungavano fino in fondo allo schermo e il testo restava rannicchiato in
	# cima a due colonne di vuoto.
	_apertura.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# SHRINK_CENTER da solo non basta: senza il bit EXPAND il VBox non gli
	# assegna lo spazio avanzato, e "centrarsi" dentro zero pixel di avanzo
	# significa restare incollato in cima.
	_apertura.size_flags_vertical = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	add_child(_apertura)

	var voce : Dictionary = _voci[_pagina]
	_apertura.add_child(_facciata_sinistra(voce))
	_apertura.add_child(MenuStyle.dorso())
	var destra := _facciata_destra(voce, animata)
	_apertura.add_child(destra)

	add_child(_piede_pagina())

	if animata:
		# La pagina intera si dissolve in entrata. NON si anima la `position`:
		# dentro un Container le posizioni dei figli vengono riscritte a ogni
		# queue_sort() e l'animazione verrebbe mangiata a metà. L'alpha no.
		if _tween_apertura and _tween_apertura.is_valid():
			_tween_apertura.kill()
		_apertura.modulate.a = 0.0
		_tween_apertura = _apertura.create_tween()
		_tween_apertura.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_tween_apertura.tween_property(_apertura, "modulate:a", 1.0, 0.18)


## Testata del tomo: il titolo col font da display e, a destra, quante magie
## contiene. Il conteggio è lì perché "quante ne so" è la prima domanda che si
## fa aprendo un grimorio.
func _testata() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	var riga := HBoxContainer.new()
	v.add_child(riga)

	var titolo : Label = MenuStyle.titolo(MenuStyle.spaziato("Grimorio"))
	titolo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	riga.add_child(titolo)

	var quante : String = "nessuna magia trascritta"
	if _voci.size() == 1:
		quante = "1 magia trascritta"
	elif _voci.size() > 1:
		quante = "%d magie trascritte" % _voci.size()
	var conto : Label = MenuStyle.testo(quante, MenuStyle.CORPO_ETICHETTA,
		MenuStyle.TESTO_FIOCO)
	conto.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	riga.add_child(conto)

	v.add_child(MenuStyle.separatore())
	return v


func _pagina_bianca() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", MenuStyle.pagina(34))
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)

	var t : Label = MenuStyle.testo("Le pagine sono ancora bianche.",
		MenuStyle.CORPO_VOCE, MenuStyle.TESTO_FIOCO)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	var r : RichTextLabel = MenuStyle.corpo_ricco(
		"[center][i]Un grimorio non nasce scritto: si riempie di ciò che si " +
		"impara, e ogni riga costa qualcosa a chi la traccia.[/i][/center]",
		640.0, MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(r)
	return box


## Facciata SINISTRA: l'immagine e i numeri. Le due cose che si guardano, non
## si leggono.
func _facciata_sinistra(voce : Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", MenuStyle.pagina())
	box.custom_minimum_size = Vector2(LARGHEZZA_MINIMA_PAGINA, ALTEZZA_MINIMA_PAGINA)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)

	v.add_child(_illustrazione(voce))
	v.add_child(MenuStyle.separatore())
	v.add_child(_scheda(voce))
	return box


## L'illustrazione, o il suo posto vuoto. Il posto vuoto è dichiarato e ha la
## stessa altezza dell'immagine: senza, le magie illustrate e quelle non
## illustrate avrebbero pagine di altezza diversa e il libro "respirerebbe" a
## ogni voltata.
func _illustrazione(voce : Dictionary) -> Control:
	var cornice := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_corner_radius_all(0)
	sb.border_color = MenuStyle.ORO_TENUE
	sb.set_border_width_all(1)
	cornice.add_theme_stylebox_override("panel", sb)
	cornice.custom_minimum_size = Vector2(0, ALTEZZA_ILLUSTRAZIONE)

	if voce.image is Texture2D:
		var tex := TextureRect.new()
		tex.texture = voce.image
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# CENTERED e non COVERED: la tavola si vede INTERA, incorniciata dal
		# fondo scuro, come una miniatura incollata sulla pagina. COVERED
		# riempiva la cornice ritagliando l'illustrazione, e su una facciata
		# larga la riduceva a una striscia — di un'illustrazione commissionata
		# restava visibile la fascia centrale e basta.
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(0, ALTEZZA_ILLUSTRAZIONE)
		cornice.add_child(tex)
	else:
		# Il sigillo grande al posto dell'illustrazione mancante: è comunque
		# l'identità visiva della magia, non un buco.
		var sigillo : Label = MenuStyle.testo(str(voce.icon), 96, MenuStyle.ORO_TENUE)
		sigillo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sigillo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cornice.add_child(sigillo)
	return cornice


## I numeri della magia, in righe etichetta/valore. Si mostrano SOLO le voci che
## dicono qualcosa: stampare "Danno 0" su Morsa del Gelo — che di proposito non
## ferisce — farebbe leggere come rotta una magia che è progettata così.
func _scheda(voce : Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)

	v.add_child(MenuStyle.testo(MenuStyle.spaziato("Il prezzo e la misura"),
		MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO))

	v.add_child(_riga_dato("Arcanium Vivo", "%d" % roundi(voce.cost)))
	v.add_child(_riga_dato("Riposo", "%.1f s" % voce.cooldown))

	if voce.damage > 0:
		var tipo : String = TIPI_DANNO.get(voce.damage_type, String(voce.damage_type).to_lower())
		v.add_child(_riga_dato("Danno", "%d  %s" % [voce.damage, tipo]))
	if voce.frozen_buildup > 0.0:
		v.add_child(_riga_dato("Congelamento", "%d per colpo" % roundi(voce.frozen_buildup)))
	if voce.is_positional:
		v.add_child(_riga_dato("Campo", "%.0f m di raggio, %.0f s" % [voce.aoe_radius, voce.aoe_duration]))
	return v


func _riga_dato(etichetta : String, valore : String) -> Control:
	var riga := HBoxContainer.new()
	var e : Label = MenuStyle.testo(etichetta, MenuStyle.CORPO_ETICHETTA,
		MenuStyle.TESTO_FIOCO)
	e.custom_minimum_size = Vector2(150, 0)
	riga.add_child(e)
	riga.add_child(MenuStyle.testo(valore, MenuStyle.CORPO_ETICHETTA))
	return riga


## Facciata DESTRA: il nome e il testo. Le due cose che si leggono.
func _facciata_destra(voce : Dictionary, animata : bool) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", MenuStyle.pagina())
	box.custom_minimum_size = Vector2(LARGHEZZA_MINIMA_PAGINA, ALTEZZA_MINIMA_PAGINA)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)

	# Riga del titolo: il sigillo, il nome, e a destra la natura della magia.
	var testata := HBoxContainer.new()
	testata.add_theme_constant_override("separation", 10)
	v.add_child(testata)

	var sigillo : Label = MenuStyle.testo(str(voce.icon), 30, MenuStyle.ORO)
	testata.add_child(sigillo)

	var nome : Label = MenuStyle.titolo(String(voce.name), 26, MenuStyle.TESTO)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	testata.add_child(nome)

	var natura : Label = MenuStyle.testo(MenuStyle.spaziato(_natura(voce)),
		MenuStyle.CORPO_ETICHETTA, MenuStyle.TESTO_FIOCO)
	natura.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	testata.add_child(natura)

	v.add_child(MenuStyle.separatore())

	var lore : String = String(voce.lore)
	if lore.strip_edges() == "":
		lore = "[i]Nessuna glossa accompagna questa pagina.[/i]"
	# La larghezza passata è un PAVIMENTO, non la misura finale: dentro una
	# facciata EXPAND_FILL il RichTextLabel riceve la larghezza vera e manda a
	# capo su quella. Il pavimento esiste solo perché una larghezza zero
	# manderebbe a capo ogni singolo carattere.
	var r : RichTextLabel = MenuStyle.corpo_ricco(lore,
		LARGHEZZA_MINIMA_PAGINA - 60.0, MenuStyle.CORPO_VOCE)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(r)

	if animata:
		MenuStyle.svela(r, 0.45)
	return box


## Che cosa è, in due parole. Serve a distinguere a colpo d'occhio le magie
## che si lanciano in modi diversi.
func _natura(voce : Dictionary) -> String:
	if voce.is_positional:
		return "Campo"
	return "Proiettile"


## Piede: a che punto del tomo siamo e come si gira pagina. I trattini sono un
## indice compatto — con dieci magie una fila di dieci segni si legge a colpo
## d'occhio, "pagina 3 di 10" no.
func _piede_pagina() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(MenuStyle.separatore())

	var segni := ""
	for i in _voci.size():
		segni += "—" if i == _pagina else "·"
		if i < _voci.size() - 1:
			segni += " "
	var indice : Label = MenuStyle.testo(segni, MenuStyle.CORPO_VOCE, MenuStyle.ORO)
	indice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(indice)

	_piede = MenuStyle.testo(
		MenuStyle.spaziato("← → sfoglia     %d di %d" % [_pagina + 1, _voci.size()]),
		MenuStyle.CORPO_AIUTO, MenuStyle.TESTO_FIOCO)
	_piede.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_piede)
	return v


## ─── Caricamento ────────────────────────────────────────────────────────────

## Ordine di lettura: alfabetico.
func _carica_voci() -> Array:
	var incantesimi := _carica_cartella(SPELLS_DIR)
	incantesimi.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return incantesimi


func _carica_cartella(percorso : String) -> Array:
	var out : Array = []
	var dir := DirAccess.open(percorso)
	if dir == null:
		return out   ## cartella non ancora creata: pagine in meno, nessun errore
	dir.list_dir_begin()
	var nome := dir.get_next()
	while nome != "":
		if not dir.current_is_dir() and nome.get_extension() == "tres":
			var res := load(percorso + nome)
			if res != null and _e_conosciuta(res):
				out.append(_descrivi(res, nome))
		nome = dir.get_next()
	dir.list_dir_end()
	return out


## Una magia entra nel grimorio solo se il giocatore l'ha davvero appresa. Il
## criterio: `unlock_flag` vuoto = sempre nota, altrimenti serve il flag in
## PlayerFlags. Senza questo controllo il grimorio spoilererebbe le magie che si
## trovano piu' avanti.
func _e_conosciuta(res : Resource) -> bool:
	var gate : String = String(res.get("unlock_flag")) if ("unlock_flag" in res) else ""
	if gate == "":
		return true
	var flags := get_node_or_null("/root/PlayerFlags")
	return flags == null or flags.has(gate)


func _descrivi(res : Resource, nome_file : String) -> Dictionary:
	var nome := String(res.get("name")) if ("name" in res) else ""
	if nome.strip_edges() == "":
		nome = nome_file.get_basename().capitalize()

	return {
		"name": nome,
		"icon": res.get("icon") if ("icon" in res) else "◈",
		"image": res.get("image") if ("image" in res) else null,
		"lore": String(res.get("lore")) if ("lore" in res) else "",
		"cost": float(res.get("cost")) if ("cost" in res) else 0.0,
		"cooldown": float(res.get("cooldown")) if ("cooldown" in res) else 0.0,
		"damage": int(res.get("damage")) if ("damage" in res) else 0,
		"damage_type": String(res.get("damage_type")) if ("damage_type" in res) else "FISICO",
		"frozen_buildup": float(res.get("frozen_buildup")) if ("frozen_buildup" in res) else 0.0,
		"is_positional": bool(res.get("is_positional")) if ("is_positional" in res) else false,
		"aoe_radius": float(res.get("aoe_radius")) if ("aoe_radius" in res) else 0.0,
		"aoe_duration": float(res.get("aoe_duration")) if ("aoe_duration" in res) else 0.0,
	}
