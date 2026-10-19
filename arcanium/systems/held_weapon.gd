extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ARMA IN MANO
## ═══════════════════════════════════════════════════════════════════════════
##
## Fa combaciare ciò che il menu dice di impugnare con ciò che il protagonista
## impugna davvero. Prima non combaciava: si poteva equipaggiare la Spada del
## Senza Nome, la scheda cambiava, le statistiche pure — e in mano restava la
## lama del kit iniziale, con il suo danno e il suo tipo. L'equipaggiamento era
## una cosa che si leggeva.
##
## Qui l'arma equipaggiata detta tre cose, tutte sull'oggetto d'arma del
## template (l'EquipmentObject sotto il mount della mano), che resta il solo a
## conoscere il combattimento:
##   • la RISORSA che passa al bersaglio quando colpisce (danno, tipo, poise);
##   • il MODELLO visibile, che sostituisce quello montato nella scena;
##   • la HITBOX, perché la portata di una lancia non è quella di una spada.
##
## Non tocca l'EquipmentSystem: quello continua ad accendere e spegnere il suo
## `current_equipment` come ha sempre fatto, ignaro che il contenuto sia
## cambiato sotto.

## Il WeaponSystem del player. Da qui si arriva all'arma tenuta in mano.
@export var weapon_system : Node3D
## Lo slot di EquipmentLoadout che decide cosa si impugna.
@export var slot : String = "arma_primaria"

## ─── L'ARCO E LO SCUDO ──────────────────────────────────────────────────────
## L'arco si impugna con la DESTRA come ogni arma (e' la scelta del Soldato
## Scelto, 2026-09-13: la sinistra tira la corda). Quindi il suo modello va
## dove va ogni modello — sotto l'oggetto d'arma della destra — ma la SINISTRA
## dev'essere libera: lo scudo (o il sigillo) sparisce finche' c'e' un arco in
## mano, e con un arco non si para (vedi `start_guard` nel player).
@export var gadget_system : Node3D
const TIPI_SENZA_SCUDO : PackedStringArray = ["BOW"]

## Nome del nodo che appendiamo per il modello sostitutivo. Serve a riconoscerlo
## e rimuoverlo al cambio successivo senza toccare i figli originali della
## scena, che vanno soltanto nascosti: se li cancellassimo, tornare all'arma
## iniziale richiederebbe di ricostruirli.
const NODO_MODELLO := "ModelloEquipaggiato"

var _loadout : Node
var _dimensione_hitbox_originale : Vector3 = Vector3.ZERO
var _offset_hitbox_originale : Vector3 = Vector3.ZERO
var _hitbox_letta := false


func _ready() -> void:
	_loadout = get_node_or_null("/root/EquipmentLoadout")
	if _loadout != null and _loadout.has_signal("changed"):
		_loadout.changed.connect(_applica)
	# Lo scambio mano↔schiena del template cambia QUALE oggetto è in mano: senza
	# riapplicare, l'arma equipaggiata resterebbe su quella riposta e in mano
	# tornerebbe il modello del kit.
	if weapon_system != null and weapon_system.has_signal("equipment_changed"):
		weapon_system.equipment_changed.connect(func(_e = null): _applica())
	# L'EquipmentSystem popola `current_equipment` nel PROPRIO _ready, e l'ordine
	# fra fratelli non è garantito: aspettiamo un frame invece di scommetterci.
	await get_tree().process_frame
	_applica()


func _applica() -> void:
	var arma := _arma_in_mano()
	if arma == null or _loadout == null:
		return
	var res = _loadout.equipped_in(slot)
	if res == null:
		return

	# 1. La risorsa: da qui in poi il colpo porta i numeri dell'arma equipaggiata.
	arma.equipment_info = res
	_annuncia_tipo(res)
	_ricalcola_potenza()

	# 2. Il modello.
	var vecchio := arma.get_node_or_null(NODO_MODELLO)
	if vecchio != null:
		vecchio.free()   # subito, non queue_free: sotto contiamo i figli
	var modello_proprio : PackedScene = res.held_model if "held_model" in res else null
	for figlio in arma.get_children():
		if figlio is VisualInstance3D:
			(figlio as VisualInstance3D).visible = modello_proprio == null
	if modello_proprio != null:
		var n : Node3D = modello_proprio.instantiate()
		n.name = NODO_MODELLO
		arma.add_child(n)
		n.transform = res.held_transform
	_mostra_gadget(not _libera_la_sinistra(res))

	# 3. La hitbox. Il primo giro registra quella della scena come "default", così
	# tornare a un'arma che non la dichiara la ripristina invece di lasciare
	# addosso la portata dell'arma precedente.
	var forma := _collision_shape(arma)
	if forma != null and forma.shape is BoxShape3D:
		var box := forma.shape as BoxShape3D
		if not _hitbox_letta:
			_dimensione_hitbox_originale = box.size
			_offset_hitbox_originale = forma.position
			_hitbox_letta = true
		var voluta : Vector3 = res.hitbox_size if "hitbox_size" in res else Vector3.ZERO
		if voluta.length() > 0.001:
			# duplicate(): la BoxShape3D può essere condivisa fra istanze, e
			# scriverci sopra allungherebbe anche la lama di chi non c'entra.
			var mia := box.duplicate() as BoxShape3D
			mia.size = voluta
			forma.shape = mia
			forma.position = res.hitbox_offset
		else:
			var mia2 := box.duplicate() as BoxShape3D
			mia2.size = _dimensione_hitbox_originale
			forma.shape = mia2
			forma.position = _offset_hitbox_originale


