extends Resource
class_name TipoNodoMappa

## Un TIPO DI NODO della mappa della run (design-mappa-run, decisioni
## dell'autore del 2026-10-19 e del 2026-10-22): scontro, elite, battleground,
## boss, tesoro, imprevisto, riposo, mercante. Sono dati: un tipo nuovo (le
## espansioni) e' una scheda in piu' in arcanium/resources/mappa/tipi/, e il
## generatore (mappa_run.gd) lo piazza secondo questi campi.

## La chiave del tipo: la usano la mappa e chi esegue il nodo.
@export var id : String = ""
## Il nome che legge il giocatore (inglese, passa da tr()).
@export var nome : String = ""
@export_multiline var descrizione : String = ""
## Il segno sul medaglione finche' non ci sono le icone dipinte.
@export var icona : String = "?"
@export var colore : Color = Color(0.8, 0.75, 0.6)
## Vero per i nodi che si giocano nel dungeon (scontro, elite, boss,
## battleground): vincerli fa proseguire, perderli conta come sconfitta.
@export var combattimento : bool = false

@export_group("Dove e quanti, per regione")
## Primo e ultimo piano in cui puo' comparire (0 = il primo piano della
## regione; il piano del boss non e' mai fra questi).
@export var piano_min : int = 1
@export var piano_max : int = 4
@export var min_per_regione : int = 0
@export var max_per_regione : int = 0
## Ordine in cui il generatore riempie i posti: prima i tipi con le regole
## piu' strette, cosi' trovano ancora spazio.
@export var priorita : int = 0
## Il riposo prima del boss: almeno un nodo di questo tipo nell'ultimo piano
## prima del boss.
@export var prima_del_boss : bool = false
