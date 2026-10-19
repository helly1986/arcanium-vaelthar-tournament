extends Node

## ═══════════════════════════════════════════════════════════════════════════
## IL PONTE DEL PLAYTEST — Jev gioca, il gioco aspetta, i sorveglianti guardano
## ═══════════════════════════════════════════════════════════════════════════
##
## Autoload SOLO STRUMENTI. Senza `--playtest` fra gli argomenti utente (dopo
## `--`) si toglie dall'albero al primo frame e il gioco non sa che esiste.
##
## Lancio (lo fa `arcanium/tools/playtest/gioca.py`, che apre anche il socket):
##
##   APPDATA=<cartella della partita> godot_console.exe --path . --fixed-fps 60 \
##     res://arcanium/levels/arena_branco.tscn -- --playtest --porta=47801 \
##     --seme=1 --out=<cartella della partita> [--azioni=<azioni.jsonl>]
##
## ⚠️ APPDATA diverso e' OBBLIGATORIO: il gioco salva da solo in user://, dove
## stanno i salvataggi dei test manuali. Qui sotto c'e' una seconda sicura che
## si rifiuta di partire nella cartella vera (vedi skill arcanium-playtest).
##
## MODALITA' DISCRETA: a ogni decisione il ponte manda lo stato e BLOCCA il
## ciclo di fisica finche' non arriva la risposta. Con `--fixed-fps` il tempo
## di gioco avanza a tick fissi qualunque cosa faccia il muro, e cooldown e
## stordimenti contano i tick (orologio_gioco.gd): l'attesa di Jev non esiste
## per il mondo.
##
## REPLAY: con `--azioni=` non apre nessun socket e rigioca le azioni
## registrate, tick per tick. Stesso seme, stessa scena, stessi tick: la
## partita deve tornare identica, e l'impronta della telemetria lo verifica.
##
## Protocollo (righe JSON sul socket, il ponte e' il client):
##   → {"tipo":"ciao", ...}                         all'avvio
##   → {"tipo":"stato","tick":N,"stato":{...},"criteri":{...}}   ← {"tipo":"azione","azione":"...","cattura":bool}
##   → {"tipo":"segnalazione", ...}                 nessuna risposta
##   → {"tipo":"fine", ...}                         poi si esce

const Osservatore := preload("res://arcanium/tools/playtest/osservatore.gd")
const Esecutore := preload("res://arcanium/tools/playtest/esecutore_azioni.gd")
const Sorveglianti := preload("res://arcanium/tools/playtest/sorveglianti.gd")

## Telemetria tenuta in memoria per le segnalazioni (secondi).
const STORIA_S := 4.0
## Entro questa distanza (m) un nemico vivo rende la scelta "di Jev".
const RAGGIO_JEV := 15.0
## Entro questa distanza (m) si decide ogni DECIDI_IN_MISCHIA tick.
const RAGGIO_MISCHIA := 6.0
const DECIDI_IN_MISCHIA := 6
## Quanto aspettare Jev prima di arrendersi a "wait" (ms di muro).
const ATTESA_MAX_MS := 30000

enum Fase { ATTESA_SCENA, GIOCA, FINE }

var _arg : Dictionary = {}
var _fase := Fase.ATTESA_SCENA
var _tick := 0
var _decidi_ogni := 12
var _out := ""
var _scena := ""
var _replay : Dictionary = {}      ## tick -> azione
var _replay_attivo := false
var _scen = null                   ## lo scenario, se si gioca uno scenario (arcanium/tools/scenari/)
var _ultimo_replay := 0
var _prossima := 1                ## tick della prossima decisione

var _tcp : StreamPeerTCP = null
var _buf := ""

var oss
var esec
var sorv
var _storia : Array = []
var _impronta := ""
var _morti := 0
var _morto := false             ## a terra, in attesa del respawn
var _tappe_fatte : Array = []
var _segnalazioni := 0
var _jev_chiamate := 0
var _jev_errori := 0
var _catture_in_corso := 0
var _f_azioni : FileAccess
var _f_tele : FileAccess
var _f_colpi : FileAccess
var _viste : Array = []           ## [SubViewport, Camera3D] per le angolazioni extra
var _max_tick := 0
var _max_morti := 5


