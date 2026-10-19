extends "res://arcanium/systems/enemies/arcanium_enemy.gd"
class_name ArcaniumHumanoidEnemy

## ═══════════════════════════════════════════════════════════════════════════
## NEMICO UMANOIDE — bipede armato sul rig Nephilite
## ═══════════════════════════════════════════════════════════════════════════
##
## Tutto ciò che ha un corpo umano e un'arma in mano, dal Consumato in su:
##
##   • libreria di animazioni straight-sword caricata dal pack Nephilite
##   • ROOT MOTION authorata (i piedi guidano lo spostamento, niente foot-sliding)
##   • POISE-BREAK: lo status rompe la guardia e apre la finestra di punizione
##   • FINISHER SUBITI: backstab e riposte del player, con coppia victim/getup
##   • HITBOX D'ARMA FISICHE: il colpo arriva quando l'arma TOCCA, non quando
##     un timer dice che dovrebbe
##
## `extends` per PATH e non per class_name: la registrazione dei class_name
## dipende dallo scan dell'editor, che su questo progetto non attecchisce sempre
## (import headless) e lascia "Identifier not declared" su script validi.
##
## ─── Perché le hitbox sono un ARRAY e non una sola "lama" ───────────────────
## Il controller precedente aveva un unico export `blade`, cioè l'assunto
## implicito "un nemico = un'arma = un punto che ferisce". Qui invece ogni mossa
## può NOMINARE la propria hitbox (`EnemyMove.hitbox`): una creatura con due
## spade, o con coda e artigli, si costruisce aggiungendo Area3D alla scena e
## scrivendo il nome nel move set — senza toccare una riga di codice. Se la
## mossa non nomina nulla si usa l'arma principale; se non c'è nemmeno quella,
## si ricade sul modello a istanti di contatto della superclasse, che è la cosa
## giusta per chi colpisce a mani nude.

@export_group("Rig")
@export var skeleton_path : NodePath = NodePath("Model/NephiliteRig/Skeleton3D")

@export_group("Arma")
## Area3D sulla LAMA (non su tutta l'arma: impugnatura e guardia non
## colpiscono). Quando c'è, il danno passa dal contatto FISICO invece che da un
## cono matematico — è la differenza di "feel" principale rispetto ai manichini
## del template: un'arma che passa sopra la testa del player non deve ferirlo.
@export var blade : Area3D
## Hitbox aggiuntive, indirizzabili per NOME dalle mosse (`EnemyMove.hitbox`).
## Il gancio per le creature con più punti offensivi.
@export var extra_hitboxes : Array[NodePath] = []
## Se false si torna al cono matematico (utile per confronti a vista).
@export var use_weapon_hitbox : bool = true
## Finestra dell'arma come FRAZIONE della clip. È solo il RIPIEGO per le clip
## non ancora misurate: normalmente la finestra la dice `AttackTiming`, che sa
## in quale tratto della clip l'arma sta davvero spazzando.
##
## Perché delle frazioni fisse non vanno bene: 0.15-0.90 significa tenere la
## lama accesa per tre quarti dell'animazione, cioè anche durante il WIND-UP e
## il RECOVERY. Su `sword_charged_attack_01` (3.7 s) faceva 2.78 secondi di lama
## viva: il nemico ti feriva mentre ALZAVA la spada, e non esisteva istante in
## cui schivare fosse la risposta giusta.
@export_range(0.0, 1.0) var blade_open_frac : float = 0.15
@export_range(0.0, 1.0) var blade_close_frac : float = 0.90
## Margine aggiunto alla finestra misurata, in tempo-clip. Alzarli rende i colpi
## più "generosi" (più facili da incassare, più difficili da schivare di un pelo):
## è la manopola del feeling, e va tarata a mano sul playtest.
@export var weapon_window_lead : float = 0.04
@export var weapon_window_trail : float = 0.04
## Sotto-passi della sonda continua: la punta dell'arma percorre più di un metro
## per tick di fisica, e un Area3D campionato a passi discreti salta il player.
@export var blade_sweep_substeps : int = 6
## Frazione finale del telegraph in cui scatta lo snap-turn.
@export_range(0.05, 0.6) var snap_turn_fraction : float = 0.35

## ═══════════════════════════════════════════════════════════════════════════
## LA GUARDIA — il nemico che si ripara dietro lo scudo
## ═══════════════════════════════════════════════════════════════════════════
## Modellata sulla guardia del PROTAGONISTA (`player_charbody3D.gd::block()`),
## e volutamente **monca della metà migliore**.
##
## ⚠️ **UN CONSUMATO NON PARA MAI.** Il player ha `parry_active`, una finestra di
## 0,3 s in apertura di guardia in cui il blocco diventa parata e ribalta lo
## scontro. Qui quella finestra non esiste, e non è una semplificazione: è la
## differenza fra un soldato e ciò che ne resta. Un Consumato sa ancora **tenere**
## lo scudo — è memoria muscolare di guarnigione — ma non sa più leggere il tempo
## dell'avversario. Concretamente: qui non si chiama mai `_who.parried()`, quindi
## il giocatore non viene mai messo in stagger da un Fante.
##
## Il resto è simmetrico al player, e apposta: **lo scudo è la STESSA risorsa**
## (`ArcaniumShieldResource`) che il giocatore può equipaggiare. Quello che
## protegge il Fante è esattamente quello che droppa dal Fante, con gli stessi
## numeri — una sola verità invece di due tabelle che divergono al primo ritocco.
@export_group("Guardia")
## Lo scudo. Se è `null` la guardia non si alza mai: non esiste un blocco
## "generico" senza scudo, per la stessa ragione per cui non esiste sul player.
@export var scudo : ArcaniumShieldResource
## Semi-apertura del cono frontale protetto, in radianti. Fuori di qui il colpo
## entra pieno: è ciò che rende il posizionamento la risposta giusta al grado ①.
@export_range(0.0, PI) var guardia_arco : float = 1.15
## Danno ASSORBITO dallo scudo che serve a rompere la guardia. Si accumula ciò
## che lo scudo ha mangiato, non ciò che è passato: uno scudo che para bene si
## rompe prima, ed è giusto — è lui a incassare.
@export var guardia_tenuta : float = 46.0
## Quanto resta abbassata dopo una rottura.
@export var guardia_riposo : float = 4.0
## Entro quale distanza dal bersaglio la alza. Più lontano cammina scoperto.
@export var guardia_distanza : float = 7.0
@export var guardia_block_anim : String = "sword/sword_guard_block_medium_01"

## ─── LA POSA DELLA GUARDIA E' UNA SOLA, E NON E' UNA CLIP A SE' ─────────────
## Qui c'erano `guardia_up_anim` e `guardia_idle_anim`: due clip, "alzo lo
## scudo" e "resto in guardia". Nessuna delle due e' mai stata autorata, e
## `guardia_idle_anim` non veniva nemmeno suonata da nessuna riga di codice.
## Non era una svista: con UNA CLIP PER VOLTA quella capacita' non esiste. Il
## Fante alzava lo scudo per mezzo secondo e la locomozione ci scriveva sopra.
##
## Con l'AnimationTree la guardia e' uno STRATO MESCOLATO sopra la locomozione,
## filtrato dalla spina in su (vedi `_ossa_alte`), sfumato da un lerp. Non
## servono ne' la clip di salita ne' quella di tenuta: la sfumatura E' la
## salita. Resta da autorare **una** posa, non tre.
##
## ⚠️ FINCHE' LA POSA DEDICATA NON ESISTE si congela un FOTOGRAMMA di una clip
## che c'e' gia'. `AnimationNodeAnimation` sa farlo da solo (`use_custom_timeline`
## + `start_offset`): non serve un GLB nuovo, quindi non serve nemmeno una
## `retarget/bone_map` nuova da sbagliare. Il giorno in cui la posa vera arriva,
## si cambiano queste due righe e basta.
## ⚠️ Il nome finisce in `_anim` apposta: `verifica_famiglie_anim` controlla
## SOLO le proprieta' che finiscono cosi'. Chiamarla `guardia_posa_clip` la
## rendeva invisibile al cancello — cioe' una clip che puo' sparire senza che
## nessuno lo dica, che e' esattamente il guasto che quel cancello esiste per
## intercettare.
@export var guardia_posa_anim : String = "sword/sword_shield_bash_01"
## Istante della clip da congelare, in tempo-clip (secondi a velocita' 1.0).
@export var guardia_posa_tempo : float = 0.55
## Quanto e' rapida la salita/discesa dello scudo, in "quanto ne recupera al
## secondo".
##
## ⚠️ NON e' piu' un `lerp(a, b, 0.2)` per fotogramma come nel protagonista.
## Quel numero e' legato al FRAME RATE: a 30 fps lo scudo sale la meta' di
## quanto sale a 60, e a 144 vola su. Qui la stessa sfumatura si scrive
## `1 - exp(-k * delta)`, che da' la stessa curva a qualunque frame rate.
## 13.0 riproduce a 60 fps il vecchio 0.2.
@export_range(1.0, 40.0) var guardia_velocita_blend : float = 13.0

## ═══════════════════════════════════════════════════════════════════════════
## L'ANIMATION TREE — perche' esiste, e perche' e' spento di default
## ═══════════════════════════════════════════════════════════════════════════
## `_play()` vive nella superclasse ed e' condiviso da DICIOTTO nemici: lupi,
## Consumati, boss. Riscriverlo per tutti in un colpo significherebbe mettere in
## gioco tutta la fauna per far alzare uno scudo a un Fante.
##
## Quindi la strada e' questa: l'albero si costruisce QUI, nella sottoclasse
## umanoide, si accende per SCENA, e chi non lo accende continua a passare per
## l'AnimationPlayer esattamente come ieri. L'export e' il cancello: si allarga
## un nemico per volta, guardando il render.
##
## Cosa da' l'albero che l'AnimationPlayer non puo' dare:
##   • una PARTE ALTA che fa una cosa mentre la parte bassa ne fa un'altra —
##     la guardia oggi, gli arcieri che tirano indietreggiando domani;
##   • una posa TENUTA sopra la locomozione invece che al posto suo.
##
## ⚠️ L'albero si costruisce in CODICE e non nel `.tscn`, per due motivi che non
## sono pigrizia: i nomi delle clip nascono a runtime (`_carica_famiglia`
## costruisce le librerie per famiglia d'arma), e i filtri d'osso hanno bisogno
## del path dello scheletro, che e' un export della scena. Un albero authorato a
## mano andrebbe ricopiato — e ritoccato — in ogni scena di umanoide.
@export var usa_anim_tree : bool = false

