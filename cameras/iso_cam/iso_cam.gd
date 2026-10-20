extends Node3D
class_name IsoCam

## Rig di camera isometrica per Arcanium (sostituisce FollowCam/SpringArm3D
## di terza persona). Segue un target (di default il player), con zoom e
## rotazione azimutale regolabili da mouse/tastiera E dall'analogico destro
## del gamepad (target di prima classe).
##
## Parametri di partenza portati da Arcanium-Lite (Game.js / Constants.js):
## FOV 50, offset (0, 28, 22), follow lerp 0.08. Zoom = scalare il vettore
## offset senza cambiarne la direzione (l'angolo di vista resta identico).
##
## ⚠️ HOOK per la Fase 2 (decal-switching, NON implementata qui): "target"
## oggi punta sempre al player. Quando si implementerà il piazzamento
## posizionale (muro di fuoco / AoE / summon), basterà settare "target" sul
## decal mobile durante il piazzamento e ripristinarlo sul player alla fine.
## Nessun'altra modifica a questo script dovrebbe servire per quel caso d'uso.

# ---------------------------------------------------------------------------
# TARGET (hook Fase 2)
# ---------------------------------------------------------------------------

## Nodo-base che la camera segue: il player. NON viene sovrascritto dal focus
## temporaneo (vedi focus_target/release_focus) — è il punto a cui la camera
## RITORNA quando il focus viene rilasciato.
@export var target: Node3D

## Focus temporaneo (Fase 2): quando != null la camera segue QUESTO nodo invece
## del player, senza perdere il riferimento al player in "target". Pilotato da
## focus_target()/release_focus(), non assegnare a mano.
var _focus: Node3D = null

## Nodo effettivamente seguito questo frame: il focus se attivo, altrimenti il
## target di base. Tutto il follow/look_at passa da qui.
func _follow_node() -> Node3D:
	return _focus if _focus != null else target

## Camera3D effettiva pilotata da questo rig. Se non assegnata in editor,
## viene cercata come figlio diretto chiamato "Camera3D".
@export var camera_3d: Camera3D

# ---------------------------------------------------------------------------
# INQUADRATURA
# ---------------------------------------------------------------------------

## Offset base rispetto al target: è questo vettore a decidere l'ANGOLO di
## vista, non un campo "inclinazione".
##
## Era (0, 28, 22), ereditato da Lite: 51.8° sopra l'orizzonte, un volo d'angelo
## piuttosto ripido. Abbassato a 45° perché lo scontro si legga più "in faccia"
## restando isometrico dall'alto.
##
## ⚠️ La LUNGHEZZA del vettore è tenuta identica (35.61): è lei a decidere
## quanto lontana sta la camera, quindi cambiando solo l'angolo l'inquadratura
## non cambia scala e le tarature di zoom restano valide. Abbassare alzando la
## z e basta avrebbe allontanato la camera, facendo sembrare che fosse cambiato
## anche lo zoom.
##
## ⚠️ Un angolo più basso vede più PARETI: in una vista iso i soffitti non si
## mettono (vedi le convenzioni di rendering), ma i muri alti ora possono
## entrare fra camera e player. Da guardare nei livelli chiusi.
@export var offset: Vector3 = Vector3(0, 25.18, 25.18)

## FOV della camera in modalità prospettica.
@export_range(10.0, 90.0, 1.0) var fov: float = 50.0

## Se true, usa una Camera3D ortografica ("iso pura") invece che prospettica
## ad angolo ripido. L'utente vuole confrontare le due a schermo.
@export var use_orthogonal: bool = false

## Size della camera ortografica (usata solo se use_orthogonal == true).
## Scalata anch'essa dallo zoom, come l'offset prospettico.
@export_range(1.0, 100.0, 0.5) var orthogonal_size: float = 20.0

## Velocità di interpolazione del follow sulla posizione (0..1, per frame @ physics).
@export_range(0.01, 1.0, 0.01) var follow_lerp: float = 0.08

# ---------------------------------------------------------------------------
# ZOOM (scala il vettore offset, direzione invariata)
# ---------------------------------------------------------------------------

## Fattore di zoom di default (1.0 = offset/orthogonal_size "a grandezza naturale").
## Da 0.82 a 0.55 coi mini-dungeon (richiesta dell'autore, 2026-10-20: «bisogna
## essere piu' zoomati»): negli interni si gioca la stanza, non il panorama.
@export_range(0.1, 3.0, 0.01) var zoom_default: float = 0.55

