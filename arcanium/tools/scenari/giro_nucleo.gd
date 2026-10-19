extends "res://arcanium/tools/scenari/scenario.gd"

## ═══════════════════════════════════════════════════════════════════════════
## SCENARIO: il giro del nucleo — quello che il roguelike eredita, in un minuto
## ═══════════════════════════════════════════════════════════════════════════
##
## Nato a fine pulizia (2026-10-19): tolti Kalvorn, Traccia, Crocevia, hub e
## quest, resta da GUARDARE che il nucleo regga. Nell'arena del branco, coi tasti
## veri (l'esecutore passa dall'InputMap come un pad):
##   1. il giocatore cammina verso il branco e la camera lo segue;
##   2. prende il Sigillo in mano, sceglie un'evocazione, la piazza e la evoca
##      (prima dello scontro: uno stordimento dei lupi ignora i comandi);
##   3. aggancia (lock-on) un lupo;
##   4. attacca, leggero e pesante, e i lupi combattono;
##   5. schiva;
##   6. l'evocazione resta in campo (che combatta lo prova verifica_eco_guasta:
##      "l'Eco evocata lancia la Radice sul nemico, e la radice lo ferisce").
## A fine giro stampa: Sigillo preso, evocazioni nate, lupi vivi, danno fatto
## dal giocatore (lupo a meno di 3.5 m da lui) e altrove (dall'evocazione).
## Esito del 2026-10-19: Sigillo al tick 178, 1 evocazione, 146 di danno,
## un lupo ucciso; fotogrammi guardati.
## Un fotogramma per passo (cattura_scenario). Il giocatore regge tutto: la
## prova e' sulle meccaniche, non sulla sopravvivenza.
##
## Lancio: python arcanium/tools/playtest/gioca.py --scenario giro_nucleo
##
## ⚠️ Le evocazioni le insegnava il Maestro del Crocevia, che non c'e' piu':
## qui si alzano a mano i loro `unlock_flag`, come fa il battle_playground.

const VITA := 1000000
const SUMMON_DIR := "res://arcanium/resources/summons/"

## Il copione: [da_tick, azione]. Ogni decisione (ogni 12 tick) prende l'ultima
## voce cominciata. "sigillo", "evoca", "conferma" non sono azioni di Jev:
## sono tasti battuti da qui (vedi al_tick), e intanto l'esecutore aspetta.
const COPIONE := [
	[0, "wait"],
	[30, "sigillo"],
	[320, "approach"],
	[480, "lock_on"],
	[490, "attack_light"],
	[610, "attack_heavy"],
	[720, "dodge"],
	[760, "approach"],
	[840, "attack_light"],
	[1200, "wait"],
]

var _premuti : Array = []         ## [azione, tick di rilascio]
var _evocazioni_prima := 0
var _focus_preso := false
var _ultimo_cambio := -1000
var _focus_al := -1                  ## tick in cui il Sigillo e' arrivato in mano
var _hp_prima : Dictionary = {}     ## nemico -> vita al tick precedente
var _danno_vicino := 0.0              ## a meno di 3.5 m dal giocatore: suo
var _danno_lontano := 0.0             ## piu' lontano: dell'evocazione


func _init() -> void:
	scena = "res://arcanium/levels/arena_branco.tscn"
	durata = 1300


func prepara(oss) -> void:
	porta_player(oss, Vector3(0.0, 0.3, 12.0))
	_rendi_robusto(oss)
	var flags : Node = oss.player.get_node_or_null("/root/PlayerFlags")
	if flags != null:
		for f in DirAccess.get_files_at(SUMMON_DIR):
			if f.ends_with(".tres"):
				var res := load(SUMMON_DIR + f)
				if res != null and "unlock_flag" in res and str(res.unlock_flag) != "":
					flags.set_flag(res.unlock_flag)
	_evocazioni_prima = oss.player.get_tree().get_nodes_in_group("arcanium_minion").size()
	etichetta("pulito", "player", 0, durata, "giro del nucleo: nessun difetto atteso")


func _rendi_robusto(oss) -> void:
	var hs = oss.player.get("health_system")
	if hs == null:
		return
	if float(hs.current_health) < VITA / 2.0:
		hs.total_health = VITA
		if hs.has_method("heal"):
			hs.heal(float(VITA))
		else:
			hs.current_health = VITA


