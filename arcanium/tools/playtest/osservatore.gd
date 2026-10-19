extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## L'OSSERVATORE — cosa vede Jev, e cosa resta nella telemetria
## ═══════════════════════════════════════════════════════════════════════════
##
## Due prodotti dallo stesso sguardo sulla scena:
##
##   1. lo STATO per Jev, in parole. Jev non sa fare i conti ne' confrontare
##      numeri (docs.typesafe.ai, "Jev 1.13 jaggedness"): distanze, salute e
##      direzioni arrivano come parole ("close", "half", "ahead-left"), i conti
##      li fa il codice. FATTI OSSERVATI e DEDUZIONI stanno in due blocchi
##      separati (`observed` / `inferred`), perche' una domanda di Jev deve
##      poter puntare a cio' che e' successo senza confonderlo con cio' che il
##      codice ne ha ricavato. In inglese: e' la lingua in cui Jev rende meglio.
##
##   2. la TELEMETRIA, in numeri, un fotogramma per tick: e' cio' che si
##      allega a una segnalazione e cio' che il replay confronta.
##
## Non tocca il gioco: legge soltanto.

const Percorsi := preload("res://arcanium/tools/playtest/percorsi.gd")

## Come si chiamano i nemici per Jev, dal file della scena.
const NOMI_SCENA := {
	"lupo.tscn": "wolf",
	"lupo_alpha.tscn": "Alpha wolf (mini-boss)",
	"lupo_capobranco.tscn": "pack leader wolf",
}

const STATI_IA := ["idle", "chasing you", "fighting", "dead", "staggered (open to attacks)",
	"knocked down", "fleeing"]

var scena : Node = null
var player : CharacterBody3D = null
var director : Node = null
var terreno : Node = null
var percorso : Dictionary = {}
var tappa : int = 0

var _id_nemici : Dictionary = {}       ## istanza -> id stabile (ordine di scoperta)
var _prossimo_id : int = 1
var _ultimo_attacco : Dictionary = {}  ## id -> tick in cui ha iniziato l'ultima mossa
var _mossa_prima : Dictionary = {}     ## id -> la mossa vista al tick prima
var eventi : Array = []                ## [{tick, testo}] — gli ultimi, per Jev
var ultime_azioni : Array = []         ## nomi, le ultime 6
var tick : int = 0


func aggancia(radice : Node, percorso_scena : String) -> bool:
	scena = radice
	player = radice.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		for p in radice.get_tree().get_nodes_in_group("player"):
			if p.has_signal("death_started"):
				player = p
				break
	director = radice.get_node_or_null("Director")
	for c in radice.get_children():
		if c.get_class() == "Terrain3D":
			terreno = c
	percorso = Percorsi.per_scena(percorso_scena)
	return player != null


## ─── Le parole ──────────────────────────────────────────────────────────────

static func parola_distanza(d : float) -> String:
	if d < 2.5: return "very close"
	if d < 5.0: return "close"
	if d < 10.0: return "medium"
	if d < 20.0: return "far"
	return "very far"

static func parola_quota(r : float) -> String:
	if r >= 0.95: return "full"
	if r >= 0.7: return "high"
	if r >= 0.4: return "half"
	if r >= 0.15: return "low"
	if r > 0.0: return "almost empty"
	return "empty"

## Direzione di `verso` vista dal player, rispetto alla direzione dell'OBIETTIVO
## (non della camera ne' del muso): "ahead" vuol dire "fra te e dove devi andare".
func parola_direzione(verso : Vector3) -> String:
	var avanti := _direzione_obiettivo()
	var d := verso - player.global_position
	d.y = 0.0
	if d.length() < 0.3:
		return "here"
	var a := rad_to_deg(avanti.signed_angle_to(d.normalized(), Vector3.UP))
	## signed_angle_to attorno a +Y: positivo = a sinistra guardando lungo `avanti`.
	var nomi := ["ahead", "ahead-left", "left", "behind-left", "behind", "behind-right", "right", "ahead-right"]
	var settore := int(round(fposmod(a, 360.0) / 45.0)) % 8
	return nomi[settore]

## Dove sta `verso` rispetto a dove e' GIRATO il player (il suo +Z): e' cio'
## che decide se la spada lo prende. La prima versione dello stato dava solo
## la direzione rispetto all'obiettivo, e Jev menava davanti a se' con il
## nemico alle spalle (visto dall'utente il 2026-10-07).
func parola_rispetto_al_verso(verso : Vector3) -> String:
	var z := player.global_transform.basis.z
	z.y = 0.0
	var d := verso - player.global_position
	d.y = 0.0
	if d.length() < 0.3 or z.length() < 0.01:
		return "right on you"
	var a := rad_to_deg(z.normalized().signed_angle_to(d.normalized(), Vector3.UP))
	var nomi := ["in front of you", "in front of you, to the left", "on your left", "behind you, to the left",
		"behind you", "behind you, to the right", "on your right", "in front of you, to the right"]
	return nomi[int(round(fposmod(a, 360.0) / 45.0)) % 8]


