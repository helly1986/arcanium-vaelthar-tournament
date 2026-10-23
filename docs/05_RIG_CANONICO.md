# Il rig degli umanoidi — convenzione e pipeline

> Misure verificate su `NephiliteRig` (`lavorazione/blender/senza_nome_nephilite_rig.blend`)
> e sui corpi generati, il 2026-08-07. Ogni numero è misurato, non stimato.

## La regola

**Una sola CONVENZIONE DI OSSA per tutti gli umanoidi; le proporzioni seguono
il corpo.**

Convenzione = i nomi e la gerarchia di `NephiliteRig`, 79 ossa, quella che i
nemici già usano. Ogni personaggio ha il *proprio* rig, con quei nomi e quella
gerarchia, ma con le ossa dove stanno le sue.

### Perché nomi e gerarchia bastano

Le animazioni trasferiscono **rotazioni**, e una rotazione non dipende dalla
lunghezza dell'osso. Due rig con gli stessi nomi e la stessa gerarchia si
scambiano le clip anche se uno è alto il doppio: la differenza di posa di riposo
la assorbe `arcanium/tools/rig_retarget.gd`, verificato a **0.056°** su 10 clip
per 41 ossa.

Quello che scala è solo la traslazione — bacino e root motion — ed è il fattore
`k` che il convertitore già applica.

### Perché NON un'armatura unica identica per tutti

È la strada che avevamo scritto prima, e non regge alla prova dei fatti: un rig
a proporzioni fisse **non entra** in un corpo di proporzioni diverse. Misurato
sul corpo Meshy nuovo: dita, pollici e gomiti restano fuori dalla mesh del ~4.5%
dell'altezza, e nessuna scala uniforme o rotazione lo sistema — il gomito ci va
al posto giusto solo se l'omero è lungo uguale.

Conformare ogni corpo alle proporzioni del Senza Nome era l'alternativa, ma
significa deformare ogni protagonista per farlo entrare in un corpo che non è
il suo: cambia la silhouette, che è l'unica cosa che il lavoro non deve toccare.

### Il prezzo, dichiarato

Proporzioni diverse fra personaggi significa che **i finisher vanno verificati**.
`sword_backstab_victim_01` e il `Backstab` del giocatore sono una coppia
coreografata: braccia di lunghezza diversa afferrano un po' più in là. Non è
fatale — si tara — ma non è gratis, e va controllato ogni volta che entra un
corpo con proporzioni lontane dalla media.

## La specifica di riferimento

Misure normalizzate sull'altezza, così valgono a qualunque scala. Un corpo nuovo
non deve rispettarle al millimetro, ma più se ne allontana più i finisher vanno
ritarati.

| grandezza | riferimento (Nephilite) |
|---|---|
| posa | A-pose, braccia a **47°** sotto l'orizzontale, **palmi in giù** |
| gambe | quasi verticali, 4.3° dalla verticale |
| bacino | 50.3% dell'altezza |
| apertura caviglie | 18.4% |
| apertura mani | 54.4% |
| ampiezza spalle | 18.7% |

⚠️ La scala ASSOLUTA non conta: il Senza Nome è stato riscalato apposta per
essere più grande del giocatore. Contano solo i rapporti.

## La pipeline di un personaggio nuovo

### 1. L'immagine, prima del modello

Il text-to-3D di Meshy **non funziona più bene sui personaggi**: restituisce pose
sbagliate (braccia piegate, palmi in su) che poi vanno raddrizzate a valle.

Si parte da un'**immagine di riferimento** generata con `nano-banana-pro`,
che invece obbedisce alla posa: chiedere esplicitamente A-pose, braccia dritte a
45°, **palmi verso il pavimento**, sfondo grigio piatto, luce uniforme, figura
intera. Due strade, stesso modello:

