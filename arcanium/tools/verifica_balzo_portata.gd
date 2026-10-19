extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: il morso di un balzo si misura da dove il lupo atterra
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_balzo_portata.gd
##
## Il balzo (LEAP) dell'Alpha ha `move_range = 12.64`: e' la distanza da cui
## parte. Usata anche come portata del colpo, il morso entrava con il player a
## 6,8 m che rotolava via (playtest automatico del 2026-10-07, vedi
## docs/15_PLAYTEST_JEV.md). Qui si chiama `_apply_hit` sulla mossa vera, con
## un bersaglio finto davanti al muso:
##   1. a 2 m il balzo morde;
##   2. a 6,5 m il balzo NON morde;
##   3. un morso normale (non balzo) resta com'era, con la sua portata.

const ALPHA := "res://arcanium/characters/lupo_alpha.tscn"

var guasti := 0


class Bersaglio extends Node3D:
	var colpi := 0
	func hit(_chi, _cosa) -> void:
		colpi += 1


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


func _initialize() -> void:
	_prova()


func _prova() -> void:
	await process_frame
	var alpha : Node3D = (load(ALPHA) as PackedScene).instantiate()
	alpha.set("ai_enabled", false)
	root.add_child(alpha)
	var b := Bersaglio.new()
	root.add_child(b)
	await physics_frame

	var balzo = null
	var morso = null
	for m in alpha.move_set.moves:
		if m.leap_to_target and balzo == null:
			balzo = m
		elif not m.leap_to_target and m.move_range > 0.0 and morso == null:
			morso = m
	_sia(balzo != null, "l'Alpha ha un balzo (move_range %.2f)" % (balzo.move_range if balzo else -1.0))
	if balzo == null:
		quit(1)
		return
	alpha.target = b

	## La mesh guarda +Z: il bersaglio sta davanti al muso.
	var avanti : Vector3 = alpha.global_transform.basis.z
	avanti.y = 0.0
	avanti = avanti.normalized()

	print("=== 1. BALZO A 2 m ===")
	b.global_position = alpha.global_position + avanti * 2.0
	alpha._apply_hit(balzo)
	_sia(b.colpi == 1, "morde (colpi: %d)" % b.colpi)

	print("=== 2. BALZO A 6,5 m ===")
	b.colpi = 0
	b.global_position = alpha.global_position + avanti * 6.5
	alpha._apply_hit(balzo)
	_sia(b.colpi == 0, "non morde da lontano (colpi: %d)" % b.colpi)

	print("=== 3. MORSO NORMALE ===")
	if morso != null:
		b.colpi = 0
		b.global_position = alpha.global_position + avanti * minf(morso.move_range, 2.0)
		alpha._apply_hit(morso)
		_sia(b.colpi == 1, "%s morde entro la sua portata (%.2f m)" % [morso.id, morso.move_range])

	## 4. La portata del COLPO non e' quella da cui la mossa si sceglie: l'Alpha
	## parte da 4,33 m ma morde solo se il muso (1,31 m davanti al centro)
	## arriva sul player. Lo scenario colpi_lupi lo vedeva mordere a 3,3 m.
	print("=== 4. MORSO DELL'ALPHA: PORTATA DEL COLPO ===")
	if morso != null:
		_sia(morso.portata_colpo > 0.0 and morso.portata_colpo < morso.move_range,
			"%s ha una portata del colpo (%.2f) piu' corta di quella di scelta (%.2f)" % [
				morso.id, morso.portata_colpo, morso.move_range])
		b.colpi = 0
		b.global_position = alpha.global_position + avanti * 2.3
		alpha._apply_hit(morso)
		_sia(b.colpi == 1, "a 2,3 m morde (colpi: %d)" % b.colpi)
		b.colpi = 0
		b.global_position = alpha.global_position + avanti * 3.2
		alpha._apply_hit(morso)
		_sia(b.colpi == 0, "a 3,2 m NON morde piu' (colpi: %d)" % b.colpi)

	print("\n%s" % ("PASSATO — 0 problemi" if guasti == 0 else "FALLITO — %d problemi" % guasti))
	quit(0 if guasti == 0 else 1)
