# L'Armata Consumata Sylvorn — dal modello alla mossa giocabile

> Stato al 2026-08-17. Le sei mesh sono in
> `assets/characters/enemies/consumati_sylvorn/`; i gradi e il loro senso stanno
> in `LORE/CREATURES.md`, Parte I bis. Questo documento copre solo il passaggio
> **da mesh statica a nemico giocabile**: rig, skinning, move set, animazione.
>
> Ogni numero qui dentro è **misurato**, e dice dove. Quelli non ancora misurati
> sono marcati `DA MISURARE` — non sono stime travestite da fatti.

## 0. La taglia: il Fante è **~12% più grande**, e il bounding box aveva ragione

> ⚠️ **CORREZIONE del 2026-08-17.** Qui c'era scritto il contrario — «i corpi
> sono già alla taglia giusta, k = 1.001» — e la conclusione era di non
> riscalare *perché sono lo stesso uomo*. Il numero era sbagliato: veniva da una
> stima **geometrica** della spalla che la rilevazione AI di ARP ha poi mostrato
> essere 11 cm troppo laterale e 10 cm troppo bassa. Lasciata lì, quella riga
> avrebbe fatto tarare male portata e hitbox di sei personaggi.

Misurato sulle **lunghezze di catena** fra giunto e giunto — che non dipendono
dalla posa — con i giunti rilevati da ARP:

| segmento | Nephilite | Fante | Fante/Neph |
|---|---|---|---|
| omero | 0.2948 | 0.2773 | 94% |
| avambraccio | 0.1828 | 0.2490 | **136%** |
| femore | 0.3993 | 0.4566 | **114%** |
| tibia | 0.3771 | 0.4355 | **116%** |
| **gamba intera** | 0.7764 | 0.8921 | **+14.9%** |
| **braccio intero** | 0.4776 | 0.5263 | **+10.2%** |

Il rapporto dei bounding box (1.709 / 1.903 = 0.898) era **coerente con la
verità**. Il falso positivo non era il bounding box: ero io.

⚠️ E si noti che **non è una scala uniforme**: l'omero è più corto del
Nephilite e l'avambraccio più lungo di un terzo. Il Fante non è "il Nephilite
ingrandito", ha proporzioni sue. Nessun fattore di scala le pareggia.

**Le due misure che invece NON vanno usate**, entrambe pose-dipendenti perché il
rest Nephilite è accovacciato in stance di combattimento:
il bounding box, e la distanza **verticale** spalla→caviglia (che su un rig con
le ginocchia piegate accorcia). Si misura la catena, giunto per giunto.

**Conseguenze pratiche:**
- **Non si riscala**, ma non più «perché è lo stesso uomo»: perché
  `docs/05_RIG_CANONICO.md` sceglie esplicitamente *«una sola convenzione di
  ossa; le proporzioni seguono il corpo»*, e una scala uniforme non
  aggiusterebbe comunque proporzioni diverse.
- **`move_range` e `close_hit_range` vanno alzati di ~12%** rispetto ai valori
  del Consumato: le braccia sono più lunghe, e l'arma arriva più lontano di dove
  la tabella del Consumato dice.
- I **finisher vanno verificati** — è il prezzo dichiarato in `docs/05` §"Il
  prezzo, dichiarato", e questo è esattamente il caso previsto: un corpo con
  proporzioni lontane dalla media.
- Il ×2 del Cavaliere si misura sul **Nephilite**, non sul Fante.

## 1. Lo stato reale delle sei mesh

Letto dal chunk JSON dei GLB, non dedotto:

```
                             skin  anim  nodi   triangoli   textures
sylvorn_fante.glb              0     0     1      41 286       3
sylvorn_soldato_scelto.glb     0     0     1      41 615       3
sylvorn_chierico.glb           0     0     1      39 142       3
sylvorn_comandante.glb         0     0     1      41 156       3
sylvorn_mago.glb               0     0     1      40 885       3
sylvorn_cavaliere.glb          0     0     1      41 560       3
```

> ✅ **Il Fante non e' piu' in questa lista.** Dal 2026-08-20 e' riggato,
> travasato sul rig Nephilite ed **e' in gioco**:
> `assets/characters/enemies/consumati_sylvorn/sylvorn_fante_rigged.glb`, a cui
> puntano `sylvorn_fante.tscn` e `sylvorn_fante_spadone.tscn`. Vedi §2-ter.
> Le altre cinque mesh sono ancora statiche, e per loro vale tutto quanto segue.

