extends MeshInstance3D

## ⚠️ Niente `class_name`: chi la usa fa `preload` (vedi `fazioni.gd`).

## ═══════════════════════════════════════════════════════════════════════════
## SCIA DELLA FRECCIA — perche' una freccia si possa VEDERE arrivare
## ═══════════════════════════════════════════════════════════════════════════
##
## Un'asta di 70 cm larga due centimetri e mezzo, vista dalla camera isometrica
## a venti metri, e' meno di un pixel: al 2026-09-25 le frecce dell'arciere
## colpivano senza che le si vedesse partire, e un colpo che non si vede non si
## schiva. La scia e' la lettura del tiro — da dove viene, dove va, quando
## arriva — ed e' quindi gameplay, non decoro.
##
## Un NASTRO dietro la freccia, largo in testa e a zero in coda, sempre girato
## verso la camera (un nastro piatto visto di taglio sparirebbe proprio nei tiri
## che vengono dritti verso di lei, cioe' quelli che contano). Colore pieno e
## non additivo: sul sentiero al sole un additivo si perde. In testa un
## bagliore, che segna il punto che colpisce.
##
## Vive nel LIVELLO, non sotto la freccia: quando la freccia si conficca e
## sparisce la scia non si taglia di netto — smette di allungarsi e la coda la
## raggiunge in `durata` secondi, poi si libera da sola.

## Il proiettile da seguire.
var freccia : Node3D
var colore : Color = Color(0.55, 1.0, 0.85)
## Quanto dura un punto della scia, in secondi: la lunghezza a schermo e'
## velocita' x durata (19 m/s x 0,3 s = 5,7 m).
var durata : float = 0.3
## Larghezza in testa, in metri.
var larghezza : float = 0.28
## Diametro del bagliore in testa, in metri.
var bagliore : float = 0.8

var _punti : Array = []     ## [posizione, istante]
var _im := ImmediateMesh.new()
var _testa : MeshInstance3D
var _t : float = 0.0


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _materiale_nastro()
	_testa = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(bagliore, bagliore)
	_testa.mesh = q
	_testa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_testa.material_override = _materiale_bagliore()
	add_child(_testa)
	_testa.top_level = true


func _process(delta : float) -> void:
	_t += delta
	var viva := is_instance_valid(freccia) and freccia.is_inside_tree() and freccia.visible
	if viva:
		## La punta: la freccia guarda -Z, e la scia parte da li'.
		var punta : Vector3 = freccia.global_position - freccia.global_basis.z * 0.35
		_punti.push_front([punta, _t])
		_testa.global_position = punta
	_testa.visible = viva
	while not _punti.is_empty() and _t - float(_punti.back()[1]) > durata:
		_punti.pop_back()
	if _punti.is_empty() and not viva:
		queue_free()
		return
	_disegna()


func _disegna() -> void:
	_im.clear_surfaces()
	if _punti.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var occhio : Vector3 = cam.global_position if cam != null else Vector3(0, 100, 0)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _punti.size()
	for i in n:
		var p : Vector3 = _punti[i][0]
		var avanti : Vector3 = (_punti[maxi(i - 1, 0)][0] - _punti[mini(i + 1, n - 1)][0])
		var lato := avanti.cross(occhio - p)
		if lato.length() < 0.0001:
			lato = Vector3.UP
		lato = lato.normalized()
		## 1 in testa, 0 in coda: per eta' del punto, cosi' la coda si ritira
		## anche a freccia ferma.
		var vita : float = clampf(1.0 - (_t - float(_punti[i][1])) / durata, 0.0, 1.0)
		var w : float = larghezza * 0.5 * vita
		var c := Color(colore.r, colore.g, colore.b, vita)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(0.0, 1.0 - vita))
		_im.surface_add_vertex(p + lato * w)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(1.0, 1.0 - vita))
		_im.surface_add_vertex(p - lato * w)
	_im.surface_end()


static var _shader_nastro : Shader
static var _shader_bagliore : Shader


## Un nucleo chiaro al centro del nastro e il colore sui bordi; l'alfa scende
## verso la coda e verso i bordi.
func _materiale_nastro() -> ShaderMaterial:
	if _shader_nastro == null:
		_shader_nastro = Shader.new()
		_shader_nastro.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float nucleo = 1.0 - smoothstep(0.0, 0.45, x);
	ALBEDO = mix(COLOR.rgb, vec3(1.0), nucleo * 0.7);
	ALPHA = COLOR.a * (1.0 - smoothstep(0.55, 1.0, x)) * 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader_nastro
	return m


## Un disco sfumato sempre di faccia alla camera.
func _materiale_bagliore() -> ShaderMaterial:
	if _shader_bagliore == null:
		_shader_bagliore = Shader.new()
		_shader_bagliore.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 colore : source_color = vec4(0.55, 1.0, 0.85, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float a = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = mix(colore.rgb, vec3(1.0), (1.0 - smoothstep(0.0, 0.35, r)) * 0.8);
	ALPHA = a * a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader_bagliore
	m.set_shader_parameter("colore", colore)
	return m
