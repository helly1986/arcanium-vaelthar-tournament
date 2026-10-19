extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## FRUSTA DI SPINE — i due rampicanti che escono dalle mani del Mago Sylvorn
## ═══════════════════════════════════════════════════════════════════════════
##
## Solo il DISEGNO: chi colpisce e quando lo decide il mago
## (`arcanium_mago_enemy.gd`, mossa FRUSTA). Qui ci sono tre fasi, comandate
## dall'esterno:
##
##   CARICA  — dalla partenza della mossa: i rampicanti escono dalle mani e si
##             arrotolano all'indietro, crescendo e ondeggiando. È l'avviso.
##   SFERZA  — `sferza(punto, durata)`: in `durata` secondi le punte descrivono
##             un arco alto e si piantano sul punto mirato. Arrivano sfalsate
##             (prima la sinistra, poi la destra) come i due contatti.
##   RITIRA  — dopo una breve tenuta tornano nelle mani, e il nodo si libera.
##
## La geometria è un tubo a sezione triangolare lungo una curva di Bézier cubica
## per rampicante, rastremato verso la punta, con le spine ogni tre segmenti:
## una ImmediateMesh riscritta a ogni frame (sono due tubi da 24 segmenti, 150
## triangoli: non vale una mesh preparata). Le mani si leggono dallo scheletro
## ogni frame, così i rampicanti seguono il gesto vero.

