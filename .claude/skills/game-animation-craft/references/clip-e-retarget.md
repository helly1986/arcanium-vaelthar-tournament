# Clip, retarget e root motion

Indice:
1. Retarget o re-skin? La decisione che costa di più
2. Import corretto della sorgente (due errori che perseguitano)
3. Autorare a pose sparse
4. Root motion: dove va e cosa te la mangia
5. Trasferire clip fra rig identici
6. Diagnosi delle clip rotte

---

## 1. Retarget o re-skin? La decisione che costa di più

Storia vera, riassunta perché non si ripeta: mesi di lotta col retarget di un
pacchetto di animazioni professionale su uno scheletro auto-generato. Polsi e
caviglie "avvitati" di ~45°, esplosioni della mesh, ginocchia incrociate. Ogni
rimedio ne apriva un altro.

**La diagnosi vera:** il *roll* (l'orientamento attorno all'asse) delle ossa
dello scheletro auto-generato non coincideva con quello per cui il pacchetto era
animato. Nessuna taratura di retarget vince un mismatch strutturale.

**La soluzione che ha chiuso la questione:** ri-skinnare la mesh **direttamente
sullo scheletro del pacchetto**. Le clip diventano native, qualità identica
all'autorato, zero retarget, zero mappe ossee, zero correzioni per-osso. Bonus:
spesso quegli scheletri hanno le dita.

**Regola d'ora in poi:** se userai una libreria di clip di terzi come base del
moveset, **adotta il loro scheletro** e riggaci sopra la mesh — non generare un
rig automatico e poi tentare di far combaciare i due. Chiedi mesh senza rig, e
rigga tu.

Il retarget resta legittimo quando: il rig di destinazione è vincolato da altro
(un motore che applica rimappature ossee e correzioni di rest su cui poggia
tutta la logica di animazione già scritta), oppure devi portare una clip sola.

## 2. Import corretto della sorgente

Due errori di import hanno causato la maggior parte dei twist, e vanno decisi in
base a cosa farai:

