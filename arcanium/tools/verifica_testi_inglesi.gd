extends SceneTree

## Cancello della UI IN INGLESE (decisione dell'autore del 2026-10-21: tutto
## cio' che il giocatore legge e' in inglese).
##
## Apre davvero le schermate, raccoglie ogni testo VISIBILE (Label, Button,
## RichTextLabel, OptionButton, finestre di dialogo) e cerca l'italiano: parole
## italiane frequenti o lettere accentate.
##
## I testi che vengono dai DATI (nomi e lore di oggetti, incantesimi, nemici
## nelle risorse) si traducono al passo 6 del piano della UI: qui si tolgono dal
## testo prima del controllo e si contano a parte, cosi' non fanno fallire ma
## non spariscono dal conto.
##
## Schermate: menu principale e sua finestra di conferma; impostazioni (ogni
## scheda); selezione del campione (tutti e sei); mappa della run con la scheda
## di un nodo; dungeon con HUD e indicatore; fine
## scontro (sconfitta, carte dei perk, vittoria, eliminazione); menu di gioco
## (ogni sezione) e modale d'equipaggiamento; announcer; caricamento.
## In piu' controlla che i due font del tema siano Cinzel e EB Garamond.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_testi_inglesi.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 11
const MarcheStats := preload("res://arcanium/resources/marche_stats.gd")

## Parole che in un testo inglese non compaiono. Corte e frequenti: e' cio' che
## resta in una frase tradotta a meta'.
const PAROLE_ITALIANE := [
	"il", "lo", "gli", "di", "del", "della", "dei", "delle", "che", "per",
	"non", "con", "una", "uno", "sei", "hai", "nel", "nella", "alla", "allo",
	"dal", "dalla", "sono", "questo", "questa", "ancora", "nessuno", "nessuna",
	"vita", "danno", "tempo", "scegli", "torna", "gioco", "partita", "oggetti",
	"armi", "invio", "esci", "annulla", "conferma", "indietro", "inizia",
	"nemici", "sconfitta", "vittoria", "rimasti", "forzieri", "uscita",
	"impostazioni", "comandi", "risoluzione", "finestra", "riposo", "campo",
	"pagine", "magie", "tecniche", "casata", "marche", "genere", "arrivo",
]
const ACCENTI := "àèéìòùÀÈÉÌÒÙ"

var _fatti := 0
var _falliti := 0
var _dati : Array[String] = []
var _dai_dati := {}
var du : Node


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	_raccogli_dati()

	## 0. I font del tema.
	var ui : Font = load("res://arcanium/ui/theme/serif_ui.tres")
	var titolo : Font = load("res://arcanium/ui/theme/serif_display.tres")
	_ok(ui is FontVariation and titolo is FontVariation
			and String(ui.base_font.resource_path).contains("EBGaramond")
			and String(titolo.base_font.resource_path).contains("Cinzel")
			and ui.get_font_name() != "" and titolo.get_font_name() != "",
			"i font del tema sono EB Garamond (%s) e Cinzel (%s)" % [ui.get_font_name(), titolo.get_font_name()])

	## 1. Menu principale, con la conferma di partita nuova.
	var mm : Node = load("res://arcanium/ui/main_menu/main_menu.tscn").instantiate()
	root.add_child(mm)
	await _frame(3)
	var testi := _visibili(mm)
	for d in mm.find_children("*", "AcceptDialog", true, false):
		testi.append(d.title)
		testi.append(d.dialog_text)
	_controlla("menu principale", testi)
	mm.queue_free()
	await _frame(2)

	## 2. Impostazioni, ogni scheda.
	var sm : Node = load("res://arcanium/ui/settings_menu/settings_menu.tscn").instantiate()
	root.add_child(sm)
	await _frame(2)
	var tutte : Array = []
	for tab in sm.TABS:
		sm._select_tab(tab)
		await _frame(2)
		tutte.append_array(_visibili(sm))
	tutte.append(sm._testo_conferma(1))
	tutte.append(sm._testo_conferma(5))
	_controlla("impostazioni (%d schede)" % sm.TABS.size(), tutte)
	sm.queue_free()
	await _frame(2)

	## 3. La selezione del campione, tutti e sei.
	var cc : Node = load("res://arcanium/ui/selezione_campione/selezione_campione.tscn").instantiate()
	root.add_child(cc)
	await _frame(3)
	var sel : Array = []
	for i in cc.campioni.size():
		cc._scegli(i)
		await _frame(1)
		sel.append_array(_visibili(cc))
	_controlla("selezione del campione (%d campioni)" % cc.campioni.size(), sel)
	cc.queue_free()
	await _frame(2)

	## 3-bis. La mappa della run, con la scheda di un nodo aperta.
	var torneo_m : Node = root.get_node("Torneo")
	torneo_m.inizia(3)
	var mp : Node = load("res://arcanium/ui/mappa/mappa_schermo.tscn").instantiate()
	root.add_child(mp)
	await _frame(3)
	var testi_mappa := _visibili(mp)
	mp._su_nodo(torneo_m.raggiungibili()[0])
	await _frame(2)
	testi_mappa.append_array(_visibili(mp))
	_controlla("mappa della run e scheda del nodo", testi_mappa)
	mp.queue_free()
	torneo_m.termina()
	await _frame(2)

	## 4. Dungeon con HUD, e le schermate di fine scontro.
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	du = scena.get_node("Dungeon")
	du.seme = 0
	du.obiettivo = 0
	root.add_child(scena)
	await _frame(5)
	_controlla("dungeon: HUD e indicatore", _visibili(root))
	var banca : Node = root.get_node("CrystalBank")
	banca.add(50)
	du.forziere_aperto.emit(true)
	du.caduto.emit()
	var s : Node = await _schermo()
	var fine : Array = _visibili(s)
	s._scegli("riprova")
	await _frame(2)
	fine.append_array(_visibili(s))
	s._pulsanti[0].pressed.emit()
	await _frame(3)
	fine.append(du._contatore.text)
	banca.add(10)
	du.ripulito.emit()
	s = await _schermo()
	fine.append_array(_visibili(s))
	s._scegli("prossimo")
	await _frame(2)
	var torneo : Node = root.get_node("Torneo")
	torneo.sconfitte = torneo.sconfitte_max() - 1
	du.caduto.emit()
	s = await _schermo()
	fine.append_array(_visibili(s))
	_ok(s != null and s.eliminato, "si arriva alla schermata di eliminazione")
	_controlla("fine scontro: sconfitta, perk, vittoria, eliminazione", fine)
	s._scegli("eliminato")
	await _frame(2)

	## 5. Il menu di gioco, ogni sezione, e la modale d'equipaggiamento.
	var gm : Node = root.get_node("GameMenu")
	var menu : Array = []
	for sez in gm.SECTIONS:
		gm.open_at(sez)
		await _frame(2)
		menu.append_array(_visibili(gm))
	gm.open_at("inventory")
	await _frame(2)
	gm._apri_modale_equip("talismano_1")
	await _frame(2)
	if gm._equip_modal != null:
		menu.append_array(_visibili(gm._equip_modal))
	_controlla("menu di gioco (%d sezioni) e modale" % gm.SECTIONS.size(), menu)
	gm._set_open(false)

	## 6. Announcer e caricamento.
	var an : Node = root.get_node("Announcer")
	an.item_acquired("Riftstone", "◈")
	await _frame(2)
	var annunci := _visibili(an)
	an.legend_defeated()
	await _frame(2)
	annunci.append_array(_visibili(an))
	_controlla("announcer", annunci)
	var ls : Node = load("res://arcanium/ui/loading_screen/loading_screen.tscn").instantiate()
	root.add_child(ls)
	await _frame(2)
	_controlla("schermata di caricamento", _visibili(ls))
	ls.queue_free()

	print("--   testi presi dai dati, da tradurre al passo 6: %d" % _dai_dati.size())
	for k in _dai_dati.keys().slice(0, 12):
		print("       · %s" % k)
	paused = false
	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)