- **Tripo, pannello Immagine** (standard dal 2026-10-02, deciso dall'utente):
  nella web app (`Spazio di lavoro 3D` → `Immagine`) si sceglie **Nano Banana
  Pro** nel menu del modello, il rapporto (3:4 per un umanoide, 4:3 per un
  quadrupede) e si genera; l'immagine resta nella libreria e passa a `Modello`
  → Smart Mesh senza scaricarla. Con l'abbonamento ci sono generazioni
  gratuite (badge «Free n/100», costo 0). ⚠️ Il pannello si ridisegna a ogni
  scelta: la casella del prompt e il menu si pilotano cliccando per
  coordinate e RIGUARDANDO lo schermo dopo ogni scelta — i clic per
  riferimento sembravano riusciti e lasciavano il modello di default (GPT
  Image 2.5) e la casella vuota.
- **Meshy** (`arcanium/tools/meshy.py illustrazione`, endpoint
  `openapi/v1/text-to-image`): costa crediti Meshy, e prompt e riferimenti si
  approvano prima (memoria `arcanium-mostrare-prima-di-spendere`).

⚠️ Un'immagine generata va guardata anche per le **somiglianze**: il primo
Guardiano Radicato (2026-10-02) era un uomo di corteccia identico a un
personaggio Marvel noto. Si descrive cio' che lo distingue, non solo cio' che e'.

Poi `openapi/v1/image-to-3d` con **`meshy-6`** (non `meshy-5`, più vecchio).
Esiste anche `multi-image-to-3d`: si genera una tavola di rotazione a tre viste,
la si ritaglia e la si passa — utile ma non necessaria, meshy-6 a vista singola
è già buono.

### 2. Sempre nudo, calvo, imberbe

Armatura, capelli e barba sono **strati separati**. La lore lo chiede già:
`LORE/CHARACTERS.md` dice *"Aspetto: libero (personalizzazione)"*. Un accenno di
capelli dipinto nella texture è tollerabile finché la geometria è calva.

### 3. Alleggerire, nell'ordine giusto

1. **Merge by Distance a 0.0001.** Non è opzionale: le mesh Meshy arrivano con i
   vertici spezzati sulle cuciture UV — misurato 213.962 vertici per 119.752
   facce, scesi a 59.878 dopo la saldatura. Decimare prima di saldare non riduce
   i vertici, riduce solo le facce.
2. **⚠️ Subito dopo la saldatura: buttare le NORMALI CUSTOM**
   (`customdata_custom_splitnormals_clear`) e rimettere shade smooth.
   Il GLB di Meshy arriva con normali split per loop; fondendo i vertici delle
   cuciture i loop sopravvissuti restano con normali incoerenti fra loro, e la
   pelle si copre di un **brulichio fine su tutto il corpo**. Sembra un difetto
   della mesh densa e non lo è: la stessa geometria con le normali ricalcolate è
   liscia. Verificato affiancando quattro versioni (vecchia, grezza,
   saldata-con-normali, saldata-e-ripulita) e guardandole — solo la terza brulica.
3. **Decimazione: NON sul protagonista.** Vedi sotto.

#### ⚠️ Correzione del 2026-08-09 — la soglia dei 43.000 triangoli era sbagliata

Qui c'era scritto di decimare a ~43.000 triangoli «in linea col protagonista
attuale». Quel riferimento era `protagonist_fist.glb` — 31.161 triangoli, 24
ossa — cioè il protagonista **vecchio**, che non era l'hero. Applicata al corpo
v4 quella soglia ha buttato via il **64%** dei triangoli (119.752 → 43.000), e
si pagava in cuciture sulle ginocchia, cosce sfaccettate e dita sfrangiate.

Il numero che spiega il danno: fra la mesh densa e quella decimata lo scarto di
**posizione** è di 0,04 mm mediani (massimo 0,20). La decimazione non spostava
la superficie — toglieva risoluzione alla **normale**, ed è la normale che si
vede.

**Per il protagonista e per gli altri hero: nessuna decimazione.** 119.752
triangoli, e Godot genera i LOD da sé (`meshes/generate_lods=true`). La
decimazione resta buona per i personaggi di contorno.

Rifatto con `arcanium/tools/riporta_densita_corpo.py`, che **non ripassa dal
blend ARP**: prende l'armatura già fatta dal GLB che il gioco usa e sostituisce
solo la mesh. Le 61 ossa restano ferme entro 6,7e-07 in traslazione e ~0,0005°
in rotazione, quindi ogni clip esistente continua a cadere giusta e l'`.import`
resta valido. I pesi si trasferiscono dal corpo decimato — che è lo **stesso
personaggio nudo** a meno di 0,2 mm, non il donatore vestito di cui sotto.

⚠️ E la mesh deve chiamarsi **esattamente** `Protagonista`: cancellare
l'oggetto vecchio non basta, il suo datablock sopravvive e Blender battezza il
nuovo `Protagonista.001`. `player_dawnkeep_v4.tscn` sovrascrive il nodo
`protagonist/BaseArmature/GeneralSkeleton/Protagonista` per dargli
`material_override = corpo_mascherato.tres`, cioè la maschera che cancella la
pelle sotto l'armatura: con un altro nome quell'override si perde in silenzio.

### 4. Il rig, con ARP — la sequenza esatta

La mesh arriva **senza rig**, ed è giusto così. ARP piazza le ossa di riferimento
*sul corpo che ha davanti*: risolve il fit per costruzione invece che per
ottimizzazione, e il suo binding (heat map) è molto migliore dell'auto-weight su
ascelle e spalle, che è dove l'auto-weight sbaglia sempre.

**Gli operatori Smart stanno nel namespace `id.`, non `arp.`** — cercarli fra gli
`arp.` non li trova, e sono due ore perse.

```
1. id.get_selected_objects     # mesh selezionata; ARP crea la sua copia body_temp
2. arp.guess_markers           # 18 marker via AI (collo, spalle, gomiti, mani, ginocchia, piedi)
3. arp.guess_fingers           # altri 40: 5 dita x 4 giunti x 2 mani
4. id.go_detect                # costruisce il rig e piazza le ossa di RIFERIMENTO
5. arp.match_to_rig            # ⚠️ PORTA LE OSSA VERE SUI RIFERIMENTI
6. arp.bind_to_rig             # skinning (mesh selezionata, ARMATURA attiva)
```

⚠️⚠️ **Il passo 5 non è opzionale e non è implicito nel 4.** Senza `match_to_rig`
le ossa di riferimento sono giuste ma il rig deformante resta nella posa del
template appena appeso, a un'altra scala e un'altra quota. Il binding "riesce"
lo stesso e sembra a posto — 0 vertici senza peso — ma i pesi sono assurdi: nella
prova la punta della mano è finita pesata su `foot.l`.

**Prerequisiti dello Smart AI:**
- i file AI stanno in `Documents\AutoRigPro\AI\inference`. Il flag
  `scn.arp_smart_AI_is_installed` viene calcolato **una volta sola**, dentro il
  passo 1: se i file arrivano dopo, il flag resta `False` e si riattiva a mano
  con `scn.arp_smart_AI_is_installed = os.path.exists(smart.get_AI_path())`.
- `arp_smart_depth` deve essere `True`, o le dita AI non partono.
- impostare `arp_smart_spine_count`, `arp_smart_neck_count`, `arp_fingers_to_detect`
  **prima** del passo 1.

⚠️⚠️ **`arp_smart_spine_count` CONTA ANCHE LA RADICE.** Per un personaggio che
deve finire sul rig Nephilite il valore giusto è **4**, non 3:

| valore | ossa di spina deformanti che ARP produce |
|---|---|
| 3 | `root.x`, `spine_01.x`, `spine_02.x` — **una in meno del Nephilite** |
| **4** | `root.x`, `spine_01.x`, `spine_02.x`, `spine_03.x` — 1:1 con `Hips` + `Spine_01/02/03` |

Messo a 3 il binding **riesce lo stesso** e non dà nessun allarme: semplicemente
al `Spine_03` del Nephilite non arriva nessun peso, e siccome le clip ruotano
tutte e tre le ossa di spina il busto **sotto-ruota su ogni caricamento** — un
difetto che si vede in animazione e che nei numeri del bind non compare.
È la stessa famiglia dei falsi positivi del §"I due collaudi": il bind riesce
comunque. (Sbagliato una volta il 2026-08-17, sul Fante Sylvorn.)

I valori per un umanoide Nephilite: `spine_count = 4`, `neck_count = 1`,
`fingers_to_detect = 5`, `arp_smart_depth = True`.

⚠️ Nota di contesto MCP: gli operatori Smart di ARP vogliono un'area `VIEW_3D`
vera. Eseguiti dal ponte MCP falliscono con `'NoneType' object has no attribute
'spaces'` oppure `poll() failed` — e **il primo tentativo lascia comunque
`body_temp` in scena e la scena nascosta**. Serve un
`bpy.context.temp_override(window=…, area=…, region=…, space_data=…, screen=…)`
preso dalle finestre aperte. Dopo un fallimento, ricaricare il blend invece di
proseguire sullo stato sporco.

### 4-bis. Il travaso ARP → Nephilite: la mappa delle ossa

ARP rigga bene ma con la **sua** convenzione; le clip vivono su quella
Nephilite. Questa è la corrispondenza, verificata sulle 67 ossa deformanti
prodotte da ARP (lato `.l`, speculare a destra):

| ARP | Nephilite | nota |
|---|---|---|
| `root.x` | `Hips` | |
| `spine_01.x` / `spine_02.x` / `spine_03.x` | `Spine_01` / `Spine_02` / `Spine_03` | serve `spine_count = 4` |
| `neck.x` / `head.x` | `Neck` / `Head` | |
| `shoulder.l` | `Clavicle_L` | |
| `arm_stretch.l` + `c_arm_twist_offset.l` | `Shoulder_L` | **i twist si fondono nel genitore** |
| `forearm_stretch.l` + `forearm_twist.l` | `Elbow_L` | idem |
| `hand.l` | `Hand_L` | |
| `thigh_stretch.l` + `thigh_twist.l` | `UpperLeg_L` | idem |
| `leg_stretch.l` + `leg_twist.l` | `LowerLeg_L` | idem |
| `foot.l` | `Ankle_L` | |
| `toes_01.l` | `Ball_L` | `Toes_L` resta senza peso (è una foglia) |
| `thumb1.l`, `c_thumb2.l`, `c_thumb3.l` | `Thumb_01/02/03_L` | |
| `index1.l`, `c_index2.l`, `c_index3.l` | `IndexFinger_01/02/03_L` | |
| `middle1`, `ring1`, `pinky1` + relativi `c_*2`/`c_*3` | `Finger_01/02/03_L` | **tre dita ARP collassano in una sola catena** |
| `c_index1_base`, `c_middle1_base`, `c_ring1_base`, `c_pinky1_base` | `Hand_L` → dito | **i METACARPI si dividono lungo l'osso**: vedi sotto |

Due asimmetrie strutturali da cui discende tutto il resto:

1. **Il Nephilite non ha ossa di twist né di stretch.** I loro pesi non si
   buttano: si **sommano** al genitore, o l'avambraccio perde metà della sua
   pelle.
2. **Il Nephilite ha una mano a mitten**: pollice + indice + *una* catena
   `Finger_*` per le altre tre dita. Medio, anulare e mignolo di ARP vanno
   fusi in quella. Perdita accettabile — le armi si attaccano a
   `Prop_Attachment_R`, non alle dita.
3. **Il Nephilite non ha ossa del palmo.** I `c_*1_base` di ARP sono i
   metacarpi (dal polso alle nocche). ⚠️ **Correzione del 2026-09-30**: fino ad
   allora finivano nella prima falange, il palmo ruotava con le dita e
   nell'idle (mano chiusa sull'impugnatura) il dorso si gonfiava e pollice e
   indice si staccavano — su *tutti* i corpi montati cosi' (Mago, Fante,
   Soldato Scelto; visto in Cascadeur). Tutti alla mano e' l'errore opposto: il
   mignolo si stirava come un filo. Ora il peso di ogni metacarpo va alla mano
   vicino al polso e sfuma al dito verso la nocca (`_dividi_metacarpi`: dal 40%
   dell'osso per indice e medio, dal 70% e dall'85% per anulare e mignolo).
