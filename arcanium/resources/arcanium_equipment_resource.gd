extends EquipmentResource
class_name ArcaniumEquipmentResource

## Estende la EquipmentResource del template con il modello di Arcanium:
## - scaling per Marca (gradi S/A/B/C/D/E su una Marca primaria e una secondaria)
## - tipo di danno (per le resistenze in ArcaniumHealthSystem)
##
## COMPATIBILITÀ COL TEMPLATE: NON tocchiamo il contratto `.power`. Quando l'arma
## viene equipaggiata (o quando cambiano le Marche del portatore) chiamiamo
## `compute_power(stats)`, che scrive in `power` (ereditato) il danno effettivo
## scalato. Così EquipmentSystem/HealthSystem continuano a leggere `.power`
## esattamente come prima: lo scaling NON è più display-only.

enum Grade { NONE, E, D, C, B, A, S }

## Coefficiente di scaling per grado. È il peso massimo che una Marca "piena"
## (STAT_REF) può aggiungere al danno base, come frazione di `base_power`.
const GRADE_FACTOR : Dictionary = {
	Grade.NONE: 0.0,
	Grade.E: 0.10,
	Grade.D: 0.25,
	Grade.C: 0.40,
	Grade.B: 0.55,
	Grade.A: 0.75,
	Grade.S: 1.00,
}

const GRADE_LETTER : Dictionary = {
	Grade.NONE: "-",
	Grade.E: "E", Grade.D: "D", Grade.C: "C",
	Grade.B: "B", Grade.A: "A", Grade.S: "S",
}

## Valore di Marca a cui un grado rende il suo GRADE_FACTOR pieno. Le Marche
## partono a 10 e cresceranno ai Coni: 40 è il "cap di design" di riferimento.
const STAT_REF : float = 40.0

## ─── Display (menu Inventario/Equipaggiamento) ───────────────────────────────
@export var icon : String = "⚔"
## Illustrazione del pezzo, mostrata grande nella modale di equipaggiamento.
## Stesso schema di `SpellResource.image`: se manca, la modale disegna al suo
## posto il simbolo grande in una cornice della stessa altezza, così i pezzi
## illustrati e quelli ancora senza illustrazione non fanno "respirare" il
## riquadro cambiando misura a ogni selezione.
@export var image : Texture2D
@export_multiline var lore : String = ""
## Slot in cui compare nel pannello Equipaggiamento: arma_primaria/arma_secondaria/
## armatura_alta/armatura_bassa/scudo. Solo display, non wired a un sistema di swap.
@export var equip_slot : String = "arma_primaria"

## ⚠️ `object_type` (ereditato dal template) è il TIPO D'ARMA, e pilota il move
## set del protagonista: `weapon_type` sceglie `MovementStates/<TIPO>_tree` per
## la locomozione e `ATTACK_tree/<TIPO>` per i colpi. Il secondo si sceglie per
## advance_expression, quindi un tipo senza il suo ramo non fa scattare nessuna
## transizione e **il colpo non parte affatto** — per questo `SLASH` è scritto
## come ripiego (`weapon_type != "HEAVY"`) e non come caso esatto.
##
## ⚠️⚠️ Nei `.tres` NON si scrivono commenti: il parser scarta in SILENZIO la
## proprietà che li segue. La risorsa si carica, nessun errore, e quel campo
## resta al default. È già successo proprio su `object_type`.

## ─── Modello impugnato ──────────────────────────────────────────────────────
## Il modello 3D che compare IN MANO quando il pezzo è equipaggiato. Finché
## mancava, il menu cambiava la scheda e le statistiche ma la mano continuava a
## stringere la stessa spada del kit iniziale: l'equipaggiamento si leggeva, non
## si vedeva.
##
## Vuoto = si tiene il modello già montato nella scena del player (è il caso
## della Lama della Prima Veglia, che quel modello ce l'ha da sempre).
@export var held_model : PackedScene
## Presa: dove e come il modello si siede sul mount della mano. Contiene anche
## la SCALA, perché i modelli arrivano da pipeline diverse e nessuno è nell'unità
## del gioco (la lancia dei nemici è autorata ~12× più grande del vero).
##
## Si tara a vista, non a calcolo: vedi la skill `game-animation-craft`.
@export var held_transform : Transform3D = Transform3D.IDENTITY
## Hitbox della lama, in metri, nello spazio del mount. Una lancia che colpisce
## con la scatola di una spada corta manca tutto quello che tiene a distanza —
## che è l'unica cosa che una lancia sa fare.
@export var hitbox_size : Vector3 = Vector3.ZERO
@export var hitbox_offset : Vector3 = Vector3.ZERO

