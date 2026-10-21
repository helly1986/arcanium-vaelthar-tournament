extends CharacterBody3D

## GOTCHA class_name (vedi arcanium-godot-mcp-setup): riferimento per PATH,
## indipendente dal registro globale che l'editor a volte non rilegge subito.
const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")
const PlacementController := preload("res://arcanium/systems/spells/placement_controller.gd")

@onready var sensor_cast : ShapeCast3D
@export var animation_tree : AnimationTree
@onready var anim_length = .5 # updates as new animnations start
signal event_finished

## ─── Integrazione Arcanium: stamina ──────────────────────────────────────────
## Se `vitals` è assegnato, le azioni consumano stamina e vengono BLOCCATE quando
## è insufficiente. Se null, il comportamento del template resta invariato (nessun
## costo). Modifica prevista dal piano (vedi Fase 0: edit consentiti al player).
@export var vitals : PlayerVitals
@export var cost_attack : float = 18.0
@export var cost_attack_strong : float = 28.0
@export var cost_dodge : float = 22.0
@export var cost_sprint : float = 8.0
@export var cost_gadget : float = 14.0
@export var cost_jump : float = 12.0

## ─── Integrazione Arcanium: incantesimi (Sigillo/Crio) ───────────────────────
## SpellCaster e SpellSelection vengono creati a runtime in _ready (niente edit
## alla scena da 1900 righe). Il Sigillo (arma_secondaria) "dà voce al ghiaccio":
## su `cast_spell` si lancia lo spell selezionato (di default lo Shard di Ghiaccio),
## spendendo arcanium via `vitals`. Offset di uscita del proiettile dal petto/mano.
var spell_caster : SpellCaster
var spell_selection : SpellSelection

## Esecutore delle Lucide Tecniche, nodo figlio nella scena (a differenza di
## SpellCaster, che è creato a runtime). Risolto in _ready: se manca, il ramo
## di input degrada in silenzio invece di far crashare l'intero _input.
var lucida_tecnica_caster : Node = null
## Esecutore delle tecniche di guerra imparate dai tomi (Legione Testuggine).
## Vedi `arcanium/systems/tecnica_guerra_caster.gd`.
var tecnica_guerra_caster : Node = null
## La tecnica di guerra il cui gesto e' IN CORSO, o null. La legge
## `EquipmentSystem._apply_hit` per dare al contatto il danno della tecnica
## invece di quello del fendente — come `secondary_action` per il colpo forte.
var tecnica_in_corso : Resource = null
@export var spell_muzzle_offset : Vector3 = Vector3(0.0, 1.4, 0.0)
@export var spell_muzzle_forward : float = 0.8
## Ritardo tra la pressione del tasto e la comparsa del proiettile, per farlo
## coincidere col momento in cui la mano si apre nell'animazione di cast.
## Da tarare a vista sull'anim di gadget.
@export_range(0.0, 1.5, 0.01) var spell_release_delay : float = 0.35
signal spell_cast_started(spell)
## Emesso quando si preme cast ma manca il Sigillo: l'HUD può lampeggiare un
## avviso ("serve il bastone").
signal spell_cast_blocked

## ─── Integrazione Arcanium: casting POSIZIONALE (decal a terra) ──────────────
## Gli spell con `is_positional = true` (es. Morsa del Gelo) non lanciano un
## proiettile su `cast_spell`: entrano in PLACEMENT MODE via PlacementController
## (generico — vedi placement_controller.gd).
## Movimento e attacco restano CONGELATI finché `placement_active` è true (vedi
## guardie in _input/set_root_move/rotate_player); la camera si aggancia al
## decal mobile (IsoCam.focus_target) e torna sul player al termine.
var placement_controller : PlacementController
## Raggio massimo (m) a cui il decal può allontanarsi dal player durante il
## piazzamento. Generico: vale per qualunque spell posizionale.
@export var placement_max_range : float = 8.0
var placement_active : bool = false
var _pending_positional_spell : ArcaniumSpellResource = null

## Integrazione Arcanium: quando true, TUTTI i comandi del player sono bloccati
## (morte per veleno scriptata: si guarda soltanto la fine). Vedi begin_poison_death().
var input_fully_locked : bool = false

## Prova a spendere stamina per un'azione. Ritorna true se l'azione è consentita.
func _try_spend_stamina(cost : float) -> bool:
	if vitals == null:
		return true
	return vitals.spend_stamina(cost)
## default/1st camera is a follow cam.
@onready var current_camera = get_viewport().get_camera_3d()

## Aids strafe rotation when alternating between cameras. I found it best to keep
## track of whatever the starting camera was, rather than update it if camera's change.
@onready var orientation_target = current_camera

## Interactables that update based on entering a Ladder Area or, the sensor_cast
## colliding with an interactable.
@onready var interactable : Node3D
@onready var ladder
signal climb_started
signal interact_started(interact_type)

## A generic EquipmentSystem class, used to manage moving Weapons 
## between a hand and sheathed location as well as activating collision hitbox 
## monitoring and reporting hits have happened. Very handy.
@export var weapon_system : EquipmentSystem

## A helper variable, tracks the current weapon type for easier referencing from
## the animation_tree and anywhere else that may want to know what weapon type is held.
var weapon_type :String = "SLASH"
signal weapon_change_started ## to start the animation
signal weapon_change_ended(weapon_type:String) ## informing the change is complete
signal attack_started ## to start the animation


## A helper variable for keyboard events across 2 key inputs "shift+ attack", etc.
## there may be a better way to capture combo key presses across multiple device types,
## but this worked for me in a pinch.
## ⚠️ Tipizzata e inizializzata: nasceva `null` finche' il primo evento di
## input non la metteva a false, e un attacco chiesto da codice prima di
## qualunque input (i cancelli headless) mandava `null` a `Suoni.fendente`.
var secondary_action : bool = false

## Gadgets and guarding equipment system that manages moving nodes from the 
## off-hand, to their hip location, the same EquipmentSystem as the weapon system.
@export var gadget_system : EquipmentSystem
## A helper variable, tracks the current gadget type for easier referencing from
## the AnimationStateTree or anywhere else that may need to know what gadget type is held.
var gadget_type :String = "SHIELD"
signal gadget_change_started ## to start the animation
signal gadget_change_ended(gadget_type:String) ## to end the animation
signal gadget_started ## when the gadget attack starts


## When guarding this substate is true. Drives animation and hitbox logic for blocking.
## The first moments of guarding, the parry window is active, allowing to parry()
## attacks and avoid damage


## Turns on when the perfect parry window is active, making regular blocks turn into parries.
@onready var parry_active = false
## How brief the perfect parry window is in seconds.
@export var parry_window = .3
signal parry_started
signal block_started

## ─── Integrazione Arcanium: scudo parziale + riposte ─────────────────────────
## Un parry riuscito apre questa finestra: il prossimo attack() entro
## `riposte_window` (se il bersaglio è in poise-break) scatena la Riposte invece
## di un affondo normale. Vedi parry() e attack().
var _riposte_window : float = 0.0
@export var riposte_window_duration : float = 1.2
signal riposte_started

## Backstab: attaccando da dietro un bersaglio del gruppo "targets", entro questa
## distanza e cono, scatta al posto dell'attacco normale (qualunque momento, non
## richiede parry/poise-break). `back_dot_threshold` vicino a -1 = quasi esattamente
## alle spalle; -0.6 lascia un margine ragionevole di ~127° di cono posteriore.
@export var backstab_range : float = 2.2
@export var back_dot_threshold : float = -0.6
signal backstab_started

## Il player deve GUARDARE la vittima di un finisher: entro questo cono davanti
## a se' (coseno; 0.26 = ~75 gradi per lato). Prima non contava: il critico
## sceglieva per sola distanza e `_start_finisher` girava il player di scatto,
## anche di 180 gradi. Trovato dal playtest automatico (2026-10-08): parata +
## critico che uccide un lupo dell'Alpha alle SPALLE del player. Il cono resta
## largo perche' il backstab arriva spesso con il player ruotato di ~50 gradi
## (vedi `_start_finisher`).
@export var finisher_facing_dot : float = 0.26

## Quanto `n` sta davanti al player (coseno fra il suo avanti e la direzione
## verso `n`, sul piano). La mesh guarda +Z.
func _dot_davanti(n : Node3D) -> float:
	var verso : Vector3 = n.global_position - global_position
	verso.y = 0.0
	var avanti : Vector3 = global_transform.basis.z
	avanti.y = 0.0
	if verso.length() < 0.01 or avanti.length() < 0.01:
		return 1.0
	return avanti.normalized().dot(verso.normalized())

## Critico: un bersaglio in poise-break entro il raggio del backstab, attaccato
## da qualunque angolo DEL NEMICO (non serve essere alle spalle), ma davanti al
## player. Riusa la clip Riposte (stessa animazione, presupposto di design:
## nessuna clip "critico" distinta nel pack — vedi piano combat). Fra piu'
## candidati vince il piu' vicino, non il primo del gruppo.
func _find_critical_target() -> Node3D:
	var migliore : Node3D = null
	var d_migliore := INF
	for raw_n in get_tree().get_nodes_in_group("targets"):
		var n := raw_n as Node3D
		if n == null:
			continue
		var d := global_position.distance_to(n.global_position)
		if d > backstab_range or d >= d_migliore:
			continue
		if _dot_davanti(n) < finisher_facing_dot:
			continue
		if n.has_method("is_finisher_victim") and n.is_finisher_victim():
			continue
		if "health_system" in n and n.health_system and "status_host" in n.health_system:
			var host = n.health_system.status_host
			if host and host.is_poise_broken():
				migliore = n
				d_migliore = d
	return migliore

