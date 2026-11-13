extends Node3D

## ⚠️ Niente `class_name`: si usa per percorso (preload), come blade_trail.gd.

## ═══════════════════════════════════════════════════════════════════════════
## SCIA DELLA LAMA — il fendente si vede (2026-11-13)
## ═══════════════════════════════════════════════════════════════════════════
##
## L'utente: attacchi a una mano «soulslike, con scia visibile». Un nastro che segue la
## lama VERA: a ogni tick di fisica si prendono base e punta della forma della lama
## (la stessa definizione di punta di BladeTrail.tip_of, che held_weapon.gd ridimensiona
## per ogni arma) e si tiene una storia breve. Fra due campioni il nastro si leviga con
## una Catmull-Rom: a 60 fps un fendente veloce fa 30-40 gradi a fotogramma, e senza
## curvare la scia uscirebbe a ventaglio di spigoli.
##
## E' accesa quando la lama PUO' COLPIRE (`monitoring` dell'Area, la finestra
## dell'EquipmentSystem e delle Lucide), cioe' esattamente nel tratto che fa danno: la
## scia dice al giocatore dove la spada ferisce. Spenta, i punti vecchi si consumano da
## soli in `DURATA` secondi.

const BladeTrail := preload("res://arcanium/systems/blade_trail.gd")
const OMBRA := preload("res://arcanium/systems/scia_lama.gdshader")

## Quanto vive un tratto di scia.
const DURATA := 0.14
## Dove comincia la scia lungo la lama (0 = elsa, 1 = punta): la parte vicino alla mano
## si muove poco e farebbe solo un velo sopra il braccio.
const DALLA := 0.45
## Suddivisioni fra due campioni.
const PASSI := 5

## L'Area3D della lama (stabile anche cambiando arma).
@export var blade : Area3D
@export var colore : Color = Color(0.85, 0.9, 1.0)

var _storia : Array = []   ## [{t, base, punta}], dal piu' vecchio al piu' nuovo
var _mesh := ImmediateMesh.new()
var _mat := ShaderMaterial.new()
var _t := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var mi := MeshInstance3D.new()
	mi.name = "Nastro"
	mi.mesh = _mesh
	_mat.shader = OMBRA
	_mat.set_shader_parameter("colore", Vector3(colore.r, colore.g, colore.b))
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Il nastro e' in coordinate di mondo e cambia ogni fotogramma: niente culling.
	mi.extra_cull_margin = 16384.0
	add_child(mi)


## Il colore della scia (le infusioni dell'arma, in futuro): bianco-argento di default.
func tingi(c : Color) -> void:
	colore = c
	_mat.set_shader_parameter("colore", Vector3(c.r, c.g, c.b))


func _physics_process(delta : float) -> void:
	_t += delta
	if blade != null and blade.monitoring and blade.is_visible_in_tree() and _misura_lama():
		var punta : Vector3 = blade.global_transform * _punta_locale
		var elsa : Vector3 = blade.global_transform * _elsa_locale
		_storia.append({"t": _t, "base": elsa.lerp(punta, DALLA), "punta": punta})
	elif not _storia.is_empty() and _t - _storia.back()["t"] > 0.001:
		## Lama spenta: la scia si stacca, il prossimo fendente ne comincia una nuova.
		_storia.back()["fine"] = true
	while not _storia.is_empty() and _t - _storia[0]["t"] > DURATA:
		_storia.pop_front()
	_disegna()


## La lama VISIBILE, non la hitbox: quella e' piu' lunga della spada (copre la portata,
## ArcaniumEquipmentResource.hitbox_size) e la scia finiva mezzo metro oltre la punta.
## Dall'ingombro delle mesh dell'arma, nello spazio dell'Area: l'asse piu' lungo e' la
## lama, il capo piu' lontano dalla mano (l'origine dell'Area) e' la punta. Si rimisura
## quando held_weapon.gd cambia il modello.
var _punta_locale := Vector3.ZERO
var _elsa_locale := Vector3.ZERO
var _modello_misurato : int = 0

func _misura_lama() -> bool:
	## Solo quelle VISIBILI: sotto la lama resta il modello del template, spento.
	var mesh := blade.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.is_visible_in_tree())
	if mesh.is_empty():
		return false
	var chiave := 0
	for m in mesh:
		chiave ^= m.get_instance_id()
	if chiave == _modello_misurato:
		return true
	var inv := blade.global_transform.affine_inverse()
	var box := AABB()
	var primo := true
	for m in mesh:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := mi.get_aabb()
		for k in 8:
			var p : Vector3 = inv * (mi.global_transform * a.get_endpoint(k))
			if primo:
				box = AABB(p, Vector3.ZERO)
				primo = false
			else:
				box = box.expand(p)
	if primo:
		return false
	var asse := box.get_longest_axis_index()
	var lo := box.position
	var hi := box.end
	var c := box.get_center()
	var capo_a := c
	var capo_b := c
	capo_a[asse] = lo[asse]
	capo_b[asse] = hi[asse]
	if capo_a.length() > capo_b.length():
		_punta_locale = capo_a
		_elsa_locale = capo_b
	else:
		_punta_locale = capo_b
		_elsa_locale = capo_a
	_modello_misurato = chiave
	return true


func _forma() -> CollisionShape3D:
	if blade == null:
		return null
	for c in blade.get_children():
		if c is CollisionShape3D:
			return c
	return null


func _mezza(forma : CollisionShape3D) -> float:
	if forma.shape is BoxShape3D:
		return (forma.shape as BoxShape3D).size.y * 0.5
	if forma.shape is CapsuleShape3D:
		return (forma.shape as CapsuleShape3D).height * 0.5
	if forma.shape is CylinderShape3D:
		return (forma.shape as CylinderShape3D).height * 0.5
	return 0.0


func _disegna() -> void:
	_mesh.clear_surfaces()
	if _storia.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	var n := _storia.size()
	for i in n - 1:
		if _storia[i].get("fine", false):
			continue   ## fra un fendente e il successivo non si cuce
		var p0 : Dictionary = _storia[maxi(i - 1, 0)]
		var p1 : Dictionary = _storia[i]
		var p2 : Dictionary = _storia[i + 1]
		var p3 : Dictionary = _storia[mini(i + 2, n - 1)]
		for s in PASSI:
			var a := float(s) / PASSI
			var b := float(s + 1) / PASSI
			var ba := _cr(p0["base"], p1["base"], p2["base"], p3["base"], a)
			var pa := _cr(p0["punta"], p1["punta"], p2["punta"], p3["punta"], a)
			var bb := _cr(p0["base"], p1["base"], p2["base"], p3["base"], b)
			var pb := _cr(p0["punta"], p1["punta"], p2["punta"], p3["punta"], b)
			var ea := clampf((_t - lerpf(p1["t"], p2["t"], a)) / DURATA, 0.0, 1.0)
			var eb := clampf((_t - lerpf(p1["t"], p2["t"], b)) / DURATA, 0.0, 1.0)
			_vertice(ba, ea, 0.0); _vertice(pa, ea, 1.0); _vertice(pb, eb, 1.0)
			_vertice(ba, ea, 0.0); _vertice(pb, eb, 1.0); _vertice(bb, eb, 0.0)
	_mesh.surface_end()


func _vertice(p : Vector3, eta : float, lungo : float) -> void:
	_mesh.surface_set_uv(Vector2(eta, lungo))
	_mesh.surface_add_vertex(p)


## Catmull-Rom fra p1 e p2.
static func _cr(p0 : Vector3, p1 : Vector3, p2 : Vector3, p3 : Vector3, t : float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
