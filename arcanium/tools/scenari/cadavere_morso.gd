extends "res://arcanium/tools/scenari/scenario.gd"

## ═══════════════════════════════════════════════════════════════════════════
## SCENARIO: il player muore fra i lupi — il cadavere si morde ancora?
## ═══════════════════════════════════════════════════════════════════════════
##
## Il difetto (playtest del 2026-10-07, corretto in 2a64561): `death()` arma
## l'invulnerabilita', ma la coroutine `hurt()` del colpo mortale la riarmava
## piu' corta; da li' ogni morso sul cadavere passava e `death_started`
## ripartiva — un'unica morte contata come tre (HP -25, -32, -39).
##
## La regressione nata da quella partita era un REPLAY di azioni: col gioco
## cambiato prende un'altra strada e non arriva piu' nell'arena (2026-10-15:
## obiettivo scaduto al tick 3602, nessuna morte). Qui la situazione si monta e
## basta: il player sta fermo nell'arena dell'Alpha con poca vita, i lupi lo
## uccidono, e si resta a guardare il cadavere per 12 s. Il sorvegliante
## "morte ripetuta" non deve scattare.

const VITA_INIZIALE := 30.0


func _init() -> void:
	scena = "res://arcanium/levels/arena_branco.tscn"
	durata = 60 * 25


func prepara(oss) -> void:
	porta_player(oss, Vector3(0.0, 0.3, 0.0))
	var hs = oss.player.get("health_system")
	## `_health_f` e' il conto vero (ArcaniumHealthSystem): si scende con
	## apply_damage, come un colpo qualunque, invece di scrivere i campi.
	if hs.has_method("apply_damage"):
		hs.apply_damage(float(hs.current_health) - VITA_INIZIALE)
	print("PLAYTEST: player a %s HP fra i lupi" % hs.current_health)
	etichetta("pulito", "player", 0, durata, "una morte sola: nessun death_started ripetuto")


func azione(_tick : int, _oss) -> String:
	return "wait"
