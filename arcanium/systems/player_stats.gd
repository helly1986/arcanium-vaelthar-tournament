extends Node
## Autoload: PlayerStats
## Contatori di gameplay generici usati dal dialogue system (stat:nome>=N).
## NON sono le Sette Marche (CON/EMP/VOL/BON/PER/SAC/RES) — quelle sono un
## sistema separato. "scheggiatura_uses" sarà incrementato dal sistema di
## potere quando esisterà; per ora resta a 0 e le battute soglia relative
## semplicemente non compaiono (condition non soddisfatta).

signal changed

var _stats : Dictionary = {}

func get_stat(stat_name : String) -> int:
	return _stats.get(stat_name, 0)

func set_stat(stat_name : String, value : int) -> void:
	_stats[stat_name] = value
	changed.emit()

func add_stat(stat_name : String, delta : int) -> void:
	_stats[stat_name] = get_stat(stat_name) + delta
	changed.emit()

## Serializzazione per SaveManager.
func to_dict() -> Dictionary:
	return _stats.duplicate()

func from_dict(d : Dictionary) -> void:
	_stats = d.duplicate() if d else {}

## Azzera tutto lo stato in memoria (nuova partita).
func clear_all() -> void:
	_stats = {}
