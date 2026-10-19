extends Node
class_name NascondiInManoDuranteEvocazione

## Fa sparire quello che il protagonista ha in mano mentre evoca, e glielo
## rimette in mano quando il gesto e' finito.
##
## Serve perche' l'evocazione e' un gesto a MANI APERTE — entrambi i palmi si
## spalancano verso l'alto — e una spada impugnata da una mano con le dita
## aperte si vede che non e' impugnata da niente.
##
## Non tocca l'EquipmentSystem: l'arma resta equipaggiata, agganciata al suo
## mount e pronta. Cambia solo `visible`, come fa `hide_stored_weapon.gd` per
## l'arma riposta sulla schiena.

## Il player da cui ascoltare `summon_started` e `event_finished`.
@export var player_node : Node
## L'arma vera e propria (spada, ascia...). E' quella che l'utente ha chiesto
## di far sparire.
@export var weapon_system : EquipmentSystem
## Il Sigillo, cioe' il focus magico nella mano sinistra. Spento di default: e'
## l'oggetto che GIUSTIFICA il lancio, e toglierlo di mezzo e' una scelta
## artistica, non una necessita'. Accendendolo sparisce anche lui.
@export var nascondi_anche_il_sigillo : bool = false
@export var gadget_system : EquipmentSystem

## ⚠️ Rete di sicurezza. Se il gesto viene interrotto prima della fine (morte,
## cambio di scena, `busy` sbloccato da altri) `event_finished` non arriva e
## l'arma resterebbe invisibile PER SEMPRE, senza nessun errore a dirlo.
##
## ⚠️ Il tempo NON è una costante: si legge da `player_node.anim_length`, che
## il player ricava dalla clip appena partita. Un numero fisso invecchia — era
## 3,0 s su una clip di 2,00, poi la clip è passata a 4,00 e l'arma sarebbe
## ricomparsa a metà del gesto senza che niente lo segnalasse.
## Questo vale solo se `anim_length` non è leggibile.
const ATTESA_DI_RIPIEGO : float = 6.0
## Quanto si aspetta OLTRE la fine della clip prima di forzare il rientro.
const MARGINE : float = 1.0

var _nascosti : Array[Node3D] = []
## Cresce a ogni nascondi/mostra. Serve al timer di sicurezza per capire se sta
## ancora guardando la SUA evocazione o una successiva.
var _generazione : int = 0


func _ready() -> void:
	if player_node == null:
		push_warning("NascondiInManoDuranteEvocazione: manca player_node.")
		return
	## Come in hide_stored_weapon.gd: si aspetta che EquipmentSystem._ready
	## abbia sistemato i mount, o `held_mount_point` e' ancora vuoto.
	await get_tree().process_frame
	if player_node.has_signal("summon_started"):
		player_node.summon_started.connect(_su_evocazione)
	if player_node.has_signal("event_finished"):
		player_node.event_finished.connect(_rimetti_in_mano)


func _su_evocazione() -> void:
	_rimetti_in_mano()   ## se un gesto precedente non ha chiuso, si riparte pulito
	_nascondi(weapon_system)
	if nascondi_anche_il_sigillo:
		_nascondi(gadget_system)
	if _nascosti.is_empty():
		return
	var mia := _generazione
	## Un frame di attesa perché `anim_length` lo scrive il player quando la
	## clip parte, non quando il segnale viene emesso.
	await get_tree().process_frame
	await get_tree().create_timer(_attesa_di_sicurezza()).timeout
	if _generazione == mia:
		_rimetti_in_mano()


## Quanto tenere l'arma nascosta al MASSIMO, prima di rimetterla comunque.
func _attesa_di_sicurezza() -> float:
	if player_node != null and "anim_length" in player_node:
		var durata := float(player_node.anim_length)
		if durata > 0.0:
			return durata + MARGINE
	return ATTESA_DI_RIPIEGO


## ⚠️ `event_finished` scatta per QUALUNQUE gesto, non solo per l'evocazione.
## Va bene lo stesso: si nasconde solo sull'evocazione, e durante l'evocazione
## `busy` blocca gli altri gesti, quindi il primo `event_finished` che arriva e'
## il suo. Ed essere generosi nel RIMETTERE non fa danni — al massimo l'arma
## ricompare presto; essere generosi nel nascondere sì.
func _rimetti_in_mano() -> void:
	if _nascosti.is_empty():
		return
	for oggetto in _nascosti:
		if is_instance_valid(oggetto):
			oggetto.visible = true
	_nascosti.clear()
	_generazione += 1


func _nascondi(sistema : EquipmentSystem) -> void:
	var oggetto := _in_mano(sistema)
	## Solo quello che era VISIBILE: rimettendo `visible = true` a fine gesto si
	## farebbe altrimenti comparire un'arma che era nascosta per altri motivi.
	if oggetto != null and oggetto.visible:
		oggetto.visible = false
		_nascosti.append(oggetto)


func _in_mano(sistema : EquipmentSystem) -> Node3D:
	if sistema == null or sistema.held_mount_point == null:
		return null
	if sistema.held_mount_point.get_child_count() == 0:
		return null
	return sistema.held_mount_point.get_child(0) as Node3D
