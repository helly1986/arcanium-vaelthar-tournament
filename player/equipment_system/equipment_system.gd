extends Node3D
class_name EquipmentSystem

## A node that listens for signals from a player node to change equipment, or
## to activate and deactivate Area3D equipment nodes.
## When the 'change_signal" emits from the player node, the child #0 under
## the held_mount_point will reparent to the stored_mount_point, and same for
## child #0 of stored, will move to held. Handy for swaping objects from hand
## bones to back bones or similar.

## the Activate and deactivate signals will turn on and off monitoring for the 
## area3d children. Also if they hit things in the target_group they'll emit
## the hit_target signal, and if they hit anything else, they'll emit hit_world
## signal. Hitting target will communicate equipment and player_node info to the
## object receiving the hit.



## The node that will emit the weapon change signal
@export var player_node : CharacterBody3D
## The object group to detect 
@export var target_group : String = "targets"

## The signal name from player_node for when the item should be active.
## items themselves should manage what "active" means, but typically this is
## monitoring/collision shapes, emitters,sound FX, etc. 
@export var activate_signal : String = "attack_started"
## Signal to cancel if the collision monitoring of the held item.
@export var deactivate_signal : String = "hurt_started"
## The signal name should be connected to trigger the equipment swap
@export var change_signal : String = "weapon_changed"
## The primary item location. Bone attachments or Marker3Ds work well for placement
@export var held_mount_point : Node3D
## The secondary item location. Bone attachments or Marker3Ds work well for placement
@export var stored_mount_point : Node3D
## The item currently under the primary held mount node
@onready var current_equipment : EquipmentObject
## The item currently under the stored/sheathed node
@onready var stored_equipment : EquipmentObject
@export var activate_delay : float = .2

## Moltiplicatore di potenza dei finisher (backstab/riposte/critico), applicato
## in _on_body_entered quando il player ha `finisher_active` alzato.
const FINISHER_POWER_MULT : float = 3.75

@export_flags_3d_physics var collision_detect_layers = 15

signal hit_target
signal hit_world
signal equipment_changed(new_equipment : EquipmentObject)

## ─── Colpo di PROSSIMITÀ (stile boss) ────────────────────────────────────────
## La lama è un Area3D FISICO: contro nemici bassi/piccoli (il lupo) può passargli
## sopra e mancare. Come per il boss, aggiungiamo una hitbox "logica" durante la
## finestra d'attacco: chi è vicino viene colpito a QUALSIASI ALTEZZA. Molto
## vicino = qualunque angolo; poco più lontano = solo nel cono frontale.
@export var proximity_hit_enabled : bool = true
@export var proximity_close_range : float = 1.3   ## entro questo: colpisci a 360°, ogni altezza
## Deve COPRIRE la portata della lama fisica (~2.4m): altrimenti tra la fine del
## cono e la punta della lama resta una fascia dove solo l'Area3D flaky decide, e
## i colpi "che dovrebbero andare a segno" a volte mancano (bug consumati a distanza).
@export var proximity_cone_range : float = 2.6
@export_range(0.0, 1.0) var proximity_cone_dot : float = 0.35   ## cos(~70°): mezzo cono più generoso

## Bersagli già colpiti in QUESTO fendente: la lama fisica e la prossimità
## condividono questa lista, così nessuno prende danno doppio dallo stesso colpo.
var _hit_this_swing : Array = []

func _ready():
	
	if player_node:
		if player_node.has_signal(change_signal):
			player_node.connect(change_signal,_on_equipment_changed)
		## needed to turn on/off monitoring when attacks start/end
		if player_node.has_signal(activate_signal):
			player_node.connect(activate_signal,_on_activated)
		## Finisher (backstab/riposte): usano segnali propri, non attack_started —
		## senza questo la lama resta spenta e il finisher non fa alcun danno.
		for finisher_signal in ["backstab_started", "riposte_started"]:
			if player_node.has_signal(finisher_signal):
				player_node.connect(finisher_signal,_on_activated)
		## needed to turn off monitoring if hurt mid-attack
		if player_node.has_signal(deactivate_signal):
			player_node.connect(deactivate_signal,_on_stop_signal)

	## update what weapon we're starting with
	if held_mount_point:
		if held_mount_point.get_child(0):
			current_equipment = held_mount_point.get_child(0)
			current_equipment.equipped = true
			current_equipment.monitoring = false
			current_equipment.collision_layer = collision_detect_layers
			if current_equipment.has_signal("body_entered"):
				current_equipment.body_entered.connect(_on_body_entered)
	## update what gadget we're holding
	if stored_mount_point:
		if stored_mount_point.get_child(0):
			stored_equipment = stored_mount_point.get_child(0)
			stored_equipment.equipped = false
			stored_equipment.monitoring = false
			current_equipment.collision_mask = collision_detect_layers

