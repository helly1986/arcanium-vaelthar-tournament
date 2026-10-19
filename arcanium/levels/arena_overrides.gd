@tool
extends Resource
class_name ArenaOverrides

## Persistenza su disco delle rifiniture a mano fatte in editor su un'arena
## generata da `ArenaBuilder`.
##
## PERCHÉ ESISTE: la geometria dell'arena la genera il codice, ma le posizioni
## "belle" si trovano a occhio nell'editor. Senza questo file, premere `rebuild`
## (necessario ogni volta che si cambia l'algoritmo di generazione) butterebbe
## via ogni ritocco. Con questo file il ciclo diventa non distruttivo:
##     genera → sposta a mano → SALVA LAYOUT → rebuild → i ritocchi tornano.
##
## COS'È UN ID: il nome del nodo generato, assegnato in modo deterministico dal
## builder come `<pezzo>_<progressivo>` (es. `column_03`, `rock_17`). Il
## progressivo è PER CATEGORIA, non globale: aggiungere detriti non sfasa le
## colonne. ⚠️ Rinominare a mano un nodo generato ne spezza il collegamento con
## l'override (l'id È il nome) — per riagganciarlo, rinominalo com'era.
##
## Le tre tabelle sono separate apposta:
## - `pristine` è la fotografia di ciò che il CODICE produce. Riscritta a ogni
##   build completa. Serve come riferimento per capire cosa è stato spostato
##   (all'apertura di una scena salvata il builder non ha più quel dato in
##   memoria) e come rete per tornare indietro.
## - `overrides` contiene SOLO gli oggetti effettivamente spostati a mano.
## - `deleted` gli id rimossi a mano, che il builder non deve ricreare.
##
## Gli oggetti AGGIUNTI a mano non stanno qui: vanno messi sotto il nodo
## "HandPlaced", che il builder non tocca mai. Così puoi aggiungere qualunque
## tipo di nodo con tutte le sue proprietà, invece di serializzare solo una
## transform.

## id → Transform3D come lo genera il codice (riferimento e ripristino).
@export var pristine : Dictionary = {}

## id → Transform3D scelto a mano. Vince sul pristine.
@export var overrides : Dictionary = {}

## id che a mano sono stati cancellati: il builder li rigenera e poi li rimuove.
@export var deleted : PackedStringArray = []

func clear_edits() -> void:
	overrides.clear()
	deleted = PackedStringArray()
