extends MultiMeshInstance3D

## Faville che salgono e si spengono, per gli effetti delle Lucide Tecniche: quad
## rivolti alla camera, con un arco calcolato a mano come le zolle di SchiantoATerra.
## Si dice dove nascono (`emetti`, in coordinate di questo nodo), il resto fa da se'.

const QUANTE_DI_DEFAULT := 150

var _dati : Array = []
var _prossima := 0


func prepara(quante : int = QUANTE_DI_DEFAULT, lato : float = 0.2) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * lato
	var alone := GradientTexture2D.new()
	alone.fill = GradientTexture2D.FILL_RADIAL
	alone.fill_from = Vector2(0.5, 0.5)
	alone.fill_to = Vector2(1.0, 0.5)
	var scala := Gradient.new()
	scala.set_color(0, Color.WHITE)
	scala.set_color(1, Color(1, 1, 1, 0))
	alone.gradient = scala
	var materiale := StandardMaterial3D.new()
	materiale.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materiale.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	materiale.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	materiale.vertex_color_use_as_albedo = true
	## I colori di chi emette sono quelli che si vedono, non valori lineari.
	materiale.vertex_color_is_srgb = true
	materiale.albedo_texture = alone
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = quante
	material_override = materiale
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in quante:
		_dati.append({"vita": 0.0, "dura": 1.0, "dove": Vector3.ZERO, "v": Vector3.ZERO, "colore": Color.WHITE})
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))


func emetti(dove : Vector3, v : Vector3, dura : float, colore : Color) -> void:
	var d : Dictionary = _dati[_prossima]
	_prossima = (_prossima + 1) % _dati.size()
	d["dove"] = dove
	d["v"] = v
	d["dura"] = dura
	d["vita"] = dura
	d["colore"] = colore


func _physics_process(delta : float) -> void:
	for i in _dati.size():
		var d : Dictionary = _dati[i]
		var vita : float = d["vita"]
		if vita <= 0.0:
			continue
		vita -= delta
		d["vita"] = vita
		if vita <= 0.0:
			multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		d["v"] = d["v"] * (1.0 - 1.4 * delta) + Vector3.DOWN * 1.1 * delta
		d["dove"] = d["dove"] + d["v"] * delta
		var quota : float = vita / d["dura"]
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * lerpf(0.4, 1.1, quota)), d["dove"]))
		var c : Color = d["colore"]
		c.a = quota
		multimesh.set_instance_color(i, c)
