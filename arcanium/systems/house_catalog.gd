extends Node

## Catalogo delle Casate di Vaelthar (lore: lore/HOUSES.md) + distribuzione
## iniziale delle Sette Marche per casata. Dati statici condivisi da:
##  - la schermata di creazione personaggio (mostra casate + marche)
##  - il SaveManager (registra la casata scelta nel salvataggio)
##
## Le Marche di partenza sono una DERIVAZIONE di design dall'identità di ogni
## casata (la lore non dà numeri): somma ~71 per le 6 casate giocabili, la Casa
## Reale Kaelvar è volutamente superiore (magia Arcaica). Chiavi = sigle in
## MarcheStats.SIGLE. Vedi arcanium/resources/marche_stats.gd.
##
## Stati:
##  - "unlocked"  → selezionabile ora (solo Dawnkeep)
##  - "locked"    → casata prevista ma non ancora giocabile ("in arrivo")
##  - "ng_plus"   → la Casa Reale imperiale: solo in New Game+ (Kaelvar)

## Ordine di presentazione a schermo.
const ORDER : Array = ["dawnkeep", "sylvorn", "vorrkai", "aethon", "verath", "amareth", "kaelvar"]

const HOUSES : Dictionary = {
	"dawnkeep": {
		"name": "Dawnkeep",
		"motto": "In vigilance I shall end my life.",
		"affinity": "Frost — ice, control, barriers",
		"color": "#8fbfe0",
		"state": "unlocked",
		"marche": {"CON": 10, "EMP": 9, "VOL": 11, "BON": 8, "PER": 13, "SAC": 8, "RES": 12},
	},
	"sylvorn": {
		"name": "Sylvorn",
		"motto": "Sheltered from the storm. Beneath the Spirit of the Forest.",
		"affinity": "Spiritual — spirits, natural summons",
		"color": "#3f7a4a",
		"state": "locked",
		"marche": {"CON": 12, "EMP": 13, "VOL": 8, "BON": 12, "PER": 9, "SAC": 8, "RES": 9},
	},
	"vorrkai": {
		"name": "Vorrkai",
		"motto": "We are the will that forges the world.",
		"affinity": "Mechar — constructs, fire, forging",
		"color": "#b23a34",
		"state": "locked",
		"marche": {"CON": 12, "EMP": 8, "VOL": 13, "BON": 7, "PER": 11, "SAC": 9, "RES": 11},
	},
	"aethon": {
		"name": "Aethon",
		"motto": "Asari.",
		"affinity": "Holy — duality, karma, corruption and purification",
		"color": "#c8a94a",
		"state": "locked",
		"marche": {"CON": 11, "EMP": 9, "VOL": 8, "BON": 13, "PER": 9, "SAC": 13, "RES": 8},
	},
	"verath": {
		"name": "Verath",
		"motto": "What dies does not vanish. It waits.",
		"affinity": "Necromancy — reanimation, corruption",
		"color": "#8a9a7a",
		"state": "locked",
		"marche": {"CON": 11, "EMP": 12, "VOL": 8, "BON": 9, "PER": 9, "SAC": 13, "RES": 9},
	},
	"amareth": {
		"name": "Amareth",
		"motto": "The sun does not set. It completes its circle.",
		"affinity": "Temporal-Lightning — the rhythm of battle, lightning",
		"color": "#e0a040",
		"state": "locked",
		"marche": {"CON": 12, "EMP": 9, "VOL": 11, "BON": 8, "PER": 8, "SAC": 10, "RES": 13},
	},
	"kaelvar": {
		"name": "Kaelvar",
		"motto": "By the will of the First. For as long as the World endures.",
		"affinity": "Archaic — the Wanderer's original magic",
		"color": "#d4af37",
		"state": "ng_plus",
		"marche": {"CON": 13, "EMP": 11, "VOL": 11, "BON": 11, "PER": 12, "SAC": 11, "RES": 12},
	},
}

## Casata di default (l'unica giocabile ora).
const DEFAULT_HOUSE : String = "dawnkeep"

static func get_house(id : String) -> Dictionary:
	return HOUSES.get(id, HOUSES[DEFAULT_HOUSE])
