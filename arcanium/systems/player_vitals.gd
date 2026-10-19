extends Node
class_name PlayerVitals

## Pool vitali del protagonista non gestiti dall'HealthSystem del template:
##  - STAMINA: consumata da azioni (attacchi/dash), rigenera dopo un ritardo.
##  - ARCANIUM VIVO: pool per magie/evocazioni (l'"eco" risonante del portatore).
##
## L'Arcanium CRISTALLIZZATO (valuta) NON sta qui: vive nell'autoload CrystalBank
## perché deve sopravvivere al reload di scena alla morte del player.
##
## Sinergia con lo status system: se assegnato uno StatusHost, l'Erosione dell'Eco
## sopprime la regen di stamina (regen_mult) e drena l'Arcanium Vivo.

@export var max_stamina : float = 100.0
@export var stamina_regen : float = 25.0      ## /s
@export var stamina_regen_delay : float = 0.5 ## s di attesa dopo l'ultima spesa

@export var max_arcanium : float = 30.0
## Rigenerazione Arcanium Vivo. 0 = pool fisso di 30, NON si auto-rimpingua: la
## capacità/il refill arriveranno col meccanismo dei summon all'Hub dell'Ordine.
@export var arcanium_regen : float = 0.0      ## /s

## Facoltativo: se assegnato, l'Erosione dell'Eco ne condiziona stamina/arcanium.
@export var status_host : StatusHost

var stamina : float
var arcanium : float

var _stamina_delay_timer : float = 0.0

signal stamina_changed(current : float, maximum : float)
signal arcanium_changed(current : float, maximum : float)

func _ready() -> void:
	stamina = max_stamina
	arcanium = max_arcanium
	# Emissione iniziale per popolare la HUD.
	stamina_changed.emit(stamina, max_stamina)
	arcanium_changed.emit(arcanium, max_arcanium)

func _process(delta : float) -> void:
	# Erosione dell'Eco: sopprime la regen stamina e drena l'Arcanium Vivo.
	var regen_mult := 1.0
	if status_host:
		var echo := status_host.get_effect("echo_erosion")
		if echo and echo is EchoErosionEffect and echo.is_active():
			regen_mult = echo.stamina_regen_mult()
			_drain_arcanium(echo.drain * delta)
		# Lacerazione: rigenerazione ferma e un lieve drain di stamina.
		var lac := status_host.get_effect("laceration")
		if lac and lac is LacerationEffect and lac.is_active():
			regen_mult = 0.0
			_set_stamina(maxf(0.0, stamina - lac.stamina_da_togliere(delta)))

	if _stamina_delay_timer > 0.0:
		_stamina_delay_timer = maxf(0.0, _stamina_delay_timer - delta)
	elif stamina < max_stamina:
		_set_stamina(minf(max_stamina, stamina + stamina_regen * regen_mult * delta))

	if arcanium < max_arcanium:
		_set_arcanium(minf(max_arcanium, arcanium + arcanium_regen * delta))

## ─── Ratii per la HUD ────────────────────────────────────────────────────────
func stamina_ratio() -> float:
	return stamina / max_stamina if max_stamina > 0.0 else 0.0

func arcanium_ratio() -> float:
	return arcanium / max_arcanium if max_arcanium > 0.0 else 0.0

## ─── Spesa / guadagno ────────────────────────────────────────────────────────
## Ritorna true se c'era abbastanza stamina (azione consentita).
func spend_stamina(amount : float) -> bool:
	if stamina < amount:
		return false
	_set_stamina(stamina - amount)
	_stamina_delay_timer = stamina_regen_delay
	return true

func spend_arcanium(amount : float) -> bool:
	if arcanium < amount:
		return false
	_set_arcanium(arcanium - amount)
	return true

## Hook minimo per il respawn della Traccia Perduta (traccia_perduta_director.gd):
## rabbocca entrambi i pool al massimo ed emette i segnali per la HUD.
func refill_all() -> void:
	_set_stamina(max_stamina)
	_set_arcanium(max_arcanium)

## Drenaggio da FUORI (l'Eco Radicata Guasta che beve): toglie fino ad
## `amount` e dice quanto ha tolto davvero — chi beve si cura di quello.
func drena_arcanium(amount : float) -> float:
	var tolto : float = minf(maxf(amount, 0.0), arcanium)
	if tolto > 0.0:
		_set_arcanium(arcanium - tolto)
	return tolto

func _drain_arcanium(amount : float) -> void:
	if arcanium <= 0.0:
		return
	_set_arcanium(maxf(0.0, arcanium - amount))

func _set_stamina(v : float) -> void:
	stamina = v
	stamina_changed.emit(stamina, max_stamina)

func _set_arcanium(v : float) -> void:
	arcanium = v
	arcanium_changed.emit(arcanium, max_arcanium)
