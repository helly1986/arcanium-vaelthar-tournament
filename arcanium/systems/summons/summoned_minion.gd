extends CharacterBody3D
class_name SummonedMinion

## Minion neutrale di primo livello: la prima evocazione che il player impara
## (Maestro di Evocazioni, Traccia Perduta). È soprattutto una "batteria" —
## finché è vivo rigenera Arcanium Vivo nel pool del player (`vitals`) —, ma ha
## anche un ATTACCO BASE minimo: quando un nemico è a tiro oscilla un istante
## (carica) e sprigiona una scarica radiale di Erosione con VFX magenta, sullo
## stesso modello del blast del Senza Nome (particelle ad anello + decal a
## terra, vedi boss_vfx.gd / arcanium_boss._burst_vfx). Danno basso: dà una
## MANO al DPS mentre è in campo, non sostituisce il player. Segue il player e
## lo aiuta finché non muore.

## VFX condivisi col boss (texture monocromatiche + tinta a runtime): riusati
## per la scarica magenta, zero asset nuovi.
const BossVFX := preload("res://arcanium/systems/boss_vfx.gd")
const ArcaniumVFX := preload("res://arcanium/systems/vfx/arcanium_vfx.gd")
const CorpoSpirito := preload("res://arcanium/systems/spiriti/corpo_spirito.gd")
const EcoClip := preload("res://arcanium/systems/spiriti/eco_clip.gd")
const EcoFx := preload("res://arcanium/systems/spiriti/eco_fx.gd")

## Corpo di spirito e attacco (vedi SummonSpellResource): li travasa lo
## spell_caster come gli altri campi.
@export var corpo_spirito : bool = false
@export_enum("scarica", "radice") var attacco : String = "scarica"
## Raggio del cerchio della Radice (piu' stretto della scarica: e' un colpo
## mirato, non un'onda).
@export var radice_raggio : float = 1.5
##
## Ha HP reali (ArcaniumHealthSystem figlio) ed è nel gruppo "player": è lo
## STESSO gruppo del protagonista, usato in tutto il combat esistente
## (boss/proiettili/muri controllano `body.is_in_group("player")` per
## decidere COSA possono colpire, e i proiettili del player la escludono
## esplicitamente — vedi ice_shard_projectile.gd `_try_hit`). Aggiungerlo qui
## significa: i nemici/boss che già colpiscono il player possono colpire
## anche il minion con zero modifiche a quel codice; il player non lo
## danneggia mai per errore. Quello che NON dà gratis: una vera logica
## "attacca il bersaglio più vicino fra player e minion" — enemy_area_target_sensor.gd
## oggi traccia un solo `potential_target` per Area3D e non confronta
## distanze; quella scelta è territorio Fase C/D (nemici), non di questo
## stream.
##
## Modello: PLACEHOLDER a primitive (nessun asset Meshy ancora). Tutto il
## placeholder visivo vive sotto il nodo figlio "PlaceholderModel": per
## sostituirlo con la mesh reale basta cancellare quel nodo e instanziarne
## una nuova con lo stesso nome sotto la root, senza toccare script/collider/
## HealthSystem.

## Chi seguire (tipicamente il player — assegnato da SpellCaster.cast_summon
## via `get_parent()`, duck-typing "follow_target" in minion).
var follow_target : Node3D = null

## Pool di Arcanium Vivo su cui accreditare la generazione passiva (assegnato
## da SpellCaster.cast_summon, stesso PlayerVitals dello SpellCaster). Se
## null, il minion segue ma non genera nulla (degrado silenzioso, coerente
## col resto del sistema spell).
var vitals : PlayerVitals = null

## Arcanium Vivo generato al secondo finché il minion è vivo. Sovrascritto
## dalla risorsa spell allo spawn (SummonSpellResource.arcanium_per_sec) —
## il default qui è solo per test/istanza isolata.
@export var arcanium_per_sec : float = 1.0

