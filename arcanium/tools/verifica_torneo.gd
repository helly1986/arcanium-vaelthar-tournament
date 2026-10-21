extends SceneTree

## Cancello del TORNEO (arcanium/systems/torneo.gd): il limite di sconfitte e
## l'Arcanium alla souls, legati alla schermata di fine scontro, alla Pietra
## del Varco e ai perk della rivincita.
##
## Una run intera sul dungeon vero (dungeon_prova.tscn, seme 0, «elimina
## tutti»), con le sconfitte provocate dai segnali veri (morte del giocatore,
## caduta nel baratro) e le vittorie da `ripulito`:
##   1. il primo dungeon apre la run e azzera l'Arcanium che c'era;
##   2. morte: tutto il saldo in palio (non la meta' di PlayerCombatLink),
##      «Sconfitte 1 / 3» e la riga dell'Arcanium sulla schermata;
##   3. «Riprova» col perk: stesso seme, «in palio» nell'indicatore;
##   4. rivincita vinta: il mucchio torna intero, piu' la taglia, «recuperato»;
##   5. caduta e Pietra del Varco: il mucchio torna subito, la sconfitta resta;
##   6. la vita in piu' alza il tetto a 4;
##   7. rivincita persa: il mucchio di prima sparisce, in palio il nuovo saldo;
##      ed e' la quarta sconfitta su quattro: ELIMINATO, solo «Torna al menu»,
##      senza perk;
##   8. «Torna al menu» chiude la run; fuori dal torneo la morte torna al 50%;
##   9. un dungeon nuovo apre una run nuova; «Abbandona» la chiude.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_torneo.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 16

