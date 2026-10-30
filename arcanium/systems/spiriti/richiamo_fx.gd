extends Node3D

## ⚠️ Niente `class_name`: si usa con `preload`.

## ═══════════════════════════════════════════════════════════════════════════
## RICHIAMO DELLE ECO — l'energia che il Mago tira su dal suolo
## ═══════════════════════════════════════════════════════════════════════════
##
## Il disegno della mossa RICHIAMO del Mago (arcanium_mago_enemy.gd), sul gesto
## di `spell/spell_richiamo_01` (arcanium/animazioni/mago/richiamo.py): china
## il capo come a sentire chi c'e' sotto, poi le braccia salgono «come a tirare
## su qualcosa di pesante» e restano alzate un istante di troppo. Segue il
## TEMPO DELLA CLIP, che gli passa il mago a ogni frame (`aggiorna`), come
## radici_fx.gd.
##
##   ASCOLTO  (0,45 -> 1,15 s) — sotto i suoi piedi si accende la terra, e da
##                               li' un FILO di luce per ogni Eco striscia
##                               radente al suolo fino al suo cerchio.
##   TIRA SU  (1,15 -> 2,13 s) — i fili si staccano da terra e la loro cima
##                               sale con le mani: l'energia ora corre DAL
##                               SUOLO ALLE MANI, dove si accende una fiamma
##                               irregolare che tira a se' scintille. Dai suoi
##                               piedi salgono faville a spirale.
##   TROPPO   (2,13 -> CONTATTO) — tutto in tensione: i fili tremano, il
##                               flusso accelera, le fiamme pulsano.
##   CONTATTO (2,83 s)           — i fili si scaricano nel suolo dalla mano al
##                               cerchio, le fiamme scoppiano in scintille, a
##                               ogni cerchio un'onda: le Eco AFFIORANO dalla
##                               terra (`affiora`, la chiama il mago).
##
## Il filo e' un nastro rifatto a ogni frame, sempre di faccia alla camera,
## con uno shader che ne fa un'energia viva: nucleo che serpeggia, alone,
## impulsi e granelli che SCORRONO lungo il filo nel verso dell'energia.
##
## Vive nel livello (top_level), si libera da sola a fine scarica.

const EcoFx := preload("res://arcanium/systems/spiriti/eco_fx.gd")

const ASCOLTO := 0.45
const TIRA := 1.15
const ALTO := 2.13
## Quanti tratti ha un filo.
const TRATTI := 32

var colore : Color = Color(0.62, 0.32, 1.0)
## Dove escono le Eco: i centri dei cerchi gia' segnati dal mago.
var punti : Array[Vector3] = []
## Il secondo di clip del contatto (le Eco escono).
var contatto : float = 2.83

var _scheletro : Skeleton3D
var _mani : Array[int] = []
## I piedi del mago, a terra, fissati alla prima chiamata.
var _piedi := Vector3.ZERO
var _fili : Array[Dictionary] = []
var _fiamme : Array[MeshInstance3D] = []
var _scintille : Array[GPUParticles3D] = []
var _terra : Decal
var _faville : GPUParticles3D
var _luce : OmniLight3D
var _pronto := false
var _scaricato := false
var _spento := false


func prepara(scheletro : Skeleton3D, mano_sx : String, mano_dx : String, luce : Color) -> void:
	_scheletro = scheletro
	colore = luce
	_mani = [scheletro.find_bone(mano_sx), scheletro.find_bone(mano_dx)]


