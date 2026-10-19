extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: il finisher colpisce solo chi il player sta guardando
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_finisher_verso.gd
##
## Il playtest automatico (2026-10-08) ha visto una parata + critico uccidere un
## lupo dell'Alpha che stava ALLE SPALLE del player: `_find_critical_target`
## sceglieva per sola distanza e `_start_finisher` girava il player di scatto.
## Qui il player VERO e due bersagli finti, in poise-break o di spalle:
##   1. critico su un bersaglio davanti: preso;
##   2. critico su un bersaglio dietro: NO;
##   3. due candidati, uno dietro piu' vicino e uno davanti: vince quello davanti;
##   4. backstab (bersaglio che ci da' le spalle) davanti al player: preso;
##   5. backstab dietro al player: NO;
##   6. ruotato di 50 gradi (il caso per cui esiste lo scatto del verso): preso.

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"

var guasti := 0


class Host extends Node:
	var rotto := true
	func is_poise_broken() -> bool:
		return rotto


class Salute extends Node:
	var status_host : Host


## Un bersaglio del gruppo "targets" con la salute e il poise che il player legge.
class Bersaglio extends Node3D:
	var health_system : Salute
	func _init() -> void:
		health_system = Salute.new()
		health_system.status_host = Host.new()
		health_system.add_child(health_system.status_host)
		add_child(health_system)
		add_to_group("targets")


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


func _initialize() -> void:
	_prova()


func _nome(n) -> String:
	return "nessuno" if n == null else str(n.name)


func _prova() -> void:
	await physics_frame
	var p = (load(PLAYER) as PackedScene).instantiate()
	root.add_child(p)
	p.global_position = Vector3.ZERO
	p.global_transform.basis = Basis.IDENTITY          ## guarda +Z
	var davanti := Bersaglio.new()
	davanti.name = "Davanti"
	var dietro := Bersaglio.new()
	dietro.name = "Dietro"
	root.add_child(davanti)
	root.add_child(dietro)
	await physics_frame
	var lontano := Vector3(0, 0, 100)

	print("=== CRITICO ===")
	davanti.global_position = Vector3(0, 0, 1.5)
	dietro.global_position = lontano
	_sia(p._find_critical_target() == davanti, "1. davanti a 1,5 m: preso (%s)" % _nome(p._find_critical_target()))
	davanti.global_position = lontano
	dietro.global_position = Vector3(0, 0, -1.5)
	_sia(p._find_critical_target() == null, "2. dietro a 1,5 m: NON preso (%s)" % _nome(p._find_critical_target()))
	davanti.global_position = Vector3(0, 0, 1.9)
	dietro.global_position = Vector3(0, 0, -1.0)
	_sia(p._find_critical_target() == davanti, "3. dietro piu' vicino, davanti piu' lontano: vince davanti (%s)" % _nome(p._find_critical_target()))

	print("=== BACKSTAB ===")
	davanti.health_system.status_host.rotto = false
	dietro.health_system.status_host.rotto = false
	## Entrambi ci danno le spalle: il loro avanti punta via dal player.
	davanti.global_position = Vector3(0, 0, 1.5)
	davanti.global_transform.basis = Basis.IDENTITY
	dietro.global_position = lontano
	_sia(p._find_backstab_target() == davanti, "4. bersaglio di spalle davanti al player: preso (%s)" % _nome(p._find_backstab_target()))
	davanti.global_position = lontano
	dietro.global_position = Vector3(0, 0, -1.5)
	dietro.global_transform.basis = Basis(Vector3.UP, PI)
	_sia(p._find_backstab_target() == null, "5. bersaglio di spalle DIETRO al player: NON preso (%s)" % _nome(p._find_backstab_target()))
	dietro.global_position = lontano
	davanti.global_position = Vector3(1.5 * sin(deg_to_rad(50.0)), 0, 1.5 * cos(deg_to_rad(50.0)))
	davanti.global_transform.basis = Basis(Vector3.UP, deg_to_rad(50.0))
	_sia(p._find_backstab_target() == davanti, "6. a 50 gradi dal verso del player: preso (%s)" % _nome(p._find_backstab_target()))

	print("\n%s" % ("PASSATO — 0 problemi" if guasti == 0 else "FALLITO — %d problemi" % guasti))
	quit(0 if guasti == 0 else 1)