## ─── Modello INDOSSATO ──────────────────────────────────────────────────────
## Le piastre che compaiono ADDOSSO quando il pezzo è equipaggiato. Le monta
## `arcanium/systems/armatura_indossata.gd`, che è a questo campo ciò che
## `held_weapon.gd` è a `held_model`.
##
## ⚠️ NON è un modello rigido appeso a un osso: è un `.glb` con dentro le mesh
## GIÀ PESATE sulle ossa del corpo (le produce `arcanium/tools/vesti_protagonista.py`).
## Del `.glb` si tengono solo le mesh, e la loro Skin si lega per NOME D'OSSO
## allo scheletro del personaggio.
@export var worn_model : PackedScene

## Quali mesh prendere dal `worn_model`, per nome. VUOTO = tutte, che è il caso
## normale di un file per pezzo.
##
## Serve quando un solo `.glb` porta l'intero set e due slot se ne dividono i
## pezzi — è il caso di `prima_veglia_set.glb`, dove la corazza e i bracciali
## vanno all'armatura alta e i gambali a quella bassa. Tenerli in un file solo
## non è pigrizia: la vestizione li produce in un giro solo perché condividono
## il corpo donatore, e spezzarli in cinque `.glb` significherebbe cinque volte
## lo stesso scheletro su disco.
@export var worn_pieces : PackedStringArray = PackedStringArray()

## ─── Lucida Tecnica ─────────────────────────────────────────────────────────
## Il colpo iconico che QUESTA arma sa insegnare. Vuoto per le armi comuni: la
## Lucida Tecnica è ciò che distingue un'arma speciale da una buona arma.
##
## Sta sull'ARMA e non sul giocatore perché è la lore a chiederlo — la tecnica
## appartiene a chi la spada l'ha portata prima di te, e la perdi quando la
## riponi. Il corollario tecnico è comodo: dare una tecnica nuova a un'arma
## nuova è compilare due `.tres`, senza toccare il giocatore.
@export var lucida_tecnica : Resource

## ─── Arco ───────────────────────────────────────────────────────────────────
## La FRECCIA che QUEST'arco tira (una scena come `freccia.tscn`). Sta
## sull'arma e non sul set d'arco del protagonista perche' e' l'arco a dire
## cosa esce dalla corda: l'Arco di Spirito tira Spirito, un arco di tasso
## tira ferro. Vuota = la freccia del `SetArco` (quella di ferro).
@export var freccia : PackedScene
## Quanto la freccia SPOSTA chi la prende (m/s, vedi `EnemyMove.spinta`): il
## tiro rapido spinge di un passo, il caricato — `heavy_spinta_mult` — di
## qualche metro. Serve al giocatore per buttare giu' un nemico in bilico su
## una piattaforma, com'e' la tattica degli arcieri contro di lui.
@export var spinta : float = 0.0
@export var heavy_spinta_mult : float = 2.2

## Se true, questo oggetto è un FOCUS ARCANO (il Sigillo/"bastone"): solo con
## esso equipaggiato al posto dello scudo il mago può lanciare incantesimi e
## summon. Lanciare richiede concentrazione — si rinuncia alla difesa dello
## scudo per castare. Lo scudo usa un'altra classe (ArcaniumShieldResource) e
## quindi non ha questo campo: il check lato player degrada a "false".
@export var is_spell_focus : bool = false

## Danno di base dell'arma, prima dello scaling. `power` (ereditato) viene
## RICALCOLATO da questo + Marche: non impostare `power` a mano nei .tres.
@export var base_power : int = 1

@export var primary_marca : MarcheStats.Marca = MarcheStats.Marca.VOL
@export var primary_grade : Grade = Grade.D
@export var secondary_marca : MarcheStats.Marca = MarcheStats.Marca.RES
@export var secondary_grade : Grade = Grade.NONE

## Tipo di danno, letto dalle resistenze del bersaglio (ArcaniumHealthSystem).
@export_enum("FISICO", "TAGLIO", "PERFORAZIONE", "SCHIANTO", "CRIO", "EROSIONE", "SACRO", "FRATTURA", "VELENO", "FUOCO", "FULMINE") var damage_type : String = "FISICO"

## ─── PESO DEL COLPO (scossa di camera) ───────────────────────────────────────
##
## Quanto trema lo schermo quando questo colpo va a segno. Si usano le costanti
## di `Scossa`: LEGGERO (0.16), MEDIO (0.38), PESANTE (0.62), DEVASTANTE (1.0).
##
## A 0 (default) decide `ArcaniumHealthSystem` in base al danno finale. Va bene
## per la maggior parte delle cose, ma è un ripiego: il peso di un colpo è una
## scelta di direzione, non una conseguenza aritmetica del danno. Una spallata
## che fa poco male può essere pesantissima, e una stoccata che ne fa tanto può
## essere secca e silenziosa. Quando le due cose divergono, il numero si scrive
## QUI e vince sulle soglie.
##
## ⚠️ Il colpo caricato del player è esattamente il caso da dichiarare a mano:
## deve leggersi come "caricato" anche quando incontra un nemico resistente che
## gli dimezza il danno, e con le sole soglie scenderebbe di gradino proprio nel
## momento in cui il giocatore ha speso di più per darlo.
@export_range(0.0, 1.0, 0.01) var scossa : float = 0.0