func _on_equipment_changed():
	await get_tree().create_timer(player_node.anim_length * .5).timeout
	if stored_mount_point.get_child(0) && held_mount_point.get_child(0):
		stored_equipment = stored_mount_point.get_child(0)
		
		## rearrange children
		held_mount_point.remove_child(current_equipment)
		stored_mount_point.remove_child(stored_equipment)
		
		held_mount_point.add_child(stored_equipment)
		stored_mount_point.add_child(current_equipment)
		
		# Update to current equipment, let them know they're equiped
		current_equipment.equipped = false
		if current_equipment.is_connected("body_entered", _on_body_entered):
			current_equipment.disconnect("body_entered",_on_body_entered)
		current_equipment = held_mount_point.get_child(0)
		
		await get_tree().process_frame
		if current_equipment.has_signal("body_entered"):
			current_equipment.body_entered.connect(_on_body_entered)
		current_equipment.equipped = true
		current_equipment.collision_mask = collision_detect_layers
		equipment_changed.emit(current_equipment)
		
func _on_activated():
	## Un ARCO non colpisce con se stesso: il danno viaggia con la freccia
	## (arcieria_player.gd). Senza questo la scatola dell'arma resterebbe quella
	## della spada e un nemico addosso prenderebbe un fendente da un tiro.
	if current_equipment and current_equipment.equipment_info != null 			and ("object_type" in current_equipment.equipment_info) 			and str(current_equipment.equipment_info.object_type) == "BOW":
		return
	## awaiting so the area3D starts monitoring about after attack wind-up
	if current_equipment:
		await get_tree().create_timer(player_node.anim_length *.3).timeout
		## pause and start monitoring to hit things
		_hit_this_swing.clear()   # nuovo fendente: azzera i bersagli già colpiti
		_suonato_questo_swing = false   # ...e il colpo torna a poter suonare
		current_equipment.monitoring = true
		await get_tree().create_timer(player_node.anim_length *.5).timeout
		## after moment turn off monitoring to not hit things
		current_equipment.monitoring = false


## ─── LA FINESTRA DI UNA TECNICA DI GUERRA ───────────────────────────────────
## Chi la apre e la chiude e' `TecnicaGuerraCaster`, seguendo il playhead del
## suo OneShot: qui non c'e' nessun timer, a differenza di `_on_activated`, e
## non e' un dettaglio — un timer che parte con la clip vive di vita propria,
## e se il gesto viene interrotto tiene la lama accesa a schermo vuoto (e' il
## difetto documentato in lucida_tecnica_caster.gd).
##
## `portata` diventa il TETTO della sonda di prossimita' per la durata della
## finestra: i fendenti colpiscono a 2,6 m, un affondo corto no. Si ripristina
## alla chiusura, sempre — anche se la finestra viene chiusa da un colpo subito.
var _portata_di_riposo : float = -1.0

func apri_finestra_tecnica(portata : float) -> void:
	if current_equipment == null:
		return
	_hit_this_swing.clear()
	_suonato_questo_swing = false
	if _portata_di_riposo < 0.0:
		_portata_di_riposo = proximity_cone_range
	if portata > 0.0:
		proximity_cone_range = minf(proximity_cone_range, portata)
	current_equipment.monitoring = true

func chiudi_finestra_tecnica() -> void:
	if current_equipment != null:
		current_equipment.monitoring = false
	if _portata_di_riposo >= 0.0:
		proximity_cone_range = _portata_di_riposo
		_portata_di_riposo = -1.0

## Sonda di prossimità: attiva SOLO mentre la lama monitora (la finestra
## d'attacco). Colpisce i "targets" vicini a qualsiasi altezza — vedi _apply_hit.
func _physics_process(_delta):
	if not proximity_hit_enabled or player_node == null:
		return
	if current_equipment == null or not current_equipment.monitoring:
		return
	var fwd : Vector3 = player_node.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		fwd = fwd.normalized()
	for raw in get_tree().get_nodes_in_group(target_group):
		var n := raw as Node3D
		if n == null or n in _hit_this_swing:
			continue
		var to : Vector3 = n.global_position - player_node.global_position
		to.y = 0.0                     # QUALSIASI ALTEZZA: distanza solo orizzontale
		var d := to.length()
		if d > proximity_cone_range:
			continue
		# Molto vicino → colpisci a 360°; oltre → solo se davanti (cono frontale).
		if d <= proximity_close_range or (d > 0.01 and fwd.dot(to / d) >= proximity_cone_dot):
			_apply_hit(n)

