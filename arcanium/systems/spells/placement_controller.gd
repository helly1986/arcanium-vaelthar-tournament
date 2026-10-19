extends Node3D
class_name PlacementController

## Sistema di PIAZZAMENTO POSIZIONALE, GENERICO — pensato per essere riusato
## non solo dagli spell AoE ma anche dai futuri SUMMON: chi lo possiede
## (player_charbody3D.gd) non gli passa nulla di spell-specifico, solo
## raggio/range/colore del decal. Mostra un decal a terra che l'utente muove
## con lo stick sinistro (Input "move_left/right/up/down", stesso asse del
## movimento normale — il player è congelato durante il piazzamento, quindi
## non c'è conflitto) o col mouse (raycast sul piano orizzontale all'altezza
## dell'anchor), clampato entro `max_range` dall'anchor. Alla conferma emette
## `confirmed(position)` col centro scelto; il chiamante decide COSA fare in
## quel punto (spell AoE, summon...) — questo script non lo sa e non deve
## saperlo. All'annullamento emette `cancelled()`, nessun costo è mai speso
## qui (la spesa è responsabilità del chiamante, es. SpellCaster.cast_positional,
## chiamato SOLO dopo `confirmed`).

## Nodo da cui parte il decal e rispetto a cui è clampato il raggio massimo
## (tipicamente il player).
@export var anchor : Node3D
## Velocità (m/s) di spostamento del decal quando pilotato dallo stick.
@export var move_speed : float = 6.0
@export var stick_deadzone : float = 0.2
## Morbidezza del decal col MOUSE: più basso = più fluido/lento a seguire, più
## alto = più reattivo. Senza questo il decal saltava secco sulla posizione grezza
## del mouse (scattoso). ~12 = fluido ma preciso.
@export var mouse_smooth : float = 12.0
## Distanza di default davanti all'anchor a cui appare il decal all'avvio.
@export var default_forward_distance : float = 3.0

## Parametri dell'istanza di piazzamento corrente (settati da start()).
var decal_radius : float = 3.0
var max_range : float = 8.0
var decal_color : Color = Color("#9fe6ff")

var _decal : Node3D = null
var active : bool = false

## position: Vector3, il centro scelto dal player al momento della conferma.
signal confirmed(position : Vector3)
signal cancelled()

## Avvia il piazzamento: crea il decal davanti all'anchor e comincia a
## reagire a movimento/conferma/annullamento. Se un piazzamento era già
## attivo, lo annulla prima di iniziarne uno nuovo (nessun costo speso su
## quello vecchio, coerente col contratto di cancel()).
func start(radius : float, range_max : float, color : Color) -> void:
	if active:
		cancel()
	decal_radius = radius
	max_range = range_max
	decal_color = color
	_spawn_decal()
	active = true

## Nodo Node3D del decal correntemente attivo, o null se nessun piazzamento è
## in corso. Pensato per essere passato a IsoCam.focus_target() dal chiamante
## (questo script NON conosce la camera — resta agnostico, riusabile).
func get_decal() -> Node3D:
	return _decal

func decal_position() -> Vector3:
	return _decal.global_position if _decal else Vector3.ZERO

func _spawn_decal() -> void:
	_decal = Node3D.new()
	_decal.name = "PlacementDecal"
	var root := get_tree().current_scene
	root.add_child(_decal)

	var start_pos : Vector3 = anchor.global_position if anchor else global_position
	if anchor:
		start_pos += -anchor.global_transform.basis.z * default_forward_distance
	_decal.global_position = start_pos

	_build_decal_visual(_decal)

func _build_decal_visual(host : Node3D) -> void:
	var mesh_inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = decal_radius
	mesh.bottom_radius = decal_radius
	mesh.height = 0.04
	mesh.radial_segments = 32
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(decal_color.r, decal_color.g, decal_color.b, 0.35)
	mat.emission_enabled = true
	mat.emission = decal_color
	mat.emission_energy_multiplier = 1.0
	mesh_inst.material_override = mat
	host.add_child(mesh_inst)

func _physics_process(delta : float) -> void:
	if not active or _decal == null:
		return
	_process_move(delta)

func _process_move(delta : float) -> void:
	var cam := get_viewport().get_camera_3d()
	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if stick.length() > stick_deadzone and cam:
		var dir : Vector3 = cam.global_transform.basis.z * stick.y + cam.global_transform.basis.x * stick.x
		dir.y = 0.0
		if dir.length() > 0.0001:
			_decal.global_position += dir.normalized() * move_speed * delta
	elif cam:
		var ground = _mouse_ground_position(cam)
		if ground != null:
			# Lerp verso la posizione del mouse invece di saltarci secco: elimina
			# lo scatto/tremolio del cursore.
			var t : float = clampf(mouse_smooth * delta, 0.0, 1.0)
			_decal.global_position = _decal.global_position.lerp(ground, t)

	_clamp_to_range()

## Interseca il raggio mouse->mondo con il piano orizzontale all'altezza
## dell'anchor (scelta più semplice: niente PhysicsRayQuery/collision layer,
## sufficiente per un decal che deve solo stare "a terra" davanti al player).
func _mouse_ground_position(cam : Camera3D):
	var vp := get_viewport()
	var mouse_pos := vp.get_mouse_position()
	var origin := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var ground_y : float = anchor.global_position.y if anchor else 0.0
	var plane := Plane(Vector3.UP, ground_y)
	return plane.intersects_ray(origin, dir)

func _clamp_to_range() -> void:
	if anchor == null or _decal == null:
		return
	var anchor_pos := anchor.global_position
	var offset : Vector3 = _decal.global_position - anchor_pos
	offset.y = 0.0
	if offset.length() > max_range:
		offset = offset.normalized() * max_range
	_decal.global_position = anchor_pos + offset
	_decal.global_position.y = anchor_pos.y

func _unhandled_input(event : InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("cast_confirm"):
		confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cast_cancel"):
		cancel()
		get_viewport().set_input_as_handled()

## Conferma il piazzamento al centro corrente del decal. Distrugge il decal ed
## emette `confirmed(position)`. Non spende nulla: la spesa è del chiamante.
func confirm() -> void:
	if not active:
		return
	var pos := decal_position()
	_end()
	confirmed.emit(pos)

## Annulla il piazzamento: nessun costo speso, nessun effetto. Distrugge il
## decal ed emette `cancelled()`.
func cancel() -> void:
	if not active:
		return
	_end()
	cancelled.emit()

func _end() -> void:
	active = false
	if _decal:
		_decal.queue_free()
		_decal = null