func _find_backstab_target() -> Node3D:
	var migliore : Node3D = null
	var d_migliore := INF
	for raw_n in get_tree().get_nodes_in_group("targets"):
		var n := raw_n as Node3D
		if n == null:
			continue
		var to_self : Vector3 = global_position - n.global_position
		to_self.y = 0.0
		if to_self.length() > backstab_range or to_self.length() >= d_migliore:
			continue
		if _dot_davanti(n) < finisher_facing_dot:
			continue
		if n.has_method("is_finisher_victim") and n.is_finisher_victim():
			continue
		var enemy_fwd : Vector3 = n.global_transform.basis.z
		enemy_fwd.y = 0.0
		if enemy_fwd.length() < 0.01:
			continue
		enemy_fwd = enemy_fwd.normalized()
		if enemy_fwd.dot(to_self.normalized()) < back_dot_threshold:
			migliore = n
			d_migliore = to_self.length()
	return migliore
## Quanta stamina costa assorbire un colpo bloccato, per unità di `power` in
## arrivo (0.4 = un colpo da 10 potenza costa 4 stamina). Il blocco NON nega più
## il danno: lo riduce secondo `block_resistances` dell'equipaggiamento (scudo).
@export var stamina_drain_per_power : float = 0.4

## The HealthSystem node that will take in information about damage and healing received.
@export var health_system : HealthSystem
@onready var hurt_cool_down = Timer.new() # while running, player can't be hurt
signal hurt_started # to start the animation
signal damage_taken(by_what:EquipmentObject) # to indicate the damage value
signal health_received(by_what:ItemObject)
signal death_started
var is_dead :bool = false

@export var inventory_system : InventorySystem
var current_item : ItemResource
signal item_change_started
signal item_change_ended(current_item:ItemObject)
signal use_item_started
signal item_used

# Jump and Gravity
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var jump_velocity = 5.8
## null = con i piedi per terra. ⚠️ Era `@onready ... = global_position`, cioè
## già valorizzato al primo frame: col danno da caduta qui sotto quel valore
## saltava l'inizializzazione dell'apice, che restava a y=0 — e in un livello
## costruito in quota (Kalvorn parte a +26 m) il primo atterraggio risultava una
## caduta di 26 m e ammazzava il player appena spawnato.
var last_altitude = null
@export var hard_landing_height :float = 4 # how far they can fall before 'hard landing'
signal landed_fall(hard_or_soft:String)
signal jump_started

## ─── DANNO DA CADUTA ────────────────────────────────────────────────────────
## Tre soglie, e la terza non è una regola di design: è una rete di sicurezza.
##
##  1. sotto `fall_safe_height` non succede niente (l'apice del salto normale sta
##     a ~1.7 m con jump_velocity 5.8 e gravità 9.8: un salto non fa mai male);
##  2. fra `fall_safe_height` e `fall_lethal_height` si perde vita in modo
##     proporzionale — chi cade da poco sotto la soglia letale sopravvive con un
##     filo, ed è la sensazione giusta;
##  3. oltre `fall_lethal_height` si muore, punto.
##
## ⚠️ La rete di sicurezza sono `fall_void_time` e `fall_void_y`: un buco nel
## terreno o un collider mancante (ne è già stato trovato uno nel Crocevia) fa
## cadere il player all'infinito, e senza una di queste due la partita resta
## appesa per sempre senza nemmeno un game over. Vale per QUALUNQUE livello,
## anche quelli che non hanno strapiombi per disegno.
##
## La distanza si misura dall'APICE, non dal punto di stacco: saltare e poi
## cadere in un burrone deve contare la caduta vera.
@export var fall_safe_height : float = 6.0
@export var fall_lethal_height : float = 18.0
## Quota di vita persa (frazione del massimo) appena sotto la soglia letale.
## 0.9: da 17.9 m si arriva a terra con un decimo di vita, non morti.
@export_range(0.1, 1.0, 0.05) var fall_damage_max_ratio : float = 0.9
## Secondi di caduta continua oltre i quali si è per definizione fuori dal
## mondo. 6 s di caduta libera sono ~175 m: nessun livello previsto ci arriva.
@export var fall_void_time : float = 6.0
## Quota assoluta sotto la quale si è fuori dal mondo comunque.
@export var fall_void_y : float = -400.0

## Emesso all'atterraggio quando la caduta ha fatto danno (per audio/VFX/HUD).
## `mortale` è true anche quando il danno da solo avrebbe ucciso.
signal fall_damage_taken(metri : float, danno : float, mortale : bool)

var _fall_time : float = 0.0
var _fall_apex_y : float = 0.0

## Dodge and Sprint Mechanics.
@onready var sprint_timer :Timer = Timer.new()
signal dodge_started
signal sprint_started

# Movement Mechanics
var input_dir : Vector2
@export var default_speed = 4.0
@onready var speed = default_speed


# Strafing
var strafing :bool = false # substate
@onready var strafe_cross_product = 0.0
@onready var move_dot_product = 0.0
signal strafe_toggled(toggle:bool)

## Lock-on isometrico (arcanium/systems/lock_on/iso_lock_on.gd). Duck-typed via
## get_node_or_null: se il nodo manca, `strafing` degrada al vecchio strafe
## camera-relativo del template e nulla si rompe.
## Lo strafe resta il substate che guida le ANIMAZIONI; la novità del lock iso è
## che il player si orienta verso il BERSAGLIO invece che verso la camera
## (vedi rotate_player) e non può orbitare più vicino di min_orbit_radius.
@onready var lock_on_system = get_node_or_null("IsoLockOn")

# Laddering
signal ladder_started(top_or_bottom:String)
signal ladder_finished(top_or_bottom:String)

# State management
enum state {FREE,STATIC,CLIMB}

@onready var busy : bool = false # substate: to prevent input spamming
@onready var guarding = false # substate
@onready var sprinting : bool = false # substate
@onready var dodging : bool = false # substate
@onready var slowed : bool = false # substate:  force a slower walking speed
## Moltiplicatore della velocita' sul terreno: 1 normale, meno nell'acqua (lo
## scrive acqua_dungeon.gd entrando e uscendo).
var rallentamento_terreno : float = 1.0

@onready var current_state = state.STATIC : set = change_state
signal changed_state(new_state: state)

func _ready():
	if animation_tree:
		animation_tree.animation_measured.connect(_on_animation_measured)
		animation_tree.attack_measured.connect(_on_attack_measured)

	## ─── RESPAWN E VIAGGIO RAPIDO IN ATTESA ─────────────────────────────────
	## Chi arriva in una scena nuova per una MORTE o per un VIAGGIO A UN CONO va
	## posizionato dove ha scelto, non allo spawn di default del livello.
	##
	## ⚠️ Lo fa il PLAYER, non il director della scena, ed è il punto: prima
	## `consume_pending` era chiamato solo dal director della Traccia Perduta, e
	## siccome Crocevia e Kalvorn non ne hanno uno, viaggiare a un loro Cono ti
	## faceva comparire all'inizio del livello — a Kalvorn, alla Soglia, cioè
	## settecento metri e otto radure lontano dal Cono che avevi scelto.
	## Il player invece c'è in OGNI scena, presente e futura: agganciandolo qui
	## il problema non può ripresentarsi la prossima volta che si aggiunge un
	## livello senza director.
	var cm := get_node_or_null("/root/CheckpointManager")
	if cm and cm.has_method("consume_pending"):
		cm.consume_pending(self)

	# Le resistenze dell'armatura indossata finiscono nell'HealthSystem, e si
	# riscrivono a ogni cambio d'equipaggiamento. Senza questo aggancio un pezzo
	# d'armatura resterebbe una scheda descrittiva senza alcun effetto.
	var loadout := get_node_or_null("/root/EquipmentLoadout")
	if loadout:
		loadout.apply_to(health_system)
		if not loadout.changed.is_connected(_on_loadout_changed):
			loadout.changed.connect(_on_loadout_changed)
		
	if weapon_system:
		weapon_system.equipment_changed.connect(_on_weapon_equipment_changed)
		_on_weapon_equipment_changed(weapon_system.current_equipment)
		
	if gadget_system:
		gadget_system.equipment_changed.connect(_on_gadget_equipment_changed)
		_on_gadget_equipment_changed(gadget_system.current_equipment)
	
	if inventory_system:
		inventory_system.item_used.connect(_on_inventory_item_used)

	_setup_spell_system()
	lucida_tecnica_caster = get_node_or_null("LucidaTecnicaCaster")
	tecnica_guerra_caster = get_node_or_null("TecnicaGuerraCaster")
			
	if health_system:
		health_system.died.connect(death)
		
	climb_started.connect(_on_climb_started)
		
	add_child(sprint_timer)
	sprint_timer.one_shot = true
	
	hurt_cool_down.one_shot = true
	hurt_cool_down.wait_time = .5
	add_child(hurt_cool_down)

	if animation_tree:
		await animation_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	current_state = state.FREE
	
	weapon_change_ended.emit(weapon_type)
	
## Makes variable changes for each state, primiarily used for updating movement speeds
func change_state(new_state):
	current_state = new_state
	changed_state.emit(current_state)
	
	match current_state:
		state.FREE:
			speed = default_speed

		state.STATIC:
			speed = 0.0
			velocity = Vector3.ZERO
	
	# Arma e scudo nascosti mentre si scala O durante la morte per veleno (le mani
	# lasciano la presa e vanno alla gola): verranno riequipaggiati al Crocevia,
	# che ricarica un'istanza fresca del player. Vedi begin_poison_death().
	if current_state == state.CLIMB or input_fully_locked:
		system_visible(weapon_system,false)
		system_visible(gadget_system,false)
	else:
		system_visible(weapon_system,true)
		system_visible(gadget_system,true)
			
## ─── LA SPINTA ──────────────────────────────────────────────────────────────
## Un colpo che SPOSTA (la freccia caricata degli arcieri, domani altro): un
## impulso orizzontale che si smaltisce a `SPINTA_DECADIMENTO` m/s^2. Si
## applica con `move_and_collide` PRIMA della locomozione, non sommandolo a
## `velocity`: la root motion riscrive `velocity` ogni frame e se lo mangerebbe.
## Un muro la ferma; un bordo no — ed e' il punto: dai cavalcavia si cade.
## In guardia se ne prende la meta', in parata niente: il patto della parata
## vale anche per la spinta.
const SPINTA_DECADIMENTO : float = 10.0
var _spinta : Vector3 = Vector3.ZERO