func _ready() -> void:
	top_level = true
	## Il velo venato, non l'anello: un anello qui si leggeva come un quarto
	## cerchio d'avviso, come se un'Eco uscisse sotto di lui (render).
	_terra = EcoFx._decal(EcoFx._tex_disco(colore, randi() % EcoFx.VARIANTI), 0.95, colore, 0.0)
	## Basso: alto 3 m come i cerchi tingeva di viola la veste del mago.
	_terra.size.y = 0.5
	_terra.rotation.y = randf() * TAU
	add_child(_terra)
	_faville = _crea_faville()
	add_child(_faville)
	for k in 2:
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		f.mesh = q
		f.material_override = _materiale_fiamma(colore, randf() * 10.0)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.scale = Vector3.ONE * 0.01
		add_child(f)
		_fiamme.append(f)
		var s := _crea_scintille()
		add_child(s)
		_scintille.append(s)
	_luce = OmniLight3D.new()
	_luce.light_color = colore
	_luce.light_energy = 0.0
	_luce.omni_range = 3.0
	_luce.shadow_enabled = false
	add_child(_luce)


## Ogni frame dal mago, col secondo di clip.
func aggiorna(t : float) -> void:
	if _spento or _scaricato or _scheletro == null or not is_instance_valid(_scheletro) or _mani.has(-1):
		return
	var mani : Array[Vector3] = []
	for b in _mani:
		mani.append(_scheletro.global_transform * _scheletro.get_bone_global_pose(b).origin)
	if not _pronto:
		_prepara_fili(mani)
	var cam := get_viewport().get_camera_3d()
	var occhio := cam.global_position if cam != null else _piedi + Vector3(0, 10, 10)

	## Le tre grandezze del gesto, tutte 0..1 e morbide.
	var ascolto := _morbido((t - ASCOLTO) / (TIRA - ASCOLTO))
	var tira := _morbido((t - TIRA) / (ALTO - TIRA))
	var troppo := _morbido((t - ALTO) / maxf(contatto - ALTO, 0.05))
	var trema := troppo * (0.6 + 0.4 * sin(t * 47.0))

	## La terra sotto i piedi: si accende ascoltando, pulsa in tensione.
	_terra.global_position = _piedi
	_faville.global_position = _piedi
	_terra.emission_energy = ascolto * (1.6 + 1.0 * tira) + trema * 0.8
	_terra.modulate.a = ascolto
	_faville.emitting = tira > 0.05

	for f in _fili:
		var mano : Vector3 = mani[f["mano"]]
		var cima := _piedi.lerp(mano, tira)
		_disegna(f, cima, tira, troppo, t, occhio)
		var m : ShaderMaterial = f["mat"]
		## Ascoltando il filo cresce dal mago verso il cerchio; tirando su
		## l'energia gira e corre dal suolo alle mani, sempre piu' in fretta.
		m.set_shader_parameter("finestra", Vector2(1.0 - ascolto, 1.0))
		m.set_shader_parameter("scorre", lerpf(-1.4, 1.6, tira) + troppo * 2.2)
		m.set_shader_parameter("alfa", ascolto * (0.75 + 0.35 * tira + 0.5 * trema))

	for k in 2:
		var carica := tira * (1.0 + 0.35 * troppo)
		var fiamma := _fiamme[k]
		fiamma.global_position = mani[k]
		fiamma.scale = Vector3.ONE * maxf(lerpf(0.05, 0.55, carica) * (1.0 + 0.15 * trema), 0.01)
		(fiamma.material_override as ShaderMaterial).set_shader_parameter("alfa", tira * (0.9 + 0.4 * trema))
		_scintille[k].global_position = mani[k]
		_scintille[k].emitting = tira > 0.15
	_luce.global_position = (mani[0] + mani[1]) * 0.5
	_luce.light_energy = tira * 1.8 + trema * 0.8

	if t >= contatto:
		_scarica(mani)


