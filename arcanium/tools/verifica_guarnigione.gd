extends SceneTree

## Cancello della guarnigione della soglia. Carica DAVVERO le due scene dei Fanti
## e ne legge stat, ricompensa e drop, invece di fidarsi del fatto che il file
## sia stato scritto: una scena che non istanzia non da' errore a chi la scrive,
## da' un incontro vuoto in gioco.
##
##   godot --headless --path . --script res://arcanium/tools/verifica_guarnigione.gd

func _init() -> void:
	var guasti := 0
	var atteso := {
		"res://arcanium/characters/sylvorn_fante.tscn": 46,
		"res://arcanium/characters/sylvorn_fante_spadone.tscn": 58,
	}
	for path in atteso.keys():
		if not ResourceLoader.exists(path):
			print("MANCA  ", path); guasti += 1; continue
		var scena : PackedScene = load(path)
		if scena == null:
			print("NON CARICA  ", path); guasti += 1; continue
		var n : Node = scena.instantiate()
		if n == null:
			print("NON ISTANZIA  ", path); guasti += 1; continue

		var hs := n.get_node_or_null("HealthSystem")
		var cb := n.get_node_or_null("CrystalBounty")
		var drops : Array[Node] = []
		for f in n.get_children():
			if f.get_script() != null and "drop_chance" in f:
				drops.append(f)
		var vita : int = hs.total_health if hs else -1
		var taglia : int = cb.amount if cb else -1
		print("\n=== %s ===" % path.get_file())
		print("  vita        : %d  (attesa %d)%s" % [vita, atteso[path],
			"" if vita == atteso[path] else "   ⚠ DIVERSA"])
		print("  Arcanium    : %d  (attesi 25)%s" % [taglia,
			"" if taglia == 25 else "   ⚠ DIVERSO"])
		print("  move set    : %s" % ("SI" if n.get("move_set") != null else "⚠ ASSENTE"))
		var ms = n.get("move_set")
		if ms != null:
			for mv in ms.moves:
				print("      %-4s %-34s potenza=%d" % [mv.id, mv.anim, mv.power])
		print("  drop        : %d pezzi" % drops.size())
		for d in drops:
			var esiste := ResourceLoader.exists("res://arcanium/resources/items/%s.tres" % d.item_id)
			print("      %-22s %.0f%%   item .tres: %s" % [d.item_id, d.drop_chance * 100.0,
				"c'e'" if esiste else "⚠ NON ESISTE (il dado gira a vuoto)"])
		if vita != atteso[path] or taglia != 25:
			guasti += 1
		n.free()

	print("\n%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)
