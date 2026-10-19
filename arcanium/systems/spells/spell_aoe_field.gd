extends Node3D
class_name SpellAoeField

## preload per PATH invece di affidarsi al registro globale di class_name:
## la cache dell editor non sempre vede subito le classi nuove (vedi note di
## progetto sul gotcha "Identifier not declared").
const ArcaniumVFX := preload("res://arcanium/systems/vfx/arcanium_vfx.gd")
const BossVFX := preload("res://arcanium/systems/boss_vfx.gd")

## Campo AoE POSIZIONALE generico, istanziato da SpellCaster.cast_positional()
## al centro scelto dal player nel piazzamento (vedi PlacementController).
## Resta a terra per `duration` secondi, e ogni fisica-frame rifornisce lo
## StatusHost di tutti i nodi nel gruppo "targets" entro `radius` con
## `status_buildup_per_sec * delta` di build-up (oggi: Congelamento — vedi
## FrozenEffect/StatusHost.build_frozen). ZERO danno: solo status, come da
## design di "Morsa del gelo". Non è specifico di un solo spell: qualunque
## spell posizionale che voglia infliggere build-up di stato può riusare
## questa scena (aoe_field_scene nel .tres) senza toccare questo file.
##
## Poligono di raccolta bersagli: polling su get_tree().get_nodes_in_group
## ("targets") + distanza, non Area3D/collisioni — più semplice e sufficiente
## per un campo a vita breve (durata tipica ~2s), evita la complessità di
## body_entered/exited con bersagli che entrano/escono dal raggio nel mezzo.

@export var radius : float = 3.0
@export var duration : float = 2.0
@export var color : Color = Color("#9fe6ff")
## Build-up di status al SECONDO per bersaglio nel raggio. Impostato dallo
## spell (SpellCaster._spawn_field) da aoe_status_buildup_per_sec del .tres.
@export var status_buildup_per_sec : float = 0.0
## Tipo di danno "nominale" del campo — oggi ignorato (zero danno), tenuto per
## coerenza col resto del contratto spell (proiettili/armi leggono damage_type).
@export var damage_type : String = "CRIO"

## Secondi di "apertura" del campo: quanto ci mette a scattare a piena
## larghezza allo spawn. Corto apposta — il player deve capire SUBITO dove ha
## piazzato, l'animazione e' rifinitura, non attesa.
@export var open_time : float = 0.28

var _age : float = 0.0

## Materiali degli shader (disco + velo verticale). Vengono pilotati ogni frame
## con `life` e `open`: e' li' che vive l'informazione di gameplay, non in un
## tween — se il campo venisse distrutto prima (o la durata cambiasse da
## risorsa) il quadrante resterebbe comunque sincronizzato con la verita'.
var _disc_mat : ShaderMaterial = null
var _wall_mat : ShaderMaterial = null

## Il loop della tormenta. ⚠️ Si tiene il riferimento perche' un loop non
## finisce da solo: va spento quando il campo scade, e in dissolvenza — il fade
## di un loop si fa QUI e non dentro al file, dove diventerebbe un avvallamento
## a ogni giro.
var _voce_tormenta : Node = null

func _ready() -> void:
	_build_visuals()
	_voce_tormenta = Suoni.loop_nel_mondo(self, Suoni.MORSA_GELO, -2.0)

func _physics_process(delta : float) -> void:
	_age += delta
	if status_buildup_per_sec > 0.0:
		_tick_targets(delta)
	_update_visual_state()
	if _age >= duration:
		## Il suono si stacca dal campo PRIMA di liberarlo, cosi' puo' dissolversi
		## per conto suo: fosse figlio del campo, morirebbe di netto insieme a lui.
		Suoni.spegni(_voce_tormenta, 0.5)
		_voce_tormenta = null
		queue_free()

## Sincronizza gli shader con lo stato reale del campo.
##   open → 0..1 nei primi `open_time` secondi (lo scatto del ghiaccio)
##   life → 1..0 sull'intera durata (il quadrante che si ritira)
func _update_visual_state() -> void:
	var open := 1.0 if open_time <= 0.0 else clampf(_age / open_time, 0.0, 1.0)
	var life := 1.0 if duration <= 0.0 else clampf(1.0 - _age / duration, 0.0, 1.0)
	if _disc_mat:
		_disc_mat.set_shader_parameter("open", open)
		_disc_mat.set_shader_parameter("life", life)
	if _wall_mat:
		_wall_mat.set_shader_parameter("open", open)
		_wall_mat.set_shader_parameter("life", life)

## Rifornisce il Congelamento di ogni "target" entro il raggio. Duck-typed su
## `health_system.status_host` (stesso pattern usato da
## player_charbody3D._find_critical_target()). Se un bersaglio non ha
## StatusHost, viene semplicemente ignorato (nessun crash) — StatusHost.
## build_frozen() crea comunque il FrozenEffect al volo se assente, quindi
## basta che il nodo abbia un health_system con status_host assegnato.
func _tick_targets(delta : float) -> void:
	var amount := status_buildup_per_sec * delta
	for raw_n in get_tree().get_nodes_in_group("targets"):
		var n := raw_n as Node3D
		if n == null:
			continue
		if global_position.distance_to(n.global_position) > radius:
			continue
		if "health_system" in n and n.health_system and "status_host" in n.health_system:
			var host = n.health_system.status_host
			if host:
				host.build_frozen(amount)

