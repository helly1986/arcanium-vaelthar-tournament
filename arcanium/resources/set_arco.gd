@tool
extends Resource

## ═══════════════════════════════════════════════════════════════════════════
## SET D'ARCO — le clip del protagonista quando ha un arco in mano
## ═══════════════════════════════════════════════════════════════════════════
##
## Il tipo d'arma `BOW` non e' un'arma: e' un MODO DI MUOVERSI e un modo di
## colpire, condivisi da tutti gli archi. Le clip di quel modo stanno qui, una
## risorsa sola per tipo, letta da `arcieria_player.gd` che le innesta
## nell'AnimationTree del protagonista (`MovementStates/BOW_tree` e
## `ATTACK_tree/BOW`). L'arco specifico (numeri, modello, illustrazione) resta
## nel suo `.tres` in `resources/weapons/`, con `object_type = "BOW"`.
##
## Le clip sono GLB come quelli dei nemici (`assets/characters/enemies/anims/`),
## caricati con `clip_da_glb.gd`: si autorano in Cascadeur e si esportano con la
## catena della combo. Finche' una clip non c'e', la locomozione resta quella
## della spada e il tiro usa il gesto di lancio segnaposto — si vede, ma
## funziona, e cambiare clip e' cambiare un path qui.
##
## Nessun `class_name`: si carica per percorso (vedi arcanium-preload-non-class-name).

## Il gesto del tiro RAPIDO: carica, mira, rilascio. Obbligatorio.
@export_file("*.glb") var clip_tiro : String = ""
## A che frazione della clip la FRECCIA si vede nella mano che tira, estratta
## dalla faretra (`freccia_in_mano.gd`); dall'incocco sta sulla corda, al
## rilascio vola. 0 = mai. Si misura con `arcanium/tools/misura_arco.tscn`.
@export_range(0.0, 0.95, 0.01) var estrazione : float = 0.0
## A che frazione della clip la corda comincia a seguire la mano: l'INCOCCO,
## quando la sinistra si posa sulla corda con la freccia. Prima sta nella
## faretra. Si misura con `arcanium/tools/misura_arco.tscn` sulla clip dei
## nemici (stesse chiavi, stessi istanti) e si divide per la durata.
@export_range(0.0, 0.95, 0.01) var incocco : float = 0.0
## A che frazione della clip la freccia parte. Si MISURA sulla clip autorata
## (l'istante in cui le dita lasciano la corda), non si stima.
@export_range(0.05, 0.95, 0.01) var rilascio : float = 0.66
## Il tiro CARICATO (colpo forte): piu' lungo, piu' danno e posa, e SPINGE il
## bersaglio — e' il tiro per buttare giu' chi sta in bilico. Vuoto = si usa
## la clip del rapido anche per il caricato.
@export_file("*.glb") var clip_tiro_caricato : String = ""
@export_range(0.0, 0.95, 0.01) var estrazione_caricata : float = 0.0
@export_range(0.0, 0.95, 0.01) var incocco_caricato : float = 0.0
@export_range(0.05, 0.95, 0.01) var rilascio_caricato : float = 0.72
## Locomozione con l'arco: idle e passo/corsa in avanti. Vuoto = si tiene la
## locomozione della spada per quel punto del blend.
@export_file("*.glb") var clip_idle : String = ""
@export_file("*.glb") var clip_cammino : String = ""
@export_file("*.glb") var clip_corsa : String = ""

## La freccia e come vola.
@export var freccia : PackedScene
## La presa della freccia nella mano che tira (`mano_che_tira`, il pivot della
## sinistra) fra estrazione e incocco: la stampa `misura_presa_arco.tscn`
## all'istante dell'incocco, cosi' la freccia arriva sulla corda senza scatti.
## Si ricalcola se cambia la presa dell'arco, la clip o la lunghezza della
## freccia (`freccia.gd`).
@export var presa_freccia : Transform3D = Transform3D.IDENTITY
@export var velocita_freccia : float = 30.0
## Da dove parte, se l'arco in mano non ha un incocco: davanti al petto.
@export var altezza_bocca : float = 1.35


func valida() -> bool:
	return clip_tiro != "" and freccia != null
