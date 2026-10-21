extends StatusEffect
class_name PoiseBreakEffect

## Poise-break del Senza Nome — meccanica di BUILD-UP analoga all'Erosione dell'Eco
## (`echo_erosion_effect.gd`), ma senza moltiplicatore di danno: mentre attiva il
## boss è STAGGERATO (letto direttamente da `arcanium_boss.gd` via
## `status_host.get_effect("poise_break").is_active()`), non dall'health system.
##
## Il colpo caricato del player costruisce più barra del colpo normale (il
## `poise_damage` dell'arma è parametrico, vedi `build(amount)`); il parry riuscito
## rompe il poise ISTANTANEAMENTE (`break_now()`), a prescindere dalla barra.

@export var threshold : float = 100.0  ## soglia di proc
@export var decay : float = 12.0       ## decadimento barra/s se non si mantiene la pressione

var meter : float = 0.0

## Rapporto di riempimento della barra, 0..1: lo legge StatusHost.accumuli()
## per gli status alla Elden Ring in basso al centro (status_centrali.gd).
func accumulo() -> float:
	return clampf(meter / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0


## Emesso quando la barra cambia (per la UI di build-up): meter/threshold.
signal meter_changed(ratio : float)

func _init() -> void:
	id = "poise_break"
	label = "Stance Broken"
	icon = "💥"
	color = Color("#ffcc33")
	duration = 4.0

## Chiamato a ogni colpo che contribuisce al poise-break. Mentre già attivo i
## colpi non ricaricano (coerente con l'Erosione dell'Eco).
func build(amount : float) -> void:
	if is_active():
		return
	meter = minf(threshold, meter + amount)
	meter_changed.emit(meter / threshold)
	if meter >= threshold:
		meter = 0.0
		meter_changed.emit(0.0)
		trigger()

## Rottura istantanea (parry riuscito): salta il build-up, scatta subito.
func break_now() -> void:
	meter = 0.0
	meter_changed.emit(0.0)
	trigger()

## Da chiamare ogni frame anche quando NON attiva, per far decadere la barra.
func decay_meter(delta : float) -> void:
	if is_active() or meter <= 0.0:
		return
	meter = maxf(0.0, meter - decay * delta)
	meter_changed.emit(meter / threshold)
