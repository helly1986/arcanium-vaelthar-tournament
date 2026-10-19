extends Node3D

## Battle Playground — banco di prova per le mosse del boss.
##
## Perché esiste: il boss sceglie le mosse a caso, pesate, con cooldown e catene.
## Aspettare che il random peschi quella che vuoi testare è una lotteria — in un
## log di 70 secondi di gioco reale la mossa A2 è uscita UNA volta sola. Con
## mini-boss e nemici diversi il problema si moltiplica: testarli tutti
## empiricamente non è praticabile. Qui premi un bottone e parte quella mossa.
##
## Scelta di progetto: questo playground ISTANZIA L'ARENA VERA, non ricostruisce
## un ambiente simile. Un banco di prova che diverge dall'ambiente reale mente, ed
## è peggio che non averlo — è già successo: `arena_senza_fuoco.tscn` sovrascrive
## `anim_speed_scale = 0.5` sull'istanza del boss, mentre `senza_nome.tscn` da
## sola dichiara 1.0, e un giro di misure fatte sulla scena isolata ha prodotto
## numeri sbagliati del doppio. Istanziando l'arena, quello che provi qui è
## esattamente quello che giochi.
##
## Niente slider: le variabili si toccano dall'inspector di Godot sulla scena.
##
## I bottoni sono generati in ciclo dal move set, quindi vale già per qualunque
## nemico data-driven futuro: basta puntare `enemy_group`.

## Gruppo in cui cercare il nemico da pilotare.
@export var enemy_group : String = "targets"
## Se true, all'avvio spegne l'AI: il boss ti insegue e si gira, ma attacca solo
## quando premi un bottone. È il punto del banco di prova.
@export var disable_ai : bool = true

## Rigenerazione dell'Arcanium Vivo (al secondo) FORZATA nel banco di prova:
## serve a provare gli incantesimi uno dietro l'altro senza restare a secco.
## ⚠️ È una comodità del playground, non una regola del gioco: nel gioco vero
## l'Arcanium Vivo NON si rigenera da solo (PlayerVitals.arcanium_regen resta 0).
## Lo forniranno i summon tramite il channeling, il sacrificio di arcanium
## cristallizzato e alcune pozioni/oggetti non comuni.
@export var arcanium_regen_per_sec : float = 15.0
## Sblocca TUTTE le evocazioni all'avvio, per provarle qui. ⚠️ Comodita' del
## playground: nel gioco le insegnava il Maestro di Evocazioni del Crocevia, che
## non c'e' piu'; nel roguelike arriveranno come ricompense della run.
@export var sblocca_evocazioni : bool = true

const SUMMON_DIR := "res://arcanium/resources/summons/"

var _enemy : Node = null
var _status : Label = null
## Le mosse nell'ordine dei bottoni: l'indice è anche la hotkey (1..9).
var _move_ids : PackedStringArray = []
## Il nodo che cattura il mouse e ruota la camera. Trovato per duck-typing (ha
## `mouse_control`), come fa il resto del progetto.
var _cam : Node = null
var _player : Node = null
var _mouse_free : bool = false
## Se true, la mossa forzata si porta dietro il grafo delle catene (come in gioco).
var _allow_chain : bool = false

func _ready() -> void:
	# NIENTE await qui: i figli dell'arena hanno già fatto il loro _ready quando
	# tocca al padre, quindi il boss è già nel gruppo. Aspettare un frame gli
	# lasciava il tempo di lanciare un attacco PRIMA che spegnessimo l'AI, e poi
	# `debug_force_move` lo trovava occupato e rifiutava il primo comando.
	if sblocca_evocazioni:
		_sblocca_evocazioni()
	_enemy = get_tree().get_first_node_in_group(enemy_group)
	if _enemy == null:
		push_warning("BattlePlayground: nessun nodo nel gruppo '%s'" % enemy_group)
		return
	if disable_ai and "ai_enabled" in _enemy:
		_enemy.ai_enabled = false
	_cam = _find_camera_rig()
	_player = get_tree().get_first_node_in_group("player")
	_enable_arcanium_regen()
	_build_ui()

