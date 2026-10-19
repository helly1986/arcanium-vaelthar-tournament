extends Node3D
class_name VarianteVisiva
## Tiene visibile UNO solo dei figli, scelto a caso: due sagome nella stessa
## squadra invece di sei cloni.
##
## Nasce per gli scudi del Fante Sylvorn -- uno integro e uno col fondo
## scheggiato -- ma vale per qualunque pezzo con piu' varianti. Si appende al
## nodo che le contiene e basta.
##
## ⚠️ I figli non scelti si NASCONDONO e basta, non si liberano: liberarli in
## `_ready()` mentre l'albero si sta costruendo e' il modo classico di prendersi
## un nodo mezzo istanziato. Costano una manciata di draw call in meno, non
## valgono il rischio.

## Se > 0, tutte le istanze con lo stesso seme scelgono la stessa variante.
@export var seme : int = 0

func _ready() -> void:
	var figli : Array[Node] = []
	for c in get_children():
		if c is Node3D:
			figli.append(c)
	if figli.size() < 2:
		return
	var i : int = (seme % figli.size()) if seme > 0 else randi() % figli.size()
	for j in figli.size():
		(figli[j] as Node3D).visible = (j == i)
