extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## QUANTO SLITTANO I PIEDI — la misura della locomozione, in centimetri
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/misura_slittamento.gd
##   ... -- inerzia=0        (spegne l'inerzia e torna alla dissolvenza)
##   ... -- durata=0.25      (quanto dura lo smorzamento dello scarto)
##   ... -- v0=0             (smorzamento senza aggancio alla velocita' iniziale)
##
## ─── Perche' NON si misura lo "scatto" ──────────────────────────────────────
## Il primo tentativo misurava la variazione di velocita' angolare delle ossa,
## sull'idea che un passaggio brusco la faccia saltare. Numero inservibile: il
## picco piu' alto dell'intera sequenza (10,49) cadeva DENTRO un fendente, cioe'
## in un momento in cui l'animazione DEVE strappare, mentre i passaggi di clip
## arrivavano a 4,6. Un metro che non sa distinguere un difetto da un colpo di
## spada non misura la fluidita': misura quanto corre forte il personaggio.
##
## ─── Cosa si misura invece ──────────────────────────────────────────────────
## Il PIEDE APPOGGIATO. Mentre un piede tocca terra deve stare fermo NEL MONDO:
## il corpo gli scorre sopra, lui no. Si prende la posizione del piede nello
## spazio dello scheletro, ci si somma la root motion accumulata — che e' lo
## spostamento vero del personaggio — e si guarda di quanto si sposta il piede
## nei fotogrammi in cui e' a terra. Quel che si sposta e' slittamento, ed e'
## esattamente cio' che l'occhio legge come "pattina sul ghiaccio".
##
## E' il difetto tipico di due cicli di passo mescolati: se camminata e corsa
## non chiudono il ciclo insieme, per tutta la durata della fusione i piedi
## fanno la media di due passi diversi e strisciano.
##
## ⚠️ Il ciclo di fisica del nemico e' SPENTO e il mixer si avanza a mano, ma i
## valori continui dell'albero vanno avanzati LO STESSO (`_aggiorna_blend`): un
## primo giro senza quella riga misurava un Fante fermo nell'idle e restituiva
## numeri bellissimi e falsi.

const PASSO := 1.0 / 60.0
const FANTE := "res://arcanium/characters/sylvorn_fante.tscn"
const PIEDI := ["LeftFoot", "RightFoot"]
## Ossa spia per lo SCATTO della posa (variazione della velocita' angolare).
## ⚠️ Da leggere solo CONFRONTANDO configurazioni sulla stessa sequenza: il
## valore assoluto non dice niente, perche' un fendente ha di suo uno scatto
## piu' alto di qualunque passaggio. Qui non ci sono fendenti apposta.
const SPIE := ["LeftUpperLeg", "Spine", "LeftUpperArm"]
## Un piede conta come APPOGGIATO entro questi metri dal punto piu' basso che
## tocca nella prova.
##
## ⚠️ Era una FRAZIONE dell'escursione verticale (25%), e sbagliava di brutto:
## il piede del Fante sale a mezzo metro, quindi il 25% metteva la soglia a 25
## cm e chiamava "appoggiato" un piede alzato di tredici centimetri. Metа' del
## volo finiva nel conto, e il numero saliva a 82 cm slittati per metro
## percorso — una cifra che da sola diceva che il metro era rotto.
## Due centimetri sono l'appoggio vero: la caviglia in riposo sta a 12,3 cm
## (vedi `verifica_piedi`), e quello che conta e' quanto STA FERMA.
const SOGLIA_APPOGGIO := 0.02
## ⚠️ QUANTE VOLTE si ripete la prova, sfasando la partenza.
##
## Una sola esecuzione NON e' una misura. Lo slittamento dipende da dove cade il
## cambio di clip dentro il ciclo del passo: cambiando solo la rapidita' della
## rampa i numeri saltavano fra 5,9 e 8,9 cm/m senza nessun andamento — cioe'
## era fase, non tendenza, e ci si stava per tarare sopra. Otto partenze
## sfalsate, mediate, danno un numero che si puo' confrontare con quello di
## ieri.
const RIPETIZIONI := 8
## Mezza finestra attorno a un cambio di clip, in fotogrammi. Generosa: la rampa
## dello spazio di fusione dura molto piu' di una dissolvenza.
const FINESTRA := 40

var _f : Node
var _t : AnimationTree
var _sk : Skeleton3D
var _mod : Node = null
## -1 = non toccare, lascia il valore che il modificatore si e' dato da solo.
var _usa_v0 : int = -1
var _tracce : Dictionary = {}
var _rm_cumulata := Vector3.ZERO
var _rm_per_frame : Array = []
var _rm_prec := Vector3.ZERO
var _scatto_rm : float = 0.0


func _initialize() -> void:
	_prova()


