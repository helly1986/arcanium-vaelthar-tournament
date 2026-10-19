extends Node

## ═══════════════════════════════════════════════════════════════════════════
## L'ORDINE DEL COMANDANTE — ③ Comandante Consumato
## ═══════════════════════════════════════════════════════════════════════════
##
## «L'ultimo ordine, ad alta voce»: il Comandante ripete l'ordine gridandolo e
## i fanti attorno lo eseguono — sono LORO a coordinare l'accerchiamento.
## Ucciso per primo, i fanti non fuggono: tornano a essere singoli, smettono di
## accerchiare, attaccano scoordinati e si intralciano. E' il gemello
## dell'Alpha del Branco Guasto (la' il branco fugge, qui l'esercito si
## sfalda): «colpisci chi tiene insieme il gruppo».
##
## Il TELL, dalla lore: «chi comanda guarda i suoi, chi obbedisce guarda te».
## A intervalli il Comandante volta la testa verso i propri mentre gli altri
## restano rivolti al giocatore (docs/10 §4: un modificatore sulla testa, non
## una clip, cosi' si compone con qualunque clip e punta i suoi davvero).
##
## Figlio del Comandante. Ogni `intervallo_arruolo` secondi arruola i fanti in
## mischia entro `raggio_comando` (umanoidi senza `distanza_preferita`: gli
## arcieri e il Mago hanno la loro tattica) e scrive se stesso nel loro
## `ordine` (arcanium_enemy.gd). A ognuno da' un POSTO sull'anello di raggio
## `raggio_accerchiamento` attorno al bersaglio, a spicchi uguali, nell'ordine
## in cui gia' stanno attorno a lui (nessuno attraversa il cerchio); e a uno
## alla volta il TURNO: quello va dritto sul bersaglio e attacca, gli altri
## aspettano al posto. Il turno passa quando la mossa e' finita, o dopo
## `turno_massimo` secondi se non riesce ad attaccare.

## Metri entro cui un fante obbedisce.
@export var raggio_comando := 14.0
## Margine dell'anello oltre la soglia di RIPARTENZA del fante (la sua
## distanza di mischia + `chase_hysteresis`), in metri. ⚠️ L'anello non puo'
## stare dentro quella fascia: un fante che si ferma li' resta fermo per
## sempre — troppo vicino per ripartire, troppo lontano per colpire — e finito
## l'ordine non attaccava piu' (verifica_comandante, 2026-09-30, anello fisso a
## 4 m con la fascia 3,0-3,6).
@export var margine_anello := 1.0
## Fanti che attaccano insieme.
@export var attaccanti := 1
## Secondi massimi di un turno che non arriva a colpire.
@export var turno_massimo := 5.0
## Respiro fra un turno e il successivo.
@export var pausa_fra_turni := 0.5
## Ogni quanto si ricontano i fanti.
@export var intervallo_arruolo := 0.5

@export_group("Il tell: la testa verso i suoi")
## Ogni quanto il Comandante si volta verso i suoi (secondi, con un po' di caso).
@export var intervallo_sguardo := 5.0
## Quanto tiene lo sguardo sui suoi.
@export var durata_sguardo := 1.3
## L'osso che si volta.
@export var osso_testa := "Head"

var _comandante : Node3D
var _fanti : Array[Node3D] = []
var _di_turno : Array[Node3D] = []
var _turno_da := {}          ## fante -> secondi dall'inizio del suo turno
var _ha_attaccato := {}      ## fante -> true quando lo si e' visto in una mossa
var _prossimo := 0           ## indice del prossimo di turno (a rotazione)
var _pausa := 0.0
## Chi ha appena lasciato il turno: il prossimo aspetta che sia fuori portata,
## o nel cambio due spade arrivavano insieme (verifica_comandante).
var _uscente : Node3D = null
var _t_arruolo := 0.0
var _sciolto := false

var _sguardo : SkeletonModifier3D = null
var _mira : Marker3D = null
## Il fante che il Comandante guarda: quello a cui sta per dare il turno.
var _guardato : Node3D = null
var _t_sguardo := 0.0
var _sguardo_fino := 0.0


func _ready() -> void:
	_comandante = get_parent() as Node3D
	_t_sguardo = intervallo_sguardo * randf_range(0.4, 1.0)
	call_deferred("_monta_sguardo")


## I fanti che obbediscono ora (per le verifiche e il debug).
func fanti() -> Array[Node3D]:
	return _fanti.duplicate()


## Chi ha il turno ora.
func di_turno() -> Array[Node3D]:
	return _di_turno.duplicate()


