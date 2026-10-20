extends Node3D

## Una TRAPPOLA a punte: una lastra nel pavimento da cui escono le punte, a
## ciclo.
##
## Il ciclo: riposo (punte giu', a filo del pavimento), avviso (la lastra si
## accende di rosso per `AVVISO` secondi: chi guarda fa in tempo a scansarsi),
## punte su (chi sta sopra prende danno una volta per ciclo), di nuovo giu'.
## Ferisce chiunque: giocatore, evocazioni, nemici. Spingerci un nemico e'
## una tattica.

const Misura := preload("res://arcanium/levels/dungeon/misura_pezzo.gd")

var scena : PackedScene
var lato : float = 1.8
## Secondi di sfasamento: le trappole non scattano tutte insieme.
var sfasamento : float = 0.0

const RIPOSO := 2.2
const AVVISO := 0.7
const SU := 0.8
const DANNO := 25.0
const ALTEZZA_PUNTE := 0.45

var _modello : Node3D
var _area : Area3D
var _luce : OmniLight3D
var _t := 0.0
var _colpiti := {}


func _ready() -> void:
	add_to_group("trappola_dungeon")
	_t = -sfasamento
	_modello = Node3D.new()
	add_child(_modello)
	if scena != null:
		var m : Node3D = scena.instantiate()
		_modello.add_child(m)
		var box := Misura.ingombro(m)
		if box.size.x > 0.0:
			var s := lato / maxf(box.size.x, box.size.z)
			m.scale = Vector3(s, ALTEZZA_PUNTE / maxf(box.size.y, 0.01), s)
			m.position = -Vector3(box.get_center().x * s, box.position.y * m.scale.y, box.get_center().z * s)
	_modello.position.y = -ALTEZZA_PUNTE
	_luce = OmniLight3D.new()
	_luce.light_color = Color(1.0, 0.25, 0.15)
	_luce.omni_range = lato * 1.1
	_luce.light_energy = 0.0
	_luce.position.y = 0.3
	add_child(_luce)
	_area = Area3D.new()
	_area.monitorable = false
	_area.collision_mask = 0xFFFF
	var forma := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(lato * 0.9, 1.0, lato * 0.9)
	forma.shape = b
	forma.position.y = 0.5
	_area.add_child(forma)
	add_child(_area)


func _physics_process(delta : float) -> void:
	_t += delta
	var ciclo := RIPOSO + AVVISO + SU
	var t := fposmod(_t, ciclo)
	if t < RIPOSO:
		_modello.position.y = -ALTEZZA_PUNTE
		_luce.light_energy = 0.0
		_colpiti.clear()
	elif t < RIPOSO + AVVISO:
		## L'avviso: una luce rossa che cresce, e le punte che affiorano appena.
		var k := (t - RIPOSO) / AVVISO
		_luce.light_energy = 2.0 * k
		_modello.position.y = -ALTEZZA_PUNTE * (1.0 - 0.15 * k)
	else:
		_modello.position.y = 0.0
		_luce.light_energy = 0.4
		for corpo in _area.get_overlapping_bodies():
			if _colpiti.has(corpo):
				continue
			var hs = corpo.get("health_system")
			if hs != null and hs.has_method("apply_damage"):
				_colpiti[corpo] = true
				hs.apply_damage(DANNO, "PERFORAZIONE")


func punte_su() -> bool:
	return _modello.position.y > -0.01