@export var move_speed : float = 3.5
@export var acceleration : float = 10.0
@export var follow_distance : float = 1.8  ## si ferma a questa distanza dal target
@export var gravity : float = 20.0
## Velocità (rad/s) di rotazione verso la direzione di marcia.
@export var turn_speed : float = 10.0

@export_group("Attacco base (scarica radiale)")
## Se false, il minion resta puramente "batteria" (nessun attacco).
@export var can_attack : bool = true
## Secondi tra una scarica e la successiva.
@export var attack_cooldown : float = 3.5
## Un nemico ("targets") entro questo raggio innesca la scarica.
@export var attack_range : float = 5.0
## Raggio della scarica: chi è dentro subisce il danno. Il segno grafico
## (anello) usa lo STESSO raggio, come nel blast del boss.
@export var blast_radius : float = 2.4
## Danno della scarica (basso: aiuto, non carry).
@export var blast_power : int = 4
## Famiglia dell'evocazione, per i bonus da equipaggiamento ("bestia", ...).
## Vuota = nessuna famiglia, nessun bonus. La Scintilla è Arcanium puro e resta
## vuota; il lupo evocato del futuro tomo sarà "bestia".
@export var summon_family : String = ""
@export_enum("FISICO", "TAGLIO", "PERFORAZIONE", "SCHIANTO", "CRIO", "EROSIONE", "SACRO", "FRATTURA", "VELENO", "FUOCO", "FULMINE") var blast_damage_type : String = "EROSIONE"

## Colore della creatura: scarica, sigillo, luce e tinta della mesh.
##
## ⚠️ ERA UNA `const`. È diventato un export quando sono arrivate le sei
## evocazioni di casata (SummonSpellResource.minion_tint): con una costante,
## un'Eco Radicata di Sylvorn e una Sentinella del Passo di Dawnkeep erano
## entrambe magenta, e in isometrica — dove il colore è quasi tutto quello che
## si legge di una figura piccola in mezzo alla mischia — erano la stessa cosa.
## Il default resta il magenta della Scintilla, così le scene già montate non
## cambiano aspetto.
@export var minion_tint : Color = Color(1.0, 0.2, 0.85)

## Taglia della creatura, 1.0 = quella della scena. Applicata al modello e al
## sigillo, non al collider: l'ingombro fisico resta uno per tutte, perché è
## quello che decide se una creatura si incastra in una porta.
@export var minion_scale : float = 1.0

## Modello 3D che SOSTITUISCE quello della scena (la Scintilla). È così che sei
## evocazioni diverse vivono in una scena sola: cambia la mesh, non la struttura.
## Null = si tiene la Scintilla.
@export var minion_model : PackedScene

## Altezza voluta della creatura, in metri (0 = lascia la scala del GLB).
##
## ⚠️ Serve perché i modelli generati arrivano tutti normalizzati alla stessa
## dimensione: messi in scena senza adattarli, un Rievocato in armatura e una
## scintilla di fulmine sono alti uguale, e la differenza di stazza — che è
## metà di quello che distingue una creatura dall'altra a colpo d'occhio —
## sparisce. Si misura l'ingombro reale e si scala verso questa altezza, come
## fanno i builder delle location con `mode: "height"`.
@export var minion_height : float = 0.0

## Quanto la creatura sta sollevata da terra (0 = appoggiata). Per le evocazioni
## che fluttuano: l'Eco Radicata «non si fida ancora di staccarsi completamente».
@export var minion_hover : float = 0.0

## Punti vita da imporre all'HealthSystem figlio (0 = lascia quelli della scena).
@export var minion_health : int = 0

## Build-up di Congelamento portato dalla scarica (0 = nessuno). È la firma
## della Sentinella del Passo di Dawnkeep: quella casata non uccide, immobilizza
## — e senza questo campo la sua evocazione sarebbe "la stessa scarica, blu".
@export var blast_frozen_buildup : float = 0.0

## Frazione di danno subito rimandata a chi ha colpito (0 = niente).
## Firma del Frammento del Contrario di Aethon: «riflette una porzione di ciò
## che la colpisce. Non per scelta. Per natura.» (LORE/CREATURES.md).
@export var riflette : float = 0.0

