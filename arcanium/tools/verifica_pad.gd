extends SceneTree

## Cancello del GAMEPAD (Xbox, indici SDL di Godot): 0 A, 1 B, 2 X, 3 Y,
## 4 View, 6 Start, 8 R3, 9 LB, 10 RB, 11-14 croce su/giu'/sx/dx; assi 0-1
## stick sinistro, 2-3 destro, 4 LT, 5 RT.
##
## Parte A, la MAPPA: ogni azione di gioco ha un evento del pad, e nessun
## bottone serve due azioni dello stesso momento (in gioco, a menu chiuso).
## Gli stessi bottoni servono di nuovo nel menu e nel piazzamento: li' il
## personaggio e' fermo, ed e' voluto.
##
## Parte B, il MENU con eventi del pad veri (Input.parse_input_event): a menu
## chiuso la croce giu' scorre il quick-slot; Start apre, e allora la croce
## scorre il menu e non il quick-slot; B chiude, e a menu chiuso B non apre
## niente.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_pad.gd

## Le azioni che un giocatore col pad deve poter fare.
const SUL_PAD := [
	"move_up", "move_down", "move_left", "move_right",
	"cam_rotate_left", "cam_rotate_right", "cam_zoom_in", "cam_zoom_out",
	"use_weapon_light", "use_weapon_strong", "use_gadget_light", "use_gadget_strong",
	"lucida_tecnica", "dodge_dash", "jump", "interact", "use_item", "lock_on",
	"change_primary", "change_secondary", "select_next", "item_next",
	"toggle_game_menu", "menu_tab_prev", "menu_tab_next", "inv_prev", "inv_next",
	"menu_confirm", "menu_back", "cast_confirm", "cast_cancel", "ui_cancel",
]
## Le azioni a bottone del gioco libero: due di queste sullo stesso bottone
## partirebbero insieme.
const IN_GIOCO := [
	"use_weapon_light", "use_gadget_light", "dodge_dash", "jump", "interact",
	"use_item", "lock_on", "change_primary", "change_secondary", "select_next",
	"item_next", "toggle_game_menu", "ui_cancel",
]
const ATTESE := 8

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("PAD: %s %s" % ["ok  " if cond else "NO  ", cosa])


func _pad(a : String) -> Array:
	var out := []
	for e in InputMap.action_get_events(a):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			out.append(e)
	return out


func _premi(b : int) -> void:
	for giu in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = b
		e.pressed = giu
		e.pressure = 1.0 if giu else 0.0
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		await process_frame


func _init() -> void:
	await process_frame
	## A — la mappa
	var senza := []
	for a in SUL_PAD:
		if not InputMap.has_action(a) or _pad(a).is_empty():
			senza.append(a)
	_ok(senza.is_empty(), "ogni azione di gioco ha il pad%s" % ("" if senza.is_empty() else " (mancano %s)" % str(senza)))
	var chi := {}
	var doppi := []
	for a in IN_GIOCO:
		for e in _pad(a):
			if e is InputEventJoypadButton:
				var b : int = e.button_index
				if chi.has(b) and chi[b] != a:
					doppi.append("%d: %s+%s" % [b, chi[b], a])
				chi[b] = a
	_ok(doppi.is_empty(), "nessun bottone fa due cose in gioco%s" % ("" if doppi.is_empty() else " (%s)" % str(doppi)))
	var croce_su := false
	for e in _pad("cast_spell"):
		croce_su = croce_su or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_UP)
	_ok(not croce_su, "la croce su e' solo del ciclo magie")

	## B — il menu, con eventi del pad
	var menu : Node = root.get_node_or_null("GameMenu")
	var inv : Node = root.get_node_or_null("ArcaniumInventory")
	if menu == null or inv == null:
		_ok(false, "autoload GameMenu e ArcaniumInventory presenti")
		_fine()
		return
	## Il controllo del quick-slot vale solo se a menu chiuso la croce giu' lo
	## scorre davvero: con meno di due consumabili passerebbe a vuoto.
	inv.add(load("res://arcanium/resources/items/bende_eco.tres"), 1, true)
	var prima : int = inv.active_index
	await _premi(JOY_BUTTON_DPAD_DOWN)
	_ok(inv.consumable_slots().size() >= 2 and inv.active_index != prima,
			"a menu chiuso la croce giu' scorre il quick-slot (%d consumabili)" % inv.consumable_slots().size())
	await _premi(JOY_BUTTON_START)
	_ok(menu.is_open, "Start apre il menu")
	prima = inv.active_index
	await _premi(JOY_BUTTON_DPAD_DOWN)
	_ok(inv.active_index == prima, "a menu aperto la croce giu' non scorre il quick-slot")
	await _premi(JOY_BUTTON_B)
	_ok(not menu.is_open, "B chiude il menu")
	await _premi(JOY_BUTTON_B)
	_ok(not menu.is_blocking(), "a menu chiuso B non apre niente")
	_fine()


func _fine() -> void:
	if _fatti < ATTESE:
		_falliti += 1
		print("PAD: NO   eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("VERIFICA_PAD: %s (%d/%d)" % ["OK" if _falliti == 0 else "FALLITA", _fatti - _falliti, _fatti])
	quit(1 if _falliti else 0)
