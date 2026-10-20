extends "res://arcanium/tools/scenari/inseguimento_dungeon.gd"

## Variante: un Fante (umanoide, root motion diversa dal lupo). Seme 11: col
## seme 3, dai corridoi larghi in poi, non c'e' un Fante in una stanza aperta
## e lo scenario ripiegava in silenzio sul lupo.

func _init() -> void:
	super()
	tipo = "fante"
	seme_dungeon = 11