4. **Il giunto della muffola sta al CENTRO delle tre nocche** (medio, anulare,
   mignolo), non sulla nocca del medio: attorno al medio il mignolo, lontano
   dall'asse, sporgeva dal bordo della mano (`_mappa_giunti`, 2026-09-30).
5. **La mano NON si piega sulla disposizione del Nephilite.** Nel rest del
   Nephilite l'indice diverge dalla muffola di 28° (nel Mago 12°), e le dita
   sono gia' piegate di ~55°. Portando la nostra mano li' con la rotazione
   piu' corta, la cottura girava la muffola con 14° di torsione e apriva
   l'indice di 16° in piu': nell'idle (che per le dita E' il rest) il mignolo
   si alzava, l'indice si staccava dal medio e il pollice si piegava dentro
   (visto dall'utente in Cascadeur il 2026-09-30). Ora, nel puppet:
   - indice e muffola si piegano SOLO attorno alla riga delle nocche
     (`_cardine`), di quanto serve ad arrivare alla piega del Nephilite;
   - il pollice resta com'e' modellato rispetto al palmo (`DITA_COME_MODELLATE`);
   - `allinea_mano` porta le TESTE delle ossa della mano sulle nostre
     articolazioni, o ogni falange non combacia con la successiva e le dita
     vengono a salsicciotto. Le rotazioni di rest restano quelle del
     Nephilite (le clip vedono solo quelle), e gli attacchi delle armi non si
     muovono.

Un'osso Nephilite intermedio lasciato senza peso **non è un buco**: essendo una
catena, la sua rotazione arriva comunque alla pelle attraverso i figli. Quello
che si perde è solo la sfumatura del blend a quel livello.

**Se ARP non risulta installato dopo un riavvio**: l'addon è su disco in
`extensions/superhivemarket_com/auto_rig_pro` ma il repository può sparire dalle
preferenze. Si ri-registra con `bpy.ops.preferences.extension_repo_add(...)`,
poi `addon_utils.enable(...)` e `bpy.ops.wm.save_userpref()`.

⚠️ Non usare `SenzaNomeMesh` né `ConsumatoMeshFixed` come donatori di pesi: sono
figure **vestite e incappucciate**. Un trasferimento per vicinanza dà spalle
pesate sul mantello e testa pesata sul cappuccio. Ci sono già cascato due volte —
ed è il motivo per cui la strada giusta è ARP e non il trasferimento.

### 4-ter. I corpi generati con Tripo P2 — lo standard dal 2026-09-30

Vale per ogni umanoide nuovo o rifatto. È la strada su cui il Mago Sylvorn è
passato da «si strappa dappertutto» a pulito, un difetto alla volta.

**Formati: quad in lavorazione, triangoli in gioco.**

| tratto | formato | perché |
|---|---|---|
| Tripo → Blender | **FBX** (preset Blender, texture 2k) | è l'unico che conserva la topologia P2 così com'è (Mago: 12.227 quad + 4.008 triangoli voluti da Tripo). Il GLB la triangola, e `tris_convert_to_quads` ne ricompone solo una parte, con una topologia diversa |
| sorgente nel repo | **FBX** con texture incorporata, in `<cartella del corpo>/sorgenti/` | la cartella ha un `.gdignore`: versionata, ma Godot non la importa |
| Blender → Godot | **GLB** | la GPU disegna solo triangoli e Godot triangola QUALUNQUE formato all'import (OBJ, FBX, GLB): i quad in gioco non esistono in nessun motore. Il beneficio della topologia pulita (anelli di spigoli, vertici regolari) sopravvive alla triangolazione, perché lo skinning lavora sui vertici. Il GLB è il formato nativo di Godot, e bone map e `.import` del progetto sono costruiti su quello. OBJ non porta scheletro né pesi |
| Blender → Cascadeur | **GLB** (`base_cascadeur.py`) | in Cascadeur la mesh è solo un'anteprima: la clip che torna in gioco è fatta di ossa |

La triangolazione la decidiamo noi: `esporta_glb` triangola in Blender col
metodo **BEAUTY** (diagonale più corta, niente pieghe d'ombra sui quad non
piani) e toglie le facce non valide che Tripo lascia (15 su 28.462 sul Mago).

**La ricetta** (`arcanium/tools/monta_consumato_sylvorn.py`, dentro Blender):

```
prepara("<nome>", altezza=<m>)      # legge sorgenti/<nome>.fbx; niente quad=True sull'FBX
rigga()                             # ARP, guscio per guscio
travasa(affila=False, falde=False, gabbia=True)   # per i corpi di STOFFA
esporta_glb(DIR + "<nome>_rigged.glb")
```

`affila` (pesi a potenza, per le piastre d'acciaio) e `falde` (taglio a metà
vita, per i gonnellini d'armatura) restano `True` solo per i corpi con
armatura. Sulla stoffa strappavano collo e cintura.

**Cosa fa il travaso, in ordine, e perché:**
1. rinomina i pesi ARP → Nephilite (metacarpi divisi, vedi 4-bis);
2. `chiudi_orfani`: anche i vertici col peso **quasi nullo**, non solo quelli
   senza gruppi. Due vertici del mento a 6,6e-05 restavano nell'A-pose al bake
   e diventavano una SPINA davanti alla bocca;
3. bake A-pose → stance, poi `ripara_stirati`: uno spigolo che si allunga più
   di 3 volte è un vertice rimasto indietro. Si ammorbidiscono i pesi lì, lungo
   la mesh, e si ricuoce (Mago: 22 → 8 → 4 → 0; era la cintura pesata sulla
   coscia);
4. `mento_alla_testa`: l'osso `Head` parte dalla nuca, e mento e mandibola
   restavano al collo;
5. `pesi_dalla_gabbia`, **dopo** il bake: gli strati di stoffa (35 gusci sul
   Mago) prendono i pesi da un involucro unico e si muovono insieme. Prima del
   bake, con le braccia aperte, fondeva la manica con l'avambraccio (251
   spigoli stirati);
6. `normalizza_pesi`: somma 1 su ogni vertice.

**I collaudi da guardare nel log**, oltre ai due del §«I due collaudi»:
`COLLAUDO BAKE: nessuno spigolo stirato`, e `ossa nello skin: 79` nel GLB (80
vuol dire che un vertice a peso zero è finito su un `neutral_bone`).

⚠️ **Il bind di ARP NON è deterministico.** Stesso corpo, stessi marker (31:
11 del corpo più 20 delle dita, su un lato solo perché ARP specchia), tre giri
il 2026-09-30: 449, 409 e 389 vertici orfani dopo la rinomina. Il primo giro
aveva colato il peso dell'avambraccio destro sul fianco della veste: 44
spigoli stirati, che le riparazioni facevano SALIRE (44 → 60 → 68 → 60). Gli
altri due si chiudevano a 0 e a 1. Regola: se le riparazioni non portano il
bake a zero, **si rilancia `rigga()`** (16 secondi) invece di insistere sul
travaso. E si salva il blend dopo `rigga()`, per rifare il travaso senza
rifare il rig.

**E poi si GUARDA**: mani a riposo e nell'idle, mento con la testa giù e su,
clip più estreme. Resta un limite: una clip che torce il busto di ~90°
(`sword_th_charged_attack_01`) strappa comunque cintura e mantello di una veste
larga, perché nessun peso regge quella torsione su stoffa a strati. La cura è
la stoffa simulata (4-quater).

### 4-quater. I TESSUTI sono stoffa simulata — lo standard dal 2026-09-30

**Deciso dall'utente il 2026-09-30:** ogni personaggio che ha un tessuto
(veste, mantello, falde, stendardi) lo porta come **stoffa simulata**, non come
pelle legata alle ossa. Si parte dal Mago Sylvorn. Poi viene il **Senza Nome**
del prologo, rifatto con Tripo P2 in quad e con il mantello simulato, e dopo i
**Consumati della Traccia Perduta**, che hanno mantelli di tessuto.

**Lo strumento:** `addons/godot_gpu_cloth` (GPU Cloth Sim 3.0.0,
alien-life/gpu-cloth-sim, MIT). Simulazione PBD in compute shader, gira anche
sul renderer Mobile. Il plugin non va acceso: bastano le classi
`GPUClothSolver` e `GPUClothCollider`. La prova si fa in
`arcanium/levels/stoffa_playground.tscn`.

**La ricetta** (in `monta_consumato_sylvorn.py`, dopo il travaso; il Mago):

```
travasa(affila=False, falde=False, gabbia=True, mani="aperte")
separa_stoffe(bpy.data.objects["FanteSylvorn"])            # -> Stoffa1, Stoffa2
maschera_stoffa(Stoffa1, alto=1.20, basso=0.85, dietro=0.12)
maschera_stoffa(Stoffa2, alto=0.95, basso=0.65, coperture=(Stoffa1, Stoffa2))
esporta_glb(DIR_SYLVORN + "sylvorn_mago_rigged.glb")         # esporta anche le Stoffa*
```

e in gioco basta il nodo `StoffaSimulata` (`arcanium/systems/stoffa_simulata.gd`)
figlio del personaggio. Verifica: `arcanium/tools/verifica_stoffa.tscn` (non
headless); prova e misure: `arcanium/levels/stoffa_playground.tscn`.

**Cosa fa ogni passo, e perché:**
1. **`separa_stoffe`: uno strato per mesh.** Tripo salda tutto il tessuto in
   un guscio (Mago: 5.195 vertici). Gli strati si innestano con giunzioni a T,
   spigoli NON-MANIFOLD: tagliando lì escono gli strati veri (`Stoffa1`
   sopra: cappuccio, pettorale, maniche, mantello; `Stoffa2` sotto: veste e
   falde). I pezzi si cercano collegati anche per un solo vertice (per soli
   spigoli si spezzettavano), il tessuto è il guscio più INGOMBRANTE (non
   quello con più facce: la testa ne ha di più), e i frammenti vanno allo
   strato più vicino (lasciati al corpo restavano fermi dentro la stoffa).
   ⚠️ **Non si divide per colore della texture**: Tripo dipinge un colore
   anche sul guscio dell'altro, e la divisione esce a coriandoli.
2. **`maschera_stoffa`: il canale R di `cloth_weight`** (0 segue le ossa, 1
   libero), per altezza, con le braccia ferme (le maniche). `dietro`: libero
   solo il mantello, il pettorale che scende sulla cintura no.
3. **`coperture`: lo strato COPERTO resta sulle ossa.** Dove due strati sono
   saldati nello stesso pezzo (falde verdi e veste bianca, unite agli orli:
   niente giunzioni da tagliare, e nemmeno spigoli ripiegati) liberi si
   attraversano, peggio dello skinning. Un raggio orizzontale dall'asse del
   corpo dice cosa sta SOTTO un'altra stoffa entro 8 cm: non si vede, e si
   tiene fermo.
4. **In gioco** ogni stoffa ha il suo `GPUClothSolver`, le stoffe si nominano
   come peer (collidono fra loro), capsule su cosce, stinchi e PIEDI.

**Sui campioni** (dal 2026-10-23, Edran per primo): il guscio e la maschera
di ogni campione stanno in `STOFFE` di `arcanium/tools/monta_campione.py`, e
`riesporta_con_stoffa(nome)` riesporta il GLB dal `.blend` del montaggio (le
ossa non cambiano). In gioco il nodo `StoffaSimulata` lo crea `CorpoCampione`
quando veste il giocatore (o il rivale del battleground), con lo scheletro
del campione.

**Regolazione (default di `StoffaSimulata`):** 2 passi x 4 iterazioni,
`max_travel_distance` 0,06, `stiffness 0.8`, `bend_stiffness 0.15`, `damping
0.98`. ⚠️ Con 1 passo e 0,15 di viaggio, nel passo lungo la veste restava
indietro, la gamba la scavalcava e lo stivale bucava l'orlo: le capsule non
bastano se la stoffa è lontana dalla posa. Il collisore dalla sagoma del corpo
(`body_collider_voxel_resolution`) costava ~3 ms a personaggio e non lo
toglieva.

**Costo misurato** (Radeon 890M, Mobile, 8 maghi): 1,8 ms senza stoffa; mesh
intera nel solver 22,8 ms a 4x6, 7,3 a 1x4; solo le stoffe 5,15 a 1x4 e 7,95
a 2x4. Pesano i **dispatch** (gruppi di vincoli x passi x iterazioni), non le
particelle. Per questo `StoffaSimulata` accende la stoffa solo entro 25 m dal
GIOCATORE: fuori la mesh torna skinning (`gpu_driven = false`) e il solver si
ferma; riaccendendo, warm start e inerzia azzerata. ⚠️ Non dalla camera: quella
isometrica sta a ~29 m dal giocatore, e con 22 m dalla camera la stoffa in
partita non si accendeva mai (lo ha colto `verifica_mago_in_campo`).

**In Kalvorn** (`arcanium/tools/bench_stoffa_kalvorn.tscn`, il Mago della
conca col giocatore a 10 m, albero NON in pausa: in pausa la stoffa non
simula): la stoffa costa 1,6-2,6 ms a 2x4 passi (da ~113 a ~95 fps) e ~0,6 ms
a 1x4. Più che nel playground, perché lì il frame è leggero.

**L'addon ha una patch nostra** (segnata `ARCANIUM` in `gpu_cloth_solver.gd`):
alla distruzione libera uniform set, pipeline e shader prima dei buffer, e
stacca il materiale dalle texture della simulazione. Senza, ogni personaggio
con la stoffa che spariva stampava una raffica di "Attempted to free invalid
ID". Se si aggiorna l'addon, va rifatta.

**Cosa resta** (Mago, 2026-09-30): il mantello è bello; nella veste qualche
scheggia verde/bianca dove falde e veste si sfiorano, e nel passo lungo si
intravede il calzone dall'apertura della veste anche col solo skinning (è dei
pesi: le due metà bianche seguono ognuna la sua gamba).

