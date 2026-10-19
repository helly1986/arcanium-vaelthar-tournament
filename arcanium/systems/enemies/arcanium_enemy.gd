extends CharacterBody3D
class_name ArcaniumEnemy

## ═══════════════════════════════════════════════════════════════════════════
## SUPERCLASSE DI TUTTI I NEMICI DI ARCANIUM
## ═══════════════════════════════════════════════════════════════════════════
##
## Qui vive SOLO ciò che vale per qualunque creatura ostile, a prescindere da
## quante zampe abbia, da come consegni il danno e da quanto sia importante:
##
##   • ciclo di vita (aggancio all'HealthSystem, danno subito, morte, despawn)
##   • acquisizione del bersaglio (il più vicino tra player e minion evocati)
##   • locomozione a velocity + facing a tre fasi (windup → snap → rilascio)
##   • selezione data-driven della mossa (pesi, cooldown, anti-ripetizione, catene)
##   • esecuzione di una mossa a ISTANTI DI CONTATTO dichiarati nei dati
##   • un `_physics_process` scritto come template method, con hook virtuali
##
## Le sottoclassi non riscrivono il ciclo: ne sovrascrivono i punti d'innesto.
##
## ─── Gerarchia ──────────────────────────────────────────────────────────────
##   ArcaniumEnemy                     (questo file)
##   ├── ArcaniumQuadrupedEnemy        branco, fuga, balzo — lupi
##   └── ArcaniumHumanoidEnemy         arma su mount, poise-break, finisher
##       │                             subiti — Consumato
##       └── ArcaniumBoss              fase 2, proiettili, boss bar — Senza Nome
##
## ─── Perché un nemico COMUNE non deve girare sul controller del boss ────────
## Storicamente il Consumato usava `arcanium_boss.gd` tarato al ribasso. Non era
## solo inelegante: si portava dietro comportamenti che su un comune sono BUG.
## Il caso da manuale è l'istante del colpo. Il boss ha una lama FISICA e decide
## il contatto con una sonda; il Consumato non ce l'ha, quindi ricadeva su un
## timer piazzato a `telegraph / anim_speed_scale` = 1.4/0.7 = 2.0 s, scollegato
## da quando la lancia si vede arrivare. Qui l'istante del colpo è un DATO della
## mossa (`EnemyMove.contact_times`): una sola verità, condivisa da animazione e
## gameplay.
##
## ─── Punti di estensione previsti ───────────────────────────────────────────
##  • nemici con N arti / più armi → `EnemyMove.hitbox` nomina l'Area3D da usare
##    per quella mossa (vedi ArcaniumHumanoidEnemy._resolve_hitbox). Una creatura
##    con coda e quattro braccia non richiede un nuovo controller: solo altri
##    nodi hitbox e il nome giusto nel move set.
##  • creature senza scheletro (softbody, sciami): basta sovrascrivere `_play()`
##    e `_anim_len()` — nessun'altra parte del ciclo guarda lo scheletro.
##  • doppi boss / nemici coordinati: `engaged` e `on_ally_died()` sono già il
##    canale con cui reagire l'uno all'altro (il branco lo usa per la fuga).
##  • fasi multiple: `_in_phase2()`, `_max_chain()`, `_chain_mult()` e
##    `_pre_combat_step()` sono virtuali proprio per questo.

# ─── Riferimenti di scena ────────────────────────────────────────────────────
@export var move_set : EnemyMoveSet
@export var model : Node3D
@export var anim_player : AnimationPlayer
@export var health_system : HealthSystem

@export_group("Movimento")
@export var walk_speed : float = 1.8
@export var run_speed : float = 4.2
@export var aggro_range : float = 12.0
## ─── PROVOCAZIONE ───────────────────────────────────────────────────────────
## Chi viene COLPITO smette di preoccuparsi di `aggro_range` e ti viene addosso.
##
## Senza questo si poteva uccidere l'Alpha del Branco Guasto standosene accanto
## al Cono del Maestro di Evocazioni, a venti metri, tirandogli Schegge di
## Ghiaccio: il colpo arrivava, `hit()` impostava correttamente il bersaglio, e
## nello stesso frame `_ai_step` lo buttava via perche' la distanza superava i
## dodici metri del raggio d'ingaggio. Il nemico ti riconosceva e ti dimenticava
## dentro lo stesso fotogramma.
##
## ⚠️ Non e' una svista da tappare, e' la regola del genere: in un souls colpire
## qualcosa da lontano LO CHIAMA. Il raggio d'ingaggio serve a chi non ti ha
## ancora notato — smette di valere nell'istante in cui gli fai male.
##
## Si RINNOVA a ogni colpo: finche' continui a bersagliarlo non si calma.
##
## ⚠️ ERA 25 SECONDI E SENZA LIMITE DI DISTANZA: i Consumati inseguivano per
## mezzo livello, e in prova la cosa si notava subito («mi seguivano troppo»).
## La provocazione deve svegliare chi hai colpito, non trasformarlo in un
## segugio — anche perche' un nemico che ti segue ovunque smonta il ritmo dei
## tratti, che e' costruito sull'idea che un gruppo appartenga a un posto.
@export var provocazione_durata : float = 12.0
## ⚠️ E il GUINZAGLIO: oltre questa distanza la provocazione decade comunque,
## anche se il tempo non e' scaduto. Un raggio d'ingaggio che si puo' annullare
## per sempre con un colpo da lontano non e' piu' un raggio d'ingaggio.
## Espresso come multiplo di `aggro_range`, cosi' scala da solo su nemici con
## sensi diversi.
@export var provocazione_guinzaglio : float = 2.5
var _provocato_fino : float = 0.0
## Oltre questa distanza corre invece di camminare.
@export var run_distance : float = 3.5
@export var turn_rate : float = 3.0
## Moltiplicatore di `turn_rate` nella finestra di SNAP (fine telegraph): il
## nemico aggancia deciso il bersaglio un istante prima di colpire.
@export var snap_turn_mult : float = 6.0
## Moltiplicatore di `turn_rate` durante il WINDUP: ti insegue mentre carica,
## altrimenti i colpi partono sempre puntati dove NON sei più.
@export var windup_turn_mult : float = 1.8
## Banda morta attorno alla soglia di combattimento. Senza, il nemico oscilla
## idle/walk a ogni frame sul filo del centimetro, e ogni flip fa RIPARTIRE la
## clip da capo: sembrano finte, sono jitter.
@export var chase_hysteresis : float = 0.6

@export_group("Animazioni")
## Moltiplicatore globale di velocità (1.0 = nativa). NON serve più scalare i
## tempi di gioco a mano: i contatti si leggono dal playhead, che è già in
## tempo-clip (vedi `_advance_attack_timeline`).
@export_range(0.1, 2.0, 0.01) var anim_speed_scale : float = 1.0

## CROSS-FADE fra una clip e la successiva, in secondi. 0 = taglio netto.
##
## Era fisso a 0 con questa motivazione scritta nel codice: «clip d'attacco che
## non condividono esattamente le stesse tracce-osso mostrano una posa
## intermedia degenere per tutta la durata del blend». **Misurato e caduto**: le
## 19 clip del pack hanno 237 canali IDENTICI (unione = intersezione), quindi
## nessun osso può ricadere sulla rest a metà fusione. L'ipotesi valeva forse
## prima della migrazione; oggi no.
##
## Resta a 0 di default per non cambiare sotto i piedi boss e lupo, che hanno
## sorgenti diverse e vanno verificati uno per uno.
##
## ⚠️ Le clip SINCRONIZZATE con qualcos'altro (morte, coppie victim/getup che
## combaciano al frame con le clip del player) passano `xfade_override = 0`: una
## fusione le sposta di quel tanto e la sincronia salta.
@export_range(0.0, 0.5, 0.01) var anim_xfade : float = 0.0
## Tabella degli istanti di contatto misurati dalle clip. Vuota = si ripiega
## sulla tabella di progetto, e in mancanza di quella su `EnemyMove.telegraph`.
@export var timing : AttackTiming
@export var idle_anim : String = "idle"
@export var walk_anim : String = "walk"
@export var run_anim : String = "run"
@export var death_anim : String = "death"
@export var hurt_anim : String = "hit"
## Durata del blocco dopo un colpo subito (reazione di dolore).
@export var hurt_lock_time : float = 0.2

@export_group("Interfaccia")
## Barretta di vita flottante sopra la testa, che appare quando il nemico
## incassa. I mini-boss e i boss la spengono: hanno la barra a fondo schermo, e
## due indicatori sullo stesso avversario si contraddicono a vicenda.
@export var show_floating_health : bool = true
## Altezza della barretta sopra l'origine del nemico. A 0 si deduce dall'altezza
## reale della sua collisione, che è la cosa giusta con nemici scalati (un lupo
## a 2.6 e un Alpha a 4.0 non possono condividere un offset fisso).
@export var floating_health_height : float = 0.0

