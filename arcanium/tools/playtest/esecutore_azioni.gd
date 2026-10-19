extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## L'ESECUTORE — l'azione scelta diventa tasti, come per un giocatore umano
## ═══════════════════════════════════════════════════════════════════════════
##
## Niente chiamate a funzioni interne del player: tutto passa dall'InputMap,
## per le STESSE due strade che usa chi gioca col pad.
##
##   - i COMANDI (attacco, schivata, parata, interact, lock-on) sono eventi:
##     `Input.parse_input_event(InputEventAction)`. Arrivano a `_input()` del
##     player e aggiornano lo stato dell'azione, quindi anche il Cono, che
##     legge `Input.is_action_just_pressed("interact")`, li vede;
##   - il MOVIMENTO si legge a polling (`Input.get_vector` dentro il ciclo di
##     fisica): lo si da' con `Input.action_press(azione, intensita')`.
##
## La sterzata attorno alle rocce e il calcolo della direzione sono del codice
## (come in doom-jev): Jev sceglie "vai avanti", il codice sa dove.
##
## ⚠️ Il movimento del player e' relativo alla CAMERA, o al BERSAGLIO quando e'
## agganciato (`calc_direction` / `_direzione_dal_bersaglio` in
## player_charbody3D.gd). Qui si inverte la stessa formula: da "voglio andare
## di la' nel mondo" alle quattro intensita' dei tasti.

## Descrizioni delle azioni per Jev (criteri della Choice). In inglese, e
## contrastive: dicono QUANDO usarla, non solo cosa fa.
const CRITERI := {
	"move_on": "Walk toward the objective along the trail; the code steers around rocks. Use when no living enemy is within medium distance, or after the fight is won.",
	"attack_light": "Quick sword strike at the locked or closest enemy. Use when an enemy is very close and is recovering after its attack, not attacking, or low on health: press the advantage and finish it. Locks on by itself if needed.",
	"attack_heavy": "Slow, strong strike. Use when the enemy is very close and staggered, knocked down, or recovering after its attack.",
	"dodge": "Roll away from the closest enemy. Use when an enemy that is very close or close is winding up an attack or striking right now.",
	"guard": "Raise the shield and keep it up. Use when a strike is coming and stamina is not low.",
	"lock_on": "Lock movement and attacks onto the nearest enemy. Use when you start fighting and no target is locked.",
	"release_lock": "Stop being locked on. Use when the locked enemy is dead, fleeing or far away and you need to travel.",
	"approach": "Walk toward the locked or closest enemy. Use when an enemy blocks the way at close, medium or far distance, or a wounded enemy is getting away.",
	"back_off": "Walk away from the closest enemy. Use only when your health is low or almost empty, or your stamina is empty.",
	"circle_left": "Step around the locked or closest enemy to the left. Use to get out of the line of its attack.",
	"circle_right": "Step around the locked or closest enemy to the right. Use to get out of the line of its attack.",
	"jump": "Jump forward. Use when a low obstacle blocks the trail ahead.",
	"interact": "Use what is in front of you: activate a Channeling Cone that is not yet activated, or talk to a character. Use only when something is listed as within reach. On a Cone that is already active it opens the rest menu.",
	"close_menu": "Close the open menu and go back to the game. Use when a menu is open and you have nothing to choose in it.",
	"wait": "Do nothing for a moment. Use only when no other action makes sense.",
}

## Quanti tick resta premuto un tasto "battuto".
const TICK_BATTUTA := 2
## La schivata parte al RILASCIO di dodge_dash entro 0,3 s (dodge_or_sprint):
## tenuto di piu' diventa uno scatto.
const TICK_SCHIVATA := 2
## Senza bersaglio agganciato un attacco parte dove il personaggio e' girato,
## cioe' dove camminava: prima si aggancia il piu' vicino, poi si colpisce.
const TICK_AGGANCIO := 3
## Prima di menare si gira il player verso il bersaglio spingendo la levetta,
## come fa chi gioca: per tanti tick quanti ne servono a voltarsi.
const TICK_VOLTA := 6
## Oltre questo angolo (gradi) fra il verso del player e il bersaglio ci si
## volta prima di colpire.
const ANGOLO_VOLTA := 35.0
const AGGANCIO_AUTOMATICO := 6.0