### 5. In Godot

Import con una bone map, che rinomina le ossa sul profilo Humanoid.

⚠️ **Correzione del 2026-08-08 — la regola "mai `rest_fixer`" era sbagliata.**
Valeva per i rig dei nemici; per il **corpo del giocatore** il `rest_fixer` va
**acceso**. Verificato: `assets/characters/protagonist_fist.glb.import`, il
modello che il gioco usa da sempre, ha `fix_silhouette/enable = true`. Senza di
quello le clip condivise piegano i **gomiti al rovescio** — visto e fotografato
sul protagonista v4, che con il fixer spento teneva le braccia ripiegate dietro
le spalle.

⚠️ Per i rig generati con ARP la bone map è una **mappa identità**:
`arp_rename_for_godot` produce già i nomi del profilo Humanoid, gli stessi che
`%GeneralSkeleton` usa nelle scene. La mappa serve comunque, perché è lei a far
battezzare lo scheletro `GeneralSkeleton` — il nome su cui puntano tutti i
NodePath. Vedi `assets/characters/base_body/protagonista_v4.glb.import`.
La mappa `arcanium/resources/rigs/nephilite_humanoid.tres` resta quella dei rig
che arrivano **con i nomi Nephilite** (nemici, Senza Nome).

### 5-bis. IK sui piedi — FATTO

