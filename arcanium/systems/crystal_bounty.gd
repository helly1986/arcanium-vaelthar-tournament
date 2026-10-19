extends Node
class_name CrystalBounty

## Taglia in Arcanium Cristallizzato: da appendere a un nemico. Quando il suo
## HealthSystem emette `died`, accredita `amount` cristalli su CrystalBank.
##
## Drop-in per i nemici della Fase 4 (oggi nessun mob in scena: il Golem di
## Arcanium non compare finché non abbiamo mesh — c'è solo la lore).

@export var amount : int = 10
## HealthSystem del nemico. Se null, cerca tra fratelli/genitore.
@export var health_system : HealthSystem

var _awarded : bool = false

func _ready() -> void:
	if health_system == null:
		health_system = _find_health_system()
	if health_system and health_system.has_signal("died"):
		health_system.died.connect(_on_died)

func _find_health_system() -> HealthSystem:
	var host := get_parent()
	if host == null:
		return null
	for c in host.get_children():
		if c is HealthSystem:
			return c
	return null

func _on_died() -> void:
	if _awarded:
		return
	_awarded = true
	var bank := get_node_or_null("/root/CrystalBank")
	if bank == null:
		return
	## L'Anello dell'Arco d'Ambra (e ogni pezzo con `arcanium_bonus`) aumenta la
	## taglia. Si applica QUI e non sul saldo: il bonus vale su cio' che si
	## guadagna, non su cio' che si ha gia' in tasca.
	var mult := 1.0
	var loadout := get_node_or_null("/root/EquipmentLoadout")
	if loadout and loadout.has_method("arcanium_multiplier"):
		mult = loadout.arcanium_multiplier()
	bank.add(int(round(float(amount) * mult)))
