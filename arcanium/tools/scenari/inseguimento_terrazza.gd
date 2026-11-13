extends "res://arcanium/tools/scenari/inseguimento_dungeon.gd"

## Variante: il giocatore si nasconde IN CIMA a una terrazza (pianta_dungeon.gd,
## 9). Il nemico non puo' salire dal fianco: deve trovare la rampa, salire, e
## arrivargli addosso alla stessa quota (2026-11-13).

func _init() -> void:
	super()
	seme_dungeon = 3


## Una cella di terrazza, la piu' lontana (in passi) dal nemico fra quelle che
## non vede, entro il suo raggio d'ingaggio.
func _cerca_nascondiglio(p, g, e : Node3D, passi_min : int) -> Variant:
	var origine : Vector2i = p.cella_di(e.global_position)
	var dist := {origine: 0}
	var coda : Array[Vector2i] = [origine]
	var testa := 0
	var raggio : float = float(e.get("aggro_range")) * 0.85
	var migliore : Variant = null
	var migliore_passi := 0
	while testa < coda.size():
		var c : Vector2i = coda[testa]
		testa += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q : Vector2i = c + d
			if g._passabile(c, q) and not dist.has(q):
				dist[q] = dist[c] + 1
				coda.append(q)
				var w : Vector3 = p.centro(q)
				if p.quote.has(q) and dist[q] >= 4 and dist[q] > migliore_passi and w.distance_to(e.global_position) < raggio:
					migliore = w + Vector3(0, p.quota(q), 0)
					migliore_passi = dist[q]
	return migliore
