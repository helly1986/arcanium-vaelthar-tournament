extends RigidBody3D

## L'AMPOLLA DI LIQUIDO INFIAMMABILE lanciata (2026-11-13): il primo oggetto da lancio.
##
## Parla il dialetto di `ItemSystem` del template (`object_type`, `player_node`,
## `activate`), perche' e' lui a istanziarla: appesa al fianco come oggetto in mano
## (`_on_inventory_updated`, resta ferma e senza collisioni) e lanciata all'uso.
##
## Il lancio non e' l'impulso dritto del template: parte dalla MANO DESTRA (la clip del
## lancio, ThrowLTopOnly, e' destra) e fa una parabola che cade sul bersaglio agganciato,
## o qualche metro avanti. Al primo urto si rompe e lascia la pozza di fuoco
## (pozza_di_fuoco.gd), che e' quella che fa danno.

const PozzaDiFuoco := preload("res://arcanium/systems/oggetti/pozza_di_fuoco.gd")

## Velocita' orizzontale del lancio: la parabola si adatta alla distanza.
const VELOCITA := 13.0
## Senza bersaglio cade cosi' avanti.
const GITTATA_LIBERA := 8.0
const GITTATA_MASSIMA := 16.0
## Il mondo (strato 1) e i bersagli (strato 3): non il giocatore (2).
const MASCHERA := 1 | 4

var object_type : String = "THROWN"
var player_node : Node = null

var _lanciata := false
var _rotta := false


func _ready() -> void:
	freeze = true
	collision_layer = 0
	collision_mask = 0
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_urto)


## Il contratto del template: lo chiama ItemSystem. Qui non fa niente da solo, il lancio
## vero e' `lancia`.
func activate() -> void:
	pass


## Dalla posizione `da` (la mano) verso il bersaglio di `chi`.
func lancia(chi : Node3D, da : Vector3) -> void:
	player_node = chi
	top_level = true
	global_position = da
	var avanti : Vector3 = chi.global_transform.basis.z
	avanti.y = 0.0
	avanti = avanti.normalized() if avanti.length_squared() > 0.001 else Vector3.BACK
	var arrivo : Vector3 = chi.global_position + avanti * GITTATA_LIBERA
	if chi.has_method("spell_aim_point"):
		var p = chi.spell_aim_point()
		if p != null:
			arrivo = p
	var piano := Vector3(arrivo.x - da.x, 0.0, arrivo.z - da.z)
	if piano.length() > GITTATA_MASSIMA:
		piano = piano.normalized() * GITTATA_MASSIMA
	var t := clampf(piano.length() / VELOCITA, 0.25, 1.3)
	var g : float = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_scale
	var dy : float = arrivo.y - da.y
	linear_velocity = piano / t + Vector3.UP * (dy + 0.5 * g * t * t) / t
	angular_velocity = Vector3(randf_range(-9, 9), randf_range(-3, 3), randf_range(-9, 9))
	collision_layer = 0
	collision_mask = MASCHERA
	add_collision_exception_with(chi)
	freeze = false
	_lanciata = true
	## Se non tocca niente (un baratro), si rompe lo stesso dopo un po'.
	get_tree().create_timer(3.0).timeout.connect(func(): _rompi(global_position))


func _on_urto(_corpo : Node) -> void:
	if _lanciata:
		_rompi(global_position)


func _rompi(dove : Vector3) -> void:
	if _rotta or not is_inside_tree():
		return
	_rotta = true
	var pozza := PozzaDiFuoco.new()
	pozza.lanciatore = player_node
	## La posizione PRIMA di entrare in scena: la pozza si appoggia a terra e scoppia nel
	## suo `_ready`.
	var mondo := get_parent()
	pozza.position = (mondo as Node3D).to_local(dove) if mondo is Node3D else dove
	mondo.add_child(pozza)
	queue_free()
