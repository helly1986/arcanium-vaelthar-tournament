# Rig e skinning — montare una mesh su uno scheletro

Indice:
1. Montare una mesh su un rig CONDIVISO (la ricetta)
2. Cosa del rest si può toccare e cosa no
3. Skinning: quando l'auto-weight fallisce e cosa fare
4. Pesi sporchi: bleeding, webbing, seam
5. Diagnosi: l'osso è dentro o fuori?

---

## 1. Montare una mesh su un rig condiviso

Il caso: hai una libreria di clip già bakeate su uno scheletro master, e un
personaggio nuovo che deve usarle. Non vuoi ri-bakeare nulla.

Il rig master **non è in A-pose**: è nella posa da cui sono state espresse le
clip (tipicamente una stance di combattimento — busto in avanti, avambracci in
fuori). Una mesh generata da un servizio automatico arriva quasi sempre in
A-pose o T-pose. Montarla con la sola scala uniforme la lascia in A-pose e il
rig le esce dalle maniche: le mani finiscono fuori dal corpo, e da lì in poi
ogni cosa attaccata alla mano (armi, effetti) è disallineata.

Ricetta che funziona:
1. **Puppet**: ri-importa il file originale della mesh — quello col suo rig
   nativo, che ha pesi buoni e giunti esatti da usare come landmark. Scalalo.
2. Ruota i segmenti (braccio, avambraccio) sulle direzioni testa→testa del rest
   del rig master, poi **applica il modificatore**: ora la mesh è nella stanza
   di rest giusta, con le proprie proporzioni.
3. **Rig**: duplica il master e trasla le ossa della catena sui giunti della
   mesh. I discendenti (dita, socket per prop) ereditano il delta del proprio
   antenato.
4. Rilega.
5. Esporta con i **nomi attesi dalla scena di destinazione** e con almeno una
   clip incorporata, altrimenti alcuni motori non creano nemmeno il player di
   animazione.

⚠️ Al punto 3: un'armatura duplicata **eredita la posa** del master. Azzerare
l'action non basta — serve un clear esplicito delle trasformazioni di posa. Se
rileghi con lo scheletro posato, i pesi vengono calcolati su ossa nel posto
sbagliato e la mesh si strappa appena parte una clip, mentre **a riposo sembra
perfetta**.

## 2. Cosa del rest si può toccare e cosa no

Due regole decidono tutto, e derivano da come sono fatte le clip:

**La posa di rest non si vede mai in gioco** (gira sempre una clip). Quindi
ruotare gli arti della mesh nella stanza di rest è gratis: nessun costo di art
direction. Le **proporzioni** invece si vedono in ogni frame: non allungare gli
arti per farli combaciare col rig.

**Se le clip hanno tracce di posizione solo sulla radice** (verificalo: conta
le tracce di rotazione e quelle di posizione), allora cambiare la **posizione**
di rest di un osso è invisibile alle animazioni, mentre cambiarne la
**rotazione** le sposta tutte. Corollario prezioso: puoi riproporzionare le
ossa — accorciare braccia o gambe sul personaggio vero — traslando testa e coda
insieme, senza toccare roll né lunghezza.

## 3. Skinning: quando l'auto-weight fallisce

**Mesh frammentata.** Molte mesh generate automaticamente non sono saldate:
vertici coincidenti ma non uniti sulle cuciture, centinaia di componenti
separate. Lo skinning lineare esistente continua a funzionare (non richiede
connettività), ma qualsiasi auto-weight tipo "bone heat" fallisce o produce
spazzatura. Fix: merge per distanza con soglia piccola (0.0001) — salda tutto
in una componente sola senza distorcere. Attenzione: il merge può danneggiare le
UV sulle cuciture.

**Auto-weight che fallisce comunque.** Ripiego affidabile: skinning per
prossimità — per ogni vertice, i due ossi più vicini per distanza
punto-segmento, peso proporzionale a 1/d². Non è elegante, funziona sempre, e
per parti che devono restare separate (mantelli, dita) è preferibile
all'auto-weight, che invece le fonde.

**Parti che non devono seguire il corpo.** Un mantello simulato non si esporta
nei formati real-time. La soluzione da gioco è una catena di ossa dedicate: col
re-skin per prossimità i vertici del mantello si legano a quelle e non alle
braccia.

## 4. Pesi sporchi: bleeding, webbing, seam

