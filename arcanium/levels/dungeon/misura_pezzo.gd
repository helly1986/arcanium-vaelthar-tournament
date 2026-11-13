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


## Le PUNTE di un pezzo, nello spazio del pezzo: i vertici piu' alti del loro
## intorno in pianta (`raggio`, frazione del lato in pianta), cioe' le cime
## locali. Su un lampadario o un candelabro sono le candele, anche se il pezzo
## e' inclinato: ci si mettono le fiamme senza sapere a mano dove stanno. Le
## cime molto piu' alte delle altre (il gancio al centro) non sono candele.
static func punte(n : Node3D, raggio : float = 0.05) -> PackedVector3Array:
	var box := ingombro(n)
	var r := maxf(box.size.x, box.size.z) * raggio
	if r <= 0.0:
		return PackedVector3Array()
	## La cima di ogni casella della griglia in pianta.
	var cime := {}
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := relativa(mi, n)
		for s in mi.mesh.get_surface_count():
			var vs : PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in vs:
				var p := t * v
				var k := Vector2i(floori(p.x / r), floori(p.z / r))
				if not cime.has(k) or cime[k].y < p.y:
					cime[k] = p
	## Una casella e' una punta se nessuna delle vicine (due caselle intorno) e'
	## piu' alta, e se sta nella meta' alta del pezzo.
	var trovate : Array[Vector3] = []
	for k in cime:
		var p : Vector3 = cime[k]
		if p.y < box.position.y + box.size.y * 0.5:
			continue
		var cima := true
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var q : Vector2i = k + Vector2i(dx, dz)
				if q != k and cime.has(q) and cime[q].y > p.y:
					cima = false
		if cima:
			trovate.append(p)
	if trovate.is_empty():
		return PackedVector3Array()
	var quote : Array[float] = []
	for p in trovate:
		quote.append(p.y)
	quote.sort()
	var mediana : float = quote[quote.size() / 2]
	var out := PackedVector3Array()
	for p in trovate:
		if p.y <= mediana + box.size.y * 0.12:
			out.append(p)
	return out


## La trasformazione di `figlio` vista da `antenato`.
static func relativa(figlio : Node3D, antenato : Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var q : Node = figlio
	while q != null and q != antenato:
		if q is Node3D:
			t = (q as Node3D).transform * t
		q = q.get_parent()
	return t
