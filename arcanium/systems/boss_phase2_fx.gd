extends RefCounted
class_name BossPhase2FX

## VFX procedurali per la transizione/fase 2 del boss "Senza Nome".
##
## Riusa i materiali/texture condivisi in `BossVFX` (res://arcanium/systems/boss_vfx.gd).
## Nessuna dipendenza da arcanium_boss.gd: le factory qui sotto restituiscono
## semplicemente nodi già pronti da parentare al boss.

const ERA_VIOLA      := Color(0.75, 0.3, 1.0)
const ERA_VIOLA_CHIARO := Color(0.88, 0.55, 1.0)
const ERA_VIOLA_SCURO  := Color(0.5, 0.15, 0.75)

const BOSS_ALTEZZA_M := 3.0
const BOSS_CENTRO_Y  := 1.3

## Script minimale inline per l'auto-free: viene assegnato al nodo radice
## restituito da `charge_sphere`. In `_ready` parte un Timer one-shot che,
## allo scadere, avvia un fade (scale down + stop emitting) e poi si libera.
## Scelto invece di `get_tree().create_timer()` perché il metodo che crea il
## nodo è STATICO e non ha un albero di scena proprio da cui pescare un
## SceneTreeTimer; un Timer figlio funziona appena il nodo entra nell'albero
## (lo fa `host` quando lo aggiungo lì), è robusto anche se il chiamante
## sposta/rinomina il nodo, e non richiede polling da fuori.
class ChargeSphereLifecycle extends Node3D:
	var lifetime := 2.6
	var fade_time := 0.35
	var _timer : Timer
	var _particles : Array = []

	func _ready() -> void:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.wait_time = max(lifetime, 0.05)
		add_child(_timer)
		_timer.timeout.connect(_on_lifetime_done)
		_timer.start()

	func _on_lifetime_done() -> void:
		for p in _particles:
			if is_instance_valid(p):
				p.emitting = false
		var fade_timer := Timer.new()
		fade_timer.one_shot = true
		fade_timer.wait_time = max(fade_time, 0.05)
		add_child(fade_timer)
		fade_timer.timeout.connect(queue_free)
		fade_timer.start()


## Esplosione di CARICA: sfera viola densa e avvolgente che converge verso il
## boss, con un core pulsante e scintille. Parented a `host`, si auto-distrugge
## dopo `duration` (+ una breve dissolvenza).
static func charge_sphere(host: Node3D, duration: float) -> Node3D:
	var root := ChargeSphereLifecycle.new()
	root.name = "ChargeSphereFX"
	root.lifetime = duration
	host.add_child(root)
	root.position = Vector3(0, BOSS_CENTRO_Y, 0)

	# --- Shell convergente: particelle che nascono su una sfera larga e
	# vengono "risucchiate" verso il centro. Densa e spammosa come richiesto.
	var shell := GPUParticles3D.new()
	shell.name = "ConvergingShell"
	shell.local_coords = true
	shell.amount = 220
	shell.lifetime = 0.9
	shell.explosiveness = 0.15
	shell.randomness = 0.35
	shell.emitting = true

	var shell_mat := ParticleProcessMaterial.new()
	shell_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	shell_mat.emission_sphere_radius = 2.6
	shell_mat.direction = Vector3(0, 0, 0)
	shell_mat.spread = 180.0
	shell_mat.initial_velocity_min = 0.0
	shell_mat.initial_velocity_max = 0.3
	# Gravity punta verso il centro locale: forte attrazione centripeta.
	shell_mat.gravity = Vector3(0, 0, 0)
	shell_mat.radial_accel_min = -9.0
	shell_mat.radial_accel_max = -6.0
	shell_mat.tangential_accel_min = -1.0
	shell_mat.tangential_accel_max = 1.0
	shell_mat.scale_min = 0.25
	shell_mat.scale_max = 0.6
	var shell_scale_curve := CurveTexture.new()
	var shell_curve := Curve.new()
	shell_curve.add_point(Vector2(0.0, 0.2))
	shell_curve.add_point(Vector2(0.6, 1.0))
	shell_curve.add_point(Vector2(1.0, 0.0))
	shell_scale_curve.curve = shell_curve
	shell_mat.scale_curve = shell_scale_curve
	shell_mat.color = ERA_VIOLA
	shell.process_material = shell_mat

	var shell_mesh := QuadMesh.new()
	shell_mesh.size = Vector2(0.5, 0.5)
	shell_mesh.material = BossVFX.particle_material(BossVFX.TEX_ENERGY, ERA_VIOLA_CHIARO, 2.8)
	shell.draw_pass_1 = shell_mesh

	root.add_child(shell)
	root._particles.append(shell)

	# --- Core pulsante: bagliore centrale che respira.
	var core := GPUParticles3D.new()
	core.name = "PulsingCore"
	core.local_coords = true
	core.amount = 24
	core.lifetime = 0.5
	core.explosiveness = 0.0
	core.randomness = 0.4
	core.emitting = true

	var core_mat := ParticleProcessMaterial.new()
	core_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	core_mat.emission_sphere_radius = 0.35
	core_mat.direction = Vector3(0, 1, 0)
	core_mat.spread = 180.0
	core_mat.initial_velocity_min = 0.0
	core_mat.initial_velocity_max = 0.2
	core_mat.gravity = Vector3.ZERO
	core_mat.scale_min = 1.2
	core_mat.scale_max = 2.0
	var core_scale_curve := CurveTexture.new()
	var core_curve := Curve.new()
	core_curve.add_point(Vector2(0.0, 0.3))
	core_curve.add_point(Vector2(0.5, 1.0))
	core_curve.add_point(Vector2(1.0, 0.3))
	core_scale_curve.curve = core_curve
	core_mat.scale_curve = core_scale_curve
	core_mat.color = ERA_VIOLA_CHIARO
	core.process_material = core_mat

	var core_mesh := QuadMesh.new()
	core_mesh.size = Vector2(1.0, 1.0)
	core_mesh.material = BossVFX.particle_material(BossVFX.TEX_GLOW, ERA_VIOLA_CHIARO, 3.2)
	core.draw_pass_1 = core_mesh

	root.add_child(core)
	root._particles.append(core)

	# --- Scintille: pop veloci che vendono energia instabile.
	var sparks := GPUParticles3D.new()
	sparks.name = "ChargeSparks"
	sparks.local_coords = true
	sparks.amount = 90
	sparks.lifetime = 0.6
	sparks.explosiveness = 0.05
	sparks.randomness = 0.6
	sparks.emitting = true

	var sparks_mat := ParticleProcessMaterial.new()
	sparks_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	sparks_mat.emission_sphere_radius = 2.2
	sparks_mat.direction = Vector3(0, 0, 0)
	sparks_mat.spread = 180.0
	sparks_mat.initial_velocity_min = 0.5
	sparks_mat.initial_velocity_max = 1.5
	sparks_mat.radial_accel_min = -7.0
	sparks_mat.radial_accel_max = -4.0
	sparks_mat.scale_min = 0.1
	sparks_mat.scale_max = 0.3
	sparks_mat.color = ERA_VIOLA_SCURO
	sparks.process_material = sparks_mat

	var sparks_mesh := QuadMesh.new()
	sparks_mesh.size = Vector2(0.2, 0.2)
	sparks_mesh.material = BossVFX.particle_material(BossVFX.TEX_SPARK, ERA_VIOLA_CHIARO, 3.0)
	sparks.draw_pass_1 = sparks_mesh

	root.add_child(sparks)
	root._particles.append(sparks)

	return root