## ═══════════════════════════════════════════════════════════════════════════
## PROVATO E SCARTATO: la locomozione in un AnimationNodeBlendSpace1D
## ═══════════════════════════════════════════════════════════════════════════
## Fermo, cammina e corre in un solo spazio di fusione, con `sync_mode` a
## tenere in fase i cicli: e' la ricetta che danno tutti, ed e' stata scritta,
## misurata e TOLTA. Sta qui perche' non venga rifatta al buio.
##
## Misura (`arcanium/tools/misura_slittamento.gd`, 8 partenze sfalsate, quanto
## slitta un piede mentre e' appoggiato — l'unica cosa che l'occhio legge come
## "pattina"):
##
##                        slittamento     peggior fotogramma
##   dissolvenza (oggi)     7,51 cm/m          2,98 cm
##   spazio di fusione      6,12 cm/m          6,35 cm   <- sync NESSUNO
##   spazio di fusione      6,46 cm/m          6,84 cm   <- sync indipendente
##   spazio di fusione      6,83 cm/m          5,83 cm   <- sync ciclico mutevole
##
## Meno slittamento in totale, ma il PICCO PIU' CHE RADDOPPIA — e un piede che
## salta di sei centimetri in un fotogramma e' visibile, mentre un quinto di
## slittamento in meno spalmato su dieci secondi non lo e'.
##
## ⚠️ Il perche' conta piu' dei numeri: `sync_mode` **riscala il tempo, non
## allinea la fase**. Camminata (1,167 s) e corsa (0,833 s) partono a 24 gradi
## di scarto e da li' si allontanano; mescolarle a meta' ciclo trascina il piede
## appoggiato. La sincronia ciclica pareggia il PERIODO, non il punto del ciclo,
## e infatti e' risultata la PEGGIORE delle tre.
##
## Cosa la farebbe funzionare: cicli agganciati alla stessa fase, che non e'
## codice — e' come sono autorate le clip. Se un giorno camminata e corsa
## verranno riesportate in fase, questa strada si riapre e la misura lo dira'.
## ═══════════════════════════════════════════════════════════════════════════
## L'INERZIA AL POSTO DELLA DISSOLVENZA
## ═══════════════════════════════════════════════════════════════════════════
## Con questo acceso la clip nuova parte SUBITO a peso pieno, e il passaggio lo
## fa `inerzia_anim.gd` smorzando lo SCARTO fra la posa vecchia e la nuova.
##
## Misurato con `arcanium/tools/misura_slittamento.gd` (8 partenze sfalsate,
## fermo -> cammina -> corre -> cammina -> fermo):
##
##                                  slittamento   scatto della posa (picco)
##   dissolvenza lineare 0,12 s       7,51 cm/m        5,73 gradi/fot.
##   inerzia 0,25 s, dissolvenza 0    4,10 cm/m        3,29 gradi/fot.
##                                       -45%             -43%
##
## Le due cose migliorano INSIEME, ed e' il punto: con la dissolvenza non si
## poteva. Allungarla o addolcirla abbassava lo scatto e alzava lo slittamento
## (curva a S: scatto 2,97 ma slittamento 7,81; con anche una dissolvenza lunga
## in rientro: scatto 2,97 e slittamento 8,75). Il difetto E' la media fra due
## pose, e l'inerzia quella media non la fa mai: il piede resta dove
## l'animatore l'ha messo.
##
## ⚠️⚠️ LA DISSOLVENZA DEVE ANDARE A ZERO, o l'inerzia non serve a niente.
## Il primo giro la teneva a 0,05 s "per la root motion", e con quei cinque
## centesimi i due meccanismi si pestavano i piedi: lo scarto veniva fotografato
## mentre la dissolvenza era ancora in corso, quindi non era lo scarto vero, e i
## numeri tornavano PEGGIORI del punto di partenza (7,58 cm/m e 9,03 di scatto).
## A zero: 4,10 e 3,29.
##
## ⚠️ IL PREZZO, dichiarato: la root motion cambia di scatto insieme alla clip.
## Lo strappo massimo di velocita' passa da 3,33 a 3,89 m/s (+17%). Un salto di
## velocita' c'era gia' prima — fermo e cammina hanno velocita' diverse e basta
## — qui e' un po' piu' netto. Si e' preferito quello a un piede che pattina il
## doppio.
@export var usa_inerzia : bool = false
## Quanto dura lo smorzamento. Misurate 0,15 / 0,25 / 0,35: slittamento
## 3,91 / 4,10 / 4,42 cm/m ma peggior fotogramma 7,20 / 5,66 / 6,00 cm.
## 0,25 e' il compromesso.
@export_range(0.05, 0.8, 0.01) var inerzia_durata : float = 0.25
## Dissolvenza in entrata e in uscita dello strato. Corta: il gesto deve
## staccarsi dalla guardia in fretta, o l'affondo sembra nascere da lontano.
@export_range(0.0, 0.4, 0.01) var strato_dissolvenza : float = 0.08

## Se falso, questo nemico si avvicina SEMPRE camminando, anche da lontano.
## Vedi `_chase`: e' il passo della fanteria pesante, non una manopola di
## velocita'.
@export var insegue_di_corsa : bool = true

## ═══════════════════════════════════════════════════════════════════════════
## LEGGERE L'AVVERSARIO — si trincera sotto pressione, punisce la pausa
## ═══════════════════════════════════════════════════════════════════════════
##
## Un Fante che alza lo scudo e attacca quando gli pare e' un manichino con una
## guardia. Questo invece **ti guarda giocare**: ogni colpo che gli arriva
## addosso — parato o passato — alza una PRESSIONE, e la pressione decade da
## sola quando smetti. Sopra una soglia si trincera: continua a venirti addosso
## con lo scudo alzato ma **non attacca piu'**. Quando la pressione ricade, lo
## scudo scende e parte subito.
##
## ─── Perche' e' sleale, e perche' e' giusto che lo sia ──────────────────────
## Perche' inverte il ritmo che il giocatore si e' abituato a imporre: il colpo
## non arriva quando sei aggressivo, arriva **nell'istante in cui ti fermi a
## respirare**. E' esattamente la lettura che un avversario umano fa, ed e' cio'
## che distingue un nemico da un bersaglio.
##
## ⚠️ NON e' senza risposta, e non deve esserlo. Chi insiste rompe la guardia:
## `guardia_tenuta` conta il danno ASSORBITO, quindi trincerarsi accorcia la
## vita dello scudo. Le due strade sono entrambe buone e vogliono cose diverse —
## insistere e rompere la guardia, o fermarsi e leggere il momento in cui esce.
## Quello che NON funziona piu' e' mescolarle a caso.
##
## ⚠️ Si conta cio' che gli ARRIVA ADDOSSO, non i fendenti che il giocatore
## tira. Un colpo a vuoto a tre metri non lo mette sotto pressione, ed e'
## giusto: non e' preveggenza, e' quello che ha incassato.
@export_group("Lettura dell'avversario")
## Quanta pressione aggiunge un colpo incassato, parato o no.
## A zero il meccanismo e' spento e il Fante torna quello di prima.
@export var pressione_per_colpo : float = 1.0
## Da qui in su si trincera. Tre colpi di fila, in pratica.
@export var pressione_soglia_su : float = 3.0
## E fin qui deve ricadere per tornare ad attaccare. E' l'ISTERESI: senza, sulla
## soglia sola oscillerebbe fra guardia e attacco a ogni frame.
@export var pressione_soglia_giu : float = 1.2
## Quanta ne perde al secondo. Con questi numeri, smettere di picchiare lo fa
## uscire dalla trincea in poco meno di due secondi.
@export var pressione_decadimento : float = 1.0
## Tetto: una raffica lunga non deve poterlo trincerare per dieci secondi.
@export var pressione_massima : float = 5.0
## Scarto casuale sulla soglia, per istanza. Sei Fanti con la stessa soglia
## escono dalla trincea tutti nello stesso fotogramma, e sei sagome che fanno la
## stessa cosa insieme si leggono come una sola.
@export_range(0.0, 0.5) var pressione_varianza : float = 0.15

var _pressione : float = 0.0
var _trincerato : bool = false
## La soglia di QUESTO Fante, con la varianza gia' applicata.
var _soglia_su : float = 0.0


## Frazione di danno che passa quando lo scudo non dichiara nulla per quel tipo.
## 1.0 = non protegge: un tipo di danno non previsto NON deve essere mitigato
## per caso. È l'opposto del default 0.5 del template, che regalava mezza
## mitigazione a qualunque cosa.
const GUARDIA_TIPO_IGNOTO := 1.0

var _in_guardia : bool = false
var _guardia_assorbito : float = 0.0
var _guardia_giu_fino : float = 0.0

@export_group("Animazioni umanoide")
@export var poise_break_anim : String = "sword/sword_poise_break_01"
@export var backstab_victim_anim : String = "sword/sword_backstab_victim_01"
@export var backstab_getup_anim : String = "sword/sword_backstab_getup_01"
@export var riposte_victim_anim : String = "sword/sword_riposte_victim_01"
@export var riposte_getup_anim : String = "sword/sword_riposte_getup_01"

## ─── LA CODA DEL FINISHER ───────────────────────────────────────────────────
## Quanto la morte ASPETTA ancora, dopo che la clip victim e' finita.
##
## Il Consumato faceva la sua morte regolarmente, ma **troppo presto rispetto al
## gesto del player**: deve cadere DOPO il calcio finale, non durante. Le due
## clip sono lunghe quasi uguale (victim 3.37s contro backstab 3.20, 4.03 contro
## riposte 3.83), quindi bastava pochissimo per farle scivolare l'una dentro
## l'altra — e in quel poco ci sta tutto il colpo di grazia.
##
## ⚠️ E' un TEMPO e non un aggancio all'animazione del player di proposito: il
## nemico non deve conoscere la clip di chi lo sta uccidendo. Se un domani il
## finisher cambia lunghezza si ritocca questo numero, che e' esportato apposta.
@export var finisher_coda : float = 0.6

## Altezza convenzionale del player, per misurare quanto l'arma gli è passata
## vicino (diagnostica di mira, vedi `_track_closest`).
const PLAYER_HEIGHT := 1.7
## m per frame: oltre è root motion spuria di un cambio clip, va scartata o il
## nemico teleporta. Tarata sulle clip del pack, che hanno affondi atletici.
const ROOT_MOTION_MAX_STEP := 1.5

# ─── Root motion ─────────────────────────────────────────────────────────────
var _root_motion_delta : Vector3 = Vector3.ZERO

