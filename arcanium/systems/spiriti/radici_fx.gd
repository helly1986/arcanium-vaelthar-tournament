extends Node3D

## ⚠️ Niente `class_name`: si usa con `preload`.

## ═══════════════════════════════════════════════════════════════════════════
## RADICI DELLA VOCE — l'energia che il Mago raccoglie e manda sotto terra
## ═══════════════════════════════════════════════════════════════════════════
##
## Il disegno della mossa RADICI del Mago (arcanium_mago_enemy.gd), sul gesto
## di `spell/spell_radici_01` (arcanium/animazioni/mago/radici.py). Richiesta
## dell'utente del 2026-10-28: «VFX che mostrino l'energia che viene generata e
## movimentata». Segue il TEMPO DELLA CLIP, che gli passa il mago a ogni frame
## (`aggiorna`): se la mossa si interrompe, `spegni`.
##
##   RACCOLTA  (0,40 -> 1,40 s) — fra le mani nasce una sfera di luce viola
##                                che cresce e tira a se' scintille dal giro.
##   DISCESA   (1,40 -> AFFONDO) — la sfera segue le mani verso il suolo,
##                                piu' intensa.
##   AFFONDO   (1,75 s)          — le mani toccano terra: la sfera si spegne in
##                                un'onda a terra, e tre vene di luce corrono
##                                sotto il suolo, una per cerchio delle radici.
##   CONTATTO  (1,97 s)          — le vene arrivano: le radici esplodono
##                                (EcoFx.radice, che il mago ha gia' segnato).
##
## Vive nel livello (top_level), si libera da sola a fine onda.

const EcoFx := preload("res://arcanium/systems/spiriti/eco_fx.gd")

const RACCOLTA := 0.40
const DISCESA := 1.40
const AFFONDO := 1.75

var colore : Color = Color(0.62, 0.32, 1.0)
## Dove arrivano le vene: i centri dei cerchi delle radici.
var punti : Array[Vector3] = []
## Il secondo di clip del contatto (le vene ci arrivano).
var contatto : float = 1.97

var _scheletro : Skeleton3D
var _mani : Array[int] = []
var _sfera : MeshInstance3D
var _richiamo : GPUParticles3D
var _luce : OmniLight3D
var _affondato := false
var _spento := false


func prepara(scheletro : Skeleton3D, mano_sx : String, mano_dx : String, luce : Color) -> void:
	_scheletro = scheletro
	colore = luce
	_mani = [scheletro.find_bone(mano_sx), scheletro.find_bone(mano_dx)]


func _ready() -> void:
	top_level = true
	_sfera = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_sfera.mesh = q
	var m := EcoFx._materiale_luce(colore)
	m.set_shader_parameter("tondo", true)
	m.set_shader_parameter("alfa", 0.0)
	_sfera.material_override = m
	_sfera.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sfera)

	## Le scintille che il Mago tira a se': nascono su una sfera larga e
	## cadono verso il centro (accelerazione radiale negativa).
	_richiamo = GPUParticles3D.new()
	_richiamo.amount = 48
	_richiamo.lifetime = 0.6
	_richiamo.local_coords = true
	_richiamo.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 0.55
	pm.gravity = Vector3.ZERO
	pm.radial_accel_min = -5.0
	pm.radial_accel_max = -3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_richiamo.process_material = pm
	var goccia := QuadMesh.new()
	goccia.size = Vector2(0.05, 0.05)
	var mg := EcoFx._materiale_luce(colore)
	mg.set_shader_parameter("tondo", true)
	goccia.material = mg
	_richiamo.draw_pass_1 = goccia
	_sfera.add_child(_richiamo)

	_luce = OmniLight3D.new()
	_luce.light_color = colore
	_luce.light_energy = 0.0
	_luce.omni_range = 2.5
	_luce.shadow_enabled = false
	_sfera.add_child(_luce)


## Ogni frame dal mago, col secondo di clip.
func aggiorna(t : float) -> void:
	if _spento or _scheletro == null or not is_instance_valid(_scheletro) or _mani.has(-1):
		return
	var a := _scheletro.global_transform * _scheletro.get_bone_global_pose(_mani[0]).origin
	var b := _scheletro.global_transform * _scheletro.get_bone_global_pose(_mani[1]).origin
	var centro := (a + b) * 0.5
	_sfera.global_position = centro
	## Quanto e' carica: sale nella raccolta, resta piena nella discesa.
	var k := clampf((t - RACCOLTA) / (DISCESA - RACCOLTA), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var pulsa := 1.0 + 0.12 * sin(t * 18.0)
	var raggio := lerpf(0.05, 0.32, k) * pulsa
	if t >= DISCESA:
		raggio *= 1.15
	_sfera.scale = Vector3.ONE * raggio
	(_sfera.material_override as ShaderMaterial).set_shader_parameter("alfa", k * (1.3 if t >= DISCESA else 1.0))
	_luce.light_energy = k * 1.6
	_richiamo.emitting = t >= RACCOLTA and t < DISCESA
	if t >= AFFONDO and not _affondato:
		_affonda(centro, t)


func _affonda(centro : Vector3, t : float) -> void:
	_affondato = true
	var terra := Vector3(centro.x, _suolo(centro), centro.z)
	_sfera.visible = false
	_richiamo.emitting = false
	_onda(terra)
	var corsa := maxf(contatto - t, 0.12)
	for p in punti:
		_vena(terra, p, corsa)
	get_tree().create_timer(corsa + 1.2).timeout.connect(queue_free)


## La quota del suolo sotto `p`: un raggio verso il basso, o la quota di `p`.
func _suolo(p : Vector3) -> float:
	var spazio := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 3.0, 1)
	var r := spazio.intersect_ray(q)
	return (r.position.y if not r.is_empty() else p.y) + 0.03


## L'onda dove le mani toccano terra: un anello che si allarga e si spegne.
func _onda(terra : Vector3) -> void:
	var anello := EcoFx._decal(EcoFx._tex_anello(colore), 0.4, colore, 3.0)
	add_child(anello)
	anello.global_position = terra
	var tw := create_tween().set_parallel(true)
	tw.tween_property(anello, "size", Vector3(3.4, 3.0, 3.4), 0.45).set_ease(Tween.EASE_OUT)
	## Si spegne l'emissione e l'albedo: `modulate` non tocca l'emissione.
	tw.tween_property(anello, "emission_energy", 0.0, 0.5)
	tw.tween_property(anello, "albedo_mix", 0.0, 0.5)


## Una vena di luce che corre radente al suolo da `da` ad `a` in `durata`:
## una goccia che lascia una scia di particelle (nel mondo, restano indietro).
func _vena(da : Vector3, a : Vector3, durata : float) -> void:
	var testa := Node3D.new()
	add_child(testa)
	testa.global_position = da
	var scia := GPUParticles3D.new()
	scia.amount = 60
	scia.lifetime = 0.5
	scia.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	scia.process_material = pm
	var goccia := QuadMesh.new()
	goccia.size = Vector2(0.12, 0.12)
	var mg := EcoFx._materiale_luce(colore)
	mg.set_shader_parameter("tondo", true)
	goccia.material = mg
	scia.draw_pass_1 = goccia
	testa.add_child(scia)
	var arrivo := Vector3(a.x, _suolo(a), a.z)
	var tw := create_tween()
	tw.tween_property(testa, "global_position", arrivo, durata).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): scia.emitting = false)


## Interruzione (colpo subito, morte): la sfera si spegne subito.
func spegni() -> void:
	if _spento:
		return
	_spento = true
	if not _affondato:
		queue_free()
