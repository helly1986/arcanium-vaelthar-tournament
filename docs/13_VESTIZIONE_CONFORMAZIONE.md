# Come si veste un personaggio, davvero

> Nato il 2026-08-20, dopo che la vestizione a trasformazioni rigide ha mostrato
> il suo limite: lasciava **scoperto circa il 40% della pelle** che avrebbe dovuto
> coprire, e nessuna taratura lo chiudeva. Il gioco ha bisogno di **decine** di
> armature: serviva una strada che regga a quel numero.
>
> Ogni affermazione qui sotto è stata **provata e guardata**. Gli script e i
> render stanno in `arcanium/tools/prove/`.

## ⛔ PRIMA DI TUTTO: conta le dita

**Meshy genera spesso SEI dita invece di cinque.** E' un difetto noto del
generatore, non la sfortuna di un pezzo.

Il bracciale della Prima Veglia ne ha sei — cinque in fila piu' il pollice — e non
ce ne siamo accorti per settimane, mentre ci si costruiva sopra fitting,
pesatura, affilatura e conformazione. **Tutto da rifare**, perche' nessuna di
quelle tecniche mappa sei dita su cinque.

Cancello: `arcanium/tools/conta_dita.py`. Si passa **prima** di investire un
minuto su un pezzo generato che tocca mani o piedi.

```
blender --background --factory-startup --python arcanium/tools/conta_dita.py -- <file.glb>
```

⚠️ Si conta per TOPOLOGIA, non a occhio: da un tre quarti la prospettiva accorcia
e si sbaglia. E il **pollice** alle quote delle punte si e' gia' fuso col palmo —
cinque isole in fila equispaziate vogliono dire **sei** dita.

## Il difetto della pipeline vecchia, in una riga

`vesti_protagonista.py` applica **solo trasformazioni rigide** — scala, ruota,
sposta. Non deforma mai la mesh per farla aderire al corpo.

Da lì discendono tutti i difetti, e sono **due problemi distinti** che è facile
scambiare per uno:

| | domanda | da cosa dipende |
|---|---|---|
| **Copertura** | il pezzo arriva dove deve? | dall'ESTENSIONE della mesh sorgente. Nessuna trasformazione la crea |
| **Aderenza** | lungo quel tratto sta appiccicato? | dalla DEFORMAZIONE. Le trasformazioni rigide non ne fanno |

## Cosa è stato provato e ha fallito

| tentativo | esito misurato |
|---|---|
| Scala uniforme più grande | il pezzo diventa lungo *e* grasso nella stessa misura |
| `cinghia` (circonferenza separata dalla lunghezza) | utile sulle gambe (+10% chiude le strisce nude), **non** risolve le braccia |
| Bracciale allungato alla spalla, `cinghia` 0.60 | tubo troppo stretto: il braccio esce di sopra. Spalla nuda |
| Idem, `cinghia` 0.88 | tubo grasso, resta **sotto** il braccio. Spalla nuda |
| Proiezione dei vertici sul corpo (shrinkwrap fatto a mano) | il rilievo si azzera: manica lucida |
| Idem, conservando il rilievo lungo la normale | **peggio**: nastri e schegge |

⚠️ **La ragione geometrica del fallimento delle braccia**, che vale per ogni
pezzo d'arto: il pezzo viene posato lungo la **corda** fra i due ossi, e la
catena spalla→gomito→dita **non è dritta**. Un tubo rettilineo su un arto che
piega passa sotto il gomito comunque lo si dimensioni. Gomito→dita invece è
quasi rettilineo — ed è per questo che il disegno originale stava così.

⚠️ **La ragione del fallimento della proiezione**: il pezzo generato è un
**guscio chiuso con spessore**. Proiettando i vertici sulla superficie del corpo,
parete interna ed esterna finiscono sullo **stesso punto**: il guscio collassa su
sé stesso e si strappa. Una proiezione vertice-per-vertice non può conformare un
solido.

## LA RICETTA CHE FUNZIONA