## I fili, uno per Eco, ognuno legato alla mano dal suo lato; e il percorso a
## terra (il suolo letto una volta sola: da li' in poi i capi non si muovono).
func _prepara_fili(mani : Array[Vector3]) -> void:
	_pronto = true
	var bacino := (mani[0] + mani[1]) * 0.5
	_piedi = Vector3(bacino.x, _suolo(bacino), bacino.z)
	for p in punti:
		var giu := Vector3(p.x, _suolo(p), p.z)
		var mano := 0 if giu.distance_to(mani[0]) < giu.distance_to(mani[1]) else 1
		## La vena a terra serpeggia: uno scarto laterale a onda, nullo ai capi.
		var dir := _piedi - giu
		dir.y = 0.0
		var lato := Vector3(dir.z, 0.0, -dir.x).normalized() if dir.length() > 0.01 else Vector3.RIGHT
		var fase := randf() * TAU
		var terra : Array[Vector3] = []
		for i in TRATTI + 1:
			var s := float(i) / float(TRATTI)
			var q := giu.lerp(_piedi, s) + lato * sin(s * PI * 2.6 + fase) * 0.35 * sin(s * PI)
			q.y = _suolo(q)
			terra.append(q)
		var mi := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		mi.mesh = im
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _materiale_filo(colore)
		mi.material_override = mat
		add_child(mi)
		_fili.append({"mesh": im, "mat": mat, "terra": terra, "giu": giu, "mano": mano,
			"fase": fase, "lato": lato})


## Il nastro del filo: dalla terra (s=0, il cerchio) alla cima (s=1, la mano).
## A terra segue la vena; tirando su si stacca e s'inarca verso la mano.
func _disegna(f : Dictionary, cima : Vector3, tira : float, troppo : float, t : float, occhio : Vector3) -> void:
	var terra : Array[Vector3] = f["terra"]
	var giu : Vector3 = f["giu"]
	var lato : Vector3 = f["lato"]
	var fase : float = f["fase"]
	## La curva in aria: sale dritta dal cerchio, poi piega verso la mano.
	var c1 := giu + Vector3.UP * (1.4 + cima.y - giu.y) * 0.55
	var c2 := cima + (giu - cima) * 0.35 + Vector3.UP * 0.6
	var curva : Array[Vector3] = []
	var lungo := 0.0
	for i in TRATTI + 1:
		var s := float(i) / float(TRATTI)
		var aria := _bezier(giu, c1, c2, cima, s)
		var p : Vector3 = terra[i].lerp(aria, tira)
		## L'ondeggio lento del filo, e il tremito dell'istante di troppo.
		var onda := sin(s * PI)
		p += lato * onda * (sin(t * 2.3 + s * 5.0 + fase) * 0.12 * tira + sin(t * 39.0 + s * 23.0 + fase) * 0.05 * troppo)
		p.y += onda * sin(t * 3.1 + s * 7.0 + fase) * 0.08 * tira
		if i > 0:
			lungo += p.distance_to(curva[i - 1])
		curva.append(p)
	(f["mat"] as ShaderMaterial).set_shader_parameter("lunghezza", lungo)

	var im : ImmediateMesh = f["mesh"]
	im.clear_surfaces()
	## Due nastri: il filo, e un TREFOLO sottile che gli gira attorno a
	## spirale (un tubo solo sembrava un neon).
	for trefolo in 2:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in TRATTI + 1:
			var s := float(i) / float(TRATTI)
			var p := curva[i]
			var tang := (curva[mini(i + 1, TRATTI)] - curva[maxi(i - 1, 0)]).normalized()
			var verso := tang.cross(occhio - p).normalized()
			## Piu' largo in mezzo, sottile ai capi; a terra un po' piu' largo.
			var largo := (0.09 + 0.07 * sin(s * PI)) * lerpf(1.25, 1.0, tira)
			if trefolo == 1:
				var giro := s * TAU * 3.0 - t * 5.0 + fase
				var fuori := verso.cross(tang).normalized()
				p += (verso * sin(giro) + fuori * cos(giro)) * 0.13 * sin(s * PI) * (0.4 + 0.6 * tira)
				largo *= 0.35
			im.surface_set_uv(Vector2(s, 0.0))
			im.surface_add_vertex(p - verso * largo)
			im.surface_set_uv(Vector2(s, 1.0))
			im.surface_add_vertex(p + verso * largo)
		im.surface_end()


