extends Resource
class_name EnemyMoveSet

## Move set data-driven di un nemico: la lista delle mosse + i parametri di ritmo
## delle catene (da Lite/Constants.js SENZA_NOME). Sostituisce il random 30/70 del
## template. Usato da ArcaniumEnemyAI per scegliere cosa fare in COMBAT.

@export var moves : Array[EnemyMove] = []

## ─── Ritmo / fasi (da SENZA_NOME) ────────────────────────────────────────────
@export var link_gap : float = 0.4      ## stacco tra un colpo e il successivo
@export var chain_recovery : float = 1.15 ## pausa di fine catena (finestra di punizione)
@export var max_chain_p1 : int = 2      ## mosse max per sequenza in fase 1
@export var max_chain_p2 : int = 4      ## fase 2: catene più lunghe
@export var chain_p2_mult : float = 1.35 ## fase 2: probabilità di concatenare più alta

## Soglia di distanza melee/range per la banda "when" delle catene.
@export var melee_threshold : float = 2.0

## Fase 2: sotto questa frazione di HP il nemico sblocca i gruppi "pesanti" (C/S)
## e concatena di più. 1.0 = sempre in fase 2; 0.0 = mai.
@export_range(0.0, 1.0) var phase2_hp_ratio : float = 0.5

## Trova una mossa per id (per le catene).
func find_move(id : String) -> EnemyMove:
	for m in moves:
		if m and m.id == id:
			return m
	return null

## Ritorna le mosse eleggibili data la distanza dal bersaglio e la fase.
func eligible(distance : float, phase2 : bool) -> Array[EnemyMove]:
	var out : Array[EnemyMove] = []
	for m in moves:
		if m == null:
			continue
		if m.move_range < distance:
			continue
		# Filtro minimo simmetrico: le mosse a distanza (min_range > 0) non partono
		# se il bersaglio è troppo vicino (un cast in faccia è brutto e mal punibile).
		if m.min_range > 0.0 and distance < m.min_range:
			continue
		# I gruppi pesanti (C/S) solo in fase 2.
		if (m.group == "C" or m.group == "S") and not phase2:
			continue
		out.append(m)
	return out