func _prova() -> void:
	await process_frame
	var pk : PackedScene = load(FANTE)
	_f = pk.instantiate()
	## ⚠️ `locomozione_sync` si impone PRIMA che il nodo entri nell'albero:
	## l'albero legge la configurazione una volta sola, all'avvio. Cambiarla
	## dopo non fa niente — tre modi diversi davano lo stesso identico numero,
	## che e' il modo in cui una manopola dice di non essere collegata.
	for a0 in OS.get_cmdline_user_args():
		var s0 := str(a0)
		if s0.begins_with("inerzia=") and "usa_inerzia" in _f:
			_f.set("usa_inerzia", s0.get_slice("=", 1) == "1")
			print("  [manopola] inerzia = %s" % s0.get_slice("=", 1))
		elif s0.begins_with("v0=") and "usa_inerzia" in _f:
			_usa_v0 = 1 if s0.get_slice("=", 1) == "1" else 0
			print("  [manopola] velocita' iniziale = %s" % s0.get_slice("=", 1))
		elif s0.begins_with("durata=") and "inerzia_durata" in _f:
			_f.set("inerzia_durata", float(s0.get_slice("=", 1)))
			print("  [manopola] durata inerzia = %s s" % s0.get_slice("=", 1))
	root.add_child(_f)
	await process_frame
	await process_frame

	_t = _f.get_node_or_null("Model/AlberoAnim")
	if _t == null:
		print("FALLITO: il Fante non ha l'albero (usa_anim_tree spento?)")
		quit(1); return
	_sk = _f.get_node("Model/NephiliteRig/Skeleton3D")
	_mod = _sk.get_node_or_null("Inerzia")
	if _mod != null and _usa_v0 >= 0:
		_mod.usa_velocita_iniziale = _usa_v0 == 1
	_f.set_physics_process(false)
	_t.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	for p in PIEDI:
		_tracce[p] = []


	## Fermo, cammina, corre, rallenta, si ferma. Niente attacchi: qui si misura
	## la locomozione, e un fendente porta il piede in aria per ragioni sue.
	var copione : Array = [
		["sword/sword_idle_01", 60],
		["sword/sword_walk_01", 150],
		["sword/sword_run_01",  150],
		["sword/sword_walk_01", 150],
		["sword/sword_idle_01", 90],
	]
	var slip : Array = []
	var peggi : Array = []
	var quota : Array = []
	var per_passaggio : Array = []
	var nomi_passaggio : Array = []
	for giro in RIPETIZIONI:
		_tracce = {}
		for p in PIEDI:
			_tracce[p] = []
		_rm_cumulata = Vector3.ZERO
		_rm_per_frame = []
		# Sfasa la partenza: il cambio di clip cade ogni volta in un punto
		# diverso del ciclo del passo.
		_f._play("sword/sword_idle_01", true)
		for k in (giro * 7):
			if _f.has_method("_aggiorna_blend"):
				_f._aggiorna_blend(PASSO)
			_t.advance(PASSO)
			if _mod != null:
				_mod._process_modification_with_delta(PASSO)

		var frame := 0
		var confini : Array = []
		var prima := ""
		for atto in copione:
			_f._play(str(atto[0]), true)
			if prima != "":
				confini.append([frame, str(atto[0])])
			prima = str(atto[0])
			for i in int(atto[1]):
				if _f.has_method("_aggiorna_blend"):
					_f._aggiorna_blend(PASSO)
				_t.advance(PASSO)
				## ⚠️ Con l'avanzamento a mano il motore NON chiama i
				## SkeletonModifier: misurato, 2 chiamate su 4800 fotogrammi.
				## Quindi lo si chiama qui, che e' esattamente cio' che il
				## motore farebbe dopo che il mixer ha scritto la posa.
				if _mod != null:
					_mod._process_modification_with_delta(PASSO)
				_campiona(frame)
				frame += 1

		var tot := 0.0
		var pegg := 0.0
		var dentro := 0.0
		for p in PIEDI:
			var e := _analizza(p, confini)
			tot += e[0]
			dentro += e[1]
			pegg = maxf(pegg, e[2])
			for j in e[3].size():
				while per_passaggio.size() <= j:
					per_passaggio.append(0.0)
					nomi_passaggio.append(str(confini[j][1]).get_file())
				per_passaggio[j] += e[3][j] * 100.0
		slip.append(tot * 100.0 / maxf(_rm_cumulata.length(), 0.0001))
		peggi.append(pegg * 100.0)
		quota.append(100.0 * dentro / maxf(tot, 0.0001))

	print("=== SLITTAMENTO DEL PIEDE APPOGGIATO — %d partenze sfalsate ===" % RIPETIZIONI)
	print("  per giro (cm slittati per metro percorso):")
	var riga := "   "
	for v in slip:
		riga += " %5.2f" % v
	print(riga)
	print("  ─────────────────────────────────────────────")
	print("  SLITTAMENTO MEDIO:        %5.2f cm/m   (min %.2f, max %.2f)" %
		[_media(slip), slip.min(), slip.max()])
	print("  PEGGIOR FOTOGRAMMA medio: %5.2f cm      (max %.2f)" % [_media(peggi), peggi.max()])
	print("  quota che cade nelle fusioni: %.0f%%" % _media(quota))
	print("  STRAPPO DELLA ROOT MOTION: %.4f m/fotogramma di salto massimo (%.2f m/s)" %
		[_scatto_rm, _scatto_rm * 60.0])
	print("  SCATTO DELLA POSA: medio %.4f, picco %.4f gradi/fotogramma" %
		[_scatto_somma / maxf(_scatto_n, 1), _scatto_picco])
	if _mod != null:
		print("  [inerzia] chiamate %d su %d fotogrammi; scarto max applicato %.1f gradi; v0 max %.1f rad/s" %
			[_mod.chiamate, RIPETIZIONI * 600, rad_to_deg(_mod.scarto_massimo_applicato), _mod.velocita_massima])
	print("  dove slitta (cm per giro, media su %d giri):" % RIPETIZIONI)
	for j in per_passaggio.size():
		print("    %-24s %6.2f cm" % [nomi_passaggio[j], per_passaggio[j] / RIPETIZIONI])
	quit(0)


