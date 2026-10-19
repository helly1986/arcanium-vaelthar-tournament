extends Node
class_name MarcheWielder

## Ponte tra le Marche del portatore e lo scaling delle armi. Da appendere come
## figlio del player (o di qualunque entità che impugna armi Arcanium).
##
## Tiene un MarcheStats e, ad ogni cambio arma (o al ready), ricalcola il `power`
## effettivo dell'ArcaniumEquipmentResource impugnata via `compute_power(stats)`.
## Così lo scaling per Marca è realmente collegato al combattimento: NON serve
## modificare EquipmentSystem né player_charbody3D — restano contract-compatibili.
##
## Setup in editor: basta assegnare `stats` (una MarcheStats .tres o inline).
## `equipment_system`/`gadget_system` si auto-risolvono dal player genitore (che
## espone già `weapon_system`/`gadget_system`), quindi NON vanno collegati a mano
## — comodo perché il player è tipicamente una scena istanziata e i suoi nodi
## interni non sarebbero assegnabili via NodePath dall'esterno. Assegnali solo se
## questo nodo non è figlio diretto del player.

@export var stats : MarcheStats
@export var equipment_system : EquipmentSystem
@export var gadget_system : EquipmentSystem

func _ready() -> void:
	if stats == null:
		stats = MarcheStats.new()
	else:
		## COPIA per-partita. `stats` è tipicamente `marche_dawnkeep.tres`, e le
		## Resource caricate da disco sono CONDIVISE: senza duplicare, i punti
		## comprati salendo di livello finirebbero dentro il file di partenza —
		## validi per ogni partita futura, e in editor persino salvati su disco.
		stats = stats.duplicate()

	## I punti già comprati stanno in MarcheProgression, non nel .tres: vanno
	## riapplicati su questa copia fresca a ogni caricamento.
	var prog := get_node_or_null("/root/MarcheProgression")
	if prog and prog.has_method("applica_a"):
		prog.applica_a(stats)

	# Auto-risoluzione dal player genitore se non assegnati in editor.
	var host = get_parent()
	if equipment_system == null and host and "weapon_system" in host:
		equipment_system = host.weapon_system
	if gadget_system == null and host and "gadget_system" in host:
		gadget_system = host.gadget_system

	if equipment_system:
		equipment_system.equipment_changed.connect(_on_equipment_changed)
	if gadget_system:
		gadget_system.equipment_changed.connect(_on_equipment_changed)

	# Il template equipaggia l'arma iniziale in _ready SENZA emettere
	# equipment_changed: ricalcoliamo dopo un frame quando i mount sono pronti.
	await get_tree().process_frame
	_recompute(equipment_system)
	_recompute(gadget_system)

func _on_equipment_changed(new_equipment : EquipmentObject) -> void:
	_apply_scaling(new_equipment)

func _recompute(system : EquipmentSystem) -> void:
	if system and system.current_equipment:
		_apply_scaling(system.current_equipment)

func _apply_scaling(equipment : EquipmentObject) -> void:
	if equipment == null:
		return
	var info = equipment.equipment_info
	if info is ArcaniumEquipmentResource:
		info.compute_power(stats)

## Da chiamare dopo un level-up ai Coni di Canalizzazione per riscalare l'arma
## attualmente impugnata.
func refresh() -> void:
	_recompute(equipment_system)
	_recompute(gadget_system)
