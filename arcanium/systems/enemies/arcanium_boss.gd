extends "res://arcanium/systems/enemies/arcanium_humanoid_enemy.gd"
class_name ArcaniumBoss

## `preload` e non il class_name: la registrazione dei class_name dipende dallo
## scan dell'editor, che su questo progetto non attecchisce sempre (stesso
## motivo per cui la superclasse si estende per PATH).
const BladeTrail := preload("res://arcanium/systems/blade_trail.gd")

## ═══════════════════════════════════════════════════════════════════════════
## BOSS — il Senza Nome
## ═══════════════════════════════════════════════════════════════════════════
##
## Un umanoide armato (tutto il combattimento di base sta in
## ArcaniumHumanoidEnemy) più ciò che rende un boss un boss:
##
##   • FASE 2: sotto soglia HP una transizione forzata, immortale, con blast
##     radiale e aura persistente; da lì catene più lunghe e gruppi pesanti.
##   • MOSSE A DISTANZA: proiettili con mira predittiva, scelte solo se c'è
##     linea di tiro, con un VFX di carica sulla mano che è IL tell.
##   • SCARICHE RADIALI e MURI DI FUOCO nati lungo la traiettoria della lama.
##   • Pesi decisionali che leggono il movimento del player (chi kita va punito).
##
## Il flag `_invulnerable` vale SOLO durante la transizione di fase: un boss
## immortale in qualunque altro momento sarebbe un bug, non un design.

const BossVFX := preload("res://arcanium/systems/boss_vfx.gd")

## `cast_origin` (origine di spell e proiettili, e del VFX di carica) sta
## nell'umanoide dal 2026-09-12, insieme a linea di tiro e mira predittiva:
## l'arciere Sylvorn e' il secondo che spara, e il codice e' uno.

# ─── Balzo e scivolata ───────────────────────────────────────────────────────
## Balzo agganciato in corso (la mossa e fino a quando).
var _leap_move : EnemyMove = null
var _leap_until : float = 0.0
## Scivolata al rilascio (prese: raggiunge il player che si è allontanato di poco
## durante un windup lungo).
var _slide_move : EnemyMove = null
var _slide_until : float = 0.0
const RELEASE_SLIDE_TIME := 0.28
## Non superare questa distanza dal player: niente compenetrazione.
const RELEASE_SLIDE_GAP := 0.7
## Dove atterra il balzo rispetto a te: non ADDOSSO, o finisce a distanza zero,
## proprio la banda in cui le sue spadate mancano.
const LEAP_LAND_OFFSET := 1.5
const LEAP_MAX_SPEED := 22.0

# ─── Fase 2 ──────────────────────────────────────────────────────────────────
var _phase2_started : bool = false   # transizione già avvenuta (one-shot)
var _phase2_intro : bool = false     # transizione IN CORSO: blocca AI e movimento
var _invulnerable : bool = false     # immortale SOLO durante la transizione
var _phase2_aura : Node3D = null     # marcatore persistente di fase 2
const PHASE2_INTRO_CLIP := "sword/sword_burst_01"   # riusa il blast della Respinta
const PHASE2_INTRO_RELEASE_FRAC := 0.58   # dove cade il rilascio nella clip
const PHASE2_BLAST_RADIUS := 5.0     # ampio: chi resta vicino durante la carica lo prende
const PHASE2_BLAST_POWER := 24

# ─── Studio del movimento del bersaglio ──────────────────────────────────────
## Velocità orizzontale smussata del player. Alimenta due cose: il PESO
## decisionale del cast (chi arretra invita il colpo a distanza): la velocita'
## smussata del bersaglio (`_target_vel`) la tiene l'umanoide.

# ─── Muro lungo la traiettoria della lama ────────────────────────────────────
var _blade_path : PackedVector3Array = PackedVector3Array()
var _active_wall : Node3D = null

var _glow_tween : Tween


func _init() -> void:
	super._init()
	walk_speed = 2.2
	run_speed = 4.6
	aggro_range = 20.0
	run_distance = 4.5
	# Il cadavere del boss non si dissolve come quello di un comune: la sua
	# uscita di scena la governa il director del prologo.
	despawn_extra_delay = 3.0
	# Niente barretta sopra la testa: il boss ha la sua barra a fondo schermo.
	show_floating_health = false


