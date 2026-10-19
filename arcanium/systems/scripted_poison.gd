extends Node

## Veleno scriptato del pickup "Spada del Senza Nome" — port di ScriptedPoison.js
## (Arcanium-Lite). NON è un debuff bilanciato: è la conseguenza narrativa di aver
## raccolto l'arma del boss. Drena HP a ritmo COSTANTE fino a 0 — inarrestabile,
## non curabile (la Fiala funziona ancora, ma il veleno non si ferma), una volta
## sola. Al termine (HP a 0) emette `finished` e si disattiva.
##
## Il PrologueDirector lo istanzia e chiama start(health_system) dopo la vittoria.

signal finished

## Secondi per portare gli HP pieni a 0 (25 come in Lite).
@export var duration : float = 25.0

var _health_system : ArcaniumHealthSystem = null
var _rate_per_second : float = 0.0
var _active : bool = false

func start(health_system : ArcaniumHealthSystem) -> void:
	if _active or health_system == null:
		return
	_health_system = health_system
	_rate_per_second = float(health_system.total_health) / duration
	_active = true
	## Il lamento continuo. ⚠️ Il veleno drena via `drain()`, che NON passa da
	## `_on_damage_signal`: senza questo, l'unica fonte di danno che dura
	## venticinque secondi sarebbe l'unica muta.
	Suoni.dolore_continuo_avvia()

func _process(delta : float) -> void:
	if not _active:
		return
	_health_system.drain(_rate_per_second * delta)
	# drain() emette `died` a 0 (→ il player entra in death()): qui ci fermiamo
	# così il revive/scene-change non fa ripartire il drenaggio da capo.
	if _health_system.current_health <= 0:
		_active = false
		Suoni.dolore_continuo_ferma()
		finished.emit()
