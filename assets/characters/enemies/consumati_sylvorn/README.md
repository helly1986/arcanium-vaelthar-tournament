# L'armata dei Consumati Sylvorn

Sei mesh base generate il 2026-08-12, **da riggare**. Messe qui per poterle riprendere
dall'altro PC: non sono ancora agganciate a niente nel gioco.

## Cosa c'è dentro

| file | grado (`LORE/CREATURES.md`, Parte I bis) | ruolo |
|---|---|---|
| `sylvorn_fante.glb` | **① Fante Consumato** | spada e scudo. «Il numero»: gruppi di 4-6, il pericolo non è il colpo ma non avere più spazio |
| `sylvorn_soldato_scelto.glb` | **② Soldato Speciale** | **Arciere del Silenzio** — tira da lontano o dall'alto, non scende mai a ingaggiare |
| `sylvorn_chierico.glb` | **② Soldato Speciale** | **Chierico** — cura i suoi. Solo nel Cuore delle Radici |
| `sylvorn_comandante.glb` | **③ Comandante Consumato** | mantello ed elmo crestato. Ripete l'ordine gridandolo, e i fanti attorno lo eseguono |
| `sylvorn_mago.glb` | **④ Mago Guerriero** | la Voce Rimasta: radica il terreno, richiama Eco Radicate |
| `sylvorn_cavaliere.glb` | **⑤ Cavaliere Consumato** | due usi: il principe all'ingresso del Cuore delle Radici e **il Lord della Casata** nel Palazzo |

**La scala dei gradi è completa**: dal Fante al Cavaliere, più il Chierico come
secondo ruolo del ②. Non manca niente.

`_concept/` tiene i sei artwork approvati: sono la fonte di verità sull'aspetto, e
servono da riferimento per il rig e per l'equipaggiamento.

⚠️ **Il tell del Comandante va ANIMATO, non modellato** (`CREATURES.md` ③):
*«chi comanda guarda i suoi, chi obbedisce guarda te»*. A intervalli il capo si
volta verso i propri mentre tutti gli altri restano rivolti al giocatore. È la
lezione dell'Alpha portata un gradino su — non «colpisci il capo» ma «capisci chi
è il capo» — e senza quella clip il grado ③ non esiste, per quanto bella sia la
mesh.

## ⚠️ Lo standard dal 2026-09-30: sorgenti FBX in `sorgenti/`

Ogni corpo nuovo o rifatto si genera con **Tripo P2** (Smart Mesh, quad), si
scarica in **FBX** e la sua sorgente sta in `sorgenti/<nome>.fbx` (texture
incorporata; la cartella ha un `.gdignore`, quindi è versionata ma Godot non la
importa). In Godot entra solo `<nome>_rigged.glb`, che esce dal montaggio. La
ricetta, i formati e il perché di ogni passo stanno in `docs/05_RIG_CANONICO.md`
§4-ter.