# ═══════════════════════════════════════════════════════════════════════════
# Ciclo: fase 2, tracking, movimento in attacco
# ═══════════════════════════════════════════════════════════════════════════

func _special_state_step(delta : float) -> bool:
	if _phase2_intro:
		# Transizione: si carica sul posto (la clip è in-place), immortale.
		# Nessuna AI, nessun facing — guida tutto la coroutine _run_phase2_intro.
		_apply_gravity(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return true
	return super._special_state_step(delta)


## Transizione a fase 2, una volta sola. Arriva qui con `_busy` già falso, quindi
## NON interrompe una catena in volo: il boss finisce lo swing corrente, POI si
## carica. Più pulito, e senza race tra coroutine, che abortire una mossa a metà.
func _pre_combat_step() -> bool:
	if not _phase2_started and _in_phase2():
		_run_phase2_intro()
		return true
	return false


func _attack_motion(delta : float) -> void:
	if _busy and _leap_move != null and is_instance_valid(target) and _now() < _leap_until:
		# BALZO AGGANCIATO: mentre è per aria punta te, non la traiettoria
		# authorata — la root motion del salto porta appena +0.36 m, la clip è
		# fatta per saltare sul posto, non per chiudere una distanza. È lecito
		# SOLO qui: a mezz'aria i piedi non toccano, quindi allungare il volo non
		# produce foot-sliding; su una spadata a terra si vedrebbe.
		var rimane : float = maxf(_leap_until - _now(), 0.05)
		var dir := _flat_dir_to(target)
		var gap : float = maxf(_flat_distance(target) - LEAP_LAND_OFFSET, 0.0)
		var spd : float = clampf(gap / rimane, 0.0, LEAP_MAX_SPEED)
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
	elif _busy and _slide_move != null and is_instance_valid(target) and _now() < _slide_until:
		# SCIVOLATA AL RILASCIO (prese): scatto breve verso il player, capato
		# alla distanza `release_slide` e fermato a RELEASE_SLIDE_GAP per non
		# entrargli dentro. Chiude il piccolo gap creato durante il windup lungo,
		# così la presa lo raggiunge invece di chiudersi nel vuoto. Rispetta le
		# collisioni: è velocity, non un tween.
		var s_rem : float = maxf(_slide_until - _now(), 0.05)
		var s_dir := _flat_dir_to(target)
		var s_gap : float = maxf(_flat_distance(target) - RELEASE_SLIDE_GAP, 0.0)
		var s_spd : float = minf(s_gap, _slide_move.release_slide) / s_rem
		velocity.x = s_dir.x * s_spd
		velocity.z = s_dir.z * s_spd
	else:
		super._attack_motion(delta)


func _clear_move_state() -> void:
	super._clear_move_state()
	_leap_move = null
	_slide_move = null
	_charge_vfx_off()


# ═══════════════════════════════════════════════════════════════════════════
# Selezione delle mosse
# ═══════════════════════════════════════════════════════════════════════════

## Una mossa a distanza si sceglie solo con LINEA DI TIRO libera: un raycast
## intercettato da una colonna la scarta, e il sistema di pesi ricade da solo
## sulle melee.
func _move_is_usable(move : EnemyMove) -> bool:
	## ⚠️ `super` PRIMA di tutto: l'umanoide ci mette la trincea sotto pressione
	## (vedi `_move_is_usable` la'), e questa sovrascrittura senza `super` se la
	## portava via in silenzio. Oggi non cambia niente — il Senza Nome non ha
	## scudo, quindi non si trincera mai — ma il giorno che un mini-boss con
	## scudo eredita da qui, il meccanismo deve esserci gia'.
	return super._move_is_usable(move)


func _move_weight_multiplier(move : EnemyMove) -> float:
	if move.projectile_scene == null:
		return 1.0
	return _ranged_intent_multiplier()


## Peso della spell a distanza secondo dove sta andando il player: >1 se si
## allontana (kiting, da punire), <1 se carica (meglio prepararlo in melee).
func _ranged_intent_multiplier() -> float:
	if not is_instance_valid(target) or _target_vel.length() < 0.3:
		return 1.0
	var away := _target_vel.dot(_flat_dir_to(target))
	return clampf(1.0 + away * 0.6, 0.4, 2.2)


func _in_phase2() -> bool:
	if health_system == null or move_set == null:
		return false
	var total := float(health_system.total_health)
	return total > 0.0 and float(health_system.current_health) / total <= move_set.phase2_hp_ratio

func _max_chain() -> int:
	if move_set == null:
		return 1
	return move_set.max_chain_p2 if _in_phase2() else move_set.max_chain_p1

func _chain_mult() -> float:
	if move_set == null:
		return 1.0
	return move_set.chain_p2_mult if _in_phase2() else 1.0


# ═══════════════════════════════════════════════════════════════════════════
# Esecuzione: cariche, scariche, proiettili
# ═══════════════════════════════════════════════════════════════════════════

## Una spell o un'onda d'urto non colpiscono con la lama: niente finestra
## d'arma, il danno esce dal proiettile o dal raggio. Dichiararlo qui è ciò che
## instrada quelle mosse sul modello a istanti di contatto della superclasse.
func _move_uses_weapon(move : EnemyMove) -> bool:
	if not super._move_uses_weapon(move):
		return false
	return not (move.burst_radius > 0.0 and move.burst_frac < 0.0)


func _on_move_started(move : EnemyMove, clip_len : float) -> void:
	# Il VFX di carica deve spegnersi QUANDO parte il colpo, quindi dura fino al
	# contatto misurato — non fino al `telegraph`, che è un'altra cosa (su
	# `sword_cast_01` la differenza è poca, 1.97 contro 2.00, ma il principio è
	# che il tell e il colpo devono raccontare lo stesso istante).
	var contatti := _contact_times(move)
	var rilascio : float = contatti[0] if not contatti.is_empty() else move.telegraph
	# Stessa velocita' con cui la mossa viene RIPRODOTTA, non quella globale: se
	# la mossa ha un `anim_speed` proprio, il VFX di carica si spegnerebbe prima
	# o dopo il colpo che deve annunciare.
	var telegraph : float = rilascio / _move_speed(move)
	var is_ranged : bool = move.projectile_scene != null
	var is_burst : bool = move.burst_radius > 0.0
	# Scarica A FRAZIONE (il balzo: l'onda nasce quando la spada tocca terra) vs
	# scarica PURA (la Respinta: esplode al rilascio e non usa la lama). La prima
	# convive con la lama sulla stessa mossa, la seconda la sostituisce.
	var burst_timed : bool = is_burst and move.burst_frac >= 0.0
	var pure_burst : bool = is_burst and not burst_timed

	if burst_timed:
		_burst_at(move, clip_len * move.burst_frac)

	if move.leap_to_target:
		# Aggancio in volo: attivo fino al tocco a terra, dove esplode l'onda.
		_leap_move = move
		_leap_until = _now() + clip_len * (move.burst_frac if burst_timed else 0.5)

	if is_ranged or pure_burst:
		# Il VFX di carica sulla mano È il tell: senza, la mossa non è
		# schivabile. La clip ha il suo gesto, il VFX lo rinforza.
		_charge_vfx_on(telegraph)
		return

	if move.sword_glow:
		# La carica dura fino al RILASCIO VERO, che non è sempre il telegraph:
		# sul balzo la magia si scarica quando la spada tocca terra, quindi la
		# lama resta accesa per tutto l'arco invece di spegnersi a mezz'aria.
		_sword_glow_on(clip_len * move.burst_frac if burst_timed else telegraph, _glow_tint(move))
	if move.sword_sparks:
		_sword_sparks_on(telegraph, _glow_tint(move))


func _on_move_released(move : EnemyMove) -> void:
	if move.release_slide > 0.0:
		_slide_move = move
		_slide_until = _now() + RELEASE_SLIDE_TIME


## Sul percorso a istanti di contatto ci finiscono solo le mosse SENZA lama:
## spell e scariche pure. Il "contatto" per loro è il lancio.
func _deliver_hit(move : EnemyMove) -> void:
	if move.projectile_scene != null:
		_charge_vfx_off()
		super._deliver_hit(move)   # il tiro vero e proprio sta nell'umanoide
		return
	if move.burst_radius > 0.0 and move.burst_frac < 0.0:
		_charge_vfx_off()
		_apply_burst(move)
		return
	super._deliver_hit(move)


func _on_move_finished(_move : EnemyMove) -> void:
	_slide_move = null


func hit(_who, _by_what) -> void:
	if _invulnerable and _state != State.DEAD:
		# Immortale durante la transizione di fase: assorbe il colpo senza danno
		# né reazione, ma registra comunque chi lo ha colpito come bersaglio.
		if is_instance_valid(_who):
			target = _who
		return
	super.hit(_who, _by_what)


## Il boss non si dissolve rimpicciolendosi come un comune: resta a terra il
## tempo che serve al director, poi sparisce.
func _despawn_after_death() -> void:
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(self):
		queue_free()


# ═══════════════════════════════════════════════════════════════════════════
# Muro di fuoco lungo la traiettoria della lama
# ═══════════════════════════════════════════════════════════════════════════

func _on_weapon_window_opened(move : EnemyMove) -> void:
	_blade_path.clear()
	if move.wall_scene == null:
		return
	# Il muro nasce ORA, vuoto, non a fine swing: prima si aspettava che la
	# traccia fosse completa e il fuoco appariva con un ritardo senza senso
	# rispetto a uno swing che dura meno di un secondo.
	_active_wall = move.wall_scene.instantiate()
	_active_wall.move = move
	_active_wall.source = self
	_active_wall.duration = move.wall_duration
	_active_wall.tick_damage = move.wall_tick_damage
	_active_wall.tick_interval = move.wall_tick_interval
	get_parent().add_child(_active_wall)


func _on_weapon_window_closed(_move : EnemyMove) -> void:
	_active_wall = null   # resta in scena a vivere la sua vita (duration/fade)


## Il muro cresce un tratto alla volta MENTRE la lama passa: fuoco e collisione
## compaiono nel punto esatto in cui la spada sta transitando in quell'istante.
func _on_weapon_sweep_tick(forma : CollisionShape3D) -> void:
	if _active_wall == null or not is_instance_valid(_active_wall):
		return
	# La punta era scritta a mano come 0.495 — metà del box lama (0.99), giusto
	# ma solo per QUESTA spada. Ora la misura arriva dalla shape viva, la stessa
	# funzione che usa il lato giocatore: la mossa del boss e la Lucida Tecnica
	# non possono divergere su dove sta la punta della stessa arma.
	var tip : Vector3 = BladeTrail.tip_of(forma)
	if _blade_path.is_empty():
		_blade_path.append(tip)
	elif _blade_path[_blade_path.size() - 1].distance_to(tip) > 0.25:
		_active_wall.add_segment(_blade_path[_blade_path.size() - 1], tip)
		_blade_path.append(tip)


# ═══════════════════════════════════════════════════════════════════════════
# Mosse a distanza
# ═══════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════
# Scariche radiali
# ═══════════════════════════════════════════════════════════════════════════

## Fa esplodere l'onda dopo `delay` dall'inizio della clip (il tocco della spada
## a terra sul balzo) invece che al rilascio.
func _burst_at(move : EnemyMove, delay : float) -> void:
	await get_tree().create_timer(maxf(delay, 0.0)).timeout
	if _move_aborted():
		return
	_leap_move = null
	_apply_burst(move)


## Scarica radiale ("Respinta dell'Eco"): colpisce chi è entro `burst_radius`, in
## qualunque direzione. Niente arco, niente facing — è un'onda d'urto.
func _apply_burst(move : EnemyMove) -> void:
	_burst_vfx(move.burst_radius)
	if not is_instance_valid(target) or not target.has_method("hit"):
		return
	if _flat_distance(target) > move.burst_radius:
		return
	# Potenza ed echo propri della scarica: sul balzo l'onda vale meno della lama
	# ma carica Erosione. Si DUPLICA la risorsa prima di cambiarla — altrimenti si
	# muta la EnemyMove CONDIVISA e la modifica resta appiccicata a tutte le
	# esecuzioni successive.
	var info : EnemyMove = move
	if move.burst_power > 0 or move.burst_builds_echo:
		info = move.duplicate()
		if move.burst_power > 0:
			info.power = move.burst_power
		if move.burst_builds_echo:
			info.builds_echo = true
	target.hit(self, info)


# ═══════════════════════════════════════════════════════════════════════════
# Transizione di fase
# ═══════════════════════════════════════════════════════════════════════════

## Blast di carica FORZATO, boss IMMORTALE per tutta la durata, grande sfera
## viola di particelle che gli converge attorno. Chi resta vicino lo prende. Al
## termine: invulnerabilità giù, aura persistente su. Una volta sola.
func _run_phase2_intro() -> void:
	_phase2_started = true
	_phase2_intro = true
	_invulnerable = true
	_busy = true
	_move_since = _now()
	_snap_turn = false
	_attack_released = false
	_clear_move_state()
	if is_instance_valid(target):
		_face_instant()

	var clip_len : float = _anim_len(PHASE2_INTRO_CLIP) / anim_speed_scale
	# FX opzionali: se il file non c'è, la transizione avviene comunque — la
	# meccanica non dipende dai VFX.
	var fx = load("res://arcanium/systems/boss_phase2_fx.gd")
	if fx and fx.has_method("charge_sphere"):
		fx.charge_sphere(self, clip_len)
	_play(PHASE2_INTRO_CLIP, false)

	# Rilascio del blast dove le braccia scattano, poi il resto della clip.
	var release : float = clip_len * PHASE2_INTRO_RELEASE_FRAC
	await get_tree().create_timer(release).timeout
	if _state == State.DEAD:
		return
	_phase2_blast()
	Suoni.nel_mondo(self, Suoni.SENZANOME_RUGGITO, 3.0, 0.0)
	await get_tree().create_timer(maxf(clip_len - release, 0.05)).timeout
	if _state == State.DEAD:
		return

	_invulnerable = false
	_phase2_intro = false
	_busy = false
	if fx and fx.has_method("phase2_aura"):
		_phase2_aura = fx.phase2_aura(self)
	_next_attack = _now() + 0.5
	_state = State.IDLE
	_play(idle_anim, true)


## Onda radiale ampia della transizione (EROSIONE + carica Eco). Non è una mossa
## del set: costruisce un info usa-e-getta.
## ─── La voce del Senza Nome ─────────────────────────────────────────────────
## ⚠️ Sovrascrive quella dei Consumati che eredita: lui NON e' un Consumato, e
## soprattutto non porta la firma dell'eco. E' un uomo — dimenticato, tozzo,
## crudele, ma un uomo.
func _voce_ingaggio() -> String:
	return Suoni.SENZANOME_RUGGITO

func _voce_colpito() -> String:
	return ""   ## incassa in silenzio: e' parte di cosa lo rende temibile

func _voce_morte() -> String:
	return ""   ## la sua uscita di scena la governa il director del prologo


func _phase2_blast() -> void:
	_burst_vfx(PHASE2_BLAST_RADIUS)
	## La transizione è il momento più grosso dello scontro, e la sua scossa non
	## deve dipendere da quanto è largo il raggio dell'onda: si chiede
	## DEVASTANTE a mano. `colpo` e non `nel_mondo` perché non va attenuata —
	## quando il Senza Nome cambia fase sei sempre lì a guardarlo.
	Scossa.colpo(Scossa.DEVASTANTE)
	if not is_instance_valid(target) or not target.has_method("hit"):
		return
	if _flat_distance(target) > PHASE2_BLAST_RADIUS:
		return
	var info := EnemyMove.new()
	info.power = PHASE2_BLAST_POWER
	info.damage_type = "EROSIONE"
	info.builds_echo = true
	target.hit(self, info)


# ═══════════════════════════════════════════════════════════════════════════
# VFX
# ═══════════════════════════════════════════════════════════════════════════

## Bagliore sulla lama: sale per tutto il windup, poi si scarica di colpo —
## la scarica È il colpo.
func _sword_glow_on(duration : float, tinta : Color = Color(0.75, 0.3, 1.0)) -> void:
	## La carica si SENTE anche se la spada non si trova: il bagliore e' un di
	## piu', il suono e' il telegrafo. Per questo sta prima del `return`.
	##
	## ⚠️ Il campione dura 4 s e sale fino al rilascio, mentre i windup durano
	## meno: si alza il tono in proporzione, cosi' la salita si comprime e il
	## culmine cade comunque sul colpo invece che dopo.
	var carica := Suoni.nel_mondo(self, Suoni.CARICA_ARCANA, -3.0, 0.0)
	if carica != null:
		carica.pitch_scale = clampf(4.0 / maxf(duration, 0.6), 1.0, 2.2)

	var sword := get_node_or_null(NodePath("Model/NephiliteRig/Skeleton3D/SwordMount/Sword"))
	if sword == null:
		return
	var mesh : MeshInstance3D = null
	for n in sword.find_children("*", "MeshInstance3D", true, false):
		mesh = n
		break
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tinta.darkened(0.6)
	mat.emission_enabled = true
	mat.emission = tinta
	mat.emission_energy_multiplier = 0.0
	mesh.material_overlay = mat
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_property(mat, "emission_energy_multiplier", 6.0, maxf(duration, 0.05))
	_glow_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)
	_glow_tween.tween_callback(func() -> void:
		if is_instance_valid(mesh):
			mesh.material_overlay = null)