func _ready() -> void:
	_arg = _argomenti()
	if not _arg.has("playtest"):
		queue_free()
		return
	## ⚠️ La seconda sicura: mai giocare sopra i salvataggi dei test manuali.
	var ud := OS.get_user_data_dir().replace("\\", "/")
	if ud.contains("AppData/Roaming/Godot"):
		push_error("PLAYTEST: rifiuto di partire con la cartella utente vera (%s). Lanciare con APPDATA isolato: vedi skill arcanium-playtest." % ud)
		get_tree().quit(3)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	## Prima di tutti: gli input di questo tick devono esserci quando il player
	## legge `Input.get_vector` nel suo `_physics_process`.
	process_physics_priority = -1000
	seed(int(_arg.get("seme", "1")))
	_decidi_ogni = int(_arg.get("decidi_ogni", "12"))
	_out = str(_arg.get("out", OS.get_user_data_dir() + "/playtest"))
	_max_tick = int(float(_arg.get("max_secondi", "900")) * Engine.physics_ticks_per_second)
	_max_morti = int(_arg.get("max_morti", "5"))
	DirAccess.make_dir_recursive_absolute(_out + "/segnalazioni")
	if _arg.has("scenario"):
		_scen = load(str(_arg["scenario"])).new()
		_max_tick = int(_scen.durata)
	elif _arg.has("azioni"):
		_carica_replay(str(_arg["azioni"]))
	else:
		_connetti(int(_arg.get("porta", "47801")))
	print("PLAYTEST: avviato — seme %s, decisione ogni %d tick, %s" % [_arg.get("seme", "1"), _decidi_ogni,
		"REPLAY di " + str(_arg["azioni"]) if _replay_attivo else "Jev via socket"])


func _argomenti() -> Dictionary:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var t := str(s).trim_prefix("--")
		var i := t.find("=")
		if i < 0:
			a[t] = true
		else:
			a[t.substr(0, i)] = t.substr(i + 1)
	return a


## ─── Il ciclo ───────────────────────────────────────────────────────────────

func _physics_process(_delta : float) -> void:
	match _fase:
		Fase.ATTESA_SCENA:
			_aggancia_scena()
		Fase.GIOCA:
			_passo()

func _aggancia_scena() -> void:
	var s := get_tree().current_scene
	if s == null:
		return
	oss = Osservatore.new()
	if not oss.aggancia(s, s.scene_file_path):
		return
	_scena = s.scene_file_path
	var primo_aggancio := esec == null
	esec = Esecutore.new(oss)
	sorv = Sorveglianti.new(oss)
	_collega_segnali()
	if not primo_aggancio:
		## Riaggancio dopo un ricaricamento: file, viste e contatori restano.
		oss.tick = _tick
		_fase = Fase.GIOCA
		return
	_prepara_viste()
	if _scen:
		_scen.ponte = self
		_scen.prepara(oss)
	_f_azioni = FileAccess.open(_out + ("/azioni_replay.jsonl" if _replay_attivo else "/azioni.jsonl"), FileAccess.WRITE)
	_f_tele = FileAccess.open(_out + ("/telemetria_replay.jsonl" if _replay_attivo else "/telemetria.jsonl"), FileAccess.WRITE)
	_f_colpi = FileAccess.open(_out + ("/colpi_replay.jsonl" if _replay_attivo else "/colpi.jsonl"), FileAccess.WRITE)
	_invia({"tipo": "ciao", "scena": _scena, "seme": int(_arg.get("seme", "1")), "decidi_ogni": _decidi_ogni,
		"tappe": oss.percorso.get("tappe", []).size(), "replay": _replay_attivo})
	_fase = Fase.GIOCA

