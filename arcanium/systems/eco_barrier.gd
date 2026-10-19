extends StaticBody3D

## Barriera d'Eco che sigilla un varco finché un nemico non cade — la "porta di
## nebbia" della Traccia Perduta, tesa sulla bocca del canyon fra l'arena del
## Lupo Alpha e la conca della carovana.
##
## Perché una membrana e non un crollo di rocce: la barriera deve SPARIRE quando
## l'Alpha muore, e un masso che si smaterializza non si legge. Una membrana sì,
## ed è il vocabolario visivo che il gioco usa già per l'Erosione dell'Eco (stesso
## shader del muro del boss, vedi boss_wall.gd).
##
## Blockout: forma e collisione sono definitive, la vestizione (suono d'urto
## quando ci sbatti contro, particelle sul bordo) resta un passaggio a parte.

const ArcaniumVFX := preload("res://arcanium/systems/vfx/arcanium_vfx.gd")

## Viola dell'Erosione, lo stesso di boss_wall.gd: non è un colore nuovo, è
## "questa cosa è Eco" detto come lo dice già il resto del gioco.
const TINT := Color(0.80, 0.45, 1.0)
const FADE := 1.2

## Larghezza totale del varco da chiudere e altezza della membrana.
@export var span : float = 12.0
@export var height : float = 6.0
## In quanti quad si spezza la membrana: uno solo su 12m stira troppo la texture.
@export var segments : int = 6

signal opened

var _mat : ShaderMaterial = null
var _open := false

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	## Il director la ritrova per gruppo: un rebuild del livello rinumera i nodi,
	## quindi un NodePath fisso non reggerebbe.
	add_to_group("alpha_gate")

	## Un solo materiale per tutta la barriera: i segmenti sono lo stesso muro,
	## quindi devono dissolversi insieme (stessa `life`).
	_mat = ArcaniumVFX.erosion_wall_material(TINT, 1.5)

	var seg_w : float = span / float(maxi(segments, 1))
	for i in segments:
		var x : float = -span * 0.5 + seg_w * (float(i) + 0.5)
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		## Un filo più larghi del passo: quad affiancati esatti lasciano una
		## fessura visibile in mezzo (stesso accorgimento di boss_wall).
		qm.size = Vector2(seg_w * 1.12, height)
		mi.mesh = qm
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(x, height * 0.5, 0.0)
		add_child(mi)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span, height, 0.6)
	col.shape = box
	col.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(col)


func is_open() -> bool:
	return _open

## Dissolve la barriera e sblocca il passaggio. La collisione cade SUBITO (il
## player non deve sbattere contro un muro che sta già svanendo), la membrana si
## spegne nel tempo di FADE.
##
## ⚠️ `set_deferred` non è pignoleria: questo metodo viene chiamato dal segnale
## `died` del nemico, che l'HealthSystem emette in modo SINCRONO dentro
## `damage_taken` — cioè in piena risoluzione della fisica, dove cambiare
## collisioni al volo è vietato.
func open() -> void:
	if _open:
		return
	_open = true
	for c in find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", true)
	set_deferred("collision_layer", 0)

	if _mat:
		var tw := create_tween()
		tw.tween_method(func(v : float) -> void:
			if _mat:
				_mat.set_shader_parameter("life", v), 1.0, 0.0, FADE)
		await tw.finished
	opened.emit()
	queue_free()
