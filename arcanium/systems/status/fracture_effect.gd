extends StatusEffect
class_name FractureEffect

## Frattura (B1 del Senza Nome) — vulnerabilità pura: mentre attiva moltiplica il
## danno SUBITO dal bersaglio. Nessun build-up: si applica direttamente col colpo
## (in Lite: StatBlock.applyVulnerability, mult 1.35 per 15s).
##
## L'ArcaniumHealthSystem interroga `damage_multiplier()` in fase di calcolo danno.

@export var multiplier : float = 1.35

func _init() -> void:
	id = "fracture"
	label = "Fracture"
	icon = "🩸"
	color = Color("#dd4466")
	duration = 15.0

## Applica la Frattura con parametri espliciti (chi colpisce decide mult/durata).
func inflict(mult : float, dur : float) -> void:
	multiplier = mult
	duration = dur
	trigger()

## Moltiplicatore da applicare al danno in arrivo (1.0 se non attiva).
func damage_multiplier() -> float:
	return multiplier if is_active() else 1.0
