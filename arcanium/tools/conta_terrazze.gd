extends SceneTree

## Quante TERRAZZE escono su molti semi, per profilo (pianta_dungeon.gd, 9):
## stanze candidate, terrazze messe, per forma e per quota. Solo pianta, niente
## geometria: si lancia in headless.
##
## Uso: godot --headless --path . --script res://arcanium/tools/conta_terrazze.gd -- [profilo] [semi]

const Pianta := preload("res://arcanium/levels/dungeon/pianta_dungeon.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var percorso := args[0] if not args.is_empty() else "res://arcanium/levels/dungeon/profilo_rovine.tres"
	var semi := int(args[1]) if args.size() > 1 else 30
	var profilo : Resource = load(percorso)
	var tot := 0
	var candidate := 0
	var forme := {}
	var con := 0
	for s in semi:
		var p : RefCounted = Pianta.new()
		p.genera(profilo, s)
		for st in p.stanze:
			var r : Rect2i = st["rect"]
			if mini(r.size.x, r.size.y) >= profilo.terrazza_stanza_min and st["ruolo"] != Pianta.Ruolo.INGRESSO and st["ruolo"] != Pianta.Ruolo.USCITA:
				candidate += 1
		tot += p.terrazze.size()
		if not p.terrazze.is_empty():
			con += 1
		for t in p.terrazze:
			forme[t["forma"]] = forme.get(t["forma"], 0) + 1
	print("TERRAZZE: %s, %d semi: %d terrazze su %d stanze candidate; dungeon con almeno una: %d; forme %s" % [
		percorso.get_file(), semi, tot, candidate, con, str(forme)])
	quit()