# ─── Stato delle hitbox ──────────────────────────────────────────────────────
## Mossa la cui finestra d'arma è aperta ORA (null = arma spenta). Si porta
## dietro potenza e tipo di danno: è il motivo per cui questi nemici non possono
## usare l'EquipmentSystem del template, che passerebbe un `equipment_info`
## statico uguale per ogni mossa.
var _hit_move : EnemyMove = null
var _active_hitbox : Area3D = null
var _active_shape : CollisionShape3D = null
## Un colpo per swing: senza, l'Area3D che spazza il player registrerebbe più
## contatti nello stesso fendente.
var _hit_done : bool = false
var _prev_xform : Transform3D = Transform3D.IDENTITY
var _has_prev : bool = false
## Finestra armata per la mossa in corso, in TEMPO-CLIP: l'arma è viva quando il
## playhead ci sta dentro. Niente timer e niente coroutine — è il motivo per cui
## qui non serve più il "token" che serviva prima a invalidare le finestre di una
## mossa abortita: una finestra che non viene più aggiornata semplicemente non si
## apre. Il vecchio schema lasciava vive le coroutine delle mosse interrotte (un
## `await` di timer scade comunque), che si accavallavano con quelle nuove.
var _armed_hitbox : Area3D = null
var _window_from : float = -1.0
var _window_to : float = -1.0
## TUTTE le finestre della mossa in corso, in tempo-clip: una per colpo. Una
## clip a un colpo ne ha una; la combo dello spadone ne ha due, e fra l'una e
## l'altra la lama si CHIUDE e si RIAPRE — e' cosi' che il dedup "un colpo per
## swing" si azzera e il secondo fendente puo' toccare chi ha preso il primo.
## `_window_from`/`_window_to` restano la finestra CORRENTE (quella in cui sta
## il playhead), per il backstop ravvicinato e per gli strumenti che le leggono.
var _finestre : Array[Vector2] = []
## Avvicinamento massimo dell'arma al player in questo swing: è la misura che
## distingue "il player ha schivato" da "il nemico ha mirato male".
var _closest_approach : float = 9e9
## Shape di ogni hitbox, risolte una volta sola.
var _hitbox_shapes : Dictionary = {}

## Clip di rialzata da suonare quando finisce la victim in corso.
var _victim_getup : String = ""


## Le clip del pack Nephilite vivono sotto il prefisso "sword/". Gli export dei
## nomi clip sono dichiarati nella superclasse con i default generici
## ("idle", "walk", ...): li riscriviamo qui, in `_init` — che gira PRIMA che la
## scena applichi le proprie property, quindi un override nel .tscn continua a
## vincere.
func _init() -> void:
	idle_anim = "sword/sword_idle_01"
	walk_anim = "sword/sword_walk_01"
	run_anim = "sword/sword_run_01"
	death_anim = "sword/sword_death_01"
	hurt_anim = "sword/sword_hit_01"
	hurt_lock_time = 0.25
	turn_rate = 1.6
	snap_turn_mult = 8.0
	windup_turn_mult = 1.6
	chase_hysteresis = 0.7


func _setup() -> void:
	_soglia_su = pressione_soglia_su * randf_range(
		1.0 - pressione_varianza, 1.0 + pressione_varianza)
	_carica_librerie_arma()
	# ⚠️ DOPO le librerie e non prima: l'albero pesca le clip dall'AnimationPlayer,
	# e prima di `_carica_librerie_arma` l'AnimationPlayer non ne ha nessuna.
	_costruisci_albero()
	_setup_hitboxes()
	_connect_poise_break()


# ═══════════════════════════════════════════════════════════════════════════
# Librerie animazioni per FAMIGLIA D'ARMA (native dal pack Nephilite)
# ═══════════════════════════════════════════════════════════════════════════
## Questi nemici sono skinnati direttamente sullo scheletro del pack (zero
## retarget): ogni clip è un GLB solo-armatura esportato dallo stesso rig, quindi
## i nomi osso combaciano già. Qui si rimappa solo il prefisso-nodo delle tracce
## sul path scheletro della scena.
##
## Le clip sono raggruppate per FAMIGLIA D'ARMA, non per personaggio, e ogni
## famiglia è una cartella e una libreria: `sword/<nome>`, `spear/<nome>`.
## Serve perché lo stesso corpo verrà armato in modi diversi — un Consumato con
## lancia, uno con spada e scudo, uno con balestra pesante sono lo stesso rig e
## la stessa mesh con move set e libreria diversi. Legandola all'arma invece che
## al nemico, un tipo nuovo è una SCENA che dichiara la sua famiglia più un move
## set: niente codice da toccare.
##
## La locomozione vive in `sword/` ed è condivisa: sono clip del corpo, non
## dell'arma. Quando una famiglia avrà la propria (camminare con l'asta è
## diverso), basterà aggiungerla alla sua lista e sovrascrivere `idle_anim` &c.
## nella scena.

const ANIM_DIR := "res://assets/characters/enemies/anims/"
const FAMIGLIE : Dictionary = {
	"sword": [
		"sword_light_attack_01", "sword_light_attack_02", "sword_run_attack_01",
		"sword_charged_attack_01", "sword_charged_attack_02", "sword_jump_attack_01",
		"sword_th_charged_attack_01",
		# ⚠️ AUTORATA IN CASCADEUR, non del pack: e' la prima. Avanzamento e botta
		# di scudo, 2,73 s, contatto misurato al frame 48 (1,600 s) dove lo scudo
		# raggiunge gli 81,8 cm davanti al bacino e frena. I 2,342 m di
		# avanzamento sono bakeati sul `Root` come nelle clip del pack — se
		# tornassero sull'`Hips` il Fante scivolerebbe con la mesh e il corpo
		# resterebbe fermo (vedi arcanium/tools/bake_root_motion.py).
		"sword_shield_bash_01",
		# ⚠️ A STRATO, non una clip intera: e' autorata col corpo A RIPOSO
		# tranne il braccio destro, perche' in gioco tutto il resto viene
		# filtrato via. Se un giorno la si guarda in un player di animazioni e
		# «sembra rotta», non lo e': manca il corpo che in gioco ci sta sotto.
		"sword_guard_thrust_01",                            # Legione Testuggine
		# ⚠️ AUTORATA IN CASCADEUR (2026-09-12), a DUE COLPI: fendente
		# orizzontale (~f35) e gran colpo dall'alto (~f84), 3,33 s, sul posto —
		# torna esattamente alla posa di partenza. Lo spadone la usa come S2.
		# Due colpi = due finestre d'arma: vedi `_finestre`.
		"sword_th_combo_01",
		# ⚠️ L'ARCO, autorate dall'utente in Cascadeur (2026-09-13): il tiro
		# rapido (2,17 s) e quello caricato (4,00 s). Arco nella destra ferma,
		# la sinistra carica e rilascia: il rilascio misurato sulla SINISTRA.
		# Sul posto, nessun root motion.
		"sword_bow_shot_01", "sword_bow_shot_charged_01",
		# L'idle con l'arco in mano (autorata dall'utente in Cascadeur sul corpo
		# Tripo, 2026-09-14, 2,73 s in loop): l'arciere la dichiara come
		# `idle_anim` nella sua scena, la spada tiene `sword_idle_01`.
		"sword_bow_idle_01",
		# La corsa con l'arco (stessa mano, 2026-09-14): autorata SUL POSTO a 40
		# frame (2,5 passi, piedi a 8,5-9 m/s), tagliata su UN passo (f06->f22,
		# 16 frame, estremi in appoggio del sinistro) e chiusa nei controlli
		# con `casc_taglia_loop.py`; `rifinisci_clip_cascadeur.py --frame 27
		# --avanza 5.28` la ritma e le scrive sul Root l'avanzamento della
		# `sword_run_01` come gira in gioco (5,28 m/s): i piedi non pattinano.
		"sword_bow_run_01",
		"sword_cast_01",                                    # windup telegrafato, rilascio a ~2.0s
		"sword_burst_01",                                   # scarica radiale ravvicinata
		"sword_idle_01", "sword_walk_01", "sword_run_01",   # locomozione (root motion forward)
		"sword_death_01", "sword_hit_01", "sword_poise_break_01",
		# coppie victim dei finisher del player + rialzate, native sul rig.
		"sword_backstab_victim_01", "sword_backstab_getup_01",
		"sword_riposte_victim_01", "sword_riposte_getup_01",
	],
	"spear": [
		# Composti dalle fasi charge/hold/release del pack e raddrizzati a 0
		# gradi sull'asta (vedi _sorgenti/affondi_nephilite.blend).
		"spear_thrust_01", "spear_thrust_charged_01",
	],
}

## Quali famiglie caricare. Si dichiara nella SCENA del nemico: il Consumato con
## lancia mette ["sword", "spear"], quello con spada e scudo solo ["sword"].
@export var famiglie_anim : PackedStringArray = ["sword"]


func _carica_librerie_arma() -> void:
	if anim_player == null:
		return
	# Path scheletro RELATIVO alla root dell'AnimationPlayer (il nodo Model).
	var sk_rel := str(skeleton_path).trim_prefix("Model/")
	for famiglia in famiglie_anim:
		_carica_famiglia(str(famiglia), sk_rel)


## Una famiglia = una cartella e una libreria omonima. Le clip mancanti si
## saltano in silenzio: una famiglia a metà è meglio di un nemico senza clip.
func _carica_famiglia(famiglia : String, sk_rel : String) -> void:
	if not FAMIGLIE.has(famiglia):
		push_warning("Famiglia d'arma sconosciuta: " + famiglia)
		return
	var lib := AnimationLibrary.new()
	for clip in FAMIGLIE[famiglia]:
		var path : String = "%s%s/%s.glb" % [ANIM_DIR, famiglia, clip]
		if not ResourceLoader.exists(path):
			continue
		var scene : PackedScene = load(path)
		var inst := scene.instantiate()
		var ap : AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if ap == null or ap.get_animation_list().is_empty():
			inst.queue_free()
			continue
		var anim : Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		for i in anim.get_track_count():
			var p := str(anim.track_get_path(i))
			var colon := p.find(":")
			if colon < 0:
				continue
			anim.track_set_path(i, "%s:%s" % [sk_rel, p.substr(colon + 1)])
		lib.add_animation(clip, anim)
		inst.queue_free()
	if anim_player.has_animation_library(famiglia):
		anim_player.remove_animation_library(famiglia)
	anim_player.add_animation_library(famiglia, lib)

	# ROOT MOTION sul bone `Root`, l'architettura per cui il pack è progettato.
	# L'AnimationMixer estrae la traslazione della track e la RIMUOVE dalla posa
	# su tutti e tre gli assi: con la track sull'Hips spariva anche la componente
	# VERTICALE (oscillazione del passo, abbassamento sugli affondi, salto), e il
	# nemico sembrava galleggiare su ogni clip. Con l'orizzontale bakeata sul
	# `Root` e la verticale nativa sull'Hips, il CharacterBody prende lo
	# spostamento e la posa si tiene il peso.
	anim_player.root_motion_track = NodePath("%s:%s" % [sk_rel, "Root"])


