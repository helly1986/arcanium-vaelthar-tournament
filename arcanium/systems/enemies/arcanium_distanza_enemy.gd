extends "res://arcanium/systems/enemies/arcanium_humanoid_enemy.gd"

## ⚠️ Niente `class_name`: come gli altri nemici si aggancia per percorso.

## ═══════════════════════════════════════════════════════════════════════════
## A DISTANZA — un umanoide che non vuole il giocatore addosso
## ═══════════════════════════════════════════════════════════════════════════
##
## Estratto dall'arciere il 2026-09-26, quando il Mago Guerriero ne ha avuto
## bisogno uguale: la RITIRATA (si gira e corre a riprendere la distanza, con
## giudizio: una corsa, non una fuga infinita) e l'ARROCCATO (sul muro non
## insegue). Chi tira con l'arco ci aggiunge la corda
## (`arcanium_archer_enemy.gd`), chi lancia ci aggiunge i suoi incantesimi
## (`arcanium_mago_enemy.gd`). Il perche' di ogni regola sta nei commenti
## accanto al codice, e nel cappello dell'arciere dove sono nate.

@export_group("Posto")
## Sul muro (il camminamento del cancello di Kalvorn): NON insegue. Da lassu'
## un passo verso il bersaglio e' un passo nel vuoto, o contro il parapetto a
## correre sul posto. Tira da dove sta e si gira verso chi mira; la RITIRATA
## invece resta — sul camminamento si scappa lungo i parapetti, ed e' la
## risposta giusta a chi sale la scala.
@export var arroccato : bool = false

@export_group("Ritirata")
## Sotto questa distanza si gira e corre.
@export var distanza_ritirata : float = 4.5
## A questa distanza si ferma e torna a tirare.
@export var distanza_preferita : float = 9.0
## Durata massima di una ritirata, in secondi.
@export var ritirata_max : float = 2.2
## Riposo dopo una ritirata: per questo tempo non ne inizia un'altra.
@export var ritirata_pausa : float = 3.5
## Sotto questa velocita' reale, per `bloccato_dopo` secondi, la ritirata e'
## contro un ostacolo e si interrompe.
@export var bloccato_velocita : float = 0.4
@export var bloccato_dopo : float = 0.35

var _in_ritirata : bool = false
var _ritirata_da : float = 0.0
var _ritirata_riposo_fino : float = 0.0
var _bloccato_da : float = -1.0


func _ai_step(delta : float) -> void:
	if not is_instance_valid(target):
		_chiudi_ritirata()
		super._ai_step(delta)
		return
	var dist := _flat_distance(target)
	if _in_ritirata:
		if _ritirata_finita(dist):
			_chiudi_ritirata()
		else:
			_corri_via(delta)
			return
	elif _vuole_ritirarsi(dist):
		_in_ritirata = true
		_ritirata_da = _now()
		_bloccato_da = -1.0
		_corri_via(delta)
		return
	super._ai_step(delta)


func _vuole_ritirarsi(dist : float) -> bool:
	return dist < distanza_ritirata \
		and not _busy \
		and _now() >= _ritirata_riposo_fino \
		and _state != State.DEAD and _state != State.STAGGERED and _state != State.VICTIM


func _ritirata_finita(dist : float) -> bool:
	if dist >= distanza_preferita:
		return true
	if _now() - _ritirata_da >= ritirata_max:
		return true
	if _busy or _state == State.DEAD or _state == State.STAGGERED or _state == State.VICTIM:
		return true
	## In un angolo: la velocita' vera resta bassa mentre si spinge.
	var v := get_real_velocity()
	v.y = 0.0
	if v.length() < bloccato_velocita:
		if _bloccato_da < 0.0:
			_bloccato_da = _now()
		elif _now() - _bloccato_da >= bloccato_dopo:
			return true
	else:
		_bloccato_da = -1.0
	return false


func _chiudi_ritirata() -> void:
	if _in_ritirata:
		_ritirata_riposo_fino = _now() + ritirata_pausa
	_in_ritirata = false
	_bloccato_da = -1.0


## La corsa via. Come `_chase` dell'umanoide: e' la ROOT MOTION della clip di
## corsa a spostare il corpo, nella direzione in cui GUARDA — e in ritirata
## `_face` lo fa guardare lontano dal bersaglio. Ripiego a velocita' fissa
## solo se la clip non porta root motion.
func _corri_via(delta : float) -> void:
	_state = State.CHASE
	_play(run_anim, true)
	if delta > 0.0 and _root_motion_delta.length() > 0.0001:
		var world_rm := global_transform.basis * _root_motion_delta
		velocity.x = world_rm.x / delta
		velocity.z = world_rm.z / delta
	else:
		var dir := -_flat_dir_to(target)
		velocity.x = dir.x * run_speed
		velocity.z = dir.z * run_speed


## Arroccato: dove un altro inseguirebbe, sta. L'ingaggio pero' si annuncia
## lo stesso (`engaged`), come lo annuncia `_chase`: chi ascolta il segnale non
## deve sapere se il nemico corre o tira dal muro.
func _chase(delta : float, dist : float) -> void:
	if not arroccato:
		super._chase(delta, dist)
		return
	if not _has_engaged:
		_has_engaged = true
		engaged.emit()
	_go_idle()


## In ritirata si guarda dove si corre. Il resto del tempo, il bersaglio.
func _face(delta : float, rate_mult : float = 1.0) -> void:
	if not _in_ritirata or not is_instance_valid(target):
		super._face(delta, rate_mult)
		return
	var dir := -_flat_dir_to(target)
	if dir.length() < 0.01:
		return
	var yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(turn_rate * rate_mult * delta, 0.0, 1.0))


## Nessuna ritirata sopravvive a un colpo subito o alla morte: si riparte
## dalla decisione, non da una corsa a meta'.
func hit(_who, _by_what) -> void:
	_chiudi_ritirata()
	super.hit(_who, _by_what)
