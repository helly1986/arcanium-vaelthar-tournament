extends "res://arcanium/tools/scenari/scenario.gd"

## ═══════════════════════════════════════════════════════════════════════════
## SCENARIO: l'ululato dell'Alpha sulla Traccia — il "lupo in groppa"
## ═══════════════════════════════════════════════════════════════════════════
##
## Il director della Traccia (`_on_alpha_howl`) fa ancora `add_child` e POI
## `global_position`: lo schema che a Kalvorn faceva finire un lupo in groppa a
## un altro (vedi richiamo_branco.gd, dove e' corretto). Qui si fa ululare
## l'Alpha a comando, con il player fermo ai margini dell'arena, e si guarda
## dove nascono i due rinforzi: fotogrammi a +1, +2, +15 e +60 tick.
##
## Il sorvegliante "corpo_su_corpo" deve scattare se il difetto c'e'; dopo il
## fix questo scenario e' la regressione che lo tiene chiuso.
##
## Vaelthar Tournament: la Traccia e il suo director non ci sono piu'. Lo
## scenario gira nell'arena del branco e l'ululato ora lo serve il
## RichiamoBranco dell'Alpha stesso: resta la regressione del lupo in groppa.

const TICK_ULULATO := 40

var _alpha : Node3D = null


func _init() -> void:
	scena = "res://arcanium/levels/arena_branco.tscn"
	durata = 260


func prepara(oss) -> void:
	_alpha = nemico_per_nome(oss, "LupoAlpha")
	porta_player(oss, Vector3(0.0, 0.3, 8.0))


func al_tick(tick : int, oss) -> void:
	if _alpha == null or not is_instance_valid(_alpha):
		return
	if tick == TICK_ULULATO:
		## Messa in scena: e' il segnale che l'Alpha emette all'apice della
		## clip dell'ululato (arcanium_quadruped_enemy.gd). Lo si emette qui per
		## non dipendere da quando l'IA decide di ululare.
		_alpha.howl_summon.emit()
	for dopo in [1, 2, 15, 60]:
		if tick == TICK_ULULATO + dopo:
			ponte.cattura_scenario("ululato_piu_%d" % dopo, _alpha.global_position)


func azione(_tick : int, _oss) -> String:
	return "wait"