@export_group("Sigillo a terra")
## Se false, la creatura non porta il marchio a terra (per evocazioni che
## devono restare invisibili/furtive).
@export var show_sigil : bool = true
## Raggio del sigillo in metri: va tenuto vicino all'ingombro della creatura,
## NON al raggio della scarica — è un segno di appartenenza, non un telegrafo
## d'attacco (confonderli farebbe leggere un'area di pericolo che non c'è).
@export var sigil_radius : float = 0.75

## MeshInstance3D del sigillo. Serve tenerne il riferimento perché la carica
## dell'attacco si comunica con set_instance_shader_parameter su QUESTO nodo:
## il materiale è condiviso da tutte le evocazioni in campo (vedi ArcaniumVFX)
## e toccarlo direttamente le tingerebbe tutte insieme.
var _sigil : MeshInstance3D = null

var _attack_cd : float = 0.0
var _corpo : Node3D = null
var _clip : AnimationPlayer = null
var _attacking : bool = false
var _dead : bool = false

## Oggetto duck-typed passato a target.hit(caster, info) — stesso contratto di
## ImpactInfo in ice_shard_projectile.gd (ArcaniumHealthSystem legge i campi con
## `"campo" in _by_what`).
class BlastInfo extends Resource:
	var power : int = 0
	var damage_type : String = "EROSIONE"
	var builds_echo : bool = true   ## coerente con l'Erosione dell'Eco (Gruppo arcano)
	## Letto da ArcaniumHealthSystem._route_statuses (stesso campo dello Shard
	## di Ghiaccio): resta 0 per tutte le evocazioni tranne quelle di Dawnkeep.
	var frozen_buildup : float = 0.0

@onready var _health_system : Node = get_node_or_null("HealthSystem")

## Contratto HealthSystem: hit_reporting_node = questo nodo, damage_signal =
## "damage_taken" (default del template) — hit() consegna l'attacco qui,
## HealthSystem lo raccoglie tramite questo segnale (stesso schema di
## enemy_base_root_motion.gd.hit() / player_charbody3D.gd.hit()).
signal damage_taken(info)

func _ready() -> void:
	add_to_group("player")
	add_to_group("arcanium_minion")
	if _health_system and _health_system.has_signal("died"):
		_health_system.died.connect(_on_died)
	_applica_casata()
	_build_sigil()
	_start_idle()


## Veste la creatura dei segni della casata che l'ha chiamata: taglia, colore
## della mesh, colore della luce, punti vita.
##
## ⚠️ La tinta si applica DUPLICANDO il materiale della superficie, non
## sostituendolo: il .glb della Scintilla porta le sue texture (base color,
## emissive, normal) dentro il materiale, e assegnare uno StandardMaterial3D
## nuovo le butterebbe via lasciando sei sfere di plastica colorata. Duplicare e
## ritingere albedo/emission le conserva.
## Mette la mesh della casata al posto della Scintilla, e la porta all'altezza
## giusta appoggiandola a terra (o sollevandola di `minion_hover`).
##
## ⚠️ La LUCE non si tocca. Sta sotto lo stesso nodo del modello ma non fa parte
## del modello: sostituendo tutti i figli di MinionModel si spegneva l'unica
## fonte di luce della creatura, e in un'arena buia una figura piccola senza
## luce propria semplicemente non esiste.
func _sostituisci_modello(model : Node3D) -> void:
	if minion_model == null:
		return
	for figlio in model.get_children():
		if figlio is Light3D:
			continue
		model.remove_child(figlio)
		figlio.queue_free()
	if corpo_spirito:
		## Lo spirito si misura e si solleva da se' (altezza, sospensione), e
		## porta le sue clip: idle a riposo, radice per l'attacco.
		var corpo := CorpoSpirito.new()
		corpo.name = "Modello"
		corpo.modello = minion_model
		corpo.altezza = minion_height if minion_height > 0.0 else 1.15
		corpo.sospensione = minion_hover
		corpo.colore_bordo = minion_tint
		model.add_child(corpo)
		_corpo = corpo
		_clip = AnimationPlayer.new()
		_clip.name = "Clip"
		corpo.add_child(_clip)
		_clip.add_animation_library("", EcoClip.libreria())
		_clip.play("idle")
		return
	var inst := minion_model.instantiate()
	inst.name = "Modello"
	model.add_child(inst)
	if inst is Node3D:
		_adatta_altezza(inst as Node3D)


