extends Node3D
class_name BossWall

const BossVFX := preload("res://arcanium/systems/boss_vfx.gd")
const ArcaniumVFX := preload("res://arcanium/systems/vfx/arcanium_vfx.gd")
const Fazioni := preload("res://arcanium/systems/fazioni.gd")

## Tinta viola dell'Erosione, condivisa da membrana e particelle.
const EROSION_TINT := Color(0.80, 0.45, 1.0)

## Materiale della membrana, UNO per tutto il muro (vedi ArcaniumVFX): i
## segmenti di una stessa spadata hanno la stessa età, quindi condividono anche
## `life`. Creato pigramente al primo segmento.
var _membrane_mat : ShaderMaterial = null

## Muro di Erosione lasciato dal "Rovescio Risonante" (A2): la lama è magica e
## nel suo giro DISEGNA una barriera che resta nell'arena. Chi ci sta dentro paga
## a ogni tick, e si carica lo status poco per volta.
##
## Perché questa mossa è così: la lama di A2 manca il player di 80cm in modo
## IDENTICO a ogni esecuzione (misurato: min_dist=0.80 sia da fermo che in
## movimento). È geometria della clip — authorata per colpire un avversario
## grande quanto l'attaccante — e nessuna taratura la vince. Invece di combatterla,
## la mossa diventa quel giro di lama: il muro nasce ESATTAMENTE dove la spada è
## passata, quindi il fatto che non ti tocchi smette di essere un difetto. A2 non
## è più una spadata mancata, è controllo dello spazio — un ruolo che nessun'altra
## mossa del boss ha.
##
## Il percorso arriva dal boss, campionato dalla sonda della lama durante lo
## swing: il muro non è un box piazzato a occhio davanti al boss, è la traccia
## reale dell'arma.
##
## COSTRUZIONE INCREMENTALE: il boss chiama `add_segment()` un tratto alla
## volta, MENTRE la spada sta ancora swingando (non aspetta la fine dello
## swing per esistere tutto insieme). Prima il muro nasceva intero a swing
## finito: il fuoco appariva con un ritardo senza senso rispetto a uno swing
## che dura meno di un secondo. Ora ogni tratto si accende — collisione e
## fuoco — nell'istante esatto in cui la lama lo attraversa, quindi il colpo
## comincia a valere da subito, non da quando lo swing è finito.
##
## `path` resta come parametro opzionale per costruzione "in un colpo solo"
## (utile per test), ma l'uso normale è: instanziare vuoto, poi `add_segment`
## ripetuti a ogni tick della sonda della lama.
##
## ─── TODO: morire come si è nati, al contrario ──────────────────────────────
## Oggi il muro nasce UN TRATTO ALLA VOLTA, seguendo la lama, e muore TUTTO
## INSIEME con una dissolvenza uniforme di `FADE`. È un'asimmetria che si vede:
## la nascita racconta il gesto, la morte no.
##
## Va reso simmetrico — i tratti si spengono in sequenza, nell'ordine in cui
## sono nati (o al contrario), così il muro si "ritira" invece di svanire in
## blocco. Il dato per farlo c'è già: `_membranes` e `_particles` sono array
## ORDINATI di nascita, e basta dare a ciascun tratto la propria `life`
## sfalsata invece di condividere un solo `_membrane_mat` per tutto il muro.
##
## ⚠️ Proprio quel materiale condiviso è l'ostacolo: è UNO per muro (scelta
## fatta perché i segmenti di una stessa spadata hanno la stessa età). Per
## spegnerli sfalsati servono materiali per-segmento — o un `INSTANCE_CUSTOM`
## con l'istante di nascita, che è la strada che NON rompe il batching.

## Opzionale: se popolato PRIMA di aggiungere alla scena, costruisce subito
## tutto il percorso in un colpo. L'uso normale (il boss) lascia questo vuoto
## e chiama `add_segment()` mentre la lama swinga.
var path : PackedVector3Array = PackedVector3Array()  ## punti mondo dove è passata la lama
var move : Resource = null      ## la EnemyMove (damage_type + status)
var source : Node = null        ## chi ha tirato il fendente, escluso dai contatti
var duration : float = 6.0
var tick_damage : int = 4
var tick_interval : float = 0.55

