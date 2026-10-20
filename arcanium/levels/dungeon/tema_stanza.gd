extends Resource

## Il TEMA di una stanza del mini-dungeon: pavimento, luce e arredo. Ogni
## stanza ne prende uno compatibile col suo ruolo (richiesta dell'autore,
## 2026-10-20: «stanze con identita' per ruolo», e varieta' anche nei
## pavimenti). I temi stanno nel profilo come dati: un DLC ne aggiunge.

@export var nome : String = ""
## I ruoli in cui compare (pianta_dungeon.gd, Ruolo): 0 ingresso,
## 1 combattimento, 2 chiusa, 3 tesoro.
@export var ruoli : PackedInt32Array = PackedInt32Array([1])
@export var peso : float = 1.0
@export var pavimento : Material
## La luce di riempimento della stanza.
@export var luce_colore : Color = Color(1.0, 0.72, 0.45)
@export var luce_energia : float = 0.5
@export var torce : bool = true
@export var bracieri : bool = true
## Le colonne agli angoli delle stanze rettangolari grandi.
@export var colonne : bool = false
## Quante rovine sparse (colonne cadute, macerie, lastre).
@export var rovine_min : int = 0
@export var rovine_max : int = 0
## I pezzi del tema (pezzo_tema.gd).
@export var arredo : Array[Resource] = []