## ⚠️ CAP conservativo di avvicinamento: resta molto più alto del minimo di Lite
## (0.15) apposta, per non mostrare le sfaldature del low-poly da vicino.
## Allargato da 0.45 a 0.36 su richiesta: un po' più di corsa verso il primo
## piano, senza arrivare dove la geometria si sfalda.
@export_range(0.1, 3.0, 0.01) var zoom_min: float = 0.36

## Massimo allontanamento consentito. Allargato da 1.15 a 1.40: serve respiro
## per leggere il campo di battaglia quando ci sono più evocazioni in campo.
##
## Da 1.40 a 2.10 per KALVORN: dal ballatoio a +30 m la foresta sotto non si
## leggeva — si vedevano i propri piedi e il vuoto, e metà del senso di stare in
## alto andava persa. Siccome il ballatoio è un ramo FACOLTATIVO, il panorama non
## è un contorno: è la ricompensa, e una ricompensa che non si vede non è tale.
##
## ⚠️ Questo cap è GLOBALE: cambia l'inquadratura massima anche al Crocevia,
## sulla Traccia Perduta e nell'Arena. Era la scelta consapevole fra questo e un
## preset di camera locale al ballatoio; se altrove il campo lungo dovesse
## risultare troppo largo, la strada è tornare a un volume con preset suo, non
## riabbassare questo numero e riperdere il panorama.
##
## Da 2.10 a 0.80 coi mini-dungeon (stessa richiesta: «non permettere di
## zoomare troppo indietro»). Il ballatoio di Kalvorn in Vaelthar non c'e'; se
## tornasse un panorama, gli serve il preset locale di cui sopra.
@export_range(0.1, 3.0, 0.01) var zoom_max: float = 0.80

## Incremento per ogni "scatto" di zoom (rotella mouse / pressione stick).
@export_range(0.01, 0.5, 0.01) var zoom_step: float = 0.08

## Velocità di smoothing dello zoom verso il target corrente (0..1 per physics frame).
@export_range(0.01, 1.0, 0.01) var zoom_smoothing: float = 0.15

## Sensibilità zoom dell'asse Y dello stick destro (moltiplica zoom_step/sec).
@export_range(0.1, 5.0, 0.1) var gamepad_zoom_sensitivity: float = 1.5

# ---------------------------------------------------------------------------
# ZOOM CINEMATICO: avvicinandosi la camera si ABBASSA e scopre l'alto
# ---------------------------------------------------------------------------
## Nello zoom CLASSICO l'offset viene solo scalato, quindi l'elevazione resta
## quella di `offset` a ogni distanza: ci si avvicina e si vedono le stesse cose
## più grandi. Va benissimo per leggere un campo di battaglia, e non mostra
## niente di nuovo.
##
## Nel CINEMATICO l'elevazione scende mentre ci si avvicina: la camera guarda
## più in orizzontale e nell'inquadratura entra ciò che sta in ALTO — le chiome,
## il ballatoio a +30, la volta di Kalvorn. È il modo di premiare chi si
## avvicina per guardare, invece di dargli solo un ingrandimento.
##
## ⚠️ La LUNGHEZZA del vettore resta quella di `offset`: si cambia l'ANGOLO e
## nient'altro. È la stessa disciplina del cappello di `offset` — cambiare la
## lunghezza qui vorrebbe dire cambiare la distanza, e sembrerebbe che lo zoom
## sia impazzito. La scala la decide `_zoom_current`, che moltiplica dopo.
##
## ⚠️ E un angolo più basso vede più PARETI: nei livelli chiusi può entrare
## geometria fra camera e player. La IsoCam dissolve gli occlusori ma si ferma a
## sei — per questo il cinematico è una SCELTA del giocatore, non il default.

## Elevazione (gradi sopra l'orizzonte) al massimo allontanamento. A -1 usa
## quella di `offset`, così il campo lungo resta identico al classico e le due
## modalità si distinguono solo avvicinandosi.
@export_range(-1.0, 89.0, 0.5) var elevazione_lontano: float = -1.0

## Elevazione al massimo avvicinamento. 26° contro i 45° di `offset`: quasi venti
## gradi di campo guadagnati verso il cielo.
@export_range(5.0, 89.0, 0.5) var elevazione_vicino: float = 26.0

