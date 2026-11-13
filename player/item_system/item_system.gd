extends Node3D
class_name ItemSystem

## This class is tied very closely to the Inventory system. It's purpose is to 
## place the current inventory item on the player's hip whenever items are changed
## it also manages throwing objects when the item used is a throwable.

@export var player_node : CharacterBody3D
@onready var hand_bone = $HandBone
@onready var mount_point = $HandBone/HandPivot

@onready var storage_bone = $StorageBone
@onready var storage_mount = $StorageBone/HipPivot

@export var signaling_node : Node
@export var use_item_signal : String = "item_used"
@export var throw_strength = 15

signal item_thrown
signal item_drunk

# Called when the node enters the scene tree for the first time.
func _ready():
	if signaling_node:
		if signaling_node.has_signal(use_item_signal):
			signaling_node.connect(use_item_signal, _on_item_used_signal)
		if signaling_node.has_signal("inventory_updated"):
			signaling_node.connect("inventory_updated", _on_inventory_updated)
		
func _on_inventory_updated(inventory):
	# This simply adds a visual version to your hip when you change/use items.
	var thekids = storage_mount.get_children()
	for kid in thekids:
		#print(kid)
		kid.queue_free()
	
	if inventory[0]:
		var current_item = inventory[0]
		if current_item.count > 0:
			if current_item.physical_instance:
				var item_instance = current_item.physical_instance
				var new_item :RigidBody3D = item_instance.instantiate()
				# pass ItemResource data to this new physical object
				storage_mount.call_deferred("add_child",new_item)
			
			

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _on_item_used_signal(_current_item : ItemResource):
	if _current_item != null:
		## Arcanium (2026-11-13): un lanciabile che sa lanciarsi da se' (l'ampolla,
		## ampolla_lanciata.gd) parte dalla MANO DESTRA quando la mano e' al PUNTO PIU' ALTO
		## del lancio (l'utente). Il segnale arriva all'INIZIO del gesto (l'inventario
		## ascolta `use_item_started`): da qui si segue il braccio vero, fotogramma per
		## fotogramma. Il percorso del template (mano sinistra, 0,8 s fissi, impulso dritto)
		## resta per gli altri oggetti.
		if _current_item.object_type == "THROWN" and _current_item.physical_instance:
			var lanciabile = _current_item.physical_instance.instantiate()
			if lanciabile.has_method("lancia"):
				## In mano destra per tutta la carica, poi via dalla cima.
				var presa := _presa_destra()
				if presa != null:
					presa.add_child(lanciabile)
				await _picco_della_mano()
				var da := _mano_destra()
				var mondo : Node = get_tree().current_scene if get_tree().current_scene != null else player_node.get_parent()
				if lanciabile.get_parent() != null:
					da = lanciabile.global_position
					lanciabile.reparent(mondo)
				else:
					mondo.add_child(lanciabile)
				lanciabile.lancia(player_node, da)
				item_thrown.emit()
				return
			lanciabile.queue_free()
		if _current_item.physical_instance:
			var item_instance = _current_item.physical_instance
			var new_item :RigidBody3D = item_instance.instantiate()
			# pass ItemResource data to this new physical object
			new_item.object_type = _current_item.object_type
			new_item.player_node = player_node
			mount_point.call_deferred("add_child",new_item)
			
			await get_tree().create_timer(.8).timeout
			new_item.activate()
			if new_item.object_type == "THROWN":
				item_thrown.emit()
				var force_dir = player_node.global_transform.basis.z
				#force_dir.y += .1
				new_item.apply_impulse(force_dir * throw_strength, mount_point.global_position)
			elif new_item.object_type == "DRINK":
				item_drunk.emit()


## La presa della mano destra: un BoneAttachment sullo scheletro della sinistra del
## template, creato la prima volta. Il lanciabile ci sta appeso durante la carica, col
## collo nel pugno (l'origine dell'ampolla e' il collo, prepara_ampolla.py).
var _presa : BoneAttachment3D
func _presa_destra() -> Node3D:
	if _presa != null:
		return _presa.get_node("Pugno")
	if not hand_bone.use_external_skeleton:
		return null
	_presa = BoneAttachment3D.new()
	_presa.name = "ManoDestra"
	add_child(_presa)
	_presa.use_external_skeleton = true
	_presa.external_skeleton = _presa.get_path_to(hand_bone.get_node(hand_bone.external_skeleton))
	_presa.bone_name = "RightHand"
	var pugno := Marker3D.new()
	pugno.name = "Pugno"
	## Nel palmo, poco oltre il polso; l'ampolla in piedi lungo le dita.
	pugno.position = Vector3(0.0, 0.08, 0.03)
	_presa.add_child(pugno)
	return pugno


## Quanto e' alta la mano destra sopra i piedi del player.
func altezza_mano_destra() -> float:
	return _mano_destra().y - player_node.global_position.y


## Aspetta che la mano destra salga (almeno `SALITA_LANCIO` sopra dov'era) e poi scenda
## di `CALO_LANCIO`: il rilascio e' la cima. La clip sale in due tempi (spalla, poi dietro
## la testa): un calo piccolo non basta a dire che e' finita. In fotogrammi di fisica,
## non in millisecondi (con --fixed-fps il tempo vero mente); con un tetto, se la clip
## non alza il braccio.
const SALITA_LANCIO := 0.4
const CALO_LANCIO := 0.04
func _picco_della_mano() -> void:
	var partenza := altezza_mano_destra()
	var cima := partenza
	for _f in 72:
		await get_tree().physics_frame
		var y := altezza_mano_destra()
		if y > cima:
			cima = y
		elif cima > partenza + SALITA_LANCIO and y < cima - CALO_LANCIO:
			return


## Dove sta la mano destra adesso: il lancio parte da li'. Lo scheletro e' quello della
## mano sinistra del template (HandBone, scheletro esterno).
func _mano_destra() -> Vector3:
	var scheletro := hand_bone.get_node_or_null(hand_bone.external_skeleton) as Skeleton3D if hand_bone.use_external_skeleton else null
	if scheletro != null:
		var osso := scheletro.find_bone("RightHand")
		if osso >= 0:
			return scheletro.global_transform * scheletro.get_bone_global_pose(osso).origin
	return player_node.global_position + Vector3.UP * 1.6
