# Export e passaggio al motore

Indice:
1. Export glTF: la lista di controllo
2. Verificare l'export (non fidarsi del "nessun errore")
3. Import nel motore: rimappature, rest fixer, reimport
4. Attaccare un'arma a un osso
5. Collider che devono seguire qualcosa

---

## 0. LE UNITÀ — il difetto che passa ogni controllo e distrugge tutto

Leggi questo prima del resto, perché è quello che costa di più.

Una clip esportata con l'armatura ancora **scalata** (tipico dopo un import FBX:
oggetto a scala 0.01, ossa in centimetri) produce un file **perfettamente
valido**: struttura giusta, numero di tracce giusto, durata giusta, nomi d'osso
giusti, nessun avviso. In gioco il personaggio esplode, perché le posizioni sono
cento volte troppo grandi rispetto allo scheletro che le riceve.

**Diagnosi in dieci secondi, senza aprire il motore:** apri il file esportato e
uno che FUNZIONA, e confronta le trasformate di rest nodo per nodo. Un fattore
100 su tutte le traslazioni, o una rotazione sulla radice che l'altro non ha,
sono la firma.

**Rimedio:** applica rotazione e scala all'armatura **e poi riscala a mano le
fcurve di `location`** — applicare la scala non le tocca (vedi
`clip-e-retarget`), e restano in unità vecchie mentre le ossa sono in unità
nuove. Se la clip nasce da action importate insieme all'armatura, vanno
riscalate **anche quelle**, non solo il risultato: ricomporre da sorgenti non
riscalate rifà il danno.

### Il controllo che va automatizzato: l'INGOMBRO

Nessuna verifica strutturale coglie quel difetto. Quella che lo coglie è
misurare, **nel motore e sul personaggio vero**, il riquadro che contiene tutte
le ossa mentre la clip gira, e confrontarlo con una clip che si sa sana. Un
umanoide sta in un paio di metri; un umanoide esploso ne misura ottanta.

Costa poche righe, gira headless (nessuna finestra, nessun conflitto con un
editor aperto) e va eseguito **prima** di attivare la clip nel gioco. È l'unico
modo onesto di dire "l'ho verificata" quando non puoi guardarla.

E quando una clip nuova rompe il gioco: **prima disattivala** (toglierla dalla
lista delle mosse è una riga), poi diagnostica. Chi aspetta di aver capito
lascia il gioco rotto per tutto il tempo della diagnosi.

## 1. Export glTF: la lista di controllo

Gli errori qui sono silenziosi: il file esce, l'operazione "riesce", e il
contenuto è sbagliato o vuoto.

- **Oggetti nascosti vengono esclusi.** Un'armatura nascosta (magari dopo un
  render di controllo) produce un export con la sola mesh statica: zero skin,
  zero animazioni, nessun errore. Rendi visibile tutto prima di esportare.
- **Con lo scheletro in posizione "rest" l'export può fallire in silenzio**
  producendo un file senza rig. Rimetti la posa normale prima di esportare.
- **La modalità "tutte le action" esporta davvero tutte le action del file**,
  incluse quelle ereditate da import precedenti. O rimuovi le altre, o usa la
  modalità "solo action attiva".
- **Le action duplicate** (stesso nome con suffisso numerico, tipiche delle
  sessioni lunghe) finiscono nell'export raddoppiando le clip. Pulisci prima.
- **Se un'action deve sopravvivere a un salvataggio/ricarica, marcala come da
  conservare**: un'action non assegnata a nessun oggetto viene eliminata al
  reload. Si perdono così bozze intere.
- Se il sistema usa **slot di action**, assegnare l'action non basta: senza slot
  assegnato l'esportatore salta l'animazione.
- Non applicare il modificatore dell'armatura in export.

## 1bis. Formati e topologia: quad in lavorazione, triangoli nel motore

**Nel motore i quad non esistono.** La GPU disegna solo triangoli, e ogni
motore triangola qualunque formato all'import (OBJ, FBX, GLB). Scegliere FBX o
OBJ "per tenere i quad in gioco" non tiene niente. Il valore di una topologia
quad pulita — anelli di spigoli che seguono pieghe e articolazioni, vertici
regolari — **sopravvive** alla triangolazione, perché lo skinning lavora sui
vertici: si perde solo l'etichetta.

