extends Node

## ═══════════════════════════════════════════════════════════════════════════
## IL MIRACOLO DELLA VITA — l'energia che il protagonista tira su dal basso
## ═══════════════════════════════════════════════════════════════════════════
##
## Mentre il protagonista fa la sua danza, qualcosa deve NASCERE. Senza, quei
## quattro secondi sono un uomo che si accuccia e alza le braccia.
##
## Tre atti, agganciati agli istanti MISURATI sulla clip `Evocazione` (4,00 s):
##
##   0,60 s  NASCITA   fra le mani basse si accende un seme. Intorno, particelle
##                     che convergono VERSO di lui: l'energia non compare, viene
##                     raccolta.
##   1,60 s  MATURA    la sfera è formata e comincia a salire con le mani.
##   2,10 s  RILASCIO  apice delle braccia: la sfera si apre verso l'ALTO in un
##                     arco, e resta la scia mentre la creatura si materializza.
##   2,90 s  FINE      la coda si spegne.
##
## ⚠️ Questi numeri NON sono scelti: vengono da `misura_rilascio.py` sulla clip
## vera (raccolta 0,6-1,6 s, apice a 2,10 s, tenuta fino a 2,7). Se la clip
## cambia vanno rimisurati, ed è lo stesso motivo per cui `summon_release_delay`
## del player vale 2,10 — le due cose devono guardare lo stesso istante.
##
## La sfera vive fra le MANI e le segue fotogramma per fotogramma: leggere le
## ossa è l'unico modo perché l'effetto stia dov'è la mano anche se la clip
## viene ritoccata.

## Il viola dell'Arcanium, lo stesso della materializzazione e del pelo guasto.
const VIOLA := Color(0.65, 0.18, 1.0)
## Il cuore della sfera è quasi bianco: senza un centro caldo una palla di
## energia legge come una palla di fumo colorato.
const CUORE := Color(0.92, 0.80, 1.0)

@export var player_node : Node
## Lo scheletro da cui leggere le mani. Se manca, l'effetto non parte: meglio
## niente che una sfera piantata nell'origine del personaggio.
@export var skeleton : Skeleton3D

@export_group("Tempi (s dall'inizio del gesto)")
@export var t_nascita : float = 0.60
@export var t_matura : float = 1.60
@export var t_rilascio : float = 2.10
@export var t_fine : float = 2.90

@export_group("Aspetto")
## Raggio della sfera a maturità, in metri.
@export var raggio : float = 0.22
## Da quanto lontano arriva l'energia raccolta.
@export var raggio_raccolta : float = 1.0

var _vivo : Node3D = null


func _ready() -> void:
	if player_node == null:
		return
	await get_tree().process_frame
	if player_node.has_signal("summon_started"):
		player_node.summon_started.connect(_su_evocazione)


func _su_evocazione() -> void:
	if skeleton == null:
		push_warning("MiracoloEvocazione: manca lo Skeleton3D, niente effetto.")
		return
	## Un'evocazione alla volta: se ne parte una nuova, la vecchia se ne va.
	if is_instance_valid(_vivo):
		_vivo.queue_free()
	_vivo = _Miracolo.crea(self, skeleton, t_nascita, t_matura, t_rilascio,
		t_fine, raggio, raggio_raccolta)