Su parti vicine e connesse (dita, cosce interne) l'auto-weight **sconfina**:
curvi un dito e si muovono i vicini. Il rimedio è un pesaggio geometrico
isolato, non automatico:

- Assegna ogni vertice **solo** alla catena più vicina → zero bleeding per
  costruzione. Dentro la catena, blend fra le falangi per curve morbide.
- Aggiungi un **osso statico** che non ruota mai e dagli il peso complementare
  (1 − peso_dito). Serve perché il modificatore normalizza i pesi: senza, un
  vertice a peso parziale seguirebbe comunque al 100% e si vedrebbe una
  giuntura staccata.
- **La membrana fra due dita** non deve seguire nessuno dei due, o si stira. Ma
  sospendi il peso **solo vicino alla base** (la vera forca): se lo sospendi
  anche in zone distali — dove due dita sono semplicemente vicine — la mesh si
  stira in modo grottesco, perché lì la geometria si aspetta di muoversi.
- **Test di isolamento:** curva UN solo dito e guarda se i vicini restano
  fermi.

Per il bleeding fra gamba e gamba, o gamba e busto, una maschera geometrica
(oltre una soglia laterale, o sopra una certa quota) rimuove il peso sconfinato
in modo prevedibile.

## 4ter. Quando il rig di destinazione è più povero della sorgente

Si rigga con un sistema ricco (un auto-rig con ossa del palmo, twist, stretch) e
si travasa su uno scheletro condiviso più povero, perché le clip vivono lì.
Ogni osso sorgente che il destinatario non ha va **distribuito**, e la scelta di
dove mandarlo si vede in animazione, non nei numeri.

**Le ossa del palmo (metacarpi).** Mandarle alla prima falange fa ruotare il
palmo con le dita: appena la clip chiude la mano, il DORSO SI GONFIA e pollice e
indice sembrano staccarsi. Mandarle tutte alla mano è l'errore opposto: le dita
che ruotano attorno a un perno lontano (vedi sotto) stirano la loro base come un
filo. La cura è dividerle **lungo l'osso**: alla mano verso il polso, sfumando al
dito verso la nocca (a partire da circa il 40% della lunghezza).

**Più dita in una catena sola ("mano a muffola").** Se tre dita condividono una
catena, il suo giunto va al **centro delle loro nocche**, non sulla nocca di una
di loro: il dito più lontano dall'asse, ruotando attorno a un perno spostato,
sporge dal bordo della mano. E i metacarpi delle dita più lontane da quel
centro (anulare, mignolo) passano alla catena solo a ridosso della nocca.

**La mano si piega sulle SUE nocche, non sulla disposizione del donatore.**
Portare la mesh nel rest del rig condiviso (bake di posa) con la rotazione più
corta per ogni falange sceglie a caso la torsione attorno al dito e forza la
divaricazione del donatore. Sul campo: indice aperto di 16° in più, muffola
girata di 14°, pollice piegato dentro, già nell'idle, perché per le dita
l'idle è il rest. La cura:
- le falangi si piegano solo attorno alla riga delle nocche della mesh;
- il pollice resta com'è modellato;
- le TESTE delle ossa della mano si spostano sulle articolazioni della mesh
  cotta. Le clip leggono solo le rotazioni, quindi le teste delle dita sono
  libere. Senza questo passo ogni falange non combacia con la successiva e le
  dita vengono a salsicciotto.

Si guarda la mano cotta nel rest, da sopra il dorso, PRIMA di qualunque clip.

