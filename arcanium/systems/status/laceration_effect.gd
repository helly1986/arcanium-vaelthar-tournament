extends StatusEffect
class_name LacerationEffect

## Lacerazione — il sanguinamento di Arcanium (chiesto dall'utente il
## 2026-09-26: «tipo sanguinamento di Elden Ring»). Meccanica di BUILD-UP come
## Erosione dell'Eco e Congelamento: ogni colpo che lacera (una spina, un
## rampicante) riempie la barra; a `threshold` SCATTA:
##
##   1. subito, un colpo secco agli HP: `frazione_vita` della vita massima più
##      `danno_fisso`, NON mitigato (le difese non fermano una ferita che si
##      apre da dentro) — è `drain` dell'health system, che uccide se arriva a 0;
##   2. per `duration` secondi, un lieve drain di STAMINA con la rigenerazione
##      ferma (lo applica `PlayerVitals`, come fa con l'Erosione). È ciò che
##      rende la lacerazione pericolosa DOPO: si scappa col fiato corto.
##
## La barra cala se si smette di prendere colpi: va tenuta la pressione. Mentre
## lo scatto è attivo i colpi non ricaricano (come l'Erosione).
##
## Chi PARA con lo scudo non accumula: il colpo parato passa da `apply_damage`,
## che non instrada gli status.

@export var threshold : float = 100.0
@export var decay_per_sec : float = 8.0
## Dopo ogni colpo la barra resta FERMA per questo tempo, poi cala. Senza, fra
## una frustata e l'altra del Mago (clip + recupero + cooldown, ~5 s) la barra
## si svuotava e la lacerazione non scattava mai (misurato in campo il
## 2026-09-26). È il sanguinamento di Elden Ring: si accumula su una sequenza
## di colpi, non solo su una raffica.
@export var ritardo_decadimento : float = 5.0
## Lo scatto: quota della vita MASSIMA, più un fisso.
@export var frazione_vita : float = 0.22
@export var danno_fisso : float = 6.0
## Stamina tolta al secondo mentre attiva (e la rigenerazione è ferma).
@export var drain_stamina : float = 5.0

var meter : float = 0.0
var _fermo : float = 0.0

## Emesso allo scatto, col danno inflitto (per effetti e numeri a schermo).
signal lacerato(danno : float)
## Emesso quando la barra cambia: meter/threshold.
signal meter_changed(ratio : float)

func _init() -> void:
	id = "laceration"
	label = "Lacerazione"
	icon = "🩸"
	color = Color("#c0202a")
	duration = 5.0

## Rapporto di riempimento della barra, 0..1 (per la HUD).
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
	var hs := _health_system()
	if hs == null:
		return
	var danno : float = float(hs.get("total_health")) * frazione_vita + danno_fisso
	if hs.has_method("drain"):
		hs.drain(danno, "TAGLIO")
	lacerato.emit(danno)

## Stamina da togliere in questo frame (0 se non attiva). La chiede PlayerVitals.
func stamina_da_togliere(delta : float) -> float:
	return drain_stamina * delta if is_active() else 0.0

func decay_meter(delta : float) -> void:
	if is_active() or meter <= 0.0:
		return
	if _fermo > 0.0:
		_fermo -= delta
		return
	meter = maxf(0.0, meter - decay_per_sec * delta)
	meter_changed.emit(accumulo())

## L'health system dello stesso corpo: lo StatusHost è suo fratello, e il corpo
## lo espone come `health_system` (player e nemici).
func _health_system() -> Node:
	var host := get_parent()
	var corpo := host.get_parent() if host != null else null
	if corpo != null and "health_system" in corpo and corpo.health_system != null:
		return corpo.health_system
	if corpo != null:
		return corpo.get_node_or_null("HealthSystem")
	return null
