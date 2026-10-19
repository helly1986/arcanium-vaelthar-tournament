extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## PLAYGROUND DELLA STOFFA — GPU Cloth Sim (addons/godot_gpu_cloth) sul Mago
## ═══════════════════════════════════════════════════════════════════════════
##
##   Godot.exe --path . res://arcanium/levels/stoffa_playground.tscn -- \
##       [n=1] [stoffa=si|no|maschera] [clip=sword/sword_walk_01] \
##       [gira=si|no] [scatti=<cartella>] [misura=si]
##
## Mette N maghi su un pavimento (AI spenta), fa loro ripetere una clip e, con
## `gira=si`, li fa camminare in cerchio: e' lo spostamento del corpo che la
## stoffa deve inseguire. Con `stoffa=si` ognuno ha il suo GPUClothSolver, con
## `stoffa=maschera` si vede la MASCHERA (nero = segue le ossa, rosso = stoffa
## libera) invece della texture.
##
## Le stoffe sono le mesh `Stoffa<N>` del GLB, e la maschera e' il loro colore
## dei vertici: le fa il montaggio (`separa_stoffe` + `maschera_stoffa` in
## monta_consumato_sylvorn.py, docs/05 §4-quater). Ogni stoffa ha il suo
## solver, e le stoffe si nominano a vicenda come PEER: collidono fra loro.
##
## `misura=si` stampa il tempo medio di frame (vsync spento) fra il secondo 3
## e il secondo 8, poi chiude. `scatti=<cartella>` salva un PNG ogni mezzo
## secondo fra il secondo 2 e il 5.
##
## Manopole: `viaggio=` (metri di scarto massimo dalla posa delle ossa),
## `passi=`, `iterazioni=`, `distanza=` (oltre, la stoffa torna skinning).
## La stoffa la monta `arcanium/systems/stoffa_simulata.gd`, lo stesso nodo
## che la porta in gioco.
##
## Cosa si e' visto il 2026-09-30 (Radeon 890M, renderer Mobile):
## - il MANTELLO, guscio unico, si muove benissimo;
## - la VESTE no: Tripo la fa a gusci sovrapposti (tunica verde sopra, veste
##   bianca sotto, 1-2 cm fra l'una e l'altra) e liberi si incrociano: peggio
##   dello skinning. Con `libero=0.5 viaggio=0.05` torna quasi pulita;
##   l'autocollisione (anche a risoluzione 32) non separa gusci cosi' vicini;
## - COSTO con tutta la mesh nel solver (14.787 particelle, 82.980 vincoli in
##   59 gruppi): 8 maghi a 4x6 passi 22,8 ms/frame (senza stoffa 1,8), a 2x4
##   10,6, a 1x4 7,3 — e 1x4 si vede quasi uguale. Pesano i dispatch (gruppi x
##   passi x iterazioni), non le particelle.
## La strada: la stoffa in una mesh sua, a guscio UNICO, e solo quella nel solver.
##
## ⚠️ NON `--headless`: la stoffa gira in compute shader sul RenderingDevice.
## ⚠️ NON `--rendering-driver vulkan`: ricade su Forward+ e si misura il
## renderer sbagliato (il gioco usa il Mobile).

const SCENA_MAGO := "res://arcanium/characters/sylvorn_mago.tscn"

const GIRO_RAGGIO := 3.0

var _n := 1
var _stoffa := "si"
var _clip := "sword/sword_walk_01"
var _gira := true
var _scatti := ""
var _misura := false
## Manopole della prova: quanto puo' allontanarsi dalla posa delle ossa,
## autocollisione, passi e iterazioni del solver.
var _viaggio := 0.06
var _passi := 2
var _iterazioni := 4
var _distanza := 22.0
var _collisore := 0