## ─── Il percorso ────────────────────────────────────────────────────────────

func tappa_corrente() -> Dictionary:
	var tappe : Array = percorso.get("tappe", [])
	if tappa < tappe.size():
		return tappe[tappa]
	return {}

func posizione_tappa(t : Dictionary) -> Vector3:
	if t.get("tipo") == "boss":
		var b := boss_della_tappa(t)
		if b != null:
			return b.global_position
	if t.get("tipo") == "cono":
		var c := cono_della_tappa(t)
		if c != null:
			## Davanti al Cono, dal lato da cui si arriva (la strada va verso −Z).
			return c.global_position + Vector3(0, 0, 1.6)
	return t.get("pos", player.global_position)

func _direzione_obiettivo() -> Vector3:
	var t := tappa_corrente()
	var d := (posizione_tappa(t) if not t.is_empty() else player.global_position + Vector3.FORWARD) - player.global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else Vector3.FORWARD

func cono_della_tappa(t : Dictionary) -> Node3D:
	for c in player.get_tree().get_nodes_in_group("channeling_cone"):
		if str(c.name).begins_with(str(t.get("nodo", "?"))):
			return c
	return null

func boss_della_tappa(t : Dictionary) -> Node3D:
	for e in nemici():
		if str(e.name).begins_with(str(t.get("nodo", "?"))):
			return e
	return null

## True se la tappa e' fatta. Il percorso va avanti da solo: e' il codice a
## sapere dove si e', Jev legge solo "dove andare adesso".
func tappa_fatta(t : Dictionary) -> bool:
	match str(t.get("tipo")):
		"cono":
			var c := cono_della_tappa(t)
			return c != null and bool(c.get("is_active"))
		"boss":
			var b := boss_della_tappa(t)
			return b == null or not is_instance_valid(b) or b.is_dead()
		_:
			var p : Vector3 = t.get("pos")
			var d := player.global_position - p
			d.y = 0.0
			## Raggiunta, o oltrepassata lungo −Z (la strada della Traccia).
			return d.length() < 2.5 or player.global_position.z < p.z - 1.0


## ─── I nemici ───────────────────────────────────────────────────────────────

func nemici() -> Array:
	var out : Array = []
	for e in player.get_tree().get_nodes_in_group("arcanium_enemy"):
		if is_instance_valid(e) and e.is_inside_tree():
			if not _id_nemici.has(e):
				_id_nemici[e] = _prossimo_id
				_prossimo_id += 1
			out.append(e)
	## Ordine stabile: per id, cosi' "enemy 2" resta lo stesso fra due stati.
	out.sort_custom(func(a, b): return _id_nemici[a] < _id_nemici[b])
	return out

func id_di(e : Node) -> int:
	return int(_id_nemici.get(e, 0))

func nome_nemico(e : Node) -> String:
	var f := str(e.scene_file_path).get_file()
	if NOMI_SCENA.has(f):
		return NOMI_SCENA[f]
	if f.begins_with("consumato"):
		return "Consumed (undead warrior)"
	if e.get("is_alpha") == true:
		return "Alpha wolf"
	if "quadruped" in str(e.get_script().resource_path):
		return "wolf"
	return str(e.name).to_lower()

func clip_di(e : Node) -> String:
	if e.has_method("_clip_corrente"):
		return str(e.call("_clip_corrente"))
	return str(e.get("_current_anim"))

## Su che cosa poggia un corpo: il suolo, un altro corpo, o niente.
static func appoggio(corpo : CharacterBody3D) -> Dictionary:
	if not corpo.is_on_floor():
		return {"su": "aria", "nodo": null}
	for i in corpo.get_slide_collision_count():
		var k := corpo.get_slide_collision(i)
		if k.get_normal().y > 0.7:
			var col := k.get_collider()
			if col is CharacterBody3D:
				return {"su": "corpo", "nodo": col}
			return {"su": "suolo", "nodo": col}
	return {"su": "suolo", "nodo": null}

## Le tre fasi di una mossa, perche' chiedono tre risposte diverse: in CARICA
## si schiva o si para, mentre COLPISCE ci si toglie, in RECUPERO si mena.
## La prima partita di Jev (2026-10-07) le leggeva fuse in "striking or
## recovering" e non trovava mai la finestra per contrattaccare: 388 fra
## schivate, passi indietro e parate contro 64 attacchi.
func fase_attacco(e : Node) -> String:
	var mossa = e.get("_active_move")
	if mossa == null:
		return "not attacking"
	if not bool(e.get("_attack_released")):
		return "winding up an attack (the strike is coming)"
	var contatti = e.get("_pending_contacts")
	if contatti is PackedFloat32Array and not contatti.is_empty():
		return "striking right now (more hits of this attack are coming)"
	return "recovering after its attack (open to a counterattack)"

