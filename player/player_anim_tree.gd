extends AnimationTree
class_name AnimationTreeSoulsBase

## A companion to the SoulsCharacterBase, expects a lot of specific signals and will react to them
## by triggering oneshot animations, switching trees, blending run types, etc. This is really 
## the meat of the souls modules since so much relies on animations and their timing.
## Most of the difficulty comes from when the movement tree changes from one weapon type to another.
## There are many ways to approach transitioning between different movement trees,
## I simply found this to be most convenient.

@export var player_node : CharacterBody3D
@onready var base_state_machine : AnimationNodeStateMachinePlayback = self["parameters/MovementStates/playback"]
#@onready var ladder_state_machine = self["parameters/MovementStates/LADDER_tree/playback"]
@onready var current_weapon_tree : AnimationNodeStateMachinePlayback
@onready var weapon_type : String = "SLASH"
@onready var gadget_type : String = "SHIELD"
@onready var interact_type :String = "GENERIC"
@onready var current_item : ItemResource
@export var max_attack_count : int = 2 ## how many attacks you have in the attack tree
@onready var attack_count = 1 ## Used in the anim state tree. The oneShot for the
## ATTACK_tree, under SLASH and HEAVY each route to an animation will use this 
## variable under it's advanced expression to know which route to take.
@onready var hurt_count = 1

@onready var anim_length

@onready var landing_type = "SOFT"
var last_oneshot = "Attack"
var lerp_movement

var guard_value :float = 0.0

signal animation_measured
## Durata della clip di ATTACCO appena partita (solo quelle: vedi _is_attack_clip).
signal attack_measured(length : float)

func _ready():
	if !player_node:
		push_warning(str(self) + ": Player node must be set")
		
	player_node.dodge_started.connect(_on_dodge_started)
	player_node.jump_started.connect(_on_jump_started)
	player_node.sprint_started.connect(_on_sprint_started)
	player_node.landed_fall.connect(_on_landed_fall)
	
	player_node.interact_started.connect(_on_interact_started)
	player_node.climb_started.connect(_on_climb_start)
	#player_node.ladder_finished.connect(_on_ladder_finished)

	player_node.weapon_change_started.connect(_on_weapon_change_started)
	player_node.weapon_change_ended.connect(_on_weapon_change_ended)
	player_node.attack_started.connect(_on_attack_started)
	
	player_node.gadget_change_started.connect(_on_gadget_change_started)
	player_node.gadget_change_ended.connect(_on_gadget_change_ended)
	player_node.gadget_started.connect(_on_gadget_started)
	
	player_node.item_change_started.connect(_on_item_change_started)
	player_node.item_change_ended.connect(_on_item_change_ended)
	player_node.use_item_started.connect(_on_use_item_started)
		
	player_node.parry_started.connect(_on_parry_started)
	player_node.hurt_started.connect(_on_hurt_started)
	player_node.block_started.connect(_on_block_started)
	player_node.riposte_started.connect(_on_riposte_started)
	player_node.backstab_started.connect(_on_backstab_started)

	player_node.death_started.connect(_on_death_started)

	_on_weapon_change_ended(player_node.weapon_type)
	_on_gadget_change_ended(player_node.gadget_type)
	_on_item_change_ended(player_node.current_item)

	_salta_risveglio_se_non_serve()


## ─── IL RISVEGLIO VA SOLO DOPO LA MORTE ─────────────────────────────────────
## La state machine ha la catena `Start → Spawn → SLASH_tree` cablata nel
## percorso d'ingresso: il protagonista si rialza da terra **ogni volta che
## l'AnimationTree si inizializza**, cioè a ogni caricamento di scena. Uscire
## dalla Traccia e rientrare al Crocevia lo faceva risvegliare come se fosse
## appena morto.
##
## È giusto solo dopo una morte: lì il risveglio È il racconto. Attraversare una
## porta no — chi cammina da una scena all'altra ci arriva in piedi.
##
## ⚠️ Non si tocca la transizione nel .tscn: la si SCAVALCA. Modificare a mano
## le transizioni di una state machine dentro un file di scena è il modo più
## rapido per romperne una che oggi funziona, e questa serve ancora.
func _salta_risveglio_se_non_serve() -> void:
	var cm := get_node_or_null("/root/CheckpointManager")
	var da_morte : bool = cm != null and cm.get("risveglio_da_morte") == true
	if da_morte:
		## Consumato: la prossima scena non deve ereditarlo.
		cm.set("risveglio_da_morte", false)
		return
	## Un frame di attesa: al `_ready` la playback della state machine non ha
	## ancora fatto il primo passo, e un `travel` chiesto adesso verrebbe
	## sovrascritto dall'ingresso automatico su "Spawn".
	await get_tree().process_frame
	if is_instance_valid(player_node) and not player_node.is_dead:
		revive_from_death()
	
