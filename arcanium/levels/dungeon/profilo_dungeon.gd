extends Resource

## Il PROFILO di un mini-dungeon: le regole numeriche e il materiale con cui
## pianta_dungeon.gd genera e costruttore_dungeon.gd costruisce.
##
## Un territorio nuovo (o un DLC) aggiunge un profilo `.tres`: altre stanze,
## altri nemici, altri pezzi. Il codice resta quello.

@export_group("Griglia")
## Celle della griglia in larghezza (x) e in profondita' (z).
@export var larghezza : int = 30
@export var profondita : int = 30
## Lato di una cella, in metri.
@export var lato_cella : float = 2.0

@export_group("Stanze e corridoi")
@export var stanze_min : int = 5
@export var stanze_max : int = 7
## Lato di una stanza, in celle.
@export var stanza_lato_min : int = 5
@export var stanza_lato_max : int = 9
## Celle di distacco fra due stanze (ci passano muro e corridoi).
@export var distacco_stanze : int = 2
## Larghezza dei corridoi, in celle.
@export var corridoio_largo : int = 2
## Collegamenti in piu' oltre all'albero minimo.
@export var anelli_min : int = 0
@export var anelli_max : int = 2

@export_group("Ruoli")
@export_range(0.0, 1.0) var probabilita_chiusa : float = 0.3
@export_range(0.0, 1.0) var probabilita_tesoro : float = 0.12

@export_group("Baratri")
@export_range(0.0, 1.0) var probabilita_baratro : float = 0.35
## Lato minimo di una stanza per avere un baratro.
@export var baratro_stanza_min : int = 7
@export var baratro_spessore : int = 2
@export var ponte_largo : int = 2

@export_group("Popolamento")
## Una cella ogni quante porta un nemico in piu'.
@export var celle_per_nemico : int = 18
@export var nemici_per_stanza_max : int = 3
@export var trappole_min : int = 2
@export var trappole_max : int = 4
@export_range(0.0, 1.0) var probabilita_forziere : float = 0.25
@export_range(0.0, 1.0) var probabilita_raro : float = 0.08

@export_group("Nemici")
## Le scene dei nemici e il peso con cui escono (stessa lunghezza).
@export var nemici : Array[PackedScene] = []
@export var pesi_nemici : PackedFloat32Array = PackedFloat32Array()

@export_group("Pezzi")
## Altezza dei muri, e dei muri che stanno fra la stanza e la camera (bassi,
## o la camera isometrica guarderebbe solo pietra).
@export var muro_alto : float = 3.2
@export var muro_basso : float = 0.9
@export var materiale_pavimento : Material
@export var materiale_muro : Material
@export var arco : PackedScene
@export var porta : PackedScene
@export var colonna : PackedScene
@export var cono : PackedScene
@export var colonna_caduta : PackedScene
@export var macerie : PackedScene
@export var lastre : PackedScene
@export var sasso : PackedScene
## I forzieri normali: ne esce uno a caso (piu' modelli = piu' varieta').
@export var forzieri : Array[PackedScene] = []
@export var forziere_raro : PackedScene
@export var trappola : PackedScene

@export_group("Luci")
## Una luce calda per stanza: le rovine non sono buie del tutto.
@export var luce_stanza_colore : Color = Color(1.0, 0.72, 0.45)
@export var luce_stanza_energia : float = 1.3