Mesh statiche in A-pose, **centrate sull'origine** (piedi a −0.95, non a zero) e
con i vertici **spezzati sulle cuciture UV**: sul Fante la saldatura a 0.0001 è
scesa da 40 958 a 20 588 vertici, cioè **metà erano doppioni**. Vale per tutte e
sei, ed è il primo passo obbligatorio (poi le normali custom vanno buttate, o la
pelle brulica — `docs/05_RIG_CANONICO.md` §3).

## 2. Il rig: perché la mesh si piega sul rig e non viceversa

Il rig Nephilite è **condiviso** e il suo rest è la stance di combattimento. Le
clip di `anims/sword` e `anims/spear` esprimono **rotazioni locali relative a
quel rest**: montarle su un rest diverso dà una posa diversa. Quindi il rest è
intoccabile, e il corpo nuovo — che arriva in A-pose — va portato nella stance.

Ed è gratis: **la posa di rest non si vede mai in gioco**, perché gira sempre una
clip (`rig-e-skinning.md` §2).

**La ricetta scelta — il "puppet" costruito dal rig stesso.** La ricetta canonica
usa come puppet il rig nativo della mesh, che qui non esiste (skin=0). E lo Smart
AI di ARP, che sarebbe l'altra strada, **non è installato su questa macchina**:
`Documents\AutoRigPro\AI\inference` non c'è (i file sono probabilmente sull'altro
PC). Il puppet si costruisce quindi dal rig Nephilite:

1. pulizia mesh (saldatura + normali) e piedi a quota zero;
2. **copia** del rig, posata nell'A-pose misurata sulla mesh, poi *applica posa
   come rest*: ora il puppet ha il rest della mesh;
3. bind della mesh al puppet (pesi automatici);
4. il puppet torna alla posa Nephilite e si **applica il modificatore**: la mesh
   è ora cotta nella stance di combattimento;
5. bind della mesh cotta al rig Nephilite **intatto**.

Lo strumento è `arcanium/tools/monta_consumato_sylvorn.py`.

### Cosa sa già misurare, e cosa no

I giunti si ricavano dalla geometria per **gruppi contigui lungo X**: a mezzo
busto una fetta orizzontale dà tre gruppi — *braccio | busto | braccio* — e i
confini sono geometria, non soglie. Simmetria destra/sinistra verificata entro
**8 mm** su tutti i giunti: la misura è coerente.

Due trappole già pagate e scritte nel codice, perché non si ripaghino:

- **Le falde dell'armatura falsano l'inforcatura.** Cercare il vuoto sull'asse
  x≈0 dava 0.640 m, cioè il 34% dell'altezza — anatomicamente impossibile: le
  falde scendono fra le cosce e chiudono quel vuoto molto più in basso
  dell'inforcatura vera. Contando i *gruppi-gamba* invece del vuoto: **0.811 m**,
  il 43%, che è giusto.
- **Il gomito e il ginocchio non esistono in un arto dritto.** In A-pose il
  braccio è un cilindro rettilineo: non c'è nessuna piega da trovare, e ogni
  euristica che "cerca il gomito" insegue un segnale che nella geometria non c'è
  (ne usciva 16 cm troppo basso). Si misurano i due **estremi** — la spalla, dove
  il braccio si fonde col busto, e la mano — e si suddivide con le **proporzioni
  del rig**, che sono il corpo a cui la clip si riferisce comunque.

