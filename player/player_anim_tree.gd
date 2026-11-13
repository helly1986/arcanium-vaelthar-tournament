extends AnimationTree
class_name AnimationTreeSoulsBase

const MovesetNostro := preload("res://arcanium/systems/moveset_nostro.gd")

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
	_aggiungi_affondo()
	_aggiungi_colpi_caricati()
		
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

	_prepara_idle_dalla_posa()
	_prepara_aggancio()
	_salta_risveglio_se_non_serve()


## ─── L'IDLE RIPARTE DALLA POSA ──────────────────────────────────────────────
## Le idle d'autore dei campioni durano 6 s e hanno gesti larghi (Kessra alza il
## martello). Nello spazio di fusione della camminata ogni clip continua a
## scorrere anche a peso zero (`sync_mode` Independent), e sotto un fendente
## l'idle va avanti: fermandosi si rientrava in un punto a caso del giro, e il
## martello saliva in un decimo di secondo (2026-10-27).
##
## Qui l'idle resta inchiodata al fotogramma 0 — la Posa, la stessa posa neutra
## da cui partono le altre clip — finche' NON SI VEDE: in cammino, sotto un
## gesto a peso pieno, in un altro stato. Riparte quando torna a pesare.
##
## ⚠️ La si riporta a 0 solo quando non pesa niente, mai mentre sfuma: un salto
## sotto un peso parziale e' proprio lo scatto da togliere.
##
## La posizione di una clip nell'albero non si scrive (`current_position` e' in
## sola lettura): il punto (0, 0) di ogni spazio di fusione `MoveStrafe` viene
## avvolto, al primo avvio, in un BlendTree con un TimeSeek davanti.

## Oltre questa distanza dal centro l'idle non pesa piu': i passi stanno a 0,3.
const IDLE_SPARITA := 0.3
## Spento solo dalla controprova di `verifica_idle_dalla_posa.gd`.
var idle_dalla_posa := true
## Albero d'arma ("SLASH_tree") → il parametro seek_request della sua idle.
var _idle_seek : Dictionary = {}
## I gesti che coprono tutto il corpo: con un filtro (solo le braccia) sotto si
## vede ancora l'idle.
var _gesti_pieni : PackedStringArray = []


## Ampiezza del passo da agganciati senza corsa: e' la distanza dei punti degli
## strafe a passo dal centro della blend space.
const PASSO_AGGANCIATO := 0.3

## Col nemico AGGANCIATO alcuni punti della blend space `MoveStrafe` suonano un'altra
## clip: il movimento libero usa solo l'asse in avanti, l'aggancio tutto il piano, e i
## punti avanti/indietro sono gli stessi (2026-11-09: indietro suonava il cammino IN
## AVANTI). Posizione del punto -> clip da agganciati; si usa solo se il corpo ce l'ha
## (le clip nostre stanno nella scheda del campione, CampioneResource.clip_d_autore),
## altrimenti resta quella di prima. Il nodo del punto si sostituisce con uno suo, cosi'
## cambiarne la clip non tocca gli altri punti che condividono la risorsa.
## Per albero d'arma: le armi a due mani (HEAVY) hanno le loro (Zarine, 2026-11-10: agganciata
## va in guardia al passo).
const AGGANCIO := {
	"SLASH_tree": {
		Vector2(0, -0.3): &"MeleeLib/root-LightStrafeBwalk",
		Vector2(0, 0.3): &"MeleeLib/root-LightStrafeFwalk",
		## Di corsa all'indietro (2026-11-10): prima la corsa in avanti suonata al contrario.
		Vector2(0, -0.9): &"MeleeLib/root-LightStrafeBrun",
	},
	"HEAVY_tree": {
		Vector2(0, 0.3): &"MeleeLib/root-HeavyStrafeFwalk",
		Vector2(0, -0.3): &"MeleeLib/root-HeavyStrafeBwalk",
		## Non root-HeavyStrafeLWalk e RWalk: quelle ci sono gia' nella libreria di tutti, e
		## agganciati gli altri campioni le suonerebbero diverse (il punto a sinistra la suona al
		## contrario).
		Vector2(-0.3, 0): &"MeleeLib/root-HeavyStrafeLwalk",
		Vector2(0.3, 0): &"MeleeLib/root-HeavyStrafeRwalk",
		## Di corsa con l'asta in spalla; anche qui nomi nuovi, HeavyStrafeL/R sono di tutti.
		Vector2(-1, 0): &"MeleeLib/root-HeavyStrafeLrun",
		Vector2(1, 0): &"MeleeLib/root-HeavyStrafeRrun",
		Vector2(0, -1): &"MeleeLib/root-HeavyStrafeBrun",
	},
}
## [nodo, clip libera, clip agganciata]
var _aggancio : Array = []
var _agganciato := false