var _maghi : Array[Node3D] = []
var _t := 0.0
var _frame_tempi : PackedFloat32Array = []
var _prossimo_scatto := 2.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"n": _n = int(kv[1])
			"stoffa": _stoffa = kv[1]
			"clip": _clip = kv[1]
			"gira": _gira = kv[1] == "si"
			"scatti": _scatti = kv[1]
			"misura": _misura = kv[1] == "si"
			"viaggio": _viaggio = float(kv[1])
			"passi": _passi = int(kv[1])
			"iterazioni": _iterazioni = int(kv[1])
			"distanza": _distanza = float(kv[1])
			"collisore": _collisore = int(kv[1])
	if _misura:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("stoffa_playground: n=%d stoffa=%s clip=%s gira=%s viaggio=%.2f passi=%dx%d distanza=%.0f renderer=%s" % [
		_n, _stoffa, _clip, _gira, _viaggio, _passi, _iterazioni, _distanza,
		ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	_costruisci_mondo()
	for i in _n:
		_aggiungi_mago(i)


func _aggiungi_mago(i : int) -> void:
	var m : Node3D = (load(SCENA_MAGO) as PackedScene).instantiate()
	## In cerchio attorno all'origine, sfasati: con n=1 sta sul giro.
	m.set_meta("fase", TAU * float(i) / float(_n))
	m.set_meta("raggio", GIRO_RAGGIO + float(i % 2) * 1.6)
	## La stoffa la monta il nodo del mago stesso (StoffaSimulata), come in
	## partita: lo si regola PRIMA che il mago entri in scena, perche' i
	## solver nascono nel suo _ready. Con `no` e `maschera` lo si toglie.
	var st : Node3D = m.get_node_or_null("StoffaSimulata")
	if st != null:
		if _stoffa == "si":
			st.set("passi", _passi)
			st.set("iterazioni", _iterazioni)
			st.set("viaggio", _viaggio)
			st.set("distanza_attiva", _distanza)
			st.set("collisore_corpo", _collisore)
		else:
			m.remove_child(st)
			st.free()
	add_child(m)
	_posa(m, 0.0)
	m.set_physics_process(false)
	for n in m.find_children("*", "SkeletonModifier3D", true, false):
		n.set("active", false)
	m._play(_clip, true)
	_maghi.append(m)
	if _stoffa == "maschera":
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for mi in m.find_children("Stoffa*", "MeshInstance3D", true, false):
			mi.material_override = mat


func _process(delta : float) -> void:
	_t += delta
	if _gira:
		for m in _maghi:
			_posa(m, _t)
	_inquadra()
	if _misura and _t > 3.0:
		_frame_tempi.append(delta)
		if _t > 8.0:
			var somma := 0.0
			for d in _frame_tempi:
				somma += d
			var medio := somma / _frame_tempi.size()
			print("MISURA n=%d stoffa=%s: %.2f ms/frame (%.0f fps) su %d frame" % [
				_n, _stoffa, medio * 1000.0, 1.0 / medio, _frame_tempi.size()])
			get_tree().quit(0)
	if _scatti != "" and _t >= _prossimo_scatto:
		_prossimo_scatto += 0.5
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var nome := "%s/stoffa_%03d.png" % [_scatti, int(round(_t * 10.0))]
		img.save_png(nome)
		print("  scatto %s" % nome)
		if _t > 5.0:
			get_tree().quit(0)


## Il mago sul giro: a passo (1 m/s) lungo il cerchio, con la faccia avanti.
func _posa(m : Node3D, t : float) -> void:
	var r : float = m.get_meta("raggio")
	var a : float = m.get_meta("fase") + (t / r if _gira else 0.0)
	m.position = Vector3(cos(a), 0.0, sin(a)) * r
	var avanti := Vector3(-sin(a), 0.0, cos(a))
	m.look_at(m.position - avanti, Vector3.UP)


func _costruisci_mondo() -> void:
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.38)
	env.ambient_light_energy = 0.7
	amb.environment = env
	add_child(amb)
	var luce := DirectionalLight3D.new()
	luce.rotation_degrees = Vector3(-40, -60, 0)
	luce.light_energy = 1.3
	luce.shadow_enabled = true
	add_child(luce)
	var piano := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	piano.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.14, 0.11)
	piano.material_override = m
	add_child(piano)
	## Con un mago solo la camera lo segue di tre quarti; con molti li
	## inquadra tutti dall'alto.
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.set_meta("segui", _n == 1)
	_cam = cam
	_inquadra()


var _cam : Camera3D


func _inquadra() -> void:
	if _cam.get_meta("segui") and not _maghi.is_empty():
		var m := _maghi[0]
		var fianco := m.global_transform.basis.x
		var avanti := m.global_transform.basis.z
		var da := m.position + avanti * 2.6 + fianco * 1.6 + Vector3(0, 1.5, 0)
		_cam.look_at_from_position(da, m.position + Vector3(0, 1.0, 0), Vector3.UP)
	elif not _cam.get_meta("segui"):
		_cam.look_at_from_position(Vector3(0, 9, 11), Vector3(0, 0.8, 0), Vector3.UP)