## Vero mentre il Comandante guarda i suoi.
func guarda_i_suoi() -> bool:
	return _sguardo_fino > 0.0


## Il fante che sta guardando (o null).
func guardato() -> Node3D:
	return _guardato if _sguardo_fino > 0.0 else null


## Il posto di un fante, o null se e' di turno (o non e' dei nostri).
func posto_per(fante : Node3D) -> Variant:
	if _sciolto or not _fanti.has(fante) or _di_turno.has(fante):
		return null
	var t := _bersaglio()
	if t == null:
		return null
	var ang := _angolo_del_posto(fante, t)
	var p := t.global_position + Vector3(sin(ang), 0.0, cos(ang)) * raggio_per(fante)
	p.y = fante.global_position.y
	return p


## Il raggio dell'anello per un fante: fuori dalla sua fascia di ripartenza.
func raggio_per(fante : Node3D) -> float:
	var soglia : float = fante._combat_range() + float(fante.get("chase_hysteresis"))
	return soglia + margine_anello


## Morto il Comandante: tutti tornano singoli.
func sciogli() -> void:
	if _sciolto:
		return
	_sciolto = true
	for f in _fanti:
		if is_instance_valid(f) and f.get("ordine") == self:
			f.set("ordine", null)
	_fanti.clear()
	_di_turno.clear()
	if _sguardo != null and is_instance_valid(_sguardo):
		_sguardo.influence = 0.0


func _exit_tree() -> void:
	sciogli()


func _physics_process(delta : float) -> void:
	if _sciolto:
		return
	if _comandante == null or not is_instance_valid(_comandante) \
			or (_comandante.has_method("is_dead") and _comandante.is_dead()):
		sciogli()
		return
	_t_arruolo -= delta
	if _t_arruolo <= 0.0:
		_t_arruolo = intervallo_arruolo
		_arruola()
	_turni(delta)
	_aggiorna_sguardo(delta)


## Il bersaglio del Comandante: l'ordine vale solo mentre lui combatte.
func _bersaglio() -> Node3D:
	var t = _comandante.get("target")
	if t == null or not is_instance_valid(t):
		return null
	return t as Node3D


func _arruola() -> void:
	var t := _bersaglio()
	var combatte := t != null and _comandante.global_position.distance_to(t.global_position) \
			<= float(_comandante.get("aggro_range")) * 1.5
	var nuovi : Array[Node3D] = []
	if combatte:
		for n in get_tree().get_nodes_in_group("targets"):
			var f := n as Node3D
			if f == null or f == _comandante or not is_instance_valid(f):
				continue
			if not ("ordine" in f) or not f.has_method("is_dead") or f.is_dead():
				continue
			if not f.has_method("_legge_avversario") or f.get("distanza_preferita") != null:
				continue   # solo umanoidi da mischia
			var altro = f.get("ordine")
			if altro != null and altro != self and is_instance_valid(altro):
				continue   # obbedisce a un altro Comandante
			if f.global_position.distance_to(_comandante.global_position) <= raggio_comando:
				nuovi.append(f)
	## Chi esce (morto, lontano, fine del combattimento) torna singolo.
	for f in _fanti:
		if not nuovi.has(f) and is_instance_valid(f) and f.get("ordine") == self:
			f.set("ordine", null)
	## L'ordine dei posti: come gia' stanno attorno al bersaglio, cosi' nessuno
	## attraversa l'anello per raggiungere il suo.
	if t != null:
		var c := t.global_position
		nuovi.sort_custom(func(a, b):
			return atan2(a.global_position.x - c.x, a.global_position.z - c.z) \
				< atan2(b.global_position.x - c.x, b.global_position.z - c.z))
	_fanti = nuovi
	for f in _fanti:
		f.set("ordine", self)
	_di_turno = _di_turno.filter(func(f): return _fanti.has(f))


## L'angolo del posto di un fante sull'anello: spicchi uguali, nell'ordine in
## cui i fanti gia' stanno attorno al bersaglio, e l'anello ruotato dove gli
## scarti dai posti sono minimi (media circolare di `angolo_i - i * spicchio`).
## ⚠️ Non «il primo fante da' l'angolo»: ordinando per atan2, quando uno passa
## per ±180° il primo cambia, tutti i posti ruotano di uno spicchio e qualcuno
## attraversa il cerchio passando sotto al giocatore (visto in
## verifica_comandante: tre a portata di spada insieme). La media circolare
## invece non cambia quando cambia chi e' primo.
func _angolo_del_posto(fante : Node3D, t : Node3D) -> float:
	var c := t.global_position
	var ang : Array = []
	for f in _fanti:
		ang.append([atan2(f.global_position.x - c.x, f.global_position.z - c.z), f])
	ang.sort_custom(func(a, b): return a[0] < b[0])
	var n := ang.size()
	var spicchio := TAU / float(n)
	var sx := 0.0
	var cy := 0.0
	var mio := 0
	for i in n:
		var d : float = ang[i][0] - float(i) * spicchio
		sx += sin(d)
		cy += cos(d)
		if ang[i][1] == fante:
			mio = i
	return atan2(sx, cy) + float(mio) * spicchio