var oss  ## Osservatore
var azione : String = "wait"
var _inizio : int = 0
var _rilasci : Dictionary = {}      ## azione InputMap -> tick del rilascio
var _tenute : Dictionary = {}       ## azioni InputMap tenute giu' finche' l'azione dura
var _differiti : Dictionary = {}    ## azione InputMap -> tick in cui batterla
var _volta_fino := -1               ## fino a questo tick si spinge verso il bersaglio
var sentiero : String = "clear"     ## l'ultima lettura delle sonde, per lo stato
var _dir_schivata := Vector3.ZERO


func _init(osservatore) -> void:
	oss = osservatore


## ─── Quali azioni hanno senso adesso ────────────────────────────────────────

func azioni_disponibili(menu_aperto : bool) -> Array:
	if menu_aperto:
		return ["close_menu", "wait"]
	var p : CharacterBody3D = oss.player
	var out : Array = ["move_on"]
	var vivi : Array = oss.nemici().filter(func(e): return not e.is_dead())
	var vicino := _piu_vicino(vivi)
	var d := 999.0
	if vicino != null:
		d = _piatta(vicino.global_position - p.global_position).length()
	if d < 20.0:
		out.append_array(["attack_light", "attack_heavy", "dodge", "guard"])
		out.append("release_lock" if p.lock_on_target() != null else "lock_on")
		out.append_array(["approach", "back_off", "circle_left", "circle_right"])
	out.append("jump")
	if qualcosa_a_portata() != "":
		out.append("interact")
	out.append("wait")
	return out

func criteri(azioni : Array) -> Dictionary:
	var c := {}
	for a in azioni:
		c[a] = CRITERI.get(a, a)
	return c

## Il nome di cio' che e' a portata di "interact", o "".
func qualcosa_a_portata() -> String:
	var p : CharacterBody3D = oss.player
	var it = p.get("interactable")
	if it != null and is_instance_valid(it):
		return str(it.name)
	for c in p.get_tree().get_nodes_in_group("channeling_cone"):
		## Stessa misura del Cono (`dist <= interact_radius` in channeling_cone.gd).
		if c.global_position.distance_to(p.global_position) <= float(c.get("interact_radius")):
			return "Channeling Cone (%s)" % ("already active" if bool(c.get("is_active")) else "not yet activated")
	for m in p.get_tree().get_nodes_in_group("summon_teacher"):
		if _piatta(m.global_position - p.global_position).length() < 2.5:
			return "Summoning Master (a character you can talk to)"
	return ""


## ─── Una nuova decisione ────────────────────────────────────────────────────

func scegli(nuova : String, tick : int) -> void:
	var cambiata := nuova != azione
	if cambiata and _tenute.has("use_gadget_light") and nuova != "guard":
		_evento("use_gadget_light", false)
		_tenute.erase("use_gadget_light")
	azione = nuova
	_inizio = tick
	match nuova:
		"attack_light", "attack_heavy":
			var tasto := "use_weapon_light" if nuova == "attack_light" else "use_weapon_strong"
			var ritardo := 0
			if _aggancia_se_serve(tick):
				ritardo = TICK_AGGANCIO
			## Girato dalla parte sbagliata: prima ci si volta (levetta verso il
			## bersaglio in `_direzione_voluta`), poi si colpisce.
			_volta_fino = -1
			if _angolo_dal_bersaglio() > ANGOLO_VOLTA:
				_volta_fino = tick + TICK_VOLTA
				ritardo = maxi(ritardo, TICK_VOLTA)
			if ritardo > 0:
				_differiti[tasto] = tick + ritardo
			else:
				_batti(tasto, tick)
		"lock_on", "release_lock": _batti("lock_on", tick)
		"jump": _batti("jump", tick)
		"interact": _batti("interact", tick)
		"close_menu": _batti("ui_cancel", tick)
		"dodge":
			var v = _piu_vicino(oss.nemici().filter(func(e): return not e.is_dead()))
			_dir_schivata = _piatta(oss.player.global_position - v.global_position).normalized() if v != null else -_avanti_percorso()
			_batti("dodge_dash", tick, TICK_SCHIVATA)
		"guard":
			if not _tenute.has("use_gadget_light"):
				_evento("use_gadget_light", true)
				_tenute["use_gadget_light"] = true