`DA MISURARE / da rifinire`: la **spalla** esce ancora ~8 cm troppo laterale
(cade nel pauldron invece che nell'ascella) e il **collo** trova l'attacco
dell'elmo invece della base del collo. Entrambi vanno chiusi prima del bind,
perché sono i due giunti su cui l'auto-weight sbaglia sempre.

### I due collaudi obbligatori prima di dire "riggato"

Da `docs/05_RIG_CANONICO.md`, e nessuno dei due è facoltativo:

1. **Ogni osso deformante è dentro la mesh** — punto più vicino più segno della
   normale, non a occhio. Riferimento buono: 0 ossa fuori.
2. **Un vertice noto pesa sull'osso giusto** — la punta del dito medio deve
   pesare sul dito medio. È il collaudo che conta di più, perché il binding
   *riesce comunque* e non dà nessun allarme anche coi pesi completamente
   sbagliati.

⚠️ E un terzo, specifico di questi corpi: **le falde e i pauldron sono piastre
che non devono seguire la carne**. L'auto-weight le fonderà alla coscia e alla
spalla. Trattamento da `rig-e-skinning.md` §3-4 (catena di ossa dedicate o
pesaggio per prossimità isolato) — sulle falde ci sono già gli
`Hips_Attachment` e i `Loincloth_*` del rig, che esistono apposta.


### 2-ter. Il travaso, FATTO — e i due errori che l'hanno pagato

Chiuso il 2026-08-20. Lo strumento e' `arcanium/tools/monta_consumato_sylvorn.py`
§4-§5 (il blend di lavoro sta in `lavorazione/blender/sylvorn_fante_travaso.blend`,
fuori dal repo: si ricostruisce rilanciando lo script).

**Il cancello che autorizza la costruzione.** Misurato sulle dieci clip `sword`:
le tracce di **posizione** stanno **solo su `Root` e `Hips`**. Da
`rig-e-skinning.md` §2 discende che le *rotazioni* di rest sono intoccabili
mentre le *posizioni* sono libere — cioe' **le proporzioni del Fante si tengono
senza toccare una sola clip**. ⚠️ Se una clip nuova portasse tracce di posizione
su altre ossa, questa costruzione non vale piu': ri-misurare prima di rilanciare.

Ne esce `FanteRig`: nomi e gerarchia del Nephilite, rotazioni di rest identiche,
giunti del Fante. Verificato **dopo l'import in Godot**, non solo in Blender:

| | valore |
|---|---|
| scarto massimo di rotazione locale di rest | **0.1119°** (precisione float del round-trip glTF) |
| avambraccio / femore / tibia / omero | **+31.4% / +12.6% / +17.3% / −4.9%** |
| baricentro-giunto, mediana | **2.31 %H** (Consumato di controllo: 3.49 %H) |
| vertici senza peso | **0** |

**I due errori, perche' non si ripaghino:**

1. ⚠️⚠️ **Le code delle ossa di `NephiliteRig` non puntano ai figli.** Arriva da
   glTF, che le lunghezze d'osso non ce l'ha, e Blender se le inventa:
   `Shoulder_L.tail` dista **41.8 cm** dalla testa di `Elbow_L`, e `LowerLeg_L`
   e' lungo 4.5 cm. Chi si fida della coda ottiene zero catene, un rig identico
   al donatore e un puppet a rotazione nulla — **e nessun numero protesta**. Si
   misura testa → testa del figlio.
2. ⚠️ **Il collaudo «ossa dentro la mesh» col segno della normale non regge
   qui.** Su un corpo corazzato a doppia parete il punto piu' vicino cade sulla
   parete *interna* della piastra e il segno si inverte: 45 ossa «fuori» sul
   Fante e **47 sul Consumato, che in gioco funziona**. Il metro buono e' il
   **baricentro dei vertici dominati** contro il giunto, con un personaggio che
   funziona nella stessa misurazione.

**Due cose restano aperte, entrambe misurate:**

- ~~Le falde e i pauldron seguono la carne.~~ **RISOLTO il 2026-08-21, e la
  diagnosi qui sopra era SBAGLIATA** — la lascio scritta perche' l'errore vale
  quanto la correzione. Diceva `UpperLeg` 14 %H e `Shoulder` 7 %H: erano
  artefatti della SONDA. Lo scarto baricentro-osso era misurato contro il
  **vettore dell'osso**, che sul rig Nephilite (glTF) non segue l'arto.
  Rimisurato sull'asse vero — testa dell'osso → testa del figlio — `UpperLeg`
  scende a **1.8-2.0 %H** e `Shoulder` a **0.7 %H**: non c'era niente da
  aggiustare. Restava in piedi solo `Spine_02` a **10.1 %H**, e li' il difetto
  era reale ma diverso: ARP pesa la corazza in un pezzo solo, quindi `Spine_02`
  si prendeva tutta la piastra **dal petto fino alle falde**, che oscillavano
  col busto invece che col bacino. Corretto da `stacca_falde()`: 2.680 vertici
  passati al `Hips`, tagliando alla **sezione piu' stretta** della regione — la
  vita, cercata e non cablata (sul Fante z=1.075, 11 cm sopra l'anca) — con una
  fascia sfumata di 3 cm per non incernierare la piastra di netto.
  Provato per isolamento: ruotando di 40° **solo** il petto, le falde non si
  muovono. ⚠️ Non sui `Loincloth_*`: nessuna clip li anima, sono figli inanimati
  di `Hips`.
- **Il Fante affonda di 3.8 cm** sotto `sword_idle_01` (6.2 sul fendente),
  perche' le clip pinzano l'`Hips` a un'altezza scritta per gambe piu' corte.
  ⚠️ **Non e' una regressione:** sulle stesse clip il Consumato **galleggia di
  14.7 cm** — e' lo stesso difetto di `docs/05` §5-bis, e il Fante lo riduce di
  quattro volte. L'IK dei piedi lo chiuderebbe per entrambi.

⚠️ **All'import, il riferimento e' `consumato_rigged.glb.import`, NON
`protagonista_v4.glb.import`.** Nel progetto ci sono due famiglie di scheletro:
il player (`BaseArmature/Skeleton3D`, mappa identita' ARP→Humanoid,
`fix_silhouette` **acceso** col filtro sui piedi) e i nemici
(`NephiliteRig/Skeleton3D`, `nephilite_humanoid.tres`, `fix_silhouette`
**spento**). Tutte le 21 clip di `anims/sword` portano il blocco *nemici*:
copiarci sopra quello del player rinominerebbe le ossa sul profilo Humanoid e
romperebbe `Prop_Attachment_R` e ogni NodePath delle due scene.

⚠️ E il GLB nuovo ha gli stessi **nomi** del Consumato ma non lo stesso
**ordine**: `Prop_Attachment_R` passa dall'indice 45 al **53**, e il `bone_idx`
del `BoneAttachment3D` va aggiornato nelle scene.

## 3. I move set

Il move set è **dati** (`EnemyMove` + `EnemyMoveSet`), non codice. Gli istanti di
contatto sono già misurati per tutte le clip del pack e vivono in
`arcanium/resources/attack_timing.tres` — si copiano da lì, non si stimano.

Regola che vale per tutti e sei, e che nessun grado può rompere:
**un Consumato non può sembrare rapido.** Rompe la regola in potenza e in
interrompibilità, mai in velocità (`LORE/CREATURES.md`, ⑤).

### Il salto di difficoltà — **da qui in poi fanno male sul serio** *(deciso 2026-08-17)*

Il giocatore ha **100 HP** (`characters/player_dawnkeep_v4.tscn`). La regola
data: *«se ti fai cogliere impreparato, con 4/5 colpi muori»* — quindi
**20-25 di danno a colpo**, contro gli 8-9 dei Consumati della Traccia.

Per riferimento, la scala esistente: lupo 7-11, Consumato 9-14, Alpha 16-28,
Senza Nome 11-34. L'armata Sylvorn si piazza **sopra l'Alpha**, ed è voluto:
sulla Traccia i Consumati erano *«il contrappasso gentile dopo la crudeltà del
Senza Nome»*, qui sono una guarnigione militare.

⚠️ Il salto è di **potenza**, non di velocità. `anim_speed_scale` resta 0.7 (0.6
sullo spadone). Un Consumato veloce non è più un Consumato — e con questi numeri
la leggibilità del wind-up smette di essere un vezzo: è l'unica cosa che rende
il colpo evitabile invece che ingiusto.

### I DUE Fanti — scudo e spadone *(deciso 2026-08-17)*

Il grado ① si sdoppia in due varianti sulla **stessa mesh e lo stesso rig**:

| | arma | cosa insegna |
|---|---|---|
| **①a Fante con scudo** | spada + scudo | *quando* colpire — c'è una guardia da aggirare |
| **①b Fante con spadone** | spadone a due mani | *quanto* costa sbagliare — colpisce come un treno |

Insieme risolvono il problema che il grado ① aveva da solo: quattro-sei nemici
identici sono una folla, non uno scontro. Con due sagome diverse la domanda
diventa **«chi colpisco per primo?»**, che è esattamente la lezione del grado
portata un gradino su.

#### ①a — Lo scudo: le clip ESISTONO GIÀ nel pack

Verificato nel pack Nephilite (`Straight Sword Animation Set`), cartella
**Off Hand** — non serve autorare niente:

| clip nel pack | a cosa serve |
|---|---|
| `straight_sword_off_guard_idle_01` | sta dietro lo scudo |
| `straight_sword_off_guard_up_01` / `_down_01` | **alza e abbassa la guardia** — è il tell su cui il giocatore temporizza |
| `straight_sword_off_guard_block_light/medium/heavy_01` | l'impatto parato, per peso del colpo |
| `straight_sword_off_guard_block_ping_01` | il colpo che rimbalza |
| `straight_sword_off_guard_break_01` | guardia rotta → finestra di punizione |
| `straight_sword_off_walk_guard_*` / `run_guard_*` | avanza **restando** dietro lo scudo (8 direzioni) |

E c'è anche `straight_sword_main_guard_counter_01`: il contrattacco dalla
guardia, che è ciò che rende la parata del nemico una minaccia e non solo un
muro.

**Il timing che ne esce.** Il Fante alza lo scudo, avanza coperto, e la finestra
per colpirlo è quella fra `guard_down` e l'inizio del suo attacco. Chi picchia
sullo scudo si becca il `block_ping` e il contrattacco; chi aspetta il momento
in cui la guardia scende passa. In gruppo, questo è ciò che costringe a
**scegliere il bersaglio** invece di menare nel mucchio.

⚠️ **Il blocco è CODICE NUOVO, e non è poco.** In `arcanium/systems/enemies/`
non esiste nessuno stato di guardia: c'è solo il poise-break, che è uno status
subito. Serve uno stato `GUARD` che (a) assorba o riduca il danno frontale, (b)
scelga la clip di blocco in base alla `power` del colpo ricevuto, (c) si rompa
accumulando colpi o su un colpo pesante, aprendo `guard_break`. È il pezzo di
lavoro più grosso di tutta l'armata, e va fatto prima che ①a abbia senso.

#### ①b — Lo spadone: anche qui il pack ha tutto

Cartella **Two Hand**, moveset completo e mai importato:

`th_light_attack_01/02/03` · `th_run_attack_01` · `th_charged_attack_01/02`
(anche a fasi `_charge`/`_hold`/`_release`/`_release_full`) · `th_jump_light_attack_01`
· `th_idle_01` · `th_guard_idle_01` · `th_death_01` · `th_back_step_attack_01/02`

Oggi in gioco c'è **una sola** clip `th` (`sword_th_charged_attack_01`, contatto
misurato a 1.60). Le altre vanno portate dentro con la pipeline A→Z
(memoria `arcanium-pipeline-clip-nemico`): export in **metri**, root motion
spostata su `Root`, e i `contact_times` **misurati** con
`measure_attack_contacts`, non stimati. È il passo dove si è già rotto tutto una
volta esportando in centimetri.

#### Ricompense — entrambe le varianti

- **25 Arcanium** alla morte (`CrystalBounty.amount = 25`). Il Consumato della
  Traccia ne dà 1: il salto dice al giocatore che questi valgono il rischio.
- **Pezzi d'armatura ed equipaggiamento al 10% ciascuno** (`ItemDrop`, un nodo
  per pezzo, `drop_chance = 0.1`), come già stabilito nel README della cartella.
  ✅ **Gli item Sylvorn ESISTONO** — `sylvorn_{elmo,corazza,bracciali,gambali}.tres`
  in `arcanium/resources/items/`, e il loro `id` combacia con l'`item_id`
  dichiarato nei nodi `ItemDrop` delle due scene. I drop funzionano.
  *(Qui c'era scritto il contrario; verificato sui file il 2026-08-20.)*

### ① Fante — `sylvorn_fante_moveset.tres` *(scritto, gira su clip esistenti)*

Il grado che si può accendere **oggi**, appena la mesh è riggata: usa solo clip
già in gioco e misurate.

| id | clip | durata | contatto | note |
|---|---|---|---|---|
| F1 | `sword/sword_light_attack_01` | 1.30 | 0.47 | fendente base |
| F2 | `sword/sword_light_attack_02` | 1.53 | 0.46 | rovescio, chiude la catena |
| F3 | `sword/sword_run_attack_01` | 1.37 | 0.51 | serve a **chiudere la distanza** |

**Niente attacco caricato, ed è una scelta di regia.** Il Fante arriva in gruppi
di 4-6: sei wind-up da 3.7 s sovrapposti non si leggono più, e la lezione del
grado — *«contro di lui si impara il posizionamento, non il parry»* — richiede
che il singolo colpo sia corto e frequente, e che la pressione venga dal
**numero**. Per la stessa ragione `link_gap` è alto e la probabilità di catena
bassa: con sei nemici, ogni catena si moltiplica per sei.

Verificato con `arcanium/tools/verifica_moveset.gd` (headless): le tre clip
esistono e i tre contatti cadono al 36% / 30% / 37% della loro clip.

> ⚠️ **Trovato di passaggio, e riguarda un nemico già in gioco.** Lo stesso
> cancello mostra che le clip `spear/` del Consumato **non sono mai passate da
> `measure_attack_contacts`**: non hanno durata in `attack_timing.tres`, quindi i
> contatti dichiarati in `consumato_moveset.tres` (1.23 e 1.70) sono gli unici
> del gioco che nessuno ha verificato. Sono clip composte a mano dalle fasi del
> pack, cioè proprio quelle a più alto rischio.

### ② Arciere del Silenzio — **bloccato, e non dal move set**

`min_range` alto e `projectile_scene` bastano per il tiro, ma il grado è definito
da *«non scende mai a ingaggiare, arretra se ti avvicini»*: l'arretramento
**non esiste** in `ArcaniumEnemy`. Il quadrupede ha già una fuga
(`_special_state_step`), quindi il gancio è quello — va promosso nella base.
Clip: **manca** l'incocca-e-tira. `sword_cast_01` regge come segnaposto (wind-up
telegrafato, rilascio misurato a 1.97) ma è visibilmente una spada.