func _prepara_aggancio() -> void:
	var stati : AnimationNodeStateMachine = tree_root.get_node("MovementStates")
	for stato in stati.get_node_list():
		var albero = stati.get_node(stato)
		if not albero is AnimationNodeStateMachine or not albero.has_node("MoveStrafe"):
			continue
		var spazio = albero.get_node("MoveStrafe")
		if not spazio is AnimationNodeBlendSpace2D:
			continue
		var punti : Dictionary = AGGANCIO.get(String(stato), {})
		for i in spazio.get_blend_point_count():
			for punto in punti:
				var vecchio = spazio.get_blend_point_node(i)
				if spazio.get_blend_point_position(i).is_equal_approx(punto) and vecchio is AnimationNodeAnimation:
					var nuovo := AnimationNodeAnimation.new()
					nuovo.animation = vecchio.animation
					spazio.set_blend_point_node(i, nuovo)
					_aggancio.append([nuovo, vecchio.animation, punti[punto]])


func _aggiorna_aggancio() -> void:
	if player_node.strafing == _agganciato:
		return
	_agganciato = player_node.strafing
	var ap := get_node(anim_player) as AnimationPlayer
	for v in _aggancio:
		var voluta : StringName = v[2] if _agganciato and ap.has_animation(v[2]) else v[1]
		(v[0] as AnimationNodeAnimation).animation = voluta


func _prepara_idle_dalla_posa() -> void:
	var stati : AnimationNodeStateMachine = tree_root.get_node("MovementStates")
	for stato in stati.get_node_list():
		var albero = stati.get_node(stato)
		if not albero is AnimationNodeStateMachine or not albero.has_node("MoveStrafe"):
			continue
		var spazio = albero.get_node("MoveStrafe")
		if not spazio is AnimationNodeBlendSpace2D:
			continue
		for i in spazio.get_blend_point_count():
			if spazio.get_blend_point_position(i) != Vector2.ZERO:
				continue
			var nodo : AnimationNode = spazio.get_blend_point_node(i)
			if nodo is AnimationNodeAnimation:
				var bt := AnimationNodeBlendTree.new()
				bt.add_node("Idle", nodo)
				bt.add_node("Seek", AnimationNodeTimeSeek.new())
				bt.connect_node("Seek", 0, "Idle")
				bt.connect_node("output", 0, "Seek")
				spazio.set_blend_point_node(i, bt)
				nodo = bt
			if nodo is AnimationNodeBlendTree and (nodo as AnimationNodeBlendTree).has_node("Seek"):
				_idle_seek[String(stato)] = "parameters/MovementStates/%s/MoveStrafe/%s/Seek/seek_request" % [
						stato, spazio.get_blend_point_name(i)]
	for n in (tree_root as AnimationNodeBlendTree).get_node_list():
		var gesto = tree_root.get_node(n)
		if gesto is AnimationNodeOneShot and not gesto.is_filter_enabled():
			_gesti_pieni.append(String(n))


## Vero se l'idle dell'albero d'arma in uso non si vede.
func idle_nascosta() -> bool:
	if base_state_machine.get_current_node() != StringName(weapon_type + "_tree"):
		return true
	if current_weapon_tree == null or current_weapon_tree.get_current_node() != &"MoveStrafe":
		return true
	var pos : Vector2 = get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position")
	if pos.length() >= IDLE_SPARITA:
		return true
	for g in _gesti_pieni:
		if get("parameters/%s/active" % g) and get("parameters/%s/fade_in_remaining" % g) <= 0.0:
			return true
	return false


