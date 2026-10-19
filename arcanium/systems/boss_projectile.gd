extends Area3D
class_name BossProjectile

const Fazioni := preload("res://arcanium/systems/fazioni.gd")

const BossVFX := preload("res://arcanium/systems/boss_vfx.gd")

## Proiettile "fuoco nero" del Senza Nome (Erosione condensata). Vola in linea retta
## nella direzione già calcolata dal boss (con lead predittivo sul movimento del
## player) e consegna danno/status per CONTATTO, con la stessa pipeline duck-typing
## del melee: al contatto col player chiama player.hit(source, move) e HealthSystem
## legge power + i campi status dalla EnemyMove. Impatta anche col mondo (colonne,
## muri) e si distrugge. Tutti i VFX sono procedurali (nessun asset esterno):
## core scuro con bordo viola (fresnel), scia di braci, luce a energia NEGATIVA
## (l'orbo SCURISCE l'ambiente mentre vola — resa naturale dell'Erosione).

## Impostati dal boss PRIMA di aggiungere alla scena.
var direction : Vector3 = Vector3.FORWARD
var speed : float = 12.0
var move : Resource            ## la EnemyMove (power + status)
var source : Node              ## il boss (attacker passato a player.hit, ed escluso dai contatti)

const LIFETIME := 4.0
const RADIUS := 0.35

var _alive : bool = true
var _age : float = 0.0

func _ready() -> void:
	# Rileva mondo (layer 1) + player (layer 2); il proiettile stesso non sta su
	# nessun layer di collisione fisica (solo monitoring dell'Area).
	collision_layer = 0
	collision_mask = 1 | 2
	monitoring = true

	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = RADIUS
	col.shape = sph
	add_child(col)

	_build_visuals()
	body_entered.connect(_on_body_entered)

func _physics_process(delta : float) -> void:
	if not _alive:
		return
	_age += delta
	if _age >= LIFETIME:
		_dissipate()
		return
	global_position += direction * speed * delta

func _on_body_entered(body : Node) -> void:
	if not _alive or body == source:
		return
	# Bersaglio valido? consegna il colpo con la stessa firma del melee
	# (attacker, move). Chi sia valido lo decide `Fazioni`: prima era cablato
	# su "player", il che rendeva l'orbo inservibile a chiunque non fosse il boss.
	if Fazioni.colpibile(body, source):
		body.hit(source, move)
		## La SPINTA: dopo il danno, lo spostamento. Va nel verso del volo,
		## in piano: una freccia dall'alto non schiaccia a terra, spinge via.
		var forza : float = float(move.get("spinta")) if move != null and ("spinta" in move) else 0.0
		if forza > 0.0 and body.has_method("spingi"):
			var verso := Vector3(direction.x, 0.0, direction.z)
			if verso.length() > 0.01:
				body.spingi(verso.normalized(), forza)
	# Contro qualunque corpo (player o mondo) l'orbo si consuma.
	_impact()

## ─── Fine vita ───────────────────────────────────────────────────────────────
## Raggio entro cui l'orbo sfonda i prop distruttibili, e quanto danno gli fa.
##
## ⚠️ Il danno ai MURI è un numero suo, scollegato da `move.power`. Il danno ai
## personaggi è tarato sulla curva degli HP del gioco e cambia con la fase e col
## bilanciamento; una colonna invece deve venire giù in un paio di orbi sempre,
## o l'arena si trasforma quando capita invece che quando il giocatore lo vede
## succedere. Sono due economie diverse e vanno tenute separate.
const DANNO_STRUTTURE := 30.0
const RAGGIO_STRUTTURE := 2.2

func _impact() -> void:
	if not _alive:
		return
	_alive = false
	## L'orbo sfonda: se ha preso una colonna, quella viene giù.
	OggettoDistruttibile.colpisci_intorno(self, global_position,
			RAGGIO_STRUTTURE, DANNO_STRUTTURE)
	_burst()
	_fade_and_free()

func _dissipate() -> void:
	# Fine vita "morbida" (timeout senza colpire nulla): niente burst, solo dissolvenza.
	if not _alive:
		return
	_alive = false
	_fade_and_free()

