extends StatusEffect

## ⚠️ Niente `class_name`: si importa con `preload` (status_host.gd).

## Shock — Comando del Tuono (2026-11-07, regole dell'autore). A build-up: a soglia toglie
## di colpo il 20% degli HP. A ogni Shock la soglia del prossimo sale, salvo che il
## bersaglio sia BAGNATO: allora toglie il 25% degli HP totali e la soglia torna quella di
## partenza. E' li' la sinergia con chi bagna (corsi d'acqua, spell, altre armi).

@export var soglia_base : float = 100.0
## Quanto sale la soglia a ogni Shock da asciutto.
@export var soglia_in_piu : float = 50.0
@export var decay_per_sec : float = 6.0
@export var quota_asciutto : float = 0.20
@export var quota_bagnato : float = 0.25

var meter : float = 0.0
## Il build-up aggiuntivo accumulato dagli Shock precedenti.
var extra : float = 0.0

signal meter_changed(ratio : float)
signal scattato(danno : float, bagnato : bool)


func _init() -> void:
	id = "shock"
	label = "Shock"
	icon = "⚡"
	color = Color("#ffe066")
	## Solo il lampo: l'effetto e' istantaneo.
	duration = 0.45


func soglia() -> float:
	return soglia_base + extra


func accumulo() -> float:
	return clampf(meter / soglia(), 0.0, 1.0)


func add_buildup(amount : float) -> void:
	if is_active() or amount <= 0.0:
		return
	meter = minf(soglia(), meter + amount)
	meter_changed.emit(accumulo())
	if meter >= soglia():
		meter = 0.0
		meter_changed.emit(0.0)
		trigger()


func on_apply() -> void:
	var host := get_parent()
	var corpo := host.get_parent() if host != null else null
	var salute = corpo.get("health_system") if corpo != null else null
	var acqua = host.get_effect("bagnato") if host != null and host.has_method("get_effect") else null
	var bagnato : bool = acqua != null and acqua.is_active()
	var danno := 0.0
	if salute != null and salute.has_method("drain"):
		danno = float(salute.get("total_health")) * (quota_bagnato if bagnato else quota_asciutto)
		salute.drain(danno, "FULMINE")
	extra = 0.0 if bagnato else extra + soglia_in_piu
	scattato.emit(danno, bagnato)


func decay_meter(delta : float) -> void:
	if is_active() or meter <= 0.0:
		return
	meter = maxf(0.0, meter - decay_per_sec * delta)
	meter_changed.emit(accumulo())
