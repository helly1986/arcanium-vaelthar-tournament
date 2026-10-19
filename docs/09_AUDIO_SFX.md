# 09 — AUDIO SFX: come facciamo i suoni di Arcanium

> Stabilito il 2026-08-14. Il mestiere generale sta nella skill
> `.claude/skills/game-sfx-craft/` (nel repo, cosi' e' condivisa fra le macchine) — qui c'è solo ciò che riguarda Arcanium.

## Il problema

Le musiche ci sono (Lyria). **Gli SFX sono ancora tutti del template**: 88 WAV in
`audio/SoundFX/`, divisi in 16 categorie (`hit`, `swoosh`, `swish`, `clang`,
`step`, `cloth`, `fire`…). Sono suoni generici da soulslike-tutorial, e non
raccontano niente di questo gioco: non c'è un boato per gli schianti a terra, non
c'è un crollo per le colonne, non c'è nulla per le cariche arcane.

---

## 1. Lo strumento: ElevenLabs Sound Effects su fal.ai

`fal-ai/elevenlabs/sound-effects/v2` — **$0.002 al secondo**, cioè mezzo
centesimo per un impatto da 3 s. Il costo non è un vincolo: si generano venti
varianti e se ne tengono due.

### Perché quello e non altri — misurato, non supposto

Stesso prompt di schianto, 3 secondi, due modelli a confronto:

| modello | <200 Hz | 200 Hz–2 kHz | >2 kHz | risultato |
|---|---|---|---|---|
| **ElevenLabs SFX v2** | **90.5%** | 4.4% | 5.1% | un boato vero |
| Sonilo text-to-SFX | 5.0% | 11.8% | **83.3%** | detriti e fruscio |

Due suoni completamente diversi dallo stesso testo. Per Arcanium — dove quasi
tutto ciò che manca è **peso** (schianti, crolli, cariche) — vince ElevenLabs
senza discussione. Sonilo resta da riprovare per le cose leggere (foglie, stoffa,
passi sulla ghiaia), dove quella banda alta è quella giusta.

Altri modelli utili sul catalogo, verificati esistenti:
- `fal-ai/stable-audio-3/small/sfx/audio-to-audio` → **fare le VARIANTI** di un
  colpo approvato invece di rigenerarlo da zero;
- `mirelo-ai/sfx1.6/extend-audio` → allungare una coda tagliata corta;
- `fal-ai/hunyuan-video-foley` → foley su una clip già renderizzata.

---

## 2. Stato dell'audio, famiglia per famiglia

### ① Schianti e crolli — ✅ FATTI E CABLATI
`SchiantoATerra` e `OggettoDistruttibile` non sono più muti.
Resta da fare, se un giorno servisse più varietà: una versione su TERRA BATTUTA
(oggi c'è solo la pietra) e i singoli rimbalzi dei frammenti.

### ② Fendenti — ✅ FATTI E CABLATI
`audio/SoundFX/fendenti/`. Tre famiglie per **tipo di danno** (che è la
suddivisione che il gioco ha già nelle armi) × leggero/pesante — e la seconda
distinzione esiste già nel codice, è `secondary_action`.

| | <200 Hz | 200 Hz–2 kHz | >2 kHz |
|---|---|---|---|
| `taglio_leggero` (lame) | 6% | 15% | **79%** |
| `taglio_pesante` (spadone) | 35% | 39% | 27% |
| `perforazione_leggero` (giavellotto) | 32% | 46% | 22% |
| `perforazione_pesante` (lancia) | 54% | 18% | 28% |
| `schianto_leggero` (mazza) | 43% | 50% | 7% |
| `schianto_pesante` (maglio) | 37% | 57% | 6% |

Le tre famiglie si separano bene: il taglio è acuto, lo schianto è sordo (6-7%
di alte), la perforazione sta in mezzo. Dentro ogni famiglia il pesante ha più
bassa del leggero — che è l'unica cosa che devono fare.

### ②ter I COLPI — dove vive la personalità dell'arma
`audio/SoundFX/colpi/`. Matrice **3 tipi di danno × bersaglio/mondo**:

| | su bersaglio | sul mondo |
|---|---|---|
| **taglio** | 23% / 28% / 49% | 1% / 13% / 86% |
| **perforazione** | 20% / 28% / 52% | 2% / 5% / 93% |
| **schianto** | 37% / 28% / 35% | 46% / 28% / 25% |

⚠️ **Il colpo NON è il fendente.** Il fendente è l'aria spostata e parte con lo
swing; il colpo è il contatto. Sono due suoni distinti nello stesso gesto, ed è
la loro DISTANZA a far sentire il peso dell'arma.

**Lo strato viscerale entra DOPO l'impatto**, non insieme: sangue a 45 ms sul
taglio e 35 sulla perforazione, crack d'ossa a 30 ms sullo schianto. La lama
tocca, *poi* il corpo cede — sovrapposti sullo stesso istante si fondono in un
rumore solo e si perde proprio la lettura che aggiungono.

⚠️ **Il colpo sul mondo suona SOLO su collisione vera.** Nasce da
`body_entered` dell'Area3D della lama, cioè da una sovrapposizione fisica:
menare nell'aria non emette niente. (Nota: una spazzata bassa che tocca il
terreno lo fa suonare — è una collisione autentica, ma se in gioco desse
fastidio si escluderebbe il layer del suolo.)

