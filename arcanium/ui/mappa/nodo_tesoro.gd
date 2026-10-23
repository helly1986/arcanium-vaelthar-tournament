extends "res://arcanium/ui/mappa/nodo_base.gd"

## Il TESORO: un forziere senza guardiani. Dentro, Arcanium (piu' a ogni tappa)
## e un oggetto dal bottino (bottino.gd): una Pietra del Varco, un
## consumabile, la Brace Votiva o un pezzo che non si ha ancora.

const Bottino := preload("res://arcanium/systems/bottino.gd")

var oggetto : Resource
var arcanium := 0


func _costruisci() -> void:
	arcanium = rng.randi_range(30, 60) * tappa()
	oggetto = Bottino.pesca(rng, get_tree())
	titolo("An unguarded chest")
	testo(tr("The lid gives with a groan. Inside: %d Arcanium%s.") % [arcanium,
			(tr(" and %s") % tr(String(oggetto.item_name))) if oggetto != null else ""])
	var b := scelta(tr("Take it"), "", _prendi)
	b.grab_focus()


func _prendi() -> void:
	var banca := get_node_or_null("/root/CrystalBank")
	if banca != null:
		banca.add(arcanium)
	if oggetto != null:
		Bottino.consegna(oggetto, get_tree())
	chiudi()
