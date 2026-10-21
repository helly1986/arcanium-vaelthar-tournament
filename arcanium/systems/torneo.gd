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

var in_corso := false
var sconfitte := 0
## Le vite in piu' concesse dagli oggetti: alzano il tetto delle sconfitte.
var vite_extra := 0
## L'Arcanium perso all'ultima sconfitta, da riprendere.
var in_palio := 0

signal cambiato


func sconfitte_max() -> int:
	return SCONFITTE_BASE + vite_extra


func eliminato() -> bool:
	return sconfitte >= sconfitte_max()


## Una run nuova: tutto da zero, Arcanium compreso.
func inizia() -> void:
	in_corso = true
	sconfitte = 0
	vite_extra = 0
	in_palio = 0
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


## Fine della run («Abbandona», eliminazione): cio' che resta si perde.
func termina() -> void:
	in_corso = false
	in_palio = 0
	var banca := _banca()
	if banca != null:
		banca.reset()
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