Quattro passi. **L'ordine conta, e il passo 2 è quello che nessuno racconta.**

1. **Posare** il pezzo grossolanamente sull'arto — il posamento rigido di oggi
   va benissimo, e si dichiara sull'arto INTERO (spalla→dita), non su un pezzo.
2. **Calcolare il vertex group di ADERENZA**, cioè quanto ogni vertice deve
   muoversi. È una **fascia attorno alla pelle**, non una semiretta:
   - fra `affondo` sotto la pelle e `stacco` sopra → peso **1**, aderisci
   - più lontano di `stacco + fascia` → peso **0**, resta dove sei
   - più sepolto di `affondo + fascia` → peso **0**, resta dove sei
   - nelle due zone in mezzo → sfuma
3. **Shrinkwrap** con `wrap_mode = OUTSIDE`, `offset` = lo stacco della piastra
   dalla pelle (~9 mm), **pesato da quel vertex group**.
4. **Solidify** solo se la sorgente era una superficie sottile. Se il pezzo lo
   spessore ce l'ha già, non serve.

### Perché funziona, nei tre punti che contano

⚠️⚠️ **`OUTSIDE`, e NON `OUTSIDE_SURFACE`.** I due nomi si somigliano e i due modi
fanno il contrario. `OUTSIDE` muove **solo i vertici che stanno dentro**,
spingendoli fuori di `offset`, e quelli già fuori li lascia dove sono.
`OUTSIDE_SURFACE` **proietta sulla superficie** — a distanza `offset`, ma
proietta — tutto ciò che ha peso, parete esterna compresa.

> **Questo documento diceva il contrario, ed è da qui che l'errore è entrato in
> pipeline.** Costo: i gambali sfrangiati attorno al ginocchio, con le schegge
> che si accavallavano fra le due gambe, e schegge sparse sulla spalliera.
> Trovato bisezionando — rendere il pezzo dopo OGNI stadio, stessa camera e
> stesso materiale: `arcanium/tools/prove/bisezione_gambali.py`.
>
> ⚠️ E i due render che avevano «scagionato» la conformazione non erano
> confrontabili: uno faceva `materials.append` e lasciava il grigio Meshy allo
> slot 0, l'altro faceva `materials.clear()` e rendeva in metallo scuro. Su
> metallo scuro un difetto di normali si vede, su grigio opaco no. **Un confronto
> fra due render con materiali diversi non è un confronto.**
>
> Misurato sui gambali con `OUTSIDE_SURFACE`: **1.720 vertici mossi su 3.894**,
> mentre dentro la carne ce n'erano **689**. E **1.075 dei mossi guardavano
> FUORI**, cioè erano la faccia che si vede. Con `OUTSIDE`: 897 mossi, e nel
> render la fascia del ginocchio e il calzare restano interi
> (`esito_wrap_OUTSIDE.png` contro `esito_wrap_OUTSIDE_SURFACE.png`).

⚠️ **La fascia di aderenza ha un FONDO, e serve.** «Dentro il corpo → peso 1»
sembra ovvio e non lo è: sui gambali la cima del cosciale è sepolta fino a **12
cm** dentro il bacino, e con peso 1 lo shrinkwrap la catapulta fuori di 13 cm,
in schegge. Un pezzo di piastra sepolto nella carne è **invisibile**;
catapultato è una scheggia che si vede. Provati i fondi 60/35/18 mm: a 35 mm il
p99 dello spostamento scende da 10,9 cm a 4,5 cm e le schegge spariscono
(`esito_fondo_NESSUNO.png` contro `esito_fondo_035.png`).

⚠️ **Il vertex group conserva lo spessore da solo.** La parete INTERNA del guscio
è vicina alla pelle → peso 1 → si appoggia. La parete ESTERNA, cioè le cime delle
piastre, è lontana → peso 0 → non si muove. Il guscio non collassa, e non si
toglie nemmeno una faccia.

⚠️ **Il peso non si dipinge a mano: si CALCOLA** dalla distanza dal corpo. Vale
per qualunque pezzo su qualunque corpo, senza intervento. È questo che rende la
cosa sostenibile su decine di armature.