## ─── Di chi è il muro ───────────────────────────────────────────────────────
## Nasce come mossa del boss, ma la stessa spada finisce in mano al giocatore:
## la Spada del Senza Nome porta con sé il suo Rovescio Risonante come Lucida
## Tecnica. Il muro è lo stesso oggetto — stessa membrana, stesso fuoco, stessa
## traccia della lama — cambia solo CHI brucia. Tenerne due copie significherebbe
## far divergere l'aspetto della mossa del boss da quella del giocatore, che è
## esattamente ciò che la Lucida Tecnica NON deve fare: deve essere riconoscibile
## come lo stesso colpo.
##
## Chi brucia NON si dichiara: lo deduce `Fazioni` dal `source`. Qui resta solo
## la maschera fisica, che è una domanda diversa — non "chi è nemico" ma "chi
## l'Area3D riesce a vedere". Il boss vede il layer del giocatore, il giocatore
## quello delle sue stesse lame.
var collision_mask : int = 2

## Deroga ESPLICITA al fuoco amico. Chi può essere ferito lo decide `Fazioni`,
## che è la stessa risposta che danno proiettili ed evocazioni: qui si dichiara
## soltanto se QUESTA mossa è una di quelle che pagano la propria forza col
## rischio di bruciare i propri.
var friendly_fire : bool = false

const HEIGHT := 2.0             ## il muro sale da terra: ci cammini dentro, non ci passi sotto
const THICKNESS := 0.5
const FADE := 1.0               ## dissolvenza finale: sparire di colpo è illeggibile
const MIN_SEGMENT_LEN := 0.05

var _area : Area3D = null
var _tick_accum : float = 0.0
var _age : float = 0.0
var _particles : Array[GPUParticles3D] = []
var _membranes : Array[MeshInstance3D] = []
var _segment_count : int = 0

func _ready() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = collision_mask
	_area.monitoring = true
	add_child(_area)
	# Costruzione "in un colpo solo", se qualcuno ha popolato `path` a monte
	# (uso non standard: normalmente si chiama add_segment mentre si swinga).
	for i in range(path.size() - 1):
		add_segment(path[i], path[i + 1])

## Pianta UN tratto di muro, subito: collisione + fuoco nell'istante in cui
## viene chiamato. Il boss lo chiama ripetutamente durante lo swing, un
## tratto alla volta, man mano che la sonda della lama avanza.
func add_segment(a : Vector3, b : Vector3) -> void:
	if _area == null:
		return   # chiamato prima di _ready o dopo la distruzione: ignora
	var mid : Vector3 = (a + b) * 0.5
	var seg : Vector3 = b - a
	var len : float = seg.length()
	if len < MIN_SEGMENT_LEN:
		return
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(THICKNESS, HEIGHT, maxf(len, 0.2))
	cs.shape = box
	# ⚠️ add_child PRIMA di toccare global_position/look_at: su un nodo fuori
	# dall'albero `global_position` non ha significato e `look_at_*` non ha un
	# frame di riferimento. Posizionandoli prima, i box finivano altrove mentre
	# le particelle (aggiunte per prime, e quindi corrette) restavano al posto
	# giusto: si vedeva il muro e non colpiva.
	_area.add_child(cs)
	# il muro poggia a terra e sale: la Y del percorso non conta, conta dove
	# la lama è passata in pianta.
	var flat := Vector3(seg.x, 0.0, seg.z)
	var at := Vector3(mid.x, HEIGHT * 0.5, mid.z)
	if flat.length() > 0.01:
		cs.look_at_from_position(at, at + flat, Vector3.UP)
	else:
		cs.global_position = at
	_spawn_membrane(Vector3(mid.x, 0.0, mid.z), maxf(len, 0.2), flat)
	_spawn_fire(Vector3(mid.x, 0.0, mid.z), maxf(len, 0.2), flat)
	_segment_count += 1

## Superficie del tratto di muro: un quad verticale piantato lungo il segmento.
##
## Le particelle da sole non bastavano — dicono "qui succede qualcosa", non
## "qui c'è una parete", e in isometrica il confine della zona che fa danno
## spariva. Il quad ha la stessa lunghezza e la stessa altezza del BoxShape3D
## di collisione: il segno grafico È la hitbox, come già fa `_burst_ring` per
## la scarica radiale, non una sua approssimazione.
func _spawn_membrane(at : Vector3, seg_len : float, dir : Vector3) -> void:
	if _membrane_mat == null:
		_membrane_mat = ArcaniumVFX.erosion_wall_material(EROSION_TINT, 1.5)
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	## Larghezza MAGGIORATA rispetto al segmento: sulla curva della spadata due
	## quad consecutivi sono angolati tra loro e, se lunghi esatti, lasciano un
	## cuneo vuoto sul lato esterno — a schermo si vedevano fessure nere nel
	## muro. Sovrapponendoli un filo, la parete resta continua.
	qm.size = Vector2(seg_len * 1.18, HEIGHT)
	mi.mesh = qm
	mi.material_override = _membrane_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	## Il quad nasce nel piano XY guardando +Z, quindi va ruotato per stendersi
	## LUNGO il segmento: look_at lo orienta col -Z verso `dir`, e la larghezza
	## (la sua X) finisce parallela al muro. Centrato a mezza altezza.
	var pos := Vector3(at.x, HEIGHT * 0.5, at.z)
	if dir.length() > 0.01:
		mi.look_at_from_position(pos, pos + dir.normalized().cross(Vector3.UP), Vector3.UP)
	else:
		mi.global_position = pos
	_membranes.append(mi)

