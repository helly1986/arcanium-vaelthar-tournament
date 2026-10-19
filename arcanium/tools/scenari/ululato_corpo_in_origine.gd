extends "res://arcanium/tools/scenari/ululato_traccia.gd"

## ═══════════════════════════════════════════════════════════════════════════
## SCENARIO: l'ululato della Traccia con un corpo nell'origine del contenitore
## ═══════════════════════════════════════════════════════════════════════════
##
## Sulla Traccia lo schema vecchio di `_on_alpha_howl` (add_child, POI
## global_position) e' LATENTE: il rinforzo nasce un istante nell'origine di
## T8Enemies, che e' (0, 0, 0) del mondo, vicino all'ingresso, dove durante lo
## scontro con l'Alpha non c'e' nessuno (scenario ululato_traccia, 2026-10-07:
## rinforzi a 4 m dall'Alpha, sul terreno, nessun allarme).
##
## Qui si ricrea la condizione in cui a Kalvorn il difetto si vedeva: un lupo
## fermo proprio in quell'origine. Si guarda sia l'arena sia l'origine.

var _ospite : Node3D = null


func prepara(oss) -> void:
	super.prepara(oss)
	for e in oss.nemici():
		if not e.is_dead() and str(e.scene_file_path).get_file() == "lupo.tscn" and str(e.get_parent().name) != "Alpha":
			_ospite = e
			break
	if _ospite:
		_ospite.set("ai_enabled", false)
		_ospite.global_position = _alpha_contenitore(oss) + Vector3(0, 0.1, 0)


func _alpha_contenitore(oss) -> Vector3:
	var a := nemico_per_nome(oss, "LupoAlpha")
	return (a.get_parent() as Node3D).global_position if a else Vector3.ZERO


func al_tick(tick : int, oss) -> void:
	super.al_tick(tick, oss)
	for dopo in [1, 2, 15, 60]:
		if tick == TICK_ULULATO + dopo and _ospite and is_instance_valid(_ospite):
			ponte.cattura_scenario("origine_piu_%d" % dopo, _ospite.global_position)