const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")
const SEGMENTI := 24
const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 legno : source_color;
uniform vec4 luce : source_color;
void fragment() {
	float k = pow(UV.x, 2.5);
	ALBEDO = mix(legno.rgb, luce.rgb, k * 0.85);
	ROUGHNESS = 0.8;
	EMISSION = luce.rgb * pow(UV.x, 4.0) * 1.6;
}
"""
const LATI := 3

enum Fase { CARICA, SFERZA, TIENI, RITIRA }

var colore_legno : Color = Color(0.20, 0.28, 0.12)
var colore_luce : Color = Color(0.62, 0.32, 1.0)
## Raggio del tubo alla base e lunghezza del rampicante arrotolato in carica.
var raggio : float = 0.075
var lunghezza_carica : float = 1.3
var tenuta : float = 0.18
var ritiro : float = 0.35
## Sfasamento fra i due rampicanti nella sferza, in frazione della durata.
var sfasamento : float = 0.35

var _scheletro : Skeleton3D
var _ossa : Array[int] = []
var _mesh : ImmediateMesh
var _fase : int = Fase.CARICA
var _t : float = 0.0
var _punto : Vector3
var _durata_sferza : float = 0.15
var _punte_carica : Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


## `scheletro` e i nomi delle due ossa delle mani (sinistra, destra).
func prepara(scheletro : Skeleton3D, mano_sx : String, mano_dx : String, luce : Color) -> void:
	_scheletro = scheletro
	colore_luce = luce
	_ossa = [scheletro.find_bone(mano_sx), scheletro.find_bone(mano_dx)]


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	## Il colore lo decide lo SHADER dalla posizione lungo il rampicante (UV.x,
	## 0 alla mano, 1 alla punta): legno verde scuro, che vira al viola sporco e
	## si accende solo verso la punta. Coi colori dei vertici su un
	## StandardMaterial3D i rampicanti uscivano bianchi (2026-09-26), e con
	## un'emissione piena tutti viola: così il legno resta legno.
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("legno", colore_legno)
	mat.set_shader_parameter("luce", colore_luce)
	mi.material_override = mat
	add_child(mi)


## Le punte partono da dove sono e si piantano su `punto` in `durata` secondi.
func sferza(punto : Vector3, durata : float) -> void:
	_punto = punto
	_durata_sferza = maxf(durata, 0.05)
	_fase = Fase.SFERZA
	_t = 0.0


## Interruzione (colpo subito, morte): si ritirano subito.
func ritira() -> void:
	if _fase != Fase.RITIRA:
		_fase = Fase.RITIRA
		_t = 0.0


func fase() -> int:
	return _fase


func _process(delta : float) -> void:
	if _scheletro == null or not is_instance_valid(_scheletro) or _ossa.has(-1):
		queue_free()
		return
	_t += delta
	match _fase:
		Fase.SFERZA:
			if _t >= _durata_sferza * (1.0 + sfasamento):
				_fase = Fase.TIENI
				_t = 0.0
		Fase.TIENI:
			if _t >= tenuta:
				_fase = Fase.RITIRA
				_t = 0.0
		Fase.RITIRA:
			if _t >= ritiro:
				queue_free()
				return
	_disegna()


func _mano(i : int) -> Transform3D:
	return _scheletro.global_transform * _scheletro.get_bone_global_pose(_ossa[i])


func _disegna() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var corpo := _scheletro.global_transform
	var avanti := corpo.basis.z
	avanti.y = 0.0
	avanti = avanti.normalized() if avanti.length() > 0.01 else Vector3.FORWARD
	for i in 2:
		var mano := _mano(i)
		var p0 := mano.origin
		var lato := corpo.basis.x.normalized() * (-1.0 if i == 0 else 1.0)
		var tempo := OrologioGioco.adesso()
		## CARICA: arrotolato dietro e sopra la mano, che ondeggia.
		var crescita := clampf(_t / 0.5, 0.0, 1.0) if _fase == Fase.CARICA else 1.0
		var arrotolata := p0 + (-avanti * 0.6 + Vector3.UP * 0.5 + lato * 0.35).normalized() * lunghezza_carica * crescita \
			+ Vector3(sin(tempo * 5.0 + i), cos(tempo * 4.0 + i * 2.0), 0.0) * 0.12
		var fine := arrotolata
		var alto := 0.8
		match _fase:
			Fase.CARICA:
				_punte_carica[i] = arrotolata
			Fase.SFERZA:
				var ritardo := sfasamento * _durata_sferza * float(i)
				var k := clampf((_t - ritardo) / _durata_sferza, 0.0, 1.0)
				k = 1.0 - pow(1.0 - k, 3.0)
				fine = _arco(_punte_carica[i], _punto + lato * 0.4, k)
				alto = lerpf(0.8, 0.3, k)
			Fase.TIENI:
				fine = _punto + lato * 0.4
				alto = 0.3
			Fase.RITIRA:
				var k := clampf(_t / ritiro, 0.0, 1.0)
				fine = (_punto + lato * 0.4).lerp(p0, k * k)
				alto = 0.3 * (1.0 - k)
		_tubo(p0, fine, alto, lato, i)
	_mesh.surface_end()


## La punta che vola dalla carica al bersaglio passando ALTA: una sferzata, non
## un affondo dritto.
func _arco(da : Vector3, a : Vector3, k : float) -> Vector3:
	var p := da.lerp(a, k)
	p.y += sin(k * PI) * 1.2
	return p


func _tubo(p0 : Vector3, p3 : Vector3, alto : float, lato : Vector3, seme : int) -> void:
	var d := p3 - p0
	var p1 := p0 + d * 0.3 + Vector3.UP * alto * d.length() * 0.35 + lato * 0.25
	var p2 := p0 + d * 0.7 + Vector3.UP * alto * d.length() * 0.2 - lato * 0.15
	var punti : Array[Vector3] = []
	for s in SEGMENTI + 1:
		var u := float(s) / float(SEGMENTI)
		var v := 1.0 - u
		punti.append(p0 * v * v * v + p1 * 3.0 * v * v * u + p2 * 3.0 * v * u * u + p3 * u * u * u)
	var anelli : Array = []
	for s in punti.size():
		var t := (punti[mini(s + 1, punti.size() - 1)] - punti[maxi(s - 1, 0)]).normalized()
		var n := t.cross(Vector3.UP)
		if n.length() < 0.01:
			n = t.cross(Vector3.RIGHT)
		n = n.normalized()
		var b := t.cross(n).normalized()
		var r := raggio * lerpf(1.0, 0.18, float(s) / float(SEGMENTI))
		var anello : Array[Vector3] = []
		for l in LATI:
			var a := TAU * float(l) / float(LATI) + float(s) * 0.4
			anello.append(punti[s] + (n * cos(a) + b * sin(a)) * r)
		anelli.append(anello)
		## Le spine: ogni tre segmenti, una punta fuori dal tubo.
		if s % 3 == 1 and s < SEGMENTI - 1:
			var a2 := float(s * 7 + seme * 3)
			var fuori := (n * cos(a2) + b * sin(a2)).normalized()
			var base := punti[s] + fuori * r * 0.8
			_tri(base + t * r, base - t * r, punti[s] + fuori * (r + 0.09), float(s) / float(SEGMENTI))
	for s in anelli.size() - 1:
		var ca : Array = anelli[s]
		var cb : Array = anelli[s + 1]
		## Il legno si accende verso la punta (lo fa lo shader, da `u`).
		var u := float(s) / float(SEGMENTI)
		for l in LATI:
			var l2 := (l + 1) % LATI
			_tri(ca[l], cb[l], cb[l2], u)
			_tri(ca[l], cb[l2], ca[l2], u)


func _tri(a : Vector3, b : Vector3, c : Vector3, u : float) -> void:
	var n := (b - a).cross(c - a).normalized()
	for p in [a, b, c]:
		_mesh.surface_set_uv(Vector2(u, 0.0))
		_mesh.surface_set_normal(n)
		_mesh.surface_add_vertex(p)
