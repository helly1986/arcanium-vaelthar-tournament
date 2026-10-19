extends RefCounted
class_name BarChip

## Logica riusabile del "chip": una scia chiara che resta indietro quando una
## barra cala di colpo (danno/spesa) e poi rientra fino al riempimento. Lavora su
## ratii 0..1. Port fedele di Arcanium-Lite/BarChip.js.

var chip : float
var _last : float
var _timer : float = 0.0

func _init(ratio : float = 1.0) -> void:
	chip = ratio
	_last = ratio

## ratio: valore attuale (0..1). delta: secondi. Ritorna la width del chip (0..1).
func update(ratio : float, delta : float, hold : float = 0.4, speed : float = 0.7) -> float:
	if ratio < _last - 1e-4:
		_timer = hold          # appena calato → trattieni la scia
	_last = ratio

	if ratio > chip:
		chip = ratio            # barra cresciuta (cura/regen): la scia segue subito
	elif _timer > 0.0:
		_timer -= delta
	elif chip > ratio:
		chip = maxf(ratio, chip - speed * delta)
	return chip