`arcanium/systems/ik_piedi.gd`, un `SkeletonModifier3D` appeso come figlio
diretto del `GeneralSkeleton` nella scena del player.

Serviva perche' le clip sono state fatte su un corpo con gambe **6,4 cm piu'
corte**: misurato in gioco al Crocevia sulla posa d'attesa, le caviglie stavano
a **15,3 e 14,9 cm** da terra contro i 12,3 del rest, e sotto la suola sinistra
si vedeva l'ombra. Col modificatore acceso la suola arriva sul lastricato.

La distanza suola→caviglia si LEGGE dal rest (`get_bone_global_rest`), non si
scrive: il corpo femminile e i nemici non avranno bisogno di un altro numero.

**⚠️ Non c'e' una lista di animazioni su cui spegnere, ed e' deliberato.**
L'`AnimationTree` del player ha otto macchine a stati annidate: una lista di
stati sarebbe sempre incompleta della clip appena aggiunta. Decide la geometria —
ogni piede cerca il terreno solo dentro una finestra stretta attorno a se', e se
il terreno non e' li' dentro quel piede e' in aria **per volonta' dell'animatore**
(salto, rotolata, il calcio del finisher) e non lo si tocca. Restano due
interruttori: `is_on_floor()` del corpo e `influence`, che si sfuma.

