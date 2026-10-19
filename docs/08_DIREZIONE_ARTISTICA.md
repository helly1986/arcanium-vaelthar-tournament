# 08 — DIREZIONE ARTISTICA: il riferimento è Baldur's Gate 3

> Stabilito il 2026-08-12. Vale per **tutto il gioco**, non solo per Kalvorn.
> Riferimento: BG3 (Emerald Grove, Druid Grove), in ottica **Indie/AA**.

Arcanium è isometrico esattamente come BG3, quindi il paragone regge dove di
solito non reggerebbe: stessa distanza di camera, stessi problemi di lettura,
stesse soluzioni. Il riferimento non è "fotorealismo": è **densità e strati**.

---

## 1. Le cinque cose che fanno l'effetto BG3

In ordine di resa per noi, non di importanza teorica.

### ① Il suolo non è MAI nudo
In BG3 nessun metro quadro calpestabile è una texture sola. Sopra l'erba ci
sono ciuffi alti, poi felci, poi fiori, poi sassolini, poi foglie secche, poi
muschio che sale sui massi. **Sette strati dove noi ne abbiamo due.**

⚠️ La conseguenza pratica non è «servono prop più belli»: servono **più strati di
prop piccoli**. Un masso in più non si nota, trenta ciuffi in più sì.

### ② I massi sono l'ossatura
Entrambe le immagini di riferimento sono *costruite sui massi*: definiscono i
sentieri, terrazzano il terreno, danno le silhouette. Sono di dieci dimensioni
diverse, spesso mezzi sepolti, quasi sempre in gruppo.

Kalvorn oggi ha **due varianti di masso**. È l'aggiunta col miglior rapporto
resa/costo che abbiamo davanti.

### ③ I punti di contatto sono sfumati
Dove il masso incontra il terreno, BG3 ci mette muschio e piantine. Nessuna
giuntura netta, mai. I nostri oggetti si vedono **appoggiati**, e l'occhio lo
legge come "modello posato su un piano" invece che "sasso che sta lì da secoli".

Costa poco: un ciuffo alla base di ogni masso e di ogni tronco.

### ④ I colori d'accento
Il verde di BG3 legge come *rigoglioso* e non come *cupo* perché accanto c'è
altro: pietra calda, sentiero sabbioso, fiori viola e rosa, legno chiaro.

Kalvorn oggi è **monocromo verde**. `kalvorn_fiore_accento` esiste e non viene
quasi usato. Gli accenti vanno messi **dove il giocatore guarda** — lungo i
sentieri, ai piedi dei landmark, nei punti di sosta — non sparsi a caso.

### ⑤ La luce — ⚠️ NON si copia la luminosità: si copiano le Shadow-Cursed Lands

**Kalvorn deve restare cupa: è nella lore, e schiarirla la tradirebbe.**

Il riferimento giusto per noi non è la Radura Smeraldo: sono le **Shadow-Cursed
Lands**. Sono **più scure dei nostri screenshot attuali** e si leggono
perfettamente. Il difetto di Kalvorn non è che è scura — **è che è uniforme.**

Quattro cose fanno funzionare quelle immagini, e sono tutte copiabili:

**a) Il SUOLO è il piano più chiaro.** In entrambe le immagini il terreno a
mezza distanza è la cosa più luminosa dell'inquadratura, e tutto ciò che è
verticale — tronchi, rami, rovine — è più scuro. È questo che rende le sagome
leggibili e lo spazio percorribile.
⚠️ **Da noi è il contrario**: terreno scuro *e* alberi scuri, e il risultato
impasta. È la singola correzione con più resa che abbiamo davanti, e non costa
niente: è la tinta del terreno contro quella della vegetazione.

**b) La nebbia separa i piani.** Primo piano quasi nero, piano medio grigio-blu,
fondo pallido. La prospettiva aerea fa da sola tutto il lavoro di profondità che
noi stiamo chiedendo alla geometria.

**c) UN accento saturo, usato poco.** Là sono il fogliame cremisi e il bagliore
teal, in un mondo desaturato. Due colori contro il grigio-blu, e sono loro a
dare tutto l'interesse visivo.
Per Kalvorn l'accento ce l'abbiamo già a canone: **il teal degli spiriti**
(`#00c8aa`), che nelle Shadow-Cursed Lands ha esattamente la stessa funzione. Un
secondo accento caldo può stare alle lanterne dell'avamposto.

