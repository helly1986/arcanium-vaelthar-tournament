extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## I SORVEGLIANTI — i controlli deterministici, attivi durante la partita
## ═══════════════════════════════════════════════════════════════════════════
##
## Sono loro a fare le segnalazioni, non Jev: "l'output tipizzato garantisce
## l'interfaccia, non la verita'". Ogni controllo ha una soglia esplicita e un
## tempo di CONFERMA (un contatto di un frame non e' un difetto), e dopo uno
## scatto tace per `SILENZIO` secondi sullo stesso soggetto.
##
## Le soglie sono un primo tentativo dichiarato, da tarare sul set etichettato
## (fase 2): per questo ogni allarme porta con se' i numeri grezzi, cosi' una
## soglia nuova si riapplica ai dati senza rigiocare.
##
## Gli errori del log di Godot li guarda l'orchestratore Python, che legge lo
## stdout del processo: qui non c'e' un modo pulito di intercettarli.

const SILENZIO := 5.0

## Quanto deve durare una condizione prima di diventare un allarme (secondi).
const CONFERMA := {
	"corpo_su_corpo": 0.25,
	"corpo_su_corpo_geometrico": 0.1,
	"sotto_il_suolo": 0.25,
	"bloccato": 2.0,
	"nemico_inerte": 6.0,
	"clip_vuota": 1.0,
	"softlock": 25.0,
}
## Tempo massimo per tappa, in secondi di gioco (il boss ha piu' margine).
const TEMPO_TAPPA := {"punto": 90.0, "cono": 60.0, "boss": 240.0}
## Sotto il terreno oltre questa quota (m) si e' "sotto il suolo".
const SOTTO_SUOLO := 0.6
## Il player che vuole muoversi e in 2 s fa meno di questo (m) e' bloccato.
const SPOSTAMENTO_MINIMO := 0.4
## Distanza (m) entro cui un nemico che combatte DEVE attaccare, prima o poi.
const PORTATA_INERTE := 2.5
## Due corpi "impilati": in pianta piu' vicini di questo (m)...
const RAGGIO_IMPILATI := 0.6
## ...e uno piu' alto dell'altro di almeno questo (m).
const DISLIVELLO_IMPILATI := 0.5
## Un colpo il cui autore sta oltre questa distanza (m) e' "senza sorgente".
const DANNO_LONTANO := 5.0
## DIREZIONALITA': un colpo che entra con la vittima oltre questo angolo dal
## "davanti" di chi colpisce e' "fuori asse". Sotto CORTO (m) non si giudica:
## a contatto il nemico colpisce senza arco (CLOSE_ARC_FREE_DIST nel nemico).
const ANGOLO_FUORI_ASSE := 90.0
const CORTO := 1.2

var oss  ## Osservatore
var _da : Dictionary = {}        ## chiave -> tick in cui la condizione e' iniziata
var _zitto : Dictionary = {}     ## chiave -> tick fino a cui tacere
var _pos_storia : Array = []     ## posizioni del player, una per tick, ultimi 2 s
var _tappa_da : int = 0
var _tappa_vista : int = -1
var _danni : Array = []          ## danni subiti da controllare (dal segnale)
var _dati : Array = []           ## colpi DATI dal player, da controllare
var colpi : Array = []           ## ogni colpo, in numeri: il ponte li scrive in colpi.jsonl


func _init(osservatore) -> void:
	oss = osservatore

func _tps() -> float:
	return float(Engine.physics_ticks_per_second)