func _fade_and_free() -> void:
	# Ferma il moto, nasconde il visuale e libera dopo un attimo. NON si scala a zero
	# la radice: una basi con determinante 0 rende non invertibile la trasformata e
	# Godot spamma "det == 0" quando calcola i transform dei figli (luce/core). Il
	# burst d'impatto vive come nodo indipendente reparentato al mondo (vedi _burst).
	set_deferred("monitoring", false)
	visible = false
	get_tree().create_timer(0.05).timeout.connect(queue_free)

## ─── VFX ─────────────────────────────────────────────────────────────────────
func _build_visuals() -> void:
	# Core: sfera quasi nera con bordo viola emissivo (fresnel). Unshaded così il
	# "nero" non viene schiarito dall'illuminazione dell'arena.
	var core := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	core.mesh = mesh
	var mat := ShaderMaterial.new()
	## ⚠️ Shader CONDIVISO, non uno nuovo per proiettile.
	## Prima qui c'era `Shader.new()` + `sh.code = ...` a ogni `_build_visuals`:
	## ogni palla di fuoco creava una Shader Resource nuova, e una Shader nuova
	## è una COMPILAZIONE nuova per il driver — non basta che il testo sia
	## identico, la cache è per risorsa. Con un boss che spara a ripetizione
	## significa un micro-hitch a ogni colpo, proprio nel momento in cui il
	## player deve reagire. Compilato una volta sola e riusato da tutti.
	mat.shader = _core_shader()
	core.material_override = mat
	add_child(core)

	# Luce a energia NEGATIVA: sottrae luce → alone scuro che viaggia con l'orbo.
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.15, 0.9)
	light.light_negative = true
	light.light_energy = 1.6
	light.omni_range = 4.5
	add_child(light)

	# Scia: braci viola scure che restano indietro.
	var trail := GPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.6
	trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.15
	pm.scale_max = 0.4
	pm.color = Color(0.35, 0.08, 0.5)
	trail.process_material = pm
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(0.3, 0.3)
	# Texture solo per la FORMA della brace: blend MIX e colori sotto 1.0, altrimenti
	# l'orbo brillerebbe invece di scurire (vedi commento in testa al file).
	qmesh.material = BossVFX.dark_particle_material(BossVFX.TEX_SMOKE, Color(0.35, 0.08, 0.5))
	trail.draw_pass_1 = qmesh
	add_child(trail)

func _burst() -> void:
	# Esplosione one-shot all'impatto: braci scure che schizzano radialmente. Vive
	# come nodo INDIPENDENTE reparentato al mondo, così sopravvive al queue_free
	# dell'orbo e finisce la sua animazione.
	var impact_pos := global_position   # catturato ORA (l'orbo è ancora nell'albero)
	var burst := GPUParticles3D.new()
	burst.amount = 60
	burst.lifetime = 0.7
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.scale_min = 0.1
	pm.scale_max = 0.35
	pm.color = Color(0.4, 0.1, 0.55)
	burst.process_material = pm
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(0.25, 0.25)
	qmesh.material = BossVFX.dark_particle_material(BossVFX.TEX_SPARK, Color(0.4, 0.1, 0.55))
	burst.draw_pass_1 = qmesh
	# Reparent al genitore dell'orbo (arena) prima che l'orbo sparisca. La posizione
	# si imposta SOLO dopo add_child (prima il nodo non è nell'albero).
	var host := get_parent()
	if host:
		host.add_child(burst)
		burst.global_position = impact_pos
		burst.emitting = true
		# Autodistruzione del burst dopo la sua durata.
		get_tree().create_timer(1.0).timeout.connect(burst.queue_free)

## Istanza unica della Shader del nucleo, compilata al primo proiettile e poi
## riusata da tutti (vedi commento in _build_visuals).
static var _core_shader_cached : Shader = null

static func _core_shader() -> Shader:
	if _core_shader_cached == null:
		_core_shader_cached = Shader.new()
		_core_shader_cached.code = _CORE_SHADER
	return _core_shader_cached

const _CORE_SHADER := "shader_type spatial;\n" + \
	"render_mode unshaded, cull_disabled;\n" + \
	"uniform vec3 core_color : source_color = vec3(0.02, 0.0, 0.04);\n" + \
	"uniform vec3 rim_color : source_color = vec3(0.6, 0.12, 0.95);\n" + \
	"void fragment() {\n" + \
	"    float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);\n" + \
	"    ALBEDO = mix(core_color, rim_color, fres);\n" + \
	"    EMISSION = rim_color * fres * 2.5;\n" + \
	"}\n"