# ═══════════════════════════════════════════════════════════════════════════
# L'ALBERO — locomozione a due slot + strato di guardia
# ═══════════════════════════════════════════════════════════════════════════
##
##     ClipA ─┐
##            ├─► Corpo (Transition, xfade) ─► Velocita (TimeScale) ─┐
##     ClipB ─┘                                                      ├─► Guardia
##     PosaGuardia (fotogramma congelato) ───────────────────────────┘  (Blend2
##                                                                       filtrato
##                                                                       spina in su)
##
## ─── Perché DUE slot e non uno ──────────────────────────────────────────────
## `AnimationNodeAnimation` tiene UNA clip, scritta nella sua proprietà. Il
## nemico invece suona clip decise dai DATI (`EnemyMove.anim`): scrivere il nome
## nuovo sullo stesso nodo cambierebbe la clip di scatto, senza dissolvenza —
## cioè si perderebbe `anim_xfade`, che è l'unica cosa che tiene insieme
## camminata e fendente. Con due slot e un `AnimationNodeTransition` in mezzo si
## riempie SEMPRE lo slot fermo e si chiede la transizione: la dissolvenza la fa
## il nodo, con lo stesso numero di prima.
##
## ─── Perché il TimeScale sta DOPO il Transition ─────────────────────────────
## `anim_speed_scale` vale per il personaggio, non per la clip: uno solo, dopo,
## invece di due gemelli da tenere allineati. L'unico caso in cui si vede la
## differenza è `speed_override` durante una dissolvenza — per mezzo `xfade`
## anche la clip uscente va alla velocità nuova. Le clip che usano l'override
## (morte, coppie victim/getup) partono con `xfade` a zero apposta: lì non ci
## sono due clip insieme.
##
## ⚠️ IL FILTRO NON TOCCA `Root` NÉ `Hips`. La ROOT MOTION passa dal `Root`: se
## finisse dentro il filtro, la posa di guardia — che sta ferma — lo azzererebbe
## e il Fante alzerebbe lo scudo restando inchiodato a terra.
const SLOT : PackedStringArray = ["ClipA", "ClipB"]
const NODO_CORPO := "Corpo"
const NODO_VELOCITA := "Velocita"
const NODO_GUARDIA := "Guardia"
const NODO_POSA := "PosaGuardia"
## Lo strato dei gesti che non prendono possesso del corpo (vedi
## `EnemyMove.strato`): un one-shot filtrato che si sovrappone alla guardia.
const NODO_STRATO := "Strato"
const NODO_STRATO_CLIP := "StratoClip"
## Da quale osso in su comanda lo strato alto. Tutto cio' che discende da qui
## entra nel filtro; il resto (bacino, gambe, gonnellino, `Root`) resta della
## locomozione.
const OSSO_ALTO := "Spine"
## Da quale osso parte il filtro delle mosse a strato, quando la mossa non lo
## dichiara. Il braccio armato: e' quello che colpisce senza toccare lo scudo.
@export var strato_radice_predefinita : String = "RightShoulder"

var _albero : AnimationTree = null
var _slot_attivo : int = 0
var _nodi_slot : Array[AnimationNodeAnimation] = []
var _nodo_corpo : AnimationNodeTransition = null
var _nodo_strato_clip : AnimationNodeAnimation = null
## Clip in corso sullo strato, "" se lo strato e' spento. E' anche il modo in
## cui il resto del ciclo sa che la mossa corrente non possiede il corpo.
var _strato_attivo : String = ""
var _inerzia : SkeletonModifier3D = null
var _blend_guardia : float = 0.0


func _costruisci_albero() -> void:
	if not usa_anim_tree or anim_player == null or model == null:
		return
	var sk_rel := str(skeleton_path).trim_prefix("Model/")
	var sk := model.get_node_or_null(sk_rel) as Skeleton3D
	if sk == null:
		push_warning("AnimationTree: scheletro non trovato in " + str(skeleton_path))
		return

	var bt := AnimationNodeBlendTree.new()

	# I due slot della locomozione. Partono entrambi dall'idle: un
	# `AnimationNodeAnimation` senza clip fa rumore nel log e non serve a niente.
	_nodi_slot.clear()
	for nome in SLOT:
		var a := AnimationNodeAnimation.new()
		a.animation = idle_anim
		bt.add_node(nome, a)
		_nodi_slot.append(a)

	_nodo_corpo = AnimationNodeTransition.new()
	_nodo_corpo.input_count = 2
	_nodo_corpo.set_input_name(0, SLOT[0])
	_nodo_corpo.set_input_name(1, SLOT[1])
	_nodo_corpo.xfade_time = anim_xfade
	## ⚠️ La dissolvenza LINEARE e' il residuo di scatto che resta anche quando
	## le clip sono giuste: il peso parte da zero con pendenza piena e ci
	## arriva con pendenza piena, quindi l'inizio e la fine della fusione sono
	## due strappi. Una curva a S entra e esce con pendenza nulla — la posa
	## comincia a muoversi da ferma e si rimette ferma.
	_nodo_corpo.xfade_curve = _curva_a_esse()
	## ⚠️ `false`: chiedere la transizione verso lo slot in cui si è già
	## farebbe ripartire la clip da zero. Le mosse ripetute (due fendenti uguali
	## di fila) passano comunque, perché `_play` alterna gli slot a ogni chiamata.
	_nodo_corpo.allow_transition_to_self = false
	bt.add_node(NODO_CORPO, _nodo_corpo)

	var ts := AnimationNodeTimeScale.new()
	bt.add_node(NODO_VELOCITA, ts)

	var posa := AnimationNodeAnimation.new()
	posa.animation = guardia_posa_anim
	## Il fotogramma congelato: si entra nella clip a `guardia_posa_tempo` e si
	## resta lì. `stretch_time_scale = false` perché la finestra va letta in
	## tempo-clip vero, non riscalata sulla durata dello slot.
	posa.use_custom_timeline = true
	posa.start_offset = guardia_posa_tempo
	## ⚠️⚠️ UN FOTOGRAMMA, E IN LOOP_NONE. Qui c'era `timeline_length = 0.12` con
	## `LOOP_LINEAR`, e non era affatto una posa congelata: erano dodici
	## centesimi di shield bash ripetuti a ciclo. In quella fetta il braccio
	## sinistro oscilla di 12,7 gradi e la mano destra di 37,5 — a otto ripetizioni
	## al secondo, un TREMOLIO. Si vedeva a occhio e nessun numero lo diceva,
	## perche' la posa "c'era" ed era quella giusta: solo, non stava ferma.
	##
	## Con `LOOP_NONE` il nodo suona la fetta una volta e poi TIENE l'ultimo
	## valore: una posa sola, davvero. La fetta resta corta ma non nulla —
	## a lunghezza zero il nodo non ha un fotogramma da tenere.
	posa.timeline_length = 0.01
	posa.stretch_time_scale = false
	posa.loop_mode = Animation.LOOP_NONE
	bt.add_node(NODO_POSA, posa)

	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	for osso in _ossa_da(sk, OSSO_ALTO):
		blend.set_filter_path(NodePath("%s:%s" % [sk_rel, osso]), true)
	bt.add_node(NODO_GUARDIA, blend)

	## ─── LO STRATO ───────────────────────────────────────────────────────────
	## Un `AnimationNodeOneShot` filtrato sul solo braccio armato, montato SOPRA
	## la guardia. Sopra e non sotto: l'ordine e' cio' che decide chi vince
	## sulle ossa condivise, e la Testuggine deve poter muovere il braccio
	## destro che la guardia stava tenendo fermo.
	##
	## ⚠️ Un one-shot e non un secondo `Blend2`: il gesto ha un inizio e una
	## fine, e la dissolvenza in entrata e in uscita la fa il nodo. Con un
	## `Blend2` il peso andrebbe pilotato a mano, e la clip resterebbe accesa a
	## peso zero per sempre.
	_nodo_strato_clip = AnimationNodeAnimation.new()
	_nodo_strato_clip.animation = idle_anim
	bt.add_node(NODO_STRATO_CLIP, _nodo_strato_clip)

	var uno := AnimationNodeOneShot.new()
	uno.fadein_time = strato_dissolvenza
	uno.fadeout_time = strato_dissolvenza
	uno.filter_enabled = true
	for osso in _ossa_da(sk, strato_radice_predefinita):
		uno.set_filter_path(NodePath("%s:%s" % [sk_rel, osso]), true)
	bt.add_node(NODO_STRATO, uno)

	## ⚠️ `connect_node(chi_riceve, quale_ingresso, chi_manda)` — il primo
	## argomento è il nodo A VALLE. Invertirli non solleva nessun errore e non
	## lascia nessuna traccia: il nodo resta scollegato e l'albero suona un
	## silenzio perfetto.
	bt.connect_node(NODO_CORPO, 0, SLOT[0])
	bt.connect_node(NODO_CORPO, 1, SLOT[1])
	bt.connect_node(NODO_VELOCITA, 0, NODO_CORPO)
	bt.connect_node(NODO_GUARDIA, 0, NODO_VELOCITA)
	bt.connect_node(NODO_GUARDIA, 1, NODO_POSA)
	bt.connect_node(NODO_STRATO, 0, NODO_GUARDIA)
	bt.connect_node(NODO_STRATO, 1, NODO_STRATO_CLIP)
	bt.connect_node("output", 0, NODO_STRATO)

	_albero = AnimationTree.new()
	_albero.name = "AlberoAnim"
	_albero.tree_root = bt
	## `root_node` deve essere lo STESSO dell'AnimationPlayer (il nodo Model), o
	## i path delle tracce — che `_carica_famiglia` ha appena riscritto come
	## `NephiliteRig/Skeleton3D:Osso` — non risolvono più.
	model.add_child(_albero)
	_albero.root_node = NodePath("..")
	_albero.anim_player = _albero.get_path_to(anim_player)
	_albero.root_motion_track = anim_player.root_motion_track
	## Lo stesso momento di aggiornamento dell'AnimationPlayer che sostituisce:
	## la root motion si legge in `_physics_process`, e due mixer che girano in
	## momenti diversi darebbero due spostamenti diversi per lo stesso frame.
	_albero.callback_mode_process = anim_player.callback_mode_process

	## Da qui in poi comanda l'albero: se l'AnimationPlayer continuasse a suonare
	## per conto suo scriverebbero sulle stesse ossa a turno.
	anim_player.stop()
	if anim_player.animation_finished.is_connected(_on_anim_finished):
		anim_player.animation_finished.disconnect(_on_anim_finished)
	_albero.animation_finished.connect(_on_anim_finished)

	_costruisci_inerzia(sk)

	_albero.active = true
	_albero.set("parameters/%s/scale" % NODO_VELOCITA, anim_speed_scale)
	_albero.set("parameters/%s/blend_amount" % NODO_GUARDIA, 0.0)


## Il modificatore che smorza lo scarto fra due pose. Sta sullo scheletro, non
## sull'albero: lavora DOPO che il mixer ha scritto la posa.
##
## ⚠️ Va messo PRIMA dell'IK dei piedi (`move_child(..., 0)`): i modificatori
## girano nell'ordine dei figli, e l'IK deve correggere la posa DEFINITIVA. Al
## contrario l'inerzia sommerebbe il suo scarto sopra piedi gia' posati, e
## rimetterebbe in aria proprio quello che l'IK era appena riuscito a posare.
const INERZIA := preload("res://arcanium/systems/inerzia_anim.gd")

