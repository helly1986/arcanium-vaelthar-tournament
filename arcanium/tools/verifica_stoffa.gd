extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## VERIFICA DELLA STOFFA SIMULATA — arcanium/systems/stoffa_simulata.gd
## ═══════════════════════════════════════════════════════════════════════════
##
##   Godot.exe --path . res://arcanium/tools/verifica_stoffa.tscn
##
## ⚠️ NON `--headless`: senza RenderingDevice il componente non fa niente
## (voluto), e non ci sarebbe niente da verificare.
##
## Sul Mago vero (sylvorn_mago.tscn):
##   1. ha le mesh Stoffa* e un solver per ognuna, coi peer incrociati;
##   2. con la camera vicina la stoffa SIMULA (gpu_driven sul materiale);
##   3. con la camera oltre `distanza_attiva` torna skinning e il solver si ferma;
##   4. riavvicinata, riparte (warm start) senza inerzia arretrata.

const SCENA_MAGO := "res://arcanium/characters/sylvorn_mago.tscn"

var _problemi := 0


func _ok(cond : bool, testo : String) -> void:
	print("  %s  %s" % ["ok  " if cond else "KO  ", testo])
	if not cond:
		_problemi += 1


func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 1.5, 4), Vector3(0, 1, 0), Vector3.UP)
	var m : Node3D = (load(SCENA_MAGO) as PackedScene).instantiate()
	add_child(m)
	m.set_physics_process(false)
	var st : Node3D = m.get_node_or_null("StoffaSimulata")
	print("=== 1. MONTAGGIO ===")
	_ok(st != null, "il mago ha il nodo StoffaSimulata")
	if st == null:
		_fine()
		return
	var solver : Array = st.get_children().filter(func(n): return n.get_script() == st.SOLVER)
	var stoffe := m.find_children("Stoffa*", "MeshInstance3D", true, false)
	_ok(stoffe.size() >= 2, "le mesh di stoffa ci sono (%d)" % stoffe.size())
	_ok(solver.size() == stoffe.size(), "un solver per stoffa (%d)" % solver.size())
	var peer_ok := true
	for s in solver:
		peer_ok = peer_ok and (s.get("peer_cloth_solvers") as Array).size() == solver.size() - 1
	_ok(peer_ok, "ogni solver nomina gli altri come peer")
	for i in 30:
		await get_tree().process_frame
	print("=== 2. VICINO ===")
	_ok(st.attiva(), "con la camera a 4 m la stoffa simula")
	_ok(_guidati(solver) == solver.size(), "il materiale legge la simulazione (gpu_driven)")
	print("=== 3. LONTANO ===")
	cam.global_position = Vector3(0, 1.5, st.distanza_attiva + 10.0)
	for i in 5:
		await get_tree().process_frame
	_ok(not st.attiva(), "oltre %.0f m la stoffa si spegne" % st.distanza_attiva)
	_ok(_guidati(solver) == 0, "e la mesh torna allo skinning (gpu_driven false)")
	_ok(solver.all(func(s): return not s.is_processing()), "e i solver non girano")
	## il mago si sposta mentre la stoffa dorme: al risveglio l'inerzia non
	## deve portarsi dietro questo salto
	m.global_position += Vector3(6, 0, 0)
	for i in 5:
		await get_tree().process_frame
	print("=== 4. DI NUOVO VICINO ===")
	cam.look_at_from_position(m.global_position + Vector3(0, 1.5, 4), m.global_position + Vector3(0, 1, 0), Vector3.UP)
	for i in 5:
		await get_tree().process_frame
	_ok(st.attiva(), "riavvicinata, la stoffa riparte")
	_ok(_guidati(solver) == solver.size(), "e il materiale torna alla simulazione")
	var ref : Node3D = solver[0].get("_ref_node")
	_ok(ref != null and (solver[0].get("_prev_skel_world_pos") as Vector3).distance_to(ref.global_position) < 0.5,
		"l'inerzia riparte da dove sta il mago, non da 6 m prima")
	_fine()


func _guidati(solver : Array) -> int:
	var n := 0
	for s in solver:
		var mat : ShaderMaterial = s.get("_surf_mat")
		if mat != null and mat.get_shader_parameter("gpu_driven"):
			n += 1
	return n


func _fine() -> void:
	print("PASSATO — 0 problemi" if _problemi == 0 else "FALLITO — %d problemi" % _problemi)
	get_tree().quit(0 if _problemi == 0 else 1)