## Colore della carica secondo la magia della mossa: l'Erosione è il viola del
## fuoco nero, la Frattura è elettrica e fredda. Due magie diverse devono
## LEGGERSI diverse mentre caricano, o il tell non dice nulla.
func _glow_tint(move : EnemyMove) -> Color:
	match move.damage_type:
		"FRATTURA":
			return Color(0.55, 0.85, 1.0)
		_:
			return Color(0.75, 0.3, 1.0)


## Scariche lungo la lama per tutto il wind-up: il tell di un colpo MAGICO e non
## solo fisico. Agganciate all'arma, quindi seguono la spada mentre carica.
func _sword_sparks_on(duration : float, tinta : Color) -> void:
	var sword := get_node_or_null(NodePath("Model/NephiliteRig/Skeleton3D/SwordMount/Sword")) as Node3D
	if sword == null:
		return
	var p := GPUParticles3D.new()
	sword.add_child(p)
	p.position = Vector3(0, 0.205, 0)     # centro della lama, spazio dell'arma
	p.amount = 90
	p.lifetime = 0.45
	p.local_coords = true                  # seguono la spada: la carica è SUA
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.03, 0.495, 0.07)   # il volume della lama
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 1.4
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.03
	mat.scale_max = 0.10
	var grad := Gradient.new()
	grad.set_color(0, Color(tinta.r, tinta.g, tinta.b, 1.0))
	grad.set_color(1, Color(tinta.r * 0.3, tinta.g * 0.3, tinta.b * 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	p.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.16)   # un arco elettrico allungato
	qm.material = BossVFX.particle_material(BossVFX.TEX_ARC, tinta, 3.5)
	p.draw_pass_1 = qm
	p.emitting = true
	get_tree().create_timer(maxf(duration, 0.05)).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false)
	get_tree().create_timer(maxf(duration, 0.05) + 1.0).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## Tinta dei detriti che il Senza Nome solleva. Di default il pavimento
