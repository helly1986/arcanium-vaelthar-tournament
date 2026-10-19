extends Area3D
class_name IceShardProjectile

const Fazioni := preload("res://arcanium/systems/fazioni.gd")

## preload per PATH (vedi nota in spell_aoe_field.gd).
const ArcaniumVFX := preload("res://arcanium/systems/vfx/arcanium_vfx.gd")
const BossVFX := preload("res://arcanium/systems/boss_vfx.gd")

## Proiettile del player per gli incantesimi a distanza (Shard di Ghiaccio e,
## in futuro, altre spell Crio che condividono questo contratto). Vola in
## linea retta lungo `direction` a `speed`, consegna danno + build-up di
## Congelamento per CONTATTO col bersaglio, poi si autodistrugge. Ricalca lo
## schema di boss_projectile.gd (Area3D monitor-only + duck-typing su `.hit`).
## Chi possa essere ferito NON è più scritto qui: lo decide `Fazioni` a partire
## dal `caster`, la stessa risposta che danno il muro e il proiettile del boss.
##
## Il colpo arriva al bersaglio con la stessa firma della pipeline melee:
## `target.hit(caster, info)`, dove `info` è un oggetto duck-typed che espone
## `.power`, `.damage_type` e `.frozen_buildup` — letti rispettivamente da
## ArcaniumHealthSystem._final_damage() e ._route_statuses().

## Impostati da SpellCaster PRIMA di aggiungere alla scena.
var direction : Vector3 = Vector3.FORWARD
var speed : float = 17.0
var damage : int = 12
var radius : float = 0.26
var lifetime : float = 1.6
var color : Color = Color("#9fe6ff")
var frozen_buildup : float = 0.0
var damage_type : String = "CRIO"
## Rollio attorno all'asse di volo (rad/s), puramente estetico.
var spin_speed : float = 6.0
## Il caster: da lui si deduce la FAZIONE (vedi `Fazioni`), oltre a servire come
## attacker passato a `.hit`. Va impostato sempre — un proiettile senza caster
## non ha schieramento e ferirebbe chiunque, compreso chi l'ha lanciato.
var caster : Node

var _alive : bool = true
var _age : float = 0.0

## Oggetto duck-typed passato a target.hit(caster, info). Usiamo una Resource
## leggera invece di un Dictionary perché ArcaniumHealthSystem/EquipmentResource
## leggono i campi con `"campo" in _by_what` (funziona anche su Dictionary, ma
## Resource è coerente col contratto usato da armi/mosse nemiche esistenti).
class ImpactInfo extends Resource:
	var power : int = 0
	var damage_type : String = "CRIO"
	var frozen_buildup : float = 0.0

func _ready() -> void:
	# Rileva solo i "targets" (nemici/boss, layer 2 nel template originale è il
	# player: qui monitoriamo via GRUPPO, non layer fisico, perché i nemici non
	# hanno tutti lo stesso collision_layer garantito — coerente col fatto che
	# controlliamo comunque is_in_group prima di applicare il colpo).
	collision_layer = 0
	collision_mask = 1 | 2 | 4
	monitoring = true

	## Lo schiocco del ghiaccio che si stacca. Suona alla NASCITA della scheggia,
	## non all'impatto: e' il suono del distacco, ed e' anche l'unico istante in
	## cui il giocatore ha bisogno di un riscontro (l'impatto lo vede).
	Suoni.nel_mondo(self, Suoni.ICE_SHARD)

	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	col.shape = sph
	add_child(col)

	_build_visuals()
	_orient_to_flight()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_expired)

func _physics_process(delta : float) -> void:
	if not _alive:
		return
	_age += delta
	global_position += direction * speed * delta
	## Rollio lento attorno all'asse di volo: fa scintillare le facce della lama
	## senza cambiarne la traiettoria.
	rotate_object_local(Vector3.BACK, spin_speed * delta)

func _on_body_entered(body : Node) -> void:
	_try_hit(body)

func _on_area_entered(area : Area3D) -> void:
	_try_hit(area)

func _try_hit(node : Node) -> void:
	if not _alive or node == caster or node == self:
		return
	# Chi si può ferire lo decide `Fazioni`, non questo file: la regola "mai i
	# propri" era scritta qui a mano e in altre tre forme diverse altrove.
	if Fazioni.colpibile(node, caster):
		var info := ImpactInfo.new()
		info.power = damage
		info.damage_type = damage_type
		info.frozen_buildup = frozen_buildup
		node.hit(caster, info)
		_impact()
		return
	# Contatto col mondo (muri/colonne): si consuma senza infliggere danno.
	if node is Node3D and node.is_in_group("world_geometry"):
		_impact()

func _on_lifetime_expired() -> void:
	_dissipate()

