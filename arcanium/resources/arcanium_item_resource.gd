extends ItemResource
class_name ArcaniumItemResource

## Estende l'ItemResource del template con i campi di design di Arcanium (dai
## data/*.json di Lite): categoria, icona, effetto+entità, conteggio iniziale,
## fonte e lore. Non tocca il contratto del template (item_name/object_type/...).

@export var id : String = "item"
@export_enum("arma", "sigillo", "armatura", "talismano", "consumabile", "curiosita") var category : String = "consumabile"
@export var icon : String = "●"
## Effetto all'uso (per ora: "heal"; estendibile: "cure_status", "buff"...).
## `minion_vigore`: +`amount` (frazione) di vita ai minion per `durata` secondi
## (l'Estratto di Kalvorn, arcanium/systems/summons/vigore_minion.gd).
@export_enum("none", "heal", "cure_status", "buff", "minion_vigore") var effect : String = "none"
@export var amount : float = 0.0
## Per `effect = "cure_status"`: l'id dello stato che cura (es. "laceration").
@export var stato : String = ""
## Per gli effetti a tempo: quanti secondi durano.
@export var durata : float = 0.0
@export var start_count : int = 1
@export var source : String = ""
@export_multiline var lore : String = ""

## ─── Cosa INSEGNA, se è un tomo ─────────────────────────────────────────────
## Una `TecnicaGuerra` (`arcanium/resources/tecnica_guerra.gd`), o null per
## qualunque oggetto che non insegni niente — cioè quasi tutti.
##
## Sta sull'OGGETTO e non su chi lo consegna per la stessa ragione di
## `_concedi_equipaggiabile` in `arcanium_inventory.gd`: il tomo può arrivare da
## un baule, da un drop, da una bottega o da un dialogo, e se l'insegnamento
## fosse cablato nel baule le altre tre strade lo dimenticherebbero — com'è già
## successo alla Spada del Senza Nome col suo equipaggiabile. Il ponte lo tira
## l'inventario, una volta sola, per qualunque strada l'oggetto prenda.
@export var insegna : Resource
