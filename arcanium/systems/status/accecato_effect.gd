extends StatusEffect

## ⚠️ Niente `class_name`: si importa con `preload` (status_host.gd).
## Blinded by Light — lo stato del Sacro (2026-11-07, regole dell'autore). A build-up: a
## soglia arriva un ingente danno tutto insieme, e per 10 secondi non ci si vede: il
## giocatore perde il lock-on (player_charbody3D), i nemici attaccano alla cieca
## (ArcaniumEnemy._alla_cieca).

@export var threshold : float = 100.0
@export var decay_per_sec : float = 6.0
@export var ritardo_decadimento : float = 3.0
## Lo scatto: quota della vita MASSIMA, piu' un fisso.
@export var frazione_vita : float = 0.15
@export var danno_fisso : float = 10.0

var meter : float = 0.0
var _fermo : float = 0.0

signal meter_changed(ratio : float)


func _init() -> void:
	id = "accecato"
	label = "Blinded by Light"
	icon = "☀"
	color = Color("#fff1a8")
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
	var host := get_parent()
	var corpo := host.get_parent() if host != null else null
	var salute = corpo.get("health_system") if corpo != null else null
	if salute != null and salute.has_method("drain"):
		salute.drain(float(salute.get("total_health")) * frazione_vita + danno_fisso, "SACRO")


func decay_meter(delta : float) -> void:
	if is_active() or meter <= 0.0:
		return
	if _fermo > 0.0:
		_fermo -= delta
		return
	meter = maxf(0.0, meter - decay_per_sec * delta)
	meter_changed.emit(accumulo())