func _costruisci_inerzia(sk : Skeleton3D) -> void:
	if not usa_inerzia:
		return
	_inerzia = INERZIA.new()
	_inerzia.name = "Inerzia"
	_inerzia.set("durata", inerzia_durata)
	sk.add_child(_inerzia)
	sk.move_child(_inerzia, 0)


## Una curva 0→1 che parte e arriva con pendenza nulla (tangenti a zero).
## E' la stessa forma dello `smoothstep`: niente strappo agli estremi.
func _curva_a_esse() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0), 0.0, 0.0)
	c.add_point(Vector2(1.0, 1.0), 0.0, 0.0)
	c.bake()
	return c


## Le ossa di una CATENA: l'osso dato e tutta la sua discendenza.
##
## ⚠️ Si ricava dallo SCHELETRO e non da una lista scritta a mano. Una lista
## ricopiata sopravvive al corpo che descrive: il Fante ha ossa di aggancio
## (`Shield_Attachment_L`, `Prop_Attachment_R`) appese alle mani, ed è a quelle
## che stanno attaccati scudo e spada. Dimenticarne una lascia lo scudo indietro
## mentre il braccio si alza.
func _ossa_da(sk : Skeleton3D, dal : String) -> PackedStringArray:
	var radice := sk.find_bone(dal)
	if radice < 0:
		push_warning("AnimationTree: osso '%s' assente, filtro vuoto" % dal)
		return PackedStringArray()
	var dentro := {radice: true}
	var fuori : PackedStringArray = [sk.get_bone_name(radice)]
	## Le ossa di uno Skeleton3D sono in ordine topologico (un genitore viene
	## sempre prima dei figli), quindi una sola passata basta.
	for i in sk.get_bone_count():
		if dentro.has(sk.get_bone_parent(i)):
			dentro[i] = true
			fuori.append(sk.get_bone_name(i))
	return fuori


## Muove il valore continuo dell'albero: quanto e' alzato lo scudo. Non salta
## mai a destinazione.
##
## ⚠️ Gira in `_special_state_step`, cioe' in OGNI stato — anche dentro uno
## stagger o un finisher subito, dove `_pre_ai_step` non viene chiamato affatto.
## Stava li' prima, e il risultato era uno scudo che restava alzato mentre il
## Fante veniva pugnalato alle spalle: il blend si congelava sull'ultimo valore
## perche' nessuno lo aggiornava piu'.
func _aggiorna_blend(delta : float) -> void:
	if _albero == null or delta <= 0.0:
		return

	## `1 - exp(-k * delta)` invece di una frazione fissa per fotogramma: la
	## stessa sfumatura a 30, 60 e 144 fps. Con un `lerp(a, b, 0.2)` la guardia
	## saliva a velocita' diverse a seconda di quanto girava il gioco.
	var giu : bool = _state == State.DEAD or _state == State.STAGGERED \
		or _state == State.VICTIM
	var bersaglio_g : float = 1.0 if (_in_guardia and not giu) else 0.0
	var k_g : float = 1.0 - exp(-guardia_velocita_blend * delta)
	_blend_guardia = _avvicina(_blend_guardia, bersaglio_g, k_g)
	_albero.set("parameters/%s/blend_amount" % NODO_GUARDIA, _blend_guardia)


## Un passo verso il bersaglio, con la coda chiusa a mano: un `lerp` esponenziale
## al bersaglio non ci arriva MAI, e restare a 0.999 significa tenere due clip
## accese per sempre — costo doppio, e un filo di posa sbagliata che non se ne va.
func _avvicina(ora : float, bersaglio : float, k : float) -> float:
	var nuovo : float = lerp(ora, bersaglio, k)
	if absf(nuovo - bersaglio) < 0.002:
		return bersaglio
	return nuovo


# ─── Le tre letture che cambiano quando comanda l'albero ─────────────────────

func _clip_corrente() -> String:
	if _albero == null:
		return super._clip_corrente()
	## Con una mossa a strato in corso, la clip "che sta suonando" ai fini del
	## colpo e' quella dello STRATO: il corpo intanto cammina, e `_current_anim`
	## dice la camminata.
	if _strato_attivo != "":
		return _strato_attivo
	return _current_anim

func _clip_pos() -> float:
	if _albero == null:
		return super._clip_pos()
	if _strato_attivo != "":
		return float(_albero.get("parameters/%s/current_position" % NODO_STRATO_CLIP))
	return float(_albero.get("parameters/%s/current_position" % SLOT[_slot_attivo]))

func _root_motion() -> Vector3:
	if _albero == null:
		return super._root_motion()
	return _albero.get_root_motion_position()


