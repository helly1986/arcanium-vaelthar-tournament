extends StatusEffect

## ⚠️ Niente `class_name`: si importa con `preload` (status_host.gd).

## Ghiacciato — il gradino dopo il Congelamento (Baluardo del Freddo, 2026-11-07, regole
## dell'autore). Si accumula SOLO su chi e' gia' congelato, coi colpi che congelano: a
## soglia il bersaglio resta COMPLETAMENTE IMMOBILE per 10 secondi (ArcaniumEnemy ferma
## movimento e animazioni) e perde 5 punti vita al secondo. Il fuoco lo scioglie subito
## (StatusHost.cauterizza). Uno Schianto lo frantuma: ×2 e il ghiaccio si rompe
## (ArcaniumHealthSystem._route_statuses).

@export var threshold : float = 100.0
@export var decay_per_sec : float = 10.0
@export var danno_al_secondo : float = 5.0

## Letto da StatusHost.moltiplicatore_velocita.
var slow_multiplier : float = 0.0
@export var vuln_taglio : float = 1.2
@export var vuln_perforazione : float = 1.2
@export var vuln_schianto : float = 2.0

var meter : float = 0.0
var _al_morso : float = 0.0

signal meter_changed(ratio : float)


func _init() -> void:
	id = "ghiacciato"
	label = "Frozen Solid"
	icon = "🧊"
	color = Color("#cfeeff")
	duration = 10.0


func damage_multiplier_for(dtype : String) -> float:
	match dtype:
		"TAGLIO": return vuln_taglio
		"PERFORAZIONE": return vuln_perforazione
		"SCHIANTO": return vuln_schianto
		_: return 1.0


func accumulo() -> float:
	return clampf(meter / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0


func add_buildup(amount : float) -> void:
	if is_active() or amount <= 0.0:
		return
	meter = minf(threshold, meter + amount)
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
	if salute != null and salute.has_method("drain"):
		salute.drain(danno_al_secondo * host.damage_multiplier(), "CRIO")


func decay_meter(delta : float) -> void:
	if is_active() or meter <= 0.0:
		return
	meter = maxf(0.0, meter - decay_per_sec * delta)
	meter_changed.emit(accumulo())