## ─── A ogni tick ────────────────────────────────────────────────────────────

func applica(tick : int) -> void:
	for a in _differiti.keys():
		if tick >= int(_differiti[a]):
			_batti(a, tick)
			_differiti.erase(a)
	for a in _rilasci.keys():
		if tick >= int(_rilasci[a]):
			_evento(a, false)
			_rilasci.erase(a)
	_muovi(_direzione_voluta(tick))

## Aggancia il nemico piu' vicino se non c'e' gia' un bersaglio e uno e' a
## portata: e' il gesto che fa chi gioca prima di menare. True se ha agganciato.
func _aggancia_se_serve(tick : int) -> bool:
	var p : CharacterBody3D = oss.player
	if not p.has_method("lock_on_target") or p.lock_on_target() != null:
		return false
	var v = _piu_vicino(oss.nemici().filter(func(e): return not e.is_dead()))
	if v == null or _piatta(v.global_position - p.global_position).length() > AGGANCIO_AUTOMATICO:
		return false
	_batti("lock_on", tick)
	return true

## Di quanti gradi il player dovrebbe girarsi per guardare il bersaglio.
func _angolo_dal_bersaglio() -> float:
	var p : CharacterBody3D = oss.player
	var b = p.lock_on_target() if p.has_method("lock_on_target") else null
	if b == null:
		b = _piu_vicino(oss.nemici().filter(func(e): return not e.is_dead()))
	if b == null:
		return 0.0
	var d := _piatta(b.global_position - p.global_position)
	var z := _piatta(p.global_transform.basis.z)
	if d.length() < 0.01 or z.length() < 0.01:
		return 0.0
	return rad_to_deg(z.normalized().angle_to(d.normalized()))

func rilascia_tutto() -> void:
	_differiti.clear()
	for a in _rilasci.keys():
		_evento(a, false)
	_rilasci.clear()
	for a in _tenute.keys():
		_evento(a, false)
	_tenute.clear()
	_muovi(Vector3.ZERO)

func _direzione_voluta(tick : int) -> Vector3:
	var p : CharacterBody3D = oss.player
	var vivi : Array = oss.nemici().filter(func(e): return not e.is_dead())
	var bersaglio = p.lock_on_target() if p.has_method("lock_on_target") else null
	if bersaglio == null:
		bersaglio = _piu_vicino(vivi)
	if azione in ["attack_light", "attack_heavy"] and tick <= _volta_fino and bersaglio != null:
		return _piatta(bersaglio.global_position - p.global_position).normalized()
	match azione:
		"move_on", "jump":
			return _sterza(_avanti_percorso_verso_tappa())
		"approach":
			return _piatta(bersaglio.global_position - p.global_position).normalized() if bersaglio else Vector3.ZERO
		"back_off":
			return _piatta(p.global_position - bersaglio.global_position).normalized() if bersaglio else Vector3.ZERO
		"circle_left", "circle_right":
			if bersaglio == null:
				return Vector3.ZERO
			var verso := _piatta(bersaglio.global_position - p.global_position).normalized()
			## Guardando il bersaglio, la sinistra e' UP × verso.
			var lato := Vector3.UP.cross(verso) if azione == "circle_left" else verso.cross(Vector3.UP)
			return lato.normalized()
		"dodge":
			return _dir_schivata if tick - _inizio <= TICK_SCHIVATA + 1 else Vector3.ZERO
	return Vector3.ZERO

func _avanti_percorso() -> Vector3:
	return oss._direzione_obiettivo()

func _avanti_percorso_verso_tappa() -> Vector3:
	var t : Dictionary = oss.tappa_corrente()
	if t.is_empty():
		return Vector3.ZERO
	var d := _piatta(oss.posizione_tappa(t) - oss.player.global_position)
	## Arrivati davanti a un Cono ci si ferma: tocca a Jev premere "interact".
	if str(t.get("tipo")) == "cono" and d.length() < 0.9:
		return Vector3.ZERO
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