func spingi(verso : Vector3, forza : float) -> void:
	if is_dead or forza <= 0.0:
		return
	if parry_active:
		return
	if guarding:
		forza *= 0.5
	var v := Vector3(verso.x, 0.0, verso.z)
	if v.length() < 0.01:
		return
	_spinta = v.normalized() * forza

func spinta_in_corso() -> Vector3:
	return _spinta

func _applica_spinta(delta : float) -> void:
	if _spinta.length() < 0.01:
		_spinta = Vector3.ZERO
		return
	move_and_collide(_spinta * delta)
	_spinta = _spinta.move_toward(Vector3.ZERO, SPINTA_DECADIMENTO * delta)

func _physics_process(_delta):
	if _riposte_window > 0.0:
		_riposte_window = maxf(0.0, _riposte_window - _delta)

	_applica_spinta(_delta)
	_update_attack(_delta)

	match current_state:
		state.FREE:
			rotate_player()

		state.CLIMB:
			set_root_climb(_delta)
			
	set_root_move(_delta)
	## Il terreno che rallenta (l'acqua dei mini-dungeon): si accorcia il passo
	## di questo frame e poi la velocita' torna quella di prima, cosi' il root
	## motion e le accelerazioni non se ne accorgono. In aria non vale: chi
	## salta il canale non si bagna.
	if rallentamento_terreno < 1.0 and is_on_floor():
		var vx := velocity.x
		var vz := velocity.z
		velocity.x *= rallentamento_terreno
		velocity.z *= rallentamento_terreno
		move_and_slide()
		velocity.x = vx
		velocity.z = vz
	else:
		move_and_slide()
	_enforce_lock_on()
	apply_gravity(_delta)
	fall_check()
	
func _input(_event:InputEvent):
	## Integrazione Arcanium: durante la morte per veleno TUTTI i comandi sono
	## bloccati (il player può solo guardare la fine). Vedi begin_poison_death().
	if input_fully_locked:
		return
	## Col GameMenu aperto (autoload) l'input di movimento/combattimento resta
	## congelato, ma i colpi nemici continuano a passare (il mondo non va in
	## pausa). Vedi arcanium/ui/game_menu/game_menu.gd.
	var game_menu := get_node_or_null("/root/GameMenu")
	if game_menu and game_menu.is_blocking():
		return
	## ⚠️ STORDITO: i comandi non passano, e il menù sopra continua a funzionare —
	## il controllo sta DOPO quello del GameMenu apposta, che perdere il controllo
	## del personaggio non deve voler dire perdere anche la pausa.
	##
	## Qui si RITORNA e basta: niente coda, niente buffer. È il punto della
	## meccanica — il giocatore pesta schivata e parata e non succede niente,
	## e quel niente è l'informazione. Bufferizzare l'input renderebbe lo stun
	## un ritardo invece che una punizione.
	if is_stunned():
		return
	## TOGGLE della modalità cast/piazzamento col TASTO DESTRO (use_gadget_light),
	## SOLO col Sigillo (bastone) equipaggiato. Va PRIMA del guard placement_active
	## così il destro può USCIRE dal piazzamento (che sotto congela l'input):
	## - in piazzamento → esce (annulla, nessun costo speso);
	## - fuori → lancia lo spell selezionato / entra in piazzamento se è ad area.
	## Con lo SCUDO, has_spell_focus() è false: il destro cade nel ramo parata più
	## sotto. Si consuma l'evento perché cast_cancel è anch'esso sul destro.
	if _event.is_action_pressed("use_gadget_light") and has_spell_focus():
		if placement_active:
			if placement_controller:
				placement_controller.cancel()
		else:
			cast_spell()
		get_viewport().set_input_as_handled()
		return

	## Durante il piazzamento posizionale (decal a terra) movimento e attacco
	## sono congelati: conferma/annullamento passano dal PlacementController
	## stesso (cast_confirm/cast_cancel), non da qui.
	if placement_active:
		return

		# Update current orientation to camera when nothing pressed
	if !Input.is_anything_pressed():
		current_camera = get_viewport().get_camera_3d()
	
	# TODO(arcanium): ui_cancel dovrà aprire il menu di pausa, non chiudere il gioco.
	# Quit-istantaneo rimosso: viola i requisiti di certificazione console (suspend/resume,
	# save-in-progress) ed è un footgun durante i test.
	#if _event.is_action_pressed("ui_cancel"):
		#get_tree().quit()

	## ─── LEGIONE TESTUGGINE — la tecnica di guerra della guardia ──────────────
	## Con lo SCUDO ALZATO, il colpo leggero (sinistro / RB) non e' piu' un
	## fendente: e' l'affondo a strato che passa sopra il bordo dello scudo senza
	## farlo cadere. Deciso con l'utente il 2026-09-12: l'accordo "destro tenuto
	## + sinistro" apparteneva gia' alla Lucida Tecnica (`_combo_mouse_tecnica`,
	## qui sotto), e invece di un tasto nuovo si e' scelto che sia la GUARDIA a
	## decidere — scudo su, Testuggine; scudo giu', Lucida come prima.
	##
	## ⚠️ Va PRIMA della Lucida e prima di `queue_attack`, e CONSUMA l'evento
	## anche quando il lancio viene rifiutato (cooldown, stamina): con lo scudo
	## alzato un click sinistro che degradasse a fendente aprirebbe la guardia
	## proprio nel momento in cui il giocatore la sta tenendo chiusa — cioe' il
	## contrario di cio' che ha chiesto. Se la tecnica non e' APPRESA, invece,
	## tutto resta com'era: il click scende ai rami di sempre.
	##
	## Non passa da `busy`: `set_guarding()` abbasserebbe lo scudo. Il gesto vive
	## nel suo OneShot in cima all'albero — vedi il cappello del caster.
	if guarding and _event.is_action_pressed("use_weapon_light") 			and tecnica_guerra_caster != null 			and tecnica_guerra_caster.tecnica_di_guardia() != null:
		tecnica_guerra_caster.lancia()
		get_viewport().set_input_as_handled()
		return

	## ─── LUCIDA TECNICA ──────────────────────────────────────────────────────
	## Tre modi di chiamarla, tutti qui: tasto B, LT sul pad (entrambi nell'azione
	## `lucida_tecnica`), e i DUE TASTI DEL MOUSE INSIEME.
	##
	## Il combo del mouse non può essere un InputEvent — Godot non ha eventi
	## "due bottoni insieme" — quindi si riconosce a mano: al premere di uno dei
	## due si guarda se l'altro è già giù. Ed è per questo che va PRIMA dei rami
	## dell'attacco e della parata: sinistro e destro da soli sono già colpo
	## leggero e gadget, e senza consumare l'evento un tentativo di Tecnica
	## partirebbe come attacco normale.
	##
	## Se non c'è tecnica pronta l'evento NON si consuma: il combo degrada al
	## comportamento di sempre invece di mangiarsi il colpo.
	if _event.is_action_pressed("lucida_tecnica") or _combo_mouse_tecnica(_event):
		if lucida_tecnica_caster and lucida_tecnica_caster.lancia():
			get_viewport().set_input_as_handled()
			return

	## Lock-on isometrico: aggancia il bersaglio più vicino, ripremendo sgancia.
	if _event.is_action_pressed("lock_on"):
		set_strafe_targeting()
		
	# a helper for keyboard controls, not really used for joypad
	if Input.is_action_pressed("secondary_action"):
		secondary_action = true
	else:
		secondary_action = false
	
	# ⚠️ L'attacco NON passa dal gate `current_state == state.FREE` qui sotto: un
	# click va sempre MEMORIZZATO, anche (soprattutto) mentre stai già menando.
	# Vedi queue_attack().
	if _event.is_action_pressed("use_weapon_light"):
		queue_attack(false)
	elif _event.is_action_pressed("use_weapon_strong"):
		queue_attack(true)

	if current_state == state.FREE:

		if is_on_floor():
			# if interactable exists, activate its action
			if _event.is_action_pressed("interact"):
				interact()
			
			elif _event.is_action_pressed("jump"):
				jump()
				
			elif _event.is_action_pressed("dodge_dash"):
				dodge_or_sprint()
				
			elif _event.is_action_released("dodge_dash") \
			&& sprint_timer.time_left:
				dodge()
			
			elif _event.is_action_pressed("change_primary"):
				weapon_change()
			elif _event.is_action_pressed("change_secondary"):
				gadget_change()

			elif _event.is_action_pressed("use_gadget_strong"): 
				use_gadget()
					
			elif _event.is_action_pressed("use_gadget_light"):
				## Col bastone il destro è già stato gestito in cima (toggle cast).
				## Qui arriva solo con lo SCUDO: parata (o gadget con secondary).
				if secondary_action:
					use_gadget()
				else:
					start_guard()
			
			## Il cambio oggetto NON passa più da qui. Era `item_change()`, che
			## rallenta il player e aspetta un'animazione di scambio: giusto per
			## rinfoderare un'arma, sbagliato per scorrere il quick-slot, che deve
			## essere istantaneo come `,`/`.` per magie ed evocazioni. Ora i tasti
			## `item_prev`/`item_next` (1 e 2) li gestisce ArcaniumInventory, che
			## è l'unico a sapere cosa c'è in borsa.
			elif _event.is_action_pressed("use_item"):
				use_item()
	
	elif current_state == state.CLIMB:
			#aiming = false
			if _event.is_action_pressed("interact"):
				abort_climb()
	
	if sprinting:
		
		if !input_dir:
			end_sprint()
		
		if _event.is_action_released("dodge_dash"):
			end_sprint()
				
	if _event.is_action_released("use_gadget_light"):
		## Solo se stavamo effettivamente parando: col bastone il destro casta e
		## basta, non c'è guardia da chiudere.
		if not secondary_action and guarding:
			end_guard()