⚠️ **Un colpo per FENDENTE, non per corpo colpito.** Un fendente che prende tre
nemici sparerebbe tre campioni sovrapposti, che si sentono come distorsione e
non come tre colpi. Stessa disciplina che il danno ha già con `_hit_this_swing`.

Il suono di PARATA non è stato fatto: quello del template va già bene, e semmai
si modifica quello.

### ②bis Voci dei nemici — ✅ FATTE E CABLATE
`audio/SoundFX/nemici/`. Vedi §2quater per la firma che le tiene insieme.

⚠️ **Due suoni li ho bocciati io prima di mandarli all'utente, sulla sola
misura**, ed è il caso in cui le misure servono davvero:
- la **perforazione pesante** usciva più ACUTA della leggera (53% di alte contro
  22%): l'arma grossa suonava più sottile di quella piccola;
- il **ruggito del Senza Nome** aveva l'**1%** sotto i 200 Hz. Per una cosa
  immensa non è una sfumatura: senza bassa non c'è massa.

Rifatti chiedendo il contrario sono usciti all'estremo opposto (91% e 87% di
sub, inudibili sui portatili), quindi la versione buona è la **stratificazione**
delle due, con gli strati allineati sul picco.

### ③ Cariche arcane — ✅ FATTE E CABLATE
Spada del Senza Nome, transizione a fase 2, e **evocazioni del protagonista**
(`SpellCaster.cast_summon`).

⚠️ **È lo STESSO campione per il boss e per il player, ed è voluto.** L'Arcanium
è uno solo: un'evocazione del protagonista attinge alla stessa cosa a cui
attinge lui, e che il suono sia riconoscibilmente lo stesso è un pezzo di
racconto, non un riuso pigro. Le distingue il TONO — più acuto per il player,
perché è magia di un uomo e non di ciò che il Senza Nome è diventato.

⚠️ **Il tono si alza in proporzione all'attesa**, e i numeri sono ancorati alla
clip vera (`player_evocazione.glb`, autorata in Cascadeur, commit `71aa93d`):

| | |
|---|---|
| durata della clip | 4,00 s |
| 0,6–1,1 s | la RACCOLTA: le anche scendono di 37,7 cm |
| 1,1–1,6 s | tenuta bassa, la carica |
| `summon_release_delay` | **2,10 s** — misurato sull'apice |
| durata del campione | ~3,9 s |
| tono applicato | 3,9 / 2,10 = **1,86×** → il suono finisce a 2,10 s |

Il culmine cade quindi ESATTAMENTE sulla comparsa della creatura. Senza
comprimere la salita, il suono starebbe ancora caricando mentre il minion è già
lì, e il culmine arriverebbe sul vuoto. Stessa logica del windup del boss.