## Registra un colpo al player (dal segnale damage_taken): lo si giudica al tick.
func colpo_subito(by_what) -> void:
	var pos := Vector3.INF
	var nome := "?"
	## Il colpo di un nemico arriva come la sua MOSSA (EnemyMove, una Resource):
	## l'autore e' il nemico che ha quella mossa attiva in questo momento.
	## ⚠️ La risorsa e' CONDIVISA da tutti i nemici dello stesso tipo: con due
	## lupi comuni a meta' dello stesso morso, prima il nome veniva dal primo e
	## la distanza dall'ultimo (2026-10-15: "W2 di nemico 9" a 1,99 m, misurati
	## da nemico 10 a 0,5 s di clip, lontano da ogni contatto). Ora si sceglie
	## una volta sola: chi ha la clip piu' vicina a un istante di contatto.
	var autore : Node3D = null
	if by_what is Resource:
		nome = str(by_what.get("id")) if by_what.get("id") != null else by_what.resource_path.get_file()
		autore = _autore_della_mossa(by_what)
		if autore != null:
			pos = autore.global_position
			nome = "%s di %s" % [nome, _chi(autore)]
	elif by_what is Node3D:
		pos = by_what.global_position
		nome = str(by_what.name)
	elif by_what is Node:
		nome = str(by_what.name)
	## La posizione del player si prende QUI, all'istante del colpo, non al
	## tick dopo: in mezzo puo' esserci il teletrasporto della rinascita, e
	## confrontare l'autore col player gia' portato al Cono inventa colpi da 15 m.
	var p : CharacterBody3D = oss.player
	_danni.append({"pos": pos, "nome": nome, "classe": by_what.get_class() if by_what is Object else "null",
		"pos_player": p.global_position, "morto": bool(p.get("is_dead")),
		"in_fisica": Engine.is_in_physics_frame(), "frame": Engine.get_process_frames()})
	_registra_colpo(autore, p, nome)


## Un colpo del player a un nemico (dal segnale damage_taken del nemico).
func colpo_dato(vittima : Node3D, by_what) -> void:
	var p : CharacterBody3D = oss.player
	## Il colpo della spada arriva come la RISORSA dell'arma (es.
	## lama_prima_veglia.tres), non come un nodo del player: si riconosce
	## confrontandola con l'arma in mano. Una Resource che non e' una mossa
	## nemica (niente `move_range`) e' comunque equipaggiamento del player.
	var arma = p.call("_arma_equipaggiata") if p.has_method("_arma_equipaggiata") else null
	var dal_player : bool = by_what == p or (by_what is Node and p.is_ancestor_of(by_what)) 		or (by_what is Resource and (by_what == arma or not ("move_range" in by_what)))
	var nome : String = str(by_what.name) if by_what is Node else str(by_what)
	var r := _registra_colpo(p if dal_player else null, vittima, nome)
	if dal_player:
		_dati.append(r)


## Angolo fra il "davanti" di chi colpisce (+Z, per player e nemici: vedi
## `_start_finisher` e `_apply_hit`) e la direzione verso la vittima.
## 0° = colpo davanti al muso, 180° = colpo dato alle proprie spalle.
## Fra i nemici con questa mossa attiva, quello che sta colpendo ORA: la clip
## piu' vicina a uno degli istanti di contatto della mossa.
func _autore_della_mossa(mossa : Resource) -> Node3D:
	var migliore : Node3D = null
	var scarto := INF
	var contatti : PackedFloat32Array = mossa.get("contact_times") if mossa.get("contact_times") != null else PackedFloat32Array()
	for e in oss.nemici():
		if e.get("_active_move") != mossa:
			continue
		var s := 0.0
		if e.has_method("_clip_pos") and not contatti.is_empty():
			var t := float(e.call("_clip_pos"))
			s = INF
			for c in contatti:
				s = minf(s, absf(t - float(c)))
		if s < scarto:
			scarto = s
			migliore = e
	return migliore