## dell'Arena Senza Fuoco, che è dove combatte: se un domani lo si porta altrove,
## si cambia qui sull'istanza invece di toccare il codice.
@export var detriti_tinta : Color = SchiantoATerra.PIETRA_ARENA
## Se false, niente pietre volanti (utile per isolare un difetto visivo).
@export var detriti_attivi : bool = true


## Pietre divelte dall'onda d'urto.
##
## ⚠️ La forza NON è il raggio dell'onda. Il raggio dice fin dove fa male, e per
## la Respinta è piccolo mentre per il blast di fase 2 è grande: legarci i
## detriti darebbe uno schianto minuscolo sulla mossa che invece deve sentirsi.
## Si usa una scala compressa (radice), così un'onda doppia alza pietre "una
## volta e mezza" e non il doppio — che è come funziona l'occhio, e impedisce al
## blast di fase 2 di riempire lo schermo di sassi.
func _schianto_di_pietra(radius : float) -> void:
	## L'onda sfonda anche le STRUTTURE: una colonna presa in pieno viene giù.
	## Il danno alle strutture è un numero suo e non `move.power`, per la stessa
	## ragione spiegata in boss_projectile.gd — HP dei personaggi e solidità dei
	## muri sono due economie diverse, e legarle vuol dire che ribilanciare il
	## boss cambia di nascosto quando crolla l'arena.
	OggettoDistruttibile.colpisci_intorno(self, global_position, radius + 0.8, 22.0)
	if not detriti_attivi:
		return
	var forza : float = clampf(sqrt(maxf(radius, 0.5) / 3.0), 0.7, 2.0)
	SchiantoATerra.sotto(self, forza, detriti_tinta)