### ② Chierico — **bloccato dal codice, non dalle clip**

`sword_cast_01` è la clip giusta per il canale. Manca la **cura di un alleato**:
il sistema nemici non ha nessun canale nemico→nemico se non `on_ally_died()`.
⚠️ La lore lo marca come **cancello, non lezione**: ignorarlo significa non poter
vincere, quindi deve essere sempre *raggiungibile* — è un vincolo di level
design prima che di move set.
Il tell («ogni tanto guarisce un cadavere, o il vuoto») costa pochissimo e
va scritto insieme alla cura, non dopo.

### ③ Comandante — clip di combattimento ok, manca **la giratina**

> **Aggiornamento 2026-09-30: la meccanica c'è**, su un corpo segnaposto (il
> Fante Spadone, `arcanium/characters/sylvorn_comandante.tscn`). Tutto sta in
> `arcanium/systems/enemies/ordine_comandante.gd`: arruola i fanti da mischia
> entro 14 m, dà a ognuno un posto sull'anello attorno al giocatore e uno alla
> volta il turno d'attacco; morto il Comandante i fanti tornano singoli. La
> giratina è un `LookAtModifier3D` sulla testa che guarda il fante a cui sta per
> dare il turno. Cancello: `verifica_comandante.gd` (headless).
> **2026-10-02: il corpo c'è** (Tripo P2 quad dal concept, mantello di stoffa
> simulata, ricetta nel cappello di `sylvorn_comandante.tscn`).
> **2026-10-02: in Kalvorn sono DUE** (scelta dell'utente): uno nel Nido della
> Radice Sorda, dietro il mucchio, con 6 scudi e 1 spadone ai suoi ordini (il
> nido conta 11 nemici per la quest); uno nella guarnigione della soglia, al
> centro dietro gli scudi, in aggiunta ai 5 Fanti. Il raggio di comando (14 m)
> decide dove possono stare: a 9 m dal centro del nido tre scudi restavano
> fuori. `verifica_comandante` ora prova l'ordine anche sugli SCUDI (guardia e
> Testuggine): passa. Ritratti: `ritratto_nido.tscn`, `ritratto_soglia.tscn`.

