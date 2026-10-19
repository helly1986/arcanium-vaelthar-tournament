@tool
extends "res://arcanium/levels/location_builder.gd"
class_name ArenaBuilder

## Costruisce "L'Arena Senza Fuoco" (Prologo) dal kit modulare Trellis 2 migrato
## da Arcanium-Lite, portando l'algoritmo di ArenaScene.js: pavimento 40×40, mura
## perimetrali modulari con portali/breccia/passaggio, 6 coni spenti in cerchio,
## 9 ostacoli (colonne/macerie) a posizioni fisse, 30 detriti sparsi. Piazzamenti
## deterministici (stessi seed di Lite) → arena riproducibile.
##
## @tool: si può rigenerare in editor con la spunta `rebuild`. La geometria viene
## costruita sotto il nodo "Built" così è ispezionabile ma facile da ripulire.
##
## Pulsanti, persistenza del layout e adozione della scena salvata arrivano
## tutti da LocationBuilder (location_builder.gd): qui resta solo il contenuto
## specifico dell'Arena Senza Fuoco.

## ─── Cielo notturno ("Senza Fuoco" = niente sole, solo pallido chiarore) ─────
## Energia dell'ambient-light da cielo (bassa = penombra fredda, non buio totale).
@export_range(0.0, 1.0) var night_ambient_energy : float = 0.12
## Energia della "luce lunare" direzionale debolissima (0 = nessuna).
@export_range(0.0, 0.3) var moonlight_energy : float = 0.06
## Densità del campo stellare (0..1, passata allo shader del cielo).
@export_range(0.0, 1.0) var star_density : float = 0.12

const SIZE := 40.0
const HALF := SIZE / 2.0
const WALL_H := 8.0
const WALL_THICK := 0.9
const ARCHMAGE_H := 1.8
const TOWER_H := ARCHMAGE_H * 6.7   # ~12
const OUT := HALF + WALL_THICK / 2.0
const SEGT := 12.0

const DIR := "res://assets/environment/arena/"

const OBSTACLES := [
	{"x": -5.0, "z": 4.0, "r": 1.0, "h": 1.9},
	{"x": 5.0, "z": -2.0, "r": 1.1, "h": 2.3},
	{"x": -8.0, "z": -5.0, "r": 0.9, "h": 1.6},
	{"x": 8.0, "z": 6.0, "r": 1.0, "h": 2.0},
	{"x": 3.0, "z": 9.0, "r": 0.95, "h": 1.7},
	{"x": -3.0, "z": -9.0, "r": 0.95, "h": 2.1},
	{"x": 0.0, "z": 5.0, "r": 0.85, "h": 1.5},
	{"x": -11.0, "z": 2.0, "r": 1.05, "h": 2.2},
	{"x": 11.0, "z": -6.0, "r": 1.0, "h": 1.8},
]

var _cache : Dictionary = {}   # nome → PackedScene
# LCG deterministico (come ArenaScene.js): stato riscritto da _seed().
var _rng_state : int = 0

func _build_content() -> void:
	_build_floor()
	_build_walls()
	_build_coni()
	_build_obstacles()
	_build_debris()
	_build_collision()
	_build_night_sky()

## ─── RNG deterministico ──────────────────────────────────────────────────────
func _seed(s : int) -> void:
	_rng_state = s

func _rng() -> float:
	_rng_state = (_rng_state * 9301 + 49297) % 233280
	return float(_rng_state) / 233280.0

## ─── Caricamento + scaling dei pezzi (porta spawnModel) ──────────────────────
func _packed(name : String) -> PackedScene:
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".glb")
	return _cache[name]