## Alza il punto guardato mentre ci si avvicina, in metri, al massimo
## avvicinamento. Sposta l'inquadratura verso l'alto ANCHE a parità di angolo:
## serve perché abbassando la camera il player tende a salire nel fotogramma, e
## questo lo rimette al suo posto lasciando il cielo sopra.
@export_range(0.0, 4.0, 0.1) var mira_alta_vicino: float = 1.1

var _zoom_target: float = 1.0
var _zoom_current: float = 1.0

# ---------------------------------------------------------------------------
# ROTAZIONE AZIMUTALE (feature NUOVA rispetto a Lite: orbita attorno al target
# mantenendo l'elevazione iso)
# ---------------------------------------------------------------------------

## Velocità di rotazione, in gradi/secondo, per tastiera (Q/E) e per la
## pressione massima dello stick destro (asse X).
@export_range(10.0, 360.0, 5.0) var rotation_speed_deg: float = 90.0

## Se true, limita la rotazione azimutale entro [rotation_min_deg, rotation_max_deg]
## invece di permettere un giro completo a 360°.
@export var clamp_rotation: bool = false
@export_range(-180.0, 180.0, 1.0) var rotation_min_deg: float = -60.0
@export_range(-180.0, 180.0, 1.0) var rotation_max_deg: float = 60.0

var _azimuth_deg: float = 0.0

# ---------------------------------------------------------------------------
# ALLINEAMENTO IN LOCK-ON
# ---------------------------------------------------------------------------
#
# Fuori lock la camera si gira a piacimento. AGGANCIATI invece si comporta come
# in un soulslike canonico: si mette IN LINEA dietro al player rispetto al
# nemico, e lo insegue mentre gli si orbita intorno. Senza, ruotando attorno al
# bersaglio ci si ritrova a guardare lo scontro di sbieco o di lato, e capire
# dove si sta andando diventa un lavoro mentale.
#
# Il player non lo conosce nessuno qui: si chiede al nodo seguito, se sa
# rispondere (`lock_on_target`), esattamente come per `focus_target`.

## Se false, l'allineamento non avviene e la rotazione resta manuale anche
## agganciati.
@export var align_to_lock: bool = true

## Velocità MASSIMA di riallineamento, gradi/secondo. Fa da tetto: la camera si
## avvicina in modo esponenziale (vedi `lock_align_smoothing`) ma non scatta mai
## più veloce di così, o orbitando stretti attorno al nemico dà la nausea.
@export_range(10.0, 720.0, 5.0) var lock_align_speed_deg: float = 150.0

## Quota dello scarto recuperata a ogni physics frame (0..1): governa la
## morbidezza dell'inseguimento.
@export_range(0.01, 1.0, 0.01) var lock_align_smoothing: float = 0.08

# ---------------------------------------------------------------------------
# GAMEPAD (analogico destro = zoom + rotazione, prima classe)
# ---------------------------------------------------------------------------

## Deadzone applicata allo stick destro, oltre a quella già impostata
## sull'InputMap (difesa extra contro drift dello stick).
@export_range(0.0, 0.9, 0.01) var stick_deadzone: float = 0.2


func _ready() -> void:
	if camera_3d == null:
		camera_3d = get_node_or_null("Camera3D")
	if target == null:
		# Fallback: se non assegnato in editor, cerca un CharacterBody3D nel
		# gruppo "player" nella scena (stesso pattern di FollowCam).
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]

	_zoom_target = zoom_default
	_zoom_current = zoom_default

	if camera_3d:
		camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL if use_orthogonal else Camera3D.PROJECTION_PERSPECTIVE
		camera_3d.fov = fov
		camera_3d.size = orthogonal_size
		camera_3d.current = true

	# Posiziona subito la camera senza attendere il primo lerp (evita lo
	# "scivolamento" visibile al caricamento della scena).
	var follow := _follow_node()
	if follow:
		global_position = follow.global_position + _current_offset()
		if camera_3d:
			camera_3d.look_at(follow.global_position + Vector3.UP * _mira_alta(), Vector3.UP)


func _physics_process(delta: float) -> void:
	_process_zoom_input(delta)
	_process_rotation_input(delta)
	_follow_target(delta)
	_process_occlusioni(delta)