**Se retargetti**, importa gli FBX con l'orientamento automatico delle ossa
attivo: senza, le ossa mantengono gli assi-nodo grezzi da motore di gioco (non
allineati all'osso), lo scheletro non è "umanoide" e il retarget esce twistato.

**Se invece adotti lo scheletro nativo** (niente retarget), fai l'opposto:
importa **senza** orientamento automatico. Motivo: quell'opzione calcola i roll
sulla rest del singolo file, e ogni file del pacchetto ha una reference pose
diversa — mescolando bind e clip prese da file diversi ottieni convenzioni
d'osso incoerenti, cioè twist. Senza l'opzione, gli assi-nodo grezzi sono una
convenzione fissa identica per tutti i file.

**La rotazione a livello oggetto va azzerata prima del retarget.** L'import da
convenzioni Y-up mette una rotazione di 90° sull'oggetto armatura; se il target
è a rotazione 0, il mismatch fa impazzire ogni calcolo (sintomo: ginocchia
incrociate). Applica **solo la rotazione**, non la scala: le fcurve di
*location* sono espresse nella convenzione della scala corrente e applicarla le
moltiplicherebbe di 100.

**Ossa foglia con rest spazzatura.** Un osso senza figli (la punta di un piede,
l'ultima falange) riceve dall'auto-orientamento una rest arbitraria, e siccome
il retarget calcola una delta rispetto alla rest *di quell'osso*, il risultato è
sballato solo lì. Prima di correggere a mano: controlla se il **genitore
immediato** ha una rest pulita e rimappa su quello. Si perde l'ultimo grado di
libertà della catena — di solito trascurabile, e spesso è anche più corretto
anatomicamente.

## 3. Autorare a pose sparse

Per clip nuove (o bozze da far correggere a un umano) la tecnica migliore non è
il bake fitto ma la **posa sparsa**: 9-11 chiavi a corpo intero nei momenti che
contano, interpolazione in mezzo.

Vantaggi concreti:
- La clip resta leggibile e modificabile, invece di essere un muro di frame.
- Le richieste di regia si eseguono spostando **una battuta di pose**, non
  rifacendo tutto.
- Se la clip deve restare **sincronizzata** con un'altra (un finisher e la sua
  vittima), puoi cambiare il ritmo interno **senza toccare la durata**: sposta
  la battuta, lascia il rilascio dov'è.

Esempio di ritmo per un'azione d'impatto: neutro → anticipazione (carica
all'indietro) → contatto → sovraestensione → assestamento → ritorno.
L'anticipazione è ciò che rende leggibile il colpo; se sembra "piatto", di
solito è perché lo scarico è monotono — concentra la velocità in pochi frame
invece di distribuirla.

**La carica può essere enorme, lo scatto no.** Una rotazione sull'osso RADICE
ruota tutto il corpo attorno al bacino, quindi si somma a tutto ciò che sta a
valle: se al momento dell'impatto dai 14° di beccheggio alla radice, 20° al
petto e 40° al collo, il personaggio si pianta il muso sotto il pavimento con
le zampe divaricate — una faccia a terra invece di un morso. Nella posa di
CARICA puoi esagerare quanto vuoi (è lì che serve leggibilità); nello SCATTO
tieni la radice piccola e lascia che l'affondo lo diano petto e collo, e tieni
gli arti vicini al neutro, perché devono reggere il peso.

**Quanto deve essere grande un anticipo?** Misuralo in rapporto a una lunghezza
del personaggio, non in assoluto. Un morso il cui anticipo muoveva la testa di
2,8 cm su un animale con la testa 31 cm sopra l'anca (il 9%) era invisibile alla
distanza di gioco; portandolo a 7,7 cm (il 25%) è diventato leggibile. Se la
telecamera è lontana o isometrica, **il segnale deve essere una posa diversa**,
non una sfumatura della stessa posa.

**In una combo, ogni colpo ha bisogno della sua carica.** Due impatti separati
da un rimbalzo si leggono come un colpo solo lungo, e il secondo diventa
imparabile. La ricarica intermedia deve essere profonda almeno quanto la prima e
durare abbastanza da vedersi (mezzo secondo, non un quarto).

## 4. Root motion: dove va e cosa te la mangia

**Il motore rimuove la traccia di root motion dalla posa su tutti e tre gli
assi** e te la consegna via API. Se il tuo controller usa solo X e Z e scarta la
Y, hai appena cancellato ogni movimento verticale del corpo: il bob del passo,
l'abbassamento sugli affondi, il salto. Il sintomo non è un offset, è
**l'assenza di peso** — il personaggio sembra scivolare, "hoverare", non essere
piantato a terra. E siccome il danno avviene solo a runtime, in Blender i numeri
sono puliti e non trovi niente.

**Architettura giusta:** un osso `Root` separato dal bacino, che porta la sola
componente **orizzontale**, mentre la verticale resta nel bacino e vive nella
posa. Così la traccia di root motion sta su un osso che non partecipa alla
deformazione, e il bacino non viene mai né estratto né congelato.

**Effetto collaterale prezioso:** con la traccia su un osso non deformante,
spariscono un'intera famiglia di workaround (congelamenti del bacino, spostare
la traccia durante le clip speciali, cadute che avvengono a mezz'aria).

⚠️ **La traccia di root motion CONGELA l'osso al valore in cui si trova quando
viene riattivata.** Se una clip lascia il bacino ruotato di 180° e tu riattivi
la traccia lì, il personaggio resta girato **per sempre**, e nessuna clip
successiva riesce a correggerlo. Sintomo inequivocabile: la mesh guarda a 180°
dal nodo, in modo persistente su tutte le clip, mentre la logica di gioco
continua a funzionare correttamente (i colpi vanno a segno mentre il
personaggio guarda altrove).

**Clamp anti-spike:** se applichi la root motion frame per frame con un limite
massimo di passo, ricordati che clip più atletiche possono superarlo
legittimamente e finire azzerate proprio nel momento clou. Tara il limite sul
massimo misurato, non a occhio.

## 5. Trasferire clip fra rig identici

Se sorgente e destinazione sono **lo stesso scheletro** (stesso file d'origine,
stessa gerarchia), non serve retarget: copia le trasformate osso per osso in
spazio mondo. È una copia esatta, verificabile (la differenza deve essere zero).

Attenzione alla scala: se l'oggetto sorgente ha una scala non unitaria che
compensa le unità, **applicarla non riscala le fcurve di location già esistenti**.
Il valore grezzo viene poi letto senza compensazione e produce traslazioni ~100
volte troppo grandi. Se devi applicare la scala, **cachea prima** i valori mondo
che ti servono, e usa la cache dopo.

Bake solo-rotazione ovunque tranne dove serve davvero la traslazione (la
radice). Le ossa ruotano attorno ai giunti, non traslano: tracce di posizione su
ogni osso sono un invito all'esplosione.

**Se i due rig NON sono identici** (unità diverse, roll diversi), la formula che
regge è quella espressa in **vero spazio mondo**, includendo le matrici oggetto
di entrambi — non `rest_dest @ rest_src⁻¹ @ pose_src`, che ignora le unità e fa
esplodere la mesh a migliaia di unità di distanza. Concettualmente: porta la posa
sorgente in mondo, togli la rest sorgente in mondo, riapplica sulla rest
destinazione in mondo, e solo alla fine riporta in spazio locale del target.
Processa **genitori prima delle foglie** e aggiorna dopo ogni osso.

## 5b. Portare un ATTACCO D'ARMA da un motore all'altro

Il transform del mount è espresso nello spazio dell'osso, e **lo spazio
dell'osso non è lo stesso in due motori** anche quando il rig "è lo stesso":
pipeline di import diverse producono convenzioni d'asse diverse. Convertire la
matrice a mano dà una posa plausibile e sbagliata — e le due conversioni
possibili (±90° sull'asse su cui differiscono) sono entrambe errate se il
disallineamento non è solo quello.

**La soluzione che funziona: non convertire, misurare.** Si costruisce una
terna ortonormale da TRE PUNTI DI OSSO, si esprimono lì sopra i punti
caratteristici dell'arma (punta, calcio, un punto laterale per il rollio) e si
ricostruisce dall'altra parte dagli stessi tre punti. I punti sono geometria:
non hanno convenzioni.

⚠️ **La terna deve essere RIGIDA con l'osso che porta l'arma.** Spalla-gomito-
mano sembra comoda e non lo è: quando il gomito si piega, quella terna ruota
rispetto al pugno, quindi il montaggio vale solo se misurato nella stessa,
identica posa nei due motori — e non lo è quasi mai (in un motore lo scheletro
sta già suonando l'idle, nell'altro è a riposo). Usa punti che non si muovono
fra loro: la mano e due dita, o tre ossa della stessa falange.

**La prova che il montaggio è giusto** è l'invarianza: la direzione dell'arma
espressa in quella terna deve restare identica in **più pose diverse**. Se lo
scarto è 0.00° a riposo e cresce sui frame animati, la terna non è rigida e il
risultato è casuale. Verificarlo costa una stampa e smaschera l'errore prima
dell'export.

Corollario di regia, non di tecnica: **una presa tarata sull'idle può non
reggere a metà attacco.** L'idle è la posa in cui è comodo tararla e la meno
significativa per giudicarla.

## 6. Diagnosi delle clip rotte

**"Il personaggio si rimpicciolisce nei blend".** Controlla se le clip bakeano
tracce di **scala**: se una sola clip ha una scala diversa dalle altre, ogni
crossfade da e verso quella ri-scala il corpo. Rimedio: tieni solo le tracce di
rotazione, così lunghezze ossee e scala restano quelle del bind, identiche per
tutte le clip.

**"Cammina incrociando le gambe".** Verifica sulla **mesh renderizzata**, non
sulle ossa. Se la caviglia incrocia mentre anca e ginocchio restano dal lato
giusto, e il grado di incrocio è proporzionale alla flessione, è una torsione
del femore nel rig: un de-twist costante attorno all'asse longitudinale, cotto
nella sorgente prima del transfer, risolve tutte le clip locomotorie insieme.

**"Fluttua o sprofonda in modo diverso per clip".** Se qualcuno ha rimosso la
traccia verticale della radice per impedire al personaggio di volare via, ha
tolto anche il movimento verticale legittimo. Rimedio: riporta a terra il punto
più basso **per clip**, con i minimi pre-campionati una volta sola — non
ricalibrando ogni frame, che fa affondare progressivamente le clip che alzano i
piedi, e non latchando il primo campione dopo un cambio clip, che non è mai il
minimo vero e produce un tuffo a ogni transizione.

**"Una fase dell'attacco manca".** I pacchetti spesso hanno sia le fasi separate
(carica / tenuta / rilascio) sia il file base già composito. Controlla il range
di frame prima di concatenare a mano tre file.
