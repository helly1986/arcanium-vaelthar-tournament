extends Node3D
class_name IsoLockOn

## Lock-on per la CAMERA ISOMETRICA di Arcanium.
##
## Sostituisce il lock-on del template (`PlayerTargetingSystem`), inservibile
## qui: era camera-relativo-terza-persona (tre "occhi" Area3D orientati sopra la
## spalla) e soprattutto RI-AGGANCIAVA muovendo lo STICK DESTRO, che in vista
## isometrica è la camera (rotazione + zoom). Riusarlo significherebbe ruotare la
## camera ogni volta che si cambia bersaglio.
##
## Qui la scelta del bersaglio è CAMERA-INDIPENDENTE: il più vicino AL PLAYER nel
## gruppo `target_group`, entro `max_range` e (opzionale) in linea di vista.
## I nemici escono dal gruppo quando muoiono (`enemy_base_root_motion.death()`,
## `arcanium_boss.gd`), quindi "bersaglio valido" si riduce a "è ancora nel
## gruppo ed è in range": nessun segnale di morte da cablare.
##
## Questo nodo NON legge input e NON tocca la camera: espone toggle()/release(),
## la validazione e il clamp del raggio d'orbita. È il player a chiamarli
## (vedi `player_charbody3D.gd`), così la politica di input resta in un posto solo.

## Gruppo dei bersagli agganciabili. Il boss ci si aggiunge in _ready e ne esce
## alla morte.
@export var target_group : String = "targets"

## Oltre questa distanza (piano XZ) non si aggancia, e un bersaglio già
## agganciato viene mollato. Generoso di proposito: in vista isometrica si vede
## molto campo, e un raggio corto costringe ad avvicinarsi per agganciare.
@export var max_range : float = 35.0

## ⚠️ RAGGIO MINIMO D'ORBITA: orbitando NON ci si può avvicinare al bersaglio
## più di così. È il valore chiesto dal design (Arcanium-Lite): tarabile a vista.
@export_range(0.0, 5.0, 0.05) var min_orbit_radius : float = 0.9

## Se true, un bersaglio dietro un muro non è agganciabile.
@export var require_line_of_sight : bool = true

@export_flags_3d_physics var line_of_sight_mask : int = 1

var current_target : Node3D = null

signal target_acquired(target : Node3D)
signal target_released()

func is_locked() -> bool:
	return is_instance_valid(current_target)

## Ritorna il nuovo stato di lock (true = agganciato). Se non c'è nessun
## bersaglio valido resta sganciato e ritorna false.
func toggle() -> bool:
	if is_locked():
		release()
		return false
	return acquire()

func acquire() -> bool:
	var best := _best_target([])
	if best == null:
		return false
	current_target = best
	target_acquired.emit(best)
	return true

## Passa al bersaglio valido successivo (escluso quello attuale). Non ancora
## legato a un input: serve quando in campo ci saranno più nemici/summon.
func cycle() -> bool:
	if not is_locked():
		return acquire()
	var next := _best_target([current_target])
	if next == null:
		return true  ## nessun altro bersaglio: resta agganciato a questo
	current_target = next
	target_acquired.emit(next)
	return true

func release() -> void:
	if current_target == null:
		return
	current_target = null
	target_released.emit()

## Da chiamare ogni physics frame: sgancia se il bersaglio è morto (uscito dal
## gruppo), è stato liberato o si è allontanato oltre max_range.
func validate() -> void:
	if current_target == null:
		return
	if not _is_valid(current_target):
		release()

## Applica il raggio minimo d'orbita alla posizione data, ritornandola corretta.
## Agisce SOLO sul piano XZ: la quota del player resta la sua (dislivelli e
## gravità non vengono toccati).
func clamp_orbit_position(pos : Vector3) -> Vector3:
	if not is_locked() or min_orbit_radius <= 0.0:
		return pos
	var flat := pos - current_target.global_position
	flat.y = 0.0
	var dist := flat.length()
	if dist >= min_orbit_radius or dist <= 0.0001:
		return pos
	var pushed := current_target.global_position + flat.normalized() * min_orbit_radius
	pushed.y = pos.y
	return pushed

## ═══════════════════════════════════════════════════════════════════════════
## PUNTO DI MIRA — il centro della MESH, non una quota fissa
## ═══════════════════════════════════════════════════════════════════════════
##
## Prima erano due posti a indovinare la stessa altezza, e sbagliavano insieme:
## il mirino la piazzava a 2.2 m fissi sopra i piedi del bersaglio (tarati sugli
## umanoidi, alti ~3 m), e i proiettili partivano ORIZZONTALI dall'altezza del
## petto del player. Su un lupo — che è basso e lungo — il mirino galleggiava in
## aria e l'Ice Shard passava sopra la schiena senza toccarlo.
##
## Il punto si ricava dallo SCHELETRO: il centro del riquadro che contiene tutte
## le ossa nella posa corrente. È l'unica misura onesta su un personaggio
## animato, e segue il bersaglio mentre si muove.
##
## ⚠️ NON usare l'AABB della MeshInstance3D. Su una mesh skinnata `get_aabb()`
## torna il box dei dati A RIPOSO, nello spazio in cui sono stati salvati, e
## moltiplicarlo per `global_transform` dà un risultato che SEMBRA sensato (un
## box, non vuoto, delle dimensioni giuste) ma descrive un'altra cosa: sul lupo
## veniva fuori un ingombro alto 1.56 m — la LUNGHEZZA dell'animale messa in
## verticale — col centro esattamente sull'origine del modello. La posa vera la
## conosce solo lo scheletro.
##
## Se il bersaglio non ha scheletro si ripiega sull'AABB visiva (giusta per i
## prop rigidi), e infine su questa quota.
@export var fallback_aim_height : float = 1.2