## Marcatore PERSISTENTE di fase 2: aura viola discreta + braci lente che
## salgono. Parented a `host`, vive finché il chiamante non fa `queue_free()`.
static func phase2_aura(host: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Phase2AuraFX"
	host.add_child(root)
	root.position = Vector3(0, BOSS_CENTRO_Y, 0)

	# --- Foschia: nebbia bassa densità che avvolge senza coprire.
	var mist := GPUParticles3D.new()
	mist.name = "AuraMist"
	mist.local_coords = true
	mist.amount = 14
	mist.lifetime = 3.0
	mist.explosiveness = 0.0
	mist.randomness = 0.5
	mist.emitting = true

	var mist_mat := ParticleProcessMaterial.new()
	mist_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mist_mat.emission_sphere_radius = 1.0
	mist_mat.direction = Vector3(0, 1, 0)
	mist_mat.spread = 40.0
	mist_mat.initial_velocity_min = 0.05
	mist_mat.initial_velocity_max = 0.15
	mist_mat.gravity = Vector3(0, 0.05, 0)
	mist_mat.scale_min = 1.5
	mist_mat.scale_max = 2.5
	var mist_scale_curve := CurveTexture.new()
	var mist_curve := Curve.new()
	mist_curve.add_point(Vector2(0.0, 0.0))
	mist_curve.add_point(Vector2(0.2, 1.0))
	mist_curve.add_point(Vector2(0.8, 1.0))
	mist_curve.add_point(Vector2(1.0, 0.0))
	mist_scale_curve.curve = mist_curve
	mist_mat.scale_curve = mist_scale_curve
	mist_mat.color = Color(ERA_VIOLA.r, ERA_VIOLA.g, ERA_VIOLA.b, 0.35)
	mist.process_material = mist_mat

	var mist_mesh := QuadMesh.new()
	mist_mesh.size = Vector2(1.5, 1.5)
	mist_mesh.material = BossVFX.particle_material(BossVFX.TEX_SMOKE, ERA_VIOLA, 0.9)
	mist.draw_pass_1 = mist_mesh

	root.add_child(mist)

	# --- Braci: piccole scintille che salgono lente lungo il corpo.
	var embers := GPUParticles3D.new()
	embers.name = "AuraEmbers"
	embers.local_coords = true
	embers.amount = 10
	embers.lifetime = 2.5
	embers.explosiveness = 0.0
	embers.randomness = 0.6
	embers.emitting = true

	var embers_mat := ParticleProcessMaterial.new()
	embers_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	embers_mat.emission_box_extents = Vector3(0.6, BOSS_ALTEZZA_M * 0.4, 0.6)
	embers_mat.direction = Vector3(0, 1, 0)
	embers_mat.spread = 15.0
	embers_mat.initial_velocity_min = 0.25
	embers_mat.initial_velocity_max = 0.5
	embers_mat.gravity = Vector3(0, 0.15, 0)
	embers_mat.scale_min = 0.15
	embers_mat.scale_max = 0.3
	var embers_scale_curve := CurveTexture.new()
	var embers_curve := Curve.new()
	embers_curve.add_point(Vector2(0.0, 0.0))
	embers_curve.add_point(Vector2(0.15, 1.0))
	embers_curve.add_point(Vector2(1.0, 0.0))
	embers_scale_curve.curve = embers_curve
	embers_mat.scale_curve = embers_scale_curve
	embers_mat.color = ERA_VIOLA_CHIARO
	embers.process_material = embers_mat

	var embers_mesh := QuadMesh.new()
	embers_mesh.size = Vector2(0.18, 0.18)
	embers_mesh.material = BossVFX.particle_material(BossVFX.TEX_SPARK, ERA_VIOLA_CHIARO, 2.5)
	embers.draw_pass_1 = embers_mesh

	root.add_child(embers)

	return root
