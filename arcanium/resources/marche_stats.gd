extends Resource
class_name MarcheStats

## Le Sette Marche — le statistiche interiori del protagonista di Arcanium.
## NON sono Forza/Destrezza/Arcano classici: sono qualità emotive/interiori
## (lore in docs/lore/PROJECT_BIBLE.md). Regola lore: il gioco non spiega mai
## cosa fa ciascuna Marca, quindi la UI mostra solo sigla+nome+valore.
##
## Valori di partenza = 10. Il level-up avviene ai Coni di Canalizzazione
## durante il riposo: lo gestisce l'autoload `MarcheProgression`, che tiene il
## livello e i punti spesi per Marca e li applica qui.

enum Marca { CON, EMP, VOL, BON, PER, SAC, RES }

## Sigle e nomi estesi, indicizzati come l'enum Marca.
const SIGLE : Array[String] = ["CON", "EMP", "VOL", "BON", "PER", "SAC", "RES"]
const NOMI : Array[String] = [
	"Knowledge", "Empathy", "Will", "Benevolence",
	"Perseverance", "Sacrifice", "Resilience",
]
## Le sigle come le legge il giocatore (inglese). `SIGLE` resta la chiave
## interna (HouseCatalog, scaling delle armi): non si traduce.
const SIGLE_MOSTRATE : Array[String] = ["KNO", "EMP", "WIL", "BEN", "PER", "SAC", "RES"]

@export var conoscenza : int = 10   ## CON
@export var empatia : int = 10      ## EMP
@export var volonta : int = 10      ## VOL
@export var bonta : int = 10        ## BON
@export var perseveranza : int = 10 ## PER
@export var sacrificio : int = 10   ## SAC
@export var resistenza : int = 10   ## RES

## Ritorna il valore di una Marca dato l'enum. Utile per armi/formule che
## non sanno a compile-time su quale Marca scalano.
func get_marca(marca : Marca) -> int:
	match marca:
		Marca.CON: return conoscenza
		Marca.EMP: return empatia
		Marca.VOL: return volonta
		Marca.BON: return bonta
		Marca.PER: return perseveranza
		Marca.SAC: return sacrificio
		Marca.RES: return resistenza
	return 0


## Somma `delta` a una Marca. Serve al level-up ai Coni: senza, chi sale di
## livello dovrebbe conoscere il nome del campo per ciascuna Marca e
## l'associazione enum→campo finirebbe scritta in due posti.
func add_marca(marca : Marca, delta : int) -> void:
	match marca:
		Marca.CON: conoscenza += delta
		Marca.EMP: empatia += delta
		Marca.VOL: volonta += delta
		Marca.BON: bonta += delta
		Marca.PER: perseveranza += delta
		Marca.SAC: sacrificio += delta
		Marca.RES: resistenza += delta