func _on_body_entered(_hit_body):
	if _hit_body.is_in_group(target_group):
		_apply_hit(_hit_body)
	else:
		hit_world.emit()
		_suona_colpo(true, _hit_body)

## Applica il colpo a un bersaglio, UNA sola volta per fendente (dedup condiviso
## fra lama fisica e sonda di prossimità). Estratto da _on_body_entered così i
## due percorsi non possono raddoppiare il danno.
func _apply_hit(_hit_body) -> void:
	if _hit_body in _hit_this_swing:
		return
	if not _hit_body.has_method("hit"):
		return
	_hit_this_swing.append(_hit_body)
	hit_target.emit()
	_suona_colpo(false, _hit_body)
	var info = current_equipment.equipment_info
	# Colpo forte (attack_strong): duplica la risorsa PRIMA di scalare potenza/
	# poise, per non mutare quella condivisa dagli attacchi leggeri.
	if player_node and player_node.secondary_action and info is ArcaniumEquipmentResource:
		info = info.duplicate()
		info.power = int(round(info.power * info.heavy_power_mult))
		info.poise_damage *= info.heavy_poise_mult
		## PESO DEL COLPO: la spadata caricata deve leggersi come caricata anche
		## contro un nemico che le dimezza il danno. Dichiararlo qui — dove si sa
		## che QUESTO fendente è pesante — è l'unico posto che funziona: la
		## risorsa dell'arma è la stessa per il colpo leggero e per quello forte,
		## quindi scriverlo lì li renderebbe indistinguibili.
		info.scossa = Scossa.MEDIO
	# Finisher (backstab/riposte/critico): danno maggiorato, one-shot per attacco.
	if player_node and ("finisher_active" in player_node) and player_node.finisher_active:
		player_node.finisher_active = false
		info = info.duplicate()
		info.power = int(round(info.power * FINISHER_POWER_MULT))
		## Un finisher è una esecuzione: vale un gradino sopra la caricata.
		if info is ArcaniumEquipmentResource:
			info.scossa = Scossa.PESANTE
	## Tecnica di guerra in corso (Legione Testuggine): il colpo e' quello della
	## tecnica, non il fendente dell'arma — una frazione della sua potenza e il
	## SUO tipo di danno (un affondo perfora, qualunque cosa dica la spada).
	## Si legge dal player, come `secondary_action`, perche' e' il player a sapere
	## che QUESTO contatto appartiene al gesto a strato e non a un fendente.
	if player_node and ("tecnica_in_corso" in player_node) and player_node.tecnica_in_corso != null 			and info is ArcaniumEquipmentResource:
		var tecnica : Resource = player_node.tecnica_in_corso
		info = info.duplicate()
		info.power = maxi(1, int(round(info.power * float(tecnica.get("danno_moltiplicatore")))))
		var tipo = tecnica.get("tipo_danno")
		if tipo is String and tipo != "":
			info.damage_type = tipo
	_hit_body.hit(player_node, info)

func _on_stop_signal():
	current_equipment.monitoring = false


## ─── IL SUONO DEL COLPO ─────────────────────────────────────────────────────
##
## ⚠️ Il colpo NON e' il fendente. Il fendente e' l'aria spostata dall'arma e
## parte con lo swing (vedi `_suona_fendente` nel player); questo e' il contatto,
## e parte quando l'arma tocca qualcosa. Sono due suoni distinti nello stesso
## gesto, ed e' la loro distanza a far sentire il peso dell'arma.
##
## Si distingue per TIPO DI DANNO (una lancia non entra come una mazza) e per
## COSA ha toccato: un bersaglio o il mondo. Il mondo non sanguina, e sentire
## carne quando hai preso una colonna e' il tipo di errore che toglie credibilita'
## a tutto il resto.
##
## ⚠️ Un colpo per FENDENTE, non per corpo colpito: `_hit_this_swing` gia'
## deduplica il danno, e senza questa stessa disciplina sul suono un fendente che
## prende tre nemici sparerebbe tre campioni sovrapposti — che a schermo si sente
## come distorsione, non come tre colpi.
var _suonato_questo_swing : bool = false

func _suona_colpo(sul_mondo : bool, _corpo) -> void:
	if _suonato_questo_swing:
		return
	_suonato_questo_swing = true
	var tipo := "TAGLIO"
	var info = current_equipment.equipment_info if current_equipment else null
	if info != null and "damage_type" in info:
		tipo = str(info.damage_type)
	var dove : Node3D = _corpo if _corpo is Node3D else player_node
	Suoni.nel_mondo(dove, Suoni.colpo(tipo, sul_mondo))