## Rifà lo scaling per Marche sull'arma appena messa in mano.
##
## `power` NON è un dato del .tres: è `base_power` scalato sulle Marche, e lo
## scrive MarcheWielder chiamando `compute_power()`. Lo fa al ready e allo
## scambio mano↔schiena del template — non quando siamo NOI a cambiare la
## risorsa sotto l'oggetto d'arma.
##
## Senza questa riga l'arma equipaggiata dal menu restava al `power` di default
## di EquipmentResource, che è **1**: la Spada del Senza Nome faceva 1 danno
## invece di 21, cioè 35 colpi per un lupo e 260 per l'alpha. A schermo si legge
## come "l'arma non fa danno", e la colpa sembra della hitbox — che invece era
## giusta. La Lama della Prima Veglia funzionava solo perché è l'arma iniziale,
## quindi il suo `power` lo calcolava il giro di startup.
func _ricalcola_potenza() -> void:
	var player = weapon_system.player_node if "player_node" in weapon_system else null
	if player == null:
		return
	for n in player.get_children():
		# Duck-typing invece del class_name: la registrazione delle classi
		# dipende dallo scan dell'editor e su questo progetto non sempre regge.
		if n.has_method("refresh") and "stats" in n:
			n.refresh()
			return


## Dice al resto del player CHE TIPO d'arma è ora in mano, che è ciò da cui
## dipende il move set: l'AnimationTree del template tiene un sotto-albero per
## tipo (`SLASH_tree`, `HEAVY_tree`, e domani quello degli affondi) e sceglie in
## base a `weapon_type`.
##
## Serviva perché `weapon_change_ended` lo emette solo lo scambio mano↔schiena
## del template: equipaggiando dal menu cambiava l'arma e non il modo di menare,
## e una lancia avrebbe fatto fendenti.
func _annuncia_tipo(res) -> void:
	var player = weapon_system.player_node if "player_node" in weapon_system else null
	if player == null or not ("weapon_type" in player):
		return
	var tipo : String = res.object_type if "object_type" in res else "SLASH"
	if player.weapon_type == tipo:
		return
	player.weapon_type = tipo
	if player.has_signal("weapon_change_ended"):
		player.weapon_change_ended.emit(tipo)


## Vero per i pezzi che vogliono la sinistra libera (l'arco).
func _libera_la_sinistra(res) -> bool:
	return res != null and "object_type" in res and str(res.object_type) in TIPI_SENZA_SCUDO


## Lo scudo (o il sigillo) in mano sinistra si vede solo se la sinistra e'
## libera. Si nasconde il NODO, non i suoi figli: lo scudo ha un'anima sua
## (VarianteScudo, mesh, collider) e non si vuole inseguirla.
func _mostra_gadget(visibile : bool) -> void:
	if gadget_system == null or not ("current_equipment" in gadget_system):
		return
	var g = gadget_system.current_equipment
	if g is Node3D:
		(g as Node3D).visible = visibile


## L'oggetto d'arma sotto il mount della mano. Si passa dall'EquipmentSystem
## quando l'ha già trovato, altrimenti si legge il mount: durante il primo frame
## `current_equipment` può essere ancora nullo.
func _arma_in_mano() -> Node3D:
	if weapon_system == null:
		return null
	if "current_equipment" in weapon_system and weapon_system.current_equipment != null:
		return weapon_system.current_equipment
	var mount = weapon_system.held_mount_point if "held_mount_point" in weapon_system else null
	if mount != null and mount.get_child_count() > 0:
		return mount.get_child(0)
	return null


func _collision_shape(n : Node) -> CollisionShape3D:
	for c in n.get_children():
		if c is CollisionShape3D:
			return c
	return null
