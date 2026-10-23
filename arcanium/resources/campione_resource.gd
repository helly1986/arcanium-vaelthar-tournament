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
## Il kit di partenza davvero: slot dell'armadio -> scheda (.tres). Lo mette
## addosso EquipmentLoadout a ogni partita nuova; vuoto = il kit di Dawnkeep.
@export var dotazione : Dictionary = {}
## Le tecniche di guerra (.tres) gia' apprese all'inizio della run: Ilwen tira
## con l'arco dal primo scontro, e l'Arcieria che per gli altri si apre con un
## tomo per lei e' aperta.
@export var tecniche_iniziali : PackedStringArray = []
## Famiglia di danno favorita (chiave di `resistances`): i suoi potenziamenti
## escono piu' spesso.
@export var affinita : String = ""
@export var abilita_nome : String = ""
@export_multiline var abilita_testo : String = ""
## La scena del corpo montato (pipeline Tripo -> ARP -> GLB). Vuota finche' il
## campione non e' fatto: la selezione mostra la sagoma.
@export_file("*.tscn", "*.glb") var corpo : String = ""
## La clip d'idle d'autore, che da' carattere (i moveset sono condivisi): un
## GLB di sole ossa con una clip, uscito da Cascadeur e passato da
## rifinisci_clip_cascadeur.py --radice-ferma, importato con la bone map del
## corpo (lo stesso _subresources del GLB del campione). In gioco suona da
## fermo al posto della Posa (CorpoCampione); vuota = la Posa.
@export_file("*.glb") var idle : String = ""
## La PRESA nelle mani di questo corpo: le armi del player sono state
## agganciate sulla mano del protagonista, e le ossa della mano di ogni
## campione hanno assi loro. E' la trasformazione dei nodi `Sword` (sotto
## WeaponSystem/RightHand/HandPivot) e `Shield` (sotto
## GadgetSystem/LeftHand/HandPivot), sistemata a mano sul banco
## arcanium/tools/banco_impugnatura_<nome>.tscn. Vale per ogni arma in quella
## mano: i modelli di casata stanno dentro `Sword`. Il manico va NEL PALMO,
## all'altezza delle nocche, non sulle seconde falangi: li' le dita chiuse da
## presa_mano.gd lasciano le punte fuori (Edran, 2026-10-23: spostato di 3,6
## cm verso il palmo).
@export var presa_arma := Transform3D.IDENTITY
@export var presa_scudo := Transform3D.IDENTITY
## Quanto si chiudono le dita sull'impugnatura (arcanium/systems/presa_mano.gd,
## 0 = la mano delle clip, 1 = gli angoli pieni), destra sull'arma e sinistra
## sulla maniglia dello scudo.
@export_range(0.0, 1.5) var chiusura_mano_destra := 0.0
@export_range(0.0, 1.5) var chiusura_mano_sinistra := 0.0


## Il ritratto per il medaglione dell'HUD e per la selezione: il viso
## ritagliato dal concept (Nano Banana Pro su Tripo).
func ritratto() -> String:
	return "res://assets/ui/ritratti/%s.png" % casata