# ---------------------------------------------------------------------------
# OCCLUSIONI — convenzione isometrica: quello che ti copre si dissolve
# ---------------------------------------------------------------------------
#
# In una vista dall'alto i soffitti non si mettono (vedi le convenzioni di
# rendering), ma i MURI restano: abbassando il volo d'angelo a 45° una parete
# alta può infilarsi fra camera e player, e in un soulslike perdere di vista il
# personaggio durante uno scambio non è un fastidio estetico, è un colpo preso.
#
# Si tira un raggio dalla camera al player e tutto ciò che lo taglia sfuma. Non
# appena non dà più fastidio torna com'era, alla stessa velocità.

## Se false, niente dissolvenza (utile per capire se un buco visivo è colpa di
## questo sistema o della geometria).
@export var fade_occluders: bool = true

## Su quali layer cercare gli ostacoli. Di default "World": il player e i
## bersagli non devono dissolversi mai.
@export_flags_3d_physics var occluder_mask: int = 1

## DISSOLVENZA sfuma la mesh; NASCONDI la toglie e basta.
## ⚠️ `GeometryInstance3D.transparency` è garantito su Forward+ e Mobile ma NON
## su Compatibility, e questo progetto gira su **mobile** (vedi i vincoli
## shader/VFX). Se la dissolvenza non si vedesse, questa è la leva: NASCONDI
## funziona ovunque perché non tocca i materiali.
enum ModoOcclusione { DISSOLVENZA, NASCONDI }
@export var occluder_mode: ModoOcclusione = ModoOcclusione.DISSOLVENZA

## Quanto diventa trasparente un ostacolo: 1.0 sarebbe invisibile, ma lasciarne
## un velo aiuta a capire che LÌ C'È UN MURO — sparire del tutto fa sembrare che
## il livello abbia un buco, e ci si va a sbattere.
@export_range(0.0, 1.0, 0.05) var occluder_transparency: float = 0.78

## Velocità della dissolvenza, in unità di trasparenza al secondo. Volutamente
## rapida: deve essere già finita quando il muro ti passa davanti.
@export_range(0.5, 20.0, 0.5) var occluder_fade_speed: float = 8.0

## Quanti ostacoli in fila si attraversano al massimo (muro + colonna + arco…).
@export_range(1, 12, 1) var occluder_max_hits: int = 6

## Se un ostacolo appartiene a un prop composto (muro + decorazioni), mettere il
## suo nodo radice in questo gruppo dissolve TUTTO il prop insieme invece del
## solo pezzo colpito, che altrimenti si buca a metà.
@export var occluder_root_group: String = "occluder_root"

## Radice del prop → { "mesh": Array[GeometryInstance3D], "alfa": float,
## "originali": Array[float], "attivo": bool }
var _occlusi: Dictionary = {}


func _process_occlusioni(delta: float) -> void:
	if not fade_occluders:
		if not _occlusi.is_empty():
			_ripristina_tutti()
		return
	var follow := _follow_node()
	if follow == null or camera_3d == null:
		return

	for dati in _occlusi.values():
		dati["attivo"] = false
	for radice in _trova_occlusori(follow):
		if not _occlusi.has(radice):
			_occlusi[radice] = _schedina(radice)
		_occlusi[radice]["attivo"] = true

	var passo := occluder_fade_speed * delta
	for radice in _occlusi.keys():
		var dati : Dictionary = _occlusi[radice]
		var bersaglio : float = occluder_transparency if dati["attivo"] else 0.0
		dati["alfa"] = move_toward(dati["alfa"], bersaglio, passo)
		_applica_alfa(dati)
		## si smette di seguirlo solo quando è tornato ESATTAMENTE com'era:
		## dimenticarselo a metà dissolvenza lo lascerebbe semitrasparente per
		## sempre, e sarebbe un difetto che nessuno riesce a riprodurre
		if not dati["attivo"] and is_zero_approx(dati["alfa"]):
			_occlusi.erase(radice)


## Radici dei prop che tagliano il raggio camera → player. Si ripete il raggio
## escludendo ogni volta ciò che si è già colpito: un solo `intersect_ray`
## troverebbe la PRIMA parete e si fermerebbe lì, lasciando opache tutte quelle
## dietro.
func _trova_occlusori(follow: Node3D) -> Array:
	var mondo := get_world_3d()
	if mondo == null:
		return []
	var spazio := mondo.direct_space_state
	if spazio == null:
		return []
	## si punta al petto, non ai piedi: al suolo qualunque gradino taglierebbe
	var da := camera_3d.global_position
	var a : Vector3 = follow.global_position + Vector3.UP
	var escludi : Array[RID] = []
	if follow is CollisionObject3D:
		escludi.append((follow as CollisionObject3D).get_rid())
	var radici := []
	for _i in occluder_max_hits:
		var q := PhysicsRayQueryParameters3D.create(da, a, occluder_mask, escludi)
		var colpo := spazio.intersect_ray(q)
		if colpo.is_empty():
			break
		escludi.append(colpo["rid"])
		var radice := _radice_prop(colpo["collider"])
		if radice != null and not radici.has(radice):
			radici.append(radice)
	return radici