@export_group("Morte")
## Il cadavere si dissolve da solo dopo la clip di morte.
@export var despawn_after_death : bool = true
## Attesa extra dopo la fine della clip di morte, prima di dissolversi.
@export var despawn_extra_delay : float = 0.7

## Se false il nemico insegue e si gira ma NON sceglie mosse da solo: attacca
## solo su `debug_force_move`. Serve al Battle Playground — con pesi e catene,
## aspettare che il random peschi la mossa da testare è una lotteria.
@export var ai_enabled : bool = true

## Stati condivisi da tutta la gerarchia. In GDScript un enum non è estendibile,
## quindi vivono tutti qui anche se non ogni sottoclasse li usa: FLEE è del
## branco, STAGGERED/VICTIM degli umanoidi.
enum State { IDLE, CHASE, COMBAT, DEAD, STAGGERED, VICTIM, FLEE }

const OrologioGioco := preload("res://arcanium/systems/orologio_gioco.gd")

## Penalità al peso della mossa appena usata (e della penultima): rompe la
## ripetizione senza vietarla.
const REPEAT_PENALTY := 0.2
const REPEAT2_PENALTY := 0.55
## Sblocco d'emergenza se UNA mossa resta appesa (coroutine che non si risolve).
## È per-MOSSA e non per-catena: misurarlo sulla catena tronca a metà le combo
## lunghe legittime.
const BUSY_SAFETY_MAX := 9.0
## Ogni quanto si ri-valuta chi è il bersaglio (inutile farlo a ogni frame).
const RETARGET_INTERVAL := 0.5
## Finestra massima di snap-turn, in secondi: oltre, l'aggancio degenera in
## tracking reattivo per tutta la carica e il colpo diventa inschivabile.
const SNAP_WINDOW_MAX := 0.45
## Tolleranza di portata per un follow-up di catena: con una soglia secca le
## catene non partivano quasi mai (il bersaglio si sposta durante il colpo prima).
const CHAIN_RANGE_BUFFER := 1.2
## Sotto questa distanza l'arco frontale non conta: sei talmente addosso che il
## colpo ti prende comunque.
const CLOSE_ARC_FREE_DIST := 1.2

signal damage_taken(by_what)
signal death_started
## Emesso al primo aggro: la boss bar souls-style si aggancia qui.
signal engaged

var target : Node3D
var _state : State = State.IDLE
var _gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Una mossa è in esecuzione: sospende AI e locomozione ordinaria.
var _busy : bool = false
var _hurt_lock : float = 0.0
var _next_attack : float = 0.0
var _cooldown_until : Dictionary = {}
var _last_move : String = ""
var _second_last : String = ""
var _current_anim : String = ""
## Vero solo nella finestra finale del telegraph: vedi `snap_turn_mult`.
var _snap_turn : bool = false
## Vero dal RILASCIO del colpo alla fine della mossa: blocca del tutto il
## facing, così lo swing resta dove era puntato e la schivata a tempo paga.
var _attack_released : bool = false
var _move_since : float = 0.0
var _has_engaged : bool = false
var _retarget_t : float = 0.0

## Mossa in esecuzione e i suoi contatti ancora da consegnare, in TEMPO-CLIP
## (vedi `_advance_attack_timeline`). Si svuota man mano che il playhead li
## attraversa.
var _active_move : EnemyMove = null
var _pending_contacts : PackedFloat32Array = PackedFloat32Array()
var _released_this_move : bool = false

## Percorso della tabella dei tempi di progetto, generata da
## `arcanium/tools/measure_attack_contacts.gd`.
const TIMING_PATH := "res://arcanium/resources/attack_timing.tres"
static var _shared_timing : AttackTiming = null


# ═══════════════════════════════════════════════════════════════════════════
# Ciclo di vita
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("targets")
	add_to_group("arcanium_enemy")
	collision_layer = 5   # come il nemico del template: colpibile dall'arma del player
	if health_system:
		health_system.died.connect(_on_died)
		## ⚠️ La barretta segue il SEGNALE, non i punti in cui si incassa un
		## colpo. Prima la aggiornavano due chiamate a mano — `hit()` e la
		## parata — e tutto il resto le passava sotto il naso: il veleno,
		## l'Erosione dell'Eco, il drenaggio del Senza Nome, le cure. Il
		## giocatore vedeva un nemico consumarsi con la barretta ferma.
		if health_system.has_signal("health_updated"):
			health_system.health_updated.connect(_on_health_updated)
	if anim_player:
		anim_player.animation_finished.connect(_on_anim_finished)
	target = _nearest_player_target()
	_setup()
	_play(idle_anim, true)


## Innesto d'inizializzazione delle sottoclassi: chiamato quando segnali e
## bersaglio sono pronti, prima della prima clip. Evita di dover sovrascrivere
## `_ready()` ricordandosi di `super()` nel punto giusto.
func _setup() -> void:
	pass


# ═══════════════════════════════════════════════════════════════════════════
# Ciclo di fisica — template method
# ═══════════════════════════════════════════════════════════════════════════
## L'ordine qui è vincolante e ogni riga ha un motivo. Le sottoclassi non lo
## riscrivono: innestano nei punti virtuali (`_special_state_step`,
## `_pre_ai_step`, `_attack_motion`, `_pre_combat_step`).

## ─── LA SPINTA ──────────────────────────────────────────────────────────────
## Un colpo che SPOSTA: la freccia del protagonista (e domani altro). Impulso
## orizzontale smaltito a `SPINTA_DECADIMENTO` m/s^2, applicato con
## `move_and_collide` PRIMA di qualunque ramo — `_chase`, `_attack_motion` e
## lo stagger riscrivono `velocity` ogni frame, e sommarla li' vorrebbe dire
## sommarla in quattro posti. Un muro la ferma; un bordo no: un nemico in
## bilico su una piattaforma si butta giu', ed e' il modo in cui il giocatore
## restituisce la tattica degli arcieri. In guardia se ne prende la meta'.
const SPINTA_DECADIMENTO : float = 10.0
var _spinta : Vector3 = Vector3.ZERO

func spingi(verso : Vector3, forza : float) -> void:
	if _state == State.DEAD or forza <= 0.0:
		return
	if _para():
		forza *= 0.5
	var v := Vector3(verso.x, 0.0, verso.z)
	if v.length() < 0.01:
		return
	_spinta = v.normalized() * forza

## Vero se il nemico sta parando: lo dichiara chi ha una guardia (l'umanoide,
## che ha gia' una variabile `_in_guardia` per la posa: qui e' l'atto).
func _para() -> bool:
	return false

func spinta_in_corso() -> Vector3:
	return _spinta

func _applica_spinta(delta : float) -> void:
	if _spinta.length() < 0.01:
		_spinta = Vector3.ZERO
		return
	move_and_collide(_spinta * delta)
	_spinta = _spinta.move_toward(Vector3.ZERO, SPINTA_DECADIMENTO * delta)

func _physics_process(delta : float) -> void:
	if _state == State.DEAD:
		velocity = Vector3.ZERO
		return
	_applica_spinta(delta)

	# Stati che sospendono l'AI e gestiscono da soli il movimento (stagger,
	# finisher subito, fuga, transizione di fase). Se uno se ne fa carico, il
	# frame è suo e finisce qui.
	if _special_state_step(delta):
		return

	_apply_gravity(delta)

	if _hurt_lock > 0.0:
		_hurt_lock -= delta

	_update_target(delta)

	# Contatti e finestre d'arma si leggono dal playhead: PRIMA del facing, così
	# lo snap-turn e il blocco al rilascio valgono già in questo frame.
	_advance_attack_timeline()

	# Innesto PRIMA di ogni ramo che può uscire: qui vanno le cose che devono
	# girare anche durante un attacco (drenaggio della root motion, sonda della
	# lama, studio del movimento del bersaglio). Metterle più in basso
	# significherebbe non eseguirle mai proprio durante gli attacchi.
	_pre_ai_step(delta)

	_busy_watchdog()
	_update_facing(delta)

	# Durante una mossa (o l'hit-stun) la locomozione ordinaria è sospesa: ci si
	# muove solo di quanto dice la mossa.
	if _busy or _hurt_lock > 0.0:
		_attack_motion(delta)
		move_and_slide()
		return

	# Qui `_busy` è già falso: una transizione di fase innestata adesso non
	# interrompe una catena in volo (il boss finisce lo swing, POI cambia fase).
	if _pre_combat_step():
		return

	_ai_step(delta)
	move_and_slide()