func _registra_colpo(autore : Node3D, vittima : Node3D, cosa : String) -> Dictionary:
	var p : CharacterBody3D = oss.player
	var r := {"tick": oss.tick, "cosa": cosa, "autore": _chi(autore) if autore else "?", "vittima": _chi(vittima)}
	if autore != null and is_instance_valid(autore) and is_instance_valid(vittima):
		var verso := vittima.global_position - autore.global_position
		verso.y = 0.0
		var avanti := autore.global_transform.basis.z
		avanti.y = 0.0
		r["distanza"] = snappedf(verso.length(), 0.01)
		if verso.length() > 0.01 and avanti.length() > 0.01:
			r["angolo"] = snappedf(rad_to_deg(avanti.normalized().angle_to(verso.normalized())), 0.1)
	if autore != null and autore != p and is_instance_valid(autore):
		## Dove era la clip del nemico quando il colpo e' entrato: e' il dato che
		## dice se il morso a schermo e il danno arrivano insieme.
		r["clip"] = oss.clip_di(autore)
		if autore.has_method("_clip_pos"):
			r["pos_clip"] = snappedf(float(autore.call("_clip_pos")), 0.001)
		var m = autore.get("_active_move")
		if m != null:
			r["move_range"] = snappedf(float(m.move_range), 0.01)
			r["balzo"] = bool(m.leap_to_target)
	if autore == p or vittima == p:
		## Cosa stava facendo il player: un finisher, una schivata, e i tasti
		## del movimento — e' il movimento che puo' girarlo durante un critico.
		r["player_fa"] = oss._cosa_fa_il_player()
		r["player_input"] = [snappedf(Input.get_action_strength("move_left"), 0.01), snappedf(Input.get_action_strength("move_right"), 0.01),
			snappedf(Input.get_action_strength("move_up"), 0.01), snappedf(Input.get_action_strength("move_down"), 0.01)]
		r["finisher"] = bool(p.get("finisher_active"))
		## Dove spingeva la LEVETTA, in gradi dal verso del player: se la levetta
		## puntava giusto e il colpo e' uscito storto, e' la rotazione del gioco.
		r["yaw_player"] = oss._yaw(p)
	colpi.append(r)
	return r