## Alza l'`unlock_flag` di ogni evocazione in SUMMON_DIR: SpellSelection ascolta
## PlayerFlags.changed e le aggiunge subito alla barra.
func _sblocca_evocazioni() -> void:
	var flags := get_node_or_null("/root/PlayerFlags")
	if flags == null:
		return
	var dir := DirAccess.open(SUMMON_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var res := load(SUMMON_DIR + f)
		var gate : String = res.unlock_flag if res != null and "unlock_flag" in res else ""
		if gate != "" and not flags.has(gate):
			flags.set_flag(gate)


## Accende la rigenerazione dell'Arcanium Vivo sul player di QUESTA scena.
## Si tocca l'istanza, non la risorsa condivisa: il gioco vero resta a secco
## com'è giusto che sia.
func _enable_arcanium_regen() -> void:
	if _player == null or arcanium_regen_per_sec <= 0.0:
		return
	var vitals = _player.get("vitals")
	if vitals == null or not ("arcanium_regen" in vitals):
		push_warning("BattlePlayground: PlayerVitals non trovato, Arcanium non rigenerato.")
		return
	vitals.arcanium_regen = arcanium_regen_per_sec
	## Si parte col serbatoio pieno, così la prima prova non aspetta.
	if "max_arcanium" in vitals and "arcanium" in vitals:
		vitals.arcanium = vitals.max_arcanium

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# In ALTO A DESTRA: l'HUD del gioco (vita, arcanium) sta a sinistra e si
	# sovrapponeva.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-300, 12)
	panel.custom_minimum_size = Vector2(288, 0)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "PLAYGROUND — %s" % _enemy.name
	box.add_child(title)

	var help := Label.new()
	help.text = "TAB = libera/cattura il mouse\nF12 = AI on/off | F1..F9 = lancia la mossa"
	box.add_child(help)

	_status = Label.new()
	box.add_child(_status)

	# Di default il tasto lancia UNA mossa. Col grafo delle catene attivo, F1
	# lanciava A1→A2 (e A3→A1→A2: tre colpi da un tasto), che è il gioco vero ma
	# rende impossibile isolare una mossa — l'utente lo leggeva come "colpi
	# rimasti appesi nella catena". Qui si sceglie.
	var chain_cb := CheckBox.new()
	chain_cb.text = "Consenti catene (come in gioco)"
	chain_cb.button_pressed = _allow_chain
	chain_cb.focus_mode = Control.FOCUS_NONE
	chain_cb.toggled.connect(func(v : bool) -> void:
		_allow_chain = v
		_refresh_status())
	box.add_child(chain_cb)

	box.add_child(HSeparator.new())

	var ms = _enemy.get("move_set")
	if ms == null:
		return
	# Un bottone per mossa, generati dal move set: nessun elenco da tenere
	# aggiornato a mano quando il moveset cambia o quando arriva un altro nemico.
	var i := 0
	for m in ms.moves:
		i += 1
		_move_ids.append(m.id)
		var b := Button.new()
		var etichetta : String = m.name if m.name != "" else m.id
		b.text = "[F%d] %s — %s (pot %d)" % [i, m.id, etichetta, m.power]
		b.pressed.connect(_fire.bind(m.id))
		# Coi bottoni non focalizzabili, i tasti numerici restano hotkey e non
		# finiscono nel bottone che ha il focus.
		b.focus_mode = Control.FOCUS_NONE
		box.add_child(b)
	_refresh_status()

## TAB libera il mouse per cliccare i bottoni. Non basta cambiare `mouse_mode`:
## la follow cam ruota su InputEventMouseMotion e, col mouse libero, la
## telecamera impazzirebbe mentre clicchi. Le spegniamo l'input finché serve.
##
## Hotkey su F1..F9 e non sui numeri: **1 e 2 sono già `change_item`** nel project
## input map, quindi premere "1" avrebbe cambiato l'arma del player OLTRE a
## lanciare la mossa. F1-F12 sono liberi (verificato sull'input map).
func _unhandled_input(event : InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k : int = (event as InputEventKey).keycode
	if k == KEY_TAB:
		_toggle_mouse()
		get_viewport().set_input_as_handled()
	elif k == KEY_F12:
		_toggle_ai()
	elif k >= KEY_F1 and k <= KEY_F9:
		var idx : int = k - KEY_F1
		if idx < _move_ids.size():
			_fire(_move_ids[idx])

func _toggle_mouse() -> void:
	_mouse_free = not _mouse_free
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _mouse_free else Input.MOUSE_MODE_CAPTURED
	if _cam:
		_cam.set_process_input(not _mouse_free)
	# Il player legge i comandi in `_input(event)`, che gira PRIMA della GUI: il
	# click sul bottone arrivava al protagonista prima che il bottone lo
	# consumasse, e faceva partire l'attacco leggero insieme alla mossa del boss.
	# Spegnergli `_input` risolve alla radice. Il movimento resta vivo (non passa
	# da lì), così puoi posizionarti col mouse libero.
	if _player:
		_player.set_process_input(not _mouse_free)
	_refresh_status()

func _find_camera_rig() -> Node:
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n.has_method("mouse_control"):
			return n
	return null

func _fire(id : String) -> void:
	if _enemy == null or not _enemy.has_method("debug_force_move"):
		return
	var ok : bool = _enemy.debug_force_move(id, _allow_chain)
	_refresh_status("%s: %s" % [id, "partita" if ok else "RIFIUTATA (gia' occupato)"])

func _toggle_ai() -> void:
	if _enemy == null or not ("ai_enabled" in _enemy):
		return
	_enemy.ai_enabled = not _enemy.ai_enabled
	_refresh_status()

## La distanza si aggiorna in tempo reale: è il numero che mancava. Nel log della
## prima sessione OGNI mancato era a dist=0.95 — il player era incollato al boss
## (capsula r=0.55 + player ~0.4), dentro il raggio dell'arco delle spadate.
## Senza vederla a schermo, non si sa a che distanza si sta testando.
func _process(_delta : float) -> void:
	_refresh_status(_last_msg)

var _last_msg : String = ""

func _refresh_status(msg : String = "") -> void:
	_last_msg = msg
	if _status == null:
		return
	var ai : bool = _enemy.ai_enabled if ("ai_enabled" in _enemy) else true
	var dist := 0.0
	if _player and _enemy and _player is Node3D and _enemy is Node3D:
		var a : Vector3 = (_player as Node3D).global_position
		var b : Vector3 = (_enemy as Node3D).global_position
		dist = Vector2(a.x - b.x, a.z - b.z).length()
	_status.text = "AI: %s | mouse: %s | catene: %s\ndistanza dal boss: %.2f m%s" % [
		"accesa" if ai else "SPENTA",
		"LIBERO" if _mouse_free else "gioco",
		"SI" if _allow_chain else "no",
		dist,
		"\n" + msg if msg != "" else ""]
