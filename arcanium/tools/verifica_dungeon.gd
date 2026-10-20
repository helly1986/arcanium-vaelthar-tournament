extends SceneTree

## Il cancello del mini-dungeon procedurale (arcanium/levels/dungeon/).
##
## Parte A, la PIANTA, su 60 semi:
##   - numero di stanze nei limiti del profilo;
##   - tutto il pavimento raggiungibile dall'ingresso;
##   - nessun nemico nell'ingresso, ogni nemico su pavimento raggiungibile;
##   - le porte stanno sul bordo della propria stanza e danno su un corridoio;
##   - nessuna trappola davanti a una porta o nell'ingresso;
##   - sull'insieme dei semi compaiono stanze chiuse, baratri, forzieri e
##     forzieri rari (la varieta' c'e' davvero).
## Parte B, la GUIDA: dall'ingresso si cammina fino a ogni nemico seguendo
##   `prossimo_punto`, senza mai pestare una cella non camminabile; e con le
##   porte chiuse bloccate, dall'ingresso non si vede dentro le stanze chiuse.
## Parte C, la COSTRUZIONE, su 4 semi: i nodi corrispondono alla pianta, cio'
##   che la camera inquadra resta sotto i 100k triangoli (nemici esclusi), e
##   dopo un secondo di fisica nessun nemico e' caduto dal pavimento.
##
## Parte D, il BAULE di Kalvorn: aperto, alza davvero il coperchio
##   (animazione "Apri" di arcanium/tools/baule_apribile.py).
##
## Uso: godot --headless --script arcanium/tools/verifica_dungeon.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const Pianta := preload("res://arcanium/levels/dungeon/pianta_dungeon.gd")
const Guida := preload("res://arcanium/levels/dungeon/guida_dungeon.gd")
const Costruttore := preload("res://arcanium/levels/dungeon/costruttore_dungeon.gd")
const PROFILO := "res://arcanium/levels/dungeon/profilo_rovine.tres"

var _fallite := 0
var _eseguite := 0
## I controlli attesi: 10 di pianta, 2 di guida, 3 per ciascuno dei 4 semi
## costruiti, 1 del baule. Meno di cosi' vuol dire che uno script non si e'
## caricato.
const ATTESE := 25


func _ok(cond : bool, msg : String) -> void:
	_eseguite += 1
	print(("ok    " if cond else "FAIL  ") + msg)
	if not cond:
		_fallite += 1


func _init() -> void:
	await process_frame
	var profilo : Resource = load(PROFILO)
	_parte_a(profilo)
	_parte_b(profilo)
	await _parte_c(profilo)
	await _parte_d()
	if _eseguite < ATTESE:
		_fallite += 1
		print("FAIL  eseguiti %d controlli su %d attesi" % [_eseguite, ATTESE])
	print("\nESITO: %s (%d fallite)" % ["OK" if _fallite == 0 else "FALLITO", _fallite])
	quit(0 if _fallite == 0 else 1)


