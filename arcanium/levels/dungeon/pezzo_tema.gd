extends Resource

## Un pezzo d'arredo di un TEMA di stanza (tema_stanza.gd): cosa, dove e
## quanti.

enum Posto {
	## Con la schiena al muro, la faccia verso la stanza (scaffali, rastrelliere,
	## statue). Mai sui muri bassi verso la camera.
	MURO,
	## Al centro della stanza, uno solo (altare).
	CENTRO,
	## Negli angoli interni (candelabri, statue).
	ANGOLO,
	## Sul pavimento libero, girato a caso (ossa, libri, oro).
	SPARSO,
	## In due file lungo il lato lungo della stanza, tutti paralleli (sarcofagi,
	## tavoli).
	FILE,
}

@export var scena : PackedScene
@export var posto : Posto = Posto.SPARSO
@export var quanti_min : int = 1
@export var quanti_max : int = 2
## Uno in piu' ogni tante celle di stanza (0: solo min/max). Il totale resta
## comunque fra min e max.
@export var celle_per_pezzo : float = 0.0
## Il lato maggiore in pianta, in metri. Se e' 0 si scala sull'altezza.
@export var larghezza : float = 1.0
## L'altezza, in metri: se c'e' anche la larghezza, il pezzo si stira in
## altezza su quella misura.
@export var altezza : float = 0.0
## Ha un corpo: la guida ci gira intorno e i nemici ci sbattono.
@export var solido : bool = true
## Una fiamma in cima (candelabri, bracieri rituali).
@export var fuoco : bool = false
