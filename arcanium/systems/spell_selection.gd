extends Node
class_name SpellSelection

## Selezione degli incantesimi del player, via rotellina del mouse o hotkey.
## NON lancia nulla: solo tiene l'indice corrente ed emette `selection_changed`
## quando la selezione cambia. Il lancio effettivo (su azione input
## `cast_spell`) è responsabilità del player controller, che legge
## `current_spell` e lo passa al proprio SpellCaster.
##
## Duck-typing verso le resource: qui NON importiamo/referenziamo
## SpellResource/SpellCaster. Le spell note vengono caricate come Resource
## generiche dai .tres trovati in `res://arcanium/resources/spells/`; se la
## cartella non esiste la lista resta vuota e il sistema degrada in silenzio.
##
## Le EVOCAZIONI non sono piu' del campione (decisione dell'autore del
## 2026-10-21): avranno la loro modalita', il battleground. Le risorse in
## `res://arcanium/resources/summons/` restano per le sue unita', ma da qui non
## si selezionano piu'.

const SPELL_DIR := "res://arcanium/resources/spells/"

## Lista di Resource (duck-typed: qualunque .tres in SPELL_DIR).
var known_spells : Array[Resource] = []

var _spell_index : int = -1

## La resource attualmente selezionata, o null se la lista è vuota. Sempre
## allineata a _spell_index.
var current_spell : Resource = null

## kind: sempre "spell". resource: la Resource selezionata (o null).
signal selection_changed(kind : String, resource : Resource)

func _ready() -> void:
	known_spells = _scan_dir(SPELL_DIR)
	if not known_spells.is_empty():
		_spell_index = 0
		current_spell = known_spells[0]

## Scansiona una directory di risorse .tres/.res e le carica come Resource
## generiche. Ritorna array vuoto se la dir non esiste (fallback silenzioso).
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
	## Sul pad la croce su e' sia `select_next` sia `inv_prev` del menu.
	var menu := get_node_or_null("/root/GameMenu")
	if menu != null and menu.is_blocking():
		return
	if event.is_action_pressed("select_next"):
		select_next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_prev"):
		select_prev()
		get_viewport().set_input_as_handled()

## Avanza la selezione, in ciclo.
func select_next() -> void:
	_cycle(1)

## Arretra la selezione, in ciclo.
func select_prev() -> void:
	_cycle(-1)

func _cycle(delta : int) -> void:
	if known_spells.is_empty():
		return
	_spell_index = _advance_index(_spell_index, known_spells.size(), delta)
	current_spell = known_spells[_spell_index]
	selection_changed.emit("spell", current_spell)

## Ritorna la resource correntemente selezionata.
func current() -> Resource:
	return current_spell

func _advance_index(index : int, size : int, delta : int) -> int:
	if size <= 0:
		return -1
	if index < 0:
		return 0 if delta > 0 else size - 1
	return (index + delta + size) % size
