extends StatusEffect
class_name EchoErosionEffect

## Erosione dell'Eco (afflizione Shaded del Senza Nome, Gruppo A) — meccanica di
## BUILD-UP distinta dalla Frattura: ogni colpo del Gruppo A riempie una barra
## (`meter`); a `threshold` PROCca l'afflizione per `duration` secondi, che drena
## l'Arcanium del bersaglio e sopprime la regen di stamina. La barra decade se non
## si viene colpiti — va mantenuta la pressione. Fedele a Lite/EchoErosion.js.
##
## Default = SENZA_NOME.ECHO_EROSION di Constants.js (buildup 40, soglia 100,
## durata 5s, drain 8/s, regenMult 0.25, decay 14/s).

@export var buildup : float = 40.0     ## incremento barra per colpo A
@export var threshold : float = 100.0  ## soglia di proc
@export var drain : float = 8.0        ## Arcanium drenato/s mentre attiva
@export var regen_mult : float = 0.25  ## moltiplicatore regen stamina mentre attiva
@export var decay : float = 14.0       ## decadimento barra/s se non colpito

var meter : float = 0.0

## Rapporto di riempimento della barra, 0..1: lo legge StatusHost.accumuli()
## per gli status alla Elden Ring in basso al centro (status_centrali.gd).
func accumulo() -> float:
	return clampf(meter / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0


## Emesso ogni frame mentre attiva: quanto Arcanium drenare in questo frame.
signal drained(amount : float)
## Emesso quando la barra cambia (per la UI di build-up): meter/threshold.
signal meter_changed(ratio : float)

func _init() -> void:
	id = "echo_erosion"
	label = "Echo Erosion"
	icon = "🕳"
	color = Color("#7a5cff")
	duration = 5.0

## Regen stamina corrente (1.0 se non attiva, `regen_mult` mentre attiva).
func stamina_regen_mult() -> float:
	return regen_mult if is_active() else 1.0

## Chiamato a ogni colpo del Gruppo A che va a segno. Riempie la barra; a soglia
## piena scatta l'afflizione. Mentre è già attiva i colpi non ricaricano.
func build() -> void:
	if is_active():
		return
	meter = minf(threshold, meter + buildup)
	meter_changed.emit(meter / threshold)
	if meter >= threshold:
		meter = 0.0
		meter_changed.emit(0.0)
		trigger()  # attiva per `duration` secondi

func on_tick(delta : float) -> void:
	# Mentre attiva: drena Arcanium. Il decadimento barra è gestito in _process
	# base solo tramite remaining; il decay della barra pre-proc sta in decay().
	drained.emit(drain * delta)

## Da chiamare ogni frame anche quando NON attiva, per far decadere la barra.
func decay_meter(delta : float) -> void:
	if is_active() or meter <= 0.0:
		return
	meter = maxf(0.0, meter - decay * delta)
	meter_changed.emit(meter / threshold)