func _media(a : Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)


var _q_spia : Dictionary = {}
var _d_spia : Dictionary = {}
var _scatto_somma : float = 0.0
var _scatto_picco : float = 0.0
var _scatto_n : int = 0

func _campiona(frame : int) -> void:
	for o in SPIE:
		var b := _sk.find_bone(o)
		var q : Quaternion = _sk.get_bone_pose_rotation(b)
		if _q_spia.has(o):
			var d : float = rad_to_deg(_q_spia[o].angle_to(q))
			if _d_spia.has(o):
				var sc : float = absf(d - _d_spia[o])
				_scatto_somma += sc
				_scatto_picco = maxf(_scatto_picco, sc)
				_scatto_n += 1
			_d_spia[o] = d
		_q_spia[o] = q
	## ⚠️ Lo strappo della ROOT MOTION e' il rischio di togliere la dissolvenza:
	## il Transition cambia clip di scatto, e con lei lo spostamento per
	## fotogramma — cioe' la VELOCITA' del personaggio. Il corpo puo' arrivare
	## liscio e il passo no.
	var rm : Vector3 = _t.get_root_motion_position()
	_scatto_rm = maxf(_scatto_rm, (rm - _rm_prec).length())
	_rm_prec = rm
	_rm_cumulata += rm
	_rm_per_frame.append(_rm_cumulata)
	for p in PIEDI:
		var idx := _sk.find_bone(p)
		var locale : Vector3 = _globale(idx).origin
		_tracce[p].append([locale + _rm_cumulata, locale.y, frame])


## ⚠️ Qui `get_bone_global_pose()` dice la verita' SOLO perche' il modificatore
## e' stato chiamato a mano un attimo prima, e ha scritto nella posa che questa
## funzione legge. In gioco, con la pipeline vera, la stessa chiamata da' la
## posa dell'ANIMAZIONE e non quella che esce dai modificatori — trappola gia'
## pagata su `ik_piedi.gd`.
func _globale(osso : int) -> Transform3D:
	return _sk.get_bone_global_pose(osso)


## Somma lo slittamento di UN piede, e dice quanto ne cade dentro le fusioni.
func _analizza(piede : String, confini : Array) -> Array:
	var t : Array = _tracce[piede]
	if t.size() < 3:
		return [0.0, 0.0, 0.0, []]
	var ymin := INF
	var ymax := -INF
	for c in t:
		ymin = minf(ymin, c[1])
		ymax = maxf(ymax, c[1])
	var soglia : float = ymin + SOGLIA_APPOGGIO

	var somma := 0.0
	var peggiore := 0.0
	var appoggiati := 0
	var per_frame : Array = []
	for i in range(1, t.size()):
		var s := 0.0
		if t[i][1] <= soglia and t[i - 1][1] <= soglia:
			var d : Vector3 = t[i][0] - t[i - 1][0]
			d.y = 0.0
			s = d.length()
			somma += s
			peggiore = maxf(peggiore, s)
			appoggiati += 1
		per_frame.append(s)

	var dentro := 0.0
	var per_confine : Array = []
	for c in confini:
		var q := 0.0
		for i in range(maxi(0, c[0] - FINESTRA), mini(per_frame.size(), c[0] + FINESTRA)):
			q += per_frame[i]
		dentro += q
		per_confine.append(q)

	return [somma, dentro, peggiore, per_confine]
