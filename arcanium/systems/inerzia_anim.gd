@tool
extends SkeletonModifier3D

## ═══════════════════════════════════════════════════════════════════════════
## INERZIA — il passaggio fra due clip come SMORZAMENTO, non come dissolvenza
## ═══════════════════════════════════════════════════════════════════════════
##
## Una dissolvenza mescola due animazioni: per un decimo di secondo il corpo è
## la media di due gesti. Qui invece la clip nuova parte SUBITO a peso pieno, e
## quello che si smorza è lo SCARTO fra la posa vecchia e la nuova — un offset
## per osso, che parte esattamente uguale alla differenza e va a zero da solo.
##
## È l'inertialization presentata da David Bollo alla GDC 2018 per Gears of War 4
## (SIGGRAPH 2017, «High performance animation in Gears of War 4»).
##
## ─── Perché non basta allungare la dissolvenza ──────────────────────────────
## Misurato su questo Fante (`arcanium/tools/misura_slittamento.gd`): allungare
## o addolcire la dissolvenza **abbassa lo scatto della posa ma alza lo
## slittamento dei piedi**. È un baratto, non un miglioramento — e ha una causa
## fisica precisa. Mentre due cicli di passo si mescolano, il piede a terra è la
## media di due piedi che stanno in due punti diversi: più a lungo dura la
## media, più il piede striscia. La dissolvenza non può vincere su entrambi i
## fronti perché il difetto È la media.
##
## Qui la media non esiste mai. In ogni istante il corpo suona UNA clip sola, al
## cento per cento, quindi il piede sta dove l'animatore l'ha messo. Sopra ci
## viene sommata una rotazione per osso che all'inizio vale esattamente la
## differenza fra le due pose — così il primo fotogramma è identico a prima del
## passaggio, e non c'è nessun salto — e che poi si spegne.
##
## ─── Perché una QUINTICA e non una sfumatura qualsiasi ──────────────────────
## Perché lo scarto deve andare a zero portandosi dietro anche la sua VELOCITÀ.
## Una sfumatura semplice azzera la differenza di posa ma non quella di
## velocità: l'occhio vede la posa arrivare a destinazione e fermarsi di colpo.
## La quintica impone sei condizioni — posa, velocità e accelerazione dello
## scarto all'inizio e alla fine.
##
## Con `v0 = 0` la formula si riduce a `x0 · (1 − smootherstep)`, che è insieme
## la controprova che i coefficienti sono giusti e — misurato — il modo che su
## queste clip rende di più: vedi `usa_velocita_iniziale`.
##
## ⚠️ SI AGGANCIA ALLA POSA CHE ESCE, non a quella che entra. `_q_prec` conserva
## ciò che questo modificatore ha PRODOTTO, non ciò che gli ha passato l'albero.
## Senza, due passaggi ravvicinati (fendente interrotto da un colpo subito) si
## calcolerebbero il secondo scarto da una posa che a schermo non c'è mai stata,
## e il secondo smorzamento partirebbe con uno strappo.
##
## ⚠️ IL `Root` RESTA FUORI. Da lì passa la root motion, che l'AnimationMixer ha
## già estratto e consegnato al CharacterBody: sommarci una rotazione che si
## spegne vorrebbe dire far curvare il personaggio a ogni cambio di clip.
##
## ⚠️ NON si misura con `get_bone_global_pose()` da fuori: quella chiamata
## restituisce la posa dell'ANIMAZIONE, non quella che esce dai modificatori
## (stessa trappola documentata in `ik_piedi.gd`). Per questo il modificatore
## pubblica `posa_finale`, che è ciò che ha davvero scritto.