## Stessa firma e stesse promesse di `ArcaniumEnemy._play`, ma sull'albero.
##
## Due strade, e la differenza e' tutta qui: una clip di locomozione NON viene
## fatta partire — si sposta il punto dello spazio di fusione, e le tre clip che
## ci stanno dentro continuano a girare come stavano girando. Tutto il resto
## (fendenti, colpi subiti, morte) passa dai due slot alternati.
func _play(name : String, loop : bool, speed_override : float = -1.0,
		xfade_override : float = -1.0) -> void:
	if _albero == null:
		super._play(name, loop, speed_override, xfade_override)
		return
	if anim_player == null or name == "" or not anim_player.has_animation(name):
		return
	## Una mossa a strato non passa dal corpo: si accende il one-shot e si
	## lascia camminare le gambe.
	if _strato_attivo != "" and name == _strato_attivo:
		_nodo_strato_clip.animation = name
		anim_player.get_animation(name).loop_mode = Animation.LOOP_NONE
		_albero.set("parameters/%s/request" % NODO_STRATO,
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return
	if _current_anim == name:
		return
	_current_anim = name
	var a := anim_player.get_animation(name)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_albero.set("parameters/%s/scale" % NODO_VELOCITA,
		speed_override if speed_override > 0.0 else anim_speed_scale)

	# Si riempie sempre lo slot FERMO: quello che sta suonando deve poter
	# sfumare via mentre l'altro entra.
	_slot_attivo = 1 - _slot_attivo
	_nodi_slot[_slot_attivo].animation = name
	## Entrare in un fendente e' secco — e' il telegrafo su cui il giocatore
	## temporizza — ma TORNARE al passo no: li' non c'e' niente da leggere, solo
	## un corpo che si rimette in cammino, e una dissolvenza corta lo fa
	## sobbalzare.
	if xfade_override >= 0.0:
		_nodo_corpo.xfade_time = xfade_override
	elif _inerzia != null:
		# Zero, e non "poco": vedi il cappello di `usa_inerzia`. Con anche solo
		# cinque centesimi di dissolvenza lo scarto viene fotografato a meta'
		# fusione, e l'inerzia peggiora le cose invece di migliorarle.
		_nodo_corpo.xfade_time = 0.0
	else:
		_nodo_corpo.xfade_time = anim_xfade
	_albero.set("parameters/%s/transition_request" % NODO_CORPO, SLOT[_slot_attivo])
	if _inerzia != null:
		_inerzia.avvia()


# ═══════════════════════════════════════════════════════════════════════════
# Ciclo: stati speciali, root motion, movimento in attacco
# ═══════════════════════════════════════════════════════════════════════════

func _special_state_step(delta : float) -> bool:
	## ⚠️ QUI e non in `_pre_ai_step`. Questo e' l'unico innesto che il ciclo
	## attraversa in OGNI stato: `_pre_ai_step` non viene chiamato affatto
	## dentro uno stagger o un finisher subito, e i due valori continui
	## dell'albero (scudo, locomozione) restavano congelati sull'ultimo numero.
	## Si vedeva: il Fante veniva pugnalato alle spalle con lo scudo ancora su.
	_aggiorna_blend(delta)
	_aggiorna_pressione(delta)

	if _state == State.STAGGERED:
		# Guardia rotta: fermo in piedi, la clip fa il resto.
		_apply_gravity(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return true

	if _state == State.VICTIM:
		# Congelato nel finisher del player, ma la ROOT MOTION della clip victim
		# si applica: la caduta/barcollamento porta spostamento authorato.
		# Niente facing: il nemico è in balia dell'attaccante.
		_apply_gravity(delta)
		var victim_rm : Vector3 = _root_motion()
		if victim_rm.length() > ROOT_MOTION_MAX_STEP:
			victim_rm = Vector3.ZERO
		if delta > 0.0:
			var world_rm := global_transform.basis * victim_rm
			velocity.x = world_rm.x / delta
			velocity.z = world_rm.z / delta
		move_and_slide()
		return true

	return false


func _pre_ai_step(delta : float) -> void:
	# Drena l'accumulatore di root motion OGNI frame: se non lo si legge, si
	# scarica tutto insieme alla prima lettura e il nemico fa uno scatto.
	_root_motion_delta = _root_motion()
	if _root_motion_delta.length() > ROOT_MOTION_MAX_STEP:
		_root_motion_delta = Vector3.ZERO

	# Apertura/chiusura dell'arma dal playhead. Non serve più alcun watchdog per
	# le mosse abortite: se la clip cambia o lo stato diventa STAGGERED/VICTIM,
	# la finestra semplicemente non risulta più attiva e l'arma si spegne da
	# sola nello stesso frame — prima restava viva una coroutine appesa e il
	# nemico continuava a ferire mentre era a terra.
	_update_weapon_window()

	# La sonda DEVE girare qui: gli attacchi sono proprio `_busy`, e più in
	# basso nel ciclo non verrebbe mai eseguita.
	if _active_hitbox and _active_hitbox.monitoring:
		_weapon_sweep()

	_aggiorna_guardia()

	_track_target(delta)


# ═══════════════════════════════════════════════════════════════════════════
# Guardia
# ═══════════════════════════════════════════════════════════════════════════

## Alza e abbassa lo scudo. **È il tell su cui il giocatore temporizza**: la
## guardia cade mentre attacca (`_busy`), e quella è la finestra per colpire.
## Non c'è nessun timer a farla oscillare: se oscillasse da sola sarebbe rumore,
## e il giocatore imparerebbe un ritmo invece di leggere il nemico.
func _aggiorna_guardia() -> void:
	var vuole := (
		scudo != null
		## ⚠️ `_strato_attivo` scavalca `_busy`: una mossa A STRATO non fa cadere
		## la guardia, ed e' tutto il punto della Testuggine. Senza questa riga
		## l'affondo abbasserebbe lo scudo proprio nell'istante in cui passa
		## sopra il suo bordo.
		and (not _busy or _strato_attivo != "")
		and _state != State.DEAD and _state != State.STAGGERED and _state != State.VICTIM
		and _now() >= _guardia_giu_fino
		and is_instance_valid(target)
		and _flat_distance(target) <= guardia_distanza
	)
	if vuole == _in_guardia:
		return
	_in_guardia = vuole
	if _in_guardia:
		_guardia_assorbito = 0.0
	# Non si forza NESSUNA clip, ne' alzandola ne' abbassandola. Alzandola ci
	# pensa lo strato mescolato (`_aggiorna_blend_guardia`), che sale sopra
	# qualunque cosa stiano facendo le gambe; abbassandola o sta partendo un
	# attacco (che ha la sua clip) o e' STAGGERED (idem), e sovrascriverle qui
	# le troncherebbe.


## Scala la pressione e decide se restare trincerato. Gira in ogni stato: anche
## mentre incassa un poise-break la pressione deve scendere, o si rialzerebbe
## gia' pronto a trincerarsi di nuovo.
func _aggiorna_pressione(delta : float) -> void:
	if not _legge_avversario():
		return
	if _pressione > 0.0:
		_pressione = maxf(0.0, _pressione - pressione_decadimento * delta)
	if not _trincerato:
		if _pressione >= _soglia_su:
			_trincerato = true
	elif _pressione <= pressione_soglia_giu:
		_trincerato = false
		## ⚠️ E qui sta la slealta': non aspetta il proprio turno. Uscendo dalla
		## trincea azzera l'attesa fra un attacco e l'altro, quindi il fendente
		## parte nel primo fotogramma utile — cioe' NELL'ISTANTE in cui il
		## giocatore ha smesso di picchiare. Senza questa riga si trincererebbe
		## e basta, e la lettura non pagherebbe niente.
		_next_attack = 0.0


## Il meccanismo esiste solo per chi ha uno scudo da tenere alzato: senza, «mi
## trincero» vorrebbe dire «resto fermo a prenderle», che non e' una tattica.
func _legge_avversario() -> bool:
	return scudo != null and pressione_per_colpo > 0.0


## Un colpo incassato — parato o passato — alza la pressione.
func _registra_pressione() -> void:
	if not _legge_avversario():
		return
	_pressione = minf(pressione_massima, _pressione + pressione_per_colpo)


## Trincerato non attacca: nessuna mossa e' utilizzabile, quindi `_choose_move`
## torna null e il ciclo ricade da solo sull'inseguimento. Continua a venirti
## addosso, con lo scudo alzato, e aspetta.
##
## ⚠️ Sta QUI e non in `_try_attack` perche' il boss e i mini-boss sovrascrivono
## `_move_is_usable` per conto loro: mettendolo nel filtro delle mosse, chi
## eredita se lo porta dietro chiamando `super`, e chi non ha scudo non se ne
## accorge nemmeno (`_legge_avversario` e' falso).
## ⚠️ E una mossa A STRATO passa ANCHE da trincerato — anzi, e' l'unica che
## passa, ed e' il pezzo che mancava alla trincea. Un Fante che si chiude non e'
## piu' un bersaglio fermo: chi lo tempesta di colpi si prende comunque
## l'affondo che sbuca dal bordo dello scudo. La guardia non cade, quindi la
## lettura del giocatore resta quella di prima — o rompi, o aspetti — ma
## aspettare adesso costa.
func _move_is_usable(move : EnemyMove) -> bool:
	if move.solo_in_guardia and not _in_guardia:
		return false
	## Senza albero uno strato non esiste, e NON si ripiega su una clip intera:
	## sostituirebbe il corpo, cioe' cancellerebbe la guardia che e' la ragione
	## per cui la mossa esiste.
	if move.strato and _albero == null:
		return false
	if _trincerato and not move.strato:
		return false
	## Senza linea di tiro un proiettile finirebbe in un tronco: la mossa non
	## si sceglie nemmeno.
	if move.projectile_scene != null and not _has_line_of_sight():
		return false
	return super._move_is_usable(move)


## Il colpo arriva dentro il cono protetto?
##
## ⚠️ Si misura sul FRONTE DELLA MESH, che guarda +Z (stessa convenzione di
## `_apply_hit`): usare la basis grezza qui darebbe un cono ruotato di 90° e uno
## scudo che para di fianco.
func _guardia_copre(chi : Node) -> bool:
	if not _in_guardia or not is_instance_valid(chi) or not (chi is Node3D):
		return false
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return false
	var verso := (chi as Node3D).global_position - global_position
	verso.y = 0.0
	if verso.length() < 0.001:
		return false
	return fwd.normalized().dot(verso.normalized()) >= cos(guardia_arco)


## Sostituisce `damage_taken.emit()` per il colpo parato: il danno ridotto va
## applicato DIRETTAMENTE all'HealthSystem, esattamente come fa il player in
## `block()`. Passare per il segnale significherebbe consegnare l'oggetto arma
## intatto, e l'HealthSystem ne rileggerebbe la `power` piena.
func _blocca(chi : Node, colpo) -> void:
	var dtype : String = colpo.damage_type if "damage_type" in colpo else "FISICO"
	var pieno : float = float(colpo.power) if "power" in colpo else 0.0
	var passa : float = GUARDIA_TIPO_IGNOTO
	if scudo and scudo.block_resistances.has(dtype):
		passa = float(scudo.block_resistances[dtype])
	var entra := pieno * passa

	if health_system and health_system.has_method("apply_damage"):
		health_system.apply_damage(entra, dtype)
	# La barretta si aggiorna da sola: `apply_damage` emette `health_updated`.
	_play(guardia_block_anim, false)

	# Si accumula ciò che lo SCUDO ha mangiato, non ciò che è passato.
	_guardia_assorbito += maxf(0.0, pieno - entra)
	if _guardia_assorbito >= guardia_tenuta:
		_rompi_guardia()

	# Il colpo parato AGGRA comunque: chi picchia sullo scudo si è fatto notare.
	if is_instance_valid(chi):
		target = chi
		_provocato_fino = _now() + provocazione_durata


## Rompere la guardia riusa la macchina che esiste già: lo status `poise_break`
## porta a STAGGERED, fa partire `poise_break_anim` e apre la finestra di
## punizione. Costruirne una seconda qui avrebbe voluto dire due modi diversi di
## essere "scoperto", che prima o poi divergono.
func _rompi_guardia() -> void:
	_in_guardia = false
	_guardia_assorbito = 0.0
	_guardia_giu_fino = _now() + guardia_riposo
	## La trincea muore con lo scudo: chi ha appena visto saltare la propria
	## guardia non ci si rimette dentro: si rialza e mena. Senza questo, dopo lo
	## stagger sarebbe rimasto trincerato con lo scudo abbassato — cioe' fermo a
	## prenderle, che e' il peggio dei due mondi.
	_pressione = 0.0
	_trincerato = false
	if health_system and "status_host" in health_system:
		var host = health_system.status_host
		if host and host.has_method("break_poise_now"):
			host.break_poise_now()


## Intercetta il colpo PRIMA della catena normale.
##
## ⚠️ I finisher non passano di qui — `backstabbed()` e `riposted()` sono chiamati
## direttamente dal player — quindi lo scudo non li ferma, e non deve: prendere
## alle spalle un nemico in guardia è esattamente la risposta che il grado ①
## vuole insegnare.
func hit(_who, _by_what) -> void:
	if _state == State.DEAD:
		return
	# Prima di sapere se lo scudo copre: conta il colpo comunque, perche' un
	# fendente che passa di lato e' aggressione quanto uno che rimbalza.
	_registra_pressione()
	if _guardia_copre(_who):
		_blocca(_who, _by_what)
		return
	super.hit(_who, _by_what)


# ═══════════════════════════════════════════════════════════════════════════
# Mosse a distanza
# ═══════════════════════════════════════════════════════════════════════════
##
## ⚠️ SOLLEVATE DAL BOSS il 2026-09-12, quando e' arrivato il secondo che
## spara: l'arciere Sylvorn. Prima vivevano in `arcanium_boss.gd` con
## `cast_origin`, la linea di tiro e la mira predittiva; un arciere che le
## copiasse sarebbe stato il secondo posto dove la mira puo' divergere. Una
## mossa e' RANGED se `EnemyMove.projectile_scene` e' valorizzato: il colpo
## non passa dalla lama (`_move_uses_weapon` false), non e' scelto senza linea
## di tiro (`_move_is_usable`), e al contatto misurato — il rilascio — nasce
## il proiettile (`_deliver_hit`). Il boss ci mette sopra solo il suo VFX.

## Origine di spell e proiettili: un BoneAttachment3D sulla mano che tira.
## Vuoto = ripiego davanti al petto.
@export var cast_origin : NodePath

## Velocita' orizzontale smussata del bersaglio: serve alla MIRA PREDITTIVA
## e a chi pesa le mosse su dove sta andando il player (il boss).
var _target_prev_pos : Vector3 = Vector3.ZERO
var _target_vel : Vector3 = Vector3.ZERO
var _has_prev_pos : bool = false


## Velocita' orizzontale smussata del bersaglio (finestra breve): taglia il
## rumore per-frame e mantiene la tendenza.
func _track_target(delta : float) -> void:
	if not is_instance_valid(target) or delta <= 0.0:
		_has_prev_pos = false
		return
	var pos := target.global_position
	pos.y = 0.0
	if not _has_prev_pos:
		_target_prev_pos = pos
		_has_prev_pos = true
		return
	_target_vel = _target_vel.lerp((pos - _target_prev_pos) / delta, clampf(delta * 6.0, 0.0, 1.0))
	_target_prev_pos = pos


## Raycast dal petto al petto del bersaglio, SOLO contro il mondo (layer 1):
## se un tronco o un muro interrompe la linea, non c'e' tiro.
func _has_line_of_sight() -> bool:
	if not is_instance_valid(target):
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.4, 0)
	var to : Vector3 = target.global_position + Vector3(0, 1.2, 0)
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, [self])).is_empty()


## Punto di lancio in world-space: il BoneAttachment3D della mano se assegnato,
## altrimenti un punto davanti e sopra il petto.
func _muzzle_position() -> Vector3:
	if cast_origin != NodePath(""):
		var n := get_node_or_null(cast_origin) as Node3D
		if n:
			return n.global_position
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	return global_position + Vector3(0, 1.5, 0) + fwd * 0.6


## Lancia il proiettile con MIRA PREDITTIVA: punta dove sara' il player fra il
## tempo di volo, scalata da `projectile_lead` (0.5 = schivabile col dash a
## tempo, ma non camminando via). Il danno viaggia col proiettile.
func _fire_projectile(move : EnemyMove) -> void:
	if move.projectile_scene == null or not is_instance_valid(target):
		return
	var origin := _muzzle_position()
	var aim : Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var flight := origin.distance_to(aim) / maxf(move.projectile_speed, 0.1)
	aim += _target_vel * flight * move.projectile_lead
	# Property dinamiche (niente cast al tipo del proiettile) per non accoppiare
	# il nemico alla registrazione del class_name del proiettile in fase di parse.
	var proj := move.projectile_scene.instantiate() as Node3D
	if proj == null:
		return
	proj.set("direction", (aim - origin).normalized())
	proj.set("speed", move.projectile_speed)
	proj.set("move", move)
	proj.set("source", self)
	# Genitore = il livello, NON il nemico: il proiettile e' autonomo.
	get_parent().add_child(proj)
	proj.global_position = origin