## Scariche dal basso verso l'alto sul cerchio dell'onda: l'erosione che sale dal
## terreno. Senza un segno a terra l'onda non è leggibile né imparabile — e una
## mossa che non puoi imparare non è difficile, è ingiusta.
func _burst_vfx(radius : float) -> void:
	## SCHIANTO A TERRA: pietre del pavimento divelte dall'onda.
	##
	## Sta QUI e non nelle singole mosse perché `_burst_vfx` è l'imbuto unico di
	## tutte le scariche del Senza Nome — l'atterraggio del balzo (che passa da
	## `_burst_at` → `_apply_burst`), la Respinta, e il blast della transizione a
	## fase 2. Un aggancio solo, e le tre cose si comportano uguale per
	## costruzione invece che per disciplina.
	_schianto_di_pietra(radius)

	var p := GPUParticles3D.new()
	get_parent().add_child(p)
	p.global_position = Vector3(global_position.x, global_position.y + 0.05, global_position.z)
	p.amount = 220
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.85
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3.UP
	mat.emission_ring_radius = radius
	mat.emission_ring_inner_radius = radius * 0.15
	mat.emission_ring_height = 0.05
	mat.direction = Vector3.UP          # dal basso verso l'alto
	mat.spread = 8.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 7.5
	mat.gravity = Vector3(0, -2.0, 0)
	mat.scale_min = 0.06
	mat.scale_max = 0.16
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.85, 0.95, 1.0))
	grad.set_color(1, Color(0.15, 0.35, 0.6, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	p.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.30)
	# Filamenti d'energia che salgono, non puntini: la forma la porta la texture.
	qm.material = BossVFX.particle_material(BossVFX.TEX_ENERGY, Color(0.6, 0.9, 1.0), 3.0)
	p.draw_pass_1 = qm
	p.emitting = true
	_burst_ring(radius)
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## Segno a terra dell'onda: un anello che si apre fino a `radius` ESATTO. Le
## scintille dicono "è successo qualcosa", non DOVE finisce. Il raggio qui è lo
## stesso che decide il danno in `_apply_burst`: il segno È la hitbox, non una
## sua approssimazione grafica.
##
## Decal e non un quad orizzontale: si PROIETTA sul pavimento, quindi non
## z-fighta col kit modulare dell'arena né sparisce dentro un gradino.
func _burst_ring(radius : float) -> void:
	var d := Decal.new()
	get_parent().add_child(d)
	d.global_position = Vector3(global_position.x, global_position.y + 0.9, global_position.z)
	# Solo emission: il decal deve AGGIUNGERE luce al pavimento (e accendere il
	# bloom), non ridipingerne l'albedo — l'arena è volutamente a bassa albedo.
	d.texture_emission = BossVFX.TEX_RING
	d.emission_energy = 4.0
	d.modulate = Color(0.6, 0.9, 1.0)
	d.albedo_mix = 0.0
	# size.y = profondità di proiezione verso il basso: abbastanza da pescare il
	# pavimento anche se il boss atterra leggermente sopra di esso.
	d.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	d.scale = Vector3(0.15, 1.0, 0.15)
	# Tween legato al DECAL, non al boss: se il boss muore mentre l'onda è a
	# schermo, un tween legato a lui verrebbe ucciso e il queue_free non
	# arriverebbe mai — anello piantato a terra per sempre.
	var tw := d.create_tween()
	tw.set_parallel(true)
	# Apertura rapida: l'onda colpisce ISTANTANEAMENTE, quindi l'anello deve
	# arrivare al bordo subito. Se ci mettesse mezzo secondo mentirebbe sul
	# momento del danno.
	tw.tween_property(d, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(d, "emission_energy", 0.0, 0.75) \
		.set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(d.queue_free)


# ═══════════════════════════════════════════════════════════════════════════
# VFX di carica sulla mano (il TELL delle mosse a distanza)
# ═══════════════════════════════════════════════════════════════════════════
## Costruito una volta e riusato: luce viola + scintille che convergono verso la
## mano, che salgono d'intensità lungo il telegraph e si spengono al rilascio.

var _charge_light : OmniLight3D
var _charge_particles : GPUParticles3D
var _charge_core : MeshInstance3D
var _charge_tween : Tween

func _ensure_charge_vfx() -> void:
	if _charge_light != null:
		return
	var host : Node3D = get_node_or_null(cast_origin) as Node3D
	if host == null:
		host = self
	_charge_light = OmniLight3D.new()
	_charge_light.light_color = Color(0.6, 0.15, 0.95)
	_charge_light.light_energy = 0.0
	_charge_light.omni_range = 3.5
	host.add_child(_charge_light)

	_charge_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_charge_core.mesh = sm
	var m := StandardMaterial3D.new()
	## ⚠️ SHADING_MODE_UNSHADED manda ALBEDO dritto in uscita e IGNORA EMISSION.
	## Qui l'albedo era (0.08, 0.0, 0.12) — praticamente nero — e tutto il viola
	## stava in `emission`: verificato dalla IsoCam, il nucleo della carica si
	## vedeva come un BUCO NERO al centro dell'alone viola, cioè l'opposto di
	## "sta raccogliendo potere". Col glow disattivato a livello di progetto non
	## c'è nemmeno un bloom che lo recuperi. Il colore vivo va quindi nell'ALBEDO;
	## l'emission resta coerente per il giorno in cui il glow verrà acceso.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.72, 0.30, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.55, 0.12, 0.9)
	m.emission_energy_multiplier = 2.0
	_charge_core.material_override = m
	_charge_core.scale = Vector3.ZERO
	host.add_child(_charge_core)

	_charge_particles = GPUParticles3D.new()
	_charge_particles.amount = 32
	_charge_particles.lifetime = 0.5
	_charge_particles.local_coords = true
	_charge_particles.emitting = false
	var pm := ParticleProcessMaterial.new()
	# Scintille che NASCONO in una shell e convergono verso il centro
	# (accelerazione radiale negativa) = "sta raccogliendo potere".
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.7
	pm.direction = Vector3(0, 0, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	pm.radial_accel_min = -3.5
	pm.radial_accel_max = -2.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.05
	pm.scale_max = 0.15
	pm.color = Color(0.6, 0.2, 0.85)
	_charge_particles.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.12)
	## ⚠️ Questo quad era SENZA materiale: Godot ci mette il materiale di default,
	## cioè bianco OPACO e non billboardato. Il telegraph della carica — la cosa
	## che il player deve leggere per sapere che sta arrivando una mossa a
	## distanza — si vedeva quindi come una manciata di quadretti bianchi che
	## ruotavano col polso del boss, e il viola di `pm.color` veniva ignorato
	## (senza vertex_color_use_as_albedo il color_ramp non arriva all'albedo).
	## Stesso materiale additivo degli altri emettitori del boss: adesso la
	## carica è viola e billboardata come il resto.
	qm.material = BossVFX.particle_material(BossVFX.TEX_SPARK, Color(0.6, 0.2, 0.85), 2.6)
	_charge_particles.draw_pass_1 = qm
	host.add_child(_charge_particles)


func _charge_vfx_on(duration : float) -> void:
	_ensure_charge_vfx()
	if _charge_tween and _charge_tween.is_valid():
		_charge_tween.kill()
	_charge_particles.emitting = true
	_charge_tween = create_tween()
	_charge_tween.set_parallel(true)
	_charge_tween.tween_property(_charge_light, "light_energy", 3.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_charge_tween.tween_property(_charge_core, "scale", Vector3.ONE, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _charge_vfx_off() -> void:
	if _charge_light == null:
		return
	if _charge_tween and _charge_tween.is_valid():
		_charge_tween.kill()
	_charge_particles.emitting = false
	_charge_light.light_energy = 0.0
	_charge_core.scale = Vector3.ZERO