**Misurato**: sul bracciale della Prima Veglia, **728 vertici su 3.859** erano
dentro la carne.

⚠️ **Il bersaglio va SALDATO.** Da glTF il corpo arriva spezzato su ogni cucitura
UV: su `protagonista_v4` sono **12.312 spigoli di bordo**, cioè una superficie
aperta dappertutto, e la regione ritagliata ne eredita i buchi — nella gamba il
**piede resta un'isola staccata** (`esito_bersaglio_bucato.png`). Su una
superficie aperta il «dentro» non è definito: il punto più vicino cade sul bordo
e la normale lì vale quel che vale. Un `remove_doubles` a 1e-4 sul corpo porta i
bordi a **zero**.

**Guardato** (`arcanium/tools/prove/esito_J_sartoriale.png`): spalliera,
cubitiera, vambrace e guanto con le dita articolate, dalla spalla alle nocche.
Nessuno strappo, nessuna scheggia, nessun buco. Legge come armatura vera.

### La strada peggiore, provata prima

**Scorticare** il guscio (togliere le facce la cui normale punta verso il corpo)
e poi shrinkwrap + Solidify. Funziona, ma buca: sul bracciale toglieva **3.358
facce su 7.810** e lasciava strappi al gomito e schegge alle dita
(`esito_I_ricetta_braccio_intero.png`). Il vertex group ottiene lo stesso
risultato senza togliere niente. **Non rifarla.**

## L'altra metà: il guscio DERIVATO DAL CORPO

Per i pezzi che devono **avvolgere** un arto c'è una strada ancora più diretta:
non partire da una mesh generata, ma **ritagliare la superficie del corpo** sulla
regione dichiarata (per osso), staccarla di 8-10 mm lungo la normale e
ingrossarla.

Misurato: braccio 8.317 vertici in regione su 66.190, gamba 11.798. Copre
**esattamente** ciò che si dichiara e aderisce **per costruzione**, perché *è* la
superficie del corpo — interno coscia compreso, che era il buco peggiore.

Cosa non dà: l'aspetto. Legge come una muta, e i bordi sono seghettati perché
seguono la soglia di peso vertice per vertice.

## ⚠️ UNA MANO NON È UN ARTO

Il guscio derivato funziona su braccia e gambe — dimostrato. **Sulla mano
fallisce**, e vale la pena sapere perché: una mano non è un cilindro, sono
**cinque tubi sottili con pieghe profonde in mezzo**. Tutto ciò che regge su un
arto lì si rompe.

Cinque strade provate per ricavare un guanto dal corpo, tutte fallite:

| tentativo | perché fallisce |
|---|---|
| stacco lungo la normale + solidify | i gusci di dita adiacenti si **compenetrano** nelle pieghe |
| lisciatura forte per rimediare | il laplaciano **restringe**: sui tubi sottili li collassa, la pelle esce |
| taglio sulla curva di livello | risolve i **bordi** a scaletta, non la compenetrazione |
| voxel remesh a 4,5 mm | grana più grossa del guscio: **se lo mangia** (590 vertici di schegge) |
| voxel remesh a 2,8 mm | una superficie sottile aperta non voxelizza in un solido: **frammenti staccati** |

Script: `arcanium/tools/prove/rifai_guanto.py`.

**Decisione**: il guanto vero si modella **una volta sola**, come asset a sé. Una
mano è una mano: quello stesso guanto varrà per ogni armatura di ogni casata, su
ogni corpo. È il pezzo che merita lavoro manuale più di ogni altro.

Intanto la Prima Veglia ha i **bracciali senza guanto** — un look legittimo, e il
taglio al polso è pulito.

## Il taglio dichiarabile: `taglia_su`

Quando una mesh generata comprende una parte che non si vuole (o che è
sbagliata), si dichiara nella tabella `VESTIZIONE` su quali ossa **non** deve
arrivare, e la pipeline la taglia. Non a occhio e non a quota fissa: per ogni
vertice si guarda **su quale osso pesa il punto del corpo più vicino**.

