extends StatusEffect

## ⚠️ Niente `class_name`: si importa con `preload` (status_host.gd).

## Bruciatura — chiesta dall'autore per il Lascito del Bruciante (2026-11-07). A
## BUILD-UP come la Lacerazione: ogni colpo che brucia riempie la barra, e a
## `threshold` SCATTA. Ma la Lacerazione e' una ferita che si apre di colpo, questa
## e' un fuoco che resta: per `duration` secondi consuma una quota della vita massima
## a piccoli morsi, non mitigati (`drain` dell'health system, che uccide se arriva a
## 0). Mentre brucia i colpi non ricaricano.
##
## Da dove viene (regole dell'autore): ROSSO dal fuoco, TEAL dal fuoco spirituale, che
## accumula piu' lentamente ma fa piu' danno, perche' brucia fino all'anima. Lo decide
## l'ultimo colpo che accumula, e resta finche' brucia.

const ROSSO := Color("#e0391c")
const TEAL := Color("#2fd6c4")
const ACCUMULO_SPIRITUALE := 0.7
const DANNO_SPIRITUALE := 1.5

@export var threshold : float = 100.0
@export var decay_per_sec : float = 10.0
## Dopo un colpo la barra resta ferma per questo tempo, poi cala.
@export var ritardo_decadimento : float = 2.0
## Quanto consuma in tutto: quota della vita MASSIMA, piu' un fisso.
@export var frazione_vita : float = 0.12
@export var danno_fisso : float = 8.0
## Ogni quanti secondi morde.
@export var intervallo : float = 0.5

var meter : float = 0.0
var spirituale : bool = false
var _fermo : float = 0.0
var _al_morso : float = 0.0

signal meter_changed(ratio : float)


func _init() -> void:
	id = "burn"
	label = "Burn"
	icon = "🔥"
	color = ROSSO
	duration = 6.0


## Rapporto di riempimento della barra, 0..1 (per la HUD).
func accumulo() -> float:
	return clampf(meter / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0


func add_buildup(amount : float, dello_spirito : bool = false) -> void:
	if is_active() or amount <= 0.0:
		return
	spirituale = dello_spirito
	color = TEAL if spirituale else ROSSO
	meter = minf(threshold, meter + amount * (ACCUMULO_SPIRITUALE if spirituale else 1.0))
	_fermo = ritardo_decadimento
	meter_changed.emit(accumulo())
	if meter >= threshold:
		meter = 0.0
		meter_changed.emit(0.0)
		trigger()


func on_apply() -> void:
	_al_morso = intervallo


func on_tick(delta : float) -> void:
	_al_morso -= delta
	if _al_morso > 0.0:
		return
	_al_morso += intervallo
	var hs := _health_system()
	if hs == null or not hs.has_method("drain"):
		return
	var tutto : float = float(hs.get("total_health")) * frazione_vita + danno_fisso
	if spirituale:
		tutto *= DANNO_SPIRITUALE
	var host := get_parent()
	if host != null and host.has_method("damage_multiplier"):
		tutto *= host.damage_multiplier()
	hs.drain(tutto * intervallo / duration, "FUOCO")
	## Ogni morso e' fuoco che arriva: cauterizza e scioglie (StatusHost.cauterizza).
	if host != null and host.has_method("cauterizza"):
		host.cauterizza()


func decay_meter(delta : float) -> void:
	if is_active() or meter <= 0.0:
		return
	if _fermo > 0.0:
		_fermo -= delta
		return
	meter = maxf(0.0, meter - decay_per_sec * delta)
	meter_changed.emit(accumulo())


## L'health system dello stesso corpo, come per la Lacerazione.
func _health_system() -> Node:
	var host := get_parent()
	var corpo := host.get_parent() if host != null else null
	if corpo != null and "health_system" in corpo and corpo.health_system != null:
		return corpo.health_system
	if corpo != null:
		return corpo.get_node_or_null("HealthSystem")
	return null