func _passo() -> void:
	## La scena si e' ricaricata (morte senza un Cono acceso: il director
	## ricarica il livello). Il player vecchio non esiste piu': ci si riaggancia
	## alla scena nuova invece di leggere un'istanza liberata a ogni tick.
	if not is_instance_valid(oss.player) or not oss.player.is_inside_tree():
		print("PLAYTEST: scena ricaricata al tick %d, mi riaggancio" % _tick)
		_fase = Fase.ATTESA_SCENA
		return
	_tick += 1
	oss.tick = _tick
	oss.aggiorna_memoria_nemici()
	if _scen:
		_scen.al_tick(_tick, oss)
	if _morto and not bool(oss.player.get("is_dead")):
		_morto = false
	_avanza_tappe()

	var tel : Dictionary = oss.telemetria()
	_storia.append(tel)
	if _storia.size() > int(STORIA_S * Engine.physics_ticks_per_second):
		_storia.pop_front()
	_impronta = (_impronta + JSON.stringify(tel)).md5_text()

	for a in sorv.controlla(_tick):
		_segnala(a)
	## Ogni colpo, dato o subito, in numeri: angolo, distanza, cosa faceva il player.
	while not sorv.colpi.is_empty() and int(sorv.colpi[0]["tick"]) < _tick - 1:
		var c : Dictionary = sorv.colpi.pop_front()
		c.erase("_giudicato")
		_scrivi(_f_colpi, c)

	if _tocca_decidere():
		_decidi(tel)
		_prossima = _tick + (DECIDI_IN_MISCHIA if _in_mischia() else _decidi_ogni)
		if _fase != Fase.GIOCA:
			return
	esec.applica(_tick)

	var esito := ""
	if _scen and _tick >= _max_tick:
		esito = "scenario_finito"
	elif _replay_attivo and _tick > _ultimo_replay + _decidi_ogni:
		esito = "fine_replay"
	elif oss.tappa >= oss.percorso.get("tappe", []).size():
		esito = "completato"
	elif _tick >= _max_tick:
		esito = "tempo_scaduto"
	elif _morti >= _max_morti:
		esito = "troppe_morti"
	if esito != "":
		_chiudi(esito)


func _avanza_tappe() -> void:
	var tappe : Array = oss.percorso.get("tappe", [])
	while oss.tappa < tappe.size() and oss.tappa_fatta(tappe[oss.tappa]):
		_tappe_fatte.append({"tappa": oss.tappa, "tick": _tick, "secondi": snappedf(_tick / float(Engine.physics_ticks_per_second), 0.01)})
		oss.evento("objective completed: " + str(tappe[oss.tappa].get("testo", "")))
		print("PLAYTEST: tappa %d fatta al tick %d" % [oss.tappa, _tick])
		oss.tappa += 1


## ─── Una decisione ──────────────────────────────────────────────────────────

func _decidi(tel : Dictionary) -> void:
	var p : CharacterBody3D = oss.player
	var menu := _menu_aperto()
	var azioni : Array = esec.azioni_disponibili(menu)
	var scelta := "move_on"
	var fonte := "codice"
	var risposta := {}
	if bool(p.get("is_dead")):
		scelta = "wait"
	elif _replay_attivo:
		scelta = str(_replay.get(_tick, "wait"))
		fonte = "replay"
	elif _scen:
		scelta = str(_scen.azione(_tick, oss))
		fonte = "scenario"
	elif _serve_jev(menu):
		var extra := {
			"path_ahead": esec.sentiero,
			"within_reach": _o(esec.qualcosa_a_portata(), "nothing"),
			"menu_open": menu,
		}
		var stato : Dictionary = oss.stato_per_jev(azioni, extra)
		_invia({"tipo": "stato", "tick": _tick, "stato": stato, "criteri": esec.criteri(azioni)})
		risposta = _ricevi()
		_jev_chiamate += 1
		if risposta.is_empty():
			_jev_errori += 1
			scelta = "wait"
			fonte = "errore"
		else:
			scelta = str(risposta.get("azione", "wait"))
			fonte = str(risposta.get("fonte", "jev"))
			if not scelta in azioni:
				scelta = "wait"
				fonte = "fuori_lista"
	esec.scegli(scelta, _tick)
	oss.ultime_azioni.append(scelta)
	if oss.ultime_azioni.size() > 12:
		oss.ultime_azioni.pop_front()
	_scrivi(_f_azioni, {"tick": _tick, "azione": scelta, "fonte": fonte})
	_scrivi(_f_tele, tel)
	if bool(risposta.get("cattura", false)):
		_cattura("jev_%06d" % _tick, p.global_position, {"motivo": risposta.get("motivo_cattura", ""), "tick": _tick})
	## L'orchestratore puo' fermare la partita (tetto di spesa, Ctrl+C).
	if bool(risposta.get("stop", false)):
		_chiudi("fermato: " + str(risposta.get("perche", "")))

