extends RefCounted

## ⚠️ Niente `class_name`: si usa con `preload`.

## ═══════════════════════════════════════════════════════════════════════════
## GLI EFFETTI DELL'ECO RADICATA — per chi la combatte e per chi la evoca
## ═══════════════════════════════════════════════════════════════════════════
##
## Tre effetti, ognuno e' la LETTURA di una mossa (vedi eco_clip.gd):
##
##   artigli — tre graffi di luce ricurvi davanti all'Eco, che si spengono in
##             un quarto di secondo: dice DOVE e' passato il colpo.
##   radice  — un cerchio a terra che si riempie (l'avviso: e' li' che uscira'),
##             poi la radice che ESPLODE dal suolo e si ritira. Il cerchio e'
##             l'unica cosa che rende la mossa schivabile: e' fatto per leggersi
##             dall'isometrica, largo e con il bordo pieno.
##   sorso   — scintille che corrono dal petto di chi viene bevuto al cappuccio
##             dell'Eco: il giocatore deve VEDERE che l'Arcanium se ne va.
##
## Tutti vivono nel livello (non sotto l'Eco) e si liberano da soli.

const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")
const SPIRITO := "res://arcanium/systems/spiriti/corpo_spirito.gd"


## ─── Artigli ────────────────────────────────────────────────────────────────
static func artigli(genitore : Node, davanti : Transform3D, colore : Color) -> void:
	var n := Node3D.new()
	n.name = "ArtigliEtere"
	genitore.add_child(n)
	n.global_transform = davanti
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _materiale_luce(colore)
	n.add_child(mi)
	## Tre archi obliqui, dall'alto a sinistra al basso a destra, ognuno una
	## striscia che si assottiglia alle punte.
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var dx : float = (float(k) - 1.0) * 0.22
		var punti := []
		for i in 13:
			var t : float = float(i) / 12.0
			var ang : float = lerpf(-1.0, 1.0, t)
			punti.append(Vector3(dx + sin(ang) * 0.75, 1.35 - t * 0.9 + dx * 0.4, 0.8 + cos(ang) * 0.35))
		for i in 12:
			var a : Vector3 = punti[i]
			var b : Vector3 = punti[i + 1]
			var w0 : float = sin(PI * float(i) / 12.0) * 0.06
			var w1 : float = sin(PI * float(i + 1) / 12.0) * 0.06
			var su := Vector3(0.0, 0.0, 1.0)
			_quad(im, a - su * w0, a + su * w0, b + su * w1, b - su * w1, colore)
	im.surface_end()
	var tw := n.create_tween()
	tw.tween_method(func(v : float): (mi.material_override as ShaderMaterial).set_shader_parameter("alfa", v), 1.0, 0.0, 0.28)
	tw.tween_callback(n.queue_free)


## ─── Radice che afferra ─────────────────────────────────────────────────────
## Mette l'avviso a terra in `punto` e, dopo `avviso` secondi, fa esplodere la
## radice. `raggio` e' quello del danno: il cerchio lo disegna uguale.
static func radice(genitore : Node, punto : Vector3, raggio : float, avviso : float, colore : Color) -> Node3D:
	var n := Node3D.new()
	n.name = "RadiceCheAfferra"
	genitore.add_child(n)
	n.global_position = punto + Vector3(0.0, 0.03, 0.0)

	## ⚠️ DECAL, non un quad piatto: il terreno di Kalvorn non e' piano, e il
	## quad lo tagliava a meta' (una lastra viola mezza sepolta, vista a render).
	## Il Decal si proietta sul suolo com'e'. Due strati: l'ANELLO, pieno da
	## subito (dice DOVE), e il DISCO che si allarga dal centro fino al bordo
	## (dice QUANDO).
	## Ogni cerchio ha il suo bordo irregolare e le sue venature (una delle
	## VARIANTI, girata a caso): un anello perfetto a compasso «era brutto»
	## (l'utente, 2026-10-28).
	var variante := randi() % VARIANTI
	var anello := _decal(_tex_anello(colore, variante), raggio, colore, 1.3)
	anello.rotation.y = randf() * TAU
	n.add_child(anello)
	var disco := _decal(_tex_disco(colore, variante), raggio, colore, 1.0)
	disco.size = Vector3(0.01, 3.0, 0.01)
	disco.rotation.y = anello.rotation.y
	n.add_child(disco)
	var spore := _spore(raggio, colore)
	n.add_child(spore)

	var tw := n.create_tween()
	tw.tween_method(func(v : float): disco.size = Vector3(raggio * 2.0 * v, 3.0, raggio * 2.0 * v), 0.05, 1.0, avviso)
	tw.tween_callback(func():
		spore.emitting = false
		_erutta(n, raggio, colore))
	tw.tween_method(func(v : float):
		anello.modulate.a = v
		disco.modulate.a = v, 1.0, 0.0, 0.5)
	tw.tween_interval(0.6)
	tw.tween_callback(n.queue_free)
	return n