## Il contatto: l'energia torna giu' nel suolo, dalla mano al cerchio.
func _scarica(mani : Array[Vector3]) -> void:
	_scaricato = true
	_faville.emitting = false
	for k in 2:
		_scintille[k].emitting = false
		_scoppio(mani[k])
		var fiamma := _fiamme[k]
		var tw := create_tween().set_parallel(true)
		tw.tween_property(fiamma, "scale", fiamma.scale * 1.8, 0.18).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v : float): (fiamma.material_override as ShaderMaterial).set_shader_parameter("alfa", v), 1.4, 0.0, 0.3)
	for f in _fili:
		var m : ShaderMaterial = f["mat"]
		m.set_shader_parameter("scorre", -7.0)
		var tw := create_tween()
		tw.tween_method(func(v : float):
			m.set_shader_parameter("finestra", Vector2(0.0, v))
			m.set_shader_parameter("alfa", 1.6 * (0.4 + 0.6 * v)), 1.0, 0.0, 0.22).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): _onda(f["giu"]))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_luce, "light_energy", 0.0, 0.5)
	tw.tween_property(_terra, "emission_energy", 0.0, 0.6)
	tw.tween_property(_terra, "albedo_mix", 0.0, 0.6)
	get_tree().create_timer(1.6).timeout.connect(queue_free)


## L'onda dove l'energia arriva: un anello irregolare che si allarga e si spegne.
func _onda(terra : Vector3) -> void:
	var anello := EcoFx._decal(EcoFx._tex_anello(colore, randi() % EcoFx.VARIANTI), 0.5, colore, 3.0)
	anello.rotation.y = randf() * TAU
	add_child(anello)
	anello.global_position = terra
	var tw := create_tween().set_parallel(true)
	tw.tween_property(anello, "size", Vector3(3.2, 3.0, 3.2), 0.5).set_ease(Tween.EASE_OUT)
	## Si spegne l'emissione e l'albedo: `modulate` non tocca l'emissione.
	tw.tween_property(anello, "emission_energy", 0.0, 0.55)
	tw.tween_property(anello, "albedo_mix", 0.0, 0.55)


