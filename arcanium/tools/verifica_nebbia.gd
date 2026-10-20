extends SceneTree

## Cancello della NEBBIA DI GUERRA del mini-dungeon (nebbia_dungeon.gd), su
## piu' semi di dungeon_prova:
##   - col giocatore all'ingresso, l'ingresso e' in vista e le stanze dietro
##     porte chiuse non sono nemmeno esplorate;
##   - i nemici si vedono solo se la loro cella e' in vista (e ce n'e' almeno
##     uno nascosto);
##   - le luci delle zone mai viste sono spente, qualcuna e' accesa;
##   - ogni mesh del dungeon porta il velo, nessun nemico lo porta;
##   - portato il giocatore in una stanza che dall'ingresso non si vede, quella
##     entra in vista e l'ingresso resta esplorato ma fuori vista.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_nebbia.gd

const Pianta := preload("res://arcanium/levels/dungeon/pianta_dungeon.gd")
const SEMI := [3, 11, 42]
const ATTESE := 18

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	for s in SEMI:
		await _prova(s)
	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti else 0)


func _prova(s : int) -> void:
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	var d : Node = scena.get_node("Dungeon")
	d.seme = s
	root.add_child(scena)
	for i in 3:
		await process_frame
	var p : RefCounted = d.pianta
	var n : Node = d.nebbia
	if n == null:
		_ok(false, "seme %d: la nebbia c'e'" % s)
		scena.queue_free()
		return

	## all'ingresso
	var ingresso_visto := true
	for c in p.celle_di(p.stanze.find_custom(func(st): return st["ruolo"] == Pianta.Ruolo.INGRESSO)):
		if p.camminabile(c) and not n.in_vista(c):
			ingresso_visto = false
	var chiuse_viste := 0
	for i in p.stanze.size():
		if p.stanze[i]["ruolo"] in [Pianta.Ruolo.CHIUSA, Pianta.Ruolo.TESORO]:
			for c in p.celle_di(i):
				if n.esplorata(c):
					chiuse_viste += 1
	_ok(ingresso_visto and chiuse_viste == 0,
			"seme %d: ingresso in vista, stanze chiuse mai viste (%d celle viste)" % [s, chiuse_viste])

	var sbagliati := 0
	var nascosti := 0
	for e in get_nodes_in_group("nemico_dungeon"):
		var vede : bool = n.in_vista(p.cella_di(e.global_position))
		if e.visible != vede:
			sbagliati += 1
		if not e.visible:
			nascosti += 1
	_ok(sbagliati == 0 and nascosti > 0, "seme %d: nemici visibili solo in vista (%d nascosti, %d sbagliati)" % [s, nascosti, sbagliati])

	var accese := 0
	var spente_male := 0
	var luci := 0
	for coppia in n._a_cella:
		var nodo : Node3D = coppia[0]
		if not (nodo is Light3D):
			continue
		luci += 1
		if nodo.visible:
			accese += 1
		var esplorata := false
		for dd in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			esplorata = esplorata or n.esplorata(coppia[1] + dd)
		if nodo.visible != esplorata:
			spente_male += 1
	_ok(accese > 0 and accese < luci and spente_male == 0,
			"seme %d: luci accese solo dove esplorato (%d su %d)" % [s, accese, luci])

	var senza_velo := 0
	var nemici_velati := 0
	for m in d.find_children("*", "MeshInstance3D", true, false):
		var in_nemico := false
		var q : Node = m
		while q != d:
			if q.is_in_group("nemico_dungeon"):
				in_nemico = true
				break
			q = q.get_parent()
		if in_nemico and m.material_overlay != null:
			nemici_velati += 1
		elif not in_nemico and m.material_overlay != n.materiale:
			senza_velo += 1
	_ok(senza_velo == 0 and nemici_velati == 0, "seme %d: velo su ogni mesh del dungeon, mai sui nemici (%d senza, %d nemici velati)" % [s, senza_velo, nemici_velati])

	## in un'altra stanza: la piu' lontana che dall'ingresso non si vede ed e'
	## raggiungibile senza porte chiuse
	var raggiunte : Dictionary = p.raggiungibili()
	var meta := -1
	for i in p.stanze.size():
		var c : Vector2i = p.stanze[i]["centro"]
		if p.stanze[i]["ruolo"] == Pianta.Ruolo.COMBATTIMENTO and raggiunte.has(c) and p.camminabile(c) and not n.esplorata(c):
			meta = i
	if meta < 0:
		_ok(false, "seme %d: c'e' una stanza aperta non ancora vista" % s)
		_ok(false, "seme %d: (salta)" % s)
	else:
		var c : Vector2i = p.stanze[meta]["centro"]
		var g : Node3D = scena.get_node("Player")
		g.global_position = p.centro(c) + Vector3(0, 0.2, 0)
		n.aggiorna(true)
		_ok(n.in_vista(c), "seme %d: portato nella stanza %d, la stanza e' in vista" % [s, meta])
		var cin : Vector2i = p.ingresso
		_ok(n.esplorata(cin) and not n.in_vista(cin),
				"seme %d: l'ingresso resta esplorato ma fuori vista" % s)
	scena.queue_free()
	for i in 3:
		await process_frame