Fendenti pesanti da `sword_charged_attack_01/02` (contatto 2.53 / 2.54) più i
leggeri. Quello che il grado *è*, però, non è una mossa: è
*«chi comanda guarda i suoi, chi obbedisce guarda te»*. Senza quella, il grado ③
non esiste per quanto bella sia la mesh. Vedi §4: **non serve una clip**.

### ④ Mago Guerriero (la Voce Rimasta) — il grado più economico

`sword_cast_01` per il canale, `min_range` alto. Radicamento del terreno: si può
riusare `wall_scene` (`boss_wall.gd`), che già disegna una zona persistente con
tick di danno. Il richiamo delle **Eco Radicate Guaste** ha già mesh, tinta e
regola (`SummonedMinion.minion_tint`); manca il lato nemico, come dice
`LORE/CREATURES.md`. Serve in più una clip di richiamo — *le braccia che si
alzano e restano alzate un istante di troppo*.

### ⑤ Cavaliere — ×2, e le tre conseguenze da non scoprire dopo

Clip a due mani (`sword_th_charged_attack_01`, contatto 1.60) e `jump_attack`.

⚠️ **La scala ×2 va cotta nella geometria all'export, non messa sul nodo.** Una
scala su un nodo con scheletro e collisioni è la stessa famiglia di guai già
pagata sui distruttibili (memoria `arcanium-distruttibili-frattura`).
E poi: `anim_speed_scale` più basso (~0.55: raddoppiato, un corpo che riproduce
clip autorate a scala 1 sembra *leggero*), e `hitbox_size`/`hitbox_offset`/
`contact_times` ritarati sulla portata doppia. Manca anche il **guinzaglio**
(*«non ti insegue oltre il perimetro che difendeva da vivo»*): non c'è in
`ArcaniumEnemy`.