## Va chiamato a ogni tick: tiene a mente quando ogni nemico ha attaccato.
func aggiorna_memoria_nemici() -> void:
	for e in nemici():
		var i := id_di(e)
		var m = e.get("_active_move")
		if m != null and _mossa_prima.get(i) == null:
			_ultimo_attacco[i] = tick
		_mossa_prima[i] = m

func tick_ultimo_attacco(e : Node) -> int:
	return int(_ultimo_attacco.get(id_di(e), -1))

func parola_ultimo_attacco(e : Node) -> String:
	var t := tick_ultimo_attacco(e)
	if t < 0:
		return "has not attacked yet"
	var s := float(tick - t) / float(Engine.physics_ticks_per_second)
	if s < 1.0: return "attacked just now"
	if s < 4.0: return "attacked recently"
	return "has not attacked for a while"


## ─── Gli eventi recenti ─────────────────────────────────────────────────────

func evento(testo : String) -> void:
	eventi.append({"tick": tick, "testo": testo})
	if eventi.size() > 12:
		eventi.pop_front()

func _eventi_recenti() -> Array:
	var out : Array = []
	for ev in eventi:
		var s := float(tick - int(ev["tick"])) / float(Engine.physics_ticks_per_second)
		if s > 8.0:
			continue
		var quando := "just now" if s < 1.0 else ("a moment ago" if s < 4.0 else "a few seconds ago")
		out.append("%s (%s)" % [ev["testo"], quando])
	return out.slice(-6)


## ─── Lo stato per Jev ───────────────────────────────────────────────────────

func stato_per_jev(azioni : Array, extra : Dictionary) -> Dictionary:
	var hs = player.get("health_system")
	var vit = player.get("vitals")
	var vita := float(hs.current_health) / float(maxi(1, hs.total_health)) if hs else 1.0
	var p := {
		"health": parola_quota(vita),
		"stamina": parola_quota(vit.stamina_ratio()) if vit else "unknown",
		"doing": _cosa_fa_il_player(),
		"on_ground": player.is_on_floor(),
		"locked_on_target": _bersaglio_agganciato(),
	}
	var lista : Array = []
	for e in nemici():
		if e.is_dead():
			continue
		var d := Vector3(e.global_position - player.global_position)
		d.y = 0.0
		if d.length() > 30.0:
			continue
		var hse = e.get("health_system")
		var app := appoggio(e)
		lista.append({
			"id": id_di(e),
			"kind": nome_nemico(e),
			"distance": parola_distanza(d.length()),
			"direction": parola_direzione(e.global_position),
			"relative_to_your_facing": parola_rispetto_al_verso(e.global_position),
			"state": STATI_IA[int(e.get("_state"))] if int(e.get("_state")) < STATI_IA.size() else "unknown",
			"attack": fase_attacco(e),
			"last_attack": parola_ultimo_attacco(e),
			"health": parola_quota(float(hse.current_health) / float(maxi(1, hse.total_health))) if hse else "unknown",
			"animation": clip_di(e),
			"standing_on": _parola_appoggio(app),
		})
	var t := tappa_corrente()
	var obiettivo := {}
	if not t.is_empty():
		var pos := posizione_tappa(t)
		var dd := pos - player.global_position
		dd.y = 0.0
		obiettivo = {"text": t.get("testo", ""), "direction": parola_direzione(pos), "distance": parola_distanza(dd.length())}
	var osservato := {
		"player": p,
		"player_standing_on": _parola_appoggio(appoggio(player)),
		"enemies": lista,
		"objective": obiettivo,
		"recent_events": _eventi_recenti(),
		"your_last_actions": ultime_azioni.slice(-6),
	}
	osservato.merge(extra)
	return {
		"observed": osservato,
		"inferred": _deduzioni(lista),
		"available_actions": azioni,
	}

func _parola_appoggio(app : Dictionary) -> String:
	match str(app["su"]):
		"aria": return "nothing (in the air)"
		"corpo":
			var n = app["nodo"]
			if n == player:
				return "the player"
			if _id_nemici.has(n):
				return "another creature: enemy %d (%s)" % [id_di(n), nome_nemico(n)]
			return "another creature"
	return "the ground"

func _cosa_fa_il_player() -> String:
	if bool(player.get("is_dead")): return "dead"
	if player.has_method("is_stunned") and player.is_stunned(): return "stunned (cannot act)"
	if bool(player.get("input_fully_locked")): return "in a conversation or cutscene (cannot move)"
	if bool(player.get("dodging")): return "dodging"
	if bool(player.get("guarding")): return "guarding with the shield"
	if bool(player.get("busy")): return "attacking"
	if not player.is_on_floor(): return "in the air"
	var v := player.velocity
	v.y = 0.0
	return "moving" if v.length() > 0.5 else "standing still"