Il bordo viene pulito perché il campo si **liscia prima** e poi si taglia **sulla
curva di livello**, spezzando gli spigoli che la attraversano nel punto esatto.
Cancellare vertici interi darebbe una scaletta comunque.

Misurato sui bracciali: 131 e 134 spigoli spezzati, 1.916 e 1.870 vertici via.

## La divisione che riconcilia tutte le prove

Non è «Meshy **o** Blender». È **quale pezzo**:

| tipo di pezzo | esempi | come si fa |
|---|---|---|
| **Sta in rilievo** | spalliera, ginocchiera, corazza, calzare, falda | **posamento rigido**, quello di oggi. E infatti sono esattamente i pezzi che oggi stanno bene |
| **Avvolge un arto** | manica, cosciale, schiniere, guanto | **conformazione**: vertex group di aderenza → shrinkwrap `OUTSIDE`. Oppure guscio derivato dal corpo + dettaglio dal pezzo generato |

Questo spiega tutta l'evidenza raccolta: i pezzi che oggi funzionano sono i
rilievi, quelli che falliscono sono gli avvolgenti.

## Perché NON si può dire a Meshy le misure

È image/text→3D: non onora vincoli metrici. Non esiste modo di chiedergli «lungo
0,30 m, largo 0,11 al gomito e 0,055 al polso». Con una tavola a tre viste si
ottiene **stile**, non misure. Meshy resta la fonte dell'aspetto, non del fit.

## Non siamo i primi

- [Surface Deform, manuale Blender](https://docs.blender.org/manual/en/dev/modeling/modifiers/deform/surface_deform.html)
- [Fitting clothing over different body mesh — cgcookie](https://cgcookie.com/community/9783-fitting-clothing-outfit-mesh-over-different-body-mesh)
- [Riusare un'armatura su corpi diversi — polycount](https://polycount.com/discussion/219187/modular-character-is-there-any-solution-to-reuse-armor-over-a-range-of-body-size)
- [Body Conform Controls, MetaHuman](https://dev.epicgames.com/documentation/metahuman/body-conform-controls) — Epic lo vende come funzione
- [ShapeKeyWrap](https://squeezypixels.gumroad.com/l/shapekeywrap) — l'addon che automatizza il giro in ~100 righe

⚠️ RBF e Surface Deform risolvono un problema **diverso**: rifittare un capo
*già fittato* su un corpo *diverso*. Vogliono una corrispondenza di partenza, e
un pezzo generato non è mai stato fittato a niente. Servono quando arriverà il
corpo femminile, non adesso.

## Da fare

- [ ] Portare la ricetta dentro `vesti_protagonista.py` come modo dichiarabile
      per pezzo (`"modo": "rilievo"` o `"modo": "avvolgente"`).
- [ ] Tarare `stacco` e `fascia` per tipo di pezzo: una manica aderente vuole una
      fascia stretta, una spalliera che sta in rilievo la vuole larga.
- [ ] Rifare i pezzi esistenti dichiarandoli sull'arto INTERO invece che su un
      segmento — è la dichiarazione che porta la copertura.
- [ ] Decidere se i pezzi avvolgenti prendono la geometria dal guscio derivato e
      il dettaglio dal pezzo generato (bake normal/height), invece della mesh
      generata conformata.
- [ ] **Le chiazze di pelle sui polpacci e sull'interno coscia.** Restano
      identiche prima e dopo la correzione del `wrap_mode`: non sono
      sfrangiamento, sono COPERTURA — lì la piastra sta dentro la gamba più a
      fondo di `affondo`, quindi giustamente non viene tirata fuori. Si cura con
      `cinghia`/`gonfia`, o rifacendo il pezzo, non con la conformazione.
- [ ] **Il guanto.** `arcanium/tools/prove/guanto_lamelle.py`: una lamella per
      falange, costruita sulle ossa. Vedi §«UNA MANO NON È UN ARTO».