## Inseguimento guidato dalla ROOT MOTION authorata delle clip walk/run: sono i
## piedi a decidere quanto si avanza, quindi niente foot-sliding. Fallback alla
## velocità di progetto se la clip non porta spostamento.
func _chase(delta : float, dist : float) -> void:
	_state = State.CHASE
	if not _has_engaged:
		_has_engaged = true
		engaged.emit()
	## ⚠️ Chi porta uno scudo NON CORRE. Non e' una taratura di velocita': e' che
	## un fante di linea con lo scudo alzato avanza, non carica — e a schermo la
	## differenza si legge subito, perche' una corsa con lo scudo davanti sembra
	## una fuga in avanti invece di una manovra. Il Fante Spadone, che lo scudo
	## non ce l'ha, continua a correre.
	var running := dist > run_distance and insegue_di_corsa
	_play(run_anim if running else walk_anim, true)
	if delta > 0.0 and _root_motion_delta.length() > 0.0001:
		var world_rm := global_transform.basis * _root_motion_delta
		velocity.x = world_rm.x / delta
		velocity.z = world_rm.z / delta
	else:
		var dir := _dir_di_marcia()
		var spd := run_speed if running else walk_speed
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd


## Durante un attacco l'avanzamento è quello AUTHORATO nella clip: il passo in
## avanti del fendente esiste nell'animazione, non lo aggiunge il codice.
func _attack_motion(delta : float) -> void:
	if _busy and delta > 0.0:
		var world_rm := global_transform.basis * _root_motion_delta
		velocity.x = world_rm.x / delta
		velocity.z = world_rm.z / delta
	else:
		velocity.x = 0.0
		velocity.z = 0.0


## La guardia alzata dimezza la spinta (vedi `spingi` nella base).
func _para() -> bool:
	return _trincerato


func _clear_move_state() -> void:
	# Anche una mossa abortita deve spegnere lo strato, o il colpo continuerebbe
	# a essere consegnato dal playhead di un gesto che non esiste piu'.
	_strato_attivo = ""
	super._clear_move_state()
	_armed_hitbox = null
	_window_from = -1.0
	_window_to = -1.0
	_finestre.clear()
	_close_weapon_window()


# ═══════════════════════════════════════════════════════════════════════════
# Timeline della mossa: finestra d'arma fisica, o istanti di contatto
# ═══════════════════════════════════════════════════════════════════════════

## La timeline è quella della superclasse (contatti dal playhead). Qui si arma
## in più la finestra dell'arma fisica, e lo si fa in `_begin_move` invece che
## in `_on_move_started` di proposito: quest'ultimo lo sovrascrivono le
## sottoclassi, e una che si dimenticasse di chiamare `super()` lascerebbe il
## nemico a menare con la lama spenta.
func _begin_move(move : EnemyMove) -> float:
	## ⚠️ L'ordine conta: `super._begin_move` chiama `_play(move.anim, ...)`, e
	## `_play` decide dove mandare la clip guardando `_strato_attivo`. Se lo si
	## impostasse dopo, il primo fotogramma dell'affondo finirebbe sul corpo —
	## cioe' proprio sulla guardia che non deve cadere.
	_strato_attivo = move.anim if _e_a_strato(move) else ""
	if _strato_attivo != "" and move.strato_radice != "":
		_rifiltra_strato(move.strato_radice)
	var clip_len := super._begin_move(move)
	_arm_weapon_window(move)
	return clip_len


## Vero se la mossa va suonata come strato e questo nemico ha l'albero per
## farlo. Il meccanismo non e' cablato sulla Testuggine: e' un flag sul DATO
## (`EnemyMove.strato`), quindi vale per il calcio di un altro nemico o per la
## botta di scudo di domani senza toccare una riga di qui.
func _e_a_strato(move : EnemyMove) -> bool:
	return move != null and move.strato and _albero != null


func _finish_move(move : EnemyMove) -> void:
	_strato_attivo = ""
	super._finish_move(move)


## Cambia al volo la catena filtrata dello strato, per una mossa che ne dichiara
## una sua: un calcio filtra dalla gamba, non dalla spalla.
func _rifiltra_strato(dal : String) -> void:
	var sk_rel := str(skeleton_path).trim_prefix("Model/")
	var sk := model.get_node_or_null(sk_rel) as Skeleton3D
	if sk == null or _albero == null:
		return
	var uno : AnimationNodeOneShot = _albero.tree_root.get_node(NODO_STRATO)
	uno.filters = []
	uno.filter_enabled = true
	for osso in _ossa_da(sk, dal):
		uno.set_filter_path(NodePath("%s:%s" % [sk_rel, osso]), true)


## Con un'arma fisica il danno NON lo decide la timeline: lo decide il contatto.
## Il contatto misurato resta comunque l'istante in cui il facing si blocca e in
## cui parte il rilascio (vedi `_advance_attack_timeline` nella superclasse), che
## è quello che serve al giocatore per temporizzare parata e schivata.
func _deliver_hit(move : EnemyMove) -> void:
	## Una mossa a distanza consegna un PROIETTILE al rilascio, non un colpo.
	if move.projectile_scene != null:
		_fire_projectile(move)
		return
	if _resolve_hitbox(move) != null:
		return
	super._deliver_hit(move)


# ═══════════════════════════════════════════════════════════════════════════
# Hitbox d'arma
# ═══════════════════════════════════════════════════════════════════════════

func _setup_hitboxes() -> void:
	for area in _all_hitboxes():
		area.monitoring = false
		if not area.body_entered.is_connected(_on_hitbox_body_entered):
			area.body_entered.connect(_on_hitbox_body_entered)
		for c in area.get_children():
			if c is CollisionShape3D and c.shape != null:
				_hitbox_shapes[area] = c
				break


func _all_hitboxes() -> Array:
	var out : Array = []
	if blade:
		out.append(blade)
	for np in extra_hitboxes:
		var a := get_node_or_null(np) as Area3D
		if a and not out.has(a):
			out.append(a)
	return out


## Quale hitbox usa QUESTA mossa. null = nessuna arma fisica → istanti di contatto.
func _resolve_hitbox(move : EnemyMove) -> Area3D:
	if not use_weapon_hitbox or not _move_uses_weapon(move):
		return null
	if move.hitbox != "":
		for a in _all_hitboxes():
			if a.name == move.hitbox:
				return a
		return null
	return blade


## Alcune mosse non colpiscono con l'arma: un proiettile viaggia da solo, e
## una scarica radiale la dichiara il boss.
func _move_uses_weapon(move : EnemyMove) -> bool:
	return move.projectile_scene == null


## Calcola QUANDO l'arma dovrà essere viva, in tempo-clip. Non la accende: ci
## pensa `_update_weapon_window()` quando il playhead entra nell'intervallo.
##
## Ordine di precedenza:
##  1. frazioni dichiarate sulla MOSSA — intenzione esplicita di chi l'ha
##     autorata, vince sempre;
##  2. finestra MISURATA dalla clip — il caso normale: l'arma è viva per l'arco
##     dello swing e basta;
##  3. frazioni globali — ripiego per le clip non ancora misurate.
func _arm_weapon_window(move : EnemyMove) -> void:
	_armed_hitbox = _resolve_hitbox(move)
	_window_from = -1.0
	_window_to = -1.0
	_finestre.clear()
	if _armed_hitbox == null:
		return
	var clip_native : float = _anim_len(move.anim)

	if move.blade_open_frac >= 0.0 or move.blade_close_frac >= 0.0:
		var fo : float = move.blade_open_frac if move.blade_open_frac >= 0.0 else blade_open_frac
		var fc : float = move.blade_close_frac if move.blade_close_frac >= 0.0 else blade_close_frac
		_finestre.append(Vector2(clip_native * fo, clip_native * fc))
	else:
		var lib := _timing()
		if lib:
			_finestre = lib.windows_for(move.anim, weapon_window_lead, weapon_window_trail)
		if _finestre.is_empty():
			_finestre.append(Vector2(clip_native * blade_open_frac, clip_native * blade_close_frac))
	## La prima finestra e' quella "corrente" finche' il playhead non ne entra
	## in un'altra (vedi `_update_weapon_window`).
	_window_from = _finestre[0].x
	_window_to = _finestre[0].y


## Apre e chiude l'arma seguendo il playhead. Chiamata ogni frame di fisica.
func _update_weapon_window() -> void:
	if _armed_hitbox == null or anim_player == null:
		return
	var attiva := false
	if _active_move != null and _clip_corrente() == _active_move.anim \
			and not _move_aborted():
		var pos : float = _clip_pos()
		## Dentro QUALE finestra sta il playhead: quella diventa la corrente.
		## Fra una finestra e la successiva `attiva` e' falso, la lama si chiude,
		## e alla successiva si riapre da zero (`_hit_done` torna falso).
		for w in _finestre:
			if pos >= w.x and pos <= w.y:
				_window_from = w.x
				_window_to = w.y
				attiva = true
				break
	if attiva and _active_hitbox == null:
		_open_weapon_window()
	elif not attiva and _active_hitbox != null:
		var chiusa := _hit_move
		_close_weapon_window()
		_on_weapon_window_closed(chiusa)


func _open_weapon_window() -> void:
	_hit_move = _active_move
	_active_hitbox = _armed_hitbox
	_active_shape = _hitbox_shapes.get(_armed_hitbox)
	_hit_done = false
	_has_prev = false
	_closest_approach = 9e9
	_active_hitbox.monitoring = true
	_on_weapon_window_opened(_hit_move)


func _close_weapon_window() -> void:
	if _active_hitbox and is_instance_valid(_active_hitbox):
		_active_hitbox.monitoring = false
	_active_hitbox = null
	_active_shape = null
	_hit_move = null

func _on_weapon_window_opened(_move : EnemyMove) -> void:
	pass

func _on_weapon_window_closed(_move : EnemyMove) -> void:
	pass


## Sonda CONTINUA dell'arma, un tick di fisica alla volta.
##
## `body_entered` da solo non basta: è campionato a passi discreti e la punta
## dell'arma si sposta di oltre un metro per tick, quindi scavalca il player
## senza mai sovrapporsi nell'istante in cui viene guardata (il classico "mi
## attraversa e non fa danno"). Qui si interpola la posa tra il tick precedente
## e quello corrente e si testa il box lungo TUTTO il tragitto: il colpo arriva
## se l'arma ha attraversato il player, non se per caso lo stava toccando
## proprio nell'istante del campionamento.
func _weapon_sweep() -> void:
	if _hit_move == null or _hit_done or _active_shape == null:
		return
	var cur : Transform3D = _active_shape.global_transform
	if not _has_prev:
		_prev_xform = cur
		_has_prev = true

	_track_closest(cur)
	_on_weapon_sweep_tick(_active_shape)

	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _active_shape.shape
	q.collision_mask = _active_hitbox.collision_mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var steps : int = maxi(blade_sweep_substeps, 1)
	for s in steps + 1:
		q.transform = _prev_xform.interpolate_with(cur, float(s) / float(steps))
		for r in space.intersect_shape(q, 4):
			var body = r.get("collider")
			if body and body.is_in_group("player") and body.has_method("hit"):
				_hit_done = true
				body.hit(self, _hit_move)
				_prev_xform = cur
				return
	_prev_xform = cur

	# BACKSTOP RAVVICINATO: gira insieme all'arma, ma solo DOPO che la hitbox
	# fisica ha già mancato questo tick (il colpo onesto ha la precedenza). A
	# corto raggio le clip del pack passano di lato, sempre di ~0.8 m: se sei
	# dentro l'arco frontale e abbastanza vicino, ti becca comunque.
	_close_range_backstop()

