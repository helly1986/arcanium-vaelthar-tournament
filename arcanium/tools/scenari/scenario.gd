extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## SCENARIO — una situazione montata apposta, con la sua verita' scritta
## ═══════════════════════════════════════════════════════════════════════════
##
## Gira dentro il ponte del playtest (ponte_playtest.gd, `--scenario=<path>`):
## stessi sorveglianti, stessa telemetria, stesse catture delle partite. Cambia
## chi decide (lo scenario, non Jev) e cosa resta alla fine: le ETICHETTE, cioe'
## quali difetti ci sono davvero e in che tick. Sono le righe del set
## etichettato con cui si misurano precisione e richiamo di ogni canale
## (sorveglianti, Noul di Jev, canale visivo) — principio 2 del piano.
##
## Lancio: python arcanium/tools/playtest/gioca.py --scenario <nome>
## (APPDATA isolato come ogni lancio: vedi skill arcanium-playtest).
##
## Uno scenario concreto estende questo file e sovrascrive cio' che gli serve.

## La scena da caricare (va passata a Godot come scena principale).
var scena := "res://arcanium/levels/arena_branco.tscn"
## Quanti tick dura, dal primo tick in cui la scena e' agganciata.
var durata := 600
## Il ponte, per catturare e segnalare (`ponte.cattura_scenario(...)`).
var ponte : Node = null
## Le verita': [{tipo, soggetto, da_tick, a_tick, nota}] — un difetto vero per riga.
## I casi PULITI si dichiarano con tipo "pulito": servono quanto i difetti.
var etichette : Array = []


## Una volta, appena la scena e' agganciata (player e nemici esistono).
func prepara(_oss) -> void:
	pass

## A ogni tick, prima delle decisioni.
func al_tick(_tick : int, _oss) -> void:
	pass

## L'azione da dare al player a questo tick di decisione (default: ferma).
func azione(_tick : int, _oss) -> String:
	return "wait"

func etichetta(tipo : String, soggetto : String, da_tick : int, a_tick : int, nota : String = "") -> void:
	etichette.append({"tipo": tipo, "soggetto": soggetto, "da_tick": da_tick, "a_tick": a_tick, "nota": nota})


## ─── Aiuti comuni per montare le situazioni ─────────────────────────────────

## Sposta il player (anche il suo slancio): e' una MESSA IN SCENA, non un'azione
## di gioco, quindi qui si puo' toccare il nodo direttamente.
static func porta_player(oss, dove : Vector3) -> void:
	oss.player.global_position = dove
	oss.player.velocity = Vector3.ZERO

static func nemico_per_nome(oss, prefisso : String) -> Node3D:
	for e in oss.nemici():
		if str(e.name).begins_with(prefisso):
			return e
	return null
