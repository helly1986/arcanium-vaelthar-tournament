---
name: game-animation-craft
description: "Mestiere di animatore/rigger per videogiochi maturato sul campo: come montare una mesh su un rig condiviso, autorare o retargettare clip, portarle nel motore senza che esplodano, e soprattutto come VERIFICARE che abbiano davvero funzionato. Usa questa skill ogni volta che si tocca un rig, uno skinning, una clip di animazione, un export glTF/FBX, un attacco di arma a un osso, la root motion, o quando un personaggio in gioco fa qualcosa di sbagliato (fluttua, sprofonda, si strappa, incrocia le gambe, muore in piedi, tiene l'arma storta, guarda dalla parte sbagliata) — anche se la richiesta è in italiano e non nomina Blender esplicitamente. Vale per Blender + Godot/Unity/Three.js, non solo per un progetto."
---

# Mestiere di animatore per videogiochi

Questa non è una guida a Blender: di quelle ce ne sono tante e coprono i menu.
Questo è il **taccuino delle cicatrici** — ciò che è costato giorni interi
scoprire, su un progetto vero, e che nessun tutorial dice. Il valore sta quasi
tutto in un punto: **quasi ogni bug di animazione è invisibile ai numeri e ovvio
a vista, e quasi ogni verifica "andata bene" è un falso positivo.**

Leggi il riferimento pertinente prima di agire, non dopo aver sbagliato:

| Se stai per… | Leggi |
|---|---|
| montare una mesh su uno scheletro esistente, pesare, rilegare | `references/rig-e-skinning.md` |
| autorare una clip a mano, retargettare, spostare root motion | `references/clip-e-retarget.md` |
| esportare glTF/FBX, importare nel motore, agganciare armi, scegliere il formato (quad/triangoli) | `references/export-e-motore.md` |
| travasare su un rig più povero (palmo, dita a muffola, viso), vestiti a strati | `references/rig-e-skinning.md` §4ter–4sexies |
| vestire un personaggio di TESSUTO (veste, mantello): la stoffa si simula, non si pesa | `references/rig-e-skinning.md` §4septies |
| scriptare Blender (sessioni lunghe, action, spazi, assi) | `references/blender-in-pratica.md` |

---

## 1. La regola madre: verifica sul risultato, non sull'ipotesi

Il numero di volte in cui una misura numerica ha detto "a posto" mentre a
schermo era un disastro è la statistica più importante di questo taccuino. È
successo almeno quattro volte, sempre nello stesso modo.

**Non verificare mai un deform guardando le ossa.** Le posizioni di testa/coda
degli ossi possono essere perfette mentre la PELLE si incrocia, si strappa o si
avvita. Le ossa sono l'input; la mesh deformata è l'output. Si giudica l'output.

- Un check "0 flip su tutti i frame" misurato sulle ossa ha dichiarato risolto
  un bug di gambe incrociate che era ancora lì, identico.
- Un ginocchio a X = −0.14 "corretto" apparteneva a una mesh che incrociava.
- Angoli di gomito e ginocchio perfettamente plausibili appartenevano a una
  mesh renderizzata a zigzag.

**La ricetta di verifica che funziona:** render della mesh deformata, in
workbench, camera ortografica, su **più frame** (inizio / metà / fine e i frame
critici), poi guardare l'immagine. Se il motore è già in piedi, meglio ancora:
guardarla lì, perché è l'unico ambiente che conta davvero.

### Il PROVINO A CONTATTO — usalo sempre, per ogni movimento

Non guardare una clip un frame per volta: **rendila tutta in un'immagine sola**.
Render OpenGL della viewport (`render.opengl(animation=True, view_context=True)`)
con `frame_step` 2-5, poi monta i PNG in una griglia e **scrivici sopra il numero
di frame**. È l'unico modo per giudicare il RITMO, che è ciò che rende buono o
piatto un colpo — e il ritmo non si vede in nessun frame singolo.

Perché ripaga sempre:
- rivela in un colpo d'occhio le fasi e la loro DURATA: una tenuta di due
  secondi quasi immobile si riconosce subito come tale, e nei numeri no;
- il numero di frame stampato rende l'immagine *operativa*: si può dire "il
  contatto è al 63, taglia lì" invece di descrivere a parole;
- due clip affiancate nello stesso foglio si confrontano davvero (variante
  parziale vs piena, prima vs dopo una correzione);
- costa una manciata di secondi e si condivide con chi decide.

Inquadratura: **profilo ortografico**. Un affondo va avanti, e di fronte
l'avanzamento non si vede; un fendente vuole invece il tre quarti. Scegli
l'angolo in cui l'azione ha la massima escursione, non quello "bello".

Se la clip arriva su un'armatura nuda, **importa la mesh del pack e legaci la
clip**: settantanove ossa ottaedriche sono illeggibili, e resta comunque vero
che si giudica la pelle, non lo scheletro.

**Giudica con pose moderate, non estreme.** Una posa di stress spinta al limite
inganna in entrambe le direzioni: fa sembrare rotto uno skinning sano e fa
sembrare sano uno skinning che cederà alle ampiezze vere. Usa le ampiezze che
avrà davvero in gioco.

**Prima di deformare, salva una copia dei vertici** da qualche parte da cui puoi
ripristinare. Le deformazioni sperimentali sono normali; perderle e dover
ricostruire l'asset no.