## Il pezzo colpito è un corpo di collisione; la mesh da sfumare sta di solito
## accanto o sopra. Si sale al nodo marcato come radice del prop, se c'è.
func _radice_prop(collider) -> Node:
	if collider is not Node:
		return null
	var n : Node = collider
	while n != null:
		if n.is_in_group(occluder_root_group):
			return n
		n = n.get_parent()
	## nessun marcatore: si sfuma il corpo colpito e ciò che ci sta dentro
	return collider


func _schedina(radice: Node) -> Dictionary:
	var mesh : Array = []
	var originali : Array = []
	if radice is GeometryInstance3D:
		mesh.append(radice)
	for n in radice.find_children("*", "GeometryInstance3D", true, false):
		mesh.append(n)
	for m in mesh:
		originali.append((m as GeometryInstance3D).transparency)
	return {"mesh": mesh, "originali": originali, "alfa": 0.0, "attivo": true}


func _applica_alfa(dati: Dictionary) -> void:
	var mesh : Array = dati["mesh"]
	var originali : Array = dati["originali"]
	var alfa : float = dati["alfa"]
	for i in mesh.size():
		var m = mesh[i]
		if not is_instance_valid(m):
			continue
		var gi := m as GeometryInstance3D
		if occluder_mode == ModoOcclusione.NASCONDI:
			## niente mezze misure: o c'è o non c'è, e la soglia sta a metà
			## dissolvenza così la comparsa non lampeggia sul filo
			gi.visible = alfa < occluder_transparency * 0.5
			continue
		gi.visible = true
		## si PARTE dal valore che il prop aveva già: c'è chi nasce
		## semitrasparente (drappi, vetri), e riportarlo a 0 lo renderebbe opaco
		var base : float = originali[i]
		gi.transparency = maxf(base, alfa)


func _ripristina_tutti() -> void:
	for dati in _occlusi.values():
		dati["alfa"] = 0.0
		_applica_alfa(dati)
	_occlusi.clear()


# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------

func _process_zoom_input(delta: float) -> void:
	# Tastiera/mouse: cam_zoom_in / cam_zoom_out sono azioni "a scatto"
	# (rotella mouse), quindi usiamo just_pressed per un incremento discreto.
	if Input.is_action_just_pressed("cam_zoom_in"):
		_zoom_target -= zoom_step
	if Input.is_action_just_pressed("cam_zoom_out"):
		_zoom_target += zoom_step

	# Gamepad: asse Y dello stick destro = zoom continuo, con deadzone.
	var gamepad_zoom_axis := Input.get_axis("cam_zoom_in", "cam_zoom_out")
	if abs(gamepad_zoom_axis) > stick_deadzone:
		_zoom_target += gamepad_zoom_axis * gamepad_zoom_sensitivity * zoom_step * delta * 10.0

	_zoom_target = clamp(_zoom_target, zoom_min, zoom_max)
	_zoom_current = lerp(_zoom_current, _zoom_target, zoom_smoothing)


func _process_rotation_input(delta: float) -> void:
	# Agganciati comanda il bersaglio, non i tasti di rotazione: la camera si
	# rimette in linea da sola. (Q/E tornano a funzionare appena si sgancia.)
	if _align_to_lock(delta):
		return

	# Tastiera (Q/E) + gamepad (asse X stick destro), unificati via get_axis
	# con deadzone applicata sia dall'InputMap sia qui (difesa extra).
	var rotate_axis := Input.get_axis("cam_rotate_left", "cam_rotate_right")
	if abs(rotate_axis) <= stick_deadzone:
		rotate_axis = 0.0

	if rotate_axis != 0.0:
		_azimuth_deg += rotate_axis * rotation_speed_deg * delta
		if clamp_rotation:
			_azimuth_deg = clamp(_azimuth_deg, rotation_min_deg, rotation_max_deg)
		else:
			_azimuth_deg = wrapf(_azimuth_deg, -180.0, 180.0)


