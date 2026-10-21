extends Resource
class_name CampioneResource

## Un CAMPIONE del torneo: l'arcimago che una casata manda al Grande Torneo
## (docs/campioni_concept.md, schede approvate dall'autore il 2026-10-21).
## E' un dato, non codice: un campione nuovo (patch, DLC) e' un .tres in piu'
## in arcanium/resources/campioni/, letto dalla schermata di selezione.
##
## I testi sono in inglese (tutto cio' che il giocatore legge, design-ui-nuova)
## e passano da tr() quando si mostrano.

## La casata, chiave di HouseCatalog (colore, motto, Marche di partenza).
@export var casata : String = ""
@export var nome : String = ""
## L'epiteto, «il Rintocco».
@export var epiteto : String = ""
@export_enum("male", "female") var genere : String = "male"
@export_multiline var bio : String = ""
## La battuta a inizio scontro.
@export var battuta : String = ""
@export_multiline var bio_casata : String = ""
@export var territorio : String = ""
## Il kit di partenza, come lo legge il giocatore.
@export var kit : PackedStringArray = []
## Famiglia di danno favorita (chiave di `resistances`): i suoi potenziamenti
## escono piu' spesso.
@export var affinita : String = ""
@export var abilita_nome : String = ""
@export_multiline var abilita_testo : String = ""
## La scena del corpo montato (pipeline Tripo -> ARP -> GLB). Vuota finche' il
## campione non e' fatto: la selezione mostra la sagoma.
@export_file("*.tscn", "*.glb") var corpo : String = ""
## La clip d'idle d'autore, che da' carattere (i moveset sono condivisi).
@export var idle : String = ""


## Il ritratto per il medaglione dell'HUD e per la selezione: il viso
## ritagliato dal concept (Nano Banana Pro su Tripo).
func ritratto() -> String:
	return "res://assets/ui/ritratti/%s.png" % casata