### Riepilogo di cosa blocca cosa

| grado | mesh | rig | clip | codice |
|---|---|---|---|---|
| ① Fante | ✅ | ✅ **fatto** | ✅ esistenti | ✅ niente di nuovo |
| ② Arciere | ✅ | da fare | ⚠️ manca l'arco | ⚠️ arretramento |
| ② Chierico | ✅ | da fare | ✅ `cast_01` | ⚠️ cura alleati |
| ③ Comandante | ✅ P2 + stoffa (2026-10-02) | ✅ | ✅ esistenti | ✅ tell + coordinamento (2026-09-30) |
| ④ Mago | ✅ | da fare | ⚠️ richiamo | ⚠️ evocazione nemica |
| ⑤ Cavaliere | ✅ | da fare (×2) | ✅ due mani | ⚠️ guinzaglio, hyperarmor |

## 4. AnimTree: **la proposta è di non introdurlo adesso**

Oggi i nemici girano su `AnimationPlayer` nudo (`_play()` + `anim_xfade`);
l'`AnimationTree` esiste solo sul giocatore (`docs/02_ANIMTREE_MAP.md`).
La domanda vera non è "sarebbe più elegante", è **cosa si romperebbe**.

**Due contratti poggiano oggi sull'AnimationPlayer, e sono i due su cui si regge
il combattimento:**