## ─── Status inflitti al colpo (opzionali) ────────────────────────────────────
## Letti da ArcaniumHealthSystem e instradati allo StatusHost del bersaglio.
## Tipicamente valorizzati sulle mosse dei nemici (Fase 4), ma disponibili anche
## per armi speciali (es. la Spada del Senza Nome).

## Applica Frattura (vulnerabilità) al colpo.
@export var inflicts_fracture : bool = false
@export var fracture_multiplier : float = 1.35
@export var fracture_duration : float = 15.0

## Aggiunge build-up di Erosione dell'Eco al colpo (attacchi "Gruppo A").
@export var builds_echo : bool = false

## Poise-break: quanta barra costruisce questo colpo sul bersaglio (letta da
## ArcaniumHealthSystem._route_statuses → status_host.get_effect("poise_break")).
## Il colpo caricato usa `heavy_poise_mult` (vedi sotto) per costruirne di più.
@export var poise_damage : float = 10.0
## Moltiplicatori applicati SOLO all'attacco forte (vedi equipment_system.gd,
## che duplica la risorsa per non mutare quella condivisa dall'attacco leggero).
@export var heavy_power_mult : float = 1.3
@export var heavy_poise_mult : float = 2.0

## Contributo frazionario di una singola Marca (0..GRADE_FACTOR massimo).
func _scaling_contribution(grade : Grade, stat_value : int) -> float:
	var factor : float = GRADE_FACTOR.get(grade, 0.0)
	return factor * (float(stat_value) / STAT_REF)

## Danno effettivo dato un set di Marche. Non ha effetti collaterali: utile
## anche per la UI (mostrare l'attack rating senza equipaggiare).
func power_with(stats : MarcheStats) -> int:
	if stats == null:
		return base_power
	var mult : float = 1.0
	mult += _scaling_contribution(primary_grade, stats.get_marca(primary_marca))
	mult += _scaling_contribution(secondary_grade, stats.get_marca(secondary_marca))
	return int(round(float(base_power) * mult))

## ─── Difesa (armature) ──────────────────────────────────────────────────────
## Moltiplicatore di danno SUBITO per tipo, mentre il pezzo è indossato: <1
## protegge, >1 espone. Solo i tipi dichiarati contano, gli altri restano a 1.0.
##
## Si moltiplicano fra loro i pezzi indossati (vedi EquipmentLoadout), quindi due
## pezzi da 0.9 sullo stesso tipo fanno 0.81 e non 0.8: le protezioni si
## sommano con rendimenti decrescenti invece di arrivare a zero impilandone
## abbastanza.
## Frazione di Arcanium Cristallizzato IN PIÙ da ogni uccisione, mentre il pezzo
## è indosso (0.20 = +20%). I pezzi si sommano fra loro, come i bonus alle
## evocazioni: e' un bonus offensivo, e la somma e' la lettura che il giocatore
## si aspetta.
##
## Sta tipicamente su un TALISMANO: gli slot sono quattro e sempre contesi,
## quindi portarne uno costa rinunciare a un ALTRO talismano. È li' che vive la
## scelta di build, non nel togliersi un'arma.
@export var arcanium_bonus : float = 0.0

@export var resistances : Dictionary = {}

## ─── Evocazioni ─────────────────────────────────────────────────────────────
## Bonus al danno delle evocazioni, per FAMIGLIA: `{"bestia": 0.15}` = +15% alle
## creature di tipo bestia finché il pezzo è indosso. Una famiglia vuota o
## assente non riceve nulla.
@export var summon_damage_bonus : Dictionary = {}


## Ricalcola e SCRIVE `power` (contratto col template). Chiamare all'equip e
## quando le Marche cambiano (level-up ai Coni).
func compute_power(stats : MarcheStats) -> int:
	power = power_with(stats)
	return power

## Stringa di scaling per la UI, es. "VOL D · RES D". Display-only.
func scaling_label() -> String:
	var out := "%s %s" % [MarcheStats.SIGLE_MOSTRATE[primary_marca], GRADE_LETTER[primary_grade]]
	if secondary_grade != Grade.NONE:
		out += " · %s %s" % [MarcheStats.SIGLE_MOSTRATE[secondary_marca], GRADE_LETTER[secondary_grade]]
	return out