## Scala l'istanza perché il suo ingombro reale sia alto `minion_height`, con la
## base a terra. Misura l'AABB unito delle mesh: i GLB generati arrivano
## normalizzati e non c'è modo di sapere a priori quanto siano alti.
func _adatta_altezza(inst : Node3D) -> void:
	if minion_height <= 0.0:
		inst.position.y = minion_hover
		return
	var unione := AABB()
	var primo := true
	for nodo in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.mesh == null:
			continue
		## ⚠️ In spazio di `inst`, non del proprio genitore: dentro un GLB le mesh
		## stanno annidate sotto nodi con trasformazioni proprie, e usare
		## `mi.transform` misurerebbe l'ingombro di un pezzo solo nello spazio
		## sbagliato. Qui il nodo è già nell'albero (siamo dentro `add_child`),
		## quindi le globali sono valide.
		var box : AABB = (inst.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		if primo:
			unione = box
			primo = false
		else:
			unione = unione.merge(box)
	if primo or unione.size.y <= 0.0001:
		inst.position.y = minion_hover
		return
	var f := minion_height / unione.size.y
	inst.scale = Vector3.ONE * f
	## La base dell'ingombro va a y = hover: senza questo un modello il cui
	## pivot non e' ai piedi affonda nel terreno o galleggia a caso.
	inst.position.y = minion_hover - unione.position.y * f


func _applica_casata() -> void:
	if _health_system and minion_health > 0 and "total_health" in _health_system:
		_health_system.total_health = minion_health
		## ⚠️ I figli fanno `_ready` PRIMA del genitore: quando arriviamo qui
		## ArcaniumHealthSystem ha già copiato il `total_health` della SCENA nel
		## proprio accumulatore `_health_f`, ed è quello — non `total_health` — a
		## decidere quando la creatura muore. Scriverne uno solo dei due darebbe
		## una barra da 90 su una vita da 40.
		_health_system.set("_health_f", float(minion_health))
		if "current_health" in _health_system:
			_health_system.current_health = minion_health

	var model := get_node_or_null("MinionModel") as Node3D
	if model == null:
		return
	_sostituisci_modello(model)
	if not is_equal_approx(minion_scale, 1.0):
		model.scale = Vector3.ONE * minion_scale
	for luce in model.find_children("*", "OmniLight3D", true, false):
		(luce as OmniLight3D).light_color = minion_tint
	## ⚠️ La MESH si ritinge SOLO quando la creatura non ha un modello proprio.
	## Le sei evocazioni di casata hanno il loro GLB, già dipinto coi colori
	## giusti da chi l'ha fatto: passarci sopra una tinta piatta butterebbe via
	## proprio il lavoro che le rende riconoscibili. Chi condivide la mesh della
	## Scintilla — e domani l'Eco Radicata corrotta dall'Arcanium grezzo, che è
	## la stessa creatura in viola — la tinta la vuole eccome: è l'unica cosa
	## che la distingue dall'originale.
	## Luce, sigillo e scarica restano tinti in ogni caso: sono il segno di
	## fazione, e quello deve dire la casata anche su un modello proprio.
	if minion_model != null:
		return
	for nodo in model.find_children("*", "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if base is StandardMaterial3D:
				var copia : StandardMaterial3D = base.duplicate()
				copia.albedo_color = minion_tint
				copia.emission_enabled = true
				copia.emission = minion_tint
				mi.set_surface_override_material(s, copia)

## Marchio a terra dell'evocazione.
##
## PERCHÉ ESISTE: il design prevede 3-4 evocazioni PER FAZIONE sul campo. In
## isometrica, in un'arena buia, una mischia di otto creature diventa una
## poltiglia di silhouette e il player non distingue le proprie. Il sigillo
## risolve questo e basta: sta sul PAVIMENTO — il piano che la camera iso
## inquadra meglio e che i corpi non coprono — e porta il colore della fazione.
##
## Costa una draw call condivisa: il materiale è UNO per tutte le creature
## (ArcaniumVFX.summon_sigil_material) e il colore passa da instance uniform,
## quindi otto sigilli restano in batch invece di essere otto materiali unici.
func _build_sigil() -> void:
	if not show_sigil:
		return
	_sigil = ArcaniumVFX.make_summon_sigil(sigil_radius, minion_tint)
	add_child(_sigil)

## Comunica al sigillo quanto la creatura è "carica" (0 = a riposo, 1 = sta per
## scaricare). Nessun-op se il sigillo è disattivato.
func _set_sigil_charge(v : float) -> void:
	if _sigil:
		_sigil.set_instance_shader_parameter("inst_charge", clampf(v, 0.0, 1.0))

## Avvia in loop la clip "idle" del GLB della Scintilla (stesso pattern di
## crocevia_npc.gd::_start_idle): trova il primo AnimationPlayer tra i figli,
## forza LOOP_LINEAR sulla clip e la fa partire. Nessun-op se il modello non
## ha animazioni (es. placeholder senza AnimationPlayer).
func _start_idle() -> void:
	var ap : AnimationPlayer = null
	for n in find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break
	if ap == null:
		return
	var chosen := ""
	for a in ap.get_animation_list():
		if a.to_lower() == "idle":
			chosen = a
			break
	if chosen == "":
		return
	var anim := ap.get_animation(chosen)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	ap.play(chosen)

func _physics_process(delta : float) -> void:
	_apply_gravity(delta)
	_follow(delta)
	move_and_slide()

func _process(delta : float) -> void:
	_tick_arcanium(delta)
	_tick_attack(delta)

## ─── Attacco base: scarica radiale magenta ───────────────────────────────────
func _tick_attack(delta : float) -> void:
	if not can_attack or _attacking or _dead:
		return
	if _attack_cd > 0.0:
		_attack_cd -= delta
		return
	var enemy := _nearest_enemy()
	if enemy == null:
		return
	_attack_cd = attack_cooldown
	if attacco == "radice":
		_do_radice(enemy)
	else:
		_do_blast()

## Quanto l'equipaggiamento di chi ha evocato potenzia questa creatura.
func _bonus_padrone() -> float:
	var loadout := get_node_or_null("/root/EquipmentLoadout")
	if loadout == null:
		return 1.0
	return loadout.summon_multiplier(summon_family)


## Il "targets" più vicino entro attack_range (nemici/boss); null se nessuno.
func _nearest_enemy() -> Node3D:
	var best : Node3D = null
	var best_d := attack_range
	for node in get_tree().get_nodes_in_group("targets"):
		var n := node as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var d := _flat_dist(n)
		if d <= best_d:
			best_d = d
			best = n
	return best

func _flat_dist(n : Node3D) -> float:
	var v := n.global_position - global_position
	v.y = 0.0
	return v.length()

## Oscilla un istante (carica leggibile), poi sprigiona la scarica: VFX + danno
## a tutti i "targets" nel raggio.
func _do_blast() -> void:
	_attacking = true
	## Il sigillo pulsa durante la carica: è il telegrafo. In isometrica il
	## sobbalzo del modello (sotto) si vede poco quando la creatura è dietro a
	## un corpo, il marchio a terra no.
	_set_sigil_charge(1.0)
	var model := get_node_or_null("MinionModel") as Node3D
	if model:
		var base := model.position
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.tween_property(model, "position", base + Vector3(0.0, 0.14, 0.0), 0.12)
		tw.parallel().tween_property(model, "scale", Vector3(0.9, 1.15, 0.9), 0.12)
		tw.tween_property(model, "position", base, 0.10)
		tw.parallel().tween_property(model, "scale", Vector3.ONE, 0.10)
		await tw.finished
	if _dead or not is_instance_valid(self):
		_attacking = false
		return
	_set_sigil_charge(0.0)
	_blast_vfx(blast_radius)
	_apply_blast_damage()
	_attacking = false

## La Radice che Afferra dell'Eco evocata: la stessa mossa dell'Eco Guasta,
## girata contro i nemici. Affondando la coda (0,8 s) segna dove sta il nemico,
## il cerchio si riempie, la radice esplode al contatto e colpisce chi ci sta
## dentro. Il nemico che esce in tempo la schiva: vale anche per loro.
func _do_radice(enemy : Node3D) -> void:
	_attacking = true
	_set_sigil_charge(1.0)
	var velocita := 1.0
	if _clip != null:
		_clip.play("radice")
		velocita = _clip.get_playing_speed()
	var segna := 0.8
	var contatto : float = EcoClip.CONTATTI["radice"][0]
	await get_tree().create_timer(segna / velocita).timeout
	if _dead or not is_instance_valid(self) or not is_instance_valid(enemy):
		_fine_radice()
		return
	var punto := enemy.global_position
	EcoFx.radice(get_parent(), punto, radice_raggio, (contatto - segna) / velocita, minion_tint)
	await get_tree().create_timer((contatto - segna) / velocita).timeout
	if _dead or not is_instance_valid(self):
		_fine_radice()
		return
	var info := BlastInfo.new()
	info.power = int(round(blast_power * _bonus_padrone()))
	info.damage_type = blast_damage_type
	info.frozen_buildup = blast_frozen_buildup
	for node in get_tree().get_nodes_in_group("targets"):
		var n := node as Node3D
		if n == null or not is_instance_valid(n) or not n.has_method("hit"):
			continue
		var d : Vector3 = n.global_position - punto
		if Vector3(d.x, 0.0, d.z).length() <= radice_raggio:
			n.hit(self, info)
	_fine_radice()


func _fine_radice() -> void:
	_set_sigil_charge(0.0)
	_attacking = false
	if _clip != null and is_instance_valid(_clip):
		await get_tree().create_timer(0.55).timeout
		if is_instance_valid(_clip):
			_clip.play("idle")


func _apply_blast_damage() -> void:
	var info := BlastInfo.new()
	# L'equipaggiamento del PADRONE può potenziare l'evocazione: il Manto del
	# Branco Guasto dà +15% alle creature di famiglia "bestia". Il moltiplicatore
	# si applica qui, sul danno finale, così vale per qualunque bonus futuro
	# senza toccare altro.
	info.power = int(round(blast_power * _bonus_padrone()))
	info.damage_type = blast_damage_type
	info.frozen_buildup = blast_frozen_buildup
	for node in get_tree().get_nodes_in_group("targets"):
		var n := node as Node3D
		if n == null or not is_instance_valid(n) or not n.has_method("hit"):
			continue
		var d : Vector3 = n.global_position - global_position
		if Vector3(d.x, 0.0, d.z).length() <= blast_radius:
			n.hit(self, info)

## Scarica radiale: particelle ad anello che salgono + decal a terra al raggio
## esatto. Copia snella di arcanium_boss._burst_vfx/_burst_ring, tinta magenta,
## parentata al genitore così sopravvive al despawn del minion.
func _blast_vfx(radius : float) -> void:
	var host := get_parent()
	if host == null:
		return
	var p := GPUParticles3D.new()
	host.add_child(p)
	p.global_position = Vector3(global_position.x, global_position.y + 0.05, global_position.z)
	p.amount = 120
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 0.9
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3.UP
	mat.emission_ring_radius = radius
	mat.emission_ring_inner_radius = radius * 0.15
	mat.emission_ring_height = 0.05
	mat.direction = Vector3.UP
	mat.spread = 10.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0.0, -2.0, 0.0)
	mat.scale_min = 0.05
	mat.scale_max = 0.13
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.35, 0.95, 1.0))
	grad.set_color(1, Color(0.5, 0.1, 0.6, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	p.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.11, 0.26)
	qm.material = BossVFX.particle_material(BossVFX.TEX_ENERGY, minion_tint, 3.0)
	p.draw_pass_1 = qm
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())
	_blast_ring(radius)

