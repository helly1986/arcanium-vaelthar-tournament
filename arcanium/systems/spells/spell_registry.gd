extends Node
class_name SpellRegistry

## Piccolo registro statico degli incantesimi noti, per id stringa. Non è un
## autoload (nessuna modifica a project.godot, fuori dal mio ambito): chi ha
## bisogno di risolvere uno spell per nome può istanziare questa classe al
## volo, es. `SpellRegistry.new().get_spell("ice_shard")`, oppure tenerne una
## @onready var locale. I path sono hardcoded qui perché oggi esiste un solo
## spell prodotto (Shard di Ghiaccio); aggiungere un nuovo spell = una riga.

const _PATHS : Dictionary = {
	"ice_shard": "res://arcanium/resources/spells/ice_shard.tres",
	"morsa_del_gelo": "res://arcanium/resources/spells/morsa_del_gelo.tres",
	## Evocazione: vive in resources/summons/ (non resources/spells/), stessa
	## cartella scansionata da SpellSelection.known_summons — vedi
	## summon_spell_resource.gd per il perché.
	"evoca_scintilla": "res://arcanium/resources/summons/evoca_scintilla.tres",
}

var _cache : Dictionary = {}

## Ritorna lo spell per id, o null se sconosciuto. Cachea il Resource caricato.
func get_spell(id : String) -> ArcaniumSpellResource:
	if _cache.has(id):
		return _cache[id]
	if not _PATHS.has(id):
		push_warning("SpellRegistry: id spell sconosciuto '%s'." % id)
		return null
	var res : Resource = load(_PATHS[id])
	if res is ArcaniumSpellResource:
		_cache[id] = res
		return res
	push_warning("SpellRegistry: risorsa a '%s' non è una ArcaniumSpellResource." % _PATHS[id])
	return null

## Tutti gli spell noti (carica ogni voce non ancora in cache).
func all_spells() -> Array:
	var out : Array = []
	for id in _PATHS.keys():
		var s := get_spell(id)
		if s != null:
			out.append(s)
	return out
