extends "res://enemy/enemy_base_root_motion.gd"

## ⚠️ LEGACY — NON fa parte della gerarchia ArcaniumEnemy.
##
## Si chiamava `arcanium_enemy.gd`, ma non è il nemico di Arcanium: è il
## MANICHINO del livello di prova (`characters/test_dawnkeep_level.tscn`, via
## `characters/arcanium_enemy.tscn`), cioè il nemico del template guidato dalla
## sua pipeline (`attack()` → hitbox dell'EquipmentSystem → target.hit). Risale
## alla Fase 4, quando il move set data-driven era appena nato e i nemici veri
## non esistevano ancora.
##
## I nemici del gioco stanno in `arcanium/systems/enemies/` e discendono da
## `ArcaniumEnemy`, che guida direttamente l'AnimationPlayer invece di passare
## dal combat loop del template. È stato rinominato per liberare il nome
## `arcanium_enemy.gd` e per non far credere che sia la classe base.
##
## Da tenere finché serve il livello dei manichini (utile per confrontare il
## "feel" del template col nostro), da cancellare insieme a quello.

## Nemico Arcanium: sostituisce il combat loop random 30/70 del template con una
## AI data-driven dal move set, portata da Lite/SenzaNomeDecisions.js:
##  • APERTURA: scelta pesata per fascia (range) con memoria anti-ripetizione
##    (ultima mossa penalizzata, penultima ancora di più) → varietà leggibile;
##  • CATENE: combo graph (move.chains) con recovery extra a fine catena
##    (la finestra di punizione souls-like);
##  • FASI: sotto soglia HP sblocca i gruppi pesanti (C/S) e catene più lunghe.
##
## Sottoclasse del nemico base (scena erede) → non tocca il template. Consegna il
## danno infilando la mossa come `equipment_info` dell'arma e lasciando che la
## pipeline del template (attack_started → hitbox → target.hit) porti
## danno + status (Erosione/Frattura) al bersaglio. Se `move_set` è null, ricade
## sul comportamento originale.

@export var move_set : EnemyMoveSet

const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")
const REPEAT_PENALTY := 0.15    ## peso dell'ultima mossa usata (anti-martello)
const REPEAT2_PENALTY := 0.55   ## peso della penultima

var _cooldown_until : Dictionary = {}   # move.id → timestamp (s) di riuso
var _weapon : EquipmentSystem
var _busy : bool = false
var _last_move : String = ""
var _second_last : String = ""

func _ready() -> void:
	super._ready()
	_weapon = get_node_or_null("EquipmentSystem")

## Override del selettore del template: avvia una SEQUENZA (apertura + catene).
func combat_randomizer() -> void:
	if move_set == null or move_set.moves.is_empty() or not is_instance_valid(target):
		super.combat_randomizer()
		return
	if _busy:
		return
	_run_sequence()

func _run_sequence() -> void:
	_busy = true
	var chain_len := 0
	var move := _choose_opening()

	while move != null and not _aborted():
		_perform(move)
		# ritmo: telegraph + recovery della mossa + stacco di catena
		await get_tree().create_timer(move.telegraph + move.recovery + move_set.link_gap).timeout
		chain_len += 1
		if _aborted() or chain_len >= _max_chain():
			break
		move = _choose_chain(move)

	# recovery di fine catena (2+ colpi): la finestra di punizione, souls-like
	if chain_len >= 2 and not _aborted():
		await get_tree().create_timer(move_set.chain_recovery).timeout
	_busy = false

func _aborted() -> bool:
	return current_state == state.DEAD or not is_instance_valid(target)

func _perform(move : EnemyMove) -> void:
	if _weapon and _weapon.current_equipment:
		_weapon.current_equipment.equipment_info = move
	if move.cooldown > 0.0:
		_cooldown_until[move.id] = OrologioGioco.adesso() + move.cooldown
	_second_last = _last_move
	_last_move = move.id
	attack()  # pipeline del template consegna danno+status

## ─── Apertura: pool pesato per fascia con anti-ripetizione ───────────────────
func _choose_opening() -> EnemyMove:
	var dist := _distance()
	var phase2 := _in_phase2()
	var now := OrologioGioco.adesso()

	var pool : Array[EnemyMove] = []
	var weights : Array[float] = []
	for m in move_set.eligible(dist, phase2):
		if m.pick_weight <= 0.0:
			continue  # mosse solo-da-catena (es. C1) non aprono
		if now < float(_cooldown_until.get(m.id, 0.0)):
			continue
		var w := m.pick_weight
		if m.id == _last_move:
			w *= REPEAT_PENALTY
		elif m.id == _second_last:
			w *= REPEAT2_PENALTY
		pool.append(m)
		weights.append(w)

	if pool.is_empty():
		retreat()
		return null
	return _weighted_pick(pool, weights)

## ─── Catena: prima regola compatibile (banda + tiro) vince ───────────────────
func _choose_chain(prev : EnemyMove) -> EnemyMove:
	var dist := _distance()
	var phase2 := _in_phase2()
	var now := OrologioGioco.adesso()
	var band := "melee" if dist <= move_set.melee_threshold else "range"

	for rule in prev.chains:
		var when : String = rule.get("when", "any")
		if when != "any" and when != band:
			continue
		var chance : float = float(rule.get("chance", 0.0))
		if phase2:
			chance = float(rule.get("chance2", chance * move_set.chain_p2_mult))
		if randf() > chance:
			continue
		var nxt := move_set.find_move(rule.get("next", ""))
		if nxt == null:
			continue
		if nxt.move_range < dist:
			continue  # follow-up fuori portata: catena interrotta
		if now < float(_cooldown_until.get(nxt.id, 0.0)):
			continue
		return nxt
	return null

## ─── Helper ──────────────────────────────────────────────────────────────────
func _distance() -> float:
	return global_position.distance_to(target.global_position)

func _max_chain() -> int:
	return move_set.max_chain_p2 if _in_phase2() else move_set.max_chain_p1

func _weighted_pick(pool : Array[EnemyMove], weights : Array[float]) -> EnemyMove:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return pool[randi() % pool.size()]
	var r := randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

func _in_phase2() -> bool:
	if health_system == null:
		return move_set.phase2_hp_ratio >= 1.0
	var total : float = float(health_system.total_health)
	if total <= 0.0:
		return false
	return float(health_system.current_health) / total <= move_set.phase2_hp_ratio