## Un `Marker3D` figlio con questo nome, se c'è, vince su tutto: serve a tarare
## a mano un bersaglio dalla forma strana senza toccare il codice.
@export var aim_marker_name : String = "AimPoint"

var _aim_cache_target : Node3D = null
var _aim_marker : Node3D = null
var _aim_skeleton : Skeleton3D = null
var _aim_visuals : Array[GeometryInstance3D] = []


func aim_point(t : Node3D = null) -> Vector3:
	var bersaglio : Node3D = t if t != null else current_target
	if not is_instance_valid(bersaglio):
		return Vector3.ZERO
	_aggiorna_cache(bersaglio)
	if is_instance_valid(_aim_marker):
		return _aim_marker.global_position
	if is_instance_valid(_aim_skeleton) and _aim_skeleton.get_bone_count() > 0:
		return _centro_ossa(_aim_skeleton)
	var visiva := _riquadro_visivo()
	if not visiva.size.is_zero_approx():
		return visiva.get_center()
	return bersaglio.global_position + Vector3.UP * fallback_aim_height


## L'albero si esplora una volta per bersaglio: il mirino chiama `aim_point`
## ogni frame. Le POSIZIONI invece si rileggono sempre, perché il nemico si
## muove e si anima.
func _aggiorna_cache(bersaglio : Node3D) -> void:
	if bersaglio == _aim_cache_target:
		return
	_aim_cache_target = bersaglio
	_aim_marker = bersaglio.get_node_or_null(aim_marker_name) as Node3D
	if _aim_marker == null:
		_aim_marker = bersaglio.find_child(aim_marker_name, true, false) as Node3D
	_aim_skeleton = null
	for n in bersaglio.find_children("*", "Skeleton3D", true, false):
		_aim_skeleton = n as Skeleton3D
		break
	_aim_visuals.clear()
	for n in bersaglio.find_children("*", "GeometryInstance3D", true, false):
		_aim_visuals.append(n as GeometryInstance3D)


## Centro, in spazio MONDO, del riquadro che contiene tutte le ossa nella posa
## corrente. Si calcola il centro NELLO SPAZIO DELLO SCHELETRO e lo si trasforma
## alla fine: trasformare prima i due estremi e rifare il riquadro darebbe il
## centro giusto solo con lo scheletro allineato al mondo.
func _centro_ossa(sk : Skeleton3D) -> Vector3:
	var basso := Vector3.INF
	var alto := -Vector3.INF
	for i in sk.get_bone_count():
		var p : Vector3 = sk.get_bone_global_pose(i).origin
		basso = basso.min(p)
		alto = alto.max(p)
	return sk.global_transform * ((basso + alto) * 0.5)


func _riquadro_visivo() -> AABB:
	var fusa := AABB()
	var primo := true
	for vi in _aim_visuals:
		if not is_instance_valid(vi) or not vi.is_visible_in_tree():
			continue
		## salta le mesh skinnate: il loro `get_aabb()` non descrive la posa
		if vi is MeshInstance3D and not (vi as MeshInstance3D).skeleton.is_empty() \
				and (vi as MeshInstance3D).skeleton != NodePath("."):
			continue
		var box := vi.global_transform * vi.get_aabb()
		if primo:
			fusa = box
			primo = false
		else:
			fusa = fusa.merge(box)
	return fusa


func _is_valid(t : Node3D) -> bool:
	if not is_instance_valid(t) or not t.is_inside_tree():
		return false
	if not t.is_in_group(target_group):
		return false
	## Un nemico nascosto dalla nebbia del dungeon non si aggancia, e se ci
	## rientra mentre e' agganciato si sgancia.
	if not t.is_visible_in_tree():
		return false
	return _planar_distance(t) <= max_range

func _planar_distance(t : Node3D) -> float:
	var d := t.global_position - global_position
	d.y = 0.0
	return d.length()

func _best_target(exclude : Array) -> Node3D:
	var best : Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(target_group):
		if not (node is Node3D) or exclude.has(node):
			continue
		var t := node as Node3D
		if not _is_valid(t):
			continue
		var dist := _planar_distance(t)
		if dist >= best_dist:
			continue
		if require_line_of_sight and not _has_line_of_sight(t):
			continue
		best = t
		best_dist = dist
	return best

func _has_line_of_sight(t : Node3D) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	## Si guarda all'altezza del petto, non dei piedi: da terra qualunque
	## gradino taglierebbe la visuale.
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP, t.global_position + Vector3.UP, line_of_sight_mask)
	var body := get_parent()
	if body is CollisionObject3D:
		query.exclude = [body.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider = hit.get("collider")
	if collider == t:
		return true
	## L'hitbox colpita può essere un figlio del nemico (capsula, armatura...).
	return collider is Node and t.is_ancestor_of(collider)
