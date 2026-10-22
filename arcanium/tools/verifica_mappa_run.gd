extends SceneTree

## Cancello della RUN SULLA MAPPA (torneo.gd + mappa_schermo + dungeon):
##   1. all'inizio si sceglie solo fra i nodi del primo piano, e un nodo non
##      raggiungibile non si puo' scegliere;
##   2. una run intera, prendendo sempre il primo nodo aperto, attraversa le 4
##      regioni (dal boss si passa alla regione dopo) e battuto l'ultimo boss
##      e' vinta, con 4 x 7 nodi fatti;
##   3. la schermata mostra la regione in corso: un medaglione per nodo, e
##      accesi solo i raggiungibili;
##   4. dentro un nodo di combattimento il dungeon usa il seme del nodo;
##   5. vinto lo scontro, «Avanti» chiude il nodo e la mappa apre i successivi;
##   6. la rivincita resta sullo stesso nodo.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_mappa_run.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 6

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	var torneo : Node = root.get_node("Torneo")

	## 1.
	torneo.inizia(11)
	var primi : Array = torneo.regione(0)["piani"][0]
	var aperti : Array = torneo.raggiungibili()
	var fuori : String = torneo.regione(0)["piani"][2][0]
	_ok(aperti == primi and not torneo.scegli(fuori), "all'inizio solo il primo piano %s, e '%s' non si sceglie" % [str(aperti), fuori])

	## 2.
	var passi := 0
	var regioni_viste := {}
	while not torneo.vinta and passi < 100:
		var a : Array = torneo.raggiungibili()
		if a.is_empty():
			break
		torneo.scegli(a[0])
		regioni_viste[int(torneo.nodo_in_corso()["regione"])] = true
		torneo.completa()
		passi += 1
	_ok(torneo.vinta and torneo.completati.size() == 4 * 7 and regioni_viste.size() == 4,
			"una run intera: vinta=%s, %d nodi, %d regioni" % [torneo.vinta, torneo.completati.size(), regioni_viste.size()])

	## 3.
	torneo.inizia(11)
	torneo.scegli(torneo.raggiungibili()[0])
	torneo.completa()
	var m : Node = load("res://arcanium/ui/mappa/mappa_schermo.tscn").instantiate()
	root.add_child(m)
	for k in 3:
		await process_frame
	var reg : Dictionary = torneo.regione(0)
	var accesi : Array = []
	for id in m._bottoni:
		if not (m._bottoni[id] as Button).disabled:
			accesi.append(id)
	accesi.sort()
	var attesi : Array = torneo.raggiungibili()
	attesi.sort()
	_ok(m._bottoni.size() == (reg["nodi"] as Dictionary).size() and accesi == attesi,
			"la mappa: %d medaglioni su %d nodi, accesi %s" % [m._bottoni.size(), (reg["nodi"] as Dictionary).size(), str(accesi)])
	root.remove_child(m)
	m.free()

	## 4.
	var id_scontro : String = torneo.raggiungibili()[0]
	for id in torneo.raggiungibili():
		if torneo.nodo(id)["tipo"] == "scontro":
			id_scontro = id
	torneo.scegli(id_scontro)
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	var du : Node = scena.get_node("Dungeon")
	du.obiettivo = 0
	root.add_child(scena)
	for k in 5:
		await process_frame
	_ok(du._seme_usato == int(torneo.nodo(id_scontro)["seme"]), "il dungeon usa il seme del nodo (%d)" % du._seme_usato)

	## 6. (prima del 5: la rivincita non chiude il nodo)
	du._su_scelta("riprova")
	await process_frame
	_ok(torneo.nodo_corrente == id_scontro and not id_scontro in torneo.completati,
			"la rivincita resta sul nodo %s" % torneo.nodo_corrente)

	## 5.
	du._su_scelta("prossimo")
	await process_frame
	var dopo : Array = torneo.raggiungibili()
	_ok(torneo.nodo_corrente == "" and torneo.completati[-1] == id_scontro
			and dopo == torneo.nodo(id_scontro)["prossimi"],
			"«Avanti» chiude il nodo e apre %s" % str(dopo))
	root.remove_child(scena)
	scena.free()

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