## La fiamma della mano che scoppia: scintille che schizzano e ricadono.
func _scoppio(dove : Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.4
	pm.scale_max = 1.1
	pm.color_ramp = _rampa(0.0)
	p.process_material = pm
	p.draw_pass_1 = _goccia(0.07)
	add_child(p)
	p.global_position = dove
	p.emitting = true


## Le faville che salgono a spirale dai suoi piedi verso le mani.
func _crea_faville() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 56
	p.lifetime = 1.3
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.9
	pm.emission_ring_inner_radius = 0.5
	pm.emission_ring_height = 0.05
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3.ZERO
	pm.tangential_accel_min = 2.0
	pm.tangential_accel_max = 3.5
	pm.radial_accel_min = -0.9
	pm.radial_accel_max = -0.4
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color_ramp = _rampa(0.25)
	p.process_material = pm
	p.draw_pass_1 = _goccia(0.08)
	return p


## Le scintille che la mano tira a se' (come la sfera delle radici).
func _crea_scintille() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 36
	p.lifetime = 0.5
	p.local_coords = true
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 0.5
	pm.gravity = Vector3.ZERO
	pm.radial_accel_min = -6.0
	pm.radial_accel_max = -3.5
	pm.tangential_accel_min = -1.5
	pm.tangential_accel_max = 1.5
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = _rampa(0.3)
	p.process_material = pm
	p.draw_pass_1 = _goccia(0.05)
	return p


func _rampa(picco : float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0 if picco > 0.0 else 1.0))
	if picco > 0.0:
		g.add_point(picco, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _goccia(lato : float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(lato, lato)
	var m := EcoFx._materiale_luce(colore)
	m.set_shader_parameter("tondo", true)
	q.material = m
	return q


## La quota del suolo sotto `p`: un raggio verso il basso, o la quota di `p`.
func _suolo(p : Vector3) -> float:
	var spazio := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 4.0, 1)
	var r := spazio.intersect_ray(q)
	return (r.position.y if not r.is_empty() else p.y) + 0.05


static func _bezier(a : Vector3, b : Vector3, c : Vector3, d : Vector3, s : float) -> Vector3:
	var u := 1.0 - s
	return a * u * u * u + b * 3.0 * u * u * s + c * 3.0 * u * s * s + d * s * s * s


static func _morbido(x : float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Interruzione (colpo subito, morte): prima della scarica tutto si spegne in
## fretta; dopo, la scarica finisce da sola.
func spegni() -> void:
	if _spento or _scaricato:
		return
	_spento = true
	_faville.emitting = false
	for s in _scintille:
		s.emitting = false
	var tw := create_tween().set_parallel(true)
	for f in _fili:
		var m : ShaderMaterial = f["mat"]
		tw.tween_method(func(v : float): m.set_shader_parameter("alfa", v), 0.8, 0.0, 0.2)
	for fiamma in _fiamme:
		tw.tween_property(fiamma, "scale", Vector3.ONE * 0.01, 0.2)
	tw.tween_property(_luce, "light_energy", 0.0, 0.2)
	tw.tween_property(_terra, "emission_energy", 0.0, 0.2)
	tw.tween_property(_terra, "albedo_mix", 0.0, 0.2)
	tw.chain().tween_callback(queue_free)


## ─── L'Eco che affiora ──────────────────────────────────────────────────────
## Chiamata dal mago su ogni Eco appena evocata: sale dal suolo, la testa per
## prima (il `dissolvi` del corpo di spirito scopre dall'alto in basso), ferma
## finche' non e' fuori.
static func affiora(eco : Node3D, durata : float = 0.9) -> void:
	var corpo = eco.get("model")
	if corpo == null or not ("immersione" in corpo):
		return
	eco.set_physics_process(false)
	corpo.immersione = 1.3
	corpo.dissolvi = 0.85
	corpo.bagliore = 1.0
	var tw := eco.create_tween().set_parallel(true)
	tw.tween_property(corpo, "immersione", 0.0, durata).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(corpo, "dissolvi", 0.0, durata * 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(corpo, "bagliore", 0.1, durata * 1.4)
	tw.chain().tween_callback(func(): eco.set_physics_process(true))


## ─── Materiali ──────────────────────────────────────────────────────────────
static var _sh_filo : Shader
static var _sh_fiamma : Shader
static var _rumore : NoiseTexture2D


static func _tex_rumore() -> NoiseTexture2D:
	if _rumore == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.02
		n.fractal_octaves = 3
		_rumore = NoiseTexture2D.new()
		_rumore.noise = n
		_rumore.seamless = true
		_rumore.width = 256
		_rumore.height = 256
	return _rumore


## Il filo: UV.x lungo il filo (0 il cerchio, 1 la mano), UV.y di traverso.
## Tre strati: l'alone largo, il nucleo che serpeggia, i granelli; impulsi e
## granelli scorrono di `scorre` (verso la mano se positivo). `finestra` e'
## il tratto visibile, con i capi sfumati.
static func _materiale_filo(c : Color) -> ShaderMaterial:
	if _sh_filo == null:
		_sh_filo = Shader.new()
		_sh_filo.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
uniform vec4 colore : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float alfa = 1.0;
uniform float scorre = 1.0;
uniform float lunghezza = 5.0;
uniform vec2 finestra = vec2(0.0, 1.0);
uniform sampler2D rumore : repeat_enable, filter_linear_mipmap;
void fragment() {
	float u = UV.x;
	float v = UV.y * 2.0 - 1.0;
	float l = u * lunghezza;
	// Il nucleo serpeggia dentro il nastro.
	float scarto = (texture(rumore, vec2(l * 0.09 - TIME * 0.25, 0.31)).r - 0.5) * 1.1;
	float d = abs(v - scarto);
	float nucleo = exp(-d * d * 55.0);
	float alone = exp(-v * v * 3.0) * 0.35;
	// Gli impulsi che corrono lungo il filo.
	float impulso = smoothstep(0.45, 0.8, texture(rumore, vec2(l * 0.12 - TIME * scorre * 0.35, 0.67)).r);
	// I granelli: punti fini, piu' veloci degli impulsi.
	float grano = smoothstep(0.72, 0.8, texture(rumore, vec2(l * 0.7 - TIME * scorre * 0.6, v * 0.35 + 0.5)).r) * (1.0 - d);
	// La luce che cala e risale lungo il filo: niente tubo al neon.
	float acceso = 0.45 + 0.55 * texture(rumore, vec2(l * 0.05 + 0.5, 0.9)).r * 1.6;
	float dentro = smoothstep(finestra.x - 0.02, finestra.x + 0.04, u) * (1.0 - smoothstep(finestra.y - 0.04, finestra.y + 0.001, u));
	float capi = smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.96, 1.0, u) * 0.6);
	float a = (alone * (0.5 + impulso) + nucleo * (0.55 + 1.3 * impulso) * acceso + grano * 0.9) * dentro * capi * alfa;
	ALBEDO = mix(colore.rgb, vec3(1.0), clamp(nucleo * impulso * 0.7, 0.0, 1.0)) * 1.8;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _sh_filo
	m.set_shader_parameter("colore", c)
	m.set_shader_parameter("rumore", _tex_rumore())
	return m


## La fiamma della mano: un quad di faccia alla camera, con il bordo
## irregolare che si muove (rumore letto su una circonferenza), un alone, un
## cuore bianco e lingue che salgono.
static func _materiale_fiamma(c : Color, seme : float) -> ShaderMaterial:
	if _sh_fiamma == null:
		_sh_fiamma = Shader.new()
		_sh_fiamma.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
uniform vec4 colore : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float alfa = 1.0;
uniform float seme = 0.0;
uniform sampler2D rumore : repeat_enable, filter_linear_mipmap;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1].xyz);
}
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	c.y = -c.y;
	// Le lingue salgono: in alto la forma si allunga.
	vec2 q = vec2(c.x, c.y - max(c.y, 0.0) * 0.35);
	float r = length(q);
	vec2 giro = q / max(r, 0.0001);
	float bordo = texture(rumore, giro * 0.18 + vec2(seme, TIME * 0.22)).r;
	float orlo = 0.32 + 0.45 * bordo;
	float corpo = 1.0 - smoothstep(orlo * 0.55, orlo, r);
	float alone = exp(-r * r * 4.5) * 0.4;
	float cuore = exp(-r * r * 45.0);
	float ang = atan(q.y, q.x) / 6.2831;
	float lingue = pow(texture(rumore, vec2(ang * 2.0 + seme, r * 0.8 - TIME * 0.7)).r, 3.0) * 2.4 * (1.0 - smoothstep(0.15, 0.95, r));
	float a = (corpo * 0.5 + alone + cuore * 1.2 + lingue * 0.7) * alfa;
	ALBEDO = mix(colore.rgb, vec3(1.0), clamp(cuore + corpo * 0.15, 0.0, 1.0)) * 1.8;
	ALPHA = clamp(a, 0.0, 1.0) * (1.0 - smoothstep(0.9, 1.0, length(c)));
}
"""
	var m := ShaderMaterial.new()
	m.shader = _sh_fiamma
	m.set_shader_parameter("colore", c)
	m.set_shader_parameter("seme", seme)
	m.set_shader_parameter("rumore", _tex_rumore())
	return m