## Innesto per-tick sulla LAMA (il boss ci fa crescere il muro di fuoco). Passa
## la CollisionShape3D e non la sua posa: la punta si ricava dalle dimensioni
## della shape (vedi `BladeTrail.tip_of`), e una Transform3D da sola non le porta.
func _on_weapon_sweep_tick(_forma : CollisionShape3D) -> void:
	pass


func _close_range_backstop() -> void:
	if _hit_done or _hit_move == null or _hit_move.close_hit_range <= 0.0:
		return
	if not is_instance_valid(target) or not target.has_method("hit"):
		return
	# Solo nella parte IMPEGNATA dello swing: non nel windup, o il colpo
	# ravvicinato arriverebbe prima che l'arma scenda a schermo — e lascia alla
	# schivata a tempo lo spazio per uscire da raggio e arco prima che scatti.
	# La frazione si legge dal playhead, come tutto il resto della finestra.
	if anim_player == null or _window_to <= _window_from:
		return
	var frac : float = (_clip_pos() - _window_from) \
		/ (_window_to - _window_from)
	if frac < 0.40 or frac > 0.85:
		return
	var dist : float = _flat_distance(target)
	if dist > _hit_move.close_hit_range:
		return
	if dist >= 0.6:
		var fwd : Vector3 = global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		if fwd.dot(_flat_dir_to(target)) < cos(_hit_move.arc):
			return
	_hit_done = true
	target.hit(self, _hit_move)


## Rete: l'Area3D prende comunque i casi in cui il player ENTRA nell'arma ferma
## (es. ci cammina dentro), che la sonda coprirebbe solo di rimbalzo.
func _on_hitbox_body_entered(body : Node) -> void:
	if _hit_move == null or _hit_done:
		return
	if not body.is_in_group("player") or not body.has_method("hit"):
		return
	_hit_done = true
	body.hit(self, _hit_move)


## Quanto si è avvicinata l'arma al player in questo swing: è la misura che dice
## se un colpo mancato è colpa della mira o merito della schivata. Senza, resta
## un'opinione.
func _track_closest(cur : Transform3D) -> void:
	if not is_instance_valid(target):
		return
	var p0 : Vector3 = target.global_position
	var p1 : Vector3 = p0 + Vector3.UP * PLAYER_HEIGHT
	for k in 5:
		# punti lungo l'arma, nello spazio del box (alto lungo Y locale)
		var bp : Vector3 = cur * Vector3(0, lerpf(-0.495, 0.495, float(k) / 4.0), 0)
		var d : float = _dist_point_segment(bp, p0, p1)
		if d < _closest_approach:
			_closest_approach = d


func _dist_point_segment(p : Vector3, a : Vector3, b : Vector3) -> float:
	var ab : Vector3 = b - a
	var denom : float = ab.length_squared()
	if denom < 0.0001:
		return p.distance_to(a)
	var t : float = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ═══════════════════════════════════════════════════════════════════════════
# Poise-break (guardia rotta)
# ═══════════════════════════════════════════════════════════════════════════
## Il PoiseBreakEffect vive sullo StatusHost del nemico: ci si aggancia ai suoi
## segnali invece di interrogarlo ogni frame, così lo stagger scatta e finisce
## esattamente quando lo status lo dice (niente drift da polling).

func _connect_poise_break() -> void:
	if health_system == null or not ("status_host" in health_system):
		return
	var host := health_system.status_host as StatusHost
	if host == null:
		return
	var effect : StatusEffect = host.get_effect("poise_break")
	if effect:
		effect.applied.connect(_on_poise_break_applied)
		effect.expired.connect(_on_poise_break_expired)


func _on_poise_break_applied(_effect) -> void:
	if _state == State.DEAD or _state == State.VICTIM:
		# In VICTIM il finisher ha la precedenza visiva: lo status resta attivo
		# sullo StatusHost ma non interrompe la coppia victim/getup.
		return
	_state = State.STAGGERED
	_busy = false
	_clear_move_state()
	_play(poise_break_anim, false)


func _on_poise_break_expired(_effect) -> void:
	if _state == State.STAGGERED:
		_state = State.IDLE
		_play(idle_anim, true)


## Chiamato dal player quando para con successo (hook duck-typed in
## player_charbody3D.hit()). Rompe il poise ISTANTANEAMENTE, a prescindere dalla
## barra di build-up.
func parried() -> void:
	if health_system == null or not ("status_host" in health_system):
		return
	var host = health_system.status_host
	if host:
		host.break_poise_now()


# ═══════════════════════════════════════════════════════════════════════════
# Finisher subiti (backstab / riposte)
# ═══════════════════════════════════════════════════════════════════════════
## Chiamati dal player nell'istante in cui scatena il finisher: il nemico si
## congela nella coppia victim del pack (sincronizzata con la clip attacker) e
## si rialza con la getup.

## Interrogato dal player per non ri-triggerare un finisher su un bersaglio già
## a terra.
func is_finisher_victim() -> bool:
	return _state == State.VICTIM

func backstabbed(by : Node3D) -> void:
	_enter_victim(by, backstab_victim_anim, backstab_getup_anim)

func riposted(by : Node3D) -> void:
	_enter_victim(by, riposte_victim_anim, riposte_getup_anim)


func _enter_victim(by : Node3D, victim_anim : String, getup_anim : String) -> void:
	if _state == State.DEAD or _state == State.VICTIM:
		return   # niente finisher a catena su un bersaglio già a terra
	if is_instance_valid(by):
		target = by
	_state = State.VICTIM
	_busy = false            # abortisce la catena: i check post-await vedono VICTIM
	_snap_turn = false
	_hurt_lock = 0.0
	_clear_move_state()
	_victim_getup = getup_anim
	# Velocità assoluta 1.0: deve restare sincronizzata con la clip attacker del
	# player, non col tuning di difficoltà del nemico.
	_play(victim_anim, false, 1.0, 0.0)


## Finché il nemico è la vittima di un finisher, la sua clip è la METÀ di una
## coppia sincronizzata: l'altra metà la sta giocando il player. Morire nel mezzo
## fa sparire il bersaglio a gesto iniziato — il famoso calcio nel vuoto. La
## morte aspetta la fine della clip (vedi `_on_special_anim_finished`).
func _death_must_wait() -> bool:
	return _state == State.VICTIM


func _on_special_anim_finished(anim_name : StringName) -> bool:
	if _state == State.VICTIM:
		## Colpo mortale durante il finisher: niente rialzata, si muore ORA che
		## la clip è stata vista per intero.
		if _death_pending:
			_victim_getup = ""
			## La coda: si resta a terra ancora un momento, così la morte cade
			## dopo il calcio del player e non dentro.
			##
			## ⚠️ CON UN TIMER, NON CON UN `await` QUI DENTRO. Questa funzione è
			## VIRTUALE e viene chiamata in modo sincrono da
			## `arcanium_enemy._on_anim_finished`, che ne legge il valore di
			## ritorno per decidere se ha gestito la clip. Mettendoci un await
			## la funzione diventa una coroutine, il chiamante riceve un
			## GDScriptFunctionState invece di un bool e Godot lancia
			## «Trying to call an async function without await» — cioè il
			## crash al finisher.
			##
			## Il timer fa la stessa attesa senza cambiare la firma: si ritorna
			## `true` subito, e la morte arriva da sola quando scade.
			if finisher_coda > 0.0:
				var t := get_tree().create_timer(finisher_coda)
				t.timeout.connect(_finish_pending_death, CONNECT_ONE_SHOT)
				return true
			_finish_pending_death()
			return true
		if _victim_getup != "" and str(anim_name) != _victim_getup:
			_play(_victim_getup, false, 1.0, 0.0)   # victim → getup
		else:
			_victim_getup = ""
			_state = State.IDLE
			_next_attack = _now() + 0.8   # respiro dopo la rialzata
			_realign_to_mesh()
			if is_instance_valid(target):
				_face_instant()
			_play(idle_anim, true)
		return true

	if _state == State.STAGGERED:
		# Lo status dura più della clip one-shot: la ricicla in loop finché non
		# arriva `expired` dal PoiseBreakEffect.
		_play(poise_break_anim, true)
		return true

	return false


## Dopo una getup, caduta e giro di 180° sono vissuti nella POSA (la track di
## root motion sta sul bone `Root`, che è statico, quindi l'Hips non viene mai
## estratto). Il NODO invece è rimasto dov'era e girato di spalle: prima che
## l'idle resetti la posa, si porta il nodo sotto la mesh e lo si rigira.
## Senza, la rialzata "teletrasporta" indietro e il nemico resta di schiena.
func _realign_to_mesh() -> void:
	var sk := get_node_or_null(skeleton_path) as Skeleton3D
	if sk == null:
		return
	var hips_idx := sk.find_bone("Hips")
	if hips_idx < 0:
		return
	var hips_tf : Transform3D = sk.global_transform * sk.get_bone_global_pose(hips_idx)
	global_position.x = hips_tf.origin.x
	global_position.z = hips_tf.origin.z


# ═══════════════════════════════════════════════════════════════════════════
# Danno subito
# ═══════════════════════════════════════════════════════════════════════════

## Un colpo non interrompe una mossa in volo né la coppia victim di un finisher.
func _can_react_to_hit() -> bool:
	return not _busy and _state != State.VICTIM


# ═══════════════════════════════════════════════════════════════════════════
# La voce dei Consumati — i portatori dell'eco
# ═══════════════════════════════════════════════════════════════════════════
#
# Tutti i versi portano la FIRMA DELLA MAREA SORDA (l'eco innaturale), che e'
# cotta nei file: non e' un effetto applicato qui, e' cio' che quelle creature
# SONO. Vedi docs/09_AUDIO_SFX.md.

## ⚠️ L'annuncio si pesca a caso fra le indoli (saggio, belligerante, mago):
## i Consumati sono di ogni tipologia e casata, e sentirne tre diversi nella
## stessa radura e' il risultato voluto — non un difetto di coerenza.
func _voce_ingaggio() -> String:
	return Suoni.consumato_annuncio()

func _voce_colpito() -> String:
	return Suoni.CONSUMATO_COLPITO

func _voce_morte() -> String:
	return Suoni.consumato_morte()
