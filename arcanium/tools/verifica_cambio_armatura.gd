extends SceneTree

## ⛔ CANCELLO: si regge un cambio d'armatura IN CORSA?
##
## Cambiare pezzo a runtime non e' "mostra un'altra mesh": `ArmaturaIndossata`
## deve staccare dallo scheletro le piastre vecchie e appenderci le nuove. Le
## cose che possono andare storte sono tre, e nessuna si vede a occhio subito:
##
##   1. **residui** — il pezzo vecchio resta appeso e i due si compenetrano;
##   2. **perdita** — a ogni cambio i figli dello scheletro crescono, e dopo
##      dieci cambi ci sono dieci corazze sovrapposte a mangiare frame;
##   3. **il corpo sparisce** — `_spoglia()` cancella anche cio' che non ha
##      messo lei, e ci si ritrova senza mesh del personaggio.
##
##     godot --headless --script res://arcanium/tools/verifica_cambio_armatura.gd

const CORPO := "res://assets/characters/base_body/protagonista_v4.glb"
const CORAZZA := "res://arcanium/resources/equipment/corazza_prima_veglia.tres"
const MANTO := "res://arcanium/resources/equipment/manto_branco_guasto.tres"
const GAMBALI := "res://arcanium/resources/equipment/gambali_prima_veglia.tres"

var guasti := 0
var _fatto := false


func _sia(condizione: bool, cosa: String) -> void:
	if condizione:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


## ⚠️ `pezzi_fissi` e' un `Array[Resource]` TIPIZZATO: passargli un `Array`
## normale fallisce con "Invalid assignment", e siccome l'assegnazione e' anche
## il trigger della vestizione non succede niente e sembra che il sistema non
## reagisca.
func _kit(percorsi : Array) -> Array[Resource]:
	var fuori : Array[Resource] = []
	for p in percorsi:
		fuori.append(load(p))
	return fuori


## I nomi delle piastre appese da noi, e quante altre mesh ci sono sotto lo
## scheletro (il corpo, che NON si deve toccare).
func _stato(sk : Skeleton3D) -> Dictionary:
	var mie : Array = []
	var altre : Array = []
	for c in sk.get_children():
		if c is MeshInstance3D:
			if c.has_meta("armatura_indossata"):
				mie.append(str(c.name))
			else:
				altre.append(str(c.name))
	mie.sort()
	return {"mie": mie, "altre": altre}


func _process(_dt : float) -> bool:
	if _fatto:
		return true
	_fatto = true

	var scena := Node.new()
	scena.name = "Banco"
	root.add_child(scena)
	current_scene = scena

	var corpo = load(CORPO).instantiate()
	scena.add_child(corpo)
	var scheletri : Array = corpo.find_children("*", "Skeleton3D", true, false)
	_sia(scheletri.size() == 1, "il corpo ha uno scheletro")
	if scheletri.is_empty():
		quit(1)
		return true
	var sk : Skeleton3D = scheletri[0]
	var mesh_del_corpo : int = _stato(sk)["altre"].size()
	print("  mesh del corpo sotto lo scheletro: %d" % mesh_del_corpo)

	var Indossata = load("res://arcanium/systems/armatura_indossata.gd")
	var vestizione = Indossata.new()
	vestizione.skeleton = sk
	scena.add_child(vestizione)

	print()
	print("=== si indossa la corazza ===")
	vestizione.pezzi_fissi = _kit([CORAZZA, GAMBALI])
	var s1 := _stato(sk)
	print("  appese: %s" % str(s1["mie"]))
	_sia(s1["mie"].has("PV_Corazza"), "la corazza e' addosso")
	_sia(s1["mie"].size() == 3, "tre piastre appese (corazza + due gambali), non %d"
		% s1["mie"].size())

	print()
	print("=== CAMBIO IN CORSA: la corazza diventa il manto ===")
	vestizione.pezzi_fissi = _kit([MANTO, GAMBALI])
	var s2 := _stato(sk)
	print("  appese: %s" % str(s2["mie"]))
	_sia(s2["mie"].has("PV_Manto"), "il manto e' addosso")
	_sia(not s2["mie"].has("PV_Corazza"),
		"la corazza NON e' rimasta appesa (il residuo e' il difetto tipico)")
	_sia(s2["mie"].size() == 3, "sempre tre piastre, non %d" % s2["mie"].size())
	_sia(_stato(sk)["altre"].size() == mesh_del_corpo,
		"il corpo e' ancora li' (%d mesh)" % _stato(sk)["altre"].size())

	print()
	print("=== e si torna indietro ===")
	vestizione.pezzi_fissi = _kit([CORAZZA, GAMBALI])
	var s3 := _stato(sk)
	_sia(s3["mie"].has("PV_Corazza") and not s3["mie"].has("PV_Manto"),
		"si torna alla corazza senza portarsi dietro il manto")

	print()
	print("=== dieci cambi di fila: si accumula qualcosa? ===")
	for i in 10:
		vestizione.pezzi_fissi = _kit([MANTO if i % 2 == 0 else CORAZZA, GAMBALI])
	var s4 := _stato(sk)
	print("  dopo dieci cambi: %s" % str(s4["mie"]))
	_sia(s4["mie"].size() == 3,
		"ancora tre piastre dopo dieci cambi, non %d (se cresce, perde)" % s4["mie"].size())
	_sia(_stato(sk)["altre"].size() == mesh_del_corpo, "e il corpo non e' stato toccato")

	print()
	print("=== svuotare i pezzi fissi ridA' il comando al loadout ===")
	## ⚠️ Svuotare `pezzi_fissi` NON spoglia: e' il banco che si toglie di mezzo
	## e lascia decidere `EquipmentLoadout`. Me l'aspettavo nudo e mi sono
	## trovato cinque piastre — che e' il KIT INIZIALE, cioe' il comportamento
	## giusto. Gli autoload ci sono anche in un `--headless --script`.
	vestizione.pezzi_fissi = _kit([])
	var s5 := _stato(sk)
	print("  appese: %s" % str(s5["mie"]))
	var lo = root.get_node_or_null("EquipmentLoadout")
	_sia(lo != null, "l'autoload EquipmentLoadout c'e', quindi il ripiego ha di che pescare")
	## ⚠️ NON si controlla "torna la corazza": il loadout riflette il
	## SALVATAGGIO, e questo cancello girerebbe verde o rosso a seconda di cosa
	## il giocatore ha addosso — che e' l'ultima cosa che un collaudo deve fare.
	## (Successo davvero: qui `armatura_alta` era il manto, perche' era stato
	## equipaggiato in gioco poco prima.) Si controlla invece che cio' che sta
	## addosso sia ESATTAMENTE cio' che il loadout dichiara.
	var attese : Array = []
	if lo != null:
		for slot in vestizione.slots:
			var res = lo.equipped_in(slot)
			if res != null and "worn_pieces" in res:
				for nome in res.worn_pieces:
					attese.append(str(nome))
	attese.sort()
	print("  il loadout dichiara: %s" % str(attese))
	_sia(s5["mie"] == attese,
		"addosso c'e' esattamente cio' che il loadout dichiara")
	_sia(_stato(sk)["altre"].size() == mesh_del_corpo, "e il corpo c'e' ancora")

	print()
	if guasti == 0:
		print("TUTTO A POSTO: il cambio d'armatura in corsa regge.")
	else:
		print("%d CONTROLLI FALLITI" % guasti)
	quit(1 if guasti > 0 else 0)
	return true