func _process(_delta):
	
	if player_node.strafing:
		set_strafe()
	else:
		set_free_move()
		
	if player_node.current_state == player_node.state.CLIMB:
		set_ladder()
		
	set_guarding()


func request_oneshot(oneshot:String):
	last_oneshot = oneshot
	set("parameters/" + oneshot + "/request",true)

## Vero se l'albero contiene DAVVERO un nodo con questo nome.
##
## ⚠️ Serve perché chiedere un oneshot inesistente non dà nessun errore:
## `set("parameters/Fantasma/request", true)` su un parametro che non c'è viene
## ignorato in silenzio. Nessuna clip parte, quindi `animation_measured` non
## scatta mai, e chi la stava aspettando resta appeso: `trigger_event()` del
## player lascia `busy = true` per sempre e i comandi non rispondono più.
## Un nodo che manca deve diventare "niente gesto", non un blocco.
func has_oneshot(oneshot : String) -> bool:
	return tree_root is AnimationNodeBlendTree and tree_root.has_node(oneshot)

func _on_landed_fall(_hard_or_soft = "HARD"):
	landing_type = _hard_or_soft
	request_oneshot("Landed")

func set_guarding():
	if player_node.guarding && !player_node.busy:
		guard_value = 1
	else:
		guard_value = 0
	var new_blend = lerp(get("parameters/Guarding/blend_amount"),guard_value,.2)
	set("parameters/Guarding/blend_amount", new_blend)

func _on_parry_started():
	request_oneshot("Parry")

func _on_riposte_started():
	request_oneshot("Riposte")

func _on_backstab_started():
	request_oneshot("Backstab")

func _on_attack_started():
	request_oneshot("Attack")
	# L'attesa serve a far valutare al tree l'espressione su `attack_count` PRIMA
	# di incrementarlo, altrimenti il primo click partirebbe già dal secondo
	# fendente. Il contatore avanza qui e torna a 1 solo quando la catena muore,
	# per mano del player (vedi reset_attack_chain).
	await animation_measured
	attack_count += 1
	if attack_count > max_attack_count:
		attack_count = 1


func _on_block_started():
	request_oneshot("Block")

func _on_hurt_started(): ## Picks a hurt animation between "Hurt1" and "Hurt2"
	if player_node.current_state == player_node.state.CLIMB:
		hurt_count = 3
	else:
		abort_oneshot(last_oneshot)
		hurt_count = randi_range(1,2)
		request_oneshot("Hurt")
		current_weapon_tree.start("MoveStrafe")
		
