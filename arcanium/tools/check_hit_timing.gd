extends Node
## ═══════════════════════════════════════════════════════════════════════════
## BANCO DI PROVA DEI TEMPI DI COLPO
## ═══════════════════════════════════════════════════════════════════════════
##
## Per OGNI mossa di OGNI nemico: lancia la mossa sul nemico vero e misura a che
## punto della clip esce il colpo, confrontandolo con l'istante di contatto
## misurato dalle animazioni. Verifica cioè che la catena
## animazione → dato → gameplay non si sia rotta da nessuna parte.
##
## È la prova che regge parata e schivata: se il colpo non esce dove l'occhio lo
## vede, quelle due meccaniche diventano indovinelli.
##
##   godot --headless --path . res://arcanium/tools/check_hit_timing.tscn

const AttackTiming := preload("res://arcanium/resources/attack_timing.gd")

const NEMICI := {
	"Consumato": "res://arcanium/characters/consumato.tscn",
	"Lupo": "res://arcanium/characters/lupo.tscn",
	"LupoAlpha": "res://arcanium/characters/lupo_alpha.tscn",
	"SenzaNome": "res://arcanium/characters/senza_nome.tscn",
}

## Scarto tollerato tra contatto atteso e colpo osservato, in tempo-clip.
## Un frame a 60 fps è 0.017 s: 0.05 è tre frame, sotto la soglia percettiva.
const TOLLERANZA := 0.05

class Bersaglio extends CharacterBody3D:
	var colpi : Array = []
	func hit(_who, _by_what) -> void:
		colpi.append(true)


var _lib : Resource


func _ready() -> void:
	_lib = load("res://arcanium/resources/attack_timing.tres")
	print("\n╔══════════════════════════════════════════════════════════════════════════╗")
	print("║  TEMPI DI COLPO — atteso (misurato dalla clip) vs osservato (in gioco)   ║")
	print("╚══════════════════════════════════════════════════════════════════════════╝")
	for nome in NEMICI:
		await _prova_nemico(nome, NEMICI[nome])
	print("")
	get_tree().quit()


func _prova_nemico(nome : String, path : String) -> void:
	var enemy : Node3D = (load(path) as PackedScene).instantiate()
	# Prima di tutto: via l'AI. Con un bersaglio a portata il nemico apre da solo
	# un attacco nel primo frame e `debug_force_move` lo trova occupato.
	enemy.ai_enabled = false
	add_child(enemy)
	var dummy := Bersaglio.new()
	add_child(dummy)
	dummy.add_to_group("player")
	dummy.global_position = Vector3(0, 0, 1.3)
	await get_tree().physics_frame
	await get_tree().physics_frame

	print("\n── %s   (velocità clip %.2f)" % [nome, enemy.anim_speed_scale])
	print("   %-24s %-9s %-9s %-9s %s" % [
		"mossa", "atteso", "rilascio", "scarto", "finestra arma"])

	for m in enemy.move_set.moves:
		var esito := await _prova_mossa(enemy, dummy, m)
		if esito.is_empty():
			print("   %-24s  non eseguita" % m.id)
			continue
		var atteso : float = esito["atteso"]
		var oss : float = esito["rilascio"]
		var scarto : float = oss - atteso
		var flag := "ok " if absf(scarto) <= TOLLERANZA else "KO "
		if atteso < 0.0:
			flag = "-- "
		print("   %s%-21s %-9s %-9s %-9s %s" % [
			flag, m.id,
			"%.2f" % atteso if atteso >= 0.0 else "n/d",
			"%.2f" % oss if oss >= 0.0 else "mai",
			"%+.3f" % scarto if atteso >= 0.0 and oss >= 0.0 else "-",
			esito["finestra"]])

	# Regressione storica: dopo un colpo letale deve restare in riproduzione la
	# clip di MORTE. Ci finiva sopra quella di dolore, perché `died` arriva
	# SINCRONO dentro `damage_taken` e il ramo del colpo subito non ricontrollava
	# lo stato — i Consumati non mostravano praticamente mai la loro morte.
	var letale := EnemyMove.new()
	letale.power = 99999
	enemy.hit(null, letale)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("   %s morte: clip in corso \"%s\" (attesa \"%s\")" % [
		"ok " if enemy._current_anim == enemy.death_anim else "KO ",
		enemy._current_anim, enemy.death_anim])

	enemy.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _prova_mossa(enemy : Node3D, dummy : Bersaglio, m : Resource) -> Dictionary:
	dummy.colpi.clear()
	var attesi : PackedFloat32Array = enemy._contact_times(m)
	var atteso : float = attesi[0] if not attesi.is_empty() else -1.0
	# `telegraph` come ripiego non è un contatto misurato: lo segnaliamo.
	if not (_lib and _lib.has_clip(m.anim)):
		atteso = -1.0

	if not enemy.debug_force_move(m.id):
		return {}

	var rilascio := -1.0
	var finestra := ""
	var limite := Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < limite:
		await get_tree().physics_frame
		if rilascio < 0.0 and enemy._attack_released \
				and enemy.anim_player.current_animation == m.anim:
			rilascio = enemy.anim_player.current_animation_position
		if finestra == "" and "_window_from" in enemy and enemy._window_from >= 0.0:
			finestra = "%.2f-%.2f (%.0f%% clip)" % [
				enemy._window_from, enemy._window_to,
				100.0 * (enemy._window_to - enemy._window_from)
					/ maxf(enemy._anim_len(m.anim), 0.01)]
		if not enemy._busy:
			break
	if finestra == "":
		finestra = "cono (nessuna arma fisica)"
	return {"atteso": atteso, "rilascio": rilascio, "finestra": finestra}