## Un controllo per schermata: elenca le frasi che sembrano italiane.
func _controlla(dove : String, testi : Array) -> void:
	var cattivi : Array = []
	var visti := 0
	for t in testi:
		var pulito := _senza_dati(String(t))
		if pulito.strip_edges() == "":
			continue
		visti += 1
		if _italiano(pulito):
			cattivi.append(pulito.strip_edges().replace("\n", " ").left(90))
	_ok(visti > 0 and cattivi.is_empty(), "%s in inglese (%d testi%s)" % [dove, visti,
			"" if cattivi.is_empty() else ": " + " | ".join(cattivi.slice(0, 8))])


func _italiano(t : String) -> bool:
	## Le sigle delle Marche sono inglesi anche quando coincidono con una
	## parola italiana ("PER", Perseverance): si tolgono prima di cercare.
	for sigla in MarcheStats.SIGLE_MOSTRATE:
		t = RegEx.create_from_string("\\b" + sigla + "\\b").sub(t, " ", true)
	for c in ACCENTI:
		if t.contains(c):
			return true
	var minuscolo := t.to_lower()
	var parole := RegEx.create_from_string("[a-z']+").search_all(minuscolo)
	for m in parole:
		var w := m.get_string().replace("'", "")
		if w in PAROLE_ITALIANE:
			return true
	return false


## I testi dei dati (nomi e lore nelle risorse) si tolgono e si contano.
func _senza_dati(t : String) -> String:
	var out := t
	for d in _dati:
		if out.contains(d):
			out = out.replace(d, " ")
			_dai_dati[d.left(60)] = true
	return out


func _raccogli_dati() -> void:
	var visti := {}
	for dir in ["res://arcanium/resources/", "res://arcanium/characters/"]:
		_scorri(dir, visti)
	_dati.assign(visti.keys())
	## I piu' lunghi prima: "Manto del Branco Guasto" prima di "Manto".
	_dati.sort_custom(func(a, b): return a.length() > b.length())


func _scorri(dir : String, visti : Dictionary) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_scorri(dir + sub + "/", visti)
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"):
			continue
		var testo := FileAccess.get_file_as_string(dir + f)
		for campo in ["item_name", "name", "lore", "description", "display_name", "nome"]:
			var re := RegEx.create_from_string('(?m)^' + campo + ' = "((?:[^"\\\\]|\\\\.)*)"')
			for m in re.search_all(testo):
				var v := m.get_string(1).c_unescape()
				if v.length() >= 3:
					visti[v] = true


## Ogni testo visibile sotto `n`.
func _visibili(n : Node) -> Array:
	var out : Array = []
	if n == null:
		return out
	for c in n.find_children("*", "", true, false):
		if c is CanvasItem and not (c as CanvasItem).is_visible_in_tree():
			continue
		if c is OptionButton:
			for i in (c as OptionButton).item_count:
				out.append((c as OptionButton).get_item_text(i))
		elif c is Label or c is Button:
			out.append(c.text)
		elif c is RichTextLabel:
			out.append((c as RichTextLabel).get_parsed_text())
	return out


func _schermo() -> Node:
	for k in 1200:
		var s : Node = du.find_child("FineScontro", false, false)
		if s != null:
			await process_frame
			return s
		await process_frame
	return null


func _frame(n : int) -> void:
	for k in n:
		await process_frame