**d) Prima la SAGOMA, poi la superficie.** I rami contorti si leggono come forme
nere contro la nebbia: nessun dettaglio di corteccia, e non serve. A questa
distanza la silhouette conta più della texture — che per noi è anche una
fortuna, perché è la parte che costa meno.

Il metro non è «quanto è chiaro»: è **a colpo d'occhio distinguo tre piani di
profondità?** Se sì, può essere buio quanto vuole.

---

## 2. ⚠️ LA REGOLA DI SCOPO, che viene prima di tutte le altre

**BG3 è denso perché le sue mappe sono compatte e piazzate a mano.**
Kalvorn è **un chilometro quadrato**.

Densità BG3 ovunque non è un budget indie, e non è nemmeno AA: è la ragione per
cui BG3 è costato quello che è costato. Inseguirla su tutta la mappa non produce
un gioco che sembra BG3 — produce un gioco che non esce.

**La strada praticabile:** concentrare la densità **dove il giocatore cammina e
guarda** — corridoi, bordi delle radure, punti di sosta, primi piani dei
landmark — e lasciare il bosco profondo più semplice. Da lontano e in movimento
la differenza non si legge, e il colpo d'occhio resta quello.

Tradotto in termini di builder: la densità dello scatter deve dipendere dalla
**distanza dalla rete camminabile**, non essere uniforme.

### I tre livelli di densità

| livello | dove | quanto | di cosa è fatta |
|---|---|---|---|
| **① Insediamento** | avamposti, hub, accampamenti — dove ci sono NPC | **massima, per scelta** | **cose di chi ci vive**: casse, ceste, corde, assi, attrezzi, panni stesi, un fuoco |
| **② Percorso** | corridoi, bordi delle radure, punti di sosta | alta | vegetazione a strati, massi, accenti |
| **③ Fondo** | bosco profondo, oltre la fascia che si guarda | bassa | volume e silhouette, niente dettaglio |

⚠️ **La densità di ① NON è vegetazione infittita: è un'altra materia.** Nelle aree
abitate di BG3 il riempimento è fatto di **oggetti d'uso** — roba impilata,
appoggiata, dimenticata. È quella che dice «qui vive qualcuno», e nessuna
quantità di felci in più la sostituisce.

⚠️ E porta con sé **una sorgente di luce calda**: un braciere, un focolare, una
lanterna. Fa due lavori insieme — rende il terreno la cosa più chiara
dell'inquadratura (vedi ⑤a) e dà all'accento freddo qualcosa contro cui
staccare. Nelle immagini di riferimento il fuoco è sempre al centro dello spazio
abitato e il teal sta ai bordi.

**Per Kalvorn questo significa:** l'Avamposto della Radicata va vestito di
attrezzi da spirit-speaker — mazzi d'erbe appesi a seccare, ceste, secchi,
staccionate intrecciate, un fuoco basso — e non di più sottobosco.

---

## 2bis. La Traccia Perduta — conca aperta, non foresta

*Riferimento dato il 2026-08-12: l'accampamento di BG3.*

La Traccia è **l'opposto di Kalvorn per verso**: a Kalvorn si è *dentro* qualcosa
(volta chiusa, si guarda in su); alla Traccia si è *in mezzo* (cielo aperto, si
guarda intorno). Le regole di densità sono le stesse, la materia no.

- **Terreno chiaro e sabbioso al centro**, che è di nuovo il piano più luminoso.
- **Massi muschiosi grossi come ossatura**: incorniciano la conca, la
  terrazzano, danno gli appigli visivi. Sono loro a costruire lo spazio, non gli
  alberi.
- **Alberi radi e alti**, non una volta: servono a bucare il cielo, non a
  chiuderlo.
- Al posto delle tende del riferimento: **i carri e le casse della carovana**,
  rovesciati e sparsi. È la densità di livello ① — cose di chi ci viveva — ma
  raccontata al passato, che è precisamente il soggetto della quest.

## 3. Cosa NON copiare

- **Il fotorealismo dei materiali.** BG3 ha budget di texture e shading che non
  abbiamo. La nostra strada è lo stilizzato leggibile, che regge meglio a
  polycount basso e invecchia meglio.
- **Il set dressing a mano.** Non abbiamo le persone-anno per farlo su 1 km².
  Il nostro equivalente è uno **scatter con regole** (raggruppamenti, sfumatura
  al contatto, accenti lungo i percorsi), che è codice e si ritocca in un minuto.
- **La palette di BG3.** La nostra è in `LORE/LOCATIONS.md` ed è più cupa di
  proposito: il riferimento è la *densità*, non i colori.