**Il viso sotto il giunto della testa.** Se il giunto della testa sta alla
base del cranio, mento e mandibola sono *sotto e davanti* a lui, e il pesaggio
automatico li dà al collo: girando la testa il viso si strappa dalla guancia al
mento. Si passano alla testa i vertici sopra la **linea della mandibola** (nel
profilo: dal sotto del mento a sotto l'orecchio), sfumando in pochi centimetri;
la gola resta al collo.

## 4quater. Orfani travestiti: il vertice col peso quasi nullo

"Nessun vertice senza peso" è un collaudo che **mente**. Un vertice con un
gruppo a peso 0,00007 non è senza peso, ma si comporta come se lo fosse:

- se c'è un **bake da una posa all'altra** (A-pose → posa del rig di
  destinazione), resta dov'era mentre i vicini si spostano, e i suoi spigoli
  diventano una SPINA — visibile già a riposo;
- all'**export glTF** l'esportatore lo scarta e lo appende a un osso fantasma
  (`neutral_bone`): lo skin ha un osso in più, e in gioco quel vertice resta
  fermo mentre il personaggio si muove.

Orfano è chi ha la **somma** dei pesi sotto una soglia (0,01), non chi non ha
gruppi. Si chiudono PRIMA del bake, copiando i pesi del vicino pesato più
prossimo, e alla fine si normalizza tutto a somma 1.

## 4quinquies. Il collaudo del cambio di posa: gli spigoli non si allungano

Portare una mesh da una posa all'altra PIEGA il corpo, non lo stira: gli
spigoli restano quasi della loro lunghezza. Confronta ogni spigolo prima e dopo
(stessa topologia): uno che si allunga di **più di tre volte** è un vertice
rimasto indietro o pesato sull'osso sbagliato — un pezzo di cintura pesato sulla
coscia accanto a uno sulla schiena, una spina sul mento. È il collaudo che
trova in un secondo quello che il render trova solo se guardi il punto giusto.

E si **ripara** senza toccare niente a mano: si prendono i vertici stirati più
un anello di vicini, si rimette la geometria nella posa di partenza, si media
ogni peso con quelli dei vicini **lungo la mesh** e si rifà il bake, finché il
conto va a zero (sul campo: 22 → 8 → 4 → 0 in tre giri). ⚠️ I vicini lungo la
mesh, non nello spazio: una media spaziale salta da uno strato di stoffa
all'altro.

## 4sexies. Vestiti a strati e armature: due corpi diversi

**Pesi affilati (a potenza, per rendere i vertici rigidi) servono all'acciaio,
non alla stoffa.** Una piastra non si piega; una tunica sì. Sulla stoffa
l'affilatura rende rigidi due vertici su tre e collo e cintura si strappano
dove due vertici vicini seguono ossa diverse.

**Tagli di peso pensati per un'armatura** (gonnellini che pendono dal bacino,
tagliati a metà vita) su una veste lunga tagliano a metà cintura e tunica.

**Gli strati sovrapposti** (manica esterna, camicia, tunica, mantello) pesati
ognuno per conto suo ricevono pesi diversi, e quello sotto buca quello sopra.
Cura: un **involucro** chiuso del corpo (voxel remesh a ~1 cm), i pesi copiati
sull'involucro e ammorbiditi lungo la sua superficie, poi riportati su ogni
vertice dal punto più vicino. Testa e mani fuori (fonderebbe le dita).
⚠️ Si fa **dopo** il bake di posa: nella posa di partenza (braccia aperte) la
manica larga pende vicino all'avambraccio, l'involucro li fonde, e abbassando le
braccia la manica si squarcia. E voxel grossi o troppi passaggi fondono la
manica col fianco.

**Limite che nessun peso supera:** una clip che torce il busto di ~90° strappa
comunque la cintura e i lembi di una veste larga a strati. Lì servono clip
pensate per quel corpo, o una simulazione di stoffa (§4septies).

## 4septies. La stoffa simulata: il tessuto non si pesa, si simula

Un tessuto legato alle ossa si muove come la pelle: niente ritardo, niente
oscillazione, niente peso. Una simulazione di stoffa sopra lo skinning (PBD su
GPU, con una maschera per vertice: 0 segue le ossa, 1 è libero) dà il
movimento che nessun peso può dare. Le regole, pagate su un corpo generato:

- **Un guscio per ogni stoffa.** La simulazione vuole un foglio solo. Due
  strati sovrapposti a 1-2 cm, lasciati liberi, si incrociano: il risultato è
  PEGGIO dello skinning. Un mantello a guscio unico invece è subito bello. I
  generatori (Tripo, Meshy) saldano gli strati in un solo guscio: si tagliano
  in pezzi separati, ognuno col suo solver, e i pezzi che si toccano collidono
  fra loro (peer).
- **Si taglia per geometria, non per colore della texture.** Il generatore
  dipinge un colore anche sul guscio dell'altro: la divisione per colore lascia
  due strati pieni di buchi. Prima di fidarsi di una classificazione, si
  RENDERIZZA ogni pezzo da solo.
- **Le collisioni fra stoffe e con se stessa passano da un reticolo
  semplificato**, relativo all'ingombro del pezzo. Su un pezzo grande una
  cella misura centimetri, e gli strati vicini si attraversano comunque. Pezzi
  più piccoli hanno celle più fini.