## ─── LA PARTENZA A CAMMINARE ────────────────────────────────────────────────
## La posizione nello spazio di fusione insegue l'input del 20% per
## fotogramma, e i passi stanno a 0,3 dal centro: alla prima pressione la
## posizione salta a 0,2 e l'idle passa da peso pieno a un terzo in UN
## fotogramma. Misurato su Kessra (misura_uscita_idle.gd): 51 gradi di strappo
## per fotogramma sulla mano sinistra partendo dalla Posa, 115 dal giogo —
## un taglio, per ogni campione (2026-10-27).
##
## Dentro il cerchio dell'idle il passo si limita: attraversarlo dura almeno
## RACCORDO_IDLE. Fuori resta l'inseguimento di prima, che decide la prontezza
## della camminata.
const RACCORDO_IDLE := 0.2
## "rampa" (il passo limitato), "nessuno" (com'era): lo cambia solo la misura.
var raccordo_cammino := "rampa"


func _insegui(attuale : Vector2, meta : Vector2) -> Vector2:
	var nuovo : Vector2 = lerp(attuale, meta, .2)
	if raccordo_cammino != "rampa":
		return nuovo
	if attuale.length() >= IDLE_SPARITA and nuovo.length() >= IDLE_SPARITA:
		return nuovo
	var passo := nuovo - attuale
	var massimo := IDLE_SPARITA * get_process_delta_time() / RACCORDO_IDLE
	return attuale + passo.limit_length(massimo)


## Il tempo dell'idle dell'albero d'arma in uso, in secondi dall'inizio del
## giro; -1 se non si vede. Serve a chi si aggancia a un momento dell'idle
## (le scintille di Kessra, scintille_idle.gd).
func tempo_idle() -> float:
	var chiave := weapon_type + "_tree"
	if idle_nascosta() or not _idle_seek.has(chiave):
		return -1.0
	return get(String(_idle_seek[chiave]).replace("/Seek/seek_request", "/Idle/current_position"))


func _tieni_idle_alla_posa() -> void:
	if not idle_dalla_posa:
		return
	var nascosta := idle_nascosta()
	for albero in _idle_seek:
		if nascosta or albero != weapon_type + "_tree":
			set(_idle_seek[albero], 0.0)


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
	
	_aggiorna_aggancio()
	if player_node.strafing:
		set_strafe()
	else:
		set_free_move()
		
	if player_node.current_state == player_node.state.CLIMB:
		set_ladder()

	set_guarding()
	_tieni_idle_alla_posa()


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
	if attack_count > _colpi_della_catena():
		attack_count = 1


## La catena leggera da TRE dell'arma a una mano (l'utente, 2026-11-13): «due spadate in
## slash obliquo» e «un affondo finale». Il terzo stato si aggiunge qui all'ATTACK_tree/SLASH,
## come i primi due (Start -> Slash4 con `attack_count == 3`, in fondo -> End), invece che
## nel .tscn: la scena la risalva l'editor. Le altre armi restano a `max_attack_count`.
const AFFONDO := &"MeleeLib/root-SlashThrust"
func _aggiungi_affondo() -> void:
	var attacchi = tree_root.get_node("ATTACK_tree") if tree_root.has_node("ATTACK_tree") else null
	var sm = attacchi.get_node("SLASH") if attacchi != null and attacchi.has_node("SLASH") else null
	if not (sm is AnimationNodeStateMachine) or sm.has_node("Slash4"):
		return
	var clip := AnimationNodeAnimation.new()
	clip.animation = AFFONDO
	sm.add_node("Slash4", clip, Vector2(488, 340))
	var entra := AnimationNodeStateMachineTransition.new()
	entra.xfade_time = 0.2
	entra.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	entra.advance_expression = "attack_count == 3"
	sm.add_transition("Start", "Slash4", entra)
	var esce := AnimationNodeStateMachineTransition.new()
	esce.xfade_time = 0.3
	esce.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	esce.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Slash4", "End", esce)


