@tool
extends SkeletonModifier3D

## ═══════════════════════════════════════════════════════════════════════════
## LA SECONDA MANO SULL'ARMA — la sinistra segue la destra, sopra ogni clip
## ═══════════════════════════════════════════════════════════════════════════
##
## Le armi a due mani (l'asta di Zarine, la vanga di Aurin) stanno nella
## destra; la sinistra le si appoggia (2026-11-01). Le clip del moveset non la
## mettono sull'arma: qui, dopo l'animazione, un IK a due ossa porta la mano
## sinistra nella posizione che ha rispetto alla DESTRA nella guardia a due
## mani del banco (CampioneResource.seconda_mano, misurata dalla guardia di
## guardia_due_mani.gd). Legarla alla mano destra invece che al nodo dell'arma
## evita di leggere un BoneAttachment che si aggiorna un fotogramma dopo.
##
## Il gomito resta dalla parte in cui lo mette la clip; la mano prende
## l'orientamento della guardia. Vale finche' l'arma si vede (`oggetto`).
## Le dita le chiude presa_mano.gd, che gira dopo.

## La mano sinistra nello spazio della destra (ossa Humanoid, spazio scheletro).
@export var relativa := Transform3D.IDENTITY
## L'arma tenuta: la seconda mano vale solo mentre si vede. Vuoto = sempre.
var oggetto : Node3D = null


func _process_modification() -> void:
	if oggetto != null and not oggetto.is_visible_in_tree():
		return
	var sk := get_skeleton()
	if sk == null:
		return
	var i_d := sk.find_bone("RightHand")
	var i_a := sk.find_bone("LeftUpperArm")
	var i_b := sk.find_bone("LeftLowerArm")
	var i_c := sk.find_bone("LeftHand")
	if i_d < 0 or i_a < 0 or i_b < 0 or i_c < 0:
		return
	var voluta := sk.get_bone_global_pose(i_d) * relativa
	var ta := sk.get_bone_global_pose(i_a)
	var tb := sk.get_bone_global_pose(i_b)
	var tc := sk.get_bone_global_pose(i_c)
	var a := ta.origin
	var b := tb.origin
	var c := tc.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var verso := voluta.origin - a
	if l1 < 1e-4 or l2 < 1e-4 or verso.length() < 1e-4:
		return
	var d := clampf(verso.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	verso = verso.normalized()
	## Il gomito dalla parte della clip: la componente di spalla->gomito
	## perpendicolare alla nuova direzione del braccio.
	var fuori := (b - a) - verso * (b - a).dot(verso)
	if fuori.length() < 1e-4:
		fuori = Vector3.DOWN - verso * verso.y
	fuori = fuori.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var gomito := a + (verso * cos_a + fuori * sqrt(1.0 - cos_a * cos_a)) * l1
	var polso := a + verso * d
	var r1 := _rotazione(b - a, gomito - a)
	var r2 := _rotazione(r1 * (c - b), polso - gomito)
	sk.set_bone_global_pose(i_a, Transform3D(r1 * ta.basis, a))
	sk.set_bone_global_pose(i_b, Transform3D(r2 * r1 * tb.basis, gomito))
	sk.set_bone_global_pose(i_c, Transform3D(voluta.basis, polso))


static func _rotazione(da : Vector3, a : Vector3) -> Basis:
	var u := da.normalized()
	var v := a.normalized()
	var asse := u.cross(v)
	if asse.length() < 0.00001:
		return Basis()
	return Basis(asse.normalized(), acos(clampf(u.dot(v), -1.0, 1.0)))
