extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: il Branco Guasto di Kalvorn — capobranco, richiamo, fuga
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_branco.gd
##
##   1. il CAPOBRANCO e' un Alpha (`is_alpha`) ma non un mini-boss: tiene la
##      barretta sopra la testa;
##   2. l'ULULATO (howl_summon) fa affiorare due lupi accanto a lui, e un
##      secondo ululato non ne aggiunge oltre il tetto dei vivi;
##   3. morto il capobranco i lupi FUGGONO;
##   4. l'Alpha resta un mini-boss (niente barretta: la sua barra e' quella a
##      fondo schermo) e porta il suo RichiamoBranco, come il capobranco: il
##      director della Traccia che lo faceva per lui non c'e' piu'.

const CAPOBRANCO := "res://arcanium/characters/lupo_capobranco.tscn"
const LUPO := "res://arcanium/characters/lupo.tscn"
const ALPHA := "res://arcanium/characters/lupo_alpha.tscn"

var guasti := 0


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
	var suolo := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(80, 1, 80)
	fs.shape = bx
	fs.position = Vector3(0, -0.5, 0)
	suolo.add_child(fs)
	root.add_child(suolo)
	var branco := Node3D.new()
	root.add_child(branco)

	## ⚠️ La posizione PRIMA di add_child, come fa il builder: aggiunti
	## nell'origine e poi spostati, un lupo nasce dentro l'altro, ci sale sopra
	## e viene portato via con lui (vedi richiamo_branco.gd).
	var capo : Node3D = (load(CAPOBRANCO) as PackedScene).instantiate()
	capo.position = Vector3(0, 0.05, 0)
	branco.add_child(capo)
	var lupi : Array[Node3D] = []
	for p in [Vector3(-3, 0.05, 2), Vector3(3, 0.05, 2)]:
		var l : Node3D = (load(LUPO) as PackedScene).instantiate()
		l.position = p
		branco.add_child(l)
		lupi.append(l)
	await physics_frame
	await physics_frame

	print("=== 1. IL CAPOBRANCO ===")
	_sia(capo.is_alpha and not capo.mini_boss, "e' un Alpha ma non un mini-boss")
	_sia(capo.show_floating_health, "tiene la barretta sopra la testa")

	print("=== 2. L'ULULATO ===")
	var rich : Node = capo.get_node("RichiamoBranco")
	capo.howl_summon.emit()
	await physics_frame
	var nuovi : Array = rich.spawnati()
	_sia(nuovi.size() == 2, "un ululato fa affiorare %d lupi (attesi 2)" % nuovi.size())
	var vicini := nuovi.all(func(w): return w.global_position.distance_to(capo.global_position) < 5.0)
	_sia(vicini, "accanto al capobranco")
	_sia(nuovi.all(func(w): return w.get_parent() == capo.get_parent()), "fratelli del capobranco, non figli")
	capo.howl_summon.emit()
	await physics_frame
	_sia(rich.spawnati().size() == 2, "un secondo ululato non passa il tetto (%d vivi)" % rich.spawnati().size())

	print("=== 3. MORTO IL CAPOBRANCO ===")
	capo.health_system.apply_damage(10000.0)
	await physics_frame
	await physics_frame
	var tutti : Array = lupi + nuovi
	var fuggono := tutti.filter(func(w): return is_instance_valid(w) and int(w._state) == int(w.State.FLEE)).size()
	_sia(fuggono == tutti.size(), "fuggono %d lupi su %d" % [fuggono, tutti.size()])
	branco.queue_free()
	await process_frame

	print("=== 4. L'ALPHA ===")
	var alpha : Node3D = (load(ALPHA) as PackedScene).instantiate()
	root.add_child(alpha)
	await physics_frame
	_sia(alpha.mini_boss and not alpha.show_floating_health, "resta un mini-boss, senza barretta")
	_sia(alpha.get_node_or_null("RichiamoBranco") != null, "e porta il suo richiamo (il director della Traccia non c'e' piu')")

	print("\n%s" % ("PASSATO — 0 problemi" if guasti == 0 else "FALLITO — %d problemi" % guasti))
	quit(0 if guasti == 0 else 1)