**Corollario pratico:** quando devi dimostrare che un osso è fuori dalla mesh,
non misurare "distanza dal vertice più vicino" — è ambigua (è grande sia se
l'osso è fuori sia se è ben dentro il corpo). Misura il **baricentro dei
vertici che quell'osso domina** e confrontalo con la posizione dell'osso: quello
scarto ha un segno e un significato. E tieni sempre nella stessa misurazione un
personaggio **che funziona**, come riferimento: senza un metro di paragone non
sai se 0.03 è tanto o poco.

## 2. "Esiste" non vuol dire "funziona"

Prima di autorare qualcosa da zero, controlla se c'è già — e poi controlla se
quello che c'è fa davvero il suo mestiere. Sono due domande diverse.

Un GLB conteneva una clip chiamata `death`. C'era. Ma in 1,6 secondi il corpo
scendeva di 4 cm, mentre l'idle ne scendeva 7: il personaggio moriva in piedi e
spariva. La clip esisteva e non funzionava.

**Sonda rapida per qualunque clip sospetta:** campiona l'osso più alto e più
basso a inizio, metà e fine, e confronta con una clip di riferimento della
stessa famiglia. Una morte deve finire più in basso di dove è iniziata; un
attacco deve avere un'escursione; un idle deve restare fermo. Se i numeri di
due clip diversissime si somigliano, una delle due è inerte.

## 3. Il catalogo dei falsi positivi

Questi ti mentiranno in faccia. Conoscerli è metà del mestiere.

**Il bind sembra perfetto a riposo.** Un bind è *sempre* l'identità nella
propria posa di bind. Se hai rilegato con lo scheletro nella posa sbagliata, a
riposo non vedrai niente e la mesh si strapperà appena parte una clip. Non
giudicare mai uno skinning dalla posa di rest: fai partire una clip.

**"Nessun vertice senza peso" non vuol dire che tutti i vertici si muovono.**
Un vertice con un gruppo a peso 0,00007 passa quel collaudo e resta indietro
come uno senza peso: una spina dopo un bake di posa, un `neutral_bone` nel glTF.
Conta la SOMMA dei pesi. Vedi `references/rig-e-skinning.md` §4quater.

**Il bake di posa "riesce" e ha cotto uno strappo nella geometria.** Portare la
mesh da una posa all'altra non dà errori; un vertice pesato sull'osso sbagliato
si stira e resta stirato, anche a riposo. Confronta la lunghezza degli spigoli
prima e dopo (§4quinquies): nessuno deve allungarsi di tre volte.

**La posa di rest non si vede mai in gioco.** Corollario opposto e altrettanto
utile: siccome gira sempre una clip, *ruotare* gli arti della mesh nella stanza
di rest è gratis. Le PROPORZIONI invece si vedono in ogni frame — non allungare
gli arti per farli combaciare col rig.

**Un'armatura duplicata eredita la POSA del master**, non solo la sua action.
Azzerare `animation_data.action` non la toglie. Se rileghi lì sopra, i pesi
vengono calcolati su ossa nel posto sbagliato.

**Editare la posa con l'action assegnata non funziona:** l'aggiornamento del
view layer ripristina i valori dalle fcurve e le tue modifiche svaniscono in
silenzio. Il risultato "converge" su quello della run precedente, che sembra
conferma ed è il contrario.

**Un canale di posa non è mai a zero perché lo speri.** Residui di bake
precedenti sopravvivono nella sessione anche dopo aver rimosso l'action.
Azzerali esplicitamente prima di ogni bake.

**La taglia di un personaggio si misura sulle LUNGHEZZE DI CATENA, non su
distanze verticali e non sul bounding box.** Storia in due tempi, e il secondo
è la lezione vera. Un corpo nuovo in A-pose misurava 1.90 di bounding box e
quello già montato 1.71: sospettando che la scatola mentisse (il rig di
destinazione ha il rest accovacciato, la mesh nuova ha una cresta sull'elmo) ho
misurato **spalla→caviglia** e ottenuto 1.3239 contro 1.3251 — «lo stesso uomo,
a un millimetro». Conclusione pubblicata, e **sbagliata due volte**:

1. la posizione della spalla era una *stima geometrica*, poi smentita di 10 cm
   da una rilevazione vera;
2. e comunque **una distanza verticale è pose-dipendente quanto il bounding
   box**: su un rest con le ginocchia piegate, spalla→caviglia si accorcia.

Misurate le catene giunto-per-giunto — femore, tibia, omero, avambraccio — il
corpo nuovo era **+12%**, cioè quello che la scatola diceva fin dall'inizio.

Due regole da qui: **misura segmenti fra due giunti**, che non cambiano con la
posa; e **diffida di una misura che smentisce comodamente un sospetto** — il
sollievo di aver "sfatato" un falso positivo è esattamente quando si smette di
controllare. Il corollario: se il fattore di scala che ricavi da segmenti
diversi non è lo stesso numero (qui l'omero dava 94% e l'avambraccio 136%), non
è una questione di scala — sono **proporzioni diverse**, e nessun fattore
uniforme le pareggia.

**Due render con MATERIALI diversi non sono un confronto.** Un pezzo generato è
stato dichiarato «pulito alla sorgente» e quindi scagionato, mentre lo stesso
pezzo a valle era «scheggiato»: i due script rendevano lo stesso oggetto con
materiali diversi — uno faceva `materials.append`, che lascia il materiale
importato allo slot 0 e dà un grigio opaco, l'altro faceva `materials.clear()` e
metteva un metallo scuro lucido. **Su metallo scuro un difetto di normali salta
all'occhio; su grigio opaco è invisibile.** La conclusione sbagliata ha spostato
le indagini a valle per un'intera sessione.

Da qui la regola della bisezione: quando confronti stadi di una pipeline,
**cambia una cosa sola**. Stesso materiale, stessa camera, stessa luce, stessa
risoluzione — e se puoi, generali nella STESSA esecuzione, perché due esecuzioni
diverse non sono mai davvero identiche. Una bisezione vale quanto la sua
inquadratura.

**Un vertice SENZA PESO è invisibile a riposo e diventa un'asta appena parte
una clip.** L'auto-weight ne lascia sempre qualcuno indietro — misurati 84 su
20.588, sparsi fra stinchi, testa e caviglie. A riposo non si vede niente, e
nessun conteggio protesta. Ma un vertice senza peso non si muove, e
l'esportatore glTF lo appende a un `neutral_bone` piantato nell'origine: mentre
il corpo si sposta quello resta dov'è e i triangoli che lo toccano si stirano in
una scheggia sottile lunga tutto il personaggio. Si chiude dando a ogni orfano i
pesi del vicino pesato più prossimo — e **prima di qualunque bake**, perché dopo
quei vertici sono anche nel posto sbagliato, non essendosi mossi durante la
cottura.

**Un provino che scivola fuori inquadratura non è uno skinning rotto: è ROOT
MOTION.** Se la clip porta lo spostamento su un osso di root e chi la riproduce
non dichiara quell'osso come traccia di root motion, la traslazione resta nella
posa e il personaggio se ne va per i fatti suoi. Sembra il difetto più grave che
si possa vedere, e il rimedio è una riga nel *visualizzatore*, non nell'asset.
Prima di accusare il rig, controlla chi consuma la root motion.

**Una clip può girare con metà delle tracce buttate via, in silenzio.** È il
falso positivo più costoso di tutti, perché la clip *si vede muovere*: sembra
solo brutta. Se il motore adatta una clip esterna riscrivendo il **percorso**
della traccia senza tradurre il **nome dell'osso**, ogni traccia il cui osso non
esiste sul rig di destinazione semplicemente non fa nulla — niente errore,
niente avviso.

Misurato su una morte per veleno: la clip veniva da uno scheletro a 24 ossa in
convenzione Mixamo, il rig del gioco ne ha 61 in un'altra convenzione, e
**15 tracce su 24 cadevano nel vuoto**. Sopravvivevano bacino, spina, testa,
mani, piedi e spalle; sparivano *tutte* le gambe e *tutte* le braccia. Effetto a
schermo: un uomo che non riesce ad accasciarsi e non porta mai le mani alla
gola — due difetti di "regia" che nessuna quantità di lavoro sull'animazione
avrebbe risolto, perché la causa era una mappatura di nomi.

**La sonda che lo coglie in dieci righe**, e va fatta *prima* di aprire un
editor di animazione: prendi i nomi degli ossi effettivamente animati dalla
clip (i target dei channel), prendi i nomi delle ossa dello skin del corpo, e
stampa **l'intersezione e la differenza**. Se la differenza non è vuota, quelle
tracce oggi non esistono.

```python
animate = {nodi[c["target"]["node"]]["name"] for c in clip["animations"][0]["channels"]}
ossa    = {nodi[j]["name"] for j in corpo["skins"][0]["joints"]}
print("perse:", sorted(animate - ossa))
```

**I NOMI DELLE OSSA MENTONO SULL'ORDINE DELLA CATENA.** Corollario del
precedente, e trappola dentro la trappola. In quella stessa clip la spina era
`Hips -> Spine02 -> Spine01 -> Spine`: **`Spine02` era l'osso più BASSO** e
`Spine` il più alto, quello che porta spalle e collo. Mappare `Spine` su
`Spine` — l'unica cosa che i nomi suggeriscono — applicava la rotazione
dell'alto torace alla vita.

Non si mappa per nome: si mappa **per posizione nella catena**, e lo si
verifica con una misura. Confronta la direzione di ogni osso a riposo
(`testa del padre -> testa del figlio`) sui due rig: una coppia ben appaiata dà
pochi gradi, una coppia invertita dà **~180**. Nel caso vero: 175,65° mappando
per nome, 4-5° mappando per catena. Quel numero è un allarme antincendio, non
una sfumatura.

**Rinominare non basta: i riposi vanno compensati.** Due rig di provenienza
diversa non hanno gli stessi assi locali. Sempre su quel caso: omero 13,1° di
scarto a riposo, collo 14,3°, spina 4-5°. Il conto giusto passa per lo spazio
del modello — scarto rispetto al PROPRIO riposo, applicato al riposo dell'altro
— ed è lo stesso descritto in `references/clip-e-retarget.md`.

E le **posizioni** non si copiano: le ossa hanno lunghezze diverse e copiare le
traslazioni disarticola lo scheletro. L'eccezione è il bacino, la cui
traslazione è movimento vero, e si scala per il rapporto fra le due altezze di
bacino a riposo. Verifica che il retarget non abbia perso il gesto: l'altezza
del bacino, normalizzata, deve venire **identica** fra sorgente e destinazione
(misurato: differenza 0,0000), mentre testa e mani possono discostarsi — sono
proporzioni diverse, non errori.

⚠️ E se i rapporti fra segmenti diversi non danno lo stesso numero (femore
×1,19, tibia ×0,98), **non è una questione di scala**: sono proporzioni
diverse, e nessun fattore uniforme le pareggia.

**Le ossa di TORSIONE possono avere lunghezza zero, e allora si travestono da
osso vero.** Nei rig con twist bones (`LeftUpperArm_twist_01` e simili) il twist
sta spesso a offset **(0,0,0)** dal genitore: stessa identica posizione. Per un
occhio umano non c'è; per un algoritmo che deduce catene o che cerca "l'osso del
braccio" ce ne sono due indistinguibili nello stesso punto. Ogni strumento di
rigging automatico ha una sezione apposta per dichiararli — usarla, invece di
lasciarli in mezzo alla catena. E quando un tool si lamenta che non trova
un osso che tu vedi benissimo nell'outliner, il twist gemello è il primo
sospetto.

**Un messaggio d'errore che nomina due ossa non vuol dire che ne mancano due.**
Se un tool dichiara un insieme di nodi *obbligatori* e ne verifica la presenza
alla fine, il messaggio elenca gli obbligatori — non i falliti. Prima di
inseguire quei due nomi, chiediti quanti nodi si sono legati **in tutto**: se
insieme compaiono errori su tutt'altro (le torsioni, per dire), la lettura
giusta è "non si è legato niente", e cercare il difetto nelle braccia è tempo
buttato.

**Un osso che sembra STIRATO può essere un controller BLOCCATO.** È il falso
positivo più beffardo incontrato finora, perché il software stesso lo segnala
male. In Cascadeur i segmenti diventano **rossi** quando la distanza fra due
controller si scosta dalla lunghezza dell'osso, e la documentazione lo descrive
come "proporzioni compromesse" — il che porta dritti a cercare un difetto di
deformazione. Ma la stessa cosa succede quando un controller e' **bloccato**:
basta premere `R` con qualcosa selezionato e quei punti restano inchiodati dove
sono, mentre il resto del corpo simula. Il risultato a schermo e' identico a un
osso che si allunga.

Costo del non saperlo: un'ora buona passata a tarare rigidita', smorzamenti e
pesi della fisica, quando la cura era premere `R` di nuovo.

**La misura che chiude la questione in un colpo**, e vale per qualunque motore:
prendi ogni coppia padre-figlio e confronta la loro distanza a ogni frame con
quella a riposo. Un osso davvero stirato lo dice subito; se invece esce
`+0,0%` su tutti i segmenti e tutti i frame — come qui, su diciannove segmenti
— lo scheletro non e' mai stato toccato, e stai guardando un problema di
CONTROLLI, non di geometria.

```python
L0 = distanza(padre, figlio, frame_riposo)
peggio = max(distanza(padre, figlio, f) for f in frames)
print("%+.1f%%" % ((peggio / L0 - 1) * 100))
```

**Corollario, e regola generale:** quando qualcosa "si stira", la prima domanda
non e' *quanto e' morbido* ma **se un'estremita' e' fissata**. Un pin, un blocco,
un vincolo di contatto: sono tutte cose che tengono fermo un punto mentre il
resto si muove, e nessuna si cura di quanto abbassi le rigidita'.

**E attenzione a dove agisce una "rigidita'".** Su un giunto tiene la
ROTAZIONE; su un *point controller* tiene la POSIZIONE. Sono due cose diverse e
si confondono facilmente, perche' il parametro si chiama uguale. Il guaio
tipico non e' nemmeno un valore alto: e' un valore **disomogeneo lungo la
catena** — mano ferma e avambraccio molle tirano l'osso in mezzo da due parti.

**Assegnare un'action a un'armatura può non animare NIENTE.** Dalle versioni di
Blender con gli **slot** (4.4 in poi), `animation_data.action = az` non basta:
serve anche `animation_data.action_slot`. Senza, non c'è nessun errore e la
posa resta quella di riposo — un personaggio impalato per tutta la clip. È il
falso positivo peggiore della famiglia, perché *sembra* uno skinning rotto o un
retarget fallito e non è né l'uno né l'altro. Costato un provino intero: i
numeri, letti reimportando il GLB (dove il caricatore gli slot li collega da
sé), dicevano che il corpo scendeva; il render mostrava un uomo in piedi.

```python
arm.animation_data.action = az
arm.animation_data.action_slot = next(iter(az.slots))   # la riga che manca
```

Il corollario è la regola madre applicata a sé stessa: **la misura e il render
non erano d'accordo, e aveva ragione il render.** Quando le due verifiche
divergono, la colpa sta quasi sempre nel percorso della misura, non in quello
dell'occhio.

**Il pavimento non è decorazione.** In una vista di profilo ortografica un piano
a quota zero è di taglio, quindi invisibile — e senza un riferimento a terra un
corpo che crolla e un corpo che resta orizzontale sospeso a un metro sono la
stessa immagine. Sono difetti opposti. Metti sempre un piano al suolo, e inclina
la camera di un filo (bastano ~10°) perché si legga; l'ombra fa il resto.

**Un export può riuscire producendo un file vuoto.** Nessun errore, file
scritto, zero skin e zero animazioni dentro. Verifica sempre il contenuto del
file esportato, non il fatto che l'export non abbia protestato.

**Uno script che riscrive scene o risorse può riuscire producendo un file
rotto.** Stessa famiglia del precedente e altrettanto silenziosa: una riga
inserita senza l'a capo salda due dichiarazioni e il formato non è più valido,
ma lo script stampa "fatto". Chi riscrive un file di progetto deve dimostrare
di non averlo rotto **prima di salvarlo** — un'asserzione strutturale sul testo
nuovo (nei formati a sezioni: ogni intestazione a inizio riga) costa nulla e
coglie l'intera classe. E dopo, guarda comunque il file: qui il conteggio dei
nodi prima/dopo ha detto in un secondo ciò che "scritto" nascondeva.

## 4. Distingui il sintomo dalla causa prima di teorizzare

Quando qualcosa "si rimpicciolisce", chiediti se sta davvero scalando o se sta
*traslando* verso il basso. Sono cause completamente diverse e il sintomo a
occhio è identico. Misura la scala e la posizione separatamente: se la scala
resta 1, non è un problema di scala, e ogni ora spesa a cercare un errore di
unità è persa.

Stessa disciplina per "fluttua": può essere root motion estratta e scartata,
una traccia di posizione rimossa che portava anche il movimento verticale
legittimo, un pivot fuori posto, o un AABB gonfiato da geometria vagante. Sono
quattro cause con quattro rimedi opposti. **Misura prima di scegliere il
rimedio.**

Quando un'ipotesi cade, scrivilo. Le ipotesi sbagliate scartate valgono quanto
la soluzione: impediscono di ripercorrere lo stesso vicolo cieco fra un mese.

## 5. Non distruggere l'asset buono

La regola più costosa in assoluto, imparata perdendo lavoro già fatto e buono.

**Non ri-esportare mai il file base sopra una variante lavorata.** Una mesh a
pugno chiuso, riggata a mano in un pomeriggio, è stata distrutta da un fix
successivo che ha ri-esportato la mano aperta sopra lo stesso nome. Il difetto
è rimasto invisibile per giorni perché il codice commutava fra due mesh ormai
identiche.

Le conseguenze pratiche:
- Le clip nuove si esportano come file **separati e piccoli** e si caricano a
  runtime come libreria, invece di ri-esportare il modello texturizzato. Un GLB
  di sola armatura pesa decine di KB contro i megabyte del modello completo, e
  soprattutto **non può distruggere le texture**.
- Se un fix va applicato a due varianti, applicalo a ciascuna **partendo da sé
  stessa**, mai copiando l'una sopra l'altra: hanno topologia diversa.
- Prima di sovrascrivere, guarda cosa stai sovrascrivendo.

Attenzione a un caso limite: **un file di sola armatura non ha skin**. Negli
formati tipo glTF lo skin è definito dai pesi dei vertici, quindi senza mesh non
esiste, e il motore può reimportarlo come nodi vuoti invece che come scheletro.
Va benissimo se chi lo carica legge solo le animazioni; se invece l'import
applica rimappature ossee o correzioni di rest, serve almeno una **mesh proxy
minima skinnata** (poche decine di vertici).

## 6. Gli spazi e gli assi sono la prima cosa da misurare

Metà dei disastri nasce dall'aver dato per scontato un asse.

- La `location` di un osso in posa corre lungo **l'asse dell'osso**, non verso
  il basso del mondo. "Scendi di 18 cm" può mandare il personaggio a volare in
  diagonale.
- Lo spazio dell'armatura e lo spazio del mondo possono avere l'alto su assi
  diversi nello stesso file. Inquadrare una camera con le coordinate sbagliate
  dà render vuoti, e un render vuoto sembra un bug del render.
- Su rig importati senza ri-orientamento automatico, la direzione testa→coda di
  un osso **non è** la direzione dell'arto: può essere quasi perpendicolare. Per
  mirare un arto, usa `testa dell'osso → testa del figlio`, non il vettore
  dell'osso.
  ⚠️ E il modo in cui questo fallisce è **silenzioso**. glTF non ha lunghezze
  d'osso: chi importa se le inventa. Misurato su un rig vero, `Shoulder.tail`
  distava **41.8 cm** dalla testa di `Elbow`, e l'osso della tibia era lungo
  4.5 cm. Un algoritmo che deduce le catene «il figlio la cui testa cade sulla
  coda del padre» ne trova **zero**, e prosegue senza errori: ne esce un rig
  identico al donatore e un puppet a rotazione nulla. Se stai deducendo una
  catena dalle code, **stampa quante ne hai trovate** — zero è la risposta che
  non guarderesti mai.
- L'asse "avanti" di un bacino può non essere quello che credi. Misuralo una
  volta e scrivilo, perché ogni calcolo di facing dipenderà da lì.

Per costruire una posa in uno spazio noto, non assegnare la matrice mondo
direttamente all'osso: **ricava il basis a mano** (`rest.inverted() @ target`),
ruotando attorno al giunto giusto. L'assegnazione diretta degenera quando rest e
target divergono, e produce compensazioni assurde nella traslazione.

## 7. Come si autora una clip che l'utente potrà correggere

La tecnica che ha prodotto i risultati migliori non è il bake fitto: è la
**posa sparsa**. Dieci-undici chiavi a corpo intero nei momenti che contano
(anticipazione, contatto, rilascio, assestamento) e l'interpolazione in mezzo.

Perché è meglio: la clip resta **leggibile e modificabile** da un umano, invece
di essere un muro di 96 frame bakeati. E quando l'utente chiede "più
anticipazione sul calcio", si sposta una singola battuta di pose senza cambiare
la durata — cosa fondamentale se quella clip è sincronizzata con un'altra
(finisher e vittima devono combaciare al frame).

Principi di regia che si sono rivelati veri sul campo:
- **Un'azione più lunga non è la stessa azione ripetuta due volte.** Se serve
  più durata, serve un'animazione diversa, non lo stesso gesto in loop.
- Il telegrafo va autorato nella clip, non aggiunto dal codice con un tween:
  se la clip ce l'ha già, la compensazione procedurale è rumore che va rimosso.
- Prima di autorare da zero, cerca la clip sorgente giusta: molto tempo speso a
  "sistemare le braccia in A-pose" si è risolto trovando la variante della
  camminata che le braccia le animava già.

## 7bis. Vestire un personaggio: piastre rigide su un corpo che si piega

> ⚠️ Questa sezione copre i pezzi che stanno **in rilievo** (spalliera,
> ginocchiera, corazza, calzare). Per i pezzi che devono **avvolgere** un arto
> — manica, cosciale, schiniere, guanto — il posamento rigido **non basta e
> nessuna taratura lo rimedia**: vai al **§7ter**.

Montare un'armatura su un corpo animato non è "attaccare una mesh a uno
scheletro": è decidere **quanto ogni pezzo ha diritto di deformarsi**. È il
punto dove si sbaglia per primi, e il difetto non si vede finché il personaggio
non si piega — quindi va guardato **in posa estrema**, mai a riposo.

### La sequenza

1. **Taglia e posto.** I pezzi generati (Meshy, Rodin, Hunyuan) escono
   NORMALIZZATI: centrati sull'origine e inscritti in un cubo unitario, senza
   nessun rapporto col corpo. Vanno portati alla misura e messi al loro posto.
2. **Gonfiatura.** Una piastra ha spessore zero: se la si fa aderente, la pelle
   sbuca da tutte le parti *per costruzione*. Va tenuta larga sopra il corpo.
3. **Legatura.** I pesi si trasferiscono dal corpo NUDO, che è esattamente la
   superficie che la piastra ricopre.
4. **Irrigidimento.** Vedi sotto.

### ⚠️ L'acciaio non si piega — e le due cure sbagliate

**Pesi trasferiti e basta**: la piastra si deforma come la carne che copre.
Guardato in un affondo profondo — la corazza si torceva col busto, le
ginocchiere si accartocciavano, i guanti si sfaldavano sulle dita.

**Tagliare in pezzi rigidi separati, uno per osso**: l'acciaio diventa acciaio,
ma un guscio UNICO tagliato in segmenti **si apre**. Fra una piastra e l'altra
non c'è materiale di sovrapposizione, perché la mesh generata è un pezzo solo e
non un insieme di lamine sovrapposte come lo sarebbe un'armatura authorata. Si
vede il corpo attraverso i varchi. Il taglio è la cura giusta solo se i pezzi
nascono già separati e già sovrapposti.

**La cura che funziona: AFFILARE i pesi.** Si tengono quelli trasferiti e li si
eleva a potenza (esponente 5-8), poi si rinormalizza. Nel mezzo di una piastra
un osso domina già, e l'esponente lo porta a ~1.0: quella zona diventa rigida.
Sul giunto due ossa se lo contendono quasi alla pari, e lì la sfumatura
sopravvive — una fascia stretta che flette e **tiene insieme** le piastre.
Nessun taglio, nessun buco, una manopola sola. Misurato su un set completo:
dominanza mediana 0,998 e ~62% dei vertici già completamente rigidi.

**L'eccezione**: un guscio grande e continuo — un pettorale — va tutto su UN
osso solo. Affilare non basta, perché i pesi lo dividerebbero fra le vertebre e
lo si vedrebbe incernierarsi in tre tronconi. Un pettorale vero è appeso alle
spalle ed è rigido: modellalo così.

### ⚠️ Un pezzo a DUE GUSCI va diviso prima di gonfiarlo

Gambali e bracciali arrivano come una mesh sola con dentro due gusci. Gonfiando
il pezzo intero attorno al suo centro — che sta **in mezzo** ai due arti — le
piastre si allontanano l'una dall'altra e la pelle resta scoperta nel mezzo. Si
divide per gusci e ognuno si centra sul SUO arto.

### ⚠️ Saldare prima di dividere per parti sciolte

`separate LOOSE` su una mesh generata non saldata non vede due bracciali: ne
vede migliaia. I vertici arrivano spezzati sulle cuciture UV, quindi ogni
gruppetto di triangoli è già un'isola. Misurato: 2.266 "parti sciolte", e le due
più grosse avevano 141 vertici su 18.595. Salda a 1e-4 e diventano due.

### ⚠️ I pezzi degli ARTI vanno ruotati; quelli del busto no

I generatori li producono verticali, appesi. Le braccia in A-pose stanno a ~47°
sotto l'orizzontale: un bracciale incollato dritto entra nel fianco.

L'asse **si legge dallo scheletro** (gomito → punta del dito medio), non si
stima e non si scrive a mano. Il segno che è fatto bene: i due bracciali escono
speculari senza che ci sia un angolo scritto da nessuna parte.

Le gambe di solito no: pochi gradi dalla verticale, e la differenza non si vede.

### ⚠️ La maschera che cancella la pelle lavora per REGIONI intere

Se il motore nasconde la pelle sotto l'armatura con una maschera a regioni
(testa/busto/braccia/gambe), quella regione si può spegnere **solo se il pezzo
la copre tutta**. Bracciali che partono dal gomito e gambali che partono da
metà coscia non autorizzano a spegnere "braccia" e "gambe": resterebbero buchi
dove non c'è piastra. O si copre tutto, o si tiene la pelle e si allarga.

## 7quater. ⚠️ CONTA LE DITA PRIMA DI TOCCARE QUALSIASI ALTRA COSA

**I generatori sbagliano il numero delle dita, e lo sbagliano spesso: Meshy ne
fa SEI invece di cinque.** Non e' il caso sfortunato di un pezzo: e' un difetto
noto, segnalato in giro, e va dato per probabile su ogni mano generata.

Il costo di non accorgersene e' tutto il lavoro a valle. Su un bracciale del
progetto e' successo: settimane di fitting, pesatura, affilatura e conformazione
su un guanto a sei dita, e nessuna di quelle tecniche lo rimedia. **Non si
mappano sei dita su cinque**, per quanto bene si sappia vestire.

E non salta all'occhio: in mezzo a una mesh d'acciaio piena di piastre, un dito
in piu' si nota solo se lo si cerca. Un tre quarti non basta — la prospettiva
accorcia e si conta male.

**Quindi si conta per TOPOLOGIA, non a occhio**, e si conta PRIMA di investire un
minuto: prima della pesatura, prima della conformazione, prima di metterlo in una
tabella. Si taglia la mesh a varie quote vicino alla punta e si contano le
componenti connesse; dove il numero e' stabile su piu' quote, quello e' il numero
di dita separate.

⚠️ Il **pollice** e' piu' corto e arretrato: a quelle quote spesso si e' gia' fuso
col palmo e non compare fra le isole. Cinque isole allineate in un ventaglio
vogliono dire **sei** dita, non cinque. Guardare le X: se sono equispaziate sono
tutte dita, e il pollice e' in piu'.

Nel progetto: `arcanium/tools/conta_dita.py`.

E il corollario che risolve il problema alla radice: **un guanto si puo' derivare
dal CORPO** invece che generarlo — il corpo le dita giuste ce le ha per
costruzione. Vedi il guscio derivato nel §7ter.

## 7ter. Far ADERIRE un pezzo generato: la conformazione

⚠️ **Questa sezione supera il §7bis su un punto**: posare rigidamente un pezzo
generato basta solo per ciò che sta IN RILIEVO. Per ciò che deve **avvolgere** un
arto non basta, e nessuna taratura lo rimedia.

### I due problemi che sembrano uno

| | domanda | da cosa dipende |
|---|---|---|
| **Copertura** | il pezzo arriva dove deve? | dall'ESTENSIONE della mesh sorgente. Nessuna trasformazione la crea |
| **Aderenza** | lungo quel tratto sta appiccicato? | dalla DEFORMAZIONE. Le trasformazioni rigide non ne fanno |

Se lasci scoperta della pelle e la tua reazione è "allargo/allungo il pezzo",
stai curando il secondo con lo strumento del primo. Non funzionera'.

### ⚠️ Un tubo dritto non copre un arto che piega

Un pezzo posato lungo la CORDA fra due ossi passa sotto l'articolazione in mezzo,
**comunque lo si dimensioni**. Misurato su un bracciale portato dal gomito alla
spalla: stretto, il braccio esce di sopra; grasso, resta sotto il braccio; in
entrambi i casi la spalla resta nuda. Spalla→gomito→dita non e' una retta.
Gomito→dita quasi si', ed e' per questo che i bracciali si disegnano cosi'.

### LA RICETTA — quattro passi, e l'ordine conta

1. **Posare** grossolanamente, dichiarando l'arto INTERO (spalla→dita), non un
   segmento. La dichiarazione e' cio' che porta la copertura.
2. **Calcolare il vertex group di ADERENZA** — quanto ogni vertice ha diritto di
   muoversi, dalla sua distanza dalla superficie del corpo. E' una **fascia
   attorno alla pelle**, non una semiretta:
   - fra `affondo` sotto la pelle e `stacco` sopra → peso **1**
   - piu' lontano di `stacco + fascia` → peso **0**
   - piu' sepolto di `affondo + fascia` → peso **0**
   - nelle due zone in mezzo → sfuma
3. **Shrinkwrap** `wrap_mode = OUTSIDE`, `offset` = lo stacco della piastra dalla
   pelle (~9 mm), **pesato da quel vertex group**.
4. **Solidify** solo se la sorgente era una superficie sottile.

```python
m = pezzo.modifiers.new("Conforma", 'SHRINKWRAP')
m.target = corpo
m.wrap_method = 'NEAREST_SURFACEPOINT'
m.wrap_mode = 'OUTSIDE'              # ⚠️ NON 'OUTSIDE_SURFACE': vedi sotto
m.offset = 0.009
m.vertex_group = "aderenza"          # il passo che nessuno racconta
```

### ⚠️ I quattro punti che decidono se viene bene o a brandelli

1. **⚠️⚠️ `OUTSIDE`, e NON `OUTSIDE_SURFACE`.** I due nomi si somigliano e i due
   modi fanno il contrario. `OUTSIDE` muove **solo i vertici che stanno dentro**
   il bersaglio e lascia dove sono quelli gia' fuori. `OUTSIDE_SURFACE`
   **PROIETTA sulla superficie** — a distanza `offset`, ma proietta — tutto cio'
   che ha peso, parete esterna compresa: e' la stessa manica lucida che stai
   cercando di evitare, con in piu' il guscio accartocciato.

   **Questa sezione diceva il contrario**, e il contrario e' finito in una
   pipeline di produzione. Costo: gambali sfrangiati attorno al ginocchio, con
   le schegge accavallate fra le due gambe. Misurato su un cosciale: con
   `OUTSIDE_SURFACE` si muovevano **1.720 vertici su 3.894** mentre dentro la
   carne ce n'erano **689**, e **1.075 dei mossi guardavano FUORI** — cioe'
   erano la faccia che si vede. Con `OUTSIDE`: 897 mossi, e il pezzo resta
   intero.

   La sonda che lo coglie in un colpo, e che vale per qualunque deformatore:
   **conta quanti vertici si sono mossi e confrontalo con quanti dovevano
   muoversi**, e per ciascuno guarda se la sua normale punta verso il bersaglio
   o via. Se si muove la faccia esterna, non stai conformando: stai spalmando.

2. **La fascia di aderenza ha un FONDO, e serve.** «Dentro la carne → peso 1»
   sembra ovvio e non lo e': un pezzo posato grossolanamente puo' avere un
   pezzo di se' sepolto **dieci centimetri** dentro il corpo (la cima di un
   cosciale nel bacino), e con peso 1 lo shrinkwrap lo catapulta fuori di
   altrettanto, in schegge. Una piastra sepolta nella carne e' **invisibile**;
   catapultata e' una scheggia che si vede. Il fondo giusto e' dell'ordine dello
   spessore del pezzo piu' un margine — misurato, 35 mm su un cosciale.
3. **Il vertex group conserva lo spessore da solo.** Parete interna vicina alla
   pelle → peso 1 → si appoggia. Cime delle piastre lontane → peso 0 → non si
   muovono. Il guscio non collassa e **non si toglie una sola faccia**.
4. **Il peso si CALCOLA, non si dipinge.** Dalla distanza dal corpo. E' questo
   che rende la cosa sostenibile su decine di capi e su corpi diversi.

Misurato su un bracciale: **728 vertici su 3.859** erano dentro la carne.

### ⚠️ Il bersaglio va SALDATO, o il «dentro» non esiste

Una mesh che arriva da glTF e' **spezzata su ogni cucitura UV**: i vertici sono
duplicati e le facce non condividono spigoli. Misurato su un corpo di 66.190
vertici: **12.312 spigoli di bordo**, cioe' una superficie aperta dappertutto. E
se poi la ritagli per regioni, i buchi se li porta dietro — su una gamba il piede
restava un'isola staccata.

Su una superficie aperta il dentro/fuori **non e' definito**: il punto piu'
vicino cade sul bordo e la normale li' vale quel che vale. Ogni modificatore che
ragiona per dentro/fuori — shrinkwrap, boolean, proiezioni — ci si perde. Un
`remove_doubles` a 1e-4 porta i bordi a zero e costa una riga.

⚠️ E vale per il corpo quanto per il pezzo: e' facile ricordarsi di saldare la
mesh che si sta lavorando e dimenticare quella contro cui la si lavora.

### ⚠️ Due strade sbagliate, provate e guardate

- **Proiettare i vertici sul corpo** (shrinkwrap "normale", o scritto a mano). Il
  pezzo generato e' un **guscio chiuso con spessore**: parete interna ed esterna
  finiscono sullo STESSO punto, il guscio collassa e si strappa. Provando a
  conservare il rilievo lungo la normale viene **peggio** — nastri e schegge.
- **Scorticare** il guscio (togliere le facce che guardano il corpo) e poi
  conformare. Funziona ma buca: 3.358 facce su 7.810 tolte, strappi
  all'articolazione. Il vertex group ottiene lo stesso senza togliere niente.

### ⚠️ Una MANO non e' un arto: il guscio derivato li' non funziona

Ritagliare il corpo funziona su braccia e gambe. Sulla **mano** no, e il motivo e'
strutturale: non e' un cilindro, sono **cinque tubi sottili con pieghe profonde**.
Provate e guardate, tutte fallite: stacco+solidify (i gusci di dita vicine si
compenetrano nelle pieghe), lisciatura forte (il laplaciano restringe e collassa
i tubi), taglio sulla curva di livello (sistema i bordi, non la compenetrazione),
voxel remesh grosso (si mangia il guscio), voxel remesh fine (frammenti staccati:
una superficie aperta e sottile non voxelizza in un solido).

**Un guanto si modella a mano, una volta sola.** Una mano e' una mano: lo stesso
guanto vale per ogni armatura e ogni corpo. E' il pezzo che merita lavoro manuale
piu' di ogni altro — e nel frattempo un bracciale che finisce al POLSO e' un look
legittimo.

### Tagliare via una parte sbagliata: sul CAMPO, non a quota

Quando la mesh generata comprende una parte che non si vuole, si taglia per
appartenenza: per ogni vertice si guarda **su quale osso pesa il punto del corpo
piu' vicino**. Non a occhio, non a una quota fissa lungo l'arto.

E il bordo si pulisce in due mosse, **tutte e due necessarie**:
1. si **liscia il campo** prima di tagliarlo, o il bordo segue il rumore dei pesi;
2. si taglia **sulla curva di livello**, spezzando gli spigoli che la attraversano
   nel punto esatto. Cancellare vertici interi da' una scaletta comunque, perche'
   il bordo puo' solo seguire gli spigoli che gia' esistono.

### La divisione che regge

| tipo di pezzo | esempi | come si fa |
|---|---|---|
| **Sta in rilievo** | spalliera, ginocchiera, corazza, calzare | **posamento rigido** (§7bis) |
| **Avvolge un arto** | manica, cosciale, schiniere, guanto | **conformazione** (questa sezione) |

### Il guscio DERIVATO DAL CORPO, quando serve copertura garantita

Ritagliare la superficie del corpo sulla regione dichiarata (per gruppo d'ossa),
staccarla di 8-10 mm lungo la normale, ingrossarla. Copre **esattamente** cio'
che dichiari e aderisce **per costruzione**, perche' *e'* il corpo. Non da'
l'aspetto: legge come una muta, e i bordi vanno lisciati perche' seguono la
soglia di peso vertice per vertice. Usalo come base da vestire, non come pezzo.

### ⚠️ Non chiedere le misure a un generatore

Meshy, Rodin, Hunyuan sono image/text→3D: **non onorano vincoli metrici**. Non
esiste modo di chiedere "lungo 0,30 m, largo 0,11 al gomito". Con una tavola a
tre viste ottieni **stile**, non misure. Il generatore e' la fonte dell'aspetto,
il fit lo fa la conformazione.

### ⚠️ RBF e Surface Deform risolvono un ALTRO problema

Servono a rifittare un capo **gia' fittato** su un corpo **diverso**: vogliono una
corrispondenza di partenza. Un pezzo appena generato non e' mai stato fittato a
niente, quindi non c'e' niente da trasferire. Sono lo strumento del giorno in cui
arriva il secondo corpo, non del primo fitting.

## 8. Igiene di sessione e di misura

Le sessioni Blender lunghe **si degradano**: operatori che smettono di
funzionare in silenzio, selezioni che non selezionano, bake che riescono senza
assegnare nulla, action che vengono scritte dentro quella sbagliata. Quando il
comportamento diventa incoerente con lo stesso codice che funzionava poche ore
prima, il sospetto numero uno è lo stato di sessione, non un bug nuovo:
ricarica pulito invece di inseguire il sintomo.

Da qui alcune abitudini che costano poco e salvano ore:
- Non fidarti della selezione: preferisci operazioni che non dipendono da essa.
- Azzera esplicitamente ciò che deve essere a zero.
- Marca come "da conservare" le action che devono sopravvivere a un reload,
  altrimenti vengono eliminate perché nessuno le usa.
- Le variabili non sopravvivono tra chiamate separate; i dati nel file sì.
- Scrivi gli esiti degli script su file, non affidarti a ciò che resta a schermo.

## 9. Il ciclo di lavoro

1. **Misura lo stato attuale** e stabilisci il metro di paragone (un asset che
   funziona, nella stessa unità di misura).
2. **Formula UNA ipotesi** e dichiara come la falsificheresti.
3. Applica la modifica **più piccola** che la mette alla prova.
4. **Renderizza e guarda.** Su più frame.
5. Se il risultato è buono, verificalo **nel motore**, che è l'unico giudice.
6. Scrivi cosa hai imparato — incluse le ipotesi cadute.

Quando qualcosa richiede giudizio estetico (una posa, un peso, un grip d'arma),
il ciclo si chiude su una persona, non su una metrica. Prepara la scena, rendi
facile il confronto, e chiedi. Non dichiarare "a posto" ciò che non hai visto.

---

## 10. Come cresce questo taccuino

Questa skill è fatta per **ingrassare a ogni testata presa**. Ogni volta che un
bug di rig, animazione o export costa più di mezz'ora, la lezione va scritta
qui — altrimenti si ripaga lo stesso prezzo fra tre mesi, ed è già successo.

Cosa merita di entrare:
- Un falso positivo nuovo: una verifica che ha detto "ok" mentre era rotto.
- Una causa vera trovata dopo ipotesi sbagliate — **con le ipotesi sbagliate**,
  che valgono quanto la soluzione perché impediscono di ripercorrere il vicolo.
- Una ricetta di diagnosi riusabile: cosa misurare, e cosa non misurare.
- Un'opzione che fa la cosa opposta di quello che sembra.

Cosa **non** merita: lo stato di un progetto (nomi di file, cosa è fatto e cosa
manca, decisioni di design specifiche). Quello vive nelle note di progetto. Qui
va solo ciò che sarà ancora vero sul prossimo gioco, con un altro motore e un
altro personaggio.

Regola di stile: scrivi il **perché**, non solo la prescrizione. Una regola di
cui si è capito il motivo si applica anche ai casi che non avevi previsto; una
regola imparata a memoria si applica solo a quello che è già successo.

Prima di aggiungere una voce, controlla se c'è già una sezione che la riguarda:
meglio arricchire un capitolo esistente che aprirne uno gemello.