| corpo | sorgente | rig in gioco |
|---|---|---|
| Mago | `sorgenti/sylvorn_mago_p2.fbx` (P2 quad, orecchie ritoccate con `ritocca_orecchie_mago.py`) | `sylvorn_mago_rigged.glb` — montato col nuovo standard |
| Soldato Scelto | `sylvorn_soldato_scelto.glb` (P2, ma scaricato in GLB) | `sylvorn_soldato_scelto_rigged.glb` — mani col difetto dei metacarpi, da rimontare |
| Fante | `sylvorn_fante.glb` (Meshy) | `sylvorn_fante_rigged.glb` — idem, e va rifatto con P2 |
| Comandante | `sorgenti/sylvorn_comandante_p2.fbx` (P2 quad dal concept ripulito delle scie, 2026-10-02; RIGENERATA lo stesso giorno: la prima aveva l'elmo vuoto) | `sylvorn_comandante_rigged.glb` — montato con lo standard, mantello di stoffa simulata, `gusci_rigidi_fino=300` |
| Chierico, Cavaliere | `*.glb` (Meshy, statici) | da rifare con P2 prima del rig |

I GLB Meshy qui sotto restano come riferimento finché i corpi non sono rifatti.

**E i tessuti si simulano** (dal 2026-09-30, `docs/05_RIG_CANONICO.md`
§4-quater): vesti, mantelli e falde escono dal montaggio come pezzi a guscio
unico, con la maschera nel colore dei vertici, e in gioco li muove
`GPUClothSolver`. Il primo è il Mago; lo seguono il Senza Nome del prologo
(rifatto con P2, mantello simulato) e i Consumati della Traccia Perduta.

## Stato reale dei file (fino al 2026-09-14)

Verificato leggendo il glTF, non a occhio:

```
                             skin  anim   triangoli  texture
sylvorn_fante.glb              0     0      41 286      3
sylvorn_soldato_scelto.glb     0     0      27 995      3   (RIFATTO 2026-09-14, vedi sotto)
sylvorn_chierico.glb           0     0      39 142      3
sylvorn_mago.glb               0     0      40 885      3
sylvorn_cavaliere.glb          0     0      41 560      3
sylvorn_comandante.glb         0     0      41 156      3
```

Sono **mesh statiche in A-pose**: nessuno scheletro, nessuna animazione, un nodo
solo. Tutto il mestiere di rig, skinning e retarget è da fare — la procedura sta
nella skill `game-animation-craft`, e la pipeline che il progetto usa già per i
nemici è documentata in `arcanium-pipeline-clip-nemico`.

> **Aggiornamento 2026-08-17 → il piano di lavoro sta in `docs/10_ARMATA_SYLVORN.md`.**
> Due fatti misurati che smentiscono quello che si sarebbe dedotto a occhio da
> questa pagina:
> - **Il Fante è ~12% più grande del corpo Nephilite** (gamba +14.9%, braccio
>   +10.2%, misurati sulle lunghezze di catena fra i giunti rilevati da ARP), e
>   **non di una scala uniforme**: omero più corto, avambraccio più lungo di un
>   terzo. Non si riscala — `docs/05` sceglie «le proporzioni seguono il corpo» —
>   ma `move_range` e `close_hit_range` vanno alzati di ~12%.
>   ⚠️ Una versione precedente di questa nota diceva «stessa taglia, k = 1.001»:
>   era sbagliata, veniva da una stima geometrica della spalla poi smentita.
> - **Metà dei vertici sono doppioni di cucitura**: il Fante scende da 40 958 a
>   20 588 saldando a 0.0001. I 41 000 triangoli restano quelli (giusto non
>   decimarli), ma la saldatura è il primo passo obbligatorio.
>
> Lo strumento di montaggio è `arcanium/tools/monta_consumato_sylvorn.py`.
>
> **Il Soldato Scelto è stato RIFATTO il 2026-09-14**: il corpo Meshy aveva
> **sei dita** per mano (vedi la memoria `meshy-sei-dita`: si contano PRIMA di
> riggare — qui non era stato fatto). Il nuovo viene da **Tripo Smart Mesh
> P2.0** (quad, 27 995 triangoli, texture PBR 2K generate col modulo PBR di
> Tripo, 5 crediti): cinque dita, verificate sui render delle mani dalle punte.
> Arriva normalizzato a 1 m e in **87 gusci separati** (piastre, cinghie,
> cappuccio): `prepara(..., altezza=1.904)` lo porta all'altezza del corpo
> vecchio, e il bind ARP si fa guscio per guscio (vedi `rigga`), altrimenti dal
> ponte lega solo il primo. Il GLB riggato tiene lo stesso ordine di ossa
> (Prop_Attachment_R 53, _L 33, Back 13): presa dell'arco e faretra tarate sul
> corpo vecchio reggono, verificato al render.

**Sui 41 000 triangoli: NON si decimano.** *(deciso 2026-08-12)*

Avevo scritto qui che il Fante andava decimato perché in gruppi di 4-6 fa ~240 000
triangoli. Era una preoccupazione mal tarata: in una scena che porta già milioni
di triangoli di foresta, 240 000 di nemici non sono il collo di bottiglia — lì i
costi veri sono le **draw call**, il **passo delle ombre** e i novecento corpi
statici del sottobosco.

E **Godot 4 genera i LOD da solo in import**: la spesa a distanza è già gestita, e
la qualità da vicino resta piena. La decimazione avrebbe buttato via proprio
quella, cioè l'unica cosa che si vede quando un nemico ti è addosso.

Se un giorno il costo si facesse sentire, le leve nell'ordine giusto sono:
1. **ombre** — una mesh skinnata viene deformata una seconda volta per il passo
   delle ombre: è lì che il conto raddoppia, ed è il primo posto dove guardare;
2. **distanza di visibilità** e soglie di LOD, che non toccano la qualità vicina;
3. la decimazione, **per ultima**, e solo se le prime due non bastano.

⚠️ Le texture sono a piena risoluzione (~30 MB a modello, ~183 MB in tutto). In
gioco non pesano, perché il progetto impone `size_limit=1024` in import
(vedi il commit 6cb8130 e la memoria `arcanium-build-size-textures`), ma il repo
se le porta dietro così come sono.

## Decisioni già prese, da applicare al rig e all'equipaggiamento

**Aspetto (non toccare).** L'armatura resta **intatta**: l'orrore dei Consumati è
che stanno benissimo. Il guasto lo racconta la faccia — grigia, esangue — più lo
shader `arcanium/shaders/consumato_grezzo.gdshader`, che fa affiorare il **viola
dell'Arcanium** dalle fessure con un battito troncato di netto («una preghiera
interrotta a metà»). Verde della casata sulla mesh, viola del consumo nello
shader: i due colori dicono cose diverse e non vanno mescolati.

**Il Mago** ha le orecchie tese e il Corno d'Ascolto: sono segni di **casta**,
non suoi (→ `LORE/HOUSES.md`, «Il Corno d'Ascolto» e «L'Orecchio Teso»).

**Il Cavaliere è ×2 e tozzo** — con tre conseguenze già scritte in
`CREATURES.md` e da non scoprire dopo: le clip vanno **rallentate**
(`anim_speed_scale`; un Consumato non può sembrare rapido), l'arma ha il **doppio
di portata** quindi `hitbox_size`/`hitbox_offset`/`contact_times` vanno ritarati,
e il Palazzo gli deve stare intorno (4 m netti di passaggio e soffitto).

**Drop:** i pezzi d'armatura **e** l'equipaggiamento sono droppabili, **10% per
ogni singolo pezzo**.

**Resistenze dell'armatura Sylvorn:** buona contro TAGLIO, PERFORAZIONE e
SCHIANTO; **ottima contro FUOCO e SACRO** — è armatura pensata per difendersi dal
fuoco Vorrkai, ed è il motivo per cui è pesante anche sul Fante.