I quad contano dove si **lavora** il corpo: rig, pesi, ritocchi. Quindi:
- **dal generatore a Blender, il formato che li conserva.** Il GLB triangola; ricomporre
  i quad dopo (`tris_convert_to_quads`) ne recupera solo una parte e dà una
  topologia diversa da quella generata. L'FBX la porta intatta (anche i
  triangoli che il generatore lascia apposta, e che una ricomposizione
  fonderebbe);
- **verso il motore, il formato nativo del motore** (glTF per Godot);
- **la triangolazione falla tu**, in Blender, prima dell'export: metodo
  *Beauty* (la diagonale più corta, niente pieghe d'ombra sui quad non piani),
  invece di lasciarla all'esportatore. I gruppi di vertici restano;
- **valida la mesh dopo**: i generatori lasciano facce doppie o a area zero, e
  l'esportatore glTF le toglie da sé con un avviso ("Mesh … is not valid") e
  qualche triangolo in meno nel file. Toglile prima e contale.

OBJ è comunque escluso per un personaggio: non porta scheletro né pesi.

**La texture esce col nome del FILE, non dell'immagine.** Se un'immagine ha un
percorso su disco (tipico delle texture di un FBX), l'esportatore glTF la chiama
come il file (`tripo_image_<uuid>_0_0.jpg`), anche se l'hai rinominata; il
motore la estrae accanto al modello con quel nome e smette di riusare quella
che c'era. Incorpora l'immagine e dalle anche il **percorso** col nome giusto.

## 2. Verificare l'export

**Non considerare finito un export che non hai ispezionato.** La verifica è
rapida: i file glTF/GLB hanno un blocco JSON leggibile in testa (nel GLB: la
lunghezza del chunk è un intero a offset 12, il JSON comincia subito dopo
l'intestazione). Leggilo e controlla:

- `meshes` — c'è la mesh che ti aspetti?
- `skins` — esiste, e ha il numero di giunti giusto? ⚠️ Un giunto in PIÙ di
  nome `neutral_bone` vuol dire che qualche vertice aveva peso (quasi) nullo e
  l'esportatore l'ha appeso a un osso fantasma: in gioco resterà fermo. Vedi
  `rig-e-skinning.md` §4quater.
- `animations` — ci sono le clip che volevi, coi nomi puliti e senza duplicati?

Questa singola ispezione ha intercettato: export senza rig, clip doppie, clip
mancanti, e la scoperta che *tutte* le clip bakeavano tracce di scala.

## 3. Import nel motore

**Rimappature ossee e correzione della rest.** Alcuni motori applicano in
import una mappa da nomi arbitrari a un profilo standard, e possono
**ri-orientare la rest** verso una silhouette canonica. Conseguenza cruciale:
una clip espressa sulla rest grezza, applicata a uno scheletro ri-orientato,
**esplode**. Se il modello base ha quel trattamento, le clip separate devono
avere lo stesso identico trattamento nei loro file di import.

Se scrivi a mano un blocco di configurazione d'import annidato: **conta le
graffe**. Un blocco troncato non viene parsato, il motore torna ai default e —
beffardo — al reimport **riscrive il file** cancellando il tuo blocco. Sintomo
in gioco: si muovono solo le ossa che hanno lo stesso nome nei due schemi
(bacino, spalle, mani, piedi, testa) mentre il resto resta in posa di riposo.
Rileggi sempre il file **dopo** un reimport.

**Diagnosi decisiva per questa famiglia di bug:** stampa i **percorsi delle
tracce** di una clip che funziona e di una che non funziona, e confrontali. Se
una ha nomi grezzi e l'altra nomi del profilo standard, hai trovato la causa in
dieci secondi.

**Il reimport headless spesso non attecchisce.** Un file modificato fuori
dall'editor può non essere visto dal runtime, che continua a usare la versione
in cache. Metti "l'utente apre l'editor" come passo manuale esplicito, invece di
dare per scontato che la riga di comando sia bastata.

**Attenzione a non editare file di testo con strumenti che aggiungono un BOM**:
alcuni parser non lo digeriscono e il file diventa invalido senza un messaggio
chiaro.

## 3bis. L'ingombro di una mesh SKINNATA non si chiede alla mesh

Serve spesso: mirare al centro di un personaggio, piazzare una barra vita sopra
la testa, decidere se un colpo passa alto. La strada ovvia — chiedere alla mesh
il suo bounding box e portarlo in spazio mondo — **è sbagliata su tutto ciò che
è animato**, ed è un falso positivo di manuale: il risultato è un box, non è
vuoto, ha dimensioni dell'ordine giusto, e descrive un'altra cosa.

Il motivo: su una mesh skinnata quel box è quello dei dati **a riposo**, nello
spazio in cui sono salvati, e la posa la mette lo scheletro — che quel box non
lo sa. Se poi i dati sono in una convenzione d'assi diversa da quella della
scena, moltiplicare per la trasformata mondo produce una scatola *ruotata*:
su un quadrupede è venuto fuori un ingombro alto quanto l'animale è **lungo**,
col centro esattamente sull'origine del modello. Nessun controllo numerico lo
segnala, perché tutti i numeri sono plausibili.

**Il modo giusto:** misurare le **ossa** nella posa corrente — il riquadro che
contiene le loro posizioni globali. È l'unica misura che segue l'animazione, e
per il centro basta calcolarlo nello spazio dello scheletro e trasformarlo alla
fine (trasformare prima i due estremi e ricomporre il riquadro dà il centro
giusto solo se lo scheletro è allineato al mondo).

Utile prevedere, in ordine: un nodo marcatore messo a mano (per i casi strani),
poi le ossa, poi il box della mesh **solo se non è skinnata** (per i prop
rigidi è corretto), infine una quota di ripiego.

E vale la pena ricordare perché una **quota fissa** non è mai la risposta:
tarata su un umanoide, su una bestia bassa il marcatore galleggia in aria e
tutto ciò che ci punta contro passa sopra.

## 4. Attaccare un'arma a un osso

Il grip è un offset **relativo all'osso**, quindi si tara benissimo a riposo e
vale identico in ogni clip. Due trappole:

**Il nodo di aggancio è guidato dall'osso.** Se il sistema aggiorna quel nodo
dalla posa ogni frame, qualunque transform tu scriva lì viene sovrascritto.
Metti l'offset sul **figlio** (l'arma), non sul nodo di aggancio.

**Attento alla convenzione delle matrici.** Se costruisci una base matematicamente
e la scrivi in un formato di scena, verifica se quel costruttore è per righe o
per colonne: incollare le colonne dove servono le righe dà la **trasposta**,
cioè la rotazione inversa, cioè un risultato ribaltato che sembra "quasi giusto".
Il modo sicuro: **rileggi dall'engine** il risultato finale nella stessa
esecuzione e confrontalo col bersaglio voluto, invece di fidarti del calcolo.

Metodo "sonda" per fittare senza indovinare: una scena usa-e-getta che istanzia
il personaggio, forza la posa, legge la base **mondo grezza** del nodo di
aggancio (non ortonormalizzata: le ossa possono avere scala cotta dentro),
calcola la rotazione che porta l'asse dell'arma sul bersaglio, e **valida
rileggendo** il risultato.

## 5. Collider che devono seguire qualcosa

Se un collider deve seguire un oggetto animato **trascinato da un genitore**
(l'anta di una porta che ruota, un'arma in mano), attenzione all'opzione di
sincronizzazione con la fisica: quando è attiva, il corpo si fa riscrivere la
posa dal server di fisica a ogni tick, e quella riscrittura **sovrascrive** la
trasformata ereditata dal genitore. Il risultato: l'oggetto si muove a schermo e
il collider resta piantato dov'era. Quell'opzione serve a chi **muove il corpo
direttamente** (piattaforme che devono spingere il personaggio); per un corpo
trascinato va disattivata.

**Diagnosi in dieci secondi:** un raggio attraverso il passaggio, prima e dopo
il movimento. Se colpisce lo stesso corpo alla stessa distanza, il collider non
si è mosso — e il nome del corpo colpito ti dice anche *quale* sta bloccando,
il che spesso rivela che il colpevole era un altro.

Nota di forma: una forma di collisione di solito funziona **solo** come figlia
diretta di un corpo. Appesa a un nodo qualsiasi non esiste per la fisica, e si
passa attraverso l'oggetto senza alcun errore in console.
