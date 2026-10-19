extends Node
## Autoload: PlayerFlags
## Flag booleani generici usati dal dialogue system (SET_FLAG / flag:x / !flag:x).
## Persistito da SaveManager tramite to_dict()/from_dict() (vedi save_manager.gd).

signal changed

var _flags : Dictionary = {}

func has(flag_name : String) -> bool:
	return _flags.get(flag_name, false)

func set_flag(flag_name : String) -> void:
	_flags[flag_name] = true
	changed.emit()

func clear(flag_name : String) -> void:
	_flags.erase(flag_name)
	changed.emit()

## Serializzazione per SaveManager.
func to_dict() -> Dictionary:
	return _flags.duplicate()

func from_dict(d : Dictionary) -> void:
	_flags = d.duplicate() if d else {}

## Azzera tutto lo stato in memoria (nuova partita). Non emette 'changed' per
## conto suo su richiesta esplicita di begin_new_run, che gestisce il guard
## anti-autosave a monte (vedi save_manager.gd begin_new_run).
func clear_all() -> void:
	_flags = {}
