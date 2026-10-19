extends Node
class_name SpellSelection

## Selezione di spell/summon del player, via rotellina del mouse o hotkey.
## NON lancia nulla: solo tiene indice + modalità corrente ed emette
## `selection_changed` quando la selezione cambia. Il lancio effettivo (su
## azione input `cast_spell`) è responsabilità del player controller, che deve
## leggere `current_spell` e passarlo al proprio SpellCaster (altro stream).
##
## Duck-typing verso le resource: qui NON importiamo/referenziamo
## SpellResource/SpellCaster (sono di un altro stream, e potrebbero non
## esistere ancora). Le spell note vengono caricate come Resource generiche
## dai .tres trovati in `res://arcanium/resources/spells/`; se quella cartella
## non esiste ancora (caso attuale, 2026-07-22) la lista resta vuota e
## l'intero sistema degrada in modo silenzioso (nessun errore, semplicemente
## nessuna spell selezionabile finché un altro stream non popola la cartella).
##
## I summon non hanno ancora una cartella/risorsa dedicata: `known_summons`
## resta vuota finché un altro stream non la introduce. Il codice qui è già
## pronto a scansionare `res://arcanium/resources/summons/` non appena esiste
## (stesso pattern di `_scan_spell_dir`), ma quella dir non viene creata da
## questo file per non invadere territorio di altri stream.

const SPELL_DIR := "res://arcanium/resources/spells/"
const SUMMON_DIR := "res://arcanium/resources/summons/"

enum Kind { SPELL, SUMMON }

## Lista di Resource (duck-typed: qualunque .tres in SPELL_DIR/SUMMON_DIR).
var known_spells : Array[Resource] = []
var known_summons : Array[Resource] = []

var _spell_index : int = -1
var _summon_index : int = -1

## Modalità corrente: Kind.SPELL o Kind.SUMMON. Determina cosa muovono
## select_next/select_prev e cosa restituisce current().
var mode : int = Kind.SPELL

## current_spell / current_summon: la resource attualmente selezionata in
## ciascuna lista (indipendentemente dalla modalità corrente), o null se la
## lista è vuota. Sempre allineate a _spell_index / _summon_index.
var current_spell : Resource = null
var current_summon : Resource = null

## kind: "spell" o "summon". resource: la Resource selezionata (o null).
signal selection_changed(kind : String, resource : Resource)

func _ready() -> void:
	known_spells = _scan_dir(SPELL_DIR)
	known_summons = _scan_unlocked_summons()
	if not known_spells.is_empty():
		_spell_index = 0
		current_spell = known_spells[0]
	if not known_summons.is_empty():
		_summon_index = 0
		current_summon = known_summons[0]
	## Un summon può portare un `unlock_flag` (vedi SummonSpellResource): finché
	## non è impostato in PlayerFlags (tipicamente da un dialogo, es. il Maestro
	## di Evocazioni), quel summon resta FUORI da known_summons. Riascoltiamo
	## PlayerFlags.changed per farlo apparire subito, senza reload di scena, non
	## appena il flag scatta — degrada in silenzio se l'autoload non c'è ancora.
	var flags := get_node_or_null("/root/PlayerFlags")
	if flags and flags.has_signal("changed"):
		flags.changed.connect(_on_player_flags_changed)

## Scansiona SUMMON_DIR e filtra via i summon il cui `unlock_flag` (se non
## vuoto) non è ancora impostato in PlayerFlags. Nessun `unlock_flag` (stringa
## vuota) o PlayerFlags assente → sempre incluso (fallback permissivo, coerente
## col resto del file: nessuna dir/flag ancora pronti non deve mai bloccare).
func _scan_unlocked_summons() -> Array[Resource]:
	var all := _scan_dir(SUMMON_DIR)
	var flags := get_node_or_null("/root/PlayerFlags")
	var out : Array[Resource] = []
	for res in all:
		var gate : String = res.unlock_flag if ("unlock_flag" in res) else ""
		if gate == "" or (flags != null and flags.has(gate)):
			out.append(res)
	return out