func _turni(delta : float) -> void:
	## Chi e' di turno lo lascia quando ha finito la sua mossa, o dopo troppo.
	for f in _di_turno.duplicate():
		_turno_da[f] = float(_turno_da.get(f, 0.0)) + delta
		var in_mossa : bool = bool(f.get("_busy"))
		if in_mossa:
			_ha_attaccato[f] = true
		if (_ha_attaccato.get(f, false) and not in_mossa) or _turno_da[f] > turno_massimo:
			_di_turno.erase(f)
			_turno_da.erase(f)
			_ha_attaccato.erase(f)
			_pausa = pausa_fra_turni
			_uscente = f
	if _fanti.is_empty():
		return
	_pausa -= delta
	var t := _bersaglio()
	if _uscente != null and is_instance_valid(_uscente) and t != null and _pausa > -3.0:
		var d := Vector2(_uscente.global_position.x - t.global_position.x, _uscente.global_position.z - t.global_position.z).length()
		if d < _uscente._combat_range() + float(_uscente.get("chase_hysteresis")):
			return
	_uscente = null
	if _pausa > 0.0:
		return
	while _di_turno.size() < mini(attaccanti, _fanti.size()):
		_prossimo = _prossimo % _fanti.size()
		var f := _fanti[_prossimo]
		_prossimo += 1
		if not _di_turno.has(f):
			_di_turno.append(f)
			_turno_da[f] = 0.0


# ─── Il tell ────────────────────────────────────────────────────────────────

func _monta_sguardo() -> void:
	if _comandante == null:
		return
	var scheletri := _comandante.find_children("*", "Skeleton3D", true, false)
	if scheletri.is_empty():
		return
	var sk : Skeleton3D = scheletri[0]
	if sk.find_bone(osso_testa) < 0:
		return
	_mira = Marker3D.new()
	_mira.name = "MiraSguardo"
	_mira.top_level = true
	add_child(_mira)
	var la := LookAtModifier3D.new()
	la.name = "SguardoAiSuoi"
	la.bone_name = osso_testa
	la.influence = 0.0
	## Un collo, non un gufo: ±55° di lato, ±30° in alto e in basso. Senza
	## limite, con il fante alle spalle la testa girava di 141° sul busto
	## (misurato il 2026-09-30). Il limite vale rispetto alla posa della CLIP,
	## che gira gia' la testa fino a ~37°: con ±70° si arrivava a 102°.
	la.use_angle_limitation = true
	la.symmetry_limitation = true
	la.primary_limit_angle = deg_to_rad(110.0)
	la.secondary_limit_angle = deg_to_rad(60.0)
	sk.add_child(la)
	la.target_node = la.get_path_to(_mira)
	_sguardo = la


func _aggiorna_sguardo(delta : float) -> void:
	if _sguardo == null or _mira == null:
		return
	if _sguardo_fino > 0.0:
		_sguardo_fino -= delta
	elif not _fanti.is_empty() and _bersaglio() != null:
		_t_sguardo -= delta
		if _t_sguardo <= 0.0:
			_t_sguardo = intervallo_sguardo * randf_range(0.8, 1.3)
			_sguardo_fino = durata_sguardo
			## Guarda il fante a cui sta per dare il turno. ⚠️ Non il centro dei
			## suoi: stanno sull'anello attorno al giocatore, il loro centro E'
			## il giocatore, e il tell spariva (lo si guardava di nuovo in faccia).
			_guardato = _fanti[_prossimo % _fanti.size()]
	if _guardato != null and not is_instance_valid(_guardato):
		_guardato = null
	if _guardato != null:
		_mira.global_position = _guardato.global_position + Vector3(0, 1.6, 0)
	var voluto := 1.0 if _sguardo_fino > 0.0 and _guardato != null else 0.0
	_sguardo.influence = move_toward(_sguardo.influence, voluto, delta * 4.0)