1. **Il colpo lo consegna il PLAYHEAD.** `current_animation_position` è già in
   tempo-clip e si confronta *direttamente* con i `contact_times` misurati
   (`docs/04` §2b). Sotto un `AnimationTree` quel playhead non è più la verità:
   il tempo va chiesto alla `playback` della state machine, per stato. Parata e
   schivata all'ultimo istante — le due abilità su cui si regge tutto — funzionano
   solo se il danno arriva quando l'arma arriva.
2. **La root motion sta sul bone `Root`** via `anim_player.root_motion_track`, con
   la verticale lasciata nella posa dell'`Hips`. Passare all'albero significa
   rifare quella catena, che è costata la scoperta per cui i nemici
   "galleggiavano".

**E la cosa che sembra chiedere un AnimTree, in realtà non lo chiede.** L'unico
argomento forte era la *giratina del tell* del Comandante e del Mago: deve
avvenire **mentre** gira un'altra clip, e un `AnimationPlayer` non sa
sovrapporre. Ma un layer additivo non è il modo migliore neanche lì:

> **Proposta: la giratina è un `SkeletonModifier3D` che ruota `Neck` e `Head`,
> non una clip.**

Perché è meglio di un additivo:
- si compone con **qualunque** clip senza autorarne una per grado;
- punta un bersaglio **vero** (i propri) invece di una rotazione fissa, quindi il
  tell dice la verità anche quando gli alleati si spostano — ed è esattamente ciò
  che la lore chiede: *«il capo si volta verso i propri, tutti gli altri restano
  rivolti al giocatore»*;
- non può desincronizzarsi dalla logica che decide chi comanda;
- Godot 4.7 ha già la strada giusta (`_process_modification_with_delta`), la
  stessa prevista per l'IK dei piedi in `docs/05` §5-bis.

**Quando l'AnimTree diventerà giusto**, e vale la pena scriverlo ora: quando
servirà una locomozione *mescolata* (BlendSpace1D fermo↔passo↔corsa) perché sei
Fanti che scattano fra tre clip si vedono, o una separazione busto/gambe. Nessuno
dei due serve per portare l'armata in gioco, e nessuno dei due vale la
riscrittura dei due contratti qui sopra **finché il grado ① non è giocabile**.