var _fatti := 0
var _falliti := 0
var du : Node
var pl : Node
var torneo : Node
var banca : Node


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	torneo = root.get_node("Torneo")
	banca = root.get_node("CrystalBank")
	var inv : Node = root.get_node("ArcaniumInventory")
	banca.crystals = 120
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	du = scena.get_node("Dungeon")
	du.seme = 0
	du.obiettivo = 0
	root.add_child(scena)
	await process_frame
	pl = scena.get_node("Player")
	var seme : int = du.pianta.seme

	## 1.
	_ok(torneo.in_corso and torneo.sconfitte == 0 and banca.crystals == 0,
			"il primo dungeon apre la run e azzera l'Arcanium (in corso %s, banca %d)" % [torneo.in_corso, banca.crystals])

	## 2. Morte con 100 in tasca.
	banca.add(100)
	pl.death_started.emit()
	var s : Node = await _schermo()
	var testi := _testi(s)
	_ok(banca.crystals == 0 and torneo.in_palio == 100 and torneo.sconfitte == 1,
			"morte: tutto il saldo in palio, una sconfitta (banca %d, in palio %d, sconfitte %d)" % [banca.crystals, torneo.in_palio, torneo.sconfitte])
	_ok(s != null and "DEFEATS" in testi and "1 / 3" in testi and _riga(s).contains("100 Arcanium at stake")
			and _pulsanti(s) == ["Retry", "Forfeit"],
			"la schermata dice «Sconfitte 1 / 3» e «%s», con «Riprova»/«Abbandona»" % _riga(s))

	## 3. «Riprova» col primo perk.
	await _scegli(s, "riprova", true)
	_ok(du.pianta.seme == seme and du.perk_attivo != "" and du._contatore.text.contains("◆ 100 at stake"),
			"«Riprova»: stesso seme, perk %s, indicatore «%s»" % [du.perk_attivo, du._contatore.text])

	## 4. Rivincita vinta con 30 di taglia.
	banca.add(30)
	du.ripulito.emit()
	s = await _schermo()
	_ok(banca.crystals == 130 and torneo.in_palio == 0 and _riga(s).contains("100 Arcanium recovered"),
			"rivincita vinta: il mucchio torna intero piu' la taglia (banca %d), «%s»" % [banca.crystals, _riga(s)])
	await _scegli(s, "prossimo")
	_ok(not du._contatore.text.contains("at stake") and du.perk_attivo == "",
			"dopo la vittoria niente piu' perk ne' «in palio» (%s)" % du._contatore.text)

	## 5. Caduta con 40 (si spendono 90: il gia' speso non si perde), poi la Pietra.
	banca.spend(90)
	du.forziere_aperto.emit(true)
	du.caduto.emit()
	s = await _schermo()
	_ok(torneo.in_palio == 40 and torneo.sconfitte == 2 and "2 / 3" in _testi(s),
			"caduta: anche il baratro conta (in palio %d, sconfitte %d)" % [torneo.in_palio, torneo.sconfitte])
	var nota_pietra := false
	for t in _testi(s):
		nota_pietra = nota_pietra or String(t).contains("recover your Arcanium")
	await _scegli(s, "varco", true)
	_ok(nota_pietra and not inv.has_item("pietra_del_varco") and banca.crystals == 40 and torneo.in_palio == 0
			and torneo.sconfitte == 2 and du.perk_attivo != "",
			"Pietra del Varco: spesa, l'Arcanium torna subito (banca %d), la sconfitta resta (%d), il perk pure" % [banca.crystals, torneo.sconfitte])

	## 6. La vita in piu'.
	torneo.concedi_vita()
	banca.spend(30)
	du.caduto.emit()
	s = await _schermo()
	_ok(torneo.sconfitte_max() == 4 and not s.eliminato and "3 / 4" in _testi(s) and _pulsanti(s)[0] == "Retry",
			"la vita in piu': la terza sconfitta non elimina (3 / 4, %s)" % str(_pulsanti(s)))
	await _scegli(s, "riprova", true)

	## 7. Rivincita persa con 5 guadagnati: la quarta sconfitta su quattro.
	banca.add(5)
	du.caduto.emit()
	s = await _schermo()
	var righe := _righe(s)
	_ok(banca.crystals == 0 and torneo.in_palio == 5 and torneo.eliminato(),
			"rivincita persa: i 10 di prima spariscono, in palio i 5 nuovi (in palio %d)" % torneo.in_palio)
	_ok(righe.size() == 2 and righe[0].contains("10 Arcanium") and righe[0].contains("lost forever")
			and righe[1].contains("5 Arcanium lost with the tournament"),
			"la schermata dice cosa e' perso per sempre (%s)" % str(righe))
	_ok(s.eliminato and _pulsanti(s) == ["Back to menu"] and s._perk_offerti.is_empty(),
			"ELIMINATO: solo «Torna al menu», nessun perk (%s)" % str(_pulsanti(s)))

	## 8. Fine della run.
	var finita := [false]
	du.abbandonato.connect(func(): finita[0] = true, CONNECT_ONE_SHOT)
	await _scegli(s, "eliminato")
	_ok(not torneo.in_corso and banca.crystals == 0 and torneo.in_palio == 0 and finita[0] and not paused,
			"«Torna al menu» chiude la run e azzera l'Arcanium")
	banca.add(10)
	pl.death_started.emit()
	_ok(banca.crystals == 5, "fuori dal torneo la morte toglie ancora la meta' (banca %d)" % banca.crystals)

	## 9. Una run nuova, e «Abbandona».
	du.costruisci()
	await process_frame
	_ok(torneo.in_corso and torneo.sconfitte == 0 and torneo.sconfitte_max() == 3 and banca.crystals == 0,
			"un dungeon nuovo apre una run nuova (sconfitte %d/%d)" % [torneo.sconfitte, torneo.sconfitte_max()])
	banca.add(50)
	du.caduto.emit()
	s = await _schermo()
	await _scegli(s, "abbandona")
	_ok(not torneo.in_corso and banca.crystals == 0 and torneo.in_palio == 0,
			"«Abbandona» chiude la run e l'Arcanium in palio si perde")

	paused = false
	scena.queue_free()
	await process_frame
	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)


## La schermata di fine scontro, appena compare (la morte aspetta 1,8 s).
func _schermo() -> Node:
	for k in 1200:
		var s : Node = du.find_child("FineScontro", false, false)
		if s != null:
			await process_frame
			return s
		await process_frame
	return null


## Una scelta; con `perk` si prende anche la prima carta.
func _scegli(s : Node, azione : String, perk : bool = false) -> void:
	if s == null:
		return
	s._scegli(azione)
	await process_frame
	if perk:
		s._pulsanti[0].pressed.emit()
	await process_frame


func _testi(s : Node) -> Array:
	if s == null:
		return []
	return s.find_children("*", "Label", true, false).map(func(l): return l.text)


func _righe(s : Node) -> Array:
	if s == null:
		return []
	return s.find_children("RigaArcanium*", "Label", true, false).map(func(l): return l.text)


func _riga(s : Node) -> String:
	return " | ".join(_righe(s))


func _pulsanti(s : Node) -> Array:
	if s == null:
		return []
	return s._pulsanti.map(func(b): return b.text)