func _impact() -> void:
	if not _alive:
		return
	_alive = false
	## La lama si SPACCA: scoppio secco di schegge + brina a terra.
	_shatter_vfx(1.0)
	_fade_and_free()

func _dissipate() -> void:
	if not _alive:
		return
	_alive = false
	## Fine vita senza bersaglio: stesso scoppio ma dimezzato e senza brina a
	## terra. Sono due EVENTI diversi e devono leggersi diversi — se colpire e
	## mancare fanno lo stesso rumore visivo, il player non impara nulla.
	_shatter_vfx(0.45)
	_fade_and_free()

func _fade_and_free() -> void:
	set_deferred("monitoring", false)
	visible = false
	get_tree().create_timer(0.05).timeout.connect(queue_free)

## ─── VFX ─────────────────────────────────────────────────────────────────────
## Forma: una LAMA di ghiaccio — nessun manico, nessuna guardia: un coltello
## grezzo strappato al gelo. Costruita a mano come bipiramide allungata a
## sezione romboidale (4 spigoli), quindi con una vera lucentezza a faccette
## invece della sfera-placeholder di prima.
func _build_visuals() -> void:
	var blade := MeshInstance3D.new()
	blade.mesh = _build_blade_mesh()
	## SHADER, non StandardMaterial3D: l'arena è buia e low-albedo, quindi un
	## ghiaccio "fisico" (albedo chiaro, roughness bassa) non avrebbe nulla da
	## riflettere e sparirebbe. ice_crystal.gdshader dà volume con due cose che
	## NON dipendono dalla luce di scena: fresnel sui bordi (silhouette vetrosa)
	## e vene interne procedurali in spazio-mondo — necessarie perché la mesh
	## della lama è generata in SurfaceTool e non ha UV utili.
	## `rim` di StandardMaterial3D faceva una cosa simile ma solo dove c'è luce:
	## il fresnel qui è emissivo e regge anche al buio pieno.
	blade.material_override = ArcaniumVFX.ice_crystal_material(color, 2.0, 0.60)
	blade.name = "Lama"
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blade)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 3.0
	## Un proiettile può essere in volo insieme ad altri: nessuna ombra, o
	## l'atlas delle ombre si satura e comincia a sfarfallare.
	light.shadow_enabled = false
	add_child(light)

	## ALONE. Verificato dalla camera iso: a quella distanza (offset 0/28/22) la
	## lama da sola è una scheggia di pochi pixel e sul pavimento chiaro dell'arena
	## si perde. L'alone è un billboard che NON ruota col rollio della lama, quindi
	## dà una presenza costante mentre le faccette scintillano.
	## Additivo e piccolo: deve far VEDERE il proiettile, non accecare la zona.
	var halo := MeshInstance3D.new()
	halo.name = "Alone"
	var hq := QuadMesh.new()
	hq.size = Vector2(radius * 6.5, radius * 6.5)
	## Energia BASSA (verificata a schermo): additivo + energia alta satura al
	## centro e l'alone smette di essere un alone — diventa un quadrato bianco
	## col bordo netto della texture, che nasconde la lama invece di mostrarla.
	## Deve stare SOTTO la saturazione: alone morbido, lama leggibile dentro.
	hq.material = BossVFX.particle_material(BossVFX.TEX_GLOW, color, 0.55)
	halo.mesh = hq
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	## SCIA DI BRINA: cristalli che restano sospesi dove la lama è passata e si
	## spengono lentamente. `local_coords = false` è ciò che li fa RIMANERE
	## indietro invece di viaggiare col proiettile.
	var trail := GPUParticles3D.new()
	trail.name = "SciaBrina"
	trail.amount = 64
	trail.lifetime = 0.7
	trail.local_coords = false
	trail.explosiveness = 0.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.ZERO
	pm.spread = 25.0
	## Quasi fermi: la brina si stacca e resta lì, non viene sparata via.
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	## Un filo di gravità: i cristalli scendono appena, come polvere di gelo.
	pm.gravity = Vector3(0, -0.35, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.0
	pm.scale_min = 0.05
	pm.scale_max = 0.16
	## Rimpiccioliscono mentre svaniscono.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = curve
	pm.scale_curve = scale_curve
	pm.color = Color(color.r, color.g, color.b, 0.7)
	trail.process_material = pm
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(radius * 0.9, radius * 0.9)
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	trail_mat.albedo_color = Color(1, 1, 1, 0.9)
	trail_mat.emission_enabled = true
	trail_mat.emission = color
	qmesh.material = trail_mat
	trail.draw_pass_1 = qmesh
	add_child(trail)

## ─── Impatto: la scheggia si spacca ─────────────────────────────────────────
## Prima l'impatto era MUTO (visible = false e via): il colpo arrivava senza che
## niente lo dicesse a schermo. Lo scoppio è parentato al GENITORE, non a self,
## altrimenti morirebbe insieme al proiettile 0.05 s dopo.
##
## In isometrica lo scoppio si legge male se resta tutto all'altezza del petto:
## per questo l'impatto pieno lascia anche una MACCHIA DI BRINA a terra, che è
## il piano che la camera inquadra meglio, e che sopravvive un attimo al colpo.
func _shatter_vfx(intensity : float) -> void:
	var host := get_parent()
	if host == null:
		return
	var p := GPUParticles3D.new()
	host.add_child(p)
	p.global_position = global_position
	p.amount = int(round(48.0 * intensity)) + 8
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.6
	## Le schegge partono all'INDIETRO rispetto al volo (cono di rimbalzo): è la
	## lettura fisica di una punta che si sfascia contro qualcosa.
	pm.direction = -direction.normalized() if direction.length() > 0.001 else Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 2.0 * intensity
	pm.initial_velocity_max = 7.0 * intensity
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.05
	pm.scale_max = 0.18
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.20)
	qm.material = BossVFX.particle_material(BossVFX.TEX_SPARK, color, 3.0)
	p.draw_pass_1 = qm
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

	if intensity >= 0.9:
		_frost_splat(host)