## Quanto dura lo smorzamento. Sotto i 0,15 s si vede ancora lo stacco, sopra i
## 0,35 il corpo sembra molleggiare — è la stessa finestra delle dissolvenze che
## sostituisce.
@export_range(0.05, 0.8, 0.01) var durata : float = 0.25
## Ossa che non si toccano. `Root` porta la root motion.
@export var ossa_escluse : PackedStringArray = ["Root"]
## Oltre questo scarto il passaggio non è un passaggio, è un altro personaggio:
## smorzare 170 gradi di differenza produce una rotazione lenta e innaturale che
## si vede più del salto che doveva nascondere. Sopra la soglia si lascia
## passare lo stacco secco.
@export_range(10.0, 180.0) var scarto_massimo_gradi : float = 150.0
## Se vero, lo smorzamento si aggancia alla VELOCITA' con cui lo scarto si stava
## gia' muovendo (la `v0` di Bollo); se falso si spegne con una smootherstep
## pura.
##
## ⚠️ E' PREDEFINITO A FALSO, contro il testo originale, perche' su queste clip
## la misura dice il contrario della teoria:
##
##                    slittamento   peggior fot.   scatto (picco)
##   con v0             4,10 cm/m      5,66 cm      3,29 gradi
##   senza v0           2,96 cm/m      4,18 cm      4,20 gradi
##   (dissolvenza)      7,51 cm/m      2,98 cm      5,73 gradi
##
## Agganciarsi a `v0` continua il gesto vecchio ancora un istante, e quell'istante
## porta il piede piu' lontano da dove la clip nuova lo vuole. Si guadagna sulla
## continuita' della posa e si perde sull'appoggio. Senza `v0` si vince meno
## sullo scatto (-27% invece di -43%) e molto di piu' sullo slittamento
## (-61% invece di -45%): per un personaggio che cammina in giro, l'appoggio
## conta di piu'.
##
## Resta acceso qui perche' su un rig con gesti piu' ampi — o su clip autorate
## con piu' cura al passaggio — il baratto puo' girare dall'altra parte. Si
## rimisura, non si indovina.
@export var usa_velocita_iniziale : bool = false
## Diagnostica: quante volte e' stato chiamato, e il massimo scarto applicato.
var chiamate : int = 0
var scarto_massimo_applicato : float = 0.0
var velocita_massima : float = 0.0

## Quello che il modificatore ha scritto, osso per osso: l'unico modo di sapere
## da fuori che cosa si è visto davvero.
var posa_finale : Array[Quaternion] = []

var _q_prec : Array[Quaternion] = []
var _q_prec2 : Array[Quaternion] = []
var _asse : PackedVector3Array = PackedVector3Array()
var _x0 : PackedFloat32Array = PackedFloat32Array()
var _v0 : PackedFloat32Array = PackedFloat32Array()
var _t1 : PackedFloat32Array = PackedFloat32Array()
var _t : float = 0.0
var _attiva : bool = false
var _cattura : bool = false
var _escluse : Dictionary = {}
var _n : int = 0


## Chiamata quando parte una clip nuova. Non cattura niente adesso: la posa
## nuova non esiste ancora, l'albero non ha ancora girato. Si segna soltanto che
## al prossimo giro dello scheletro c'è uno scarto da prendere.
func avvia() -> void:
	_cattura = true


func _prepara(sk : Skeleton3D) -> void:
	_n = sk.get_bone_count()
	_q_prec.resize(_n)
	_q_prec2.resize(_n)
	_asse.resize(_n)
	_x0.resize(_n)
	_v0.resize(_n)
	_t1.resize(_n)
	posa_finale.resize(_n)
	_escluse.clear()
	for nome in ossa_escluse:
		var i := sk.find_bone(str(nome))
		if i >= 0:
			_escluse[i] = true
	for i in _n:
		_q_prec[i] = sk.get_bone_pose_rotation(i)
		_q_prec2[i] = _q_prec[i]
		posa_finale[i] = _q_prec[i]


