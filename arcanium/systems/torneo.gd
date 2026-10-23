extends Node

## Lo stato della RUN del torneo (design-crogiolo, decisioni dell'autore del
## 2026-10-19 e del 2026-10-21). Autoload "Torneo": sopravvive al ricaricamento
## della scena fra un match e la sua rivincita.
##
## Le sconfitte: al massimo tre in tutta la run, alla terza si e' eliminati.
## Il tetto si alza con `concedi_vita` (l'oggetto della vita in piu', da
## trovare o comprare dai mercanti; la Pietra del Varco no).
##
## L'Arcanium, alla souls: chi perde perde tutto il saldo non speso, che resta
## IN PALIO. Lo riprende intero vincendo la rivincita, o spezzando la Pietra
## del Varco; se perde anche la rivincita quel mucchio sparisce per sempre, e
## in palio resta il nuovo saldo. I potenziamenti gia' comprati non si toccano.
##
## La run comincia alla prima costruzione di un dungeon senza run in corso
## (costruttore_dungeon.gd) e finisce con «Abbandona» o con l'eliminazione:
## l'Arcanium vale solo dentro la run.

const SCONFITTE_BASE := 3
const MappaRun := preload("res://arcanium/systems/mappa_run.gd")

var in_corso := false
var sconfitte := 0
## Le vite in piu' concesse dagli oggetti: alzano il tetto delle sconfitte.
var vite_extra := 0
## L'Arcanium perso all'ultima sconfitta, da riprendere.
var in_palio := 0

signal cambiato

## ─── La mappa della run (mappa_run.gd) ──────────────────────────────────────
## La mappa intera, generata a `inizia`: si salva cosi' com'e'.
var mappa : Dictionary = {}
## Il nodo scelto e non ancora completato ("" = si sta scegliendo sulla mappa).
var nodo_corrente := ""
## I nodi completati, in ordine: il sentiero fatto.
var completati : Array = []
## La run e' vinta: battuto il boss dell'ultima regione.
var vinta := false

## ─── I miglioramenti della run (il riposo e gli eventi) ─────────────────────
## Gradi d'arma in piu' («Affila»).
var affilature := 0
## «Allenati»: stamina massima e resistenze fisiche.
var allenamenti := 0
## «Studia»: Arcanium massimo e resistenze magiche e agli status.
var studi := 0
## Salute massima in piu' (o in meno): solo eventi e consumabili speciali.
var salute_bonus := 0


func sconfitte_max() -> int:
	return SCONFITTE_BASE + vite_extra


func eliminato() -> bool:
	return sconfitte >= sconfitte_max()


## Una run nuova: tutto da zero, Arcanium compreso, e una mappa nuova dal
## seme (-1 = a caso).
func inizia(seme : int = -1) -> void:
	in_corso = true
	sconfitte = 0
	vite_extra = 0
	in_palio = 0
	mappa = MappaRun.genera(seme if seme >= 0 else randi() % 1000000000)
	nodo_corrente = ""
	completati = []
	vinta = false
	affilature = 0
	allenamenti = 0
	studi = 0
	salute_bonus = 0
	var banca := _banca()
	if banca != null:
		banca.reset()
	cambiato.emit()


## Una sconfitta (morte o baratro, una volta per scontro). Il mucchio di prima
## sparisce, il saldo diventa il nuovo mucchio. Ritorna cosa e' successo, per
## la schermata: {"perso_per_sempre", "in_palio", "sconfitte", "eliminato"}.
func registra_sconfitta() -> Dictionary:
	var perso := in_palio
	var banca := _banca()
	in_palio = banca.perdi_tutto() if banca != null else 0
	sconfitte += 1
	cambiato.emit()
	return {"perso_per_sempre": perso, "in_palio": in_palio,
		"sconfitte": sconfitte, "eliminato": eliminato()}


## Una vittoria: il mucchio torna intero (la taglia del match e' gia' entrata
## nemico per nemico). Ritorna quanto si e' ripreso.
func registra_vittoria() -> int:
	return _restituisci()


## La Pietra del Varco: si salta la rivincita e il mucchio torna subito. La
## sconfitta resta contata.
func spezza_varco() -> int:
	return _restituisci()


