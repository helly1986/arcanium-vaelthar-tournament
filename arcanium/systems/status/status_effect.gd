extends Node
class_name StatusEffect

## Classe base per gli status effect di Arcanium, componibili come Node figli di
## uno StatusHost. Gestisce ciclo di vita (durata + scadenza) e i segnali per
## UI/log; le sottoclassi implementano il comportamento (on_apply/on_tick).
##
## Contratto: uno status "attivo" ha `remaining > 0`. `id` è la chiave logica
## (es. "fracture", "echo_erosion"); `label/icon/color` sono per la UI.

@export var id : String = "status"
@export var label : String = "Status"
@export var icon : String = "●"
@export var color : Color = Color("#cc7744")
## Durata dell'afflizione attiva, in secondi.
@export var duration : float = 1.0

var remaining : float = 0.0

signal applied(effect : StatusEffect)
signal refreshed(effect : StatusEffect)
signal expired(effect : StatusEffect)
## Emesso a ogni frame mentre attivo: ratio 1→0 utile per barre di durata.
signal ticked(effect : StatusEffect, ratio : float)

func is_active() -> bool:
	return remaining > 0.0

## Ratio 1.0 (appena applicato) → 0.0 (in scadenza), per la UI.
func ratio() -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(remaining / duration, 0.0, 1.0)

## (Ri)attiva l'effetto per `duration` secondi.
func trigger() -> void:
	var was_active := is_active()
	remaining = duration
	on_apply()
	if was_active:
		refreshed.emit(self)
	else:
		applied.emit(self)

func _process(delta : float) -> void:
	if remaining <= 0.0:
		return
	remaining = maxf(0.0, remaining - delta)
	on_tick(delta)
	ticked.emit(self, ratio())
	if remaining <= 0.0:
		on_expire()
		expired.emit(self)

## Chiude SUBITO un effetto attivo, come se fosse scaduto (una cura: le Bende
## dell'Eco sulla Lacerazione). Niente se non e' attivo.
func termina() -> void:
	if remaining <= 0.0:
		return
	remaining = 0.0
	on_expire()
	expired.emit(self)

## ─── Da sovrascrivere nelle sottoclassi ─────────────────────────────────────
func on_apply() -> void: pass
func on_tick(_delta : float) -> void: pass
func on_expire() -> void: pass