## In replay si decide ESATTAMENTE ai tick registrati; dal vivo, alla cadenza.
func _tocca_decidere() -> bool:
	if _replay_attivo:
		return _replay.has(_tick)
	return _tick >= _prossima

## Con un nemico vivo e vicino la cadenza si stringe: la carica di un morso
## dura mezzo secondo, e a 0,2 s per decisione se ne perdeva un terzo prima
## di poter scegliere la schivata.
func _in_mischia() -> bool:
	for e in oss.nemici():
		if not e.is_dead() and (e.global_position - oss.player.global_position).length() < RAGGIO_MISCHIA:
			return true
	return false

## Jev si chiama solo quando c'e' davvero una scelta. Camminare lungo il
## sentiero vuoto e' una regola nota, e le regole note restano nel codice.
func _serve_jev(menu : bool) -> bool:
	if menu or bool(oss.player.get("input_fully_locked")):
		return true
	if esec.qualcosa_a_portata() != "" or esec.sentiero != "clear":
		return true
	for e in oss.nemici():
		if e.is_dead() or int(e.get("_state")) == 6:   ## FLEE
			continue
		if (e.global_position - oss.player.global_position).length() < RAGGIO_JEV:
			return true
	return false

func _menu_aperto() -> bool:
	if get_tree().root.get_node_or_null("ConeRestMenu") != null:
		return true
	var gm := get_node_or_null("/root/GameMenu")
	return gm != null and gm.has_method("is_blocking") and gm.is_blocking()

static func _o(s : String, altrimenti : String) -> String:
	return s if s != "" else altrimenti


## ─── Segnali del gioco → eventi per Jev e controlli ─────────────────────────

func _collega_segnali() -> void:
	var p : CharacterBody3D = oss.player
	if p.has_signal("damage_taken"):
		p.damage_taken.connect(func(by_what):
			sorv.colpo_subito(by_what)
			oss.evento("you took a hit"))
	if p.has_signal("death_started"):
		p.death_started.connect(_morte_del_player)
	var d = oss.director
	if d:
		if d.has_signal("player_respawned"):
			d.player_respawned.connect(func(_c): oss.evento("you came back to life at the last Channeling Cone"))
		if d.has_signal("checkpoint_activated"):
			d.checkpoint_activated.connect(func(_c): oss.evento("a Channeling Cone was activated"))
	get_tree().node_added.connect(_nodo_aggiunto)
	for e in oss.nemici():
		_collega_nemico(e)

## Il gruppo "arcanium_enemy" lo aggiunge il nemico nel SUO `_ready`, che
## arriva dopo `node_added`: si guarda un attimo dopo.
## Una morte si conta una volta sola. Un secondo `death_started` mentre il
## player e' ancora a terra e' un difetto del gioco (sorvegliante "morte
## ripetuta"): e' cosi' che il playtest del 2026-10-07 ha trovato i lupi che
## mordevano il cadavere, con tre "morti" in 2,7 s.
func _morte_del_player() -> void:
	if _morto:
		_segnala({"tick": _tick, "tipo": "morte_ripetuta", "soggetto": "player",
			"testo": "death_started di nuovo su un player gia' morto",
			"dati": {"hp": oss.player.health_system.current_health if oss.player.get("health_system") else null,
				"pos": Sorveglianti._v(oss.player.global_position)}})
		return
	_morto = true
	_morti += 1
	oss.evento("you died")
	print("PLAYTEST: morte %d al tick %d" % [_morti, _tick])

func _nodo_aggiunto(n : Node) -> void:
	if oss and n is CharacterBody3D:
		_forse_nemico.call_deferred(n)