## ───────────────────────────────────────────────────────────────────────────
## L'effetto vero, che si gestisce la vita da solo.
## ───────────────────────────────────────────────────────────────────────────
class _Miracolo extends Node3D:
	var _scheletro : Skeleton3D
	var _mano_sx : int = -1
	var _mano_dx : int = -1
	var _t : float = 0.0
	var _nascita : float
	var _matura : float
	var _rilascio : float
	var _fine : float
	var _raggio : float
	var _raggio_raccolta : float

	var _sfera : MeshInstance3D
	var _luce : OmniLight3D
	var _raccolta : GPUParticles3D
	var _scoppio : GPUParticles3D
	var _gia_scoppiato : bool = false

	static func crea(ospite : Node, scheletro : Skeleton3D, nascita : float,
			matura : float, rilascio : float, fine : float, raggio : float,
			raggio_raccolta : float) -> Node3D:
		var m := _Miracolo.new()
		m._scheletro = scheletro
		m._nascita = nascita
		m._matura = matura
		m._rilascio = rilascio
		m._fine = fine
		m._raggio = raggio
		m._raggio_raccolta = raggio_raccolta
		m.name = "MiracoloEvocazione"
		## Appeso alla SCENA e non allo scheletro: la sfera si posiziona da sé in
		## coordinate globali, e appendendola alle ossa erediterebbe la loro
		## rotazione — a braccia aperte la vedresti ribaltarsi.
		var radice := ospite.get_tree().current_scene
		if radice == null:
			radice = scheletro.get_tree().root
		radice.add_child(m)
		return m

	func _ready() -> void:
		_mano_sx = _scheletro.find_bone("LeftHand")
		_mano_dx = _scheletro.find_bone("RightHand")
		if _mano_sx < 0 or _mano_dx < 0:
			push_warning("MiracoloEvocazione: mani non trovate nello scheletro.")
			queue_free()
			return
		_costruisci()
		global_position = _fra_le_mani()
		visible = false

	## Punto medio fra le due mani, in coordinate di mondo.
	func _fra_le_mani() -> Vector3:
		var a : Vector3 = (_scheletro.global_transform * _scheletro.get_bone_global_pose(_mano_sx)).origin
		var b : Vector3 = (_scheletro.global_transform * _scheletro.get_bone_global_pose(_mano_dx)).origin
		return (a + b) * 0.5

	func _costruisci() -> void:
		var sfera_mesh := SphereMesh.new()
		sfera_mesh.radius = 1.0
		sfera_mesh.height = 2.0
		sfera_mesh.radial_segments = 24
		sfera_mesh.rings = 12
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = CUORE
		mat.disable_receive_shadows = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sfera_mesh.material = mat
		_sfera = MeshInstance3D.new()
		_sfera.mesh = sfera_mesh
		_sfera.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sfera.scale = Vector3.ZERO
		add_child(_sfera)

		## La luce è metà dell'effetto: è lei che mette il viola sul VOLTO e sul
		## petto mentre lui si accuccia. Senza, la sfera galleggia davanti a un
		## personaggio illuminato come se non stesse succedendo niente.
		_luce = OmniLight3D.new()
		_luce.light_color = VIOLA
		_luce.light_energy = 0.0
		_luce.omni_range = 4.0
		_luce.shadow_enabled = false
		add_child(_luce)

		_raccolta = _particelle_raccolta()
		add_child(_raccolta)
		_scoppio = _particelle_scoppio()
		add_child(_scoppio)

	## L'energia che ARRIVA: emessa lontano, tirata verso il centro.
	## `radial_accel` NEGATIVO è ciò che la fa cadere dentro invece che uscire.
	func _particelle_raccolta() -> GPUParticles3D:
		var p := GPUParticles3D.new()
		## ⚠️ Meno particelle e da più vicino di quanto sembrasse giusto sulla
		## carta. Con 90 scintille sparse su 1,6 m il campo si riempiva e non si
		## capiva più dove fosse il centro: la raccolta si legge se le scintille
		## CONVERGONO, non se sono tante.
		p.amount = 46
		p.lifetime = 0.7
		p.local_coords = true
		p.emitting = false
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = _raggio_raccolta
		pm.direction = Vector3.ZERO
		pm.spread = 180.0
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 0.2
		pm.gravity = Vector3.ZERO
		pm.radial_accel_min = -7.0
		pm.radial_accel_max = -11.0
		pm.tangential_accel_min = 1.0
		pm.tangential_accel_max = 2.5
		pm.scale_min = 0.03
		pm.scale_max = 0.09
		pm.color = VIOLA
		p.process_material = pm
		p.draw_pass_1 = _scintilla(0.10)
		return p

	## Il RILASCIO: una cupola verso l'alto, non una sfera. `direction` in su con
	## `spread` a 85° dà l'arco che si apre sopra le mani aperte.
	func _particelle_scoppio() -> GPUParticles3D:
		var p := GPUParticles3D.new()
		p.amount = 130
		p.lifetime = 1.15
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.emitting = false
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = _raggio * 0.9
		pm.direction = Vector3.UP
		pm.spread = 85.0
		pm.initial_velocity_min = 2.6
		pm.initial_velocity_max = 5.2
		## Una gravità LEGGERA piega le traiettorie: senza, l'arco è un riccio di
		## raggi dritti e sembra un'esplosione, non un fiore che si apre.
		pm.gravity = Vector3(0, -3.2, 0)
		pm.damping_min = 1.2
		pm.damping_max = 2.6
		pm.scale_min = 0.05
		pm.scale_max = 0.14
		pm.color = CUORE
		var rampa := Gradient.new()
		rampa.set_color(0, CUORE)
		rampa.set_color(1, Color(VIOLA.r, VIOLA.g, VIOLA.b, 0.0))
		var tex := GradientTexture1D.new()
		tex.gradient = rampa
		pm.color_ramp = tex
		p.process_material = pm
		p.draw_pass_1 = _scintilla(0.16)
		return p

	## ⚠️ La texture NON è un abbellimento. Un quad additivo SENZA texture si
	## disegna come un QUADRATO PIENO dal bordo netto: provato in gioco, lo
	## schermo si riempiva di rettangoli viola invece che di scintille. Serve una
	## macchia che sfuma sui bordi, e `GradientTexture2D` in modalità radiale la
	## fa senza portarsi dietro un file.
	static func _macchia() -> GradientTexture2D:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		return tex

	func _scintilla(lato : float) -> QuadMesh:
		var q := QuadMesh.new()
		q.size = Vector2(lato, lato)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		sm.vertex_color_use_as_albedo = true
		sm.albedo_color = VIOLA
		sm.albedo_texture = _macchia()
		sm.disable_receive_shadows = true
		q.material = sm
		return q

	func _process(delta : float) -> void:
		_t += delta
		if _t >= _fine:
			queue_free()
			return
		if _t < _nascita:
			return
		if not visible:
			visible = true
			_raccolta.emitting = true

		## Prima del rilascio la sfera sta FRA LE MANI e le segue. Dopo resta
		## dov'era: le mani si aprono a 1,41 m e il punto medio non vuol più dire
		## niente — l'energia se n'è andata per conto suo.
		if _t < _rilascio:
			global_position = _fra_le_mani()

		if _t < _rilascio:
			## Cresce fino a maturità, poi resta piena e pulsa appena.
			var q : float = clampf((_t - _nascita) / maxf(_matura - _nascita, 0.001), 0.0, 1.0)
			var r : float = _raggio * ease(q, 0.35)
			if _t > _matura:
				r *= 1.0 + 0.06 * sin((_t - _matura) * 14.0)
			_sfera.scale = Vector3.ONE * r
			_luce.light_energy = 3.2 * q
		elif not _gia_scoppiato:
			_gia_scoppiato = true
			_raccolta.emitting = false
			_scoppio.emitting = true
			_sfera.scale = Vector3.ZERO
			_luce.light_energy = 9.0
		else:
			## Coda: la luce si spegne mentre la creatura affiora.
			var q : float = clampf((_t - _rilascio) / maxf(_fine - _rilascio, 0.001), 0.0, 1.0)
			_luce.light_energy = 9.0 * (1.0 - q) * (1.0 - q)