## ─── I COLPI CARICATI (2026-11-13) ─────────────────────────────────────────
## L'utente: «mettere un wind-up ai colpi caricati... piu' tieni premuto, piu' carichi il
## colpo fino ad un massimo». Per ogni colpo forte tre stati nell'ATTACK_tree/SLASH:
##   Carica<Tipo>  la preparazione fino alla tensione massima (attacchi_una_mano.py,
##                 carica_forte / carica_affondo, f0-f15);
##   Tieni<Tipo>   ferma sulla posa di massima tensione (f15) finche' si tiene premuto;
##   Rilascio<Tipo> la clip d'attacco presa dalla SUA carica (forte f10, affondo f8):
##                 il gesto non riparte da capo.
## Ci si entra con `player_node.carica_attiva` e il tipo, si rilascia con
## `player_node.carica_rilasciata` (anche durante la preparazione). Le transizioni hanno
## priorita' 0: battono `attack_count == 1`, che e' vera anche mentre si carica.
const CARICHE := {
	## tipo: [clip della preparazione, clip dell'attacco, frame della carica nell'attacco]
	0: ["Forte", &"MeleeLib/CaricaForte", &"MeleeLib/root-Slash3", 10],
	1: ["Affondo", &"MeleeLib/CaricaAffondo", &"MeleeLib/root-SlashThrust", 8],
}
const TESO_DA := 15.0 / 30.0   ## dove la preparazione arriva alla tensione massima

func _aggiungi_colpi_caricati() -> void:
	var attacchi = tree_root.get_node("ATTACK_tree") if tree_root.has_node("ATTACK_tree") else null
	var sm = attacchi.get_node("SLASH") if attacchi != null and attacchi.has_node("SLASH") else null
	if not (sm is AnimationNodeStateMachine):
		return
	for tipo in CARICHE:
		var nome : String = String(CARICHE[tipo][0])
		if sm.has_node("Carica" + nome):
			continue
		var y : float = 420.0 + 70.0 * tipo
		var carica := AnimationNodeAnimation.new()
		carica.animation = CARICHE[tipo][1]
		carica.use_custom_timeline = true
		carica.start_offset = 0.0
		carica.timeline_length = TESO_DA
		sm.add_node("Carica" + nome, carica, Vector2(380, y))
		var tieni := AnimationNodeAnimation.new()
		tieni.animation = CARICHE[tipo][1]
		tieni.use_custom_timeline = true
		tieni.start_offset = TESO_DA
		## Ferma sulla posa di massima tensione (l'utente: «non deve ripetere l'animazione di
		## carica più volte ma deve restare nella posa di carica»): un solo fotogramma a ciclo,
		## che non finisce mai e tiene vivo l'oneshot finche' si tiene premuto.
		tieni.timeline_length = 1.0 / 30.0
		tieni.loop_mode = Animation.LOOP_LINEAR
		sm.add_node("Tieni" + nome, tieni, Vector2(500, y))
		var rilascio := AnimationNodeAnimation.new()
		rilascio.animation = CARICHE[tipo][2]
		rilascio.use_custom_timeline = true
		rilascio.start_offset = CARICHE[tipo][3] / 30.0
		rilascio.timeline_length = 0.8   ## si ricalcola dalla clip vera in prepara_carica()
		sm.add_node("Rilascio" + nome, rilascio, Vector2(620, y))
		var entra := _transizione(0.15, "player_node.carica_attiva and player_node.colpo_forte_tipo == %d" % tipo)
		entra.priority = 0
		sm.add_transition("Start", "Carica" + nome, entra)
		var tiene := _transizione(0.05, "")
		tiene.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		sm.add_transition("Carica" + nome, "Tieni" + nome, tiene)
		sm.add_transition("Carica" + nome, "Rilascio" + nome, _transizione(0.1, "player_node.carica_rilasciata"))
		sm.add_transition("Tieni" + nome, "Rilascio" + nome, _transizione(0.1, "player_node.carica_rilasciata"))
		var fine := _transizione(0.3, "")
		fine.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		sm.add_transition("Rilascio" + nome, "End", fine)


func _transizione(xfade : float, espressione : String) -> AnimationNodeStateMachineTransition:
	var tr := AnimationNodeStateMachineTransition.new()
	tr.xfade_time = xfade
	tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	tr.advance_expression = espressione
	return tr


## Vero se il campione ha la preparazione del colpo caricato `tipo` (0 forte, 1 affondo).
func ha_carica(tipo : int) -> bool:
	var ap := get_node_or_null(anim_player) as AnimationPlayer
	return ap != null and ap.has_animation(CARICHE[tipo][1]) and ap.has_animation(CARICHE[tipo][2])


