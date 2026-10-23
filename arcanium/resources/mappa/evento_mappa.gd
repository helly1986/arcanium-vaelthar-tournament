extends Resource

## Un EVENTO del nodo Imprevisto della mappa della run: un titolo, un testo e
## 2-3 scelte. Sono dati (arcanium/resources/mappa/eventi/): un evento nuovo e'
## una scheda in piu'.
##
## Ogni scelta e' un Dictionary:
##   "nome"         il pulsante;
##   "spiegazione"  cosa fa, in piccolo sotto;
##   "costo"        Arcanium da pagare per sceglierla (x tappa; 0 = gratis);
##   "effetti"      {"arcanium": n (x tappa), "salute": n, "affilatura": n,
##                   "allenamento": n, "studio": n, "medita": 1,
##                   "oggetto": "consumabile"|"pezzo"|"varco"|"vita"};
##   "esito"        il testo dopo la scelta;
##   "rischio"      facoltativo: {"probabilita": 0-1, "effetti": {...},
##                   "esito": "..."}, l'esito storto che a volte va al posto
##                   di quello buono.
## La salute massima si alza e si abbassa SOLO qui e coi consumabili speciali
## (decisione dell'autore del 2026-10-22).

@export var id : String = ""
@export var titolo : String = ""
@export_multiline var testo : String = ""
@export var scelte : Array[Dictionary] = []