## ─── La sterzata ────────────────────────────────────────────────────────────
## Raggi dal petto in un ventaglio attorno alla direzione voluta: si prende il
## primo libero. Il ginocchio colpito col petto libero e' un ostacolo basso
## (da saltare). I corpi (nemici, altri) non contano come muri: si muovono.

const ANGOLI := [0.0, 20.0, -20.0, 40.0, -40.0, 60.0, -60.0, 85.0, -85.0]
const PORTATA := 1.7

func _sterza(voluta : Vector3) -> Vector3:
	if voluta == Vector3.ZERO:
		sentiero = "clear"
		return voluta
	var p : CharacterBody3D = oss.player
	var spazio := p.get_world_3d().direct_space_state
	var base := p.global_position
	var ginocchio := _colpisce(spazio, base + Vector3.UP * 0.35, voluta)
	var petto := _colpisce(spazio, base + Vector3.UP * 0.95, voluta)
	if not petto and not ginocchio:
		sentiero = "clear"
		return voluta
	if ginocchio and not petto and not _colpisce(spazio, base + Vector3.UP * 1.6, voluta):
		sentiero = "a low obstacle you could jump over"
	else:
		sentiero = "blocked straight ahead; the code steers around it"
	for a in ANGOLI:
		var dir := voluta.rotated(Vector3.UP, deg_to_rad(a))
		if not _colpisce(spazio, base + Vector3.UP * 0.95, dir) and not _colpisce(spazio, base + Vector3.UP * 0.35, dir):
			return dir
	sentiero = "blocked in every direction"
	return voluta

func _colpisce(spazio : PhysicsDirectSpaceState3D, da : Vector3, dir : Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(da, da + dir * PORTATA, 1)
	q.exclude = [oss.player.get_rid()]
	var r := spazio.intersect_ray(q)
	if r.is_empty():
		return false
	return not (r["collider"] is CharacterBody3D)


## ─── Dal mondo ai tasti ─────────────────────────────────────────────────────

func _muovi(dir : Vector3) -> void:
	var x := 0.0
	var y := 0.0
	if dir.length() > 0.01:
		var p : CharacterBody3D = oss.player
		var b = p.lock_on_target() if p.has_method("lock_on_target") else null
		if b != null or bool(p.get("strafing")):
			var avanti := Vector3.ZERO
			if b != null:
				avanti = _piatta(b.global_position - p.global_position)
			if avanti.length() < 0.001:
				var bp : Basis = p.global_transform.basis
				avanti = Vector3(bp.z.x, 0.0, bp.z.z)
			avanti = avanti.normalized()
			var destra := avanti.cross(Vector3.UP)
			x = dir.dot(destra)
			y = -dir.dot(avanti)
		else:
			var cam : Camera3D = p.get_viewport().get_camera_3d()
			var bc : Basis = cam.global_transform.basis
			var av := Vector3(bc.z.x, 0.0, bc.z.z)
			if av.length_squared() < 0.000001:
				av = Vector3(-bc.y.x, 0.0, -bc.y.z)
			var lato := Vector3(bc.x.x, 0.0, bc.x.z)
			x = dir.dot(lato.normalized())
			y = dir.dot(av.normalized())
	_forza("move_right", maxf(x, 0.0))
	_forza("move_left", maxf(-x, 0.0))
	_forza("move_down", maxf(y, 0.0))
	_forza("move_up", maxf(-y, 0.0))

func _forza(a : String, s : float) -> void:
	if s > 0.01:
		Input.action_press(a, s)
	elif Input.is_action_pressed(a):
		Input.action_release(a)

func _batti(a : String, tick : int, durata : int = TICK_BATTUTA) -> void:
	_evento(a, true)
	_rilasci[a] = tick + durata

static func _evento(a : String, giu : bool) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = giu
	ev.strength = 1.0 if giu else 0.0
	Input.parse_input_event(ev)

static func _piatta(v : Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

func _piu_vicino(lista : Array) -> Node3D:
	var migliore : Node3D = null
	var dm := INF
	for e in lista:
		var d := _piatta(e.global_position - oss.player.global_position).length()
		if d < dm:
			dm = d
			migliore = e
	return migliore
