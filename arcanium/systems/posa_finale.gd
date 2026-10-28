extends SkeletonModifier3D

## ═══════════════════════════════════════════════════════════════════════════
## POSA FINALE — le pose delle ossa DOPO tutti i modificatori, per chi legge da fuori
## ═══════════════════════════════════════════════════════════════════════════
##
## `get_bone_global_pose()` chiamato da fuori restituisce la posa
## dell'ANIMAZIONE, non quella che esce dai modificatori (gia' annotato su
## inerzia_anim.gd e ik_piedi.gd). La stoffa simulata (GPUClothSolver) si
## skinnava cosi': sul giocatore l'IK dei piedi abbassa la gamba che la clip
## d'inizio passo alza, il corpo si disegnava con la gamba a terra e la tunica
## di Zarine seguiva la coscia alzata, aperta di traverso come un lenzuolo
## (2026-10-28: sparisce spegnendo IkPiedi).
##
## Va messo per ULTIMO fra i modificatori dello scheletro: qui dentro la posa
## e' gia' quella definitiva, e la si copia.

## Le pose globali di ogni osso, nello spazio dello scheletro.
var globali : Array[Transform3D] = []


func _process_modification_with_delta(_delta : float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var n := sk.get_bone_count()
	if globali.size() != n:
		globali.resize(n)
	for i in n:
		globali[i] = sk.get_bone_global_pose(i)


## La posa finale dell'osso, o quella dell'animazione finche' non ce n'e' una.
func posa(osso : int) -> Transform3D:
	if osso >= 0 and osso < globali.size():
		return globali[osso]
	return get_skeleton().get_bone_global_pose(osso)