## Prima di caricare: la durata del rilascio dalla clip vera (le clip dei campioni possono
## cambiare lunghezza), e la si restituisce al player, che ci tiene i tempi del colpo.
func prepara_carica(tipo : int) -> float:
	var ap := get_node_or_null(anim_player) as AnimationPlayer
	var sm = tree_root.get_node("ATTACK_tree").get_node("SLASH")
	var rilascio : AnimationNodeAnimation = sm.get_node("Rilascio" + String(CARICHE[tipo][0]))
	var durata : float = ap.get_animation(CARICHE[tipo][2]).length - rilascio.start_offset
	rilascio.timeline_length = maxf(0.1, durata)
	return rilascio.timeline_length


## Il colpo caricato e' stato interrotto (un colpo subito): l'oneshot si chiude.
func ferma_attacco() -> void:
	set("parameters/Attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Quanti colpi ha la catena leggera dell'arma in mano: tre con la una mano (se la clip
## dell'affondo c'e'), altrimenti quelli del template.
func _colpi_della_catena() -> int:
	var ap := get_node_or_null(anim_player) as AnimationPlayer
	if weapon_type == "SLASH" and ap != null and ap.has_animation(AFFONDO):
		return 3
	return max_attack_count


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
	_clip_per_tipo("MovementStates/SPRINT_tree/Sprint")
	base_state_machine.travel("SPRINT_tree")


## Lo sprint e la rotolata sono uno stato solo per tutti i tipi d'arma: la clip la sceglie il
## tipo in mano (moveset_nostro.gd, PER_STATO), se il corpo ce l'ha. Si sceglie quando lo
## stato parte, perche' il corpo del campione carica le sue clip dopo l'albero. Il nodo si
## sostituisce con uno suo, come quelli dell'aggancio.
var _per_tipo : Dictionary = {}

func _clip_per_tipo(stato : String) -> void:
	if not _per_tipo.has(stato):
		var parti := stato.split("/")
		var macchina : AnimationNode = tree_root
		for k in parti.size() - 1:
			macchina = macchina.get_node(parti[k]) if macchina != null and macchina.has_node(parti[k]) else null
		if not macchina is AnimationNodeStateMachine or not macchina.has_node(parti[-1]):
			return
		var vecchio = macchina.get_node(parti[-1])
		var nuovo := AnimationNodeAnimation.new()
		nuovo.animation = MovesetNostro.ripiego(stato)
		if vecchio is AnimationNodeAnimation:
			nuovo.play_mode = vecchio.play_mode
		macchina.replace_node(parti[-1], nuovo)
		## [nodo, come il .tscn suonava il ripiego]
		_per_tipo[stato] = [nuovo, nuovo.play_mode]
	var ap := get_node(anim_player) as AnimationPlayer
	var voluta := MovesetNostro.clip_dello_stato(stato, weapon_type)
	var nodo : AnimationNodeAnimation = _per_tipo[stato][0]
	if ap.has_animation(voluta) and voluta != MovesetNostro.ripiego(stato):
		## Le clip nostre si suonano in avanti (il salto all'indietro non e' la rotolata al
		## contrario).
		nodo.animation = voluta
		nodo.play_mode = AnimationNodeAnimation.PLAY_MODE_FORWARD
	else:
		nodo.animation = MovesetNostro.ripiego(stato)
		nodo.play_mode = _per_tipo[stato][1]

func _on_dodge_started():
	_clip_per_tipo("DODGE_tree/Roll")
	_clip_per_tipo("DODGE_tree/JumpBack")
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
		## Agganciati si va a passo (i punti a 0,3 della blend space: gli strafe in
		## guardia); la corsa si chiede (Alt tenuto, L3): player.corsa_chiesta().
		var passo := 1.0 if player_node.corsa_chiesta() else PASSO_AGGANCIATO
		new_blend *= Vector2(abs(player_node.input_dir.x),abs(player_node.input_dir.y)) * passo
	lerp_movement = get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position")
	lerp_movement = _insegui(lerp_movement, new_blend)
	set("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position", lerp_movement)

func set_free_move():
	# Non-strafing "free" movement, is just the forward input direction.
	var new_blend = Vector2(0,abs(player_node.input_dir.x) + abs(player_node.input_dir.y))
	if player_node.slowed:
		new_blend *= .4 # force a walk speed
	lerp_movement = get("parameters/MovementStates/" + weapon_type + "_tree/MoveStrafe/blend_position")
	lerp_movement = _insegui(lerp_movement, new_blend)
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