## ─── Sistema incantesimi ─────────────────────────────────────────────────────
## Crea SpellSelection (rotellina/hotkey + scan di res://arcanium/resources/spells)
## e SpellCaster (spawn proiettile + spesa arcanium), li aggancia e prova a
## collegare la SpellBar dell'HUD per l'highlight della selezione.
## Riconosce i DUE TASTI DEL MOUSE premuti insieme come chiamata alla Lucida
## Tecnica. Godot non ha un evento "combo": si guarda se, nell'istante in cui uno
## dei due scende, l'altro è già giù.
##
## Non serve una finestra temporale — se premi il destro mentre il sinistro è già
## premuto, l'intento è il combo. Il caso "premuti a un frame di distanza" è già
## coperto: il secondo dei due vede il primo ancora premuto.
func _combo_mouse_tecnica(_event : InputEvent) -> bool:
	if not (_event is InputEventMouseButton) or not _event.pressed:
		return false
	match _event.button_index:
		MOUSE_BUTTON_LEFT:
			return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		MOUSE_BUTTON_RIGHT:
			return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	return false


## ─── Sistema incantesimi ─────────────────────────────────────────────────────
func _setup_spell_system() -> void:
	spell_selection = SpellSelection.new()
	spell_selection.name = "SpellSelection"
	add_child(spell_selection)

	spell_caster = SpellCaster.new()
	spell_caster.name = "SpellCaster"
	spell_caster.vitals = vitals
	add_child(spell_caster)

	placement_controller = PlacementController.new()
	placement_controller.name = "PlacementController"
	placement_controller.anchor = self
	add_child(placement_controller)
	placement_controller.confirmed.connect(_on_placement_confirmed)
	placement_controller.cancelled.connect(_on_placement_cancelled)

	# Aggancio opzionale alla SpellBar dell'HUD (se presente in scena): highlight
	# della selezione. La ricerca è best-effort e non blocca nulla se l'HUD manca.
	await get_tree().process_frame
	var hud := get_tree().get_first_node_in_group("arcanium_hud")
	if hud == null:
		for n in get_tree().get_nodes_in_group("hud"):
			if n is ArcaniumHUD:
				hud = n
				break
	## Ultima spiaggia: cerca l'HUD nell'albero del player. La ricerca per
	## GRUPPO era l'unica strada e bastava che il nodo non fosse iscritto al
	## gruppo perché la SpellBar non venisse mai collegata alla selezione — la
	## barra si vedeva ma non reagiva al cambio di spell.
	if hud == null:
		for n in find_children("*", "Control", true, false):
			if n is ArcaniumHUD:
				hud = n
				break
	if hud and hud.has_method("get_spell_bar"):
		var bar = hud.get_spell_bar()
		if bar and bar.has_method("bind_selection"):
			bar.bind_selection(spell_selection)
		# Oggetti integrati nella barra azioni: la sezione OGGETTI legge
		# l'inventario reale (il vecchio riquadro pozioni è stato rimosso).
		if bar and bar.has_method("bind_inventory") and inventory_system:
			bar.bind_inventory(inventory_system)

## Lancia lo spell correntemente selezionato (fallback: Shard di Ghiaccio). Se
## lo spell è POSIZIONALE (is_positional), non lancia nulla subito: entra in
## placement-mode e la risoluzione avviene in _on_placement_confirmed().
## Il mago può lanciare SOLO col Sigillo (focus arcano) equipaggiato al posto
## dello scudo: castare richiede concentrazione, si rinuncia alla difesa. Lo
## scudo (ArcaniumShieldResource) non ha `is_spell_focus`, quindi qui degrada a
## false. Si cambia gadget con `change_secondary` (tasto X → gadget_change).
## Vero se in mano secondaria c'è davvero uno scudo. Speculare a
## `has_spell_focus()`: i due non possono essere veri insieme, perché la mano è
## una sola. Si riconosce dalle `block_resistances` (ArcaniumShieldResource) e
## non dalla classe, come fa il resto del progetto.
func _has_shield() -> bool:
	if gadget_system == null or gadget_system.current_equipment == null:
		return false
	var info = gadget_system.current_equipment.equipment_info
	return info != null and ("block_resistances" in info)


func has_spell_focus() -> bool:
	if gadget_system == null or gadget_system.current_equipment == null:
		return false
	var info = gadget_system.current_equipment.equipment_info
	return info != null and ("is_spell_focus" in info) and info.is_spell_focus

func cast_spell() -> void:
	if spell_caster == null or placement_active:
		return
	if not has_spell_focus():
		## Niente bastone in mano: il gesto non parte. Feedback per l'HUD.
		trigger_event("cast_blocked")
		spell_cast_blocked.emit()
		return

	var spell = spell_selection.current_spell if spell_selection else null
	if spell == null:
		spell = SpellRegistry.new().get_spell("ice_shard")
	if spell == null:
		return

	if "is_positional" in spell and spell.is_positional:
		_begin_placement(spell)
		return

	## ⚠️ Il player guarda +Z, NON -Z: le mesh Meshy sono orientate così e
	## rotate_player allinea il +Z alla direzione di marcia (vedi la formula
	## `atan2(dir.x, dir.z)`). Con `-basis.z` gli incantesimi partivano dalla
	## SCHIENA del personaggio.
	var forward := global_transform.basis.z.normalized()
	var origin := global_position + Vector3.UP * spell_muzzle_offset.y \
		+ forward * spell_muzzle_forward
	forward = aim_direction_from(origin, forward)
	## Il gesto parte subito, il proiettile dopo `spell_release_delay`: prima
	## nasceva all'istante della pressione e l'animazione lo inseguiva.
	if spell_caster.cast_delayed(spell, origin, forward, spell_release_delay,
			self, spell_muzzle_offset.y, spell_muzzle_forward):
		spell_cast_started.emit(spell)
		trigger_event("gadget_started")  # riusa l'anim di gadget per il gesto di cast

## Punto a cui mirano gli incantesimi: il centro della mesh del bersaglio
## agganciato. `null` se non c'è lock-on, e allora si tira dritto davanti a sé.
## Duck-typed apposta: lo chiama SpellCaster al momento del rilascio, che del
## player non sa nulla.
func spell_aim_point():
	if lock_on_system == null or not lock_on_system.is_locked():
		return null
	var p : Vector3 = lock_on_system.aim_point()
	return null if p == Vector3.ZERO else p

## Inclina `avanti` verso il punto di mira, se c'è. Senza questo il proiettile
## parte ORIZZONTALE dall'altezza del petto (1.4 m) e sopra un bersaglio basso —
## il lupo — passa sopra la schiena senza toccarlo.
func aim_direction_from(origin : Vector3, avanti : Vector3) -> Vector3:
	var p = spell_aim_point()
	if p == null:
		return avanti
	var d : Vector3 = (p as Vector3) - origin
	return avanti if d.length_squared() < 0.0001 else d.normalized()

## ─── Piazzamento posizionale ──────────────────────────────────────────────
func _begin_placement(spell : ArcaniumSpellResource) -> void:
	if placement_controller == null:
		return
	_pending_positional_spell = spell
	placement_active = true
	placement_controller.start(spell.aoe_radius, placement_max_range, spell.color)
	var iso_cam := get_node_or_null("IsoCam")
	if iso_cam and iso_cam.has_method("focus_target"):
		iso_cam.focus_target(placement_controller.get_decal())

## Conferma: risolve lo spell posizionale al centro scelto (spesa/cooldown
## verificati SOLO ora, da SpellCaster.cast_positional — se falliscono
## semplicemente non si spawna nulla, coerente col contratto "false = nessun
## effetto collaterale"), rilascia la camera, scongela il player.
func _on_placement_confirmed(position : Vector3) -> void:
	placement_active = false
	var iso_cam := get_node_or_null("IsoCam")
	if iso_cam and iso_cam.has_method("release_focus"):
		iso_cam.release_focus()
	var spell := _pending_positional_spell
	_pending_positional_spell = null
	if spell and spell_caster and spell_caster.cast_positional(spell, position):
		spell_cast_started.emit(spell)

## Annullamento: nessun costo speso, rilascia camera, scongela il player.
func _on_placement_cancelled() -> void:
	_pending_positional_spell = null
	placement_active = false
	var iso_cam := get_node_or_null("IsoCam")
	if iso_cam and iso_cam.has_method("release_focus"):
		iso_cam.release_focus()

func apply_gravity(_delta):
	if !is_on_floor() \
	&& current_state != state.CLIMB:
		velocity.y -= gravity * _delta
		
func rotate_player():
	if busy or placement_active:
		return
	var rate = .15
	
	var target_rotation
	var current_rotation = global_transform.basis.get_rotation_quaternion()
	# FreeCam rotation code, slerps to input oriented to the camera perspective, and only calculates when input is given
	if strafing:
		rate = .4
		## Con lock-on ISO il player guarda il BERSAGLIO (orbita intorno a lui);
		## senza bersaglio si ricade sul vecchio strafe camera-relativo del
		## template. Stessa formula di yaw del ramo libero qui sotto: il +Z del
		## player punta lungo la direzione data.
		var yaw : float
		var locked = lock_on_system.current_target if lock_on_system else null
		if is_instance_valid(locked):
			var to_target : Vector3 = locked.global_position - global_position
			to_target.y = 0.0
			yaw = atan2(to_target.x, to_target.z) if to_target.length_squared() > 0.0001 \
				else global_rotation.y
		else:
			# StrafeCam code - Look at target, slerping current rotation to the camera's rotation.
			yaw = orientation_target.global_rotation.y + PI
		target_rotation = current_rotation.slerp(Quaternion(Vector3.UP, yaw), rate)
		global_transform.basis = Basis(target_rotation)
		var new_direction = calc_direction().normalized()
		
		var forward_vector = global_transform.basis.z.normalized() 
		strafe_cross_product = -forward_vector.cross(new_direction).y
		move_dot_product = forward_vector.dot(new_direction)
		return
	
	if input_dir:
		var new_direction = calc_direction().normalized()
		# Rotate the player per the perspective of the camera
		target_rotation = current_rotation.slerp(Quaternion(Vector3.UP, atan2(new_direction.x, new_direction.z)), rate)
		global_transform.basis = Basis(target_rotation)