**⚠️ Tre trappole pagate:**

1. **I raycast non si tirano dentro `_process_modification_with_delta`**: quella
   funzione gira nell'aggiornamento dello scheletro, non nel passo di fisica. Le
   sonde stanno in `_physics_process` e si mettono in cassa.
2. **`get_bone_global_pose()` da fuori NON dice se l'IK funziona**: restituisce la
   posa dell'ANIMAZIONE, non quella che esce dai modificatori. Misurando cosi'
   l'IK sembrava inerte — 0,154 acceso come spento — mentre chiamando la funzione
   a mano il piede scendeva a 0,120. Sembrava che il motore non chiamasse affatto:
   chiamava, 642 volte. **L'unica prova e' guardare**, e se la correzione e'
   troppo piccola per vederla si esagera il parametro finche' diventa evidente.
3. **Il ginocchio non prende un polo scritto a mano**: si tiene il piano
   anca-ginocchio-piede che la clip ha gia' e si cambia solo l'angolo. Un polo
   fisso fa incrociare le gambe appena il personaggio si muove di lato, e si nota
   molto piu' del piede che fluttua.

Resta aperto: la **punta** del piede non rulla, perche' l'osso `Toes` non e'
pilotato. Su un piano si nota poco, in salita si notera'.

## I due collaudi, obbligatori prima di dichiarare fatto

