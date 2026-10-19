extends Control
class_name LockOnReticle

## Segnalino del bersaglio agganciato. Riprende l'idea del reticolo del template
## (`player/player_targeting_system/gui_reticle.gd`): proietta la posizione 3D
## del bersaglio sullo schermo e ci disegna sopra un mirino.
##
## Differenze: si aggancia a IsoLockOn (non al vecchio PlayerTargetingSystem,
## camera-relativo e ormai morto) e disegna il mirino via `_draw` invece di usare
## una texture, così non serve nessun asset e resta nitido a ogni risoluzione.
##
## Senza questo segnalino il lock-on FUNZIONAVA ma sembrava rotto: non essendoci
## nulla a schermo, l'unico modo di accorgersi dell'aggancio era sentire il
## personaggio orbitare, cosa che si nota solo da vicino.

## Il nodo IsoLockOn da osservare. Se vuoto, lo cerca nel player.
@export var lock_on : Node

## Ripiego se IsoLockOn non sa dare un punto di mira (bersaglio senza mesh).
## ⚠️ Non è più la regola: una quota FISSA era tarata sugli umanoidi (~3 m) e su
## un lupo metteva il mirino a mezz'aria sopra la schiena. Il punto giusto lo
## calcola IsoLockOn dal centro della mesh, così mirino e proiettili puntano
## allo stesso posto — vedi `iso_lock_on.aim_point()`.
@export var marker_height : float = 2.2

@export var color : Color = Color("#9fe6ff")
@export var radius : float = 17.0
@export var thickness : float = 2.0

var _target : Node3D = null

func _ready() -> void:
	## Non deve mai intercettare i click: è pura decorazione.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	hide()
	if lock_on == null:
		lock_on = _find_lock_on()
	if lock_on:
		if lock_on.has_signal("target_acquired"):
			lock_on.target_acquired.connect(_on_acquired)
		if lock_on.has_signal("target_released"):
			lock_on.target_released.connect(_on_released)

func _find_lock_on() -> Node:
	var p := get_parent()
	while p != null:
		var n := p.get_node_or_null("IsoLockOn")
		if n != null:
			return n
		p = p.get_parent()
	return null

func _on_acquired(t : Node3D) -> void:
	_target = t
	show()

func _on_released() -> void:
	_target = null
	hide()

func _process(_delta : float) -> void:
	if not is_instance_valid(_target):
		if visible:
			hide()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var world : Vector3 = _target.global_position + Vector3.UP * marker_height
	if lock_on and lock_on.has_method("aim_point"):
		var p : Vector3 = lock_on.aim_point(_target)
		if p != Vector3.ZERO:
			world = p
	## Dietro la camera unproject_position darebbe una posizione sballata.
	if cam.is_position_behind(world):
		hide()
		return
	if not visible:
		show()
	global_position = cam.unproject_position(world)
	queue_redraw()

## Mirino: cerchio sottile + quattro trattini agli assi. Disegnato attorno
## all'origine del Control, che è già posizionato sul bersaglio.
func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, thickness, true)
	var inner := radius * 0.55
	var outer := radius * 1.35
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector2(cos(a), sin(a))
		draw_line(dir * inner, dir * outer, color, thickness, true)