## Richiamato a OGNI PlayerFlags.changed (qualunque flag, non solo i nostri):
## ri-scansiona i summon sbloccati e, se la lista cambia, aggiorna indice/
## selezione corrente ed emette selection_changed così SpellBar/HUD si
## aggiornano subito (vedi spell_bar.gd._on_selection_changed che ora
## ripopola gli slot ad ogni evento, non solo al bind iniziale).
func _on_player_flags_changed() -> void:
	var refreshed := _scan_unlocked_summons()
	if refreshed.size() == known_summons.size():
		return  ## nessun nuovo/rimosso: evita di spammare selection_changed
	known_summons = refreshed
	if known_summons.is_empty():
		_summon_index = -1
		current_summon = null
	else:
		if _summon_index < 0 or _summon_index >= known_summons.size():
			_summon_index = 0
		current_summon = known_summons[_summon_index]
	selection_changed.emit("summon", current_summon)

## Scansiona una directory di risorse .tres/.res e le carica come Resource
## generiche. Ritorna array vuoto se la dir non esiste (fallback silenzioso:
## nessun errore stampato, è uno stato atteso finché altri stream non
## popolano le cartelle spells/summons).
func _scan_dir(dir_path : String) -> Array[Resource]:
	var out : Array[Resource] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	var found_names : Array[String] = []
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			found_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	found_names.sort()
	for name in found_names:
		var res := load(dir_path + name)
		if res is Resource:
			out.append(res)
	return out

func _unhandled_input(event : InputEvent) -> void:
	if event.is_action_pressed("select_next"):
		select_next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_prev"):
		select_prev()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_mode_spell"):
		set_mode("spell")
	elif event.is_action_pressed("select_mode_summon"):
		set_mode("summon")

## Avanza la selezione: CICLO UNICO su spell+summon (virgola/punto scorrono
## l'intero arsenale, non solo la modalità corrente). La modalità segue da sola.
func select_next() -> void:
	_cycle_combined(1)

## Arretra nel ciclo unico spell+summon.
func select_prev() -> void:
	_cycle_combined(-1)

## Lista piatta [{kind, res}] di tutto ciò che si può selezionare: spell poi
## summon, nell'ordine in cui compaiono nelle rispettive liste.
func _combined() -> Array:
	var out : Array = []
	for s in known_spells:
		out.append({"kind": "spell", "res": s})
	for s in known_summons:
		out.append({"kind": "summon", "res": s})
	return out

## Indice della selezione corrente dentro la lista combinata (o -1).
func _combined_index(combined : Array) -> int:
	var target : Resource = current()
	if target == null:
		return -1
	for i in combined.size():
		if combined[i]["res"] == target and combined[i]["kind"] == ("spell" if mode == Kind.SPELL else "summon"):
			return i
	return -1

func _cycle_combined(delta : int) -> void:
	var combined := _combined()
	if combined.is_empty():
		return
	var cur := _combined_index(combined)
	if cur < 0:
		cur = 0 if delta > 0 else combined.size() - 1
	else:
		cur = (cur + delta + combined.size()) % combined.size()
	var entry : Dictionary = combined[cur]
	if entry["kind"] == "spell":
		mode = Kind.SPELL
		_spell_index = known_spells.find(entry["res"])
		current_spell = entry["res"]
		selection_changed.emit("spell", current_spell)
	else:
		mode = Kind.SUMMON
		_summon_index = known_summons.find(entry["res"])
		current_summon = entry["res"]
		selection_changed.emit("summon", current_summon)

## Cambia modalità ("spell" o "summon"); emette selection_changed con la
## risorsa già selezionata in quella modalità (utile per aggiornare la UI
## anche se l'indice non cambia).
func set_mode(kind : String) -> void:
	var new_mode := Kind.SPELL if kind == "spell" else Kind.SUMMON
	if new_mode == mode:
		return
	mode = new_mode
	if mode == Kind.SPELL:
		selection_changed.emit("spell", current_spell)
	else:
		selection_changed.emit("summon", current_summon)

## Ritorna la resource correntemente selezionata secondo la modalità attiva
## (equivalente a current_spell o current_summon, ma modalità-aware).
func current() -> Resource:
	return current_spell if mode == Kind.SPELL else current_summon

func _advance_index(index : int, size : int, delta : int) -> int:
	if size <= 0:
		return -1
	if index < 0:
		return 0
	return (index + delta + size) % size

func _get_at(list : Array[Resource], index : int) -> Resource:
	if index < 0 or index >= list.size():
		return null
	return list[index]