⚠️ Il ramo con `delay` 0 resta nel codice come ripiego: serve se un domani
qualcuno evoca senza gesto (`has_oneshot("Summon")` falso). Oggi NON è il caso —
il nodo `Summon` è nel BlendTree del player e la clip c'è.

### ④ COSA MANCA DAVVERO, oggi
- **passi** per superficie (il template ne ha di generici);
- **UI**: menu, equipaggiamento, level-up;
- **ambienze** dei livelli (vento della Traccia, bosco di Kalvorn);
- varianti dei colpi e dei fendenti (oggi ce n'è **una sola** per casella: alla
  terza volta si riconosce — vedi la regola delle varianti nella skill).

---

## 2quater. ⭐ LA FIRMA DELLA MAREA SORDA

**L'eco innaturale è il marchio udibile di tutto ciò che la Marea Sorda ha
toccato.** Non un effetto su un nemico: la cosa che li fa riconoscere *come
famiglia* prima ancora di vederli.

Si applica su una voce/verso generato **PULITO** (nel prompt:
`recorded completely dry and close in a padded room, no reverb, no echo`) e la
lavorazione la fa il codice, uguale per tutti. È l'unico modo perché sia una
firma e non la reinterpretazione che il modello darebbe a ogni generazione.

### I tre profili — si scelgono per FUNZIONE, non per creatura

| profilo | quando | com'è fatto |
|---|---|---|
| **annuncio** | la creatura si fa notare | 6 livelli che scendono + **l'eco che PRECEDE** |
| **richiamo** | ululato, ringhio, minaccia che dura | 4 livelli, nessun preavviso |
| **reazione** | morso, colpo subito | **2 sole** ripetizioni, nessun preavviso |

⚠️ **Sulla reazione niente eco che precede, mai.** Un colpo va sentito quando
arriva: un'eco che lo anticipa lo trasformerebbe in un annuncio, cioè in
un'altra informazione di gioco.

Ogni ripetizione è **più grave, più sorda e ritardata**, e il tutto **non decade
come farebbe una stanza vera**: sono le tre cose che la rendono innaturale.
Il passa-basso a ogni livello è obbligatorio — senza, non è un'eco, sono due
voci sovrapposte.

### ⚠️ La forza va dosata per specie
- **Consumati: firma piena (1.0)** — sono i portatori dell'eco.
- **Lupi del Branco Guasto: 0.60–0.70** — sono *contagiati*, non portatori. A
  forza piena l'animale spariva dietro l'eco e tornava a sembrare una macchina,
  che è esattamente il difetto da cui il ringhio era stato rifatto.

### I versi, per indole
I Consumati sono di ogni tipologia e casata, e la loro indole si sente:
`consumato_annuncio_saggio_1/2` (il *mmmm* di meditazione),
`consumato_annuncio_belligerante_1` (grugnito d'avvertimento),
`consumato_annuncio_mago_tuha` e `_saka` (sillabe rituali in lingua morta).

⚠️ Qui voci DIVERSE fra loro sono un pregio, ed è il contrario della regola del
protagonista: sono creature diverse, non lo stesso personaggio che si ripete.
Altre sillabe da fare quando servono: `wei-ra`, e via così.

---

## 2ter. VOCI DEL PROTAGONISTA — la specifica

Doppie, **maschile e femminile**: il protagonista è personalizzabile, e la voce
si sceglie insieme al corpo.

| famiglia | quando | forma |
|---|---|---|
| **dolore lieve** | ogni colpo subito | ~450 ms, sommesso. **5 varianti** a rotazione casuale |
| **dolore forte** | vedi la soglia qui sotto | ~1.4–1.6 s, pieno |
| **dolore continuo** | danno nel tempo (il fuoco del Senza Nome) | loop ansimante |

### ⚠️ La soglia del grido forte
Scatta quando **un singolo colpo toglie più di metà della vita MASSIMA** — non
quando il colpo ti lascia sotto metà vita. Sono due cose diverse e solo la prima
dice la cosa giusta: *«occhio, un altro così senza curarti e vai KO»*. È un
**avvertimento sulla potenza del colpo**, non un annuncio del tuo stato di
salute — che il giocatore legge già dalla barra.

```gdscript
# in ArcaniumHealthSystem._on_damage_signal, dove il danno finale e' gia' noto
var grave : bool = dmg > float(total_health) * 0.5
```
⚠️ `total_health` (il massimo), non `current_health`: con la vita corrente la
soglia si abbasserebbe man mano che si è feriti, e il grido forte partirebbe su
colpetti qualunque proprio quando si è già in difficoltà.

### ⚠️ Le 5 varianti NON si rigenerano
Rigenerando lo stesso prompt esce **un'altra persona** (misurato: 377 Hz contro
191 Hz sullo stesso testo). Le varianti si ricavano dalla registrazione
approvata per ricampionamento a ±5.5%. Vedi la skill, §5.

