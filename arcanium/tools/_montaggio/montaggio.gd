extends Node3D
## Allinea per CALCOLO le armi sulle ossa d'aggancio e stampa la Transform3D
## da incollare nella scena del nemico.
##
## Misurato sul rest del Fante: AVANTI = Z+, SINISTRA = X+, ALTO = Y+.
## I bersagli si dichiarano in QUELLO spazio -- "la lama punta in basso e un po'
## avanti" -- e poi si convertono nello spazio dell'osso. Dichiarare
## direttamente una matrice nell'osso e' il modo classico di sbagliare.
const MODELLO := "res://assets/characters/enemies/consumati_sylvorn/sylvorn_fante_rigged.glb"
const DIR := "res://assets/equipment/EnemyEquipment/"

## nome -> file, osso, lunghezza(m), frazione lungo l'asse dove sta l'osso,
##         direzione dell'asse lungo, direzione della NORMALE del pezzo
const PEZZI := {
	"Spada": ["spada_guarnigione_sylvorn", "Prop_Attachment_R", 0.95, 0.86,
		Vector3(0.10, -1.0, 0.42), Vector3(1.0, 0.0, 0.15)],
	# ⚠️ NON gli stessi bersagli della spada a una mano: lo spadone gira le clip
	# `sword_th_*`, che sono autorate a due mani e non hanno niente a che vedere
	# con la presa a una. Puntato in basso come la spada, con 1.50 m di lama che
	# escono dal pugno, la punta finisce SOTTO il terreno. Qui e' portato avanti
	# e appena inclinato in basso: la punta resta a mezzo metro da terra.
	"Spadone": ["spadone_guarnigione_sylvorn", "Prop_Attachment_R", 1.70, 0.12,
		Vector3(-0.04, -0.34, 0.94), Vector3(1.0, 0.0, 0.10)],
	"Scudo": ["scudo_guarnigione_sylvorn", "Shield_Attachment_L", 0.87, 0.52,
		Vector3(0.12, -1.0, 0.10), Vector3(0.38, 0.05, 0.92)],
	"ScudoRotto": ["scudo_guarnigione_sylvorn_rotto", "Shield_Attachment_L", 0.87, 0.52,
		Vector3(0.12, -1.0, 0.10), Vector3(0.38, 0.05, 0.92)],
}
@export var quali : PackedStringArray = ["Spada", "Scudo", "Spadone"]

func _ready() -> void:
	var m = (load(MODELLO) as PackedScene).instantiate()
	add_child(m)
	var sk : Skeleton3D = m.find_child("Skeleton3D", true, false)
	for q in quali:
		var d : Array = PEZZI[q]
		var ba := BoneAttachment3D.new()
		ba.name = "Att_" + q
		ba.bone_name = d[1]
		ba.bone_idx = sk.find_bone(str(d[1]))
		sk.add_child(ba)
		var prop = (load(DIR + str(d[0]) + ".glb") as PackedScene).instantiate()
		prop.name = q
		ba.add_child(prop)
		var osso : Transform3D = sk.get_bone_global_rest(ba.bone_idx)
		prop.transform = _allinea(prop, float(d[2]), float(d[3]), d[4], d[5], osso)
		print("%s|%s|%s" % [q, d[1], _stampa(prop.transform)])
	print("PRONTO")