## Porta l'azimut dietro al player rispetto al bersaglio agganciato. Ritorna
## true se ha preso il comando (cioè: c'è un aggancio), così il chiamante sa che
## la rotazione manuale è sospesa.
func _align_to_lock(delta: float) -> bool:
	if not align_to_lock:
		return false
	## Lo STILE lo sceglie il giocatore dalle opzioni: dritta (soulslike),
	## obliqua (Diablo), di lato (2.5D) o "non inseguire". Il primo è il default;
	## l'ultimo restituisce false, così Q/E tornano a comandare anche agganciati.
	var stile := 0.0
	var prefs := get_node_or_null("/root/GameSettings")
	if prefs:
		if not prefs.insegue():
			return false
		stile = prefs.angolo_lock()
	var sorgente := target
	if sorgente == null or not sorgente.has_method("lock_on_target"):
		return false
	var nemico = sorgente.lock_on_target()
	if nemico == null:
		return false
	var verso: Vector3 = nemico.global_position - sorgente.global_position
	verso.y = 0.0
	## addosso al nemico la direzione degenera e l'azimut impazzirebbe
	if verso.length_squared() < 0.04:
		return true

	## L'offset base mette la camera a +Z rispetto al seguito, quindi guarda
	## verso −Z. Ruotato di `a`, il suo orizzontale vale (sin a, cos a): perché
	## la camera stia DIETRO al player rispetto al nemico serve che punti come
	## −verso, da cui l'azimut qui sotto. (Ricavarlo dall'offset invece di
	## scriverlo a mano tiene insieme le due cose se un domani l'offset cambia.)
	var desiderato := rad_to_deg(atan2(-verso.x, -verso.z)) + stile
	var piatto := Vector2(offset.x, offset.z)
	if piatto.length_squared() > 0.000001:
		desiderato -= rad_to_deg(atan2(piatto.x, piatto.y))

	var scarto := wrapf(desiderato - _azimuth_deg, -180.0, 180.0)
	var passo := scarto * lock_align_smoothing
	var tetto := lock_align_speed_deg * delta
	passo = clampf(passo, -tetto, tetto)
	_azimuth_deg = wrapf(_azimuth_deg + passo, -180.0, 180.0)
	return true


func _follow_target(delta: float) -> void:
	var follow := _follow_node()
	if follow == null:
		return

	var desired_position: Vector3 = follow.global_position + _current_offset()
	global_position = lerp(global_position, desired_position, follow_lerp)

	if camera_3d:
		camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL if use_orthogonal else Camera3D.PROJECTION_PERSPECTIVE
		camera_3d.fov = fov
		camera_3d.size = orthogonal_size * _zoom_current
		camera_3d.look_at(follow.global_position + Vector3.UP * _mira_alta(), Vector3.UP)
		_applica_scossa(delta, follow)


# ---------------------------------------------------------------------------
# SCOSSA (screen shake)
# ---------------------------------------------------------------------------
#
# Lo STATO della scossa non vive qui: sta in `Scossa` (arcanium/systems/vfx/
# scossa.gd), che chiunque può alimentare senza cercare la camera nell'albero.
# Qui c'è solo l'applicazione, ed è l'unico posto che poteva ospitarla.

## Se false, la camera ignora la scossa (per isolare un difetto: serve a capire
## se un tremore viene da qui o da un'animazione).
@export var scossa_attiva : bool = true

## Applica la scossa del frame.
##
## ⚠️ DEVE girare DOPO `look_at`, ed è tutto il motivo per cui questa funzione
## esiste invece di due righe sparse. `look_at` RISCRIVE la rotazione della
## camera da zero ogni frame: qualunque rotazione aggiunta prima viene buttata
## via, e il risultato è una scossa che trasla e non ruota — cioè metà effetto,
## con l'aria di un bug intermittente.
##
## ⚠️ E lo spostamento si somma in GLOBALE, dopo che il rig si è posizionato: il
## rig insegue il target con un lerp, quindi scrivergli dentro l'offset lo
## farebbe rincorrere e la scossa si trascinerebbe dietro una deriva.
func _applica_scossa(delta : float, follow : Node3D) -> void:
	## L'ascoltatore è il PLAYER, non la camera (vedi la nota in Scossa): serve
	## anche quando non c'è nessuna scossa in corso, perché un evento che nasce
	## nel frame successivo deve trovare una posizione già aggiornata.
	Scossa._ascoltatore = follow.global_position
	if not scossa_attiva:
		return
	if not Scossa.attiva():
		return
	var s : Array = Scossa.consuma(delta)
	var sp : Vector3 = s[0]
	var rot : Vector3 = s[1]
	camera_3d.global_position += sp
	camera_3d.rotate_object_local(Vector3.RIGHT, deg_to_rad(rot.x))
	camera_3d.rotate_object_local(Vector3.UP, deg_to_rad(rot.y))
	camera_3d.rotate_object_local(Vector3.FORWARD, deg_to_rad(rot.z))