### Cosa ha funzionato nei prompt
- «guerriera» invece di «donna»: il primo grido forte femminile era
  melodrammatico e impaurito. Chiedere **registro di petto, rabbia invece di
  paura, grido troncato dalla volontà** ha dato una condottiera;
- per il respiro fitto, l'**immagine** batte il numero: «about three per second»
  dava 1-2 respiri/sec, «like a dog breathing fast but human» ne dà 4-6.

---

## 2bis. I primi tre suoni APPROVATI (2026-08-14)

Sono in `audio/SoundFX/`, già preparati per il motore (mono, 44.1 kHz, 16 bit,
picco a −1 dBFS).

| file | cos'è | come si usa |
|---|---|---|
| `schianto/schianto_masso_1.wav` | botta terrificante sul terreno, secca | **attacchi con schianto dei boss** → `SchiantoATerra` |
| `schianto/crollo_colonna_1.wav` | schianto che produce tanti piccoli detriti | **sfondamento della colonna** → `OggettoDistruttibile` |
| `ambiente/pyrrath_fresatrice_acciaio_loop.wav` | fresatrice sull'acciaio caldo | officine di **Pyrrath** |
| `ambiente/cono_accumulo_calmo_loop.wav` | accumulo caldo e tranquillo | **in prossimità di un Cono** |
| `magia/carica_arcana_1.wav` | carica aggressiva, energia che sale | spada del Senza Nome, transizione fase 2, **evocazioni del protagonista**, **palla d'energia** — allungata o accorciata secondo il caso |
| `magia/verath_spettrale_1.wav` | la stessa carica, ma con un che di spettrale | uno **spell di Verath** |

⚠️ **Le due cariche nascono dallo stesso prompt con due sfumature diverse, e le
misure avrebbero scelto quella sbagliata.** `verath_spettrale` ha il 47% nei medi
contro il 27% dell'altra, cioè il numero che avevo inseguito per tre tentativi —
eppure all'ascolto la carica aggressiva è l'altra, e questa suona *spettrale*.
È la regola scritta in fondo a questo documento, vista all'opera: **le misure
escludono i suoni del tipo sbagliato, non promuovono quelli belli.**

### ⚠️ Perché i primi due sono due suoni e non uno
Nascono dalla stessa coppia di generazioni, e la tentazione era tenerne uno solo.
Sono invece **due eventi diversi**, e la differenza è esattamente quella fra i
due sistemi che li suonano:
- il **colpo del boss** è un evento istantaneo e violento — un botto secco e
  basta. Serve il pezzo puro, con l'attacco a 50 ms;
- il **crollo** è un evento che DURA — crepa, caduta, detriti che rimbalzano.
  Serve la versione stratificata (corpo + craccata), il cui attacco più lungo
  (190 ms) qui non è un difetto ma la caduta che si sente arrivare.

Usare il secco sul crollo lo farebbe finire prima che i frammenti si siano
fermati; usare lo stratificato sul colpo del boss toglierebbe secchezza al colpo.