func abort_oneshot(_last_oneshot:String):
	set("parameters/" + _last_oneshot + "/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

	
func _on_death_started():
	base_state_machine.travel("Death")

## Riporta l'albero fuori dallo stato di morte, all'albero di movimento dell'arma
## in mano. Serve al respawn ai Coni: `revive()` rimetteva a posto le variabili
## del player (stato, velocità, is_dead) ma NESSUNO riportava indietro la state
## machine, che restava parcheggiata su "Death" — il player rinasceva a terra e
## si limitava a ruotare sul posto, perché la posa era ancora quella del cadavere.
func revive_from_death() -> void:
	var tree_name := weapon_type + "_tree"
	if tree_root.get_node("MovementStates").has_node(tree_name):
		base_state_machine.travel(tree_name)
	else:
		base_state_machine.travel("SLASH_tree")

func _on_use_item_started():
	request_oneshot("UseItem")

func _on_gadget_started():
	request_oneshot("Gadget")

func _on_sprint_started():
	base_state_machine.travel("SPRINT_tree")
	
func _on_dodge_started():
	request_oneshot("Dodge")

func _on_interact_started(_new_interact_type):
	interact_type = _new_interact_type
	await get_tree().process_frame
	request_oneshot("Interacts")
			

func _on_jump_started():
	request_oneshot("Jump")

func _on_weapon_change_started():
	request_oneshot("WeaponChange")

func _on_weapon_change_ended(_new_weapon_type):
	# if a wapon tree exixts, swap to it, otherwise, just use the "SLASH_tree" for rmovements.
	var weapon_tree_exists = tree_root.get_node("MovementStates").has_node(str(_new_weapon_type)+"_tree")
	if weapon_tree_exists:
		weapon_type = _new_weapon_type
	else:
		weapon_type = "SLASH"
	## `weapon_type` e non `_new_weapon_type`: il ripiego appena calcolato
	## andava buttato via un rigo dopo. Con un tipo senza sotto-albero il path
	## non risolveva e `current_weapon_tree` restava null — il player smetteva
	## di attaccare, e la causa era due righe sopra a dire il contrario.
	current_weapon_tree = get("parameters/MovementStates/" + weapon_type + "_tree/playback")

func _on_gadget_change_started():
	request_oneshot("GadgetChange")

func _on_gadget_change_ended(_new_gadget_type):
	gadget_type = _new_gadget_type

func _on_item_change_started():
	request_oneshot("ItemChange")

func _on_item_change_ended(_new_item):
	current_item = _new_item

func _on_climb_start():
	#set("parameters/MovementStates/LADDER_tree/LadderBlender/blend_position",0)
	#base_state_machine.start("LADDER_tree")
	base_state_machine.travel("LADDER_tree")
	#ladder_state_machine.travel("LadderStart_" + top_or_bottom)
	
#func _on_ladder_finished(top_or_bottom):
	##ladder_state_machine.travel("LadderEnd_" + top_or_bottom)
	#pass
	
func set_ladder():
	#set("parameters/MovementStates/LADDER_tree/LadderBlend/blend_position",-player_node.input_dir.y)
	#var ladder_frame = get("parameters/MovementStates/LADDER_tree/LadderBlender/blend_position")
	#print(ladder_frame)
	#if ladder_frame > 1:
		#ladder_frame = 0
	#elif ladder_frame < 0:
		#ladder_frame = 1
	#set("parameters/MovementStates/LADDER_tree/LadderBlender/blend_position",ladder_frame - (player_node.input_dir.y * .015)) # otherwise, play the animation at the speed of player input (* a speed if climb anim is slow)
	print(player_node.input_dir.y)
	set("parameters/MovementStates/LADDER_tree/LadderTime/scale",-player_node.input_dir.y)
			
func set_strafe():
	# Strafe left and right animations run by the player's velocity cross product
	# Forward and back are acording to input, since direction changes by fixed camera orientation
	var new_blend = Vector2(player_node.strafe_cross_product,player_node.move_dot_product)
	#if player_node.current_state == player_node.state.DYNAMIC_ACTION:
	if player_node.slowed:
		new_blend *= .25 # Force a walk animiation
	else:
		# apply input as a magnatude for more natural run versus walk animation blending
		new_blend *= Vector2(abs(player_node.input_dir.x),abs(player_node.input_dir.y)) 
	lerp_movement = get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position")
	lerp_movement = lerp(lerp_movement,new_blend,.2)
	set("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position", lerp_movement)

func set_free_move():
	# Non-strafing "free" movement, is just the forward input direction.
	var new_blend = Vector2(0,abs(player_node.input_dir.x) + abs(player_node.input_dir.y))
	if player_node.slowed:
		new_blend *= .4 # force a walk speed
	lerp_movement = get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position")
	lerp_movement = lerp(lerp_movement,new_blend,.2)
	set("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position",lerp_movement)


func _on_animation_started(anim_name):
	anim_length = get_node(anim_player).get_animation(anim_name).length
	animation_measured.emit(anim_length)
	# Misura DEDICATA agli attacchi. `animation_measured` scatta per qualunque
	# clip parta, camminata compresa: chi deve sapere quanto dura il FENDENTE non
	# può fidarsi di quel segnale, perché rischia di ricevere la durata di
	# tutt'altro e chiudere l'attacco troppo presto (è così che il one-shot
	# ripartiva a metà e l'animazione sembrava spezzarsi).
	if _is_attack_clip(str(anim_name)):
		attack_measured.emit(anim_length)

## Le clip d'attacco del protagonista, per convenzione del pack: "root-Slash1..3"
## e "root-Heavy1..2" per i colpi da fermo, più le varianti situazionali
## (JumpAttack, SprintAttack, Uppercut). Il prefisso "root-" sui pesanti è
## necessario: senza, si beccherebbero anche "HeavyIdle" e "HeavyFalling", che
## sono locomozione e falserebbero la durata dell'attacco.
func _is_attack_clip(anim_name : String) -> bool:
	return anim_name.contains("Slash") \
		or anim_name.contains("root-Heavy") \
		or anim_name.contains("Attack") \
		or anim_name.contains("Uppercut") \
		or anim_name.contains("Tiro")   # l'arco (ArcoLib/Tiro, arcieria_player.gd)

## Riporta la catena al primo colpo. La decisione di QUANDO farlo sta nel player
## (vedi `combo_grace`): qui c'era un timer parallelo che azzerava il contatore
## 0.2 s dopo la clip, in disaccordo con la finestra del player — due orologi
## sullo stesso stato, e vinceva quello sbagliato.
func reset_attack_chain() -> void:
	attack_count = 1