## Offset corrente: offset base ruotato attorno a Y (rotazione azimutale) e
## poi scalato dal fattore di zoom (la direzione della vista resta identica
## ad ogni zoom, come in Lite: si scala il vettore, non l'angolo).
func _current_offset() -> Vector3:
	var base := _offset_inclinato() if _cinematico() else offset
	var rotated := base.rotated(Vector3.UP, deg_to_rad(_azimuth_deg))
	return rotated * _zoom_current


## La modalità la sceglie il giocatore dalle opzioni. Senza l'autoload (banchi di
## prova, scene isolate) si resta al classico: un banco che si comporta diverso
## dal gioco mente, e il default deve essere ciò che c'è sempre stato.
func _cinematico() -> bool:
	var prefs := get_node_or_null("/root/GameSettings")
	return prefs != null and prefs.has_method("zoom_cinematico") and prefs.zoom_cinematico()


## Quanto siamo "vicini": 0 al massimo avvicinamento, 1 al massimo allontanamento.
## È la sola grandezza da cui dipendono l'angolo e la mira alta.
func _t_distanza() -> float:
	if zoom_max - zoom_min < 0.0001:
		return 1.0
	return clampf((_zoom_current - zoom_min) / (zoom_max - zoom_min), 0.0, 1.0)


## `offset` con l'elevazione interpolata e la LUNGHEZZA INTATTA.
##
## Si ricostruisce dal piano orizzontale di `offset` invece di scrivere una
## direzione a mano: se un domani l'offset base cambia azimut o proporzioni, il
## cinematico lo segue da sé.
func _offset_inclinato() -> Vector3:
	var lung := offset.length()
	if lung < 0.0001:
		return offset
	var piatto := Vector2(offset.x, offset.z)
	if piatto.length_squared() < 0.000001:
		piatto = Vector2(0.0, 1.0)
	piatto = piatto.normalized()

	var lontano := elevazione_lontano
	if lontano < 0.0:
		## −1 = "come l'offset": si ricava, non si ricopia.
		lontano = rad_to_deg(atan2(offset.y, Vector2(offset.x, offset.z).length()))

	var elev := deg_to_rad(lerpf(elevazione_vicino, lontano, _t_distanza()))
	var raggio := lung * cos(elev)
	return Vector3(piatto.x * raggio, lung * sin(elev), piatto.y * raggio)


## Di quanto si alza il punto guardato. Zero nel classico e a campo lungo.
func _mira_alta() -> float:
	if not _cinematico():
		return 0.0
	return lerpf(mira_alta_vicino, 0.0, _t_distanza())


# ---------------------------------------------------------------------------
# API PUBBLICA DI FOCUS (Fase 2: casting posizionale / AoE / summon)
# ---------------------------------------------------------------------------
#
# Il sistema di piazzamento posizionale (quando esisterà — oggi in Godot ci sono
# solo spell a proiettile, vedi spell_caster.gd) chiama focus_target(decal)
# all'inizio del piazzamento e release_focus() alla conferma/annullamento. La
# camera si sposta sul decal col normale follow_lerp e vi ritorna sul player,
# senza che il chiamante debba conoscere i dettagli del rig. "target" (il player)
# NON viene mai perso: il focus è uno strato temporaneo sopra.

## Aggancia temporaneamente la camera a `node` (es. il decal mobile di un muro
## di fuoco). Passare null equivale a release_focus().
func focus_target(node: Node3D) -> void:
	_focus = node

## Rilascia il focus: la camera torna a seguire il player (`target`).
func release_focus() -> void:
	_focus = null

## True se un focus temporaneo è attivo (la camera NON sta seguendo il player).
func has_focus() -> bool:
	return _focus != null