## Istanzia un pezzo, ne misura l'AABB reale e lo scala/posiziona come Lite.
## mode: "height" (scala uniforme all'altezza), "stretch" (per-asse w/h/d),
##       "width" (rovine basse: x/z per width, y per height).
func _spawn(name : String, opts : Dictionary) -> Node3D:
	var inst : Node3D = _packed(name).instantiate()
	_built.add_child(inst)
	_register(inst, name)
	_set_owner_rec(inst, _owner_target())
	var box := _local_aabb(inst)
	if box.size == Vector3.ZERO:
		box.size = Vector3.ONE

	var scale := Vector3.ONE
	match opts.get("mode", "width"):
		"height":
			var s : float = float(opts["height"]) / box.size.y
			scale = Vector3(s, s, s)
		"stretch":
			scale = Vector3(
				float(opts["width"]) / box.size.x,
				float(opts["height"]) / box.size.y,
				float(opts["depth"]) / box.size.z)
		"uniform":
			# scala UNIFORME sulla base dell'ingombro a terra → niente deformazioni
			# (sassi/detriti restano naturali, non schiacciati/stirati)
			var u : float = float(opts.get("width", 1.0)) / max(box.size.x, box.size.z)
			scale = Vector3(u, u, u)
		_:
			var w : float = float(opts.get("width", 1.0))
			var h : float = float(opts.get("height", w))
			scale = Vector3(w / box.size.x, h / box.size.y, w / box.size.z)

	inst.scale = scale
	inst.rotation.y = float(opts.get("rot_y", 0.0))
	# appoggia la base a y=0
	inst.position = Vector3(
		float(opts.get("x", 0.0)),
		-box.position.y * scale.y,
		float(opts.get("z", 0.0)))

	# Collisione solo per oggetti ALTI (colonne/coni/macerie grosse): bloccano il
	# movimento come i muri. I detriti piccoli restano attraversabili.
	if opts.get("collide", false):
		var world_h : float = box.size.y * scale.y
		if world_h > 1.3:
			# Raggio = semilato PIÙ LARGO della base (l'AABB include il plinto/base
			# svasata: è la parte più larga dell'oggetto). Niente più restringimento a
			# 0.7 + media: il cilindro arriva ai bordi della base allargata, il player
			# non ci cammina sopra. Colonne e coni condividono questa regola.
			var rad : float = maxf(box.size.x * scale.x, box.size.z * scale.z) * 0.5
			_add_cylinder(Vector3(inst.position.x, 0.0, inst.position.z), maxf(0.3, rad), world_h)
	return inst