## Tutti i controlli di questo tick. Ritorna gli allarmi nuovi.
func controlla(tick : int) -> Array:
	var out : Array = []
	var p : CharacterBody3D = oss.player
	if bool(p.get("is_dead")):
		_da.clear()
		return out
	_pos_storia.append(p.global_position)
	if _pos_storia.size() > int(2.0 * _tps()):
		_pos_storia.pop_front()

	## 1. CORPO SU CORPO — un corpo poggia su un altro corpo invece che sul suolo.
	for c in [p] + oss.nemici():
		if c != p and c.is_dead():
			continue
		var app : Dictionary = oss.appoggio(c)
		var sotto = app["nodo"]
		_condizione(out, tick, "corpo_su_corpo", _chi(c), app["su"] == "corpo",
			"%s poggia su %s invece che sul suolo" % [_chi(c), _chi(sotto) if sotto else "?"],
			{"soggetto": _chi(c), "sotto": _chi(sotto) if sotto else "", "pos": _v(c.global_position),
				"pos_sotto": _v(sotto.global_position) if sotto is Node3D else []})

	## 1b. CORPO SU CORPO, GEOMETRICO — un corpo sta sopra un altro (in pianta
	## a meno di RAGGIO_IMPILATI, piu' in alto di DISLIVELLO_IMPILATI). Non
	## dipende dalle collisioni dell'ultimo move_and_slide: le vede anche quando
	## la fisica non gira (corpi congelati, teletrasportati). Misurato sul set
	## visivo del 2026-10-07: il controllo per contatto aveva mancato il lupo in
	## groppa congelato.
	var corpi : Array = [p] + oss.nemici().filter(func(e): return not e.is_dead())
	for c in corpi:
		for s in corpi:
			if c == s:
				continue
			var d : Vector3 = c.global_position - s.global_position
			var in_pianta := Vector2(d.x, d.z).length()
			var sopra : bool = in_pianta < RAGGIO_IMPILATI and d.y > DISLIVELLO_IMPILATI and d.y < 2.5
			_condizione(out, tick, "corpo_su_corpo_geometrico", _chi(c) + "|" + _chi(s), sopra,
				"%s sta %.2f m sopra %s (a %.2f m in pianta)" % [_chi(c), d.y, _chi(s), in_pianta],
				{"soggetto": _chi(c), "sotto": _chi(s), "pos": _v(c.global_position), "dislivello": snappedf(d.y, 0.01),
					"in_pianta": snappedf(in_pianta, 0.01)})

	## 2. SOTTO IL SUOLO — piu' basso del terreno sotto i piedi.
	for c in [p] + oss.nemici():
		if c != p and c.is_dead():
			continue
		var h : float = _altezza_terreno(c.global_position)
		var sotto : bool = not is_nan(h) and c.global_position.y < h - SOTTO_SUOLO
		_condizione(out, tick, "sotto_il_suolo", _chi(c), sotto or c.global_position.y < -50.0,
			"%s e' sotto il terreno" % _chi(c),
			{"soggetto": _chi(c), "y": snappedf(c.global_position.y, 0.01), "terreno": snappedf(h, 0.01) if not is_nan(h) else null,
				"pos": _v(c.global_position),
				## Oltre 96 m dalla camera Terrain3D non ha collisione (vedi il builder
				## della Traccia): li' "sotto il suolo" e' quasi sempre quello.
				"distanza_dal_player": snappedf(c.global_position.distance_to(p.global_position), 0.1)})

	## 3. BLOCCATO — vuole muoversi e non si sposta.
	var spinta := Input.get_action_strength("move_left") + Input.get_action_strength("move_right") \
		+ Input.get_action_strength("move_up") + Input.get_action_strength("move_down")
	var fermo := false
	var percorso := 0.0
	if _pos_storia.size() >= int(2.0 * _tps()):
		percorso = (_pos_storia[-1] - _pos_storia[0]).length()
		fermo = spinta > 0.5 and percorso < SPOSTAMENTO_MINIMO \
			and not bool(p.get("dodging")) and not bool(p.get("busy")) and not bool(p.get("guarding"))
	_condizione(out, tick, "bloccato", "player", fermo,
		"il player spinge da 2 s e si e' spostato di %.2f m" % percorso,
		{"spostamento_2s": snappedf(percorso, 0.01), "spinta": snappedf(spinta, 0.01), "pos": _v(p.global_position)})

	## 4. OBIETTIVO NON RAGGIUNTO entro il tempo della tappa.
	if oss.tappa != _tappa_vista:
		_tappa_vista = oss.tappa
		_tappa_da = tick
	var t : Dictionary = oss.tappa_corrente()
	if not t.is_empty():
		var limite : float = TEMPO_TAPPA.get(str(t.get("tipo")), 90.0)
		var passati := float(tick - _tappa_da) / _tps()
		if passati > limite and _libero(tick, "obiettivo_scaduto|%d" % oss.tappa):
			out.append(_allarme(tick, "obiettivo_scaduto", "tappa %d" % oss.tappa,
				"tappa %d (%s) non raggiunta in %.0f s" % [oss.tappa, t.get("tipo"), passati],
				{"tappa": oss.tappa, "testo": t.get("testo"), "secondi": snappedf(passati, 0.1), "pos": _v(p.global_position)}))
			_zitto["obiettivo_scaduto|%d" % oss.tappa] = tick + int(60.0 * _tps())

	## 5. DANNO SENZA SORGENTE — l'autore del colpo e' lontano e nessuno e' vicino.
	for d in _danni:
		var pp : Vector3 = d["pos_player"]
		var vicino := INF
		for e in oss.nemici():
			if not e.is_dead():
				vicino = minf(vicino, (e.global_position - pp).length())
		var da_lontano : bool = d["pos"] != Vector3.INF and (d["pos"] - pp).length() > DANNO_LONTANO
		if vicino > DANNO_LONTANO and (da_lontano or d["pos"] == Vector3.INF) and _libero(tick, "danno_senza_sorgente|player"):
			out.append(_allarme(tick, "danno_senza_sorgente", "player",
				"colpo da '%s' senza un nemico entro %.0f m" % [d["nome"], DANNO_LONTANO],
				{"autore": d["nome"], "classe": d["classe"], "nemico_piu_vicino_m": snappedf(vicino, 0.01) if vicino != INF else null,
					"pos_autore": _v(d["pos"]) if d["pos"] != Vector3.INF else [],
					"pos_player_al_colpo": _v(pp), "player_morto_al_colpo": d["morto"],
					"in_fisica": d["in_fisica"], "frame": d["frame"]}))
			_zitto["danno_senza_sorgente|player"] = tick + int(SILENZIO * _tps())
	_danni.clear()

	## 5b. COLPO FUORI ASSE — entra con la vittima alle spalle di chi colpisce.
	for r in colpi:
		if int(r["tick"]) != tick - 1 and int(r["tick"]) != tick:
			continue
		if r.has("angolo") and float(r["angolo"]) > ANGOLO_FUORI_ASSE and float(r.get("distanza", 0.0)) > CORTO 				and not r.get("_giudicato", false):
			r["_giudicato"] = true
			out.append(_allarme(tick, "colpo_fuori_asse", str(r["autore"]),
				"%s colpisce %s a %.0f° dal proprio davanti (%.1f m)" % [r["autore"], r["vittima"], r["angolo"], r["distanza"]],
				r.duplicate()))

	## 6. NEMICO INERTE — combatte, ti sta addosso, e non attacca mai.
	for e in oss.nemici():
		if e.is_dead():
			continue
		var stato : int = int(e.get("_state"))
		var dist : Vector3 = e.global_position - p.global_position
		dist.y = 0.0
		var ingaggiato := stato == 1 or stato == 2   ## CHASE, COMBAT
		var k := "nemico_inerte|" + _chi(e)
		var inerte := ingaggiato and dist.length() < PORTATA_INERTE
		## Se ha attaccato dopo l'inizio della condizione, la condizione riparte.
		if inerte and _da.has(k) and oss.tick_ultimo_attacco(e) >= int(_da[k]):
			_da[k] = tick
		_condizione(out, tick, "nemico_inerte", _chi(e), inerte,
			"%s ti sta a %.1f m in combattimento e non attacca" % [_chi(e), dist.length()],
			{"soggetto": _chi(e), "stato": stato, "clip": oss.clip_di(e), "distanza": snappedf(dist.length(), 0.01),
				"ultimo_attacco_tick": oss.tick_ultimo_attacco(e)})

	## 7. CLIP VUOTA — vivo, e nessuna animazione: la T-pose che si legge nei dati.
	for e in oss.nemici():
		if e.is_dead():
			continue
		_condizione(out, tick, "clip_vuota", _chi(e), oss.clip_di(e) == "",
			"%s non suona nessuna clip" % _chi(e), {"soggetto": _chi(e), "stato": int(e.get("_state"))})

	## 8. SOFTLOCK — comandi bloccati (dialogo, cutscene) o menu aperto troppo a lungo.
	var bloccato_ui := bool(p.get("input_fully_locked"))
	var menu := p.get_tree().root.get_node_or_null("ConeRestMenu") != null
	var gm := p.get_node_or_null("/root/GameMenu")
	if gm and gm.has_method("is_blocking") and gm.is_blocking():
		menu = true
	_condizione(out, tick, "softlock", "player", bloccato_ui or menu,
		"comandi bloccati da oltre %.0f s (dialogo/menu)" % CONFERMA["softlock"],
		{"input_bloccato": bloccato_ui, "menu": menu})
	return out


