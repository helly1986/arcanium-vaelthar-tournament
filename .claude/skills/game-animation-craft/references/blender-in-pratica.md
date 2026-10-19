# Blender in pratica — scripting, sessioni, spazi

Indice:
1. Spazi, assi, matrici
2. Action e posa (Blender 4.x/5.x)
3. Sessioni lunghe che si degradano
4. Il loop visivo
5. Verificare senza aprire l'interfaccia

---

## 1. Spazi, assi, matrici

**Tre spazi diversi, facili da confondere:** locale-osso, armatura, mondo. Gli
assi "alto" e "avanti" possono differire fra lo spazio dell'armatura e quello
del mondo **nello stesso file** (tipico dopo un import con conversione di
convenzione). Misura, non assumere: stampa qualche posizione nota (bacino,
orecchie, zampe) e deduci quale asse cresce verso l'alto.

**`rotation_euler == (0,0,0)` NON vuol dire che `matrix_world` è l'identità.**
La trappola più costosa di questa famiglia, e ci si ricasca ogni volta. Un
modello importato da glTF arriva spesso **Y-up nei dati della mesh** (`v.co`) e
**Z-up nel mondo**, perché la conversione di convenzione sta in `matrix_world`
(via `delta_rotation` o la matrice inversa del genitore) e **non** in
`rotation_euler`, che si stampa a zero e rassicura. Stampare `rotation_euler`,
`location` e `scale` e concludere "l'oggetto non è trasformato" è un falso
positivo perfetto.

Sintomo tipico: una camera puntata su coordinate lette da `v.co` inquadra il
vuoto o un pezzo a caso, e sembra un bug del render. Oppure una rotazione
"attorno all'asse X" ruota nel piano sbagliato.

- **Diagnosi in una riga:** confronta la bbox dalla mesh locale con quella dei
  vertici moltiplicati per `matrix_world`. Se gli assi si scambiano o cambiano
  segno, hai due convenzioni nello stesso file.
- **Rimedio:** scegli **uno** spazio e dichiaralo in cima allo script. Conviene
  il mondo: `p = obj.matrix_world @ v.co` per leggere, e
  `v.co = obj.matrix_world.inverted() @ p_nuovo` per riscrivere. Le coordinate
  che ti passa una persona guardando la viewport sono sempre in **mondo**.

**Corollario sulla camera:** in `direzione.to_track_quat('-Z', su)`, `su` è
l'asse **locale** della camera tenuto verso l'alto del mondo — per una camera in
un mondo Z-up è sempre `'Y'`, anche quando il modello ha l'alto su un altro
asse. Metterci `'Z'` perché "il mondo è Z-up" produce un'inquadratura ruotata di
90°, che si scambia facilmente per un modello messo storto.

**La `location` di un osso in posa è in spazio osso.** Non è "giù nel mondo".
Per un movimento nel mondo, costruisci la matrice voluta in spazio armatura e
ricava il basis:

```
basis = bone.matrix_local.inverted() @ target
```

dove `target` include la rotazione **attorno al giunto** (trasla al pivot,
ruota, ritrasla) e la traslazione voluta. Questo è anche l'unico modo robusto:
assegnare direttamente la matrice dell'osso in posa degenera quando rest e
target divergono — produce una rotazione quasi singolare e costringe la
traslazione a valori assurdi per compensare.

**Il vettore testa→coda di un osso non è la direzione dell'arto** se il rig è
stato importato senza ri-orientamento automatico. Può essere quasi
perpendicolare, e certe ossa sono monconi di pochi centimetri. Per mirare un
arto usa `testa dell'osso → testa del figlio`.

**Ordine di elaborazione.** Se costruisci una posa assegnando trasformate, vai
dai **genitori alle foglie** e aggiorna la dipendenza **dopo ogni osso**: senza,
l'errore si propaga come un ritardo di un frame che sembra "quasi giusto" e
decade nei frame successivi.

## 2. Action e posa

- Nelle versioni recenti le action sono **a slot**: le fcurve non stanno più
  direttamente sull'action ma sotto livelli/strip/channelbag. Per creare
  animazione basta comunque inserire keyframe; per **leggerle** serve navigare
  la nuova struttura. E per esportare, se lo slot non è assegnato l'esportatore
  salta l'animazione.
- **Editare la posa con l'action assegnata non funziona**: l'aggiornamento
  ripristina i valori dalle fcurve e le modifiche svaniscono. Pattern corretto:
  stacca l'action → edita e aggiorna → riattacca solo per inserire i keyframe.
- **Marca le action da conservare**, o al reload spariscono perché nessuno le
  usa.
- **Prima di ogni ciclo import→bake, stacca l'action attiva dal target.** Se
  resta assegnata un'action con lo stesso nome che vorresti dare al risultato,
  il bake può scrivere *dentro* quella esistente, corrompendo silenziosamente
  una clip già buona.
- **Azzera esplicitamente i canali di posa** prima di comporre una posa nuova:
  i residui di un bake precedente sopravvivono anche dopo aver rimosso l'action.
  Un canale di posizione non azzerato fa ereditare e **sommare** l'offset di
  clip in clip, con errori che crescono di file in file.