func _allinea(prop: Node3D, lunghezza: float, frazione: float,
		bers_lungo: Vector3, bers_normale: Vector3, osso: Transform3D) -> Transform3D:
	# ⚠️ I vertici vanno presi nello spazio del PEZZO, non del mondo:
	# `global_transform` contiene gia' la trasformazione dell'osso d'aggancio, e
	# usarla qui produce una matrice che applica quella dell'osso due volte --
	# l'arma finisce piantata nel petto. Costato un giro.
	var inv : Transform3D = prop.global_transform.affine_inverse()
	var pts : PackedVector3Array = []
	for mi in _mesh(prop):
		var t : Transform3D = inv * mi.global_transform
		for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			pts.append(t * v)
	var c := Vector3.ZERO
	for p in pts: c += p
	c /= pts.size()
	# tre assi principali: potenza + deflazione. a0 = il piu' lungo,
	# a2 = il piu' sottile, cioe' la NORMALE del pezzo (il piatto della lama).
	var a0 := _principale(pts, c, [])
	var a1 := _principale(pts, c, [a0])
	var a2 := a0.cross(a1).normalized()
	var lo := INF
	var hi := -INF
	for p in pts:
		var t : float = (p - c).dot(a0)
		lo = min(lo, t); hi = max(hi, t)
	var s : float = lunghezza / (hi - lo)
	# ⚠️ Verso dell'asse: lo decide la CROCIERA, non lo spessore ai capi.
	# Confrontare i due capi e' ambiguo -- su questa spada il pomo (0.133) e la
	# punta (0.098) si somigliano troppo e la lama e' uscita puntata all'insu'.
	# Il massimo di raggio lungo l'asse invece e' inequivocabile: e' la crociera
	# sulle spade (0.35 contro 0.15) e il bordo alto sugli scudi. `a0` punta
	# SEMPRE via dal capo pesante, cioe' verso la punta.
	if _dove_il_massimo(pts, c, a0, lo, hi) > 0.5:
		a0 = -a0; a2 = -a2
		var tmp := lo; lo = -hi; hi = -tmp
	var ancora : Vector3 = c + a0 * (lo + (hi - lo) * frazione)
	# la rotazione: a0 sul bersaglio lungo, a2 sulla normale, in spazio OSSO
	var L : Vector3 = (osso.basis.inverse() * bers_lungo).normalized()
	var N : Vector3 = (osso.basis.inverse() * bers_normale).normalized()
	N = (N - L * N.dot(L)).normalized()
	var b := Basis(L.cross(N), L, N)                     # colonne X,Y,Z
	var b0 := Basis(a0.cross(a2), a0, a2)
	var R : Basis = b * b0.inverse()
	var bs : Basis = R.scaled(Vector3.ONE * s)
	return Transform3D(bs, -(bs * ancora))

func _principale(pts: PackedVector3Array, c: Vector3, tolti: Array) -> Vector3:
	var a := Vector3(0.37, 0.51, 0.78).normalized()
	for _i in 60:
		var n := Vector3.ZERO
		for p in pts:
			var d := p - c
			n += d * d.dot(a)
		for t in tolti: n -= t * n.dot(t)
		if n.length() > 1e-12: a = n.normalized()
	return a

## Dove sta il massimo di raggio lungo l'asse, in frazione 0..1 da lo a hi.
func _dove_il_massimo(pts: PackedVector3Array, c: Vector3, a: Vector3, lo: float, hi: float) -> float:
	var n := 24
	var somma := PackedFloat32Array(); somma.resize(n)
	var conta := PackedInt32Array(); conta.resize(n)
	for p in pts:
		var t : float = (p - c).dot(a)
		var i : int = clampi(int((t - lo) / (hi - lo) * n), 0, n - 1)
		somma[i] += ((p - c) - a * t).length(); conta[i] += 1
	var mi := 0
	var mv := -1.0
	for i in n:
		if conta[i] < 8: continue
		var r : float = somma[i] / conta[i]
		if r > mv: mv = r; mi = i
	return (float(mi) + 0.5) / float(n)


## Raggio medio della mesh entro una fettina a un capo dell'asse.
func _spessore(pts: PackedVector3Array, c: Vector3, a: Vector3, lo: float, hi: float, alto: bool) -> float:
	var q : float = (hi - 0.08 * (hi - lo)) if alto else (lo + 0.08 * (hi - lo))
	var w : float = 0.06 * (hi - lo)
	var somma := 0.0
	var n := 0
	for p in pts:
		var t : float = (p - c).dot(a)
		if absf(t - q) < w:
			somma += ((p - c) - a * t).length(); n += 1
	return 0.0 if n == 0 else somma / n

func _mesh(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and n.mesh != null: out.append(n)
	for ch in n.get_children(): out.append_array(_mesh(ch))
	return out

func _stampa(t: Transform3D) -> String:
	var b := t.basis
	return "Transform3D(%.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f)" % [
		b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]
