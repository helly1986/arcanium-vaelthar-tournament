extends StatusEffect

## ⚠️ Niente `class_name`: si importa con `preload` (status_host.gd).
## Veleno — lo stato della famiglia Veleno (chiesto dall'autore il 2026-11-07). A build-up:
## a soglia, per 10 secondi consuma una quota della vita massima a piccoli morsi lenti, non
## mitigati, e le cure valgono la meta'. La Frattura amplifica i morsi, il Sacro ne annulla
## l'accumulo.

@export var threshold : float = 100.0
@export var decay_per_sec : float = 6.0
@export var ritardo_decadimento : float = 3.0
## Quanto consuma in tutto: quota della vita MASSIMA, piu' un fisso.
@export var frazione_vita : float = 0.15
@export var danno_fisso : float = 10.0
## Quanto valgono le cure mentre e' attivo.
@export var molt_cure : float = 0.5

var meter : float = 0.0
var _fermo : float = 0.0
var _al_morso : float = 0.0

signal meter_changed(ratio : float)


func _init() -> void:
	id = "veleno"
	label = "Poison"
	icon = "🧪"
	color = Color("#7fc241")
	duration = 10.0


func accumulo() -> float:
	return clampf(meter / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0


func add_buildup(amount : float) -> void:
	if is_active() or amount <= 0.0:
		return
	meter = minf(threshold, meter + amount)
	_fermo = ritardo_decadimento
	meter_changed.emit(accumulo())
	if meter >= threshold:
		meter = 0.0
		meter_changed.emit(0.0)
		trigger()


func on_apply() -> void:
	_al_morso = 1.0


func on_tick(delta : float) -> void:
	_al_morso -= delta
	if _al_morso > 0.0:
		return
	_al_morso += 1.0
	var host := get_parent()
	var corpo := host.get_parent() if host != null else null
	var salute = corpo.get("health_system") if corpo != null else null
	if salute == null or not salute.has_method("drain"):
		return
	var tutto : float = float(salute.get("total_health")) * frazione_vita + danno_fisso
	salute.drain(tutto / duration * host.damage_multiplier(), "VELENO")


func decay_meter(delta : float) -> void:
	if is_active() or meter <= 0.0:
		return
	if _fermo > 0.0:
		_fermo -= delta
		return
	meter = maxf(0.0, meter - decay_per_sec * delta)
	meter_changed.emit(accumulo())