Nessuno dei due è facoltativo: ognuno ha smascherato un errore che sembrava
riuscito.

**1. Le ossa sono dentro la mesh?** Punto-più-vicino più segno della normale, su
ogni osso deformante. Non a occhio.

```python
ok, loc, nor, _ = mesh.closest_point_on_mesh(testa_osso)
dentro = -(testa_osso - loc).dot(nor)      # > 0 = dentro
```

Valori buoni misurati sul protagonista: 67 ossa deformanti, **0 fuori**, margine
minimo 0.24% dell'altezza.

**2. Un vertice noto è pesato sull'osso giusto?** Prendere il vertice più esterno
del braccio e guardare su cosa pesa: deve uscire la punta del dito medio
(`c_middle3.l` al 99.9%). Se esce `foot.l`, manca `match_to_rig`.

Il collaudo 2 è quello che conta di più: il binding **riesce comunque** e non dà
nessun segnale d'allarme — 0 vertici senza peso, nessun errore — anche quando i
pesi sono completamente sbagliati.

## Regole di verifica, pagate care

- **Guardare l'oggetto, non solo misurarlo.** Tre sonde geometriche diverse
  sull'orientamento dei palmi hanno dato tre risposte, tutte sbagliate; un render
  ortografico dall'alto ha risolto in un colpo.
- **Non dedurre dai nomi.** `char1` in `retarget_senzanome.blend` sembra il
  protagonista ed è il Senza Nome. Aprire e guardare.
- **Confrontare coppia per coppia, non un numero aggregato.** L'errore del rig si
  è rivelato solo mettendo marker e ossa fianco a fianco: asse verticale perfetto
  (piede 0.000, spalla +0.002, collo 0.000) e arti fuori (mano +0.283). Una
  singola metrica riassuntiva non l'avrebbe mai detto.
- **Attenzione a misurare cose diverse.** L'estensione delle ossa arriva a
  `head.x`, che sta alla **base del cranio**; l'altezza della mesh arriva alla
  cima della testa. Dividerle dà una scala sbagliata del 20%.

## Cosa resta fuori

- **I lupi**: rig quadrupede a parte, per scelta.
- **Rigging e animazioni automatiche di Meshy** (`openapi/v1/rigging`,
  `/animations`): solo per NPC che non combattono — le loro animazioni non
  portano root motion.