## ─── Meccanica comune ───────────────────────────────────────────────────────

func _condizione(out : Array, tick : int, tipo : String, soggetto : String, vera : bool, testo : String, dati : Dictionary) -> void:
	var k := tipo + "|" + soggetto
	if not vera:
		_da.erase(k)
		return
	if not _da.has(k):
		_da[k] = tick
		return
	var durata := float(tick - int(_da[k])) / _tps()
	if durata >= float(CONFERMA.get(tipo, 0.0)) and _libero(tick, k):
		dati["durata_s"] = snappedf(durata, 0.01)
		out.append(_allarme(tick, tipo, soggetto, testo, dati))
		_zitto[k] = tick + int(SILENZIO * _tps())

func _libero(tick : int, k : String) -> bool:
	return tick >= int(_zitto.get(k, -1))

func _allarme(tick : int, tipo : String, soggetto : String, testo : String, dati : Dictionary) -> Dictionary:
	return {"tick": tick, "tipo": tipo, "soggetto": soggetto, "testo": testo, "dati": dati}

func _chi(n) -> String:
	if n == null:
		return "?"
	if n == oss.player:
		return "player"
	if oss.id_di(n) > 0:
		return "nemico %d (%s)" % [oss.id_di(n), n.name]
	return str(n.name)

func _altezza_terreno(p : Vector3) -> float:
	var t = oss.terreno
	if t == null:
		return NAN
	var d = t.get("data")
	if d == null or not d.has_method("get_height"):
		return NAN
	return float(d.get_height(p))

static func _v(p : Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
