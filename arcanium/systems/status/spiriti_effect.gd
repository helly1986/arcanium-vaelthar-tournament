extends StatusEffect

## ⚠️ Niente `class_name`: si importa con `preload` (status_host.gd).

## Gli SPIRITI RISVEGLIATI addosso a un bersaglio — Terra Risvegliata, la Lucida Tecnica
## della vanga di Aurin (2026-11-07). Per `duration` secondi rallentano e consumano la
## vita, senza accumulo: arrivano e basta. Se a uccidere e' proprio il loro morso, chi li
## ha mandati riprende tutto l'Arcanium speso e la meta' del danno inflitto come vita
## (`heal` si ferma alla vita massima: rientra solo se serve).

## Letto da chi muove il nemico (StatusHost.moltiplicatore_velocita).
@export var slow_multiplier : float = 0.55
@export var intervallo : float = 0.25
const NUTRIMENTO := 1.25

var danno_totale : float = 0.0
var lanciatore : Node = null
var costo : float = 0.0

## Quanto hanno tolto davvero, per il premio.
var inflitto : float = 0.0
var _al_morso : float = 0.0

signal ucciso(inflitto : float)


func _init() -> void:
	id = "spiriti"
	label = "Awakened Spirits"
	icon = "☠"
	color = Color("#c9f5d2")
	duration = 5.0


## Li manda addosso, o rinnova chi c'e' gia'.
func affida(danno : float, chi : Node, speso : float) -> void:
	## L'effetto resta sul bersaglio anche scaduto: il conto riparte da zero.
	if not is_active():
		inflitto = 0.0
	danno_totale = danno
	lanciatore = chi
	costo = speso
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
	var vita : float = float(hs.get("current_health"))
	if vita <= 0.0:
		return
	var morso : float = danno_totale * intervallo / duration * _nutrimento()
	inflitto += minf(morso, vita)
	hs.drain(morso, "VELENO")
	if float(hs.get("current_health")) <= 0.0:
		_premia()
		termina()


## Quanto mordono di piu': il sangue li chiama, il fuoco spirituale li nutre (quello rosso
## no), e la Frattura amplifica come ogni morso.
func _nutrimento() -> float:
	var host := get_parent()
	if host == null or not host.has_method("damage_multiplier"):
		return 1.0
	var mult : float = host.damage_multiplier()
	var sangue = host.get_effect("laceration")
	if sangue != null and sangue.is_active():
		mult *= NUTRIMENTO
	var fuoco = host.get_effect("burn")
	if fuoco != null and fuoco.is_active() and fuoco.spirituale:
		mult *= NUTRIMENTO
	return mult


func _premia() -> void:
	if is_instance_valid(lanciatore):
		var vitali = lanciatore.get("vitals")
		if vitali != null and vitali.has_method("recupera_arcanium"):
			vitali.recupera_arcanium(costo)
		var salute = lanciatore.get("health_system")
		if salute != null and salute.has_method("heal"):
			salute.heal(inflitto * 0.5)
	ucciso.emit(inflitto)


## L'health system dello stesso corpo, come per la Lacerazione.
func _health_system() -> Node:
	var host := get_parent()
	var corpo := host.get_parent() if host != null else null
	if corpo != null and "health_system" in corpo and corpo.health_system != null:
		return corpo.health_system
	if corpo != null:
		return corpo.get_node_or_null("HealthSystem")
	return null