## 3. Sessioni lunghe che si degradano

Dopo ore di lavoro scriptato, con cambi di modalità e override di contesto
ripetuti, cominciano comportamenti incoerenti **senza errori**:

- operatori di selezione che smettono di selezionare, quindi operazioni
  "solo sui selezionati" che non fanno nulla;
- bake che riportano successo **senza** assegnare la nuova action (l'action
  esiste comunque con un nome generico: cercala e assegnala a mano);
- l'oggetto sorgente ancora selezionato che si becca l'action bakeata,
  sovrascrivendo silenziosamente ciò che conteneva.

Abitudini che costano poco: non fare dipendere le operazioni dalla selezione;
deseleziona tutto e seleziona esplicitamente ciò che serve; verifica il
risultato invece del valore di ritorno.

**Regola diagnostica:** se lo stesso codice che funzionava poche ore prima ora
si comporta in modo strano, il sospetto numero uno è lo stato di sessione, non
un bug nuovo. Ricarica pulito e riparti.

**Non usare un reset di fabbrica per pulire la scena** se stai lavorando
attraverso un'estensione o un ponte: disattiva l'estensione stessa e tronca la
connessione. Rimuovi i datablock uno per uno.

**Dopo un reload il contesto resta instabile per la chiamata immediatamente
successiva.** Se un import fallisce subito dopo un reload lamentando un contesto
mancante, separa reload e prima operazione in due chiamate distinte.

**Le variabili non sopravvivono tra chiamate separate**, le funzioni nemmeno:
o metti tutto il lavoro di una clip in un blocco solo, o ridefinisci ogni volta.
Se un valore deve sopravvivere (per esempio una cache calcolata *prima* di
un'operazione che la renderebbe irrecuperabile), salvalo come proprietà
personalizzata sull'oggetto: quello vive nel file.

## 4. Il loop visivo

Lavorare alla cieca con soli render e matematica produce risultati pessimi sui
deform organici. Se puoi vedere il viewport, usalo:

- Dopo una modifica **solo da script** il viewport non si ridisegna da solo: lo
  screenshot mostrerebbe il fotogramma precedente. Forza il ridisegno prima di
  guardare.
- Pulisci la vista: nascondi le armature di display (i loro giunti ingombrano) e
  gli oggetti vaganti.
- Scegli viste **funzionali alla domanda**: dall'alto lungo la normale del
  palmo per contare le dita; di profilo per giudicare un arrotolamento; frontale
  ortografica per giudicare se le gambe si incrociano.

**Nascondere non è togliere.** Per isolare una parte e fotografarla da sola,
`mesh.hide` (Edit Mode) e i flag di nascondimento non servono: il render
disegna la geometria lo stesso, e le due prove "solo la parte" e "tutto tranne
la parte" escono **identiche**. Sembra che la selezione non abbia funzionato, e
invece è il render che ignora quei flag. Per un isolamento credibile: duplica
l'oggetto e **cancella** davvero i vertici dalla copia (`bmesh.ops.delete`),
stampando quanti ne restano — è la prova che l'isolamento è avvenuto.

Utile come coppia: la parte **da sola** dice cosa hai preso, il resto **senza la
parte** dice cosa hai lasciato indietro. La seconda immagine è quella che
smaschera un'isolamento incompleto, perché mostra il buco.

Se il viewport non c'è, il ripiego è il render workbench con camera ortografica,
su più frame. Con un piano di riferimento a quota zero, se serve giudicare il
contatto col terreno: senza un piano, "appoggia" e "sprofonda di dieci
centimetri" sono indistinguibili.

## 5. Verificare senza aprire l'interfaccia

Ricette headless che si sono rivelate riusabili:

**Escursione di una traccia.** Per ogni traccia di posizione, misura lo span
(max − min) per asse. Serve a dimostrare che una separazione è avvenuta davvero:
per esempio, se hai spostato la componente orizzontale su un osso radice, ti
aspetti span verticale zero su quello e span orizzontale zero sul bacino.

**Invarianza.** Quando una trasformazione deve essere *neutra* (spostare dati fra
due ossi senza cambiare il risultato), il test è che la posizione mondo
dell'osso interessato resti identica frame per frame. Un errore massimo
nell'ordine di 1e-6 è una dimostrazione; "sembra uguale" no.

**Confronto fra due versioni di una risorsa binaria.** "Salvato, ok" non prova
niente su un file che non si può diffare. Carica la versione nuova e la vecchia
insieme e confronta la traccia interessata frame per frame (differenza angolare
fra quaternioni). Così sai *dove* è cambiata e *di quanto*, e che il resto è
intatto.

**Guardie negli script di migrazione.** Meglio fallire rumorosamente che salvare
una libreria corrotta: aborta se i percorsi delle tracce non hanno il prefisso
atteso, o se il conteggio delle animazioni cambia quando dovrebbe restare uguale.

**Esito su file, non su schermo.** Un processo che termina subito dopo aver
stampato può non lasciare nulla di leggibile a chi lo ha lanciato. Scrivi
l'esito su un file di testo.