## Lock-on: aggancia/sgancia. Con il sistema iso presente lo strafe si accende
## SOLO se un bersaglio valido è stato trovato (premere a vuoto non blocca il
## player in strafe senza nulla da guardare).
func set_strafe_targeting():
	if lock_on_system:
		strafing = lock_on_system.toggle()
	else:
		strafing = !strafing
	strafe_toggled.emit(strafing)

## Dopo il movimento: sgancia se il bersaglio non è più valido (morto → esce dal
## gruppo "targets", oppure fuori range) e applica il raggio minimo d'orbita.
func _enforce_lock_on() -> void:
	if lock_on_system == null or not strafing:
		return
	lock_on_system.validate()
	if not lock_on_system.is_locked():
		strafing = false
		strafe_toggled.emit(false)
		return
	global_position = lock_on_system.clamp_orbit_position(global_position)

func _on_target_cleared():
	strafing = false
	if lock_on_system:
		lock_on_system.release()

## ═══════════════════════════════════════════════════════════════════════════
## COMBO E BUFFER D'ATTACCO
## ═══════════════════════════════════════════════════════════════════════════
##
## Come funzionava prima, e perché la combo non usciva mai:
##
##  1. L'input d'attacco stava dentro `if current_state == state.FREE`, e
##     `trigger_event()` si apre con `if busy: return`. Ogni click premuto
##     MENTRE stavi attaccando veniva quindi buttato via, senza memoria.
##  2. La catena si poteva innescare solo DOPO la fine dell'animazione, e
##     `attack_timer` azzerava il contatore 0.2 s più tardi: una finestra di due
##     decimi in cui bisognava azzeccare il click, con la clip già finita.
##  3. La durata dell'attacco veniva letta da `animation_measured`, che scatta
##     per QUALUNQUE clip parta — anche una di camminata. Se arrivava la misura
##     sbagliata, `busy` cadeva troppo presto e il click successivo faceva
##     RIPARTIRE il one-shot a metà fendente: è l'animazione che "si spezza".
##
## Come funziona ora, che è la convenzione souls:
##
##  • il click viene sempre MEMORIZZATO (`_buffered_attack`), anche a metà
##    swing, e resta valido per `attack_buffer_time`;
##  • la FINESTRA DI CATENA si apre DURANTE l'attacco, a `combo_open_frac` della
##    clip (cioè dopo che il colpo è partito, nel recovery) e resta aperta fino
##    a `combo_grace` dopo la fine: se c'è un click in memoria, il colpo
##    successivo parte lì, incatenato;
##  • la durata si prende dalla clip d'attacco VERA (`attack_measured`, filtrata
##    per nome), quindi `busy` cade quando deve;
##  • prima che la finestra si apra il one-shot non viene MAI ri-lanciato, che è
##    ciò che evita di spezzare l'animazione a metà.
##
## Il buffer tiene UN colpo, non la coda di tutti i click: è di proposito.
## Accumulare cinque click significa cinque fendenti obbligati mentre il nemico
## ti mena, ed è il motivo per cui nessun souls lo fa. Quello che serve è che il
## click dato "un attimo troppo presto" non vada perso — e adesso non si perde.

## Per quanto tempo un click resta in memoria se non può partire subito.
@export var attack_buffer_time : float = 0.45
## Da che frazione della clip d'attacco si può incatenare il colpo successivo.
## Più basso = combo più rapide e più "arcade"; più alto = ogni fendente va
## portato a termine. Sotto ~0.35 si rischia di tagliare il colpo prima che la
## lama arrivi a segno.
@export var combo_open_frac : float = 0.55
## Quanto la catena resta viva dopo la fine della clip, prima di tornare al
## primo fendente.
@export var combo_grace : float = 0.35

var _buffered_attack : bool = false      ## c'è un click in attesa
var _buffered_strong : bool = false      ## ...ed era un colpo forte
var _buffer_until : float = 0.0
var _attack_active : bool = false        ## una clip d'attacco è in corso
var _attack_ends_at : float = 0.0
var _combo_opens_at : float = 0.0
var _chain_alive_until : float = 0.0


func _clock() -> float:
	return OrologioGioco.adesso()


## Registra un click. Non lancia niente: decide `_process_attack_buffer()`.
func queue_attack(strong : bool) -> void:
	if is_dead or input_fully_locked:
		return
	_buffered_attack = true
	_buffered_strong = strong
	var t := _clock()
	_buffer_until = t + attack_buffer_time
	if _attack_active:
		# Un click dato DURANTE un fendente vale per la catena di quel fendente:
		# deve sopravvivere almeno fino a quando la finestra si apre. Con la sola
		# scadenza a tempo fisso si perdeva proprio il caso per cui il buffer
		# esiste — click a 0.15s, finestra a 0.66s, buffer morto a 0.60s.
		_buffer_until = maxf(_buffer_until, _combo_opens_at + attack_buffer_time)


## Chiamata ogni frame di fisica. Chiude l'attacco in corso quando la sua clip è
## finita e fa partire il colpo in memoria appena è lecito.
func _update_attack(_delta : float) -> void:
	var t := _clock()

	if _attack_active and t >= _attack_ends_at:
		_attack_active = false
		busy = false
		event_finished.emit()

	# La catena è scaduta: il prossimo click riparte dal primo fendente.
	if not _attack_active and t > _chain_alive_until and animation_tree:
		animation_tree.reset_attack_chain()

	if not _buffered_attack:
		return
	if t > _buffer_until:
		_buffered_attack = false
		return

	# Condizioni per partire: liberi, vivi, e — se stiamo già attaccando — con la
	# finestra di catena aperta.
	if current_state != state.FREE or dodging or is_dead:
		return
	if _attack_active:
		if t < _combo_opens_at:
			return
	elif busy:
		return   # un'altra azione (oggetto, cambio arma, parata) sta girando

	_buffered_attack = false
	if _buffered_strong:
		attack_strong()
	else:
		attack()


## Avvia la clip d'attacco e apre le finestre. La durata vera arriva subito dopo
## da `attack_measured` (vedi `_on_attack_measured`): finché non c'è, si lavora
## con una stima prudente, così un segnale mancato non lascia il player bloccato.
func _begin_attack() -> void:
	busy = true
	_attack_active = true
	var t := _clock()
	_attack_ends_at = t + 1.0
	_combo_opens_at = t + 1.0 * combo_open_frac
	_chain_alive_until = _attack_ends_at + combo_grace
	_suona_fendente()
	attack_started.emit()


## La clip d'attacco è partita davvero e conosciamo la sua durata: si ricalibrano
## le finestre su quella.
func _on_attack_measured(length : float) -> void:
	if not _attack_active:
		return
	var t := _clock()
	_attack_ends_at = t + length
	_combo_opens_at = t + length * combo_open_frac
	_chain_alive_until = _attack_ends_at + combo_grace


func attack():
	if not _try_spend_stamina(cost_attack):
		return
	finisher_active = false
	if _riposte_window > 0.0:
		_riposte_window = 0.0
		_start_finisher(_find_critical_target(), false)
		trigger_event("riposte_started")
		return
	var backstab_target := _find_backstab_target()
	if backstab_target != null:
		_start_finisher(backstab_target, true)
		trigger_event("backstab_started")
		return
	var critical_target := _find_critical_target()
	if critical_target != null:
		_start_finisher(critical_target, false)
		trigger_event("riposte_started")
		return
	# I finisher qui sopra restano sul percorso `trigger_event`: sono azioni
	# uniche e non concatenabili, non hanno una catena da tenere viva.
	_begin_attack()

## Avvisa il bersaglio che sta subendo un finisher (hook duck-typed, stesso
## pattern di parried()): il boss si congela nella sua clip victim sincronizzata.
## `finisher_active` viene letto dall'EquipmentSystem per moltiplicare il danno
## del colpo che la lama metterà a segno durante la clip.
var finisher_active : bool = false
func _start_finisher(victim : Node3D, is_backstab : bool) -> void:
	finisher_active = true
	if victim == null:
		return
	# Snap del facing verso il bersaglio: la clip del finisher affonda lungo il
	# forward del player, che al momento del trigger può essere ruotato anche di
	# ~50° (il cono posteriore del backstab è largo) — senza questo la stoccata
	# "mira al vuoto" accanto al torso del nemico.
	var to_victim := victim.global_position - global_position
	to_victim.y = 0.0
	if to_victim.length() > 0.01:
		var d := to_victim.normalized()
		global_transform.basis = Basis(Quaternion(Vector3.UP, atan2(d.x, d.z)))
	if is_backstab and victim.has_method("backstabbed"):
		victim.backstabbed(self)
	elif not is_backstab and victim.has_method("riposted"):
		victim.riposted(self)

func attack_strong():
	if dodging:
		return
	if not _try_spend_stamina(cost_attack_strong):
		return
	# `secondary_action` è la levetta che l'AnimationTree legge per instradare
	# sul ramo pesante: va alzata PRIMA che il one-shot parta e riabbassata
	# subito dopo, o resta appiccicata al fendente successivo.
	secondary_action = true
	_begin_attack()
	await get_tree().process_frame
	secondary_action = false
	
	