func _apply_gravity(delta : float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0


## Decisione base: attacca se puoi, altrimenti avvicinati, altrimenti aspetta.
func _ai_step(delta : float) -> void:
	if not is_instance_valid(target):
		_go_idle()
		return
	var dist := _flat_distance(target)
	## Fuori raggio si torna a riposo — a meno di essere stati PROVOCATI: chi ti
	## ha colpito lo insegue, e il raggio d'ingaggio vale solo per chi non ti ha
	## ancora notato.
	## Fuori raggio si torna a riposo — a meno di essere stati PROVOCATI, che
	## vale pero' solo entro il guinzaglio: chi ti ha colpito ti insegue, ma non
	## fino all'altro capo del livello.
	if dist > aggro_range * provocazione_guinzaglio:
		_provocato_fino = 0.0
	## Chi sta andando per una scala verso il bersaglio resta ingaggiato anche
	## se il giro lo porta oltre `aggro_range`: al piede della scala del
	## cancello si e' a 15 m dal muro, e i Fanti tornavano a riposo proprio li'.
	var per_la_scala := _in_salita() and dist <= aggro_range * provocazione_guinzaglio
	if dist > aggro_range and _now() > _provocato_fino and not per_la_scala:
		_go_idle()
		return
	## Sotto ORDINE e non di turno: si va al proprio posto dell'accerchiamento
	## e li' si aspetta, rivolti al bersaglio. Niente attacchi: li coordina il
	## Comandante, uno alla volta.
	if not _in_salita():
		var posto : Variant = _posto_d_ordine()
		if posto != null:
			var dp := Vector2((posto as Vector3).x - global_position.x, (posto as Vector3).z - global_position.z).length()
			if dp > POSTO_ARRIVO:
				_chase(delta, dist)
			else:
				_go_idle()
			return
	# Si prova SEMPRE ad attaccare prima di decidere se inseguire: una mossa a
	# lunga portata (un affondo) deve poter partire da lontano e chiudere il gap
	# da sola durante il telegraph, non solo dopo che l'inseguimento l'ha già
	# portata a distanza melee — altrimenti l'affondo arriva "già arrivato".
	if _try_attack(dist):
		return
	## Il bersaglio sta su un altro piano (un muro, un ballatoio) e c'e' una
	## scala: si va per la scala, anche se in pianta e' gia' "a portata".
	if _in_salita():
		_chase(delta, dist)
		return
	var stop_at := _combat_range()
	var threshold : float = stop_at if _state == State.CHASE else stop_at + chase_hysteresis
	if dist > threshold:
		_chase(delta, dist)
	else:
		_go_idle()


# ═══════════════════════════════════════════════════════════════════════════
# L'ORDINE di un Comandante
# ═══════════════════════════════════════════════════════════════════════════
##
## Un Comandante Consumato (③) tiene un nodo `OrdineComandante`
## (arcanium/systems/enemies/ordine_comandante.gd) che arruola i fanti attorno
## e scrive qui se stesso. Finche' c'e', il fante non va dritto sul bersaglio:
## va al POSTO che l'ordine gli assegna attorno al giocatore (l'accerchiamento)
## e attacca solo quando e' il suo TURNO. Morto il Comandante l'ordine si
## scioglie, `ordine` torna null e il fante torna singolo: va dritto, attacca
## quando puo', si intralcia con gli altri. Nessun'altra parte del nemico sa
## che l'ordine esiste.
var ordine : Node = null
## A quanto dal posto assegnato lo si da' per raggiunto. Stretto: l'anello
## sta un metro fuori dalla portata dei fendenti, e con 0,8 un fante in attesa
## poteva fermarsi quasi a portata.
const POSTO_ARRIVO := 0.5


## Il posto assegnato dall'ordine, o null (nessun ordine, o e' il mio turno).
func _posto_d_ordine() -> Variant:
	if ordine == null or not is_instance_valid(ordine):
		ordine = null
		return null
	return ordine.posto_per(self)


# ═══════════════════════════════════════════════════════════════════════════
# Dislivelli: gli ACCESSI RIALZATI
# ═══════════════════════════════════════════════════════════════════════════
##
## Nessun nemico ha un navmesh: insegue in linea retta, e finche' il terreno e'
## uno funziona. Con il passo fortificato di Kalvorn (2026-09-25) il giocatore
## puo' salire sul muro, e i Fanti restavano sotto a guardarlo — o a menare
## fendenti al vento, perche' in pianta erano "a portata".
##
## Un accesso e' un nodo nel gruppo `accesso_rialzato` con due figli `Basso` e
## `Alto`: i due capi di una scala (li mette chi costruisce la scala, vedi
## `_build_scala_cancello` in kalvorn_builder.gd). Se il bersaglio sta piu' di
## `DISLIVELLO` sopra o sotto, si cammina al capo del proprio piano, poi
## all'altro; di li' in poi l'inseguimento e' quello di sempre. Il facing punta
## il capo invece del bersaglio, e la root motion fa il resto.
##
## E nel frattempo niente mischia: una lama non arriva a un bersaglio tre metri
## piu' su, qualunque cosa dica la distanza in pianta.
const DISLIVELLO := 1.8
const GRUPPO_ACCESSI := "accesso_rialzato"
## Oltre questa distanza (in pianta) una scala non la si considera: e' di un
## altro posto.
const ACCESSO_PORTATA := 40.0
## A quanto dal primo capo lo si da' per raggiunto.
const ACCESSO_ARRIVO := 2.0

var _accesso : Node3D = null
var _accesso_fase : int = 0


## Il bersaglio e' su un altro piano, e c'e' una scala per arrivarci.
func _in_salita() -> bool:
	_punto_di_marcia()
	return _accesso != null


## Il punto verso cui si cammina: il bersaglio, un capo della scala, o la
## bocca dell'arco se in mezzo c'e' il muro.
func _punto_di_marcia() -> Vector3:
	var meta := _meta_di_marcia()
	var via : Variant = _attraversamento(meta)
	return via if via != null else meta


## ─── I PASSAGGI: un muro si attraversa dall'arco ───────────────────────────
## Un passaggio e' un nodo nel gruppo `passaggio`, orientato come il muro che
## attraversa (+Z e -Z i due lati, X lungo il muro), con tre misure in meta:
## `semilarghezza` del muro, `profondita` (mezzo spessore, arco compreso) e
## `mezza_luce` dell'apertura. Se io e la mia meta stiamo da parti opposte e la
## linea dritta non passa gia' per l'apertura, si va alla bocca dell'arco dal
## proprio lato, poi a quella di fronte, e dentro l'arco si torna dritti.
## Senza, un Fante uscito dall'arco a inseguire il giocatore, e poi richiamato
## dall'altra parte (sul muro, per la scala), spingeva contro la pietra.
const GRUPPO_PASSAGGI := "passaggio"
## Quanto fuori dallo spessore del muro sta la bocca, e a quanto la si prende.
const PASSAGGIO_BOCCA := 2.5
const PASSAGGIO_ARRIVO := 1.0
## L'attraversamento in corso: il passaggio e il lato da cui si e' entrati.
var _passaggio : Node3D = null
var _passaggio_lato : float = 0.0
## Chi arriva alla scala di FIANCO (piu' avanti del piede, lungo l'asse) va
## prima al largo, davanti: dritto verso il piede sbatteva contro il fondo del
## corrimano e restava li'.
const ACCESSO_LARGO := 4.0
## Quanto avanti sull'asse della scala si mira mentre la si percorre.
const ACCESSO_MIRA := 2.0


func _attraversamento(meta : Vector3) -> Variant:
	## Un attraversamento gia' iniziato si finisce: si va alla bocca di fronte
	## finche' non si e' usciti dall'altra parte.
	if _passaggio != null and is_instance_valid(_passaggio):
		var pxf := _passaggio.global_transform
		var qui : Vector3 = pxf.affine_inverse() * global_position
		var pprof : float = float(_passaggio.get_meta("profondita", 2.6))
		var mq : Vector3 = pxf.affine_inverse() * meta
		## Finito (si e' dall'altra parte), o la meta e' tornata dal lato da cui
		## si era entrati: l'attraversamento non serve piu'.
		var finito : bool = signf(qui.z) == -_passaggio_lato and absf(qui.z) > pprof + 0.5
		var tornata : bool = signf(mq.z) == _passaggio_lato and absf(mq.z) > pprof
		if finito or tornata:
			_passaggio = null
		else:
			return pxf * Vector3(0.0, 0.0, -_passaggio_lato * (pprof + PASSAGGIO_BOCCA))
	_passaggio = null
	for n in get_tree().get_nodes_in_group(GRUPPO_PASSAGGI):
		var pas := n as Node3D
		if pas == null:
			continue
		var xf := pas.global_transform
		var inv := xf.affine_inverse()
		var io : Vector3 = inv * global_position
		var m : Vector3 = inv * meta
		var prof : float = float(pas.get_meta("profondita", 2.6))
		var semi : float = float(pas.get_meta("semilarghezza", 7.6))
		var luce : float = float(pas.get_meta("mezza_luce", 1.3))
		## Dentro lo spessore del muro (nell'arco, o sopra) si va dritti; e dallo
		## stesso lato non c'e' niente da attraversare.
		if absf(io.z) < prof or absf(m.z) < prof or signf(io.z) == signf(m.z):
			continue
		## Dove la linea dritta attraversa le due facce del muro. Oltre la
		## testata il muro non c'e'; se resta dentro la luce per TUTTO lo
		## spessore la linea e' gia' buona. ⚠️ Non basta guardarla a meta': le
		## torri sporgono davanti all'arco, e una linea che al centro passa
		## nella luce ma parte di fianco si pianta nello spigolo di una torre.
		var x_in : float = lerpf(io.x, m.x, (io.z - prof) / (io.z - m.z)) if io.z > 0.0 \
			else lerpf(io.x, m.x, (io.z + prof) / (io.z - m.z))
		var x_out : float = lerpf(io.x, m.x, (io.z + prof) / (io.z - m.z)) if io.z > 0.0 \
			else lerpf(io.x, m.x, (io.z - prof) / (io.z - m.z))
		if absf(x_in) > semi + 1.0 and absf(x_out) > semi + 1.0:
			continue
		if absf(x_in) < luce * 0.6 and absf(x_out) < luce * 0.6:
			continue
		## Le bocche stanno BEN fuori dall'arco e si prendono strette: arrivati a
		## una bocca larga di fianco, la linea verso l'altra tagliava lo spigolo
		## della torre e ci si piantava contro.
		var lato : float = signf(io.z)
		var bocca : Vector3 = xf * Vector3(0.0, 0.0, lato * (prof + PASSAGGIO_BOCCA))
		if Vector2(bocca.x - global_position.x, bocca.z - global_position.z).length() < PASSAGGIO_ARRIVO:
			## Raggiunta la bocca ci si IMPEGNA ad attraversare: senza memoria,
			## un passo verso l'arco riportava fuori dal raggio della bocca e la
			## meta tornava lei — avanti e indietro per quaranta secondi.
			_passaggio = pas
			_passaggio_lato = lato
			return xf * Vector3(0.0, 0.0, -lato * (prof + PASSAGGIO_BOCCA))
		return bocca
	return null


## La meta senza muri: il bersaglio, o un capo della scala.
func _meta_di_marcia() -> Vector3:
	if not is_instance_valid(target):
		_accesso = null
		return global_position
	var t : Vector3 = target.global_position
	var dy : float = t.y - global_position.y
	if absf(dy) < DISLIVELLO:
		_accesso = null
		_accesso_fase = 0
		var posto : Variant = _posto_d_ordine()
		return posto if posto != null else t
	if _accesso == null or not is_instance_valid(_accesso):
		_accesso = _accesso_per(t, dy > 0.0)
		_accesso_fase = 0
		if _accesso == null:
			return t
	var basso : Vector3 = (_accesso.get_node("Basso") as Node3D).global_position
	var alto : Vector3 = (_accesso.get_node("Alto") as Node3D).global_position
	var da : Vector3 = basso if dy > 0.0 else alto
	var a : Vector3 = alto if dy > 0.0 else basso
	var asse := Vector3(alto.x - basso.x, 0.0, alto.z - basso.z)
	var lungo_asse : float = asse.length()
	asse = asse / maxf(lungo_asse, 0.001)
	## Il primo capo e' raggiunto solo arrivandoci da DAVANTI: andando al largo
	## si passa a due metri dal piede stando ancora di fianco alla scala, e da
	## li' la salita partiva di sbieco contro il fondo del corrimano (tracciato
	## il 2026-09-25 in verifica_passo_fortificato).
	var davanti : bool = (global_position - basso).dot(asse) < -0.5 if dy > 0.0 else true
	if _accesso_fase == 0 and davanti \
			and Vector2(da.x - global_position.x, da.z - global_position.z).length() < ACCESSO_ARRIVO:
		_accesso_fase = 1
	if _accesso_fase == 0 and dy > 0.0:
		if (global_position - basso).dot(asse) > -1.0:
			return basso - asse * ACCESSO_LARGO
	if _accesso_fase == 1:
		## Sulla scala si segue l'ASSE, non il capo: la mira e' un punto
		## dell'asse `ACCESSO_MIRA` metri piu' avanti della propria proiezione.
		## Puntando dritto al capo da due metri di fianco si risaliva lungo il
		## fianco della scala, strisciando sul corrimano fino a piantarsi.
		var verso : float = 1.0 if dy > 0.0 else -1.0
		var lungo_q : float = (global_position - basso).dot(asse) + verso * ACCESSO_MIRA
		lungo_q = clampf(lungo_q, 0.0, lungo_asse)
		var q : Vector3 = basso + asse * lungo_q
		q.y = basso.y if dy > 0.0 else alto.y
		return q if absf(lungo_q - (lungo_asse if dy > 0.0 else 0.0)) > 0.01 else a
	return da


## La scala che porta al piano del bersaglio, la piu' vicina.
func _accesso_per(t : Vector3, sale : bool) -> Node3D:
	var migliore : Node3D = null
	var dmin := ACCESSO_PORTATA
	for n in get_tree().get_nodes_in_group(GRUPPO_ACCESSI):
		var acc := n as Node3D
		if acc == null or not acc.has_node("Basso") or not acc.has_node("Alto"):
			continue
		var arrivo : Vector3 = (acc.get_node("Alto" if sale else "Basso") as Node3D).global_position
		var partenza : Vector3 = (acc.get_node("Basso" if sale else "Alto") as Node3D).global_position
		## Porta al piano del bersaglio, e parte dal mio.
		if absf(arrivo.y - t.y) > DISLIVELLO or absf(partenza.y - global_position.y) > DISLIVELLO:
			continue
		var d := Vector2(partenza.x - global_position.x, partenza.z - global_position.z).length()
		if d < dmin:
			dmin = d
			migliore = acc
	return migliore


## La direzione in pianta verso cui si marcia (vedi `_punto_di_marcia`).
func _dir_di_marcia() -> Vector3:
	var d := _punto_di_marcia() - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO


## Rete di sicurezza: se una singola mossa resta appesa oltre BUSY_SAFETY_MAX,
## sblocca a forza invece di lasciare il nemico congelato per sempre.
func _busy_watchdog() -> void:
	if _busy and _now() - _move_since > BUSY_SAFETY_MAX:
		_busy = false
		_clear_move_state()
		if _state != State.DEAD:
			_play(idle_anim, true)


# ─── Innesti virtuali del ciclo ─────────────────────────────────────────────

## Ritorna true se ha gestito il frame per intero (stato speciale attivo).
func _special_state_step(_delta : float) -> bool:
	return false

## Gira ogni frame da vivo, anche durante gli attacchi.
func _pre_ai_step(_delta : float) -> void:
	pass

## Movimento durante una mossa. Default: fermo (clip in-place).
func _attack_motion(_delta : float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

## Ritorna true per saltare l'AI di questo frame (es. transizione di fase).
func _pre_combat_step() -> bool:
	return false

## Ripulisce lo stato di una mossa abortita (balzo, finestre d'arma, VFX).
## Le sottoclassi che la sovrascrivono devono chiamare `super()`: qui si
## disarmano i contatti ancora in coda, che altrimenti verrebbero consegnati
## dal playhead di una mossa che non esiste più.
func _clear_move_state() -> void:
	_active_move = null
	_pending_contacts = PackedFloat32Array()
	_snap_turn = false


# ═══════════════════════════════════════════════════════════════════════════
# Bersaglio
# ═══════════════════════════════════════════════════════════════════════════

func _update_target(delta : float) -> void:
	_retarget_t -= delta
	if _retarget_t > 0.0 and is_instance_valid(target):
		return
	_retarget_t = RETARGET_INTERVAL
	# Non si cambia bersaglio a metà mossa: lo swing è già impegnato.
	if not _busy:
		target = _nearest_player_target()


## Il più VICINO tra i bersagli leciti. Il gruppo "player" contiene il player
## vero E i minion evocati: il minion deve poter fare da esca, altrimenti
## evocarlo non ha alcun effetto tattico.
##
## NB: qui stava un difetto storico del controller boss, che prendeva
## `get_first_node_in_group("player")`, cioè un nodo QUALUNQUE del gruppo in
## ordine d'albero. Con un minion in campo poteva restare agganciato alla
## Scintilla dall'altra parte dell'arena mentre il player lo colpiva.
func _nearest_player_target() -> Node3D:
	var best : Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("player"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var d := _flat_distance(n)
		if d < best_d:
			best_d = d
			best = n
	return best


# ═══════════════════════════════════════════════════════════════════════════
# Locomozione e facing
# ═══════════════════════════════════════════════════════════════════════════

func _chase(_delta : float, dist : float) -> void:
	_state = State.CHASE
	if not _has_engaged:
		_has_engaged = true
		engaged.emit()
		_suona(_voce_ingaggio())
	var running := dist > run_distance
	var clip : String = run_anim if running else walk_anim
	_play(clip, true)
	var dir := _dir_di_marcia()
	## La velocità la dichiara la CLIP, se ce l'ha. Chi non ha root motion
	## ricade sui numeri di sempre, quindi questa riga non cambia niente per
	## gli umanoidi.
	var spd := _velocita_di_falcata(clip)
	if spd <= 0.0:
		spd = run_speed if running else walk_speed
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd


## Velocità di crociera che la CLIP dichiara, in metri al secondo di MONDO.
## `-1.0` se la clip non porta root motion: allora decide il chiamante.
##
## ⚠️ Perché non `get_root_motion_position()` fotogramma per fotogramma. Quella
## via dà lo spostamento accumulato dall'ultimo giro del mixer, e per farne una
## velocità bisogna dividerlo per il delta GIUSTO — che dipende da come è
## impostato `callback_mode_process` dell'AnimationPlayer, e che sulle
## transizioni fra clip produce picchi. Qui serve uno SCALARE stabile, perché la
## direzione la decide comunque lo sterzo verso il bersaglio (`_flat_dir_to`) e
## non l'animazione. Leggere la traccia dalla risorsa dà lo stesso numero,
## esatto, una volta sola e senza dipendere dal frame rate.
##
## Tre fattori, tutti necessari:
##   - la lunghezza dello spostamento dell'osso radice sull'intera clip;
##   - la SCALA del modello, perché il root motion è in unità di scheletro e il
##     lupo è scalato 2.6, l'Alpha 6.5. Senza, l'Alpha andrebbe a passo di lupo;
##   - `anim_speed_scale`, perché una clip riprodotta più lenta copre la stessa
##     distanza in più tempo.
var _falcata_per_clip : Dictionary = {}

func _velocita_di_falcata(nome : String) -> float:
	if _falcata_per_clip.has(nome):
		return _falcata_per_clip[nome]

	var v := -1.0
	if anim_player != null and anim_player.has_animation(nome) \
			and not anim_player.root_motion_track.is_empty():
		var a : Animation = anim_player.get_animation(nome)
		var i : int = a.find_track(anim_player.root_motion_track, Animation.TYPE_POSITION_3D)
		if i >= 0 and a.length > 0.0:
			var partenza : Vector3 = a.position_track_interpolate(i, 0.0)
			var arrivo : Vector3 = a.position_track_interpolate(i, a.length)
			var passo : float = (arrivo - partenza).length()
			if passo > 0.0001:
				var scala := 1.0
				if model != null:
					scala = model.global_transform.basis.get_scale().x
				v = passo * scala * anim_speed_scale / a.length

	_falcata_per_clip[nome] = v
	return v


func _go_idle() -> void:
	if _state == State.DEAD:
		return
	_state = State.IDLE
	velocity.x = 0.0
	velocity.z = 0.0
	_play(idle_anim, true)


## Facing a tre fasi (convenzione Souls): insegue generosamente nel windup,
## aggancia deciso nello snap, si BLOCCA dal rilascio in poi. Prima era un
## valore unico per tutto l'attacco: non ti cercava durante la carica e
## continuava a ruotarti dietro dopo il colpo — il peggio di due mondi.
func _update_facing(delta : float) -> void:
	if not is_instance_valid(target):
		return
	var face_mult := 1.0
	if _attack_released and _busy:
		# Legato a `_busy`: se la mossa viene abortita, il flag non può
		# sopravvivere lasciando il nemico cieco fino alla mossa successiva.
		face_mult = 0.0
	elif _snap_turn:
		face_mult = snap_turn_mult
	elif _busy:
		face_mult = windup_turn_mult
	if face_mult > 0.0:
		_face(delta, face_mult)


func _face(delta : float, rate_mult : float = 1.0) -> void:
	if not is_instance_valid(target):
		return
	## Inseguendo si guarda dove si marcia — il capo di una scala, la bocca di
	## un arco — non per forza il bersaglio: e' il facing a portare la root motion.
	var dir := _dir_di_marcia() if _state == State.CHASE else _flat_dir_to(target)
	if dir.length() < 0.01:
		dir = _flat_dir_to(target)
	if dir.length() < 0.01:
		return
	var yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(turn_rate * rate_mult * delta, 0.0, 1.0))


func _face_instant() -> void:
	if not is_instance_valid(target):
		return
	var dir := _flat_dir_to(target)
	if dir.length() > 0.01:
		rotation.y = atan2(dir.x, dir.z)


# ═══════════════════════════════════════════════════════════════════════════
# Selezione ed esecuzione delle mosse
# ═══════════════════════════════════════════════════════════════════════════

func _try_attack(dist : float) -> bool:
	if not ai_enabled or move_set == null or _now() < _next_attack:
		return false
	var move := _choose_move(dist)
	if move == null:
		return false
	_perform(move)
	return true


## Lancia una mossa PRECISA scavalcando pesi, cooldown e catene: il resto della
## pipeline è identico al gioco vero, il playground guida il nemico reale.
func debug_force_move(id : String, allow_chain : bool = false) -> bool:
	if move_set == null or _busy or _state == State.DEAD or _state == State.VICTIM:
		return false
	var m := move_set.find_move(id)
	if m == null:
		return false
	_cooldown_until.erase(m.id)
	_next_attack = 0.0
	_perform(m, allow_chain)
	return true


func _choose_move(dist : float) -> EnemyMove:
	var now := _now()
	var pool : Array[EnemyMove] = []
	var weights : Array[float] = []
	var su_altro_piano := is_instance_valid(target) and absf(target.global_position.y - global_position.y) >= DISLIVELLO
	for m in move_set.eligible(dist, _in_phase2()):
		if m.pick_weight <= 0.0 or now < float(_cooldown_until.get(m.id, 0.0)):
			continue
		## Una lama non arriva su un altro piano: solo i tiri.
		if su_altro_piano and m.projectile_scene == null:
			continue
		if not _move_is_usable(m):
			continue
		var w := m.pick_weight
		if m.id == _last_move:
			w *= REPEAT_PENALTY
		elif m.id == _second_last:
			w *= REPEAT2_PENALTY
		w *= _move_weight_multiplier(m)
		pool.append(m)
		weights.append(w)
	if pool.is_empty():
		return null
	return _weighted_pick(pool, weights)


## Filtro aggiuntivo per-sottoclasse (es. il boss scarta le mosse a distanza
## quando non ha linea di tiro libera).
func _move_is_usable(_move : EnemyMove) -> bool:
	return true

## Correzione contestuale del peso (es. punire chi kita a distanza).
func _move_weight_multiplier(_move : EnemyMove) -> float:
	return 1.0


## Esegue una CATENA a partire da `move`: apertura, poi i follow-up del combo
## graph finché non si esaurisce. Tra un colpo e l'altro solo `link_gap`; a fine
## catena la pausa lunga `chain_recovery`, che è la finestra di punizione.
func _perform(move : EnemyMove, allow_chain : bool = true) -> void:
	_busy = true
	_state = State.COMBAT
	var max_chain := _max_chain()
	var chain_mult := _chain_mult()

	var current := move
	var steps := 0
	while current != null:
		steps += 1
		await _execute_move(current)
		if _move_aborted():
			_busy = false
			return
		var nxt : EnemyMove = null
		if allow_chain and steps < max_chain:
			nxt = _pick_chain(current, chain_mult)
		if nxt != null:
			await get_tree().create_timer(move_set.link_gap).timeout
			if _move_aborted():
				_busy = false
				return
			_face_instant()   # riallineo tra un colpo e l'altro
		current = nxt

	_next_attack = _now() + move_set.chain_recovery
	_busy = false
	if _state != State.DEAD and _state != State.FLEE:
		_play(idle_anim, true)


## Stati in cui una mossa in corso va considerata annullata.
func _move_aborted() -> bool:
	return _state == State.DEAD or _state == State.STAGGERED \
		or _state == State.VICTIM or _state == State.FLEE


func _max_chain() -> int:
	return move_set.max_chain_p1 if move_set else 1

func _chain_mult() -> float:
	return 1.0


## Follow-up dal combo graph della mossa: vince la prima regola che passa banda
## (`when`), portata e tiro (`chance`).
func _pick_chain(move : EnemyMove, chain_mult : float) -> EnemyMove:
	if move.chains.is_empty() or move_set == null:
		return null
	var dist : float = _flat_distance(target) if is_instance_valid(target) else 9e9
	var now := _now()
	for rule in move.chains:
		var nxt := move_set.find_move(str(rule.get("next", "")))
		if nxt == null or now < float(_cooldown_until.get(nxt.id, 0.0)):
			continue
		var when := str(rule.get("when", "any"))
		if when == "melee" and dist > move_set.melee_threshold + CHAIN_RANGE_BUFFER:
			continue
		if when == "range" and dist <= move_set.melee_threshold:
			continue
		## ⚠️ La banda "stun" è l'unica CONDIZIONATA A UN ESITO invece che alla
		## distanza: passa solo se il colpo precedente ha davvero stordito. È ciò
		## che rende la combo del Fante una punizione e non un tiro di dado — se
		## la botta di scudo l'hai schivata o parata, il seguito non parte.
		##
		## Si chiede al bersaglio con duck-typing, come tutto il resto della
		## pipeline di hit: un nemico non deve conoscere il tipo del giocatore.
		if when == "stun":
			if not is_instance_valid(target) or not target.has_method("is_stunned") \
					or not target.is_stunned():
				continue
		if dist > nxt.move_range + CHAIN_RANGE_BUFFER:
			continue
		var chance : float = float(rule.get("chance", 0.5)) * chain_mult
		if randf() <= chance:
			return nxt
	return null


## ─── Esecuzione di UNA mossa ────────────────────────────────────────────────
## Modello a ISTANTI DI CONTATTO: la mossa dichiara nei dati QUANDO colpisce
## (`EnemyMove.contact_times`, secondi sulla clip a velocità 1.0, uno per ogni
## impatto). Il controller aspetta quegli istanti, aggancia il bersaglio poco
## prima di ciascuno e consegna il danno. Niente da indovinare: il numero si
## legge dalla stessa timeline che l'animatore ha authorato in Blender.
##
## L'attesa totale è DETERMINISTICA (durata della clip), NON il segnale
## `animation_finished`: quel segnale è globale sull'AnimationPlayer e se per
## qualunque motivo non scatta, la coroutine resta appesa per sempre con
## `_busy = true` — è la causa storica dell'A-pose persistente.
func _execute_move(move : EnemyMove) -> void:
	var clip_len := _begin_move(move)

	# Le mosse con una coreografia propria (l'ululato) se la gestiscono da sole:
	# se una la prende in carico, qui abbiamo finito. Il controllo viene PRIMA
	# di armare i contatti, altrimenti una mossa che non colpisce ne consegnerebbe
	# comunque uno: l'ululato faceva partire un colpo da 0 danni che comunque
	# metteva il player in reazione di dolore e gli bruciava la parata.
	if await _execute_special(move, clip_len):
		_finish_move(move)
		return

	# Arma i contatti: da qui in poi li consegna il playhead. `duplicate()` è
	# obbligatorio — la coda viene CONSUMATA colpo dopo colpo, e senza copia si
	# svuoterebbe l'array della tabella condivisa (vedi AttackTiming.contacts_for)
	# o quello della risorsa EnemyMove, che è condivisa tra tutte le istanze.
	_pending_contacts = _contact_times(move).duplicate()
	_released_this_move = false

	await _run_move_timeline(move, clip_len)
	_finish_move(move)


## Avvio comune a ogni mossa: contabilità, clip, innesto d'inizio. Ritorna la
## durata REALE della clip (già scalata da `anim_speed_scale`).
func _begin_move(move : EnemyMove) -> float:
	_move_since = _now()
	_attack_released = false
	_snap_turn = false

	var vel : float = _move_speed(move)
	var clip_len : float = _anim_len(move.anim) / vel
	_play(move.anim, false, vel)
	if move.cooldown > 0.0:
		_cooldown_until[move.id] = _now() + move.cooldown
	_second_last = _last_move
	_last_move = move.id

	# La mossa corrente serve subito (il playhead la confronta con la clip in
	# riproduzione); i CONTATTI invece si armano in `_execute_move`, dopo aver
	# verificato che la mossa non abbia una coreografia propria.
	_active_move = move
	_pending_contacts = PackedFloat32Array()
	_released_this_move = false

	_on_move_started(move, clip_len)
	return clip_len


## Timeline della mossa. I contatti NON si aspettano con dei timer: si armano
## qui e li consegna `_advance_attack_timeline()` quando il playhead
## dell'animazione li attraversa (vedi lì il perché). Qui resta una sola attesa,
## quella della durata totale, che è deliberatamente DETERMINISTICA e non legata
## a `animation_finished`: quel segnale è globale sull'AnimationPlayer e se non
## scatta la coroutine resta appesa per sempre con `_busy = true`.
func _run_move_timeline(move : EnemyMove, _clip_len : float) -> void:
	await get_tree().create_timer(_move_real_duration(move)).timeout


## Durata REALE della mossa a schermo. Qui sì che serve dividere per la velocità:
## è un'attesa in secondi di gioco, non un confronto col playhead.
func _move_real_duration(move : EnemyMove) -> float:
	return maxf(_anim_len(move.anim) / _move_speed(move), 0.1)


## Velocità con cui gira QUESTA mossa. Un solo posto da cui leggerla: le durate
## reali si dividono per questa, e se una delle due la calcolasse da sola i
## tempi di gioco si scollerebbero dalla clip che si vede.
func _move_speed(move : EnemyMove) -> float:
	if move != null and "anim_speed" in move and move.anim_speed > 0.0:
		return move.anim_speed
	return anim_speed_scale


## ─── Consegna dei contatti, guidata dal PLAYHEAD ────────────────────────────
## Chiamata ogni frame di fisica mentre il nemico è vivo.
##
## Perché non dei timer. Un timer corre PARALLELO all'animazione, non insieme:
## basta che la clip venga riprodotta più lenta, interrotta, ri-sincronizzata o
## sostituita e il colpo arriva quando a schermo non sta succedendo niente. È
## esattamente ciò che rendeva imprevedibili parata e schivata all'ultimo
## istante, che sono le due abilità su cui si regge il combattimento: il
## giocatore temporizza su quello che VEDE.
##
## `AnimationPlayer.current_animation_position` è già espresso in tempo-clip: a
## velocità 0.7 dopo un secondo reale vale 0.7. Quindi si confronta DIRETTAMENTE
## con gli istanti misurati, senza dividere per `anim_speed_scale` da nessuna
## parte — e un nemico che gioca la stessa clip più lenta colpisce da solo nel
## punto giusto.
func _advance_attack_timeline() -> void:
	if _active_move == null or anim_player == null:
		return
	# Se sta suonando un'altra clip, la mossa è stata scavalcata: niente colpi.
	if _clip_corrente() != _active_move.anim:
		return
	var pos : float = _clip_pos()

	# Snap-turn nella finestra che PRECEDE il prossimo contatto: per il resto
	# della carica il nemico ruota lento, lasciando spazio a girargli attorno.
	if not _pending_contacts.is_empty():
		var next : float = _pending_contacts[0]
		_snap_turn = pos >= next - SNAP_WINDOW_MAX and pos < next

	while not _pending_contacts.is_empty() and pos >= _pending_contacts[0]:
		_pending_contacts.remove_at(0)
		if _move_aborted():
			return
		if not _released_this_move:
			# Dal primo impatto il facing si blocca: il colpo vale dove il
			# nemico guardava, e la schivata a tempo paga sempre.
			_released_this_move = true
			_attack_released = true
			_snap_turn = false
			_on_move_released(_active_move)
		_deliver_hit(_active_move)


## Innesto sul RILASCIO (primo contatto): proiettili, scariche, scivolate.
func _on_move_released(_move : EnemyMove) -> void:
	_suona(_voce_attacco(_move))


## ─── VOCE DELLA CREATURA ────────────────────────────────────────────────────
##
## Quattro innesti, uno per momento. La classe base non ha voce: ogni specie
## dichiara la sua sovrascrivendo quello che le serve, e chi non dice niente
## resta muto invece di prendere il verso di qualcun altro.
##
## ⚠️ Sta QUI e non nelle singole scene perche' i momenti (ingaggio, colpo,
## morte, attacco) sono gia' gli stessi per tutti: duplicare l'aggancio in ogni
## nemico vorrebbe dire ricordarsene per sempre, a ogni nemico nuovo.
func _voce_ingaggio() -> String: return ""
func _voce_colpito() -> String: return ""
func _voce_morte() -> String: return ""
func _voce_attacco(_move : EnemyMove) -> String: return ""

## Suona un verso, se c'e'. ⚠️ Posizionato nel mondo: un nemico che ringhia
## dall'altra parte dell'arena deve sentirsi da li', non addosso.
func _suona(percorso : String) -> void:
	if percorso != "":
		Suoni.nel_mondo(self, percorso)


func _finish_move(move : EnemyMove) -> void:
	_attack_released = false
	_snap_turn = false
	_active_move = null
	_pending_contacts = PackedFloat32Array()
	_on_move_finished(move)


## Istanti di contatto della mossa, in TEMPO-CLIP a velocità 1.0. In ordine:
##  1. `EnemyMove.contact_times` — override esplicito della singola mossa;
##  2. la tabella misurata dalle clip (`AttackTiming`) — il caso normale, ed è
##     l'unica verità condivisa da tutti i nemici che usano la stessa clip;
##  3. `telegraph` — ultima spiaggia. È un fossile dell'era Meshy (clip senza
##     wind-up authorato: il codice DOVEVA inventarsi l'istante) e come istante
##     d'impatto è tipicamente SBAGLIATO: era tarato come tempo di carica.
func _contact_times(move : EnemyMove) -> PackedFloat32Array:
	var over := move.contact_times
	if over != null and not over.is_empty():
		return over
	var lib := _timing()
	if lib and lib.has_clip(move.anim):
		var c := lib.contacts_for(move.anim)
		if not c.is_empty():
			return c
	return PackedFloat32Array([move.telegraph])


## Tabella dei tempi: quella assegnata sull'istanza, o quella di progetto
## (caricata una volta sola e condivisa da tutti i nemici).
func _timing() -> AttackTiming:
	if timing != null:
		return timing
	if _shared_timing == null and ResourceLoader.exists(TIMING_PATH):
		_shared_timing = load(TIMING_PATH)
	return _shared_timing


## Coreografie particolari. Ritorna true se ha gestito la mossa per intero.
func _execute_special(_move : EnemyMove, _clip_len : float) -> bool:
	return false

## Innesti d'inizio/fine mossa (VFX di carica, finestre d'arma, scivolate).
func _on_move_started(_move : EnemyMove, _clip_len : float) -> void:
	pass

func _on_move_finished(_move : EnemyMove) -> void:
	pass


## Consegna del danno di un contatto. Default: cono frontale matematico — che è
## la scelta CORRETTA per chi morde o artiglia senza arma. Le sottoclassi con
## una hitbox fisica lo sostituiscono (vedi ArcaniumHumanoidEnemy).
func _deliver_hit(move : EnemyMove) -> void:
	_apply_hit(move)


func _apply_hit(move : EnemyMove) -> void:
	if not is_instance_valid(target) or not target.has_method("hit"):
		return
	var dist := _flat_distance(target)
	## ⚠️ Un BALZO ha come `move_range` la distanza da cui PARTE (12,6 m per
	## l'Alpha), non quella da cui morde. Usata anche qui, il colpo entrava
	## ovunque il bersaglio fosse entro 13 m all'istante del contatto: trovato
	## dal playtest automatico il 2026-10-07, 28 HP tolti col lupo atterrato a
	## 6,8 m dal player che rotolava via. Il morso di un balzo si misura da DOVE
	## il lupo e' adesso, con la portata della mischia.
	var portata : float = _combat_range() if move.leap_to_target else move.move_range
	if not move.leap_to_target and move.portata_colpo > 0.0:
		portata = move.portata_colpo
	if dist > portata + 0.5:
		return
	if dist > CLOSE_ARC_FREE_DIST:
		# La mesh guarda +Z.
		var fwd := global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		if fwd.dot(_flat_dir_to(target)) < cos(move.arc):
			return
	target.hit(self, move)


# ═══════════════════════════════════════════════════════════════════════════
# Danno subito / morte
# ═══════════════════════════════════════════════════════════════════════════

func hit(_who, _by_what) -> void:
	if _state == State.DEAD:
		return
	if is_instance_valid(_who):
		target = _who
		## Da adesso ti insegue anche da fuori raggio, e il conto riparte a ogni
		## colpo: finche' continui a bersagliarlo non si calma.
		_provocato_fino = _now() + provocazione_durata
	damage_taken.emit(_by_what)   # → HealthSystem applica il danno
	_suona(_voce_colpito())

	# ⚠️ RIENTRO SINCRONO — non togliere il controllo qui sotto.
	# `damage_taken` arriva all'HealthSystem che, se il colpo è letale, emette
	# `died` SUBITO, dentro questa stessa chiamata (vedi
	# arcanium_health_system._on_damage_signal). Quindi a questo punto lo stato
	# può essere GIÀ DEAD e `_on_died()` può aver GIÀ avviato la clip di morte.
	#
	# Era esattamente il bug per cui i Consumati non mostravano praticamente MAI
	# la loro morte: 25 HP, uccisi quasi sempre da fermi (`_busy` falso), quindi
	# si entrava nel ramo qui sotto e la clip di dolore ripartiva SOPRA quella di
	# morte. I boss invece muoiono di solito a metà attacco (`_busy` vero), il
	# ramo veniva saltato e la morte si vedeva: da qui l'asimmetria "al boss a
	# volte sì, al Consumato mai".
	if _state == State.DEAD:
		return

	if _can_react_to_hit():
		_hurt_lock = hurt_lock_time
		_play(hurt_anim, false)


## ─── Barretta di vita flottante ─────────────────────────────────────────────
## Creata PIGRAMENTE al primo colpo incassato: un nemico che il player non ha
## mai toccato non paga nulla, e in un livello con una dozzina di nemici la
## maggior parte non viene ingaggiata affatto.

const FloatingHealthBar := preload("res://arcanium/ui/hud/enemy_health_bar.gd")
var _health_bar : Node3D = null

## Ogni variazione di vita, da qualunque parte arrivi.
func _on_health_updated(_hp : int) -> void:
	_update_floating_health()


func _update_floating_health() -> void:
	if not show_floating_health or health_system == null:
		return
	var total := float(health_system.total_health)
	if total <= 0.0:
		return
	if _health_bar == null:
		_health_bar = FloatingHealthBar.new()
		add_child(_health_bar)
		# ⚠️ Qui c'era una compensazione della scala del nemico
		# (`scale = ONE / scale.x`) «perche' l'Alpha e' 4.0 e si porterebbe
		# dietro una barra spropositata». Non serviva e non poteva servire: il
		# billboard butta via la scala, quindi la barretta e' gia' larga 0,62 m
		# per chiunque. L'ALTEZZA invece la scala sta in coordinate locali del
		# nemico, quindi si scala con lui — ed e' giusto cosi', su un Alpha alto
		# il doppio la barretta deve stare il doppio piu' su.
		_health_bar.position.y = _floating_health_offset()
	_health_bar.set_ratio(float(health_system.current_health) / total)


## Altezza a cui appendere la barretta: appena sopra la testa.
##
## ⚠️ Si legge dal CORPO, non dalla capsula di collisione. La capsula e' un
## approssimazione generosa — quella del Fante e' alta 2,60 m per un corpo di
## 1,78 — e la formula di prima la sommava anche alla propria posizione
## (`height + position.y`, cioe' l'altezza contata una volta e mezza), poi
## correggeva con un `* 0.75` messo a occhio. Risultato misurato: barretta a
## 2,92 m su una testa che sta a 1,55. Fluttuava un metro e mezzo sopra il
## nemico, staccata da lui.
##
## Il corpo si misura dall'AABB delle mesh IMPELLICCIATE, cioe' quelle legate a
## uno scheletro. Le altre no, di proposito: spada e scudo stanno su
## `BoneAttachment3D` e un'asta alzata porterebbe la barretta al cielo.
const FLOATING_MARGINE := 0.30

func _floating_health_offset() -> float:
	if floating_health_height > 0.0:
		return floating_health_height
	var cima := -INF
	var inv := global_transform.affine_inverse()
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		if mi.get_node_or_null(mi.skeleton) as Skeleton3D == null:
			continue
		var ab : AABB = (inv * mi.global_transform) * mi.get_aabb()
		cima = maxf(cima, ab.position.y + ab.size.y)
	if cima > -INF:
		return cima + FLOATING_MARGINE

	# Ripiego per chi non ha mesh impellicciate: la collisione, stavolta letta
	# come si deve (la CIMA della forma, non la sua altezza sommata al centro).
	var h := 2.0
	for c in find_children("*", "CollisionShape3D", true, false):
		var sh := (c as CollisionShape3D).shape
		if sh is CapsuleShape3D:
			h = maxf(h, c.position.y + (sh as CapsuleShape3D).height * 0.5)
		elif sh is BoxShape3D:
			h = maxf(h, c.position.y + (sh as BoxShape3D).size.y * 0.5)
		elif sh is CylinderShape3D:
			h = maxf(h, c.position.y + (sh as CylinderShape3D).height * 0.5)
	return h + FLOATING_MARGINE


## Un colpo in arrivo NON interrompe una mossa già in volo. Le sottoclassi
## aggiungono i propri stati intoccabili (finisher subito, fuga).
func _can_react_to_hit() -> bool:
	return not _busy


## Una clip "scriptata" possiede il corpo e la morte deve aspettare che finisca.
## Le sottoclassi dicono quando (il finisher subito, in ArcaniumHumanoidEnemy).
func _death_must_wait() -> bool:
	return false

var _death_pending := false

## La morte arriva dall'HealthSystem, che emette `died` SINCRONO dentro
## `damage_taken` — quindi anche a metà di un finisher. Se il corpo è impegnato
## in una clip di cui il player sta vedendo la controparte, morire subito taglia
## la scena: il nemico spariva mentre il protagonista era ancora a mezzo gesto,
## e il colpo finale finiva nel vuoto. Qui si prende nota e si muore dopo.
func _on_died() -> void:
	if _state == State.DEAD or _death_pending:
		return
	if _death_must_wait():
		_death_pending = true
		_pending_death_safety()
		return
	_do_die()

## Le clip vittima del pack stanno sotto i 4s. Se dopo questo tempo la morte è
## ancora in attesa vuol dire che la clip non è mai arrivata in fondo (finisher
## interrotto, transizione mancata): meglio un cadavere che un nemico immortale
## fermo a 0 HP.
const PENDING_DEATH_MAX := 6.0

func _pending_death_safety() -> void:
	await get_tree().create_timer(PENDING_DEATH_MAX).timeout
	if is_instance_valid(self) and _death_pending:
		_finish_pending_death()

## Chiamata dalla sottoclasse quando la clip che teneva il corpo è finita.
func _finish_pending_death() -> void:
	if not _death_pending:
		return
	_death_pending = false
	_do_die()

func _do_die() -> void:
	if _state == State.DEAD:
		return
	_state = State.DEAD
	_busy = false
	velocity = Vector3.ZERO
	_clear_move_state()
	death_started.emit()
	_suona(_voce_morte())

	# Non più bersagliabile né agganciabile col lock-on: senza, il cadavere
	# resta selezionabile e il player continua a menare un corpo a terra.
	remove_from_group("targets")
	set_collision_layer_value(1, false)
	set_collision_layer_value(3, false)
	set_collision_layer_value(5, false)

	if _health_bar and is_instance_valid(_health_bar):
		_health_bar.queue_free()   # una barra di vita su un cadavere non serve
		_health_bar = null

	# Velocità ASSOLUTA 1.0: la morte non va rallentata dal tuning di difficoltà
	# (`anim_speed_scale` serve a rendere leggibili gli ATTACCHI).
	# Morte e coppie victim/getup: sincronizzate al frame con altro, xfade 0.
	_play(death_anim, false, 1.0, 0.0)
	if despawn_after_death:
		_despawn_after_death()


func _despawn_after_death() -> void:
	await get_tree().create_timer(_anim_len(death_anim) + despawn_extra_delay).timeout
	if not is_instance_valid(self):
		return
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.45)
	tw.tween_callback(queue_free)


## Chiamato via `call_group` quando cade un alleato significativo (l'Alpha del
## branco, il gemello di un doppio boss). Default: nessuna reazione.
func on_ally_died() -> void:
	pass


func is_dead() -> bool:
	return _state == State.DEAD


## Riporta il nemico alle condizioni di partenza senza ricrearlo: usato dal
## respawn del player sui nemici che NON vengono re-istanziati (i mini-boss).
## Azzera anche l'aggro, così alla prossima vista riparte il suo `engaged` e con
## esso la boss bar.
func reset_to_idle() -> void:
	if _state == State.DEAD:
		return
	_busy = false
	_hurt_lock = 0.0
	_next_attack = 0.0
	_has_engaged = false
	_cooldown_until.clear()
	_last_move = ""
	_second_last = ""
	velocity = Vector3.ZERO
	_clear_move_state()
	_go_idle()


## Rete anti T-pose: se un one-shot finisce e non stiamo attaccando, si torna
## sempre a una clip in loop.
func _on_anim_finished(anim_name : StringName) -> void:
	if _state == State.DEAD or _busy:
		return
	if _on_special_anim_finished(anim_name):
		return
	if anim_name != idle_anim and anim_name != walk_anim and anim_name != run_anim:
		_play(idle_anim, true)


## Ritorna true se la sottoclasse ha gestito la fine di questa clip (catena
## victim → getup, stagger che si ricicla, ...).
func _on_special_anim_finished(_anim_name : StringName) -> bool:
	return false


# ═══════════════════════════════════════════════════════════════════════════
# Helper
# ═══════════════════════════════════════════════════════════════════════════

## Portata a cui fermarsi per attaccare.
func _combat_range() -> float:
	return move_set.melee_threshold if move_set else 2.0

## Le fasi multiple sono un tratto da boss: per un comune la risposta è sempre no.
func _in_phase2() -> bool:
	return false

func _flat_distance(n : Node3D) -> float:
	var d := n.global_position - global_position
	d.y = 0.0
	return d.length()

func _flat_dir_to(n : Node3D) -> Vector3:
	var d := n.global_position - global_position
	d.y = 0.0
	return d.normalized()

func _now() -> float:
	return OrologioGioco.adesso()


## ═══════════════════════════════════════════════════════════════════════════
## DOVE SI LEGGE IL PLAYHEAD — un solo posto, perché non è più uno solo
## ═══════════════════════════════════════════════════════════════════════════
## Fino a ieri la risposta a «che clip sta suonando, e a che punto è» era una
## sola: `anim_player`. Con l'AnimationTree non lo è più — l'AnimationPlayer
## resta la LIBRERIA delle clip, ma chi le suona è l'albero, e
## `current_animation` sull'AnimationPlayer torna stringa vuota.
##
## ⚠️ Queste tre funzioni non aggiungono comportamento: spostano una lettura
## che era sparsa in cinque punti dietro un nome unico, così che una sottoclasse
## possa rispondere diversamente senza che il ciclo se ne accorga. Chi le tocca
## deve sapere che sopra ci sta appesa la FINESTRA DELL'ARMA: se `_clip_pos()`
## mente, il nemico colpisce quando a schermo non succede niente.
func _clip_corrente() -> String:
	return anim_player.current_animation if anim_player else ""

func _clip_pos() -> float:
	return anim_player.current_animation_position if anim_player else 0.0

func _root_motion() -> Vector3:
	return anim_player.get_root_motion_position() if anim_player else Vector3.ZERO


## `speed_override > 0` forza una velocità ASSOLUTA (ignora `anim_speed_scale`):
## serve alle clip che devono restare sincronizzate con qualcosa di esterno —
## la morte, e le coppie victim/getup sincronizzate con le clip del player.
func _play(name : String, loop : bool, speed_override : float = -1.0,
		xfade_override : float = -1.0) -> void:
	if anim_player == null or name == "" or not anim_player.has_animation(name):
		return
	if _current_anim == name and anim_player.is_playing():
		return
	_current_anim = name
	var a := anim_player.get_animation(name)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var xf : float = xfade_override if xfade_override >= 0.0 else anim_xfade
	anim_player.play(name, xf, speed_override if speed_override > 0.0 else anim_speed_scale)


## Durata NATIVA della clip (a velocità 1.0). Chi chiama divide per
## `anim_speed_scale` quando gli serve la durata reale a schermo.
func _anim_len(name : String) -> float:
	if anim_player and anim_player.has_animation(name):
		return anim_player.get_animation(name).length
	return 1.0


func _weighted_pick(pool : Array[EnemyMove], weights : Array[float]) -> EnemyMove:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return pool[randi() % pool.size()]
	var r := randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]