- **Il costo è nei dispatch, non nelle particelle.** I vincoli si risolvono per
  gruppi colorati: ogni gruppo è un dispatch, per ogni passo e ogni iterazione.
  Si mette nel solver SOLO la stoffa, si parte da 1 passo x 4 iterazioni, e si
  misura con N personaggi insieme e il vsync spento, non con uno.
- **Maschera prima, fisica dopo.** La maschera si guarda renderizzata (nero
  legato, rosso libero) prima di accendere la simulazione. Stivali e calzoni
  dentro la veste si escludono per distanza dall'asse dell'osso, non per
  altezza.

## 4bis. Trovare i giunti su una mesh senza rig

Quando la mesh arriva nuda (nessuno scheletro da cui copiare i giunti) i
landmark si ricavano dalla geometria. Due regole, entrambe pagate.

**Isola gli arti per GRUPPI CONTIGUI, non per soglia.** A mezzo busto una fetta
orizzontale dà tre corse separate lungo l'asse laterale — *braccio | busto |
braccio* — e i confini sono geometria. Una soglia "metà larghezza del busto" va
invece misurata a una quota dove le braccia sono già presenti, quindi torna
quasi doppia e spalla, gomito e polso escono tutti schiacciati in pochi
centimetri. Lo stesso trucco dà l'inforcatura: è la quota dove i **due gruppi
gamba diventano uno**, non dove sparisce il vuoto centrale — su un personaggio
corazzato le falde scendono fra le cosce e chiudono quel vuoto molto più in
basso, restituendo un'inforcatura al 34% dell'altezza, anatomicamente
impossibile.

**Il gomito e il ginocchio NON esistono su un arto dritto.** In A-pose il
braccio è un cilindro rettilineo: non c'è nessuna piega da trovare, e ogni
euristica che "cerca il gomito" insegue un segnale che nella geometria non c'è
(ne usciva uno 16 cm più in basso del vero). Misura solo i due **estremi** —
che esistono davvero: la spalla è dove il braccio si fonde col busto, la mano è
l'estremità — e **suddividi con le proporzioni del rig di destinazione**, che è
il corpo a cui le clip si riferiscono comunque.

**Controllo gratuito che vale molto:** somma i landmark destro e sinistro. Su un
corpo simmetrico devono annullarsi. Uno scarto di pochi millimetri dice che la
misura è coerente; uno scarto grosso smaschera un'euristica che sta agganciando
cose diverse sui due lati, e lo dice *prima* che tu ci costruisca sopra un rig.

## 5. Diagnosi: l'osso è dentro o fuori dalla mesh?

**Metrica buona:** per ogni osso, confronta la sua posizione di rest col
**baricentro dei vertici che quell'osso domina** (peso maggiore). Lo scarto ha
segno e direzione, quindi ti dice anche *come* correggere.

⚠️ **Il segno della normale mente su un corpo corazzato.** Il test
«punto-più-vicino più segno della normale» presuppone un guscio unico: su
un'armatura a **doppia parete** il punto più vicino a un osso profondo cade sulla
parete *interna* della piastra, la cui normale guarda verso il corpo, e il segno
si inverte. Misurato: 45 ossa dichiarate «fuori» su un personaggio nuovo — e
**47 su quello che gira in gioco da mesi**. Il conteggio grezzo non significa
niente senza un metro di paragone.

Due vie d'uscita, e la seconda è meglio: la **parità dei raggi** (dentro = numero
dispari di intersezioni, votata su più direzioni), che non guarda le normali ma
vuole una superficie **chiusa**; oppure la metrica qui sotto, che funziona anche
su mesh aperte perché non usa la geometria ma i pesi.

**Metrica ingannevole:** la distanza dal vertice più vicino. È grande sia
quando l'osso è fuori dal corpo sia quando è ben dentro: non distingue i due
casi opposti.

**Sempre con un riferimento.** Misura nella stessa esecuzione un personaggio
che funziona. Senza metro di paragone non sai se uno scarto di 3 cm è normale o
è il bug.

**Verifica a vista:** sfere colorate imparentate alle ossa e render. Se la sfera
si vede, l'osso è fuori dalla mesh. Attenzione all'ancoraggio: certi sistemi
imparentano alla CODA dell'osso, quindi serve un offset per tornare alla testa.
