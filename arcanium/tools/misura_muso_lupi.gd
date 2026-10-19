extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## MISURA: dove sta il MUSO dei lupi all'istante del morso
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/misura_muso_lupi.gd
##
## Il colpo di un nemico si valuta dalla distanza fra i CENTRI (`_apply_hit`).
## Su un corpo lungo come l'Alpha (scala 6,5) il centro sta lontanissimo dal
## muso: lo scenario colpi_lupi lo ha visto mordere a 3,3 m con il muso a un
## metro dal player. Qui, per ogni morso di lupo comune e Alpha, si mette la clip
## all'istante di contatto e si legge quanto il muso sta DAVANTI al centro.

const SCENE := {
	"lupo": "res://arcanium/characters/lupo.tscn",
	"alpha": "res://arcanium/characters/lupo_alpha.tscn",
}
const OSSA := ["head", "jaw", "headend", "headfront"]


func _initialize() -> void:
	_misura()


func _misura() -> void:
	await process_frame
	for nome in SCENE:
		var n : Node3D = (load(SCENE[nome]) as PackedScene).instantiate()
		n.set("ai_enabled", false)
		root.add_child(n)
		await physics_frame
		await process_frame
		var ap : AnimationPlayer = n.anim_player
		var sk : Skeleton3D = n.find_child("Skeleton3D", true, false)
		var avanti : Vector3 = n.global_transform.basis.z
		avanti.y = 0.0
		avanti = avanti.normalized()
		var forma = n.find_child("CollisionShape3D", false, false)
		var raggio := -1.0
		if forma and forma.shape is CapsuleShape3D:
			raggio = (forma.shape as CapsuleShape3D).radius
		elif forma and forma.shape is BoxShape3D:
			raggio = (forma.shape as BoxShape3D).size.z * 0.5
		print("=== %s  scala modello %.2f  corpo: %s raggio/semilunghezza %.2f" % [
			nome, n.model.scale.x, forma.shape.get_class() if forma else "?", raggio])
		for m in n.move_set.moves:
			if m.contact_times == null or m.contact_times.is_empty() or m.leap_to_target:
				continue
			if not ap.has_animation(m.anim):
				print("  %s: clip %s assente" % [m.id, m.anim])
				continue
			for t in [0.0] + Array(m.contact_times):
				ap.play(m.anim)
				ap.seek(t, true)
				ap.advance(0.0)
				var riga := "  %-3s %-26s t=%.2f  portata %.2f |" % [m.id, m.anim, t, m.move_range]
				for o in OSSA:
					var i := sk.find_bone(o)
					if i < 0:
						continue
					var p : Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
					var d := p - n.global_position
					riga += "  %s avanti %.2f su %.2f" % [o, d.dot(avanti), d.y]
				print(riga)
				if t > 0.0:
					print("      punta del muso (mesh): %.2f m davanti al centro" % _punta(n, sk, avanti))
		_cima.clear()
		n.queue_free()
		await process_frame
	quit(0)


## I vertici piu' avanzati della mesh a riposo, rideformati con lo skinning
## della posa corrente: la punta vera del muso, che le ossa non raggiungono
## (l'osso piu' avanti e' la spalla).
var _cima : Array = []

func _punta(n : Node3D, sk : Skeleton3D, avanti : Vector3) -> float:
	var mi : MeshInstance3D = null
	for c in sk.get_children():
		if c is MeshInstance3D and c.skin != null:
			mi = c
			break
	if mi == null:
		return -1.0
	var arr := mi.mesh.surface_get_arrays(0)
	var vv : PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bb : PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ww : PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bb.size() / vv.size()
	if _cima.is_empty():
		var ord : Array = []
		for k in vv.size():
			ord.append([(mi.global_transform * vv[k] - n.global_position).dot(avanti), k])
		ord.sort_custom(func(a, b): return a[0] > b[0])
		for k in 40:
			_cima.append(ord[k][1])
	var skin : Skin = mi.skin
	var migliore := -99.0
	for k in _cima:
		var pos := Vector3.ZERO
		for j in per:
			var w : float = ww[k * per + j]
			if w <= 0.0:
				continue
			var bind : int = bb[k * per + j]
			var osso := skin.get_bind_bone(bind)
			if osso < 0:
				osso = sk.find_bone(skin.get_bind_name(bind))
			pos += w * (sk.global_transform * sk.get_bone_global_pose(osso) * skin.get_bind_pose(bind) * vv[k])
		migliore = maxf(migliore, (pos - n.global_position).dot(avanti))
	return migliore
