@tool
extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## EQUIP PLAYGROUND — banco di TARATURA dell'equipaggiamento
## ═══════════════════════════════════════════════════════════════════════════
##
## Qui non si gioca. Non c'è il player, non c'è l'AI, non c'è l'HUD: c'è il rig
## del protagonista e, appesi ai suoi mount veri, i modelli di ogni pezzo
## d'equipaggiamento come NODI NORMALI. Si selezionano e si trascinano
## nell'editor, esattamente come si fa con l'equipment dei nemici.
##
## Perché serve: le prese delle armi vivono nei `.tres`, dove sono dodici numeri
## da digitare a mano e nessuna anteprima. Tararle così è indovinare. Qui invece
## si vede, e quello che si vede è quello che varrà in gioco, perché i mount di
## questa scena sono COPIA ESATTA di quelli di `player_dawnkeep_v4.tscn`:
##
##   ManoDestra   ← WeaponSystem/RightHand      (osso RightHand, idx 43)
##   HandPivot    ← WeaponSystem/RightHand/HandPivot
##   ManoSinistra ← GadgetSystem/LeftHand       (osso LeftHand, idx 20)
##   Anca         ← GadgetSystem/HipBone        (osso Chest, idx 15)
##
## ⚠️ Gli indici sono quelli dello scheletro a 61 ossa di `protagonista_v4.glb`.
## Col vecchio corpo a 24 ossa erano 19/15/10: un `bone_idx` sbagliato non da'
## errore, appende l'arma a un altro osso.
##
## ⚠️ L'`Anca` è il posto dove il TEMPLATE parcheggia il gadget non impugnato,
## non uno slot d'equipaggiamento. Tutto ciò che si equipaggia sta in una delle
## due mani: lì va tarato, perché è lì che si vedrà mentre il braccio si muove.
##
## ⚠️ Se un giorno quei mount cambiano nella scena del player, vanno ricopiati
## qui: un banco di prova che diverge dal gioco mente, ed è peggio che non
## averlo (stessa lezione del battle playground con `anim_speed_scale`).
##
## GIRO DI LAVORO
##   1. apri questa scena, scegli il pezzo dai menù qui sotto nell'inspector;
##   2. trascina il nodo `Grip_*` finché la presa non convince;
##   3. dimmelo: leggo i transform da questo `.tscn` e li riverso nei `.tres`
##      e nelle scene di gioco con `arcanium/tools/export_grips.py`.
##
## La posa è quella di REST dello scheletro — in gioco il braccio si muove, e
## una presa che regge solo a riposo può ancora tradire. Questo banco toglie il
## grosso dell'errore, non l'ultimo controllo a schermo.

## I pezzi che si possono impugnare a destra. L'ordine segue i nodi `Grip_*`.
enum Arma { LAMA_PRIMA_VEGLIA, SPADA_SENZA_NOME, LANCIA_DEL_CONSUMATO }
## La mano SECONDARIA (sinistra) tiene una cosa sola per volta: o lo scudo o il
## sigillo. Non sono due pezzi diversi che convivono — il sigillo è il focus
## arcano, e si castano incantesimi solo rinunciando alla difesa dello scudo.
enum Secondaria { SCUDO, SIGILLO, NIENTE }

@export var arma : Arma = Arma.LAMA_PRIMA_VEGLIA : set = _set_arma
@export var secondaria : Secondaria = Secondaria.SCUDO : set = _set_secondaria

const MANO_DESTRA := "ManoDestra/HandPivot"
const MANO_SINISTRA := "ManoSinistra/HandPivot"
const NOMI_ARMA := ["Grip_lama_prima_veglia", "Grip_spada_senza_nome",
	"Grip_lancia_del_consumato"]
const NOMI_SECONDARIA := ["Grip_scudo_prima_veglia", "Grip_sigillo_prima_veglia"]


func _ready() -> void:
	_aggiorna()


func _set_arma(v : Arma) -> void:
	arma = v
	_aggiorna()


func _set_secondaria(v : Secondaria) -> void:
	secondaria = v
	_aggiorna()


## Sola visibilità: NON tocca mai i transform, che sono il contenuto vero di
## questa scena. Uno strumento di taratura che sposta ciò che stai tarando è
## un modo elaborato di perdere il lavoro.
func _aggiorna() -> void:
	if not is_inside_tree():
		return
	for i in NOMI_ARMA.size():
		var n := get_node_or_null(MANO_DESTRA + "/" + NOMI_ARMA[i]) as Node3D
		if n != null:
			n.visible = i == int(arma)
	for i in NOMI_SECONDARIA.size():
		var n := get_node_or_null(MANO_SINISTRA + "/" + NOMI_SECONDARIA[i]) as Node3D
		if n != null:
			n.visible = i == int(secondaria)
	_avvisa_pezzi_fuori_posto()


## Un `Grip_*` appeso a un mount che non è quello del suo slot è il modo più
## silenzioso di buttare via una taratura: a riposo si vede giusto, e sbaglia a
## ogni frame in cui quell'osso e il suo si muovono in modo diverso. È già
## successo col sigillo, montato sull'osso Chest mentre è un pezzo di mano.
func _avvisa_pezzi_fuori_posto() -> void:
	for nome in NOMI_SECONDARIA:
		if get_node_or_null(MANO_SINISTRA + "/" + nome) != null:
			continue
		var vagante := find_child(nome, true, false)
		if vagante != null:
			push_warning("EquipPlayground: '%s' pende da '%s' invece che da %s. "
				% [nome, vagante.get_parent().name, MANO_SINISTRA]
				+ "Trascinalo sul mount giusto (Godot conserva la posa nel mondo).")