func _voce(tick : int) -> String:
	var v := "wait"
	for r in COPIONE:
		if tick >= int(r[0]):
			v = str(r[1])
	return v


func _premi(azione : String, tick : int, per : int = 3) -> void:
	var ev := InputEventAction.new()
	ev.action = azione
	ev.pressed = true
	Input.parse_input_event(ev)
	_premuti.append([azione, tick + per])


func al_tick(tick : int, oss) -> void:
	_rendi_robusto(oss)
	for p in _premuti.duplicate():
		if tick >= int(p[1]):
			var ev := InputEventAction.new()
			ev.action = str(p[0])
			ev.pressed = false
			Input.parse_input_event(ev)
			_premuti.erase(p)
	var pl : Node3D = oss.player
	var voce := _voce(tick)
	## Il Sigillo: si cambia gadget finche' non c'e' il focus degli incantesimi.
	if voce == "sigillo" and not _focus_preso:
		if pl.has_method("has_spell_focus") and pl.has_spell_focus():
			_focus_preso = true
			_focus_al = tick
			print("PLAYTEST: Sigillo in mano al tick %d" % tick)
		elif tick - _ultimo_cambio >= 60 and pl.is_on_floor() 				and pl.get("current_state") == pl.get("state").FREE:
			## Solo a terra e LIBERO: all'avvio c'e' il gesto di comparsa, e
			## gadget_change() ignora il tasto finche' dura.
			## Il cambio di gadget ha il suo gesto: premere di nuovo prima che
			## finisca fa girare la ruota OLTRE il Sigillo.
			_ultimo_cambio = tick
			_premi("change_secondary", tick)
	## Chi fa danno ai lupi: vicino al giocatore e' lui, lontano e' l'evocazione.
	for e in oss.nemici():
		var hp : float = float(e.health_system.current_health) if e.get("health_system") != null else 0.0
		var k : int = e.get_instance_id()
		if _hp_prima.has(k) and hp < float(_hp_prima[k]):
			var d : float = Vector2(e.global_position.x - pl.global_position.x, e.global_position.z - pl.global_position.z).length()
			if d < 3.5:
				_danno_vicino += float(_hp_prima[k]) - hp
			else:
				_danno_lontano += float(_hp_prima[k]) - hp
		_hp_prima[k] = hp
	## Col Sigillo in mano il lancio e' il tasto DESTRO (use_gadget_light), non
	## cast_spell: vedi _input in player_charbody3D.gd.
	if _focus_al >= 0:
		if tick == _focus_al + 10:
			_premi("select_mode_summon", tick)
		if tick == _focus_al + 25:
			_premi("use_gadget_light", tick)
		if tick == _focus_al + 70:
			_premi("cast_confirm", tick)
		if tick == _focus_al + 45:
			ponte.cattura_scenario("02_piazzamento", pl.global_position)
		if tick == _focus_al + 120:
			ponte.cattura_scenario("03_evocazione", pl.global_position)
	## I fotogrammi.
	var dove : Vector3 = pl.global_position
	match tick:
		400: ponte.cattura_scenario("04_cammina", dove)
		500: ponte.cattura_scenario("05_aggancio", dove)
		550: ponte.cattura_scenario("06_attacco_leggero", dove)
		660: ponte.cattura_scenario("07_attacco_pesante", dove)
		730: ponte.cattura_scenario("08_schivata", dove)
		1100: ponte.cattura_scenario("09_evocazione_combatte", dove)
	if tick == durata - 1:
		var minion := pl.get_tree().get_nodes_in_group("arcanium_minion").size() - _evocazioni_prima
		var agganciato : bool = pl.has_method("lock_on_target") and pl.lock_on_target() != null
		print("PLAYTEST: giro_nucleo — Sigillo %s, evocazioni nate %d, lupi vivi %d, danno del giocatore %.0f, danno altrui (evocazione) %.0f" % [
			"si" if _focus_preso else "NO", minion,
			oss.nemici().filter(func(e): return not e.is_dead()).size(), _danno_vicino, _danno_lontano])
		if not agganciato:
			print("PLAYTEST: giro_nucleo — a fine giro nessun bersaglio agganciato")


func azione(tick : int, _oss) -> String:
	var v := _voce(tick)
	if v in ["sigillo", "evoca", "conferma"]:
		return "wait"
	return v