## Macchia di brina a terra sotto il punto d'impatto. Decal, come gli anelli del
## boss e del minion: è il segno che in isometrica si legge sempre.
func _frost_splat(host : Node) -> void:
	var d := Decal.new()
	host.add_child(d)
	d.global_position = Vector3(global_position.x, global_position.y, global_position.z)
	## Verificato dalla IsoCam: con SOLO l'emissivo a 3.0 la macchia si leggeva
	## come un puntino BIANCO acceso — il centro della soft_glow satura e la
	## tinta ciano sopravvive solo nell'alone, quindi l'impatto diceva "qui c'è
	## una lampada", non "qui c'è brina". Serve anche una VERA tinta sul
	## pavimento: `albedo_mix` non faceva nulla perché `texture_albedo` era null.
	d.texture_albedo = BossVFX.TEX_GLOW
	d.albedo_mix = 0.75
	d.texture_emission = BossVFX.TEX_GLOW
	d.emission_energy = 1.5
	d.modulate = color
	## Alto abbastanza da proiettarsi sul pavimento anche se l'impatto avviene
	## all'altezza del petto (il Decal proietta lungo il proprio -Y).
	d.size = Vector3(1.6, 4.0, 1.6)
	## Le decal NON devono appiccicarsi ai personaggi che ci passano sopra:
	## il layer 2 è quello dei corpi nel template.
	d.cull_mask = 1
	d.scale = Vector3(0.4, 1.0, 0.4)
	var tw := d.create_tween()
	tw.set_parallel(true)
	tw.tween_property(d, "scale", Vector3.ONE, 0.16) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(d, "emission_energy", 0.0, 0.9) \
		.set_delay(0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	## Anche la tinta sul pavimento deve svanire, o l'ultimo frame prima del
	## queue_free è una macchia piena che sparisce di colpo.
	tw.tween_property(d, "albedo_mix", 0.0, 0.9) \
		.set_delay(0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(d.queue_free)

## Bipiramide a sezione romboidale, punta lungo +Z (la direzione di volo:
## `_orient_to_flight` allinea il +Z del proiettile a `direction`).
## `radius` governa lo spessore, la lunghezza è ~4.5× così legge da lama e non
## da scaglia.
func _build_blade_mesh() -> ArrayMesh:
	var half_w := radius * 0.55      # semi-larghezza (lo spigolo tagliente)
	var half_t := radius * 0.22      # semi-spessore (la costola centrale)
	var tip := radius * 3.4          # punta, in avanti
	var tail := radius * 1.1         # coda, indietro

	# Anello centrale (il punto più largo della lama) + punta e coda.
	var p_tip := Vector3(0, 0, tip)
	var p_tail := Vector3(0, 0, -tail)
	var ring := [
		Vector3(half_w, 0, 0),
		Vector3(0, half_t, 0),
		Vector3(-half_w, 0, 0),
		Vector3(0, -half_t, 0),
	]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a : Vector3 = ring[i]
		var b : Vector3 = ring[(i + 1) % 4]
		# Falda verso la punta
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(p_tip)
		# Falda verso la coda (avvolgimento invertito per tenere le normali fuori)
		st.add_vertex(b); st.add_vertex(a); st.add_vertex(p_tail)
	st.generate_normals()
	return st.commit()

## Punta la lama lungo la traiettoria: `Basis.looking_at` allinea il -Z al
## vettore passato, quindi si passa -direction per mettere il +Z (la punta,
## vedi _build_blade_mesh) nel verso del volo.
func _orient_to_flight() -> void:
	if direction.length() < 0.0001:
		return
	var d := direction.normalized()
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(-d, up), global_position)