## Collider cilindrico verticale (per colonne/coni), layer World.
func _add_cylinder(pos_xz : Vector3, radius : float, height : float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(pos_xz.x, height * 0.5, pos_xz.z)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	body.add_child(col)
	body.name = "ColliderPilastro"
	_add(body)
	col.owner = _owner_target()

## AABB unione di tutte le MeshInstance3D del pezzo, nello spazio locale del root.
func _local_aabb(root : Node3D) -> AABB:
	var out := AABB()
	var started := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var rel : Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var a : AABB = rel * mi.mesh.get_aabb()
		if not started:
			out = a
			started = true
		else:
			out = out.merge(a)
	return out

## ─── PAVIMENTO ───────────────────────────────────────────────────────────────
func _build_floor() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(SIZE, SIZE)
	mesh.material = _floor_material()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Floor"
	_add(mi)

## Materiale PBR PATINA (fal.ai) del pavimento, tassellato 6× come in Lite.
func _floor_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tdir := DIR + "textures/"
	mat.albedo_texture = load(tdir + "floor_basecolor.png")
	mat.metallic = 0.0
	var rough : Texture2D = load(tdir + "floor_roughness.png")
	if rough:
		mat.roughness_texture = rough
	var norm : Texture2D = load(tdir + "floor_normal.png")
	if norm:
		mat.normal_enabled = true
		mat.normal_texture = norm
	mat.uv1_scale = Vector3(6, 6, 1)  # ripetizione (repeat=6 in makeFloorMaps)
	# leggera tinta per restare nella palette grigio-freddo dell'arena
	mat.albedo_color = Color(0.82, 0.85, 0.9)
	return mat

## ─── MURI PERIMETRALI MODULARI ───────────────────────────────────────────────
func _build_walls() -> void:
	# lato: along = "x"|"z" (asse lungo cui corre), fixed = coord perpendicolare
	_build_side("x", -OUT, 0.0, [{"name": "arch", "center": 0.0, "gap": 6.5}])          # Nord: portale
	_build_side("x", OUT, PI, [{"name": "wall_breach", "center": -5.0, "gap": 9.0}])    # Sud: breccia
	_build_side("z", OUT, -PI / 2, [{"name": "passage_rubble", "center": 6.0, "gap": 7.0}]) # Est: passaggio ostruito
	_build_side("z", -OUT, PI / 2, [{"name": "arch", "center": -4.0, "gap": 6.5}])      # Ovest: portale

	# pilastri d'angolo
	for c in [[-HALF, -HALF, 0.0], [HALF, -HALF, PI / 2], [HALF, HALF, PI], [-HALF, HALF, -PI / 2]]:
		_spawn("wall_corner", {"mode": "stretch", "width": 4.0, "height": WALL_H, "depth": 4.0,
			"rot_y": c[2], "x": c[0], "z": c[1]})

func _build_side(along : String, fixed : float, face_y : float, openings : Array) -> void:
	var sorted := openings.duplicate()
	sorted.sort_custom(func(a, b): return a["center"] < b["center"])
	var cursor := -OUT
	for o in sorted:
		_fill_span(along, fixed, cursor, o["center"] - o["gap"] / 2.0, face_y)
		cursor = o["center"] + o["gap"] / 2.0
		# incastona l'apertura (portale/breccia/passaggio)
		var pos := _axis_pos(along, o["center"], fixed)
		_spawn(o["name"], {"mode": "height", "height": WALL_H, "rot_y": face_y, "x": pos.x, "z": pos.y})
	_fill_span(along, fixed, cursor, OUT, face_y)

func _fill_span(along : String, fixed : float, a : float, b : float, face_y : float) -> void:
	var length := b - a
	if length <= 0.3:
		return
	var n : int = max(1, int(round(length / SEGT)))
	var w := length / float(n)
	for i in n:
		var c := a + w * (float(i) + 0.5)
		var pos := _axis_pos(along, c, fixed)
		_spawn("wall_straight", {"mode": "stretch", "width": w * 1.04, "height": WALL_H,
			"depth": WALL_THICK, "rot_y": face_y, "x": pos.x, "z": pos.y})

func _axis_pos(along : String, center : float, fixed : float) -> Vector2:
	# ritorna (x, z)
	if along == "x":
		return Vector2(center, fixed)
	return Vector2(fixed, center)

## ─── CONI DI CANALIZZAZIONE (SPENTI) ─────────────────────────────────────────
func _build_coni() -> void:
	var count := 6
	var r := (HALF - 2.2) * 0.82
	for i in count:
		var ang := (float(i) / float(count)) * TAU
		_spawn("cone", {"mode": "height", "height": TOWER_H, "rot_y": -ang + PI,
			"x": cos(ang) * r, "z": sin(ang) * r, "collide": true})

## ─── OSTACOLI (colonne/macerie, posizioni fisse) ─────────────────────────────
func _build_obstacles() -> void:
	_seed(99)
	var variants := [
		{"name": "column", "tower": true},
		{"name": "column_broken", "wk": 2.4, "hk": 1.6},
		{"name": "rubble", "wk": 2.2, "hk": 1.1},
		{"name": "debris_pile", "wk": 2.6, "hk": 0.8},
	]
	for o in OBSTACLES:
		var v : Dictionary = variants[int(_rng() * variants.size())]
		var rot_y := _rng() * TAU
		var opts : Dictionary
		if v.get("tower", false):
			opts = {"mode": "height", "height": TOWER_H}
		else:
			# uniforme (non più per-asse): niente rovine schiacciate/stirate
			opts = {"mode": "uniform", "width": o["r"] * float(v["wk"])}
		opts["rot_y"] = rot_y
		opts["x"] = o["x"]
		opts["z"] = o["z"]
		opts["collide"] = true   # gli alti bloccano; i bassi (<1.3m) passano
		var inst := _spawn(v["name"], opts)
		## COLONNE INTERE = DISTRUTTIBILI. Solo quelle: le macerie e i cumuli
		## sono GIÀ rotti, e romperli una seconda volta non racconta niente.
		## Una colonna che viene giù sotto una palla d'energia del Senza Nome
		## invece cambia l'arena mentre ci combatti dentro, ed è la sola cosa qui
		## che possa farlo.
		if v["name"] == "column":
			OggettoDistruttibile.applica(inst, {
				"salute": 55.0,
				"pezzi": 8,
				"tinta_suolo": SchiantoATerra.PIETRA_ARENA,
			})

## ─── DETRITI SPARSI ──────────────────────────────────────────────────────────
func _build_debris() -> void:
	_seed(42)
	for i in 30:
		var r := 5.0 + _rng() * (HALF - 7.0)
		var ang := _rng() * TAU
		# scatter a terra = sassi naturali (le lastre piatte 'debris_pile' restano
		# solo tra gli ostacoli grandi, dove leggono bene). Roll mantenuto per
		# non alterare la sequenza deterministica delle posizioni.
		var big := _rng() > 0.78
		var s := (0.6 + _rng() * 0.5) if big else (0.3 + _rng() * 0.45)
		var rot_y := _rng() * PI
		var inst := _spawn("rock",
			{"mode": "uniform", "width": s,
			"rot_y": rot_y, "x": cos(ang) * r, "z": sin(ang) * r})
		inst.rotation.x = _rng() * PI
		inst.rotation.z = _rng() * PI * 0.5

## ─── COLLISIONE (pavimento + perimetro) ──────────────────────────────────────
## Prima passata: player cammina e resta chiuso. Collisione per-colonna: TODO.
func _build_collision() -> void:
	_static_box(Vector3(0, -0.2, 0), Vector3(SIZE, 0.4, SIZE), "FloorCol")
	_static_box(Vector3(0, WALL_H / 2, -OUT), Vector3(SIZE + 2, WALL_H, WALL_THICK), "WallN")
	_static_box(Vector3(0, WALL_H / 2, OUT), Vector3(SIZE + 2, WALL_H, WALL_THICK), "WallS")
	_static_box(Vector3(OUT, WALL_H / 2, 0), Vector3(WALL_THICK, WALL_H, SIZE + 2), "WallE")
	_static_box(Vector3(-OUT, WALL_H / 2, 0), Vector3(WALL_THICK, WALL_H, SIZE + 2), "WallW")

func _static_box(pos : Vector3, size : Vector3, name : String) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	_add(body)
	col.owner = _owner_target()

## ─── CIELO NOTTURNO ("Senza Fuoco": niente sole, solo pallido chiarore) ──────
## Via codice (niente edit di .tscn): riusa un WorldEnvironment/"MoonLight" già
## presenti come figli diretti del root, altrimenti li crea sotto "Built".
## Sky = shader procedurale (gradiente blu-notte + campo di stelle, vedi
## night_sky.gdshader). Ambient-light da cielo con energia bassa: le stelle
## danno una luce fioca e fredda invece del buio piatto.
func _build_night_sky() -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		_add(world_env, false)

	var env := world_env.environment
	if env == null:
		env = Environment.new()
		world_env.environment = env

	if env.sky == null:
		env.sky = Sky.new()
	var shader_mat := env.sky.sky_material as ShaderMaterial
	if shader_mat == null:
		shader_mat = ShaderMaterial.new()
		env.sky.sky_material = shader_mat
	var shader := load("res://arcanium/levels/night_sky.gdshader") as Shader
	if shader_mat.shader != shader:
		shader_mat.shader = shader
	shader_mat.set_shader_parameter("star_density", star_density)

	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = night_ambient_energy
	env.ambient_light_color = Color(0.55, 0.65, 0.85)   # pallido blu-notte
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	## ⚠️ GLOW DELIBERATAMENTE NON ABILITATO — verificato a schermo 2026-07-27.
	## Tentazione naturale: i materiali VFX spingono il colore sopra 1.0 per
	## "accendersi" (vedi BossVFX.particle_material) e senza glow quel surplus
	## viene solo tagliato dal tonemapper. MA il kit modulare dell'arena è a
	## albedo CHIARO e la KeyLight sta a 2.2: con glow additivo e soglia HDR 1.0
	## fiorisce METÀ DEL SET, non i VFX — l'intera arena diventa una lastra
	## bianca e le silhouette dei nemici spariscono. Screenshot iso di confronto
	## fatti: senza glow la scena è nettamente più leggibile.
	## Se un giorno si vorrà il bloom, il prerequisito è ABBASSARE l'albedo del
	## kit (o alzare glow_hdr_threshold ben sopra 1.0), non aggiungere glow qui.

	# "Luce lunare": direzionale debolissima e azzurrina, angolata dall'alto
	# come se filtrasse dai coni spenti verso il basso. Niente sole.
	var moon := get_node_or_null("MoonLight") as DirectionalLight3D
	if moon == null:
		moon = DirectionalLight3D.new()
		moon.name = "MoonLight"
		_add(moon, false)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = moonlight_energy
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