static func _erutta(n : Node3D, raggio : float, colore : Color) -> void:
	var radice := MeshInstance3D.new()
	radice.mesh = _mesh_radice()
	var mr := StandardMaterial3D.new()
	mr.albedo_color = Color(0.16, 0.12, 0.09)
	mr.roughness = 0.9
	mr.rim_enabled = true
	mr.emission_enabled = true
	mr.emission = colore
	mr.emission_energy_multiplier = 1.4
	radice.material_override = mr
	radice.scale = Vector3(1.0, 0.01, 1.0)
	radice.rotation.y = randf() * TAU
	n.add_child(radice)
	## Su di scatto, un attimo in piedi, giu' lenta.
	var tw := radice.create_tween()
	tw.tween_property(radice, "scale", Vector3(1.0, 1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.45)
	tw.tween_property(radice, "scale", Vector3(0.6, 0.01, 0.6), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	## Zolle e schegge che saltano.
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 28
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -14, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = raggio * 0.4
	var zm := BoxMesh.new()
	zm.size = Vector3(0.08, 0.08, 0.08)
	var mz := StandardMaterial3D.new()
	mz.albedo_color = Color(0.18, 0.14, 0.1)
	zm.material = mz
	p.mesh = zm
	n.add_child(p)


static var _cache_radice : ArrayMesh


## Una radice attorcigliata: un cono a spirale di anelli, con la punta che si
## piega. Fatta una volta, condivisa.
static func _mesh_radice() -> ArrayMesh:
	if _cache_radice != null:
		return _cache_radice
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anelli := 14
	var lati := 7
	var alto := 1.7
	var centri := []
	for i in anelli + 1:
		var t := float(i) / float(anelli)
		centri.append(Vector3(sin(t * 5.0) * 0.12 * t, t * alto, cos(t * 4.0) * 0.1 * t + t * t * 0.35))
	for i in anelli:
		var t0 := float(i) / float(anelli)
		var t1 := float(i + 1) / float(anelli)
		var r0 := lerpf(0.26, 0.02, t0)
		var r1 := lerpf(0.26, 0.02, t1)
		for j in lati:
			var a0 := TAU * float(j) / float(lati) + t0 * 2.0
			var a1 := TAU * float(j + 1) / float(lati) + t0 * 2.0
			var b0 := TAU * float(j) / float(lati) + t1 * 2.0
			var b1 := TAU * float(j + 1) / float(lati) + t1 * 2.0
			var p00 : Vector3 = centri[i] + Vector3(cos(a0), 0, sin(a0)) * r0
			var p01 : Vector3 = centri[i] + Vector3(cos(a1), 0, sin(a1)) * r0
			var p10 : Vector3 = centri[i + 1] + Vector3(cos(b0), 0, sin(b0)) * r1
			var p11 : Vector3 = centri[i + 1] + Vector3(cos(b1), 0, sin(b1)) * r1
			for v in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(v)
	st.generate_normals()
	_cache_radice = st.commit()
	return _cache_radice


static func _decal(tex : Texture2D, raggio : float, colore : Color, luce : float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.texture_emission = tex
	## Il colore e' CUOCIUTO nella texture: `modulate` tinge l'albedo ma non
	## l'emissione, e il cerchio usciva bianco.
	d.modulate = Color.WHITE
	d.emission_energy = luce
	d.size = Vector3(raggio * 2.0, 3.0, raggio * 2.0)
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	## ⚠️ Nessun `cull_mask`: sono layer di RENDER, e terreno e giocatore stanno
	## sullo stesso. Il cerchio che tinge le gambe di chi ci sta dentro, del
	## resto, e' l'avviso giusto.
	return d


static var _cache_tex := {}


## Quante forme diverse di cerchio: si sceglie a caso, e si gira.
const VARIANTI := 4


static func _tex_anello(colore : Color, variante : int = 0) -> ImageTexture:
	var k := "anello_%s_%d" % [colore.to_html(), variante]
	if not _cache_tex.has(k):
		_cache_tex[k] = _tex_cerchio(colore, variante, false)
	return _cache_tex[k]


static func _tex_disco(colore : Color, variante : int = 0) -> ImageTexture:
	var k := "disco_%s_%d" % [colore.to_html(), variante]
	if not _cache_tex.has(k):
		_cache_tex[k] = _tex_cerchio(colore, variante, true)
	return _cache_tex[k]


## Il cerchio delle radici, procedurale. Il BORDO e' a raggio variabile con
## l'angolo (rumore letto su una circonferenza, quindi si richiude senza
## cuciture) e di spessore variabile; fuori ha un alone morbido, dentro le
## VENATURE di radice (le creste di un rumore, piu' forti verso il bordo) e un
## velo che sale verso l'orlo. Il `disco` (il tempo che passa) e' il riempimento
## fino allo stesso bordo irregolare, con le stesse venature.
static func _tex_cerchio(colore : Color, variante : int, disco : bool) -> ImageTexture:
	var lato := 256
	var bordo := FastNoiseLite.new()
	bordo.seed = 1000 + variante * 17
	bordo.frequency = 1.0
	var spessore := FastNoiseLite.new()
	spessore.seed = 2000 + variante * 31
	spessore.frequency = 1.6
	var luce := FastNoiseLite.new()
	luce.seed = 4000 + variante * 13
	luce.frequency = 2.4
	var vene := FastNoiseLite.new()
	vene.seed = 3000 + variante * 7
	vene.frequency = 3.2
	vene.fractal_octaves = 3
	var img := Image.create(lato, lato, false, Image.FORMAT_RGBA8)
	for y in lato:
		for x in lato:
			var c := Vector2(float(x) + 0.5 - lato * 0.5, float(y) + 0.5 - lato * 0.5) / (lato * 0.5)
			var r := c.length()
			var u := c / maxf(r, 0.0001)
			var orlo := 0.82 + 0.09 * bordo.get_noise_2d(u.x * 1.3, u.y * 1.3)
			var t := 0.02 + 0.07 * (spessore.get_noise_2d(u.x * 2.0, u.y * 2.0) * 0.5 + 0.5)
			## Lungo il giro la luce cala e risale: un anello SFRANGIATO.
			var acceso := 0.35 + 0.65 * smoothstep(-0.4, 0.5, luce.get_noise_2d(u.x * 1.8, u.y * 1.8))
			var cresta := pow(1.0 - absf(vene.get_noise_2d(c.x * 2.2, c.y * 2.2)), 14.0)
			var dentro := 1.0 - smoothstep(orlo - 0.01, orlo + 0.01, r)
			var a := 0.0
			if disco:
				a = dentro * (0.18 + 0.32 * smoothstep(0.35, orlo, r)) + dentro * cresta * 0.45
			else:
				var anello := smoothstep(orlo - t - 0.06, orlo - t, r) * (1.0 - smoothstep(orlo, orlo + 0.03, r))
				var alone := 0.3 * exp(-pow((r - orlo) / 0.07, 2.0)) * (1.0 if r > orlo else 0.0)
				var velo := dentro * 0.10 * smoothstep(0.4, orlo, r)
				## Le radici che escono dal bordo: le stesse creste, oltre l'orlo
				## e fino a 0,14 piu' in la', sempre piu' fini.
				var fuori := (1.0 - dentro) * cresta * 0.55 * (1.0 - smoothstep(orlo, orlo + 0.14, r))
				a = (anello * 0.85 + alone) * acceso + velo + dentro * cresta * 0.35 * smoothstep(0.15, orlo, r) + fuori
			a = clampf(a, 0.0, 1.0) if r < 1.0 else 0.0
			img.set_pixel(x, y, Color(colore.r * a, colore.g * a, colore.b * a, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Spore che salgono lente dal bordo mentre il cerchio si riempie: la radice
## sta arrivando da sotto.
static func _spore(raggio : float, colore : Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(clampf(raggio * 18.0, 12.0, 48.0))
	p.lifetime = 1.1
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = raggio * 0.92
	pm.emission_ring_inner_radius = raggio * 0.75
	pm.emission_ring_height = 0.02
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3.ZERO
	pm.radial_accel_min = -0.3
	pm.radial_accel_max = 0.1
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var goccia := QuadMesh.new()
	goccia.size = Vector2(0.1, 0.1)
	var m := _materiale_luce(colore)
	m.set_shader_parameter("tondo", true)
	m.set_shader_parameter("alfa", 0.85)
	goccia.material = m
	p.draw_pass_1 = goccia
	return p


static func _tex_radiale(f : Callable, colore : Color) -> ImageTexture:
	var lato := 128
	var img := Image.create(lato, lato, false, Image.FORMAT_RGBA8)
	for y in lato:
		for x in lato:
			var r := Vector2(float(x) + 0.5 - lato * 0.5, float(y) + 0.5 - lato * 0.5).length() / (lato * 0.5)
			var a : float = clampf(float(f.call(r)), 0.0, 1.0) if r <= 1.0 else 0.0
			## Il cerchio anche nel COLORE, non solo nell'alfa: l'emissione del
			## Decal legge l'RGB e ignora l'alfa — bianco pieno ovunque era un
			## quadrato bianco (visto a render).
			img.set_pixel(x, y, Color(colore.r * a, colore.g * a, colore.b * a, a))
	return ImageTexture.create_from_image(img)


## ─── Sorso ──────────────────────────────────────────────────────────────────
## Scintille dal bersaglio all'Eco per `durata` secondi. Si ferma da solo se
## uno dei due sparisce.
static func sorso(genitore : Node, da : Node3D, a : Node3D, colore : Color, durata : float) -> void:
	var n := Node3D.new()
	n.name = "SorsoEco"
	genitore.add_child(n)
	var mat := _materiale_luce(colore)
	mat.set_shader_parameter("tondo", true)
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var fine := OrologioGioco.adesso_msec() + int(durata * 1000.0)
	var gocce := []
	for k in 10:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		gocce.append([mi, float(k) / 10.0, randf_range(-0.4, 0.4)])
	_scorri(n, da, a, gocce, fine)


static func _scorri(n : Node3D, da : Node3D, a : Node3D, gocce : Array, fine : int) -> void:
	while is_instance_valid(n) and is_instance_valid(da) and is_instance_valid(a) \
			and OrologioGioco.adesso_msec() < fine:
		var p0 : Vector3 = da.global_position + Vector3(0, 1.1, 0)
		var p1 : Vector3 = a.global_position + Vector3(0, 1.3, 0)
		var dt := n.get_process_delta_time()
		for g in gocce:
			g[1] = fmod(float(g[1]) + dt * 0.9, 1.0)
			var t : float = g[1]
			var arco := Vector3(0, sin(t * PI) * 0.6, 0) + (p1 - p0).cross(Vector3.UP).normalized() * sin(t * PI) * float(g[2])
			(g[0] as MeshInstance3D).global_position = p0.lerp(p1, t) + arco
			(g[0] as MeshInstance3D).scale = Vector3.ONE * (0.6 + sin(t * PI) * 0.8)
		await n.get_tree().process_frame
	if is_instance_valid(n):
		n.queue_free()


## ─── Materiali ──────────────────────────────────────────────────────────────
static var _sh_luce : Shader


## Luce piena, sempre di faccia alla camera se e' un quad; `alfa` per spegnerla.
static func _materiale_luce(colore : Color) -> ShaderMaterial:
	if _sh_luce == null:
		_sh_luce = Shader.new()
		_sh_luce.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
uniform vec4 colore : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float alfa = 1.0;
// true = goccia (quad sempre di faccia, tonda); false = striscia (sfuma ai lati).
uniform bool tondo = false;
void vertex() {
	if (tondo) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1].xyz);
	}
}
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float f = tondo ? 1.0 - smoothstep(0.2, 1.0, length(c)) : 1.0 - smoothstep(0.3, 1.0, abs(c.x));
	ALBEDO = mix(colore.rgb, vec3(1.0), 0.35) * 2.0;
	ALPHA = alfa * f;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _sh_luce
	m.set_shader_parameter("colore", colore)
	return m


static func _quad(im : ImmediateMesh, a : Vector3, b : Vector3, c : Vector3, d : Vector3, col : Color) -> void:
	for v in [[a, Vector2(0, 0)], [b, Vector2(1, 0)], [c, Vector2(1, 1)], [a, Vector2(0, 0)], [c, Vector2(1, 1)], [d, Vector2(0, 1)]]:
		im.surface_set_uv(v[1])
		im.surface_add_vertex(v[0])
