extends Resource

## Il PROFILO di un mini-dungeon: le regole numeriche e il materiale con cui
## pianta_dungeon.gd genera e costruttore_dungeon.gd costruisce.
##
## Un territorio nuovo (o un DLC) aggiunge un profilo `.tres`: altre stanze,
## altri nemici, altri pezzi. Il codice resta quello.

@export_group("Griglia")
## Celle della griglia in larghezza (x) e in profondita' (z).
@export var larghezza : int = 64
@export var profondita : int = 64
## Lato di una cella, in metri.
@export var lato_cella : float = 2.0

@export_group("Stanze e corridoi")
@export var stanze_min : int = 5
@export var stanze_max : int = 9
## Lato di una stanza, in celle.
@export var stanza_lato_min : int = 6
@export var stanza_lato_max : int = 20
## Celle di distacco fra due stanze (ci passano muro e corridoi).
@export var distacco_stanze : int = 2
## Larghezza dei corridoi, in celle: ognuno la sua, da un budello a una
## galleria.
@export var corridoio_largo_min : int = 2
@export var corridoio_largo_max : int = 4
## Deviazioni di un corridoio fra le due stanze (0 = a L), e quanto lontano
## dalla linea dritta, in celle.
@export var deviazioni_min : int = 0
@export var deviazioni_max : int = 2
@export var deviazione_ampiezza : float = 7.0
## Le forme delle stanze e il loro peso: rettangolo, cerchio, croce, L,
## irregolare.
@export var pesi_forme : PackedFloat32Array = PackedFloat32Array([2.0, 1.5, 1.0, 1.0, 1.5])
## Collegamenti in piu' oltre all'albero minimo.
@export var anelli_min : int = 0
@export var anelli_max : int = 2

@export_group("Obiettivo")
## Quanti dungeon chiedono di trovare l'uscita invece di ripulire tutto.
@export_range(0.0, 1.0) var probabilita_uscita : float = 0.35
## La scala dell'uscita, quanto si affonda (il fondo dei gradini sotto il
## pavimento) e come si gira perche' l'arco stia a nord.
@export var uscita : PackedScene
@export var uscita_affondo : float = 1.0
@export var uscita_rotazione : float = 0.0

@export_group("Ruoli")
@export_range(0.0, 1.0) var probabilita_chiusa : float = 0.3
@export_range(0.0, 1.0) var probabilita_tesoro : float = 0.12

@export_group("Baratri")
@export_range(0.0, 1.0) var probabilita_baratro : float = 0.35
## Lato minimo di una stanza per avere un baratro.
@export var baratro_stanza_min : int = 9
@export var baratro_spessore : int = 2
@export var ponte_largo : int = 2

@export_group("Pezzi grossi")
## Nelle stanze grandissime (lato minimo in celle): una fontana coi canali, o
## un pezzo grosso al centro (la testa del colosso, il lampadario caduto).
@export var fontana_stanza_min : int = 12
@export_range(0.0, 1.0) var probabilita_fontana : float = 0.5
@export var fontana : PackedScene
@export var ponticello : PackedScene
@export var pezzi_grossi : Array[PackedScene] = []
@export_range(0.0, 1.0) var probabilita_pezzo_grosso : float = 0.7

@export_group("Popolamento")
## Una cella ogni quante porta un nemico in piu'.
@export var celle_per_nemico : int = 30
@export var nemici_per_stanza_max : int = 3
## Gruppi di 1-3 nemici nei corridoi.
@export var gruppi_corridoio_min : int = 1
@export var gruppi_corridoio_max : int = 3
## Piastre a pressione per dungeon, e i loro pezzi (la piastra e la bocca da
## muro).
@export var piastre_min : int = 3
@export var piastre_max : int = 6
@export var piastra : PackedScene
@export var bocca_trappola : PackedScene
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
## Il pavimento delle stanze senza tema, e quello dei corridoi.
@export var materiale_pavimento : Material
@export var materiale_corridoio : Material
@export var materiale_muro : Material
## Il modulo di muro: si ripete lungo ogni tratto, scalato alla lunghezza
## giusta. Senza, i muri restano scatole col materiale qui sopra.
@export var muro_modulo : PackedScene
## Lunghezza di un modulo, in metri (il tratto si divide in moduli di circa
## questa misura).
@export var muro_modulo_lungo : float = 4.0
## Il pilastro agli angoli e lungo i muri alti.
@export var pilastro : PackedScene
## Ogni quanti metri di muro alto un pilastro.
@export var pilastro_ogni : float = 8.0
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

@export_group("Dettagli del pavimento")
## Decal sparsi sul pavimento: crepe, sporco, muschio (una lista per tipo).
@export var decal_crepe : Array[Texture2D] = []
@export var decal_sporco : Array[Texture2D] = []
@export var decal_muschio : Array[Texture2D] = []
## Un decal ogni tante celle di pavimento.
@export var decal_ogni_celle : float = 6.0

@export_group("Temi")
## I temi delle stanze (tema_stanza.gd): ogni stanza ne prende uno compatibile
## col suo ruolo, preferendo quelli non ancora usati. Senza temi, rovine.
@export var temi : Array[Resource] = []

@export_group("Luci")
## Una luce calda per stanza, debole: riempie le ombre fra una torcia e l'altra.
## Molto debole dal 2026-10-20 (l'autore: «l'ambiente e' troppo chiaro, e'
## comunque un dark fantasy. Le luci devono essere fonti vere di luce il resto
## deve essere abbastanza scuro»): a illuminare sono i fuochi.
@export var luce_stanza_colore : Color = Color(1.0, 0.72, 0.45)
@export var luce_stanza_energia : float = 0.15
## Le torce sui muri alti e i bracieri a terra.
@export var torcia : PackedScene
@export var braciere : PackedScene
@export var torce_per_stanza_min : int = 2
@export var torce_per_stanza_max : int = 5
## Lato minimo di una stanza per avere un braciere.
@export var braciere_stanza_min : int = 9
@export var luce_fuoco_colore : Color = Color(1.0, 0.58, 0.25)
@export var luce_fuoco_energia : float = 3.2
@export var luce_fuoco_portata : float = 9.0
