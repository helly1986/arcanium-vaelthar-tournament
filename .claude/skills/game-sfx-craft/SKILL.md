---
name: game-sfx-craft
description: "Mestiere del suono per videogiochi: generare SFX con l'IA (fal.ai — ElevenLabs Sound Effects, Stable Audio, Sonilo), scrivere prompt che danno boati invece di fruscii, verificare OGGETTIVAMENTE un suono senza poterlo ascoltare, prepararlo per il motore (loop, transiente, headroom, varianti) e cablarlo in Godot/Unity. Usa questa skill ogni volta che si parla di suoni, SFX, foley, boati, impatti, fendenti, ronzii, riverberi, musica di gioco, audio bus, o quando il gioco 'suona di template' — anche se la richiesta è in italiano e non nomina fal.ai. Contiene misure vere, non teoria."
---

# Mestiere del suono per videogiochi

Questa non è una guida al sound design: quelle esistono e parlano di compressori.
Questo è il **taccuino delle misure** — cosa ho generato davvero, con quali
prompt, e cosa hanno detto i numeri quando l'ho confrontato.

Il valore sta quasi tutto in un punto:

> **Un agente non può ascoltare. Ma può MISURARE — e le misure giuste
> distinguono un boato da un fruscio prima che l'utente sprechi tempo ad
> ascoltare venti file sbagliati.**

⚠️ **E il corollario che non va mai dimenticato: le misure non dicono se un
suono è BELLO.** Dicono se è del tipo giusto. Il giudizio finale è sempre
dell'utente, e va chiesto esplicitamente mandandogli i file.

---

## 1. Quale modello, e perché — MISURATO

Su fal.ai ci sono modelli text-to-SFX dedicati, non solo musica. Cercali con
`search_models` (query "sound effects"), non a memoria: il catalogo cambia.

### La prova che conta

