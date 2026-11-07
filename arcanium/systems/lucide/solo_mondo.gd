extends RefCounted

## ⚠️ Niente `class_name`: si usa con `preload`.

## I raggi delle Lucide Tecniche devono vedere il MONDO, non chi ci cammina: nemici e
## player stanno sullo stesso layer dei muri, e un raggio che li colpisse li prenderebbe
## per un muro (un fascio fermato dal primo nemico, un bersaglio che copre se' stesso, un
## buco nel suolo sotto ai piedi di chi ci sta sopra).
##
## Ritorna chi escludere, da passare come `exclude` della query.
static func esclusi(albero : SceneTree, lanciatore : Node) -> Array[RID]:
	var fuori : Array[RID] = []
	for n in albero.get_nodes_in_group("targets"):
		if n is CollisionObject3D:
			fuori.append((n as CollisionObject3D).get_rid())
	if lanciatore is CollisionObject3D:
		fuori.append((lanciatore as CollisionObject3D).get_rid())
	return fuori
