extends RefCounted

## L'ingombro di un pezzo importato (un GLB istanziato): l'AABB di tutte le sue
## mesh, nello spazio del pezzo. Serve a scalarlo alla misura voluta, come fa
## arena_builder. Funziona anche prima che il pezzo sia nell'albero: le
## trasformazioni si compongono risalendo i genitori, senza passare dal mondo.

static func ingombro(n : Node3D) -> AABB:
	var box := AABB()
	var primo := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := relativa(mi, n) * mi.get_aabb()
		box = b if primo else box.merge(b)
		primo = false
	return box


## La trasformazione di `figlio` vista da `antenato`.
static func relativa(figlio : Node3D, antenato : Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var q : Node = figlio
	while q != null and q != antenato:
		if q is Node3D:
			t = (q as Node3D).transform * t
		q = q.get_parent()
	return t