func _process_modification_with_delta(delta : float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _n != sk.get_bone_count():
		_prepara(sk)
	if delta <= 0.0:
		return
	chiamate += 1

	if _cattura:
		_cattura = false
		_prendi_scarto(sk, delta)

	if _attiva:
		_t += delta
		var vivo := false
		for i in _n:
			if _escluse.has(i) or _t1[i] <= 0.0:
				continue
			if _t >= _t1[i]:
				continue
			vivo = true
			var x := _scarto_al_tempo(i, _t) * influence
			scarto_massimo_applicato = maxf(scarto_massimo_applicato, absf(x))
			if absf(x) < 0.00001:
				continue
			var q : Quaternion = sk.get_bone_pose_rotation(i)
			sk.set_bone_pose_rotation(i, (Quaternion(_asse[i], x) * q).normalized())
		if not vivo:
			_attiva = false

	## La memoria si tiene su ciò che è USCITO, non su ciò che è entrato.
	for i in _n:
		_q_prec2[i] = _q_prec[i]
		_q_prec[i] = sk.get_bone_pose_rotation(i)
		posa_finale[i] = _q_prec[i]


## Fotografa lo scarto fra la posa di ieri e quella di oggi, e la velocità con
## cui quello scarto si stava già muovendo.
func _prendi_scarto(sk : Skeleton3D, delta : float) -> void:
	var limite := deg_to_rad(scarto_massimo_gradi)
	var qualcosa := false
	for i in _n:
		_t1[i] = 0.0
		if _escluse.has(i):
			continue
		var nuova : Quaternion = sk.get_bone_pose_rotation(i)
		var inv := nuova.inverse()
		var d : Quaternion = (_q_prec[i] * inv).normalized()
		if d.w < 0.0:
			d = Quaternion(-d.x, -d.y, -d.z, -d.w)   # arco corto
		var v := Vector3(d.x, d.y, d.z)
		var sn := v.length()
		if sn < 0.000001:
			continue                                  # osso fermo: niente da smorzare
		var asse := v / sn
		var x0 := 2.0 * atan2(sn, d.w)
		if x0 > limite:
			continue
		# La stessa differenza un fotogramma prima, misurata sullo STESSO asse:
		# così `x0 - x_1` è una velocità con il segno giusto.
		var d1 : Quaternion = (_q_prec2[i] * inv).normalized()
		var x_1 := 2.0 * atan2(Vector3(d1.x, d1.y, d1.z).dot(asse), d1.w)
		var v0 := (x0 - x_1) / delta if usa_velocita_iniziale else 0.0
		velocita_massima = maxf(velocita_massima, absf(v0))

		var t1 := durata
		## ⚠️ Se lo scarto si sta già chiudendo da solo (`v0 < 0`) e lo si lascia
		## correre per tutta la durata, supera lo zero e torna indietro: l'osso
		## fa una frustata dalla parte opposta. Accorciare la finestra a
		## `-5·x0/v0` è la guardia che Bollo mette proprio per questo.
		if v0 < 0.0:
			t1 = minf(durata, -5.0 * x0 / v0)
		if t1 <= 0.0:
			continue

		_asse[i] = asse
		_x0[i] = x0
		_v0[i] = v0
		_t1[i] = t1
		qualcosa = true

	if qualcosa:
		_attiva = true
		_t = 0.0


## La quintica. Sei condizioni: scarto, velocità e accelerazione all'inizio
## (x0, v0, 0) e alla fine (0, 0, 0).
func _scarto_al_tempo(i : int, t : float) -> float:
	var t1 : float = _t1[i]
	var s : float = clampf(t / t1, 0.0, 1.0)
	var x0 : float = _x0[i]
	var c1 : float = _v0[i] * t1
	var P : float = -(x0 + c1)
	var Q : float = -c1
	var c3 : float = 10.0 * P - 4.0 * Q
	var c4 : float = 7.0 * Q - 15.0 * P
	var c5 : float = 6.0 * P - 3.0 * Q
	var s2 := s * s
	return x0 + c1 * s + c3 * s2 * s + c4 * s2 * s2 + c5 * s2 * s2 * s
