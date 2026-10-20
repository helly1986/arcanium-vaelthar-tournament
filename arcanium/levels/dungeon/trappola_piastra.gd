extends Node3D

## Una TRAPPOLA A PIASTRA: chi ci mette piede (giocatore o nemico) la fa
## scattare. La piastra affonda con un clic, un attimo dopo parte il colpo:
##   FUOCO: una palla di fuoco dalla bocca sul muro;
##   GHIACCIO: tre dardi che congelano;
##   VELENO: tre dardi che avvelenano (danno nel tempo);
##   FULMINE: un cerchio azzurro si accende sulla piastra e il fulmine cade
##   dall'alto su chi c'e' ancora dentro.
## Il ritardo e' il patto: chi sente il clic e schiva, non paga. Poi la piastra
## si riarma.

const Misura := preload("res://arcanium/levels/dungeon/misura_pezzo.gd")
const Colpo := preload("res://arcanium/levels/dungeon/colpo_trappola.gd")
const Proiettile := preload("res://arcanium/levels/dungeon/proiettile_trappola.gd")

enum Tipo { FUOCO, FULMINE, GHIACCIO, VELENO }

var tipo : int = Tipo.FUOCO
var scena_piastra : PackedScene
var scena_bocca : PackedScene
var lato : float = 1.6
## Dove sta la bocca (nel mondo: la faccia del muro, a terra) e verso dove
## spara.
var bocca : Vector3
var direzione := Vector3.FORWARD

const RITARDO := 0.35
const AVVISO_FULMINE := 0.8
const RIARMO := 2.5
const QUOTA_BOCCA := 1.0
const RAGGIO_FULMINE := 1.6
const COLORI := {
	Tipo.FUOCO: Color(1.0, 0.45, 0.15),
	Tipo.FULMINE: Color(0.55, 0.75, 1.0),
	Tipo.GHIACCIO: Color(0.6, 0.9, 1.0),
	Tipo.VELENO: Color(0.45, 0.95, 0.3),
}

var _modello : Node3D
var _area : Area3D
var _luce : OmniLight3D
var _pronta := true
## Quante volte e' scattata (per i cancelli).
var scatti := 0


func _ready() -> void:
	add_to_group("trappola_dungeon")
	add_to_group("piastra_dungeon")
	_modello = Node3D.new()
	add_child(_modello)
	if scena_piastra != null:
		var m : Node3D = scena_piastra.instantiate()
		_modello.add_child(m)
		var box := Misura.ingombro(m)
		if box.size.x > 0.0:
			var s := lato / maxf(box.size.x, box.size.z)
			m.scale = Vector3(s, 0.08 / maxf(box.size.y, 0.01), s)
			m.position = -Vector3(box.get_center().x * s, box.position.y * m.scale.y, box.get_center().z * s)
	_luce = OmniLight3D.new()
	_luce.light_color = COLORI[tipo]
	_luce.light_energy = 0.0
	_luce.omni_range = 3.0
	_luce.position.y = 0.4
	add_child(_luce)
	_area = Area3D.new()
	_area.monitorable = false
	_area.collision_mask = 2 | 4
	var forma := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(lato * 0.8, 0.8, lato * 0.8)
	forma.shape = b
	forma.position.y = 0.4
	_area.add_child(forma)
	add_child(_area)
	_area.body_entered.connect(_calpestata)
	if tipo != Tipo.FULMINE and scena_bocca != null:
		_metti_bocca()


## La maschera da demone sul muro, girata verso la piastra.
func _metti_bocca() -> void:
	var m : Node3D = scena_bocca.instantiate()
	add_child(m)
	m.top_level = true
	var box := Misura.ingombro(m)
	var s := 0.9 / maxf(box.size.x, box.size.y)
	m.scale = Vector3.ONE * s
	m.global_position = bocca + Vector3(0, QUOTA_BOCCA - box.size.y * s * 0.5, 0) + direzione * 0.05
	m.global_rotation.y = atan2(direzione.x, direzione.z)


func _calpestata(corpo : Node3D) -> void:
	if not _pronta or corpo.get("health_system") == null:
		return
	_pronta = false
	scatti += 1
	_modello.position.y = -0.05
	_luce.light_energy = 1.5
	if tipo == Tipo.FULMINE:
		_fulmine()
	else:
		await get_tree().create_timer(RITARDO, false).timeout
		_spara()
	await get_tree().create_timer(RIARMO, false).timeout
	_modello.position.y = 0.0
	_luce.light_energy = 0.0
	_pronta = true


func _spara() -> void:
	if not is_inside_tree():
		return
	var partenza := bocca + Vector3(0, QUOTA_BOCCA, 0) + direzione * 0.6
	var quanti := 1 if tipo == Tipo.FUOCO else 3
	for k in quanti:
		var p : Node3D = Proiettile.new()
		var c : RefCounted = Colpo.new()
		match tipo:
			Tipo.FUOCO:
				c.power = 30.0
				c.damage_type = "FUOCO"
				p.forma = "palla"
				p.velocita = 8.0
			Tipo.GHIACCIO:
				c.power = 12.0
				c.damage_type = "CRIO"
				c.frozen_buildup = 35.0
				p.velocita = 14.0
			Tipo.VELENO:
				c.power = 6.0
				c.damage_type = "VELENO"
				p.velocita = 14.0
				p.veleno_al_secondo = 3.0
				p.veleno_durata = 5.0
		p.colpo = c
		p.colore = COLORI[tipo]
		p.autore = self
		## I dardi a ventaglio, la palla dritta.
		var angolo := deg_to_rad((k - 1) * 9.0) if quanti > 1 else 0.0
		p.direzione = direzione.rotated(Vector3.UP, angolo)
		get_parent().add_child(p)
		p.global_position = partenza


## Il cerchio si accende, poi il fulmine cade su chi c'e' ancora dentro.
func _fulmine() -> void:
	var tw := create_tween()
	tw.tween_property(_luce, "light_energy", 4.0, AVVISO_FULMINE)
	await tw.finished
	if not is_inside_tree():
		return
	var colonna := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = 0.18
	cil.bottom_radius = 0.35
	cil.height = 6.0
	colonna.mesh = cil
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.92, 1.0)
	mat.emission_enabled = true
	mat.emission = COLORI[Tipo.FULMINE]
	mat.emission_energy_multiplier = 6.0
	colonna.material_override = mat
	colonna.position.y = 3.0
	add_child(colonna)
	_luce.light_energy = 12.0
	_luce.omni_range = 8.0
	var c : RefCounted = Colpo.new()
	c.power = 40.0
	c.damage_type = "FULMINE"
	c.imparabile = true
	for corpo in _area.get_overlapping_bodies():
		if corpo.global_position.distance_to(global_position) <= RAGGIO_FULMINE + 0.6:
			c.colpisci(corpo, self)
	await get_tree().create_timer(0.15, false).timeout
	colonna.queue_free()
	_luce.omni_range = 3.0
	_luce.light_energy = 1.5