func _forse_nemico(n : Node) -> void:
	if is_instance_valid(n) and n.is_in_group("arcanium_enemy") and not n.has_meta("_playtest_collegato"):
		_collega_nemico(n)
		oss.evento("a new %s appeared" % oss.nome_nemico(n))

func _collega_nemico(e : Node) -> void:
	if not is_instance_valid(e) or e.has_meta("_playtest_collegato"):
		return
	e.set_meta("_playtest_collegato", true)
	if e.has_signal("death_started"):
		e.death_started.connect(func(): oss.evento("%s died" % oss.nome_nemico(e)))
	if e.has_signal("damage_taken"):
		e.damage_taken.connect(func(w):
			sorv.colpo_dato(e, w)
			oss.evento("you hit %s" % oss.nome_nemico(e)))
	if e.has_signal("howl_summon"):
		e.howl_summon.connect(func(): oss.evento("%s howled" % oss.nome_nemico(e)))


## ─── Segnalazioni e catture ─────────────────────────────────────────────────

func _segnala(a : Dictionary) -> void:
	_segnalazioni += 1
	var id := "%06d_%s" % [a["tick"], str(a["tipo"])]
	var cartella := _out + "/segnalazioni/" + id
	DirAccess.make_dir_recursive_absolute(cartella)
	var pacco := a.duplicate(true)
	pacco["ultime_azioni"] = oss.ultime_azioni.duplicate()
	pacco["tappa"] = oss.tappa
	pacco["storia"] = _storia.duplicate(true)
	var f := FileAccess.open(cartella + "/telemetria.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(pacco, "  "))
	f.close()
	print("PLAYTEST: SEGNALAZIONE %s — %s" % [id, a["testo"]])
	var dove : Vector3 = oss.player.global_position
	var pos = a.get("dati", {}).get("pos")
	if pos is Array and pos.size() == 3:
		dove = Vector3(pos[0], pos[1], pos[2])
	_invia({"tipo": "segnalazione", "id": id, "tick": a["tick"], "allarme": a})
	_cattura(id, dove, {})

## Fotogrammi da tre angolazioni: la camera del gioco, di lato e dall'alto,
## puntate sul soggetto. Si scattano al frame disegnato SUCCESSIVO (la fisica
## avanza di un tick, e il tick vero e' scritto accanto).
func _prepara_viste() -> void:
	for nome in ["lato", "alto"]:
		var sv := SubViewport.new()
		sv.name = "Vista_" + nome
		sv.size = Vector2i(960, 540)
		sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cam := Camera3D.new()
		cam.current = true
		sv.add_child(cam)
		add_child(sv)
		_viste.append([nome, sv, cam])

func _cattura(id : String, dove : Vector3, extra : Dictionary) -> void:
	_catture_in_corso += 1
	var cartella := _out + "/segnalazioni/" + id
	DirAccess.make_dir_recursive_absolute(cartella)
	var tick_scatto := _tick
	for v in _viste:
		var cam : Camera3D = v[2]
		var sv : SubViewport = v[1]
		if v[0] == "lato":
			cam.look_at_from_position(dove + Vector3(5.0, 1.6, 0.0), dove + Vector3.UP * 0.8)
		else:
			cam.look_at_from_position(dove + Vector3(0.0, 9.0, 0.01), dove)
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(cartella + "/gioco.png")
	for v in _viste:
		(v[1] as SubViewport).get_texture().get_image().save_png(cartella + "/%s.png" % v[0])
	if not extra.is_empty():
		extra["tick_scatto"] = tick_scatto
		var f := FileAccess.open(cartella + "/cattura.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(extra, "  "))
		f.close()
	_catture_in_corso -= 1


## Per gli scenari: fotogrammi da tre angolazioni a un tick preciso, col nome
## scelto dallo scenario e la telemetria accanto. Finiscono nel set etichettato.
func cattura_scenario(nome : String, dove : Vector3) -> void:
	var id := "scen_%06d_%s" % [_tick, nome]
	var cartella := _out + "/segnalazioni/" + id
	DirAccess.make_dir_recursive_absolute(cartella)
	var f := FileAccess.open(cartella + "/telemetria.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"tick": _tick, "nome": nome, "storia": _storia.slice(-30)}, "  "))
	f.close()
	_cattura(id, dove, {"scenario": nome, "tick": _tick})


## ─── Fine partita ───────────────────────────────────────────────────────────

func _chiudi(esito : String) -> void:
	if _fase == Fase.FINE:
		return
	_fase = Fase.FINE
	esec.rilascia_tutto()
	var riepilogo := {
		"esito": esito, "scena": _scena, "seme": int(_arg.get("seme", "1")),
		"tick": _tick, "secondi_di_gioco": snappedf(_tick / float(Engine.physics_ticks_per_second), 0.01),
		"morti": _morti, "tappe_fatte": _tappe_fatte, "tappe_totali": oss.percorso.get("tappe", []).size(),
		"segnalazioni": _segnalazioni, "jev_chiamate": _jev_chiamate, "jev_errori": _jev_errori,
		"impronta_telemetria": _impronta, "replay": _replay_attivo,
	}
	if _scen:
		riepilogo["scenario"] = str(_arg["scenario"])
		var fe := FileAccess.open(_out + "/etichette.json", FileAccess.WRITE)
		fe.store_string(JSON.stringify(_scen.etichette, "  "))
		fe.close()
	var f := FileAccess.open(_out + ("/riepilogo_replay.json" if _replay_attivo else "/riepilogo_godot.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(riepilogo, "  "))
	f.close()
	print("PLAYTEST: FINE — %s al tick %d, impronta %s" % [esito, _tick, _impronta])
	_invia({"tipo": "fine", "riepilogo": riepilogo})
	while _catture_in_corso > 0:
		await RenderingServer.frame_post_draw
	if _f_azioni: _f_azioni.close()
	if _f_tele: _f_tele.close()
	if _f_colpi:
		for c in sorv.colpi:
			c.erase("_giudicato")
			_scrivi(_f_colpi, c)
		_f_colpi.close()
	## L'orchestratore chiude per primo dopo "fine": staccarsi da un socket
	## gia' chiuso stampa un ERROR che finirebbe fra i problemi del log.
	if _tcp:
		_tcp.poll()
		if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_tcp.disconnect_from_host()
	get_tree().quit(0)


## ─── Il socket ──────────────────────────────────────────────────────────────

func _connetti(porta : int) -> void:
	_tcp = StreamPeerTCP.new()
	_tcp.set_no_delay(true)
	_tcp.connect_to_host("127.0.0.1", porta)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		_tcp.poll()
		if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			return
		OS.delay_msec(10)
	push_error("PLAYTEST: nessun orchestratore sulla porta %d" % porta)
	get_tree().quit(4)

func _invia(msg : Dictionary) -> void:
	if _tcp == null:
		return
	_tcp.poll()
	_tcp.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())

## Aspetta UNA riga di risposta. Bloccante apposta: e' la modalita' discreta.
## (Il tempo qui e' di muro: e' l'attesa della rete, non del mondo.)
func _ricevi() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ATTESA_MAX_MS:
		_tcp.poll()
		var n := _tcp.get_available_bytes()
		if n > 0:
			_buf += _tcp.get_utf8_string(n)
		var i := _buf.find("\n")
		if i >= 0:
			var riga := _buf.substr(0, i)
			_buf = _buf.substr(i + 1)
			var v = JSON.parse_string(riga)
			return v if v is Dictionary else {}
		if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		OS.delay_msec(1)
	return {}

func _scrivi(f : FileAccess, d : Dictionary) -> void:
	if f:
		f.store_line(JSON.stringify(d))

func _carica_replay(percorso : String) -> void:
	var f := FileAccess.open(percorso, FileAccess.READ)
	if f == null:
		push_error("PLAYTEST: replay non trovato: " + percorso)
		get_tree().quit(5)
		return
	while not f.eof_reached():
		var riga := f.get_line()
		if riga.strip_edges() == "":
			continue
		var r = JSON.parse_string(riga)
		if r is Dictionary:
			_replay[int(r["tick"])] = str(r["azione"])
			_ultimo_replay = maxi(_ultimo_replay, int(r["tick"]))
	_replay_attivo = true