func _blast_ring(radius : float) -> void:
	var host := get_parent()
	if host == null:
		return
	var d := Decal.new()
	host.add_child(d)
	d.global_position = Vector3(global_position.x, global_position.y + 0.9, global_position.z)
	d.texture_emission = BossVFX.TEX_RING
	d.emission_energy = 3.5
	d.modulate = minion_tint
	d.albedo_mix = 0.0
	d.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	d.scale = Vector3(0.15, 1.0, 0.15)
	var tw := d.create_tween()
	tw.set_parallel(true)
	tw.tween_property(d, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(d, "emission_energy", 0.0, 0.7) \
		.set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(d.queue_free)

## Consegna del colpo, stessa firma usata ovunque nel progetto:
## `target.hit(caster, info)` con `info` duck-typed (.power, .damage_type,
## opzionalmente .frozen_buildup ecc. — vedi ArcaniumHealthSystem._route_statuses).
func hit(_by_who, _by_what) -> void:
	damage_taken.emit(_by_what)
	_rifletti(_by_who, _by_what)


## Rimanda a chi ha colpito una frazione del colpo (Frammento del Contrario).
##
## ⚠️ Si rimanda SOLO a un "targets", cioè a un nemico. Senza quel filtro, un
## colpo d'area del player che sfiora la propria evocazione tornerebbe indietro
## sul player stesso, e la creatura comprata per proteggerti diventerebbe una
## mina. E si rimanda un colpo SECCO, non un altro riflettibile: due creature
## che riflettono a vicenda si scambierebbero lo stesso danno all'infinito
## dentro un solo frame.
func _rifletti(_by_who, _by_what) -> void:
	if riflette <= 0.0 or _dead:
		return
	if not (_by_who is Node) or not is_instance_valid(_by_who):
		return
	if not _by_who.is_in_group("targets") or not _by_who.has_method("hit"):
		return
	if not ("power" in _by_what):
		return
	var eco := BlastInfo.new()
	eco.power = int(round(float(_by_what.power) * riflette))
	eco.damage_type = blast_damage_type
	eco.builds_echo = false
	if eco.power <= 0:
		return
	_by_who.hit(self, eco)

func _apply_gravity(delta : float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

func _follow(delta : float) -> void:
	if not is_instance_valid(follow_target):
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		return

	var to_target : Vector3 = follow_target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist <= follow_distance:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		return

	var dir := to_target.normalized()
	var desired := dir * move_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)

	## +Z = avanti, stessa convenzione delle mesh Meshy usata dal resto del
	## progetto (vedi player_charbody3D.gd rotate_player).
	var target_rot := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, turn_speed * delta)

func _tick_arcanium(delta : float) -> void:
	if vitals == null or arcanium_per_sec <= 0.0:
		return
	if not ("arcanium" in vitals) or not ("max_arcanium" in vitals):
		return
	vitals.arcanium = minf(vitals.arcanium + arcanium_per_sec * delta, vitals.max_arcanium)
	if vitals.has_signal("arcanium_changed"):
		vitals.arcanium_changed.emit(vitals.arcanium, vitals.max_arcanium)

func _on_died() -> void:
	_dead = true
	set_physics_process(false)
	set_process(false)
	## Uno spirito non si rimpicciolisce: si affloscia e si dissolve dal basso,
	## come la sua versione Guasta.
	if _clip != null and is_instance_valid(_clip) and _clip.has_animation("morte"):
		_clip.play("morte")
		await get_tree().create_timer(_clip.get_animation("morte").length).timeout
		if is_instance_valid(self):
			queue_free()
		return
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.4)
	tw.tween_callback(queue_free)