Stesso identico prompt (*"Massive stone impact: a huge warhammer slams into a
stone floor. Deep sub-bass boom, sharp rock crack on the transient, chunks of
debris scattering across stone, dry cavernous tail. Dark fantasy game combat
SFX, no music, no voice."*), 3 secondi, due modelli:

| modello | <200 Hz | 200 Hz–2 kHz | >2 kHz | cos'è uscito |
|---|---|---|---|---|
| `fal-ai/elevenlabs/sound-effects/v2` | **90.5%** | 4.4% | 5.1% | un boato vero |
| `sonilo/v1.1/text-to-sound-effects` | 5.0% | 11.8% | **83.3%** | detriti e fruscio |

**Non è una sfumatura: sono due suoni diversi.** Per impatti, schianti, crolli e
tutto ciò che deve pesare, **ElevenLabs Sound Effects è la scelta**, e la
differenza si vede nei numeri prima che nelle orecchie.

⚠️ Non concluderne che Sonilo sia scarso: è un modello diverso, non peggiore, e
su fruscii, passi, stoffa, vento potrebbe vincere lui. **La lezione è che i
modelli SFX interpretano lo stesso prompt in modo radicalmente diverso, quindi
il confronto A/B sul TUO caso d'uso va fatto una volta e poi ci si fida.**

### Scheda dei modelli utili

**`fal-ai/elevenlabs/sound-effects/v2`** — il cavallo di battaglia.
- `duration_seconds` 0.5–22 (se omesso lo decide lui dal prompt)
- `loop: true` → **funziona davvero**, vedi §3
- `prompt_influence` 0–1 (default 0.3). Alzalo a ~0.55–0.6: sotto, si prende
  troppe libertà e ti restituisce il suo suono preferito invece del tuo
- `output_format`: da `mp3_22050_32` a `mp3_44100_192`, e **`pcm_44100` /
  `pcm_48000`**
- **$0.002 al secondo** — un impatto da 3s costa mezzo centesimo. Il costo NON è
  un vincolo di progetto: genera pure venti varianti e scartane diciotto.

**`sonilo/v1.1/text-to-sound-effects`** — esce in `wav` nativo, si dichiara
commercial-use-safe, ~$0.00125 al secondo di calcolo. Campo `audios` (array)
pensato per più campioni per chiamata.

**`fal-ai/stable-audio-3/small/sfx/text-to-audio`** e le sue varianti
`audio-to-audio` / `audio-inpainting` / `audio-outpainting`. ⚠️ **La famiglia
audio-to-audio è il modo giusto di fare le VARIANTI**: dai in pasto il colpo che
ti piace e ne ottieni fratelli, invece di rigenerare da zero e ritrovarti tre
suoni che non stanno insieme.

**`mirelo-ai/sfx1.6/extend-audio`** — allunga una coda esistente. Utile quando un
riverbero è tagliato corto.

**Video → audio** (`fal-ai/hunyuan-video-foley`, `fal-ai/controlfoley`,
`sonilo/v1.1/video-to-sound-effects`): generano foley sincronizzato su un video.
Per un gioco non servono quasi mai — ma se hai già una clip renderizzata di
un'animazione, è una scorciatoia legittima per il foley di quella mossa.

---

## 2. Scrivere il prompt: le quattro cose che cambiano il risultato

Un prompt SFX non è una descrizione poetica. È una **specifica tecnica travestita
da frase.** In ordine di quanto pesano:

1. **Il MATERIALE e il GESTO, non l'emozione.** «un colpo potente e minaccioso»
   non dice niente al modello. «a huge warhammer slams into a stone floor» sì.
   Nomina cosa colpisce cosa.
2. **La BANDA che vuoi, a parole.** «deep sub-bass boom» / «bright metallic
   ring» / «dry mid-range thud». È la leva più diretta che hai sulla tabella
   qui sopra: il modello risponde a queste parole.
3. **Il TRANSIENTE e la CODA, separati.** «sharp crack on the transient» +
   «dry cavernous tail». Sono le due metà di un impatto e il modello le tratta
   come cose distinte. Se non dici nulla sulla coda, te la inventa lunga.
4. **Le ESCLUSIONI.** Chiudi sempre con `no music, no voice`. I modelli SFX
   scivolano su musica o versi umani con una facilità imbarazzante, e un ringhio
   umano dentro il tuo schianto lo rende inutilizzabile.

Aggiungi il **contesto di genere** (`dark fantasy game combat SFX`,
`sci-fi UI`, `cozy farming game`): sposta il timbro in modo utile.

### ⚠️ Nomina l'OGGETTO GIUSTO, non un oggetto qualsiasi che fa quel rumore

La correzione che ha sbloccato l'impatto pesante non è stata una taratura: è
stato cambiare **cosa** colpisce. Da *"a huge warhammer slams into a stone
floor"* a *"an enormous multi-ton boulder crashes down onto packed earth from a
great height"*. Il modello conosce la differenza fra un martello e un masso, e
il secondo pesa dieci volte tanto — perché è un oggetto diverso, non perché
gliel'ho chiesto più forte. Aggettivi come «potente» e «intenso» spostano poco;
**cambiare il sostantivo sposta tutto.**

Utile anche dire da dove arriva (`from a great height`) e quanto vicino sei
(`recorded close up`, `at close range`).

### ⚠️ Il modello capisce le IMMAGINI, non i numeri

Serviva un lamento continuo più fitto. Ho scritto `quick succession about three
per second`: sono usciti **1–2 respiri al secondo**. Ho riscritto la stessa cosa
come **immagine** — `like a dog breathing fast but human` — e sono diventati
**6 al secondo**.

| formulazione | risultato misurato |
|---|---|
| «about three per second» | 1–2 respiri/sec |
| «like a dog breathing fast but human» | **6 respiri/sec** |

Vale in generale: questi modelli non contano e non misurano. Un numero dentro al
prompt è quasi decorativo; un **paragone con una cosa che esiste** sposta il
risultato di parecchio. Stessa famiglia della lezione sul sostantivo: descrivi
un OGGETTO o un COMPORTAMENTO reale, non una quantità.

⚠️ E il ritmo è misurabile, quindi non serve fidarsi dell'orecchio per sapere se
la richiesta è passata:
```python
h = int(sr*0.02)
env = np.array([np.sqrt(np.mean(a[i:i+h]**2)) for i in range(0, len(a)-h, h)])
s = env > np.mean(env)
eventi_al_secondo = np.sum(s[1:] & ~s[:-1]) / (len(a)/sr)
```

### ⚠️ LA SPAZZATA È ARIA. L'arma si riconosce dal COLPO.

L'errore mi è stato corretto dall'utente e vale per qualunque gioco d'azione.

Avevo generato sei fendenti descrivendo l'ARMA: «wooden shaft creaking» per la
lancia, «blunt iron weight, leather grip» per la mazza. Sono usciti sei suoni
diversi fra loro e tutti sbagliati, perché:

> **Una lancia e una mazza, mentre attraversano l'aria, fanno lo stesso rumore:
> ferro contro aria.** Il legno che scricchiola e il peso sordo si sentono
> all'IMPATTO, che è un altro suono, in un altro momento.

La conseguenza pratica cambia il modo di lavorare:
- **Un solo fendente base**, buono, e tutta la famiglia si ricava da lui
  cambiando **velocità e gravità** — arma più grossa = più lenta e più grave.
  Il ricampionamento fa le due cose insieme, ed è fisicamente corretto;
- **la personalità dell'arma si compra sui COLPI**, ed è lì che vanno spesi i
  soldi e le generazioni.

### ⚠️ …ma TAGLIARE l'aria e SPOSTARLA sono due suoni diversi

Corollario, e seconda correzione dell'utente: derivare tutto da una lama
funziona per lame e lance, **non per le mazze**. «Poco ferro e troppa aria»: una
testa di maglio è molto più grande di una lama e non fende l'aria, la **spinge**.

Sono due fisiche diverse, e si sentono:

| | <200 Hz | 200 Hz–2 kHz | >2 kHz |
|---|---|---|---|
| maglio derivato da una lama (bocciato) | 6% | 21% | **73%** |
| maglio generato come spostamento d'aria | 21% | **54%** | 24% |

Le parole che fanno la differenza nel prompt: **`displacement, not cutting`**,
`shoves a large volume of air out of its way`, `deep broad full-bodied whoosh`,
e l'esclusione esplicita di `no thin whistle, no metallic hiss, no ring`.

**La regola completa:** un fendente base per ogni MODO di attraversare l'aria
(fendere / spostare), non per ogni arma. Due bastano per un intero arsenale.

Misurato, i sei fendenti derivati da un solo campione approvato: tutti al 6-7%
sotto i 200 Hz e al 73-79% sopra i 2 kHz — cioè la stessa identità — e diversi
solo in durata, da 0.79 s a 2.02 s. È il risultato giusto: **si riconoscono come
la stessa mano che impugna armi diverse.**

### Firme sonore: costruirle, non chiederle al modello

Quando una FAMIGLIA di creature deve avere un tratto sonoro riconoscibile
(«sono i portatori dell'eco»), non si mette nel prompt: si genera una base
pulita — chiedendo esplicitamente `recorded dry and close, no reverb, no echo` —
e il tratto si **costruisce in post**, uguale per tutte. Così è davvero una
firma, e non la reinterpretazione che il modello dà a ogni generazione.

Tre modi di rendere un'eco **innaturale** (usati su una voce umana per farne una
creatura):
1. **che scende** — ogni ripetizione più grave e più sorda della precedente;
2. **che non decade** — si trascina invece di spegnersi, come non fa nessuna
   stanza reale;
3. **che PRECEDE** — una copia rovesciata prima della voce. È impossibile, e
   proprio per questo si sente come sbagliata: la creatura si annuncia un
   istante prima di esistere.

⚠️ E l'eco va **passata a passa-basso** a ogni ripetizione: senza, non è
un'eco, sono due voci sovrapposte.

#### I PROFILI si scelgono per FUNZIONE, non per creatura

È la parte che rende una firma utilizzabile su un bestiario intero invece che su
un nemico. Lo stesso trattamento, tre dosi, scelte in base a **cosa deve fare il
suono**:

| profilo | quando | com'è fatto |
|---|---|---|
| **annuncio** | la creatura si fa notare | molti livelli che scendono + l'eco che PRECEDE |
| **richiamo** | minaccia che dura (ringhio, ululato) | 4 livelli, nessun preavviso |
| **reazione** | morso, colpo subito | **2 sole** ripetizioni, nessun preavviso |

⚠️ **Sulla reazione l'eco che precede è VIETATA.** Un colpo va sentito quando
arriva; un'eco che lo anticipa lo trasforma in un annuncio, cioè in un'altra
informazione di gioco. È il caso in cui l'effetto più bello è quello sbagliato.

#### ⚠️ La forza si dosa per SPECIE, ed è una scelta di racconto

Su una famiglia larga non tutti hanno la firma allo stesso grado. Nel caso vero:
i portatori dell'eco a forza **1.0**, gli animali *contagiati* a **0.60-0.70**.
Non è una sfumatura estetica — a forza piena il ringhio del lupo spariva dietro
l'eco e tornava a sembrare **una macchina**, che era esattamente il difetto per
cui quel suono era stato rifatto. Una firma troppo forte mangia l'identità di
ciò che marchia.

#### La funzione, da copiare

```python
PROFILI = {
 "annuncio": dict(strati=[(200,0.62,0.94,3800),(470,0.52,0.88,3300),(810,0.42,0.82,2800),
                          (1220,0.32,0.76,2300),(1700,0.22,0.70,1800),(2250,0.14,0.64,1400)],
                  pre=0.35, coda_s=3.0),
 "richiamo": dict(strati=[(240,0.50,0.93,3600),(560,0.40,0.86,3000),(960,0.30,0.79,2400),
                          (1450,0.20,0.72,1900)], pre=0.0, coda_s=2.2),
 "reazione": dict(strati=[(120,0.55,0.92,3600),(290,0.34,0.84,2600)], pre=0.0, coda_s=0.7),
}
# ogni strato = (ritardo_ms, guadagno, fattore_di_tono, taglio_passabasso_Hz)
# `pre` = quanto forte l'eco che PRECEDE (copia rovesciata, tono 0.9)

def tono(a, f):            # <1 = piu' grave e piu' lungo (ricampionamento)
    n = int(len(a)/f)
    return np.interp(np.linspace(0, len(a)-1, n), np.arange(len(a)), a).astype(np.float32)

def passabasso(a, sr, fc):  # un polo, in frequenza: basta e avanza per un'eco
    n = len(a); S = np.fft.rfft(a); f = np.fft.rfftfreq(n, 1/sr)
    return np.fft.irfft(S/(1.0 + (f/fc)**2), n).astype(np.float32)

def firma(base, sr, profilo, forza=1.0):
    p = PROFILI[profilo]; base = norm(base)
    off0 = int(sr*0.30) if p["pre"] > 0 else 0     # spazio per l'eco che precede
    t = np.zeros(len(base) + int(sr*p["coda_s"]) + off0, dtype=np.float32)
    def somma(x, o, g):
        o = max(o, 0); k = min(len(x), len(t)-o)
        if k > 0: t[o:o+k] += x[:k]*g
    if p["pre"] > 0:
        somma(passabasso(tono(base[::-1].copy(), 0.9), sr, 2200), 0, p["pre"]*forza)
    somma(base, off0, 1.0)
    for ms, g, tn, fc in p["strati"]:
        somma(passabasso(tono(base, tn), sr, fc), off0 + int(sr*ms/1000.0), g*forza)
    return t     # poi normalizza e chiudi col fade (§4)
```

### Scoperte per caso, che vale la pena tenere

Chiedere a un ronzio elettrico di stare **nei medi**, escludendo esplicitamente
sub e sibilo (`no deep sub bass, no high hiss, no crackle`), non ha dato un
generatore: ha dato una **fresatrice che lavora l'acciaio caldo**. Suono
inutilizzabile per lo scopo originale e perfetto per un'officina.
**Le generazioni "sbagliate" vanno riascoltate con l'orecchio di un altro
contesto prima di buttarle** — costano mezzo centesimo e a volte risolvono un
problema di cui non ti eri ancora occupato.

### Ricette che hanno prodotto il suono giusto

- **Schianto a terra (soulslike)** — vedi il prompt in §1. Risultato: 90% sotto
  i 200 Hz, attacco 80 ms.
- **Carica arcana / ronzio "che canta"** — *"Arcane energy charging up: a deep
  electrical generator hum that rises in pitch, layered harmonic drone singing at
  a stable frequency, transformer buzz with subtle metallic shimmer, ominous
  power building. Seamless continuous loop, no impact, no music, no voice."*
  ⚠️ Uscito 93% sotto i 200 Hz e solo 5.7% nei medi: **troppo sub, poco
  "elettrico"**. Per far cantare un generatore servono le ARMONICHE nei medi —
  insisti con `harmonic overtones`, `whine`, `resonant metallic ring`,
  `high-pitched electrical whine layered over the hum`, e togli `deep`.
  È il difetto tipico: i modelli, se chiedi "potenza", ti danno sub.

---

## 3. Loop: quello che si dice in giro è sbagliato

**`loop: true` di ElevenLabs funziona.** Verificato: giuntura pulita, nessun
click. Non serve crossfaddare a mano se hai usato quel flag.

### ⚠️ Come si misura un click di loop — e come NON si misura

Ci sono cascato e va scritto, perché la metrica sbagliata è quella che viene in
mente per prima.

**SBAGLIATO:** confrontare gli ultimi 50 ms con i primi 50 ms campione per
campione. Su contenuto rumoroso (un ronzio, del vento, un fuoco) due finestre
diverse non si somigliano MAI, nemmeno in un loop perfetto: sono rumore. La
misura dà ~140% e sembra un disastro anche quando è tutto a posto. Con questa
metrica avevo concluso che `loop:true` non funzionava. **Falso.**

**GIUSTO:** il click è una **discontinuità**, quindi si guarda il salto fra
l'ultimo campione e il primo, rapportato al salto TIPICO fra campioni adiacenti
dentro al file:

```python
d = np.abs(np.diff(x))
rapporto = abs(x[0] - x[-1]) / np.percentile(d, 99)
# rapporto > 1  -> la giuntura e' piu' brusca del contenuto normale = CLICK
```

Misure vere sul ronzio: `loop:true` grezzo → **0.61 (ok)**; dopo un crossfade
circolare da 0.75 s → 0.23. Il crossfade migliora ma **non era necessario**.

### Crossfade circolare (quando serve davvero)

Se un file non nasce come loop, si toglie la coda e la si risuona sopra la testa
in dissolvenza. ⚠️ **Il file si accorcia della lunghezza del crossfade**, e su un
suono corto è un prezzo che si nota.

```python
xf = int(sr * 0.75)
body = a[:-xf].copy()
r = np.linspace(0, 1, xf)
body[:xf] = body[:xf] * r + a[-xf:] * (1 - r)
```

---

## 3bis. ⚠️ IL PICCO NON È IL VOLUME — la trappola più costosa

Due file normalizzati **allo stesso identico picco** possono suonare uno molto
più basso dell'altro. Misurato:

| | picco | RMS | volume percepito (pesato A) |
|---|---|---|---|
| schianto (58% sotto 200 Hz) | 0.891 | 0.199 | **−36.1 dB** |
| ronzio (93% sotto 200 Hz) | 0.891 | **0.233** | **−36.1 dB**… |

…e all'ascolto il ronzio suonava **nettamente più basso**, pur avendo *più*
energia grezza. Non è un'impressione: l'orecchio è quasi sordo sotto i 100 Hz
(la curva A toglie ~35 dB a 40 Hz). **L'energia messa dove non si sente non si
sente.**

### La conseguenza pratica, che vale più della misura

> **Se un suono è troppo basso e sta tutto in bassa frequenza, NON alzare il
> guadagno: aggiungi i MEDI.** Alzare il volume porta solo il picco a clippare
> lasciando il suono debole com'era.

⚠️ E spesso «suona basso» e «non suona come deve» sono **lo stesso difetto con
due nomi**. Il ronzio del generatore era insieme troppo basso e poco
"elettrico": mancavano i medi, e sistemare quelli ha risolto tutte e due.

```python
def aweight(f):
    f = np.maximum(f, 1e-6); f2 = f*f
    return (12194.0**2)*(f2**2) / ((f2+20.6**2) *
            np.sqrt((f2+107.7**2)*(f2+737.9**2)) * (f2+12194.0**2))
# volume percepito = RMS dello spettro moltiplicato per aweight(f)
```

⚠️ **Le percentuali di banda sono confrontabili solo se misurate allo stesso
modo.** Lo stesso file mi ha dato 90.5% sotto i 200 Hz con una finestra di
Hanning e 58.4% senza. Non è un errore di nessuna delle due: è che il numero
assoluto non vuol dire niente. **Confronta sempre file misurati con lo stesso
script, e normalizzati allo stesso picco.**

---

## 3ter. Stratificare: come si fanno davvero gli impatti grossi

Una sola generazione quasi mai dà il peso di un impatto AAA. I professionisti
sovrappongono strati, e con un modello SFX si può fare uguale: **due o tre
generazioni con prompt diversi, mixate.**

Ricetta per un impatto pesante:
- **corpo** — prompt che chiede il sub e la massa («colossal deep sub-bass boom»)
- **craccata** — prompt che chiede il transiente e i detriti («shattering stone
  crack, splintering debris exploding outward»)
- opzionale: **coda** — il rimbombo lungo

⚠️ **Gli strati vanno allineati sul PICCO, non sull'inizio.** Sono due
registrazioni dello stesso evento: se i loro transienti non coincidono si
sentono due colpi invece di uno. Trova il massimo dell'inviluppo di ciascuno e
sfasali di conseguenza.

```python
def pk(x, sr):
    h = sr//200
    env = [np.sqrt(np.mean(x[i:i+h]**2)) for i in range(0, len(x)-h, h)]
    return int(np.argmax(env))*h
offset = pk(A, sr) - pk(B, sr)     # poi somma B spostato di offset
```

### ⚠️ Non si può mixare una banda che non c'è in nessuno strato

Ci ho sbattuto: avevo un ronzio al 93% sotto i 200 Hz e uno al 97% sopra i
2 kHz, e li ho sommati sperando nei medi. Qualunque peso provassi usciva un
**"sorriso" con un buco in mezzo** — sub e sibilo, niente corpo. Nessuna
proporzione può creare energia dove nessuno dei due ne ha.

Se manca una banda, **serve una terza generazione che viva lì**, con un prompt
che la chieda e che ESCLUDA le altre due (`no deep sub bass, no high hiss`).

---

## 4. Preparare il file per il motore

Quattro passaggi, e saltarne uno si sente in gioco.

### ① Via il silenzio iniziale — il più importante

⚠️ **Un impatto DEVE partire sul transiente.** I modelli mettono spesso qualche
decina di ms di aria prima del colpo, e in gioco quel ritardo si legge come
"il suono arriva dopo che ho visto il colpo" — che è precisamente il difetto che
fa sembrare un combattimento molle.

```python
thr = np.max(np.abs(a)) * 0.02
i = int(np.argmax(np.abs(a) > thr))
a = a[max(0, i - int(sr*0.002)):]   # 2 ms di respiro, non zero: evita il click d'inizio
```

⚠️ **E questa soglia automatica NON basta: va controllato dove cade il PICCO.**
Ci sono cascato su uno schiocco di ghiaccio. Il file non aveva silenzio davanti —
aveva **0.94 s di scricchiolio quasi impercettibile** prima dello schiocco vero.
Sopra la soglia del 2%, quindi il taglio automatico non toccava niente, e il file
sembrava perfetto ascoltato da solo. In gioco avrebbe voluto dire lanciare la
magia e non sentire nulla per quasi un secondo.

```python
h = int(sr*0.01)
env = [np.sqrt(np.mean(a[i:i+h]**2)) for i in range(0, len(a)-h, h)]
ritardo = int(np.argmax(env)) * 0.01     # a che secondo arriva il momento vero
```
**Se `ritardo` supera ~120 ms su un suono che deve colpire, il file va stretto a
mano**, lasciando giusto un pelo di attacco prima del picco.

⚠️ **La soglia vale solo per ciò che COLPISCE.** Su un fendente (un whoosh che
sale mentre la lama passa) il picco a 140-170 ms è giusto — è la lama che
transita, non un ritardo. Stesso discorso per un ruggito o un ringhio, che
salgono. Applicare la regola a tutto vuol dire troncare l'attacco proprio ai
suoni che vivono di quello. È anche un difetto
sistematico dei modelli: se chiedi 2 secondi ti riempiono 2 secondi, e l'evento
interessante finisce spesso a metà o in fondo invece che all'inizio.

⚠️ Corollario: **chiedi durate CORTE.** Un impatto va chiesto a 1–2 s, non a 4:
più spazio gli dai, più roba ci mette prima e dopo il momento che ti serve.

### ①bis Il fade-out finale — chiedilo, e comunque controllalo

I modelli tagliano spesso **a volume pieno**: il suono finisce di netto invece di
chiudersi. Si sente come un troncamento, ed è uno dei difetti che l'orecchio nota
per primo.

Due mosse, e servono entrambe:
1. **Chiedilo nel prompt** (`gentle fade at the very end`, `trailing off`,
   `fading into silence`). Aiuta, ma non è affidabile.
2. **Verificalo sempre a valle**, con una misura e non a orecchio:

```python
def coda(a, sr, ms=40):
    n = int(sr*ms/1000)
    return np.sqrt(np.mean(a[-n:]**2)) / (np.sqrt(np.mean(a**2)) + 1e-9)
# > ~0.35  ->  finisce a volume pieno: applica un fade
if coda(a, sr) > 0.35:
    fo = min(int(sr*0.12), len(a)//3)
    a[-fo:] *= np.linspace(1, 0, fo)**0.7    # curva, non retta: piu' naturale
```

### ⚠️ MAI un fade cotto dentro un LOOP

Questa è la trappola. Su un loop la dissolvenza non chiude niente: diventa un
**avvallamento che ritorna a ogni giro**, e si sente come un battito regolare.
Misurato su tre loop veri (morsa di gelo, lamento continuo maschile e femminile)
la coda stava a 0.79–0.91, cioè ben oltre la soglia — e su tutti e tre **la cosa
giusta era non fare niente.**

Su un loop la dissolvenza si fa **nel motore**, quando il suono va spento
(`tween` su `volume_db`). Se serve anche una versione a colpo singolo, si
esporta un secondo file col fade cotto e si tengono i due separati.

### ② Headroom

I modelli restituiscono roba a picco **0.99–1.00**: normalizza a **−1 dBFS** per
un SFX singolo, e più basso (−3/−6) se il suono verrà sommato ad altri dieci in
un momento concitato. Il mix si fa nel motore coi bus, non nei file.

### ③ Mono per il 3D posizionale

⚠️ In Godot un `AudioStreamPlayer3D` **spazializza solo il mono**: uno stereo
suona ma non si posiziona bene. Tutti gli SFX del mondo vanno in mono; lo stereo
si tiene per la musica e per l'UI 2D.

### ④ Formato

- **WAV 16-bit** per gli SFX corti: nessun costo di decodifica, e supporta i
  loop point nell'import di Godot.
- **Ogg Vorbis** per musica e ambienze lunghe. ⚠️ Godot legge Ogg Vorbis e MP3 e
  WAV, ma **non AAC/FLAC**: se il modello esce in AAC, converti.
- ffmpeg: `ffmpeg -i in.mp3 -ac 1 -ar 44100 -c:a pcm_s16le out.wav`

---

## 5. Varianti: la regola del "mai lo stesso campione due volte"

**Un colpo che si ripete identico si nota alla terza volta e rovina il
combattimento.** Serve un minimo di **3–4 varianti** per ogni suono ricorrente
(fendenti, passi, impatti), scelte a caso a ogni riproduzione, con anche un
**pitch random ±10-15%** sopra.

Due modi di farle, in ordine di qualità:

1. **`audio-to-audio` a partire dal campione approvato** — i fratelli si
   somigliano, che è quello che vuoi: devono essere lo stesso oggetto colpito
   due volte, non due oggetti diversi.
2. Rigenerare col solo seme diverso — più veloce, ma i risultati divergono e a
   volte non stanno insieme.

### ⚠️ SULLE VOCI, rigenerare è VIETATO: esce un'altra persona

È il caso in cui la regola qui sopra smette di essere una preferenza e diventa un
divieto. Lo stesso identico prompt, rigenerato, non dà la stessa persona che
grugnisce due volte: dà **due persone diverse**. Misurato sull'altezza della
vocalizzazione:

| | tentativo #1 | tentativo #2 |
|---|---|---|
| lamento maschile | 377 Hz | **191 Hz** (un'ottava sotto) |
| lamento femminile | 401 Hz | 281 Hz |

Cinque lamenti così sono cinque personaggi che si alternano addosso allo stesso
protagonista, ed è molto peggio di un lamento solo ripetuto.

**Il modo giusto:** una registrazione approvata, e le varianti si ricavano da
LEI per ricampionamento (che sposta insieme altezza e durata — è il trucco
classico dei passi e dei grugniti):

```python
def variante(a, f):        # f = 0.945 .. 1.055  ->  circa ±5.5%
    n = int(len(a)/f)
    return np.interp(np.linspace(0, len(a)-1, n), np.arange(len(a)), a)
```
Oltre il ±8% la voce comincia a sentirsi "lavorata"; sotto il ±3% la variazione
non si nota e tanto vale non farla.

⚠️ **E controlla il SESSO di ciò che è uscito, non fidarti del prompt.** Un
«lamento femminile continuo» mi è tornato con una fondamentale a 112 Hz, che è
territorio maschile. La misura dell'altezza costa due righe e intercetta il caso
in cui il modello ha ignorato la richiesta.

Convenzione di nomi che regge bene: `<categoria>/<nome>_1.wav`, `_2`, `_3`.

---

## 6. Cablaggio nel motore (Godot)

- **Bus**: almeno `Master` / `Music` / `SFX`, così il giocatore può regolarli
  separatamente. Effetti (riverbero, delay) su un bus dedicato a cui si MANDA,
  non sul Master.
- **Due pattern** che coprono quasi tutto: un nodo che suona **su segnale**
  (`hit_landed`, `died`) e una **traccia di animazione** che accende `playing`
  nel frame esatto. Il secondo è quello giusto per i passi e per i colpi: il
  suono e il fotogramma non possono scollarsi.
- ⚠️ **Suono sull'ATTACCO, non sulla partenza dell'animazione.** Un fendente ha
  un wind-up: se il whoosh parte col wind-up, arriva presto e il colpo sembra
  senza peso. Va sull'istante di contatto, che è lo stesso numero che usa il
  danno.
- **Attenuazione 3D**: `unit_size` e `max_distance` vanno tarati sulla scala
  della camera. In vista isometrica a ~20 m, i default (pensati per la prima
  persona) rendono tutto quasi inudibile.

---

## 7. Come si verifica, in concreto

Lo script che uso, e cosa guardare:

```python
peak = np.max(np.abs(a))
rms  = np.sqrt(np.mean(a**2))
# inviluppo a blocchi di 10 ms -> attacco = da 10% del picco al picco
# bande: <200 Hz / 200-2k / >2k, in % dell'energia totale (FFT)
```

| cosa dice | come si legge |
|---|---|
| **% sotto 200 Hz** | se un impatto non ci arriva almeno al 40-50%, **non è un boato**, per quanto bello sembri il prompt |
| **% sopra 2 kHz** | dominante = fruscio/detriti. Giusto per foglie e stoffa, sbagliato per un crollo |
| **attacco in ms** | <30 ms = secco (colpo). >500 ms = una salita (carica, riverbero) |
| **picco** | ~1.0 = va normalizzato prima di spedirlo nel motore |
| **rapporto di giuntura** | vedi §3. >1 = click |

⚠️ **Poi manda i file all'utente e chiedigli di ascoltare.** Le misure escludono
i suoni del tipo sbagliato; non promuovono quelli belli. Un file può essere
perfetto su tutte e cinque le righe della tabella e suonare di plastica.

---

## 8. Ordine di lavoro consigliato

1. Fai la lista dei suoni che servono, **raggruppati per famiglia** (impatti,
   fendenti, cariche, ambienze, UI). Le famiglie condividono il prompt di base.
2. Genera **una prova per famiglia**, non venti file. Misurala.
3. Mandala all'utente. Aspetta il giudizio.
4. Solo sulla famiglia approvata: genera le varianti (`audio-to-audio`),
   prepara, importa, cabla.
5. ⚠️ **Verifica in gioco, non in cartella.** Un suono giusto da solo può
   sparire nel mix o coprire tutto. Vale la stessa regola della grafica: le
   anteprime mentono.