⚠️ **Due dei tre sono generazioni "sbagliate" riusate.** La fresatrice nasce da
un tentativo fallito di fare il ronzio arcano; l'accumulo del Cono è il ronzio
bocciato perché troppo cupo e basso, che a volume tenuto giù diventa esattamente
la cosa giusta per un Cono. Costano mezzo centesimo l'una: **prima di buttare una
generazione, riascoltala con l'orecchio di un altro contesto.**

⚠️ **Avvertenza sull'accumulo del Cono:** ha l'**83% dell'energia sotto i 120 Hz**,
cioè sotto la soglia che un altoparlante di portatile non riproduce. Sulle casse
buone e in cuffia funziona benissimo; su un portatile sarà quasi inudibile. Va
bene finché è **atmosfera**; se un giorno dovesse portare informazione di
gioco («qui c'è un Cono»), servirà stratificarci sopra qualcosa nei medi.

### Come si suona piano, senza rovinare il file
Il file resta normalizzato a −1 dBFS e **il volume si mette nel motore**
(`volume_db` sull'`AudioStreamPlayer3D`, indicativamente −18/−24 dB per
l'accumulo del Cono, più l'attenuazione con la distanza). Abbassare il file
stesso lo renderebbe inutilizzabile altrove e farebbe perdere risoluzione.

---

## 3. Prompt di riferimento (già provati)

**Schianto del masso — APPROVATO**, `duration_seconds: 4`,
`prompt_influence: 0.7`:
```
Gigantic rock slab slams into the ground. Enormous weight landing: shattering
stone crack and splintering rock debris exploding outward, massive
body-hitting-earth thud, deep ground-shaking rumble underneath, scattered stones
tumbling and settling. Brutal, heavy, extremely intense. Dark fantasy boss
combat, no music, no voice.
```
⚠️ **Cosa ha fatto la differenza rispetto alla versione bocciata:** non una
taratura, ma **cambiare l'oggetto**. Da «un enorme martello da guerra colpisce un
pavimento di pietra» a «una lastra di roccia gigantesca si abbatte al suolo». Il
modello sa che un masso pesa dieci volte un martello; gli aggettivi («potente»,
«intenso») spostano poco, **il sostantivo sposta tutto**.

**Fresatrice di Pyrrath — APPROVATO** (nato come tentativo di ronzio arcano),
`duration_seconds: 6`, `loop: true`, `prompt_influence: 0.75`:
```
Heavy electrical transformer humming loudly at close range. Thick mains hum with
rich harmonic overtones, industrial motor drone, resonant metallic body, warm
buzzing midrange presence, steady and powerful. No deep sub bass, no high hiss,
no crackle. Seamless continuous loop, no music, no voice.
```

**Accumulo del Cono — APPROVATO** (era il ronzio bocciato: troppo cupo per una
carica distruttiva, giusto per un accumulo calmo), `duration_seconds: 6`,
`loop: true`, `prompt_influence: 0.6`:
```
Arcane energy charging up: a deep electrical generator hum that rises in pitch,
layered harmonic drone singing at a stable frequency, transformer buzz with
subtle metallic shimmer, ominous power building. Seamless continuous loop,
no impact, no music, no voice.
```

**Carica arcana aggressiva — APPROVATA** (`magia/carica_arcana_1.wav`),
`duration_seconds: 4`, `prompt_influence: 0.7`:
```
Violent magical energy charging to critical. Rising screaming whine layered over
a thick roaring drone, electric arcs snapping and crackling, ringing harmonics
climbing in pitch, unstable pressure swelling toward release. Loud, aggressive,
full-bodied midrange presence. Dark fantasy boss spell charge, no music, no voice.
```

**Carica spettrale di Verath — APPROVATA** (`magia/verath_spettrale_1.wav`),
stessa idea con `prompt_influence: 0.65`:
```
Massive arcane power surging and building. Searing swelling energy roar with a
rising tonal core, harsh crackling magical discharge, resonant ringing harmonics
swelling in the midrange, menacing pressure rising toward release. Aggressive,
dangerous, thick and present. Dark fantasy spell charge, no music, no voice.
```

### ⚠️ Come si adatta la carica ai quattro usi
Un solo file serve spada del Senza Nome, fase 2, evocazioni e palla d'energia —
ma non tale e quale. La carica dura 4 s e sale fino al rilascio, quindi:
- **si accorcia dalla TESTA, non dalla coda.** La parte che conta è il culmine,
  ed è in fondo: tagliare la fine toglie proprio il rilascio. Per una carica da
  1.5 s si prendono gli ultimi 1.5 s e ci si mette un fade-in corto;
- **si allunga** con `mirelo-ai/sfx1.6/extend-audio`, oppure ripetendo un tratto
  centrale in crossfade;
- **il pitch** distingue gli usi senza generare altro: le evocazioni del
  protagonista un po' più in alto e più corte, la palla d'energia secca.

### Le quattro leve del prompt
1. **materiale + gesto**, non emozione («warhammer on stone», non «potente»)
2. **la banda a parole** («deep sub-bass boom» / «bright metallic ring»)
3. **transiente e coda separati** («sharp crack» + «dry cavernous tail»)
4. **le esclusioni**: chiudere sempre con `no music, no voice`

---

## 4. Preparazione dei file — quattro passaggi obbligatori

1. ⚠️ **Via il silenzio iniziale.** Un impatto deve partire sul transiente, o in
   gioco il colpo si sente dopo che lo si è visto. (Lasciare 2 ms, non zero.)
2. **Normalizzare a −1 dBFS.** I modelli escono a picco 0.99–1.00.
3. ⚠️ **MONO.** `AudioStreamPlayer3D` spazializza solo il mono: uno stereo suona
   ma non si posiziona.
4. **WAV 16-bit 44.1 kHz** per gli SFX corti (niente decodifica, loop point
   nell'import). Ogg per musica e ambienze.
   `ffmpeg -i in.mp3 -ac 1 -ar 44100 -c:a pcm_s16le out.wav`

**Loop:** il flag `loop: true` di ElevenLabs **funziona** — giuntura verificata
pulita, nessun crossfade necessario. ⚠️ E si misura guardando il SALTO fra ultimo
e primo campione rapportato al salto tipico interno, non confrontando le finestre
di testa e coda (su contenuto rumoroso quel confronto dice sempre "diverse" anche
quando il loop è perfetto — ci sono cascato).

**Varianti:** minimo 3-4 per ogni suono ricorrente, scelte a caso e con pitch
random ±10-15%. Un colpo identico si riconosce alla terza volta.

---

## 5. Dove si cablano

- Libreria: `audio/SoundFX/<categoria>/<nome>_N.wav` (convenzione già in uso).
- Bus: `audio/default_bus_layout.tres` — oggi `Master`, `Echo` (delay+reverb),
  `Music`. ⚠️ **Manca un bus `SFX`**: senza, il giocatore non può abbassare gli
  effetti separatamente dalla musica. Da aggiungere.
- Sistema: `audio/SoundFXSystem.gd`, più i due pattern del template (nodo che
  suona su segnale, e traccia di animazione che accende `playing`).
- ⚠️ **Il suono va sull'istante di CONTATTO, non sulla partenza dell'animazione**
  — lo stesso numero che usa il danno (`contact_times`). Un whoosh che parte col
  wind-up arriva presto e toglie peso al colpo.

---

## 6. Ordine di lavoro

1. Una prova **per famiglia**, non venti file.
2. Misurarla (bande, attacco, picco, giuntura).
3. Mandarla all'utente e **aspettare il giudizio**: le misure escludono i suoni
   del tipo sbagliato, non promuovono quelli belli.
4. Solo sulla famiglia approvata: varianti, preparazione, import, cablaggio.
5. ⚠️ **Verificare in gioco, non in cartella.** Vale la stessa regola della
   grafica: un suono giusto da solo può sparire nel mix o coprire tutto.