func fall_check():
	## If you leave the floor, store last position.
	## When you land again, compare the distances of both location y values, if greater
	## than the hard_landing_height, then trigger a hard landing. Otherwise, 
	## clear the last_altitude variable.

	## Morto o in arrampicata: nessuna caduta in corso, e nessun conto aperto.
	## Senza questo, morire a mezz'aria lasciava il timer del vuoto acceso e si
	## moriva una seconda volta al respawn.
	if is_dead or current_state == state.CLIMB:
		last_altitude = null
		_fall_time = 0.0
		return

	if !is_on_floor():
		if last_altitude == null:
			last_altitude = global_position
			_fall_apex_y = global_position.y
		## L'apice, non il punto di stacco: saltare e poi cadere in un burrone
		## deve contare la caduta vera, non quella meno l'altezza del salto.
		_fall_apex_y = maxf(_fall_apex_y, global_position.y)
		_fall_time += get_physics_process_delta_time()
		## Rete di sicurezza: buco nel terreno, collider mancante, caduta
		## infinita. Solo mentre si SCENDE (velocity.y < 0), o un ascensore
		## lento verso l'alto conterebbe come precipizio.
		if global_position.y < fall_void_y \
		or (_fall_time > fall_void_time and velocity.y < 0.0):
			_morte_nel_vuoto()
		return

	if last_altitude != null:
		var fall_distance = absf(_fall_apex_y - global_position.y)
		if fall_distance > hard_landing_height:
			trigger_event("landed_fall")
		_applica_danno_caduta(fall_distance)
		last_altitude = null
	_fall_time = 0.0

## Dimentica la caduta in corso. **Va chiamata da CHIUNQUE teletrasporti il
## player**: punto d'arrivo di un portale, respawn al checkpoint, viaggio fra i
## Coni.
##
## ⚠️ Senza, un teletrasporto verso il basso è indistinguibile da un volo. Il
## conto della caduta parte dall'apice registrato PRIMA dello spostamento:
## arrivare a Kalvorn e comparire al piede dell'Albero Padre (−12 m) mentre
## l'apice era la Soglia (+27) risultava una caduta di 39 m — cioè morte
## istantanea all'atterraggio, senza che nulla lo spiegasse. Trovato provando
## il giro, non giocando: in gioco sarebbe sembrato un bug casuale del viaggio
## rapido.
func reset_fall() -> void:
	last_altitude = null
	_fall_time = 0.0
	_fall_apex_y = global_position.y

## Danno all'atterraggio. Usa `drain()` e non `apply_damage()`: drain ignora le
## resistenze dell'armatura — una corazza non attutisce venti metri di vuoto — e
## soprattutto emette `died`, che è ciò che chiude il cerchio col respawn.
func _applica_danno_caduta(metri : float) -> void:
	if metri <= fall_safe_height or health_system == null:
		return
	var mortale : bool = metri >= fall_lethal_height
	var danno : float
	if mortale:
		danno = float(health_system.total_health) * 10.0
	else:
		var t : float = (metri - fall_safe_height) / maxf(fall_lethal_height - fall_safe_height, 0.001)
		danno = float(health_system.total_health) * fall_damage_max_ratio * t
	fall_damage_taken.emit(metri, danno, mortale)
	if health_system.has_method("drain"):
		health_system.drain(danno, "SCHIANTO")
	elif health_system.has_method("apply_damage"):
		health_system.apply_damage(danno, "SCHIANTO")

## Fuori dal mondo: non c'è un atterraggio da cui calcolare niente, si muore e
## basta. Il player viene fermato a mezz'aria, o continuerebbe a precipitare
## mentre parte l'animazione di morte e il respawn lo pescherebbe a chilometri
## di distanza.
func _morte_nel_vuoto() -> void:
	velocity = Vector3.ZERO
	last_altitude = null
	_fall_time = 0.0
	fall_damage_taken.emit(INF, INF, true)
	if health_system and health_system.has_method("drain"):
		health_system.drain(float(health_system.total_health) * 10.0, "SCHIANTO")
	else:
		death()

func dodge_or_sprint():
	if sprint_timer.is_stopped():
		sprint_timer.start(.3)
		await sprint_timer.timeout
		if !dodging && input_dir:
			if _try_spend_stamina(cost_sprint):
				sprinting = true
				sprint_started.emit() # triggers the change in anim tree
		
func end_sprint():
	sprinting = false
		
	
func dodge(): 
	if dodging:
		return
	if not _try_spend_stamina(cost_dodge):
		return
		
	var strafe_status = strafing
	strafing = false
	dodging = true
	sprint_timer.stop()
	dodge_started.emit()
	if animation_tree:
		await animation_tree.animation_measured
	hurt_cool_down.start(anim_length*.7)
	await get_tree().create_timer(anim_length).timeout
	
	strafing = strafe_status
	dodging = false


func _on_animation_measured(_new_length):
	anim_length = _new_length - .05 # offset slightly for the process frame

func interact():
	if is_on_floor() && !busy:
		if interactable:
			interactable.activate(self)
		elif ladder:
			ladder.activate(self)

func _on_climb_started():
	#interactable = null
	current_state = state.CLIMB
	
func abort_climb():
	if current_state == state.CLIMB:
		last_altitude = global_position
		current_state = state.FREE
	

func weapon_change():
	slowed = true
	trigger_event("weapon_change_started")
	await event_finished
	print(weapon_type)
	weapon_change_ended.emit(weapon_type)
	slowed = false
	
func _on_weapon_equipment_changed(_new_weapon:EquipmentObject):
	weapon_type = _new_weapon.equipment_info.object_type

func _on_gadget_equipment_changed(_new_gadget:EquipmentObject):
	gadget_type = _new_gadget.equipment_info.object_type

func _on_inventory_item_used(_item):
	current_item = _item
	
func gadget_change():
	## Lo scudo sta lasciando la mano: la guardia va chiusa qui, non quando il
	## giocatore rilascerà il destro. Altrimenti resta alzata su una mano vuota,
	## e l'animazione di parata continua mentre il braccio impugna un sigillo.
	if guarding:
		end_guard()
	slowed = true
	trigger_event("gadget_change_started")
	await event_finished
	print(gadget_type)
	gadget_change_ended.emit(gadget_type)
	await get_tree().create_timer(anim_length *.5).timeout
	slowed = false

func item_change():
	slowed = true
	trigger_event("item_change_started")
	await event_finished
	item_change_ended.emit(current_item)
	slowed = false
	
func start_guard(): # Guarding, and for a short window, parring is possible
	## Con un ARCO in mano non c'e' scudo: la sinistra tiene l'arco e lo scudo
	## e' nascosto (held_weapon.gd). Una parata invisibile parerebbe lo stesso.
	if weapon_type == "BOW":
		return
	slowed = true
	guarding = true
	parry_active = true
	await get_tree().create_timer(parry_window).timeout
	parry_active = false
	
func end_guard():
	guarding = false
	parry_active = false
	slowed = false

func use_gadget(): # emits to start the gadget, and runs some timers before stopping the gadget
	if not _try_spend_stamina(cost_gadget):
		return
	trigger_event("gadget_started")

## ─── STORDIMENTO ────────────────────────────────────────────────────────────
## Non passa da nessun sistema di status: il player non ha uno StatusHost (il
## poise-break e la Frattura sono cose che INFLIGGE, non che subisce). Lo stun è
## una proprietà della MOSSA che l'ha colpito, letta in duck-typing come il
## danno — vedi `stun_time` in arcanium/resources/enemy_move.gd.
var _stordito_fino : float = 0.0

func is_stunned() -> bool:
	return OrologioGioco.adesso() < _stordito_fino

## Applica lo stordimento. Chiamata da `hit()` quando il colpo entra pulito.
func stun(durata : float) -> void:
	if durata <= 0.0:
		return
	_stordito_fino = maxf(_stordito_fino, OrologioGioco.adesso() + durata)
	## ⚠️⚠️ I frame d'invulnerabilità vanno SPENTI, non lasciati correre.
	## `hurt()` avvia `hurt_cool_down`, che mentre gira fa uscire subito da
	## `hit()`: uno stordito con quel timer attivo sarebbe più SICURO di uno in
	## piedi, e la combo che lo stun esiste per garantire gli passerebbe
	## attraverso senza togliergli un HP. È l'esatto contrario del senso della
	## mossa — si viene storditi per essere puniti.
	hurt_cool_down.stop()

func hit(_who, _by_what):
	## ⚠️ Da MORTI non si incassa piu' niente. `death()` arma 10 s di
	## invulnerabilita', ma non bastano: la coroutine `hurt()` del colpo mortale,
	## al risveglio dal suo `await`, riarma `hurt_cool_down` con la durata
	## dell'animazione e accorcia i 10 s. Da li' ogni morso passava, l'HealthSystem
	## rimandava `died` e `death()` ripartiva con un altro `death_started`.
	## Trovato dal playtest automatico il 2026-10-07: i lupi dell'arena dell'Alpha
	## mordevano il cadavere e un'unica morte usciva come tre in 2,7 s.
	if is_dead:
		return
	if hurt_cool_down.time_left > 0:
		return
	## I due patti che una mossa puo' rompere (enemy_move.gd): `imparriabile`
	## salta la parata perfetta, `imparabile` salta la guardia. Indipendenti.
	var imparabile : bool = _by_what != null and ("imparabile" in _by_what) and bool(_by_what.imparabile)
	var imparriabile : bool = _by_what != null and ("imparriabile" in _by_what) and bool(_by_what.imparriabile)
	if parry_active and not imparriabile:
		parry()
		if _who.has_method("parried"):
			_who.parried()
		return
	elif guarding and not imparabile:
		block(_by_what)
	else:
		damage_taken.emit(_by_what)
		## ⚠️ LO STUN VA PRIMA DI `hurt()`, e l'ordine non è cosmetico: `hurt()`
		## è una coroutine che riarma `hurt_cool_down` DOPO il suo `await`.
		## Applicandolo dopo, il mio `stop()` verrebbe disfatto un frame più
		## tardi e i frame d'invulnerabilità tornerebbero — in silenzio.
		## Messo prima, `hurt()` trova `is_stunned()` vero e non li arma affatto.
		##
		## Lo stordimento arriva solo col colpo PULITO: parato o parryato non
		## stordisce. È ciò che tiene in piedi il patto — la botta di scudo si
		## può leggere e a cui si può rispondere, e chi lo fa non paga il prezzo.
		if _by_what != null and "stun_time" in _by_what:
			stun(float(_by_what.stun_time))
		hurt()