func _bersaglio_agganciato() -> String:
	if not player.has_method("lock_on_target"):
		return "none"
	var b = player.lock_on_target()
	if b == null:
		return "none"
	if _id_nemici.has(b):
		return "enemy %d (%s)" % [id_di(b), nome_nemico(b)]
	return "something"

## Le deduzioni del codice, separate dai fatti: Jev le legge come tali.
func _deduzioni(lista : Array) -> Dictionary:
	var vicini := 0
	var in_carica := 0
	var scoperto := false
	var ferito := false
	var alle_spalle := false
	for e in lista:
		if e["distance"] in ["very close", "close"] and str(e["relative_to_your_facing"]).begins_with("behind"):
			alle_spalle = true
		if e["distance"] in ["very close", "close"] and e["state"] != "fleeing":
			vicini += 1
			if str(e["attack"]).begins_with("winding up") or str(e["attack"]).begins_with("striking"):
				in_carica += 1
		## La finestra per menare: e' la deduzione che la prima partita non
		## aveva, e senza la quale Jev scappava invece di combattere.
		if e["distance"] == "very close":
			if str(e["attack"]).begins_with("recovering") or str(e["state"]).begins_with("staggered") \
					or str(e["state"]).begins_with("knocked"):
				scoperto = true
			if e["health"] in ["low", "almost empty"]:
				ferito = true
	var pericolo := "none"
	if vicini >= 2 or in_carica >= 1:
		pericolo = "high"
	elif vicini == 1:
		pericolo = "medium"
	elif not lista.is_empty():
		pericolo = "low"
	return {
		"danger": pericolo,
		"enemies_close": "%s" % ("none" if vicini == 0 else ("one" if vicini == 1 else "several")),
		"an_enemy_strike_is_coming": in_carica > 0,
		"a_very_close_enemy_is_open_to_attack": scoperto,
		"a_very_close_enemy_is_almost_dead": ferito,
		"a_close_enemy_is_behind_you": alle_spalle,
	}


## ─── La telemetria, in numeri ───────────────────────────────────────────────

func telemetria() -> Dictionary:
	var hs = player.get("health_system")
	var vit = player.get("vitals")
	var app := appoggio(player)
	var t := {
		"tick": tick,
		"tappa": tappa,
		"tratto": director.current_tratto() if director and director.has_method("current_tratto") else -1,
		"player": {
			"pos": _v(player.global_position), "vel": _v(player.velocity),
			"a_terra": player.is_on_floor(), "su": app["su"],
			"su_nodo": str(app["nodo"].name) if app["nodo"] != null else "",
			"hp": hs.current_health if hs else -1,
			"stamina": snappedf(vit.stamina, 0.1) if vit else -1,
			"fa": _cosa_fa_il_player(),
			"yaw": _yaw(player), "finisher": bool(player.get("finisher_active")),
			"input": [snappedf(Input.get_action_strength("move_left"), 0.01), snappedf(Input.get_action_strength("move_right"), 0.01),
				snappedf(Input.get_action_strength("move_up"), 0.01), snappedf(Input.get_action_strength("move_down"), 0.01)],
		},
		"nemici": [],
	}
	for e in nemici():
		var hse = e.get("health_system")
		var ae := appoggio(e)
		t["nemici"].append({
			"id": id_di(e), "nome": str(e.name), "tipo": nome_nemico(e),
			"pos": _v(e.global_position), "stato": int(e.get("_state")),
			"clip": clip_di(e), "hp": hse.current_health if hse else -1,
			"mossa": str(e.get("_active_move").id) if e.get("_active_move") != null else "",
			"su": ae["su"], "su_nodo": str(ae["nodo"].name) if ae["nodo"] != null else "",
			"genitore": str(e.get_parent().name),
			"yaw": _yaw(e), "angolo_verso_player": _angolo_verso(e, player),
		})
	return t

## Il verso del "davanti" (+Z, come per `_start_finisher` e `_apply_hit`), in gradi.
static func _yaw(n : Node3D) -> float:
	var z := n.global_transform.basis.z
	return snappedf(rad_to_deg(atan2(z.x, z.z)), 0.1)

## Di quanti gradi `chi` dovrebbe girarsi per guardare `verso`: 0 = lo guarda.
static func _angolo_verso(chi : Node3D, verso : Node3D) -> float:
	var d := verso.global_position - chi.global_position
	d.y = 0.0
	var z := chi.global_transform.basis.z
	z.y = 0.0
	if d.length() < 0.01 or z.length() < 0.01:
		return 0.0
	return snappedf(rad_to_deg(z.normalized().angle_to(d.normalized())), 0.1)

static func _v(p : Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]