func _parte_a(profilo : Resource) -> void:
	print("── A. la pianta, 60 semi")
	var stanze_ok := true
	var raggiunto_ok := true
	var nemici_ok := true
	var porte_ok := true
	var trappole_ok := true
	var chiuse := 0
	var baratri := 0
	var forzieri := 0
	var rari := 0
	var nemici_tot := 0
	var forme := {}
	var nei_corridoi := 0
	for s in range(1, 61):
		var p := Pianta.new()
		p.genera(profilo, s)
		if p.stanze.size() < 3 or p.stanze.size() > profilo.stanze_max:
			stanze_ok = false
			print("      seme %d: %d stanze" % [s, p.stanze.size()])
		var visti : Dictionary = p.raggiungibili()
		for z in p.profondita:
			for x in p.larghezza:
				if p.camminabile(Vector2i(x, z)) and not visti.has(Vector2i(x, z)):
					raggiunto_ok = false
		for n in p.nemici:
			var c : Vector2i = n["cella"]
			var nella_entrata : bool = n["stanza"] >= 0 and p.stanze[n["stanza"]]["ruolo"] == Pianta.Ruolo.INGRESSO
			if not p.camminabile(c) or not visti.has(c) or nella_entrata:
				nemici_ok = false
		nemici_tot += p.nemici.size()
		for st in p.stanze:
			forme[st["forma"]] = true
		for n in p.nemici:
			if n["stanza"] < 0:
				nei_corridoi += 1
		for porta in p.porte:
			for coppia in porta["celle"]:
				var dentro : Vector2i = coppia[0]
				var fuori : Vector2i = coppia[1]
				if p.stanza(dentro) != porta["stanza"] or p.stanza(fuori) != -1 or not p.camminabile(fuori):
					porte_ok = false
			if porta["chiusa"]:
				chiuse += 1
		for c in p.trappole:
			var st := p.stanza(c)
			if p._vicino_a_porta(c, 0) or (st >= 0 and p.stanze[st]["ruolo"] == Pianta.Ruolo.INGRESSO):
				trappole_ok = false
		for z in p.profondita:
			for x in p.larghezza:
				if p.cella(Vector2i(x, z)) == Pianta.Cella.BARATRO:
					baratri += 1
		forzieri += p.forzieri.size()
		for f in p.forzieri:
			if f["raro"]:
				rari += 1
	_ok(stanze_ok, "stanze fra 3 e %d" % profilo.stanze_max)
	_ok(forme.size() >= 4, "compaiono forme diverse di stanza (%s)" % str(forme.keys()))
	_ok(nei_corridoi > 0, "compaiono nemici nei corridoi (%d)" % nei_corridoi)
	_ok(raggiunto_ok, "tutto il pavimento raggiungibile dall'ingresso")
	_ok(nemici_ok, "nemici su pavimento raggiungibile, mai nell'ingresso (%d in tutto)" % nemici_tot)
	_ok(porte_ok, "porte sul bordo della stanza, aperte su un corridoio")
	_ok(trappole_ok, "nessuna trappola davanti a una porta o nell'ingresso")
	_ok(chiuse > 0, "compaiono porte chiuse (%d)" % chiuse)
	_ok(baratri > 0, "compaiono baratri (%d celle)" % baratri)
	_ok(forzieri > 0 and rari > 0, "compaiono forzieri (%d) e forzieri rari (%d)" % [forzieri, rari])


func _parte_b(profilo : Resource) -> void:
	print("── B. la guida")
	var cammino_ok := true
	var vista_ok := true
	var prove := 0
	for s in range(1, 21):
		var p := Pianta.new()
		p.genera(profilo, s)
		var g := Guida.new()
		g.pianta = p
		for n in p.nemici:
			prove += 1
			var meta : Vector3 = p.centro(n["cella"])
			var pos : Vector3 = p.centro(p.ingresso)
			var arrivato := false
			for k in 600:
				var punto : Vector3 = g.prossimo_punto(pos, meta)
				var d := punto - pos
				d.y = 0.0
				if d.length() < 0.01:
					break
				pos += d.normalized() * minf(0.5, d.length())
				if not p.camminabile(p.cella_di(pos)):
					cammino_ok = false
					print("      seme %d: si pesta la cella %s" % [s, p.cella_di(pos)])
					break
				if pos.distance_to(meta) < 0.6:
					arrivato = true
					break
			if not arrivato:
				cammino_ok = false
				print("      seme %d: non si arriva a %s" % [s, n["cella"]])
		## Porte chiuse bloccate: dentro una stanza chiusa non si vede dall'ingresso.
		for porta in p.porte:
			if porta["chiusa"]:
				for coppia in porta["celle"]:
					g.blocca(coppia[0], coppia[1], true)
		for n in p.nemici:
			if n["stanza"] < 0:
				continue
			var ruolo : int = p.stanze[n["stanza"]]["ruolo"]
			if ruolo == Pianta.Ruolo.CHIUSA or ruolo == Pianta.Ruolo.TESORO:
				if g.in_vista(p.centro(p.ingresso), p.centro(n["cella"])):
					vista_ok = false
					print("      seme %d: dall'ingresso si vede dentro la stanza chiusa %d" % [s, n["stanza"]])
		g.free()
	_ok(cammino_ok, "dall'ingresso si raggiunge ogni nemico seguendo la guida (%d percorsi)" % prove)
	_ok(vista_ok, "con le porte chiuse, le stanze chiuse non si vedono dall'ingresso")


