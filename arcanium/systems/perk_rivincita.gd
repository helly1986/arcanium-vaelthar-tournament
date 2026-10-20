extends RefCounted

## I PERK DELLA RIVINCITA (design-crogiolo, decisione dell'autore del
## 2026-10-19): dopo una sconfitta se ne sceglie uno fra tre, e vale solo per
## lo scontro che segue: la rivincita («Riprova») o il prossimo incontro
## raggiunto con la Pietra del Varco («Prosegui»). Svanisce alla vittoria e
## all'abbandono.
##
## Gli effetti stanno in variabili statiche lette da chi li applica
## (arcanium_health_system.gd per i danni): si azzerano a ogni costruzione di
## dungeon e si riaccendono per il perk attivo, cosi' un perk non sopravvive
## per sbaglio allo scontro dopo.

const PERK := [
	{"id": "sangue_ostinato", "icona": "❤", "nome": "Sangue Ostinato",
		"testo": "Vita massima +40%"},
	{"id": "lama_rancorosa", "icona": "⚔", "nome": "Lama Rancorosa",
		"testo": "Danno inflitto +30%"},
	{"id": "pelle_di_pietra", "icona": "🛡", "nome": "Pelle di Pietra",
		"testo": "Danno subito -30%"},
	{"id": "ultimo_respiro", "icona": "✧", "nome": "Ultimo Respiro",
		"testo": "Il primo colpo mortale ti lascia a 1 di vita"},
	{"id": "passo_d_ombra", "icona": "➶", "nome": "Passo d'Ombra",
		"testo": "Schivata e scatto costano metà vigore"},
	{"id": "occhio_del_varco", "icona": "◉", "nome": "Occhio del Varco",
		"testo": "Vedi il doppio più lontano nel buio del dungeon"},
]

## Letti dall'HealthSystem: chi colpisce un nemico del dungeon moltiplica per
## `danno_inflitto`, il giocatore che incassa per `danno_subito`.
static var danno_inflitto := 1.0
static var danno_subito := 1.0
## Ultimo Respiro: si spegne la prima volta che salva.
static var salva_vita := false


static func azzera() -> void:
	danno_inflitto = 1.0
	danno_subito = 1.0
	salva_vita = false


static func dati(id : String) -> Dictionary:
	for p in PERK:
		if p["id"] == id:
			return p
	return {}


## Tre perk diversi a caso (`rng` gia' seminato da chi chiama).
static func tre(rng : RandomNumberGenerator) -> Array:
	var tutti : Array = PERK.duplicate()
	for k in range(tutti.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t = tutti[k]
		tutti[k] = tutti[j]
		tutti[j] = t
	return tutti.slice(0, 3)


## Accende il perk sul giocatore appena portato all'ingresso e sul dungeon
## appena costruito.
static func applica(id : String, giocatore : Node, dungeon : Node) -> void:
	azzera()
	match id:
		"sangue_ostinato":
			var hs = giocatore.get("health_system") if giocatore != null else null
			if hs != null:
				hs.total_health = int(round(hs.total_health * 1.4))
				hs.current_health = hs.total_health
				if "_health_f" in hs:
					hs._health_f = float(hs.total_health)
				hs.health_updated.emit(hs.current_health)
		"lama_rancorosa":
			danno_inflitto = 1.3
		"pelle_di_pietra":
			danno_subito = 0.7
		"ultimo_respiro":
			salva_vita = true
		"passo_d_ombra":
			if giocatore != null:
				giocatore.cost_dodge *= 0.5
				giocatore.cost_sprint *= 0.5
		"occhio_del_varco":
			if dungeon != null and dungeon.nebbia != null:
				dungeon.nebbia.raggio *= 2
				dungeon.nebbia.aggiorna(true)
