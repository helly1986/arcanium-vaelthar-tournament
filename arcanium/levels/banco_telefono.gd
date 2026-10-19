extends Node

## Il banco di prova del telefono (Fase 1 del piano, docs/17_PIANO_FASI.md).
##
## Monta l'arena del branco (giocatore, Alpha, due lupi) e il contatore delle
## prestazioni. Il giocatore non muore: sul telefono non ci sono ancora i
## comandi touch, quindi i lupi lo attaccano senza sosta e il carico resta quello
## di un combattimento vero per tutto il tempo della misura.

const ARENA := "res://arcanium/levels/arena_branco.tscn"
const MISURA := preload("res://arcanium/ui/hud/misura_prestazioni.gd")
const VITA := 1000000
const CENTRO := Vector3(0.0, 0.2, 4.0)

var _arena : Node
var _player : Node


func _ready() -> void:
	_arena = (load(ARENA) as PackedScene).instantiate()
	add_child(_arena)
	add_child(MISURA.new())
	_player = _arena.get_node_or_null("Player")
	if _player != null:
		(_player as Node3D).global_position = CENTRO


var _da_ultimo := 0.0

func _process(delta : float) -> void:
	if _player == null:
		return
	## I lupi lo spingono indietro di qualche metro al minuto: contro il muro sud
	## la camera isometrica guarda il muro e non piu' il combattimento (la camera
	## non gestisce ancora i muri: e' lavoro della Fase 2). Si riporta al centro.
	var p := _player as Node3D
	if Vector2(p.global_position.x - CENTRO.x, p.global_position.z - CENTRO.z).length() > 5.0:
		p.global_position = CENTRO
	_da_ultimo += delta
	if _da_ultimo >= 5.0:
		_da_ultimo = 0.0
		var cam := get_viewport().get_camera_3d()
		print("BANCO: giocatore a %s, camera %s a %s" % [
			(_player as Node3D).global_position.snapped(Vector3.ONE * 0.1),
			cam.name if cam else "nessuna",
			cam.global_position.snapped(Vector3.ONE * 0.1) if cam else Vector3.ZERO])
	var hs = _player.get("health_system")
	if hs != null and float(hs.current_health) < VITA / 2.0:
		hs.total_health = VITA
		if hs.has_method("heal"):
			hs.heal(float(VITA))
		else:
			hs.current_health = VITA
