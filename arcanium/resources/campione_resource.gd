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
## Scintille in un momento dell'idle d'autore (arcanium/systems/scintille_idle.gd):
## il secondo del giro in cui cadono, -1 = niente, e l'osso da cui cadono.
## Kessra: il giro di vite al ribattino del giogo.
@export var idle_scintille := -1.0
@export var idle_scintille_osso := "LeftIndexDistal"
## La regolazione della stoffa simulata per questo corpo, sopra i default di
## stoffa_simulata.gd: "capsule" {osso senza lato: raggio}, "viaggio" e
## "rilievo" in metri (vedi StoffaSimulata.regolazione). Vuota = i default.
@export var stoffa : Dictionary = {}
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
## 0 = le dita a riposo, come le lasciano le clip; 1 = gli angoli pieni), destra
## sull'arma e sinistra sulla maniglia dello scudo, o sull'arma se il kit non
## ha scudo (le armi a due mani di Zarine e Aurin).
@export_range(-0.6, 1.5) var chiusura_mano_destra := 0.0
@export_range(-0.6, 1.5) var chiusura_mano_sinistra := 0.0
## Il POLLICE di ogni mano, che va contro le dita (presa_mano.gd): sopra zero
## si chiude sopra le dita, sotto zero si allarga per un manico grosso.
@export_range(-1.0, 1.5) var pollice_mano_destra := 1.0
@export_range(-1.0, 1.5) var pollice_mano_sinistra := 1.0
## Le armi A DUE MANI: la mano sinistra nello spazio della destra, misurata
## nella guardia a due mani del banco (guardia_due_mani.gd). Con
## `seconda_mano_attiva` la sinistra la segue sopra ogni clip
## (arcanium/systems/seconda_mano.gd).
@export var seconda_mano_attiva := false
@export var seconda_mano := Transform3D.IDENTITY
## Le PRESE degli altri TIPI d'arma ("BOW", "SLASH", "HEAVY"): l'equipaggiamento
## e' intercambiabile, e un arco in mano a Edran non si tiene come la sua lama
## (2026-11-02: la corda deve passare sotto l'ascella per tutti). Per tipo, un
## dizionario con i campi della presa qui sopra (CAMPI_PRESA); il tipo
## dell'arma del kit sta nei campi stessi. Si scrivono dal banco
## (dal_banco_alla_scheda.gd).
@export var prese : Dictionary = {}

const CAMPI_PRESA := ["presa_arma", "chiusura_mano_destra", "chiusura_mano_sinistra", "pollice_mano_destra",
		"pollice_mano_sinistra", "seconda_mano_attiva", "seconda_mano"]


## Il tipo d'arma del kit ("SLASH" se il kit non ne dichiara uno).
func tipo_del_kit() -> String:
	if not dotazione.has("arma_primaria"):
		return "SLASH"
	var arma : Resource = load(dotazione["arma_primaria"])
	return String(arma.object_type) if arma != null and "object_type" in arma and String(arma.object_type) != "" \
			else "SLASH"


## La presa per il tipo d'arma `tipo`: quella in `prese`, campo per campo, o
## quella del kit dove manca.
func presa_per(tipo : String) -> Dictionary:
	var p := {}
	for k in CAMPI_PRESA:
		p[k] = get(k)
	if tipo != tipo_del_kit() and prese.has(tipo):
		for k in prese[tipo]:
			p[k] = prese[tipo][k]
	return p


## Il ritratto per il medaglione dell'HUD e per la selezione: il viso
## ritagliato dal concept (Nano Banana Pro su Tripo).
func ritratto() -> String:
	return "res://assets/ui/ritratti/%s.png" % casata