func heal(_by_what):
	health_received.emit(_by_what)

func block(_by_what = null):
	block_started.emit()
	if _by_what == null:
		return
	var dtype : String = _by_what.damage_type if "damage_type" in _by_what else "FISICO"
	## Senza SCUDO in mano non si para: il colpo entra pieno. È l'altra metà del
	## patto del focus arcano — o ti difendi, o lanci.
	##
	## Il default generico di 0.5 non reggeva: `start_guard()` scatta col destro
	## ogni volta che `has_spell_focus()` è falso, quindi qualunque gadget che
	## non sia il Sigillo — una lanterna, domani — alzava la guardia e riceveva
	## mezza mitigazione per il fatto di esistere. Lo scudo si riconosce dalle
	## `block_resistances`, quindi un pezzo nuovo para solo se le dichiara.
	var mult := 1.0
	if _has_shield():
		var shield_info = gadget_system.current_equipment.equipment_info
		mult = shield_info.block_resistances.get(dtype, 0.5)
	if health_system and health_system.has_method("apply_damage"):
		health_system.apply_damage(float(_by_what.power) * mult, dtype)
	if vitals:
		vitals.spend_stamina(float(_by_what.power) * stamina_drain_per_power)

func parry():
	parry_started.emit()
	_riposte_window = riposte_window_duration
	if animation_tree:
		await animation_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	hurt_cool_down.start(anim_length)

func hurt():
	hurt_started.emit() # before state change in case on ladder,etc
	if animation_tree:
		await animation_tree.animation_measured
	## ⚠️ Da storditi NON si armano i frame d'invulnerabilità. `hurt_cool_down`
	## fa uscire subito da `hit()` finché gira: armarlo qui renderebbe lo
	## stordito immune ai colpi che lo stun esiste apposta per fargli incassare.
	## Il controllo sta DOPO l'await perché è lì che il timer verrebbe riarmato.
	if not is_stunned():
		hurt_cool_down.start(anim_length)
	await get_tree().create_timer(anim_length).timeout

func use_item():
	slowed = true
	
	use_item_started.emit()
	if animation_tree:
		await animation_tree.animation_measured
	await get_tree().create_timer(anim_length * .5).timeout
	item_used.emit()
	await get_tree().create_timer(anim_length * .5).timeout
	slowed = false

## Integrazione Arcanium: quando un regista esterno (PrologueDirector) gestisce la
## transizione post-morte (es. risveglio nell'hub), disattiva il reload di default
## del template. Lasciato true per uso generico → comportamento template invariato.
@export var reload_scene_on_death : bool = true

func death():
	current_state = state.STATIC
	hurt_cool_down.start(10)
	is_dead = true
	## ⚠️ Il lamento del danno continuo va spento QUI. Il suo conteggio e' statico
	## e sopravvive alla morte e al ricaricamento della scena: senza questa riga,
	## chi muore bruciando si ritrova a rantolare sulla schermata di morte e poi
	## anche al respawn, dove non gli sta succedendo piu' niente.
	Suoni.dolore_continuo_azzera()
	death_started.emit()
	if not reload_scene_on_death:
		return
	await get_tree().create_timer(3).timeout
	# Respawn GLOBALE: se esiste un checkpoint (Cono) torna lì, anche in un'altra
	# scena; altrimenti il CheckpointManager ricarica la scena (fallback template).
	# Nelle scene con un director (Traccia) reload_scene_on_death è false e il
	# respawn in-scena lo gestisce il director via death_started — qui non si passa.
	var cm := get_node_or_null("/root/CheckpointManager")
	if cm and cm.has_method("on_player_died"):
		cm.on_player_died(self)
	else:
		get_tree().reload_current_scene()

## Hook minimo per un respawn IN-SCENA senza reload (Traccia Perduta →
## traccia_perduta_director.gd, che riporta il player al checkpoint attivo
## invece di ricaricare l'intero livello). Va chiamato con
## `reload_scene_on_death = false`, altrimenti il timer sopra ricarica comunque.
func _on_loadout_changed() -> void:
	var loadout := get_node_or_null("/root/EquipmentLoadout")
	if loadout:
		loadout.apply_to(health_system)


func revive() -> void:
	is_dead = false
	input_fully_locked = false
	velocity = Vector3.ZERO
	busy = false
	dodging = false
	guarding = false
	slowed = false
	_attack_active = false
	_buffered_attack = false
	if animation_tree:
		animation_tree.active = true
		# Fuori dallo stato "Death", o si rinasce a terra: vedi revive_from_death().
		animation_tree.revive_from_death()
	current_state = state.FREE
	hurt_cool_down.stop()
	_reset_death_card()

## La "death card" del template (TriggeredSounds/LifeCardAnimations) reagisce da
## sola a `death_started` e porta `DeadBackground` (nero a tutto schermo) da
## trasparente a OPACO in 2 secondi — pensata per una morte che ricarica la
## scena, quindi non si riazzera mai. Con il respawn in-scena del director
## restavi vivo davanti al Cono ma con lo schermo che diventava nero un istante
## dopo il fade-in. L'animazione "RESET" della stessa libreria rimette a zero i
## due veli (e spegne i suoni di morte/vita): è il modo pulito di annullarla.
func _reset_death_card() -> void:
	var ap := get_node_or_null("TriggeredSounds/LifeCardAnimations") as AnimationPlayer
	if ap == null:
		# Il player Dawnkeep è una COPIA della scena template: se un domani la
		# gerarchia cambia, ritrova comunque il player della card per libreria.
		for n in find_children("*", "AnimationPlayer", true, false):
			var cand := n as AnimationPlayer
			if cand.has_animation("deadcard"):
				ap = cand
				break
	if ap and ap.has_animation("RESET"):
		ap.play("RESET")
		ap.advance(0.0)   # applica subito i valori, senza aspettare il frame

## ─── Morte per veleno (Arcanium) ─────────────────────────────────────────────
## Clip drammatica: il protagonista si afferra la gola e stramazza a terra. Tutti
## i comandi restano bloccati (`input_fully_locked`): si guarda solo la fine.
## Ritorna la durata (secondi) della clip, così il PrologueDirector allinea il
## ritmo del veleno al collasso. Vedi arcanium/systems/prologue_director.gd.
const POISON_DEATH_GLB := "res://assets/characters/anims/player_poison_death.glb"
const POISON_DEATH_FALLBACK_SEC := 6.5

func begin_poison_death() -> float:
	if input_fully_locked:
		return POISON_DEATH_FALLBACK_SEC
	input_fully_locked = true
	current_state = state.STATIC
	velocity = Vector3.ZERO
	# Le mani vanno alla gola: via arma e scudo (riequipaggiati al Crocevia, che
	# ricarica un'istanza fresca del player). Il lock impedisce che tornino visibili.
	system_visible(weapon_system, false)
	system_visible(gadget_system, false)
	# Stacca l'AnimationTree: non deve contendere la posa alla clip di morte.
	if animation_tree:
		animation_tree.active = false
	return _play_poison_death_clip()

## Inietta la clip PoisonDeath importata (GLB) nell'AnimationPlayer del player,
## rimappando i path-track sullo scheletro %GeneralSkeleton (stesso pattern del
## boss, _load_sword_library). Ritorna la lunghezza della clip, o il fallback se
## il GLB non è ancora presente/importato.
##
## ⚠️ Qui si riscrive SOLO il prefisso del path, non il nome dell'osso: la clip
## deve quindi essere già sul rig canonico. Fino al 2026-08-20 non lo era — era
## uno scheletro Mixamo a 24 ossa — e 15 tracce su 24 finivano su ossa
## inesistenti, in silenzio: niente gambe (il corpo non poteva accasciarsi) e
## niente braccia (le mani non arrivavano alla gola). L'originale sta in
## `assets/characters/anims/_sorgenti/`; il retarget lo fa
## `arcanium/tools/retarget_su_canonico.py`. Una clip che arriva da fuori va
## passata di lì PRIMA di finire qui.
func _play_poison_death_clip() -> float:
	var ap : AnimationPlayer = get_node_or_null("protagonist/AnimationPlayer")
	if ap == null or not ResourceLoader.exists(POISON_DEATH_GLB):
		return POISON_DEATH_FALLBACK_SEC
	var scene : PackedScene = load(POISON_DEATH_GLB)
	var inst := scene.instantiate()
	var src_ap : AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var length := POISON_DEATH_FALLBACK_SEC
	if src_ap and not src_ap.get_animation_list().is_empty():
		var src : Animation = src_ap.get_animation(src_ap.get_animation_list()[0])
		var anim : Animation = src.duplicate(true)
		for i in anim.get_track_count():
			var p := str(anim.track_get_path(i))
			var colon := p.find(":")
			if colon < 0:
				continue
			var bone := p.substr(colon + 1)
			anim.track_set_path(i, "%%GeneralSkeleton:%s" % bone)
		var lib : AnimationLibrary
		if ap.has_animation_library("arcanium"):
			lib = ap.get_animation_library("arcanium")
		else:
			lib = AnimationLibrary.new()
			ap.add_animation_library("arcanium", lib)
		if lib.has_animation("PoisonDeath"):
			lib.remove_animation("PoisonDeath")
		lib.add_animation("PoisonDeath", anim)
		length = anim.length
		ap.play("arcanium/PoisonDeath")
	inst.queue_free()
	return length
		
func system_visible(_system_node,_new_toggle):
		if _system_node:
			_system_node.visible = _new_toggle

func trigger_interact(interact_type:String):
	if busy:
		return
	busy = true
	interact_started.emit(interact_type)
	await animation_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	busy = false
		
