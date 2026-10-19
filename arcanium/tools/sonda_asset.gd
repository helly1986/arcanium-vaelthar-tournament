extends SceneTree
## Misura un asset 3D appena importato: ingombro, orientamento, triangoli,
## materiali. Da eseguire PRIMA di costruirci sopra qualcosa.
##
##   godot --headless --path . --script res://arcanium/tools/sonda_asset.gd -- res://percorso/al/modello.glb
##
## Senza argomenti misura la lista in `PREDEFINITI`.
##
## ⚠️ Perche' esiste. I modelli generati arrivano con orientamenti e scale
## arbitrari, e il nome non lo dice: pezzi che dovevano essere tappeti sono
## arrivati come PANNELLI VERTICALI, e di tre quarti sembravano corretti. Si
## scoprono solo guardando quale asse e' il piu' lungo, o guardandoli dall'alto.
## E l'origine quasi mai sta ai piedi del modello: senza saperlo, meta' bosco
## resta sospeso o sprofonda.

const PREDEFINITI := ["res://assets/environment/arena/column_broken.glb"]

const ASSI := ["X", "Y", "Z"]


func _init() -> void:
	var percorsi := OS.get_cmdline_user_args()
	if percorsi.is_empty():
		percorsi = PREDEFINITI
	for p in percorsi:
		_misura(p)
	quit()


func _misura(percorso: String) -> void:
	print("═══ %s ═══" % percorso.get_file())
	var scn: PackedScene = load(percorso)
	if scn == null:
		print("  [NO] non caricabile (importato?)")
		return
	var radice: Node = scn.instantiate()

	var aabb := AABB()
	var primo := true
	var triangoli := 0
	var superfici := 0
	var materiali := {}
	for n in _tutte(radice):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		# L'ingombro va preso nello spazio della RADICE, non della mesh: i GLB
		# hanno quasi sempre un nodo padre con una sua trasformata, e misurare
		# l'AABB locale da' numeri che non corrispondono a come il pezzo entra
		# in scena. ⚠️ La catena si risale a mano: la scena non e' nell'albero,
		# e `global_transform` li' non e' affidabile.
		var t := _fino_alla_radice(mi, radice)
		var a: AABB = t * mi.mesh.get_aabb()
		aabb = a if primo else aabb.merge(a)
		primo = false
		for i in mi.mesh.get_surface_count():
			superfici += 1
			triangoli += mi.mesh.surface_get_array_len(i) / 3
			var mat := mi.mesh.surface_get_material(i)
			if mat != null:
				materiali[mat.get_instance_id()] = mat

	if primo:
		print("  [NO] nessuna mesh dentro")
		radice.free()
		return

	var d := aabb.size
	var lungo := 0
	for i in 3:
		if d[i] > d[lungo]:
			lungo = i
	var corto := 0
	for i in 3:
		if d[i] < d[corto]:
			corto = i

	print("  ingombro   %.3f x %.3f x %.3f  (asse piu' LUNGO: %s, piu' corto: %s)"
		% [d.x, d.y, d.z, ASSI[lungo], ASSI[corto]])
	print("  proporzione lungo/corto  %.2f : 1" % (d[lungo] / maxf(d[corto], 0.0001)))
	print("  origine    la base sta a y=%.3f, il centro a %s" % [aabb.position.y, aabb.get_center()])
	if absf(aabb.position.y) > 0.02:
		print("             ⚠️ l'origine NON e' ai piedi: chi lo posa deve compensare di %.3f" % aabb.position.y)
	print("  geometria  %d triangoli, %d superfici, %d materiali" % [triangoli, superfici, materiali.size()])
	for id in materiali:
		var m: Material = materiali[id]
		print("             %s" % _racconta(m))
	radice.free()


## Trasformata accumulata da un nodo fino alla radice della scena importata.
static func _fino_alla_radice(n: Node3D, radice: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != radice:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func _racconta(m: Material) -> String:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var pezzi: Array[String] = ["StandardMaterial3D"]
		pezzi.append("albedo=%s" % ("si" if b.albedo_texture != null else "NO"))
		pezzi.append("normal=%s" % ("si" if b.normal_texture != null else "no"))
		pezzi.append("rough=%s" % ("si" if b.roughness_texture != null else "no"))
		pezzi.append("cull=%s" % ["BACK", "FRONT", "DISABLED"][b.cull_mode])
		return "  ".join(pezzi)
	return m.get_class()


func _tutte(n: Node) -> Array[Node]:
	var fuori: Array[Node] = []
	if n is MeshInstance3D:
		fuori.append(n)
	for f in n.get_children():
		fuori.append_array(_tutte(f))
	return fuori
