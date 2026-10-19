extends "res://arcanium/tools/scenari/scenario.gd"

## ═══════════════════════════════════════════════════════════════════════════
## SCENARIO: il set visivo etichettato — difetti iniettati e inquadrature pulite
## ═══════════════════════════════════════════════════════════════════════════
##
## Serve a misurare il canale visivo (VLM locali) e i sorveglianti sullo stesso
## terreno, con la verita' scritta: un caso alla volta, ognuno montato a un tick
## noto, fotografato da tre angolazioni e poi smontato. Fra un difetto e
## l'altro ci sono inquadrature PULITE, che contano quanto i difetti: senza, non
## si misurano i falsi allarmi.
##
## I difetti sono messe in scena (materiali, posizioni, pose cambiate a mano):
## nessuno di questi stati esiste nel gioco normale, ed e' proprio per questo
## che la loro etichetta e' certa.
##
## Ogni nemico toccato viene CONGELATO (process disabilitato): niente IA,
## niente fisica, la posa resta quella del fotogramma.

const PASSO := 45          ## tick fra un caso e il successivo
const SCATTO := 6          ## tick dopo il montaggio in cui si fotografa

var _casi : Array = []
var _lupi : Array = []
var _montato : Dictionary = {}
var _quadri : Array = []


func _init() -> void:
	scena = "res://arcanium/levels/arena_branco.tscn"
	_casi = ["pulito", "magenta", "pulito", "affondato", "pulito", "in_groppa", "pulito",
		"dentro_roccia", "pulito", "z_fighting", "pulito", "t_pose", "pulito"]
	durata = 60 + PASSO * _casi.size() + 30


func prepara(oss) -> void:
	porta_player(oss, Vector3(0.0, 0.3, 8.0))
	## Due lupi comuni portati nell'arena e congelati: sono i soggetti.
	for e in oss.nemici():
		if not e.is_dead() and nome_nemico_e_lupo(e) and _lupi.size() < 2:
			_lupi.append(e)
	for i in _lupi.size():
		var l : Node3D = _lupi[i]
		l.global_position = Vector3(-2.0 + 4.0 * i, 0.1, 3.0)
		l.process_mode = Node.PROCESS_MODE_DISABLED
	## L'Alpha resta lontano e fermo: non deve entrare nelle inquadrature.
	var alpha := nemico_per_nome(oss, "LupoAlpha")
	if alpha:
		alpha.process_mode = Node.PROCESS_MODE_DISABLED


static func nome_nemico_e_lupo(e) -> bool:
	return str(e.scene_file_path).get_file() == "lupo.tscn"


func al_tick(tick : int, oss) -> void:
	var i := int((tick - 60) / PASSO)
	if tick < 60 or i >= _casi.size():
		return
	var fase := (tick - 60) % PASSO
	var caso : String = _casi[i]
	if fase == 0:
		_monta(caso, oss)
	elif fase == SCATTO:
		var dove : Vector3 = _lupi[0].global_position if not _lupi.is_empty() else oss.player.global_position
		if caso == "t_pose":
			dove = oss.player.global_position
		ponte.cattura_scenario("%02d_%s" % [i, caso], dove)
		etichetta(caso, "lupo 1" if caso != "t_pose" else "player", tick, tick)
	elif fase == PASSO - 1:
		_smonta(oss)


func _monta(caso : String, oss) -> void:
	if _lupi.size() < 2:
		return
	var a : Node3D = _lupi[0]
	var b : Node3D = _lupi[1]
	_montato = {"caso": caso, "pos_a": a.global_position, "pos_b": b.global_position}
	match caso:
		"magenta":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1, 0, 1)
			for mi in a.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = m
		"affondato":
			a.global_position = _montato["pos_a"] + Vector3(0, -0.7, 0)
		"in_groppa":
			b.global_position = a.global_position + Vector3(0.1, 0.85, 0.05)
		"dentro_roccia":
			var r := _roccia_vicina(oss, a.global_position)
			if r:
				a.global_position = r.global_position + Vector3(0, 0.2, 0)
				_montato["roccia"] = str(r.name)
		"z_fighting":
			for colore in [Color(0.9, 0.1, 0.1), Color(0.1, 0.8, 0.1)]:
				var q := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(3.0, 3.0)
				q.mesh = pm
				var mat := StandardMaterial3D.new()
				mat.albedo_color = colore
				q.material_override = mat
				oss.scena.add_child(q)
				q.global_position = a.global_position + Vector3(0, 1.2, 0)
				_quadri.append(q)
		"t_pose":
			var at = oss.player.get("animation_tree")
			if at:
				at.active = false
			for sk in oss.player.find_children("*", "Skeleton3D", true, false):
				(sk as Skeleton3D).reset_bone_poses()


func _smonta(oss) -> void:
	if _montato.is_empty() or _lupi.size() < 2:
		return
	var a : Node3D = _lupi[0]
	var b : Node3D = _lupi[1]
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = null
	a.global_position = _montato["pos_a"]
	b.global_position = _montato["pos_b"]
	for q in _quadri:
		q.queue_free()
	_quadri.clear()
	var at = oss.player.get("animation_tree")
	if at:
		at.active = true
	_montato = {}


## La roccia piu' vicina: un corpo statico del livello costruito (Built) con
## una mesh, fra i 3 e i 25 m dal punto.
func _roccia_vicina(oss, da : Vector3) -> Node3D:
	var built : Node = oss.scena.get_node_or_null("Built")
	var migliore : Node3D = null
	var dm := INF
	if built == null:
		return null
	for n in built.get_children():
		if n is StaticBody3D and (n as Node3D).find_children("*", "MeshInstance3D", true, false).size() > 0:
			var d := (n as Node3D).global_position.distance_to(da)
			if d > 3.0 and d < 25.0 and d < dm:
				dm = d
				migliore = n
	return migliore


func azione(_tick : int, _oss) -> String:
	return "wait"
