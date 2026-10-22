extends Node
## Rende invisibile l'arma nel mount "riposto" di un EquipmentSystem e visibile
## quella impugnata. Lo switch resta funzionante (le armi si scambiano di mount),
## ma l'arma non usata non viene mostrata (es. sulla schiena).
## Non modifica il template: si aggancia via segnale equipment_changed.

@export var weapon_system : EquipmentSystem

func _ready() -> void:
	if weapon_system == null:
		return
	# Aspetta che EquipmentSystem._ready abbia impostato i mount.
	await get_tree().process_frame
	if weapon_system.has_signal("equipment_changed"):
		weapon_system.equipment_changed.connect(_on_changed)
	_refresh()

func _on_changed(_new_equipment = null) -> void:
	# Il segnale arriva dopo il reparent: aggiorna le visibilità.
	_refresh()

func _refresh() -> void:
	_set_visible(weapon_system.held_mount_point, true)
	_set_visible(weapon_system.stored_mount_point, false)

func _set_visible(mount: Node3D, vis: bool) -> void:
	if mount and mount.get_child_count() > 0:
		var w := mount.get_child(0) as Node3D
		if w:
			## HeldWeapon puo' aver nascosto il gadget impugnato (lo scudo senza
			## scudo nell'armadio, la sinistra che serve all'arco o all'arma a due
			## mani): quel segno vince.
			w.visible = vis and not w.get_meta("nascosto_da_held_weapon", false)
