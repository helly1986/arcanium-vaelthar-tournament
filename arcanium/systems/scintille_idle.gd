extends BoneAttachment3D

## ═══════════════════════════════════════════════════════════════════════════
## SCINTILLE DELL'IDLE — una pioggia di scintille in un momento dell'idle
## ═══════════════════════════════════════════════════════════════════════════
##
## Kessra stringe il ribattino del giogo e dà un giro di vite: «cade una
## piccola pioggia di scintille» (docs/campioni_concept.md). Agganciata
## all'osso delle dita (CampioneResource.idle_scintille_osso), parte quando il
## tempo dell'idle passa CampioneResource.idle_scintille.
##
## Si legge il tempo dell'idle dall'albero (player_anim_tree.gd, tempo_idle),
## non da un timer: l'idle riparte dalla Posa a ogni rientro, si ferma sotto un
## gesto e non si vede in cammino. Un timer sparerebbe scintille da una mano
## che sta tirando un fendente.
##
## Le scintille vivono nel MONDO (local_coords falso): cadono per terra mentre
## la mano si stacca, non la seguono.

const VFX := preload("res://arcanium/systems/boss_vfx.gd")
## Il ferro rovente: dal giallo bianco al rosso che si spegne.
const CALDA := Color(1.0, 0.78, 0.38)

## Il secondo dell'idle in cui partono.
var momento := -1.0
## L'albero del player (AnimationTreeSoulsBase).
var albero : Node = null
## Quante volte sono partite: per i cancelli.
var partite := 0

var _particelle : GPUParticles3D
var _bagliore : OmniLight3D
var _prima := -1.0


func _ready() -> void:
	_particelle = GPUParticles3D.new()
	_particelle.name = "Scintille"
	_particelle.one_shot = true
	_particelle.emitting = false
	_particelle.amount = 40
	_particelle.lifetime = 0.7
	_particelle.explosiveness = 0.85
	_particelle.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.01
	## Schizzano in avanti e in fuori dalla borchia, poi cadono.
	m.direction = Vector3(0, 0.3, 1)
	m.spread = 70.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 1.3
	m.gravity = Vector3(0, -9.8, 0)
	m.damping_min = 0.5
	m.damping_max = 1.5
	m.scale_min = 0.5
	m.scale_max = 1.0
	var g := Gradient.new()
	## Moltiplica il colore del materiale (CALDA): dal giallo al rosso.
	g.set_color(0, Color(1.0, 1.0, 0.9, 1.0))
	g.add_point(0.4, Color(1.0, 0.6, 0.25, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.8, 0.15, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	_particelle.process_material = m
	var q := QuadMesh.new()
	## A 1,8 cm e bianche si perdevano nella camera di gioco: puntini sul
	## petto (2026-10-27).
	q.size = Vector2(0.035, 0.035)
	var mat := VFX.particle_material(VFX.TEX_SPARK, CALDA, 2.5)
	## Con BILLBOARD_ENABLED la scala delle particelle si perde.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	_particelle.draw_pass_1 = q
	add_child(_particelle)
	## Il guizzo del ferro sul petto, un quarto di secondo: a 1,8 di energia e
	## 0,6 m sbiancava il viso.
	_bagliore = OmniLight3D.new()
	_bagliore.light_color = CALDA
	_bagliore.light_energy = 0.0
	_bagliore.omni_range = 0.4
	_bagliore.shadow_enabled = false
	add_child(_bagliore)


func _process(_delta : float) -> void:
	if albero == null or momento < 0.0 or not albero.has_method("tempo_idle"):
		return
	var t : float = albero.tempo_idle()
	## Il passaggio dal momento giusto, una volta per giro: da prima a dopo,
	## senza contare il ritorno a zero del loop o il rientro dalla Posa.
	if _prima >= 0.0 and t >= 0.0 and _prima < momento and t >= momento and t - _prima < 0.5:
		_particelle.restart()
		_bagliore.light_energy = 0.8
		create_tween().tween_property(_bagliore, "light_energy", 0.0, 0.3)
		partite += 1
	_prima = t
