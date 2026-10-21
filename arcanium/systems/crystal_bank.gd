extends Node

## Portafoglio dell'Arcanium Cristallizzato. Autoload (singleton) così il saldo
## SOPRAVVIVE al reload della scena — necessario perché la morte del player nel
## template ricarica la scena (get_tree().reload_current_scene()).
##
## Payoff souls-like: si guadagnano cristalli uccidendo i mob (CrystalBounty sul
## nemico) e se ne perde il 50% morendo (chiamato da PlayerCombatLink su
## death_started). Ciò che si spende nel frattempo, ovviamente, non si riperde.
##
## Registrato come autoload "CrystalBank" in project.godot: usalo come
## `CrystalBank.add(...)` da qualunque script.

var crystals : int = 0

## Frazione persa alla morte (0.5 = 50%).
@export var death_loss_fraction : float = 0.5

signal changed(amount : int)
signal awarded(amount : int)      ## guadagno (per feedback/VFX)
signal lost(amount : int)         ## perdita alla morte (per feedback/VFX)
signal recovered(amount : int)    ## mucchio ripreso dopo una sconfitta

func add(amount : int) -> void:
	if amount <= 0:
		return
	crystals += amount
	awarded.emit(amount)
	changed.emit(crystals)

func spend(amount : int) -> bool:
	if amount <= 0 or crystals < amount:
		return false
	crystals -= amount
	changed.emit(crystals)
	return true

## La regola souls del torneo (torneo.gd): alla sconfitta si perde TUTTO il
## saldo non speso. Ritorna quanto, perche' resti in palio per la rivincita.
func perdi_tutto() -> int:
	var lost_amount := crystals
	if lost_amount <= 0:
		return 0
	crystals = 0
	lost.emit(lost_amount)
	changed.emit(crystals)
	return lost_amount

## Il mucchio ripreso: rivincita vinta o Pietra del Varco spezzata.
func restituisci(amount : int) -> void:
	if amount <= 0:
		return
	crystals += amount
	recovered.emit(amount)
	changed.emit(crystals)

## Applica la penalità di morte: perde `death_loss_fraction` del saldo corrente.
## Fuori dal torneo (le arene non ancora legate alla run); nel torneo decide la
## fine dello scontro.
func penalize_on_death() -> void:
	var lost_amount := int(floor(float(crystals) * death_loss_fraction))
	if lost_amount <= 0:
		return
	crystals -= lost_amount
	lost.emit(lost_amount)
	changed.emit(crystals)

## Reset totale (es. new game).
func reset() -> void:
	crystals = 0
	changed.emit(crystals)
