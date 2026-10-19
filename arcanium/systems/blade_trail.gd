extends Node

## ⚠️ Niente `class_name`: chi lo usa fa `preload`. Vedi la nota in `fazioni.gd`
## — un `const` omonimo di una classe globale la ombreggia, e la registrazione
## dei class_name su questo progetto non è affidabile.

## ═══════════════════════════════════════════════════════════════════════════
## TRACCIA DELLA LAMA — il muro nasce dove la spada è passata davvero
## ═══════════════════════════════════════════════════════════════════════════
##
## Il gemello lato GIOCATORE della sonda che il boss ha in `arcanium_boss.gd`.
## Serve alla Lucida Tecnica: il Rovescio Risonante non pianta una parete
## davanti a chi la lancia, DISEGNA una barriera lungo il giro di lama. Se il
## muro non seguisse l'arma, la mossa smetterebbe di essere quel gesto e
## tornerebbe a essere un rettangolo di fuoco piazzato a occhio — cioè la cosa
## che il boss aveva già smesso di fare.
##
## ─── Perché non basta il sistema d'attacco che c'è già ──────────────────────
## `equipment_system.gd` apre la finestra dell'arma con due timer
## (`anim_length * 0.3`, poi `* 0.5`) e si affida a `body_entered` più un cono di
## prossimità. Va bene per decidere SE hai colpito, non per sapere DOVE è passata
## la lama: `body_entered` dà un contatto, non un percorso, e i timer non sanno
## nulla di dove sta la spada in quell'istante. Il boss invece campiona la posa
## dell'arma a ogni tick di fisica, ed è quella la cosa che qui serve replicare.
##
## ─── La punta si CALCOLA, non si scrive ─────────────────────────────────────
## Il boss ha `Vector3(0, 0.495, 0)` scritto a mano nel codice: è metà del suo
## box lama (0.99), quindi è giusto — ma solo per lui. Lato giocatore la stessa
## spada arriva con la hitbox dichiarata nella risorsa d'arma
## (`ArcaniumEquipmentResource.hitbox_size`) e RIDIMENSIONATA a runtime da
## `held_weapon.gd` a ogni cambio d'equipaggiamento: un numero fisso sarebbe
## sbagliato appena cambi arma. Qui la mezza-altezza si legge dalla shape viva,
## ogni tick. `tip_of()` è statica apposta: è la definizione di "dov'è la punta",
## e deve esistere in un posto solo.
##
## Nota di scala: la shape del boss vive sotto un modello scalato 1.877, quella
## del giocatore no. `global_transform` porta dentro la scala, quindi la punta
## atterra giusta in entrambi i casi senza correzioni — e il muro del giocatore
## esce proporzionalmente più corto, che è quello che deve succedere.

## Distanza minima fra due campioni perché nasca un tratto di muro. Sotto questa
## soglia i punti si accumulano senza generare geometria: una spada quasi ferma
## produrrebbe decine di segmenti sovrapposti nello stesso posto.
## 0.25 è il valore del boss, tenuto identico per parità visiva della mossa.
@export var min_segment : float = 0.25

## L'`Area3D` della lama. Il nodo è STABILE anche cambiando arma: `held_weapon.gd`
## sostituisce il modello e la BoxShape3D dentro di esso, non l'Area.
@export var blade : Area3D

## Dove appendere il muro. Vuoto = il genitore del portatore, cioè il livello:
## il muro deve restare dove la lama è passata, non seguire chi l'ha tirato.
@export var wall_parent : NodePath

signal segment_added(da : Vector3, a : Vector3)

var _wall : Node3D = null
var _last_tip : Vector3 = Vector3.ZERO
var _has_last : bool = false


## Punta dell'arma in coordinate MONDO. Una sola definizione, condivisa fra il
## lato giocatore e il boss.
static func tip_of(forma : CollisionShape3D) -> Vector3:
	if forma == null or forma.shape == null:
		return Vector3.ZERO
	var mezza : float = 0.0
	if forma.shape is BoxShape3D:
		mezza = (forma.shape as BoxShape3D).size.y * 0.5
	elif forma.shape is CapsuleShape3D:
		var c := forma.shape as CapsuleShape3D
		mezza = c.height * 0.5
	elif forma.shape is CylinderShape3D:
		mezza = (forma.shape as CylinderShape3D).height * 0.5
	return forma.global_transform * Vector3(0, mezza, 0)


## La CollisionShape3D della lama, ripescata ogni volta: `held_weapon.gd` ne
## sostituisce la `shape` al cambio d'arma, e tenerne una copia significherebbe
## misurare la spada precedente.
func _forma() -> CollisionShape3D:
	if blade == null:
		return null
	for c in blade.get_children():
		if c is CollisionShape3D:
			return c
	return null


## Apre la finestra: istanzia il muro VUOTO e comincia a campionare. Il muro
## nasce subito e cresce mentre la lama gira — non a fendente finito, o il fuoco
## comparirebbe in ritardo su uno swing che dura meno di un secondo.
##
## `info` è la risorsa che porta tipo di danno e status (per il giocatore è la
## `ArcaniumEquipmentResource` dell'arma, per il boss la sua `EnemyMove`):
## `BossWall` la duplica prima di scriverci la potenza del tick.
## `source` dev'essere il CORPO del lanciatore (il CharacterBody3D), non un suo
## componente: il muro lo usa per l'esclusione per identità, e `wall_parent`
## vuoto ne prende il genitore per appendere il muro al livello.
func begin(wall_scene : PackedScene, info : Resource, source : Node,
		durata : float = 6.0, tick_damage : int = 4, tick_interval : float = 0.55,
		maschera : int = 5, fuoco_amico : bool = false) -> Node3D:
	end()
	if wall_scene == null:
		return null
	_wall = wall_scene.instantiate()
	_wall.move = info
	_wall.source = source
	_wall.duration = durata
	_wall.tick_damage = tick_damage
	_wall.tick_interval = tick_interval
	_wall.collision_mask = maschera
	# Chi brucia NON si passa: lo deduce `Fazioni` dal `source`. Qui si dichiara
	# solo l'eventuale deroga, che è una scelta di design della singola mossa.
	_wall.friendly_fire = fuoco_amico
	var genitore : Node = get_node_or_null(wall_parent)
	if genitore == null:
		# Il livello, non il portatore: un muro figlio del giocatore lo
		# seguirebbe in giro per l'arena.
		genitore = source.get_parent() if source != null else get_tree().current_scene
	genitore.add_child(_wall)
	_has_last = false
	return _wall


## Chiude la finestra. Il muro NON viene distrutto: resta in scena a vivere la
## sua durata e la sua dissolvenza.
func end() -> void:
	_wall = null
	_has_last = false


func _physics_process(_delta : float) -> void:
	if _wall == null or not is_instance_valid(_wall):
		return
	var forma := _forma()
	if forma == null:
		return
	var punta := tip_of(forma)
	if not _has_last:
		_last_tip = punta
		_has_last = true
		return
	if _last_tip.distance_to(punta) <= min_segment:
		return
	_wall.add_segment(_last_tip, punta)
	segment_added.emit(_last_tip, punta)
	_last_tip = punta