## L'oggetto della vita in piu'.
func concedi_vita() -> void:
	vite_extra += 1
	cambiato.emit()


## «Medita» al riposo: una delle sconfitte gia' subite si cancella. Falso se
## non ce n'erano.
func medita() -> bool:
	if sconfitte <= 0:
		return false
	sconfitte -= 1
	cambiato.emit()
	return true


## Fine della run («Abbandona», eliminazione): cio' che resta si perde.
func termina() -> void:
	in_corso = false
	in_palio = 0
	mappa = {}
	nodo_corrente = ""
	completati = []
	var banca := _banca()
	if banca != null:
		banca.reset()
	cambiato.emit()


## ─── Sulla mappa ────────────────────────────────────────────────────────────

## Il nodo con questo id, in qualunque regione ({} se non c'e').
func nodo(id : String) -> Dictionary:
	for reg in mappa.get("regioni", []):
		if (reg["nodi"] as Dictionary).has(id):
			return reg["nodi"][id]
	return {}


func regione(i : int) -> Dictionary:
	var regs : Array = mappa.get("regioni", [])
	return regs[i] if i >= 0 and i < regs.size() else {}


## La regione in cui si trova il giocatore: quella dell'ultimo nodo
## completato, o la successiva se era il suo boss.
func regione_attuale() -> int:
	if completati.is_empty():
		return 0
	var ultimo := nodo(completati[-1])
	var r : int = ultimo.get("regione", 0)
	return r + 1 if ultimo.get("tipo", "") == "boss" else r


## I nodi che si possono scegliere adesso.
func raggiungibili() -> Array:
	if mappa.is_empty() or vinta or nodo_corrente != "":
		return []
	if completati.is_empty():
		return (regione(0).get("piani", [[]]) as Array)[0].duplicate()
	var ultimo := nodo(completati[-1])
	if ultimo.get("tipo", "") == "boss":
		var r := regione(int(ultimo["regione"]) + 1)
		return (r["piani"][0] as Array).duplicate() if not r.is_empty() else []
	return (ultimo.get("prossimi", []) as Array).duplicate()


## Si entra in un nodo. Falso se non e' raggiungibile.
func scegli(id : String) -> bool:
	if not id in raggiungibili():
		return false
	nodo_corrente = id
	cambiato.emit()
	return true


## Il nodo corrente e' fatto (scontro vinto, scelta al riposo, ...). Battere il
## boss dell'ultima regione vince la run.
func completa() -> void:
	if nodo_corrente == "":
		return
	var n := nodo(nodo_corrente)
	completati.append(nodo_corrente)
	nodo_corrente = ""
	if n.get("tipo", "") == "boss" and int(n.get("regione", 0)) == (mappa.get("regioni", []) as Array).size() - 1:
		vinta = true
	cambiato.emit()


## Il nodo in corso, o {} sulla mappa.
func nodo_in_corso() -> Dictionary:
	return nodo(nodo_corrente) if nodo_corrente != "" else {}


## La tappa (1-4) del nodo in corso: la difficolta' sta qui, non nel
## territorio.
func tappa() -> int:
	var n := nodo_in_corso()
	return int(n.get("regione", regione_attuale())) + 1


## ─── Il salvataggio (SaveManager) ───────────────────────────────────────────
## La run si salva fra un nodo e l'altro: su telefono si chiude e si riprende
## dalla mappa (design-mappa-run).
const CAMPI := ["in_corso", "sconfitte", "vite_extra", "in_palio", "mappa", "nodo_corrente",
		"completati", "vinta", "affilature", "allenamenti", "studi", "salute_bonus"]


func to_dict() -> Dictionary:
	var d := {}
	for c in CAMPI:
		d[c] = get(c)
	return d


func from_dict(d : Dictionary) -> void:
	for c in CAMPI:
		if d.has(c):
			set(c, d[c])
	cambiato.emit()


func _restituisci() -> int:
	var preso := in_palio
	in_palio = 0
	var banca := _banca()
	if banca != null and preso > 0:
		banca.restituisci(preso)
	cambiato.emit()
	return preso


func _banca() -> Node:
	return get_node_or_null("/root/CrystalBank")