func _parte_c(profilo : Resource) -> void:
	print("── C. la costruzione")
	for s in [3, 11, 27, 42]:
		var radice := Node3D.new()
		root.add_child(radice)
		var d : Node3D = Costruttore.new()
		d.profilo = profilo
		d.seme = s
		d.costruisci_subito = false
		d.mostra_contatore = false
		radice.add_child(d)
		d.costruisci()
		var p : RefCounted = d.pianta
		var porte := get_nodes_in_group("porta_dungeon").size()
		var trappole := get_nodes_in_group("trappola_dungeon").size()
		var forzieri := get_nodes_in_group("forziere_dungeon").size()
		var nemici := get_nodes_in_group("nemico_dungeon").size()
		var chiuse : int = p.porte.filter(func(x): return x["chiusa"]).size()
		_ok(porte == chiuse and trappole == p.trappole.size() and forzieri == p.forzieri.size() and nemici == p.nemici.size(),
			"seme %d: porte %d/%d, trappole %d/%d, forzieri %d/%d, nemici %d/%d" % [s, porte, chiuse, trappole, p.trappole.size(), forzieri, p.forzieri.size(), nemici, p.nemici.size()])
		## Il budget vale per cio' che la camera inquadra: il dungeon intero e'
		## ben piu' grande di un'arena, e i pezzi fuori schermo non si disegnano
		## (sono istanze separate, ognuna col suo AABB). Per ogni stanza si
		## contano i triangoli nella zona che la camera isometrica vede col
		## giocatore al centro della stanza: 36 m di larghezza, da 20 m dietro
		## a 12 m davanti (la camera guarda da sud).
		var tot := 0
		var peggiore := 0
		var per_mesh : Array = []
		for m in d.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null or _sotto_nemico(mi):
				continue
			var n_tri := 0
			for k in mi.mesh.get_surface_count():
				var a := mi.mesh.surface_get_arrays(k)
				var idx = a[Mesh.ARRAY_INDEX]
				n_tri += (idx.size() if idx != null and idx.size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
			tot += n_tri
			per_mesh.append([mi.global_transform * mi.get_aabb(), n_tri])
		for st in p.stanze:
			var r : Rect2i = st["rect"]
			var c : Vector3 = p.centro(r.position + r.size / 2)
			var vista := AABB(Vector3(c.x - 18.0, -5.0, c.z - 20.0), Vector3(36.0, 20.0, 32.0))
			var somma := 0
			for e in per_mesh:
				if (e[0] as AABB).intersects(vista):
					somma += int(e[1])
			peggiore = maxi(peggiore, somma)
		_ok(peggiore < 100000, "seme %d: in vista al massimo %d triangoli (sotto i 100k; il dungeon intero ne ha %d)" % [s, peggiore, tot])
		for k in 60:
			await physics_frame
		var caduti := 0
		for e in get_nodes_in_group("nemico_dungeon"):
			if (e as Node3D).global_position.y < -1.0:
				caduti += 1
		_ok(caduti == 0, "seme %d: dopo un secondo di fisica nessun nemico e' caduto (%d)" % [s, caduti])
		radice.queue_free()
		await process_frame
		await process_frame


func _parte_d() -> void:
	print("── D. il baule di Kalvorn")
	var Forziere := preload("res://arcanium/levels/dungeon/forziere_dungeon.gd")
	var f : StaticBody3D = Forziere.new()
	f.scena = load("res://assets/environment/dungeon/baule_sylvorn.glb")
	root.add_child(f)
	await process_frame
	f.activate(null)
	await process_frame
	var apre := false
	for ap in f.find_children("*", "AnimationPlayer", true, false):
		if (ap as AnimationPlayer).current_animation == "Apri":
			apre = true
	_ok(apre, "aperto, il baule di Kalvorn suona l'animazione del coperchio")
	f.queue_free()


func _sotto_nemico(n : Node) -> bool:
	var q := n
	while q != null:
		if q.is_in_group("nemico_dungeon"):
			return true
		q = q.get_parent()
	return false