func _spawn_fire(at : Vector3, seg_len : float, dir : Vector3) -> void:
	var p := GPUParticles3D.new()
	add_child(p)
	p.global_position = at
	p.amount = 48
	p.lifetime = 1.1
	p.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.12, 0.05, maxf(seg_len, 0.2) * 0.5)
	mat.direction = Vector3.UP
	mat.spread = 12.0
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, 0.4, 0)      # sale, non cade: è erosione, non fuoco vero
	mat.scale_min = 0.10
	mat.scale_max = 0.26
	var grad := Gradient.new()
	grad.set_color(0, Color(0.75, 0.35, 1.0, 0.95))
	grad.set_color(1, Color(0.15, 0.05, 0.35, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	p.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.26, 0.55)
	# Volute che salgono dal terreno: smoke_wisp ha il bordo sfrangiato che il quad
	# nudo non aveva. Additivo, come gli altri emettitori del boss.
	qm.material = BossVFX.particle_material(BossVFX.TEX_SMOKE, Color(0.8, 0.45, 1.0), 2.6)
	p.draw_pass_1 = qm
	if dir.length() > 0.01:
		p.look_at_from_position(p.global_position, p.global_position + dir, Vector3.UP)
	p.emitting = true
	_particles.append(p)

## Il player sta bruciando dentro a QUESTO muro? Serve a non riaprire il lamento
## a ogni tick e a chiuderlo quando esce (o quando il muro muore con lui dentro).
var _lamento_aperto : bool = false

func _aggiorna_lamento(dentro : bool) -> void:
	if dentro == _lamento_aperto:
		return
	_lamento_aperto = dentro
	if dentro:
		Suoni.dolore_continuo_avvia()
	else:
		Suoni.dolore_continuo_ferma()


## ⚠️ Il muro puo' sparire mentre ci sei dentro, e in quel caso `_physics_process`
## smette di girare senza passare da `_aggiorna_lamento(false)`: il lamento
## resterebbe acceso per sempre. Si chiude qui, che e' l'unico punto attraversato
## da OGNI fine del muro.
func _exit_tree() -> void:
	_aggiorna_lamento(false)


func _physics_process(delta : float) -> void:
	_age += delta
	if _age >= duration:
		_aggiorna_lamento(false)
		# dissolvenza invece di sparizione secca, poi via
		for p in _particles:
			if is_instance_valid(p):
				p.emitting = false
		if _area:
			_area.monitoring = false
		## La membrana si spegne INSIEME alla collisione, non prima e non dopo:
		## finché si vede la parete, la parete fa male. `life` scende sull'intera
		## FADE, così il muro si dissolve invece di scomparire di colpo.
		if _membrane_mat:
			_membrane_mat.set_shader_parameter(
				"life", clampf(1.0 - (_age - duration) / maxf(FADE, 0.01), 0.0, 1.0))
		if _age >= duration + FADE:
			queue_free()
		return
	# Danno a TICK finché ci resti dentro: è il punto della mossa — non un colpo,
	# una zona che ti nega il terreno.
	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum = 0.0
	if _area == null or not _area.monitoring:
		return
	## Il player e' dentro al fuoco? Il lamento continuo si accende e si spegne
	## con la sua PRESENZA, non col singolo tick: un lamento riavviato a ogni
	## tick sarebbe un balbettio.
	var player_dentro := false
	for body in _area.get_overlapping_bodies():
		if body.is_in_group("player"):
			player_dentro = true
		if not Fazioni.colpibile(body, source, friendly_fire):
			continue
		# La EnemyMove è CONDIVISA fra tutte le esecuzioni: va duplicata prima di
		# cambiarle la potenza, o il danno del tick resterebbe appiccicato alla
		# mossa per sempre (stesso pattern di equipment_system.gd sui colpi forti).
		var info : Resource = move
		if move != null:
			info = move.duplicate()
			info.power = tick_damage
			if "builds_echo" in info:
				info.builds_echo = true
		body.hit(source, info)
	_aggiorna_lamento(player_dentro)