## ─── VFX ─────────────────────────────────────────────────────────────────────
## PROGETTATO PER LA CAMERA ISOMETRICA (IsoCam: offset 0/28/22, ~52° sopra
## l'orizzonte). Da lassu' il pavimento e' la superficie meglio inquadrata,
## quindi l'informazione di gameplay sta sul PIANO:
##   • disco a terra  → raggio (il bordo) + durata (il pieno che si ritira)
##   • velo verticale → lo stesso confine, ma leggibile quando i corpi dei
##     nemici coprono il pavimento
##   • punte di ghiaccio → silhouette: dicono "campo solido" e non "decal"
##   • brina sospesa   → volume e vita
## Le arene sono buie e low-albedo: disco e velo sono ADDITIVI, cosi' staccano
## sul fondo invece di sporcarlo con un grigio trasparente.
const SPIKE_COUNT := 8

func _build_visuals() -> void:
	_build_disc()
	_build_wall()
	_build_spikes()
	_build_mist()
	_build_light()

## Disco a terra: PlaneMesh (non CylinderMesh — al campo serve UNA faccia, non
## un cilindro schiacciato: meta' dei triangoli e nessun fianco che si vede di
## taglio in isometrica). Le UV 0..1 della PlaneMesh sono cio' su cui lo shader
## costruisce raggio e quadrante.
func _build_disc() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Disco"
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = plane
	_disc_mat = ArcaniumVFX.frost_field_material(color, 1.2)
	mi.material_override = _disc_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Appena sopra il pavimento: lo shader non scrive profondita', ma un filo di
	## stacco evita il compenetrarsi con dislivelli minimi del terreno.
	mi.position = Vector3(0.0, 0.03, 0.0)
	add_child(mi)

## Velo verticale sul perimetro: cilindro APERTO (niente tappi, altrimenti si
## pagherebbe un secondo disco di overdraw sopra il primo).
func _build_wall() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Velo"
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.8
	cyl.radial_segments = 48
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	_wall_mat = ArcaniumVFX.frost_wall_material(color, 1.1)
	_wall_mat.set_shader_parameter("mesh_height", cyl.height)
	mi.material_override = _wall_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, cyl.height * 0.5, 0.0)
	add_child(mi)

## Punte di ghiaccio sul bordo: poche e basse. Servono alla SILHOUETTE — in
## isometrica un effetto tutto piatto legge come una texture sul pavimento,
## mentre qualche volume che rompe la linea dice "e' successo qualcosa qui".
## Tutte condividono UN materiale: 8 mesh, un solo stato GPU.
func _build_spikes() -> void:
	var mat := ArcaniumVFX.ice_crystal_material(color, 1.6, 0.70)
	for i in SPIKE_COUNT:
		var ang := TAU * float(i) / float(SPIKE_COUNT)
		var mi := MeshInstance3D.new()
		mi.name = "Punta%d" % i
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.16
		cone.height = 0.55 + 0.25 * float(i % 3)
		cone.radial_segments = 5      ## faccettato apposta: e' ghiaccio, non vetro soffiato
		cone.rings = 1
		cone.cap_top = false
		mi.mesh = cone
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(ang) * radius * 0.96, cone.height * 0.42, sin(ang) * radius * 0.96)
		## Inclinate verso l'esterno: sembrano spuntate dal terreno spinte dal
		## centro, non piantate a mano in verticale.
		mi.rotation = Vector3(deg_to_rad(12.0) * cos(ang + PI * 0.5), 0.0, deg_to_rad(-12.0) * cos(ang))
		add_child(mi)

## Brina sospesa. Riusa la texture monocromatica condivisa (BossVFX): zero
## asset nuovi, tinta a runtime. `local_coords = false` perche' il campo non si
## muove ma il pattern deve restare ancorato al mondo.
func _build_mist() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Brina"
	particles.amount = 36
	particles.lifetime = 1.8
	particles.local_coords = false
	## Senza AABB esplicito le particelle in coordinate globali vengono cullate
	## a sproposito quando la camera iso inquadra il campo di sbieco.
	particles.visibility_aabb = AABB(
		Vector3(-radius, -0.5, -radius), Vector3(radius * 2.0, 2.5, radius * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.95
	pm.emission_ring_inner_radius = radius * 0.15
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.6
	## Gravita' NEGATIVA debolissima: la brina sale invece di cadere. E' cio' che
	## la distingue dalla polvere e la fa leggere come freddo che si alza.
	pm.gravity = Vector3(0.0, 0.25, 0.0)
	pm.damping_min = 0.2
	pm.damping_max = 0.8
	pm.scale_min = 0.06
	pm.scale_max = 0.20
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = curve
	pm.scale_curve = scale_curve
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	grad.add_point(0.3, Color(1.0, 1.0, 1.0, 0.9))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	particles.process_material = pm
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(0.22, 0.22)
	qmesh.material = BossVFX.particle_material(BossVFX.TEX_GLOW, color, 2.0)
	particles.draw_pass_1 = qmesh
	add_child(particles)

## Una sola luce, SENZA ombre: l'atlas delle ombre del Forward+/Mobile va
## saturato dalle luci con ombra, e un campo AoE non ne ha bisogno — deve
## illuminare i piedi di chi ci sta dentro, non proiettare geometrie.
func _build_light() -> void:
	var light := OmniLight3D.new()
	light.name = "LuceGelo"
	light.light_color = color
	light.light_energy = 1.1
	light.omni_range = radius * 1.4
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.0, 0.0)
	add_child(light)