func trigger_event(signal_name:String):
	if busy or dodging:
		return
	busy = true
	emit_signal(signal_name)
	await animation_tree.animation_measured
	await get_tree().create_timer(anim_length).timeout
	event_finished.emit()
	busy = false


func jump():
	# Handle jump.
	if is_on_floor():
		if not _try_spend_stamina(cost_jump):
			return
		jump_started.emit()
		await get_tree().create_timer(.2).timeout # for the windup
		velocity.y = jump_velocity

func set_root_move(delta):
	var game_menu := get_node_or_null("/root/GameMenu")
	## ⚠️ LO STORDIMENTO VA ANCHE QUI, non basta il gate in `_input()`.
	##
	## Quel gate ferma le AZIONI — parata, attacco, schivata — perche' arrivano
	## come `InputEvent`. Il MOVIMENTO no: si legge a polling con
	## `Input.get_vector`, dentro il ciclo di fisica, e non passa mai da
	## `_input()`. Risultato misurato in gioco: da storditi non ci si poteva
	## difendere ne' attaccare, ma con WASD si camminava via tranquillamente —
	## cioe' lo stun toglieva le risposte e lasciava la fuga, l'esatto contrario
	## di cio' che serve.
	##
	## La lezione generale: bloccare l'input in un motore vuol dire bloccarlo in
	## DUE posti, perche' gli eventi e il polling sono due strade diverse. Questa
	## riga e' la seconda, ed e' anche il posto giusto: e' l'elenco dove vivono
	## gia' tutti gli altri blocchi.
	if is_stunned() or input_fully_locked or placement_active or (game_menu and game_menu.is_blocking()):
		input_dir = Vector2.ZERO
	else:
		input_dir = Input.get_vector("move_left","move_right","move_up","move_down")
	#set_quaternion(get_quaternion() * animation_tree.get_root_motion_rotation())
	var rate : float # imiates directional change acceleration rate
	if is_on_floor():
		rate = .5
	else:
		rate = .1
	var new_velocity = get_quaternion() * animation_tree.get_root_motion_position() / delta

	if is_on_floor():
		velocity.x = move_toward(velocity.x, new_velocity.x, rate)
		velocity.y = move_toward(velocity.y, new_velocity.y, rate)
		velocity.z = move_toward(velocity.z, new_velocity.z, rate)
	else:
		velocity.x = move_toward(velocity.x, calc_direction().x * speed, rate)
		velocity.z = move_toward(velocity.z, calc_direction().z * speed, rate)

	
func set_root_climb(delta):
	input_dir = Input.get_vector("move_left","move_right","move_up","move_down")
	
	var rate = 2
	var new_velocity = get_quaternion() * animation_tree.get_root_motion_rotation() * animation_tree.get_root_motion_position() / delta
	
	#velocity = lerp (velocity,new_velocity,rate) #buggier than move_toward
	velocity.x = move_toward(velocity.x, new_velocity.x, rate)
	velocity.y = move_toward(velocity.y, new_velocity.y, rate)
	velocity.z = move_toward(velocity.z, new_velocity.z, rate)
	# dismount logic
	if !sensor_cast.is_colliding():
		#print("cast not colliding")
		current_state = state.FREE
		last_altitude = global_position
		var dismount_pos = to_global(Vector3.BACK)
		dismount_pos.y += .5
		var tween = create_tween()

		tween.tween_property(self,"global_position",dismount_pos,.3)
	if is_on_floor():
		current_state = state.FREE
		#free_started.emit()
	
		
## Direzione di movimento richiesta dall'input, ORIZZONTALE e con la lunghezza
## dell'input: `input_dir` pieno su un asse dà sempre un vettore lungo 1,
## qualunque sia la rotazione e lo zoom della camera.
##
## ⚠️ Gli assi della camera NON si possono usare grezzi. La iso guarda il player
## da (0, 28, 22), cioè 52° sotto l'orizzonte: il suo `basis.z` proiettato a
## terra è lungo cos(52°) ≈ 0.62, mentre `basis.x` — che è orizzontale — è lungo
## 1. Sommandoli così, "avanti" pesa il 62% di "di lato". A camera ferma non si
## nota, perché il personaggio si orienta lungo quella stessa direzione; ma in
## LOCK-ON il player guarda il BERSAGLIO, e il moto passa per la blend space di
## strafe (`move_dot_product`/`strafe_cross_product`, vedi `rotate_player`): lì
## l'asimmetria si proietta su assi che ruotano con la camera, e la velocità
## risultante — che è ROOT MOTION, quindi proporzionale al punto di blend — cala
## fino al 62% a certe angolazioni. Sintomo: con la camera girata di 45° o 90°
## il personaggio va piano o quasi non parte, e non si riesce a schivare.
func calc_direction() -> Vector3 :
	## ⚠️ La condizione è l'AGGANCIO, non `strafing`. `dodge()` spegne `strafing`
	## per la durata della rotolata (serve all'AnimationTree), e legandoci il
	## frame dei tasti la rotolata partiva camera-relativa mentre l'input era
	## stato dato in coordinate bersaglio: premendo D si rotolava all'indietro.
	if strafing or lock_on_target() != null:
		return _direzione_dal_bersaglio()
	## `current_camera` non è tipizzato: `:=` qui non inferisce e il file non
	## compila proprio.
	var cam : Basis = current_camera.global_transform.basis
	var avanti := Vector3(cam.z.x, 0.0, cam.z.z)
	var lato := Vector3(cam.x.x, 0.0, cam.x.z)
	## camera a piombo: `basis.z` non ha più proiezione a terra e l'"avanti" di
	## schermo diventa l'alto della camera
	if avanti.length_squared() < 0.000001:
		avanti = Vector3(-cam.y.x, 0.0, -cam.y.z)
	if avanti.length_squared() < 0.000001 or lato.length_squared() < 0.000001:
		return Vector3.ZERO
	return avanti.normalized() * input_dir.y + lato.normalized() * input_dir.x

## In LOCK-ON i tasti sono relativi al BERSAGLIO, non alla camera: A e D girano
## sempre attorno al nemico, W e S avvicinano e allontanano, qualunque sia
## l'angolo fra camera e nemico.
##
## ⚠️ Perché non basta la camera. Agganciato, il player guarda il BERSAGLIO, e
## il moto passa per la blend space di strafe, che è espressa nel frame del
## player (`move_dot_product` / `strafe_cross_product` in `rotate_player`).
## Con una direzione camera-relativa quella proiezione ruota insieme alla
## camera: girando la visuale, "vai a destra" finiva sotto W e il giocatore
## doveva ricalcolarsi a mente la mappatura dei tasti a ogni rotazione.
## Prendendo gli assi dal player la mappatura è fissa per costruzione.
##
## Nel caso in cui camera e player sono allineati questa formula dà lo STESSO
## risultato di prima — cambia solo che ora non dipende più da dove guarda la
## camera.
## ⚠️ L'"avanti" si prende dalla direzione PLAYER→BERSAGLIO, non dalla rotazione
## del player. Sembrano la stessa cosa — agganciato, il player guarda il
## bersaglio — ma non lo sono appena qualcosa lo fa girare: durante la ROTOLATA
## il personaggio ruota verso la direzione di rotolamento, e un frame ricavato
## dalla sua rotazione gli girerebbe sotto frame per frame, incurvando la
## rotolata. Ancorandolo al bersaglio la mappatura dei tasti resta ferma anche
## mentre il player gira.
func _direzione_dal_bersaglio() -> Vector3:
	var avanti := Vector3.ZERO
	var locked = lock_on_system.current_target if lock_on_system else null
	if is_instance_valid(locked):
		avanti = locked.global_position - global_position
		avanti.y = 0.0
	if avanti.length_squared() < 0.000001:
		## strafe senza bersaglio (ripiego del template): resta il player
		var b : Basis = global_transform.basis
		avanti = Vector3(b.z.x, 0.0, b.z.z)
	if avanti.length_squared() < 0.000001:
		return Vector3.ZERO
	avanti = avanti.normalized()
	## Guardando lungo `avanti` con l'alto in +Y, la destra è `avanti × UP`.
	var destra := avanti.cross(Vector3.UP)
	## `input_dir.y` cresce verso il BASSO dello schermo (Input.get_vector), per
	## questo W vale -1 e l'avanti va preso col segno opposto.
	return avanti * -input_dir.y + destra * input_dir.x


## Il bersaglio agganciato, o null. Lo legge anche la IsoCam per allinearsi.
func lock_on_target() -> Node3D:
	if lock_on_system == null:
		return null
	var t = lock_on_system.current_target
	return t if is_instance_valid(t) else null


## ─── IL FENDENTE ────────────────────────────────────────────────────────────
##
## Il fischio dell'arma nell'aria. Parte con lo SWING, non al contatto: e' il
## suono della lama che viaggia, e il contatto e' un altro suono (il colpo), che
## e' un'altra famiglia ancora da fare.
##
## ⚠️ Il fendente si sceglie per il TIPO DI DANNO dell'arma, non per l'arma: una
## lama e una lancia fendono l'aria allo stesso modo, una mazza la SPINGE. Sono
## due suoni per tutto l'arsenale, e la personalita' della singola arma vive nel
## colpo. (Vedi docs/09_AUDIO_SFX.md.)
func _suona_fendente() -> void:
	var tipo := "TAGLIO"
	var info = _arma_equipaggiata()
	if info != null and "damage_type" in info:
		tipo = str(info.damage_type)
	## `secondary_action` e' gia' la levetta che instrada l'AnimationTree sul ramo
	## pesante: la stessa distinzione vale per il suono, senza inventarne un'altra.
	Suoni.nel_mondo(self, Suoni.fendente(tipo, secondary_action), -2.0)


## La risorsa dell'arma in mano, se c'e'. Ritorna null senza rumore: un
## personaggio a mani nude non deve far fischiare niente di sbagliato.
func _arma_equipaggiata():
	if weapon_system == null:
		return null
	var eq = weapon_system.get("current_equipment")
	if eq == null:
		return null
	return eq.get("equipment_info")
