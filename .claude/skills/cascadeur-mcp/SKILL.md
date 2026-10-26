---
name: cascadeur-mcp
description: "Cascadeur 2026.2 via MCP: un solo tool, `run_script`, che esegue Python (csc/pycsc) dentro Cascadeur. Usare per importare ed esportare GLB, scrivere togliere e spostare keyframe, impostare l'interpolazione (LINEAR/BEZIER/AI), costruire il rig associando le ossa del metarig via QRT, lanciare comandi con call_action, pilotare AutoPosing/AutoPhysics/Inbetweening, rendere immagini o video, e convertire in root motion. Contiene le firme verificate dal vivo, i default che ingannano e gli avvisi innocui. Keywords: cascadeur, cascadeur mcp, run_script, csc, pycsc, csc.glb.process_import, process_export, csc.rig.QrtData, BoneProperty, RiggingWindow, create_from_qrt_by_content, qrigcasc, call_action, ActionManager, Interpolation.AI, set_section, unset_section, set_fixed_interpolation_or_key_if_need, AutoPosingTool, AutoPhysicTool, InbetweeningTool, RenderToFile, domain_scene, modify_update_with_session, CUBICSPLINE, root motion, port 8765."
---

# Cascadeur via MCP — un ponte, non un'API

Verificato su **Cascadeur 2026.2**, server `cascadeur-script-runner` **0.3.1**,
il 2026-08-08, e riverificato dal vivo il **2026-08-20** (rigging, keyframe,
interpolazione, azioni). Dentro gira **Python 3.11** con `csc` e `pycsc` **0.6.0**.

## La cosa da sapere per prima

**Esiste UN SOLO tool: `run_script`.** Esegue Python dentro Cascadeur al
prossimo evento di idle della scena. Non ci sono tool specializzati: non
cercarli. È lo stesso modello di `execute_blender_code` per Blender — tutto
passa da lì.

Non dedurre le capacità dal nome del prodotto. Prima di proporre un piano,
elencare i moduli e chiamare le funzioni per vedere cosa accettano.

## Accendere il server

Dentro Cascadeur: **`Script → MCP → Start MCP`**.

⚠️ **Non dà nessun riscontro a schermo.** Sembra che non sia successo niente, e
invece è in ascolto. Si verifica così:

```bash
powershell -c "Get-NetTCPConnection -LocalPort 8765 -State Listen"
```

⚠️ Va riacceso **a ogni avvio di Cascadeur**.

⚠️ I server MCP si agganciano **all'avvio della sessione**: accendere il server
a metà sessione non fa comparire i tool. Serve riavviare. Cascadeur porta la
configurazione già pronta in
`C:\Program Files\Cascadeur\resources\scripts\python\.mcp.json`:

```json
{ "cascadeur": { "type": "http", "url": "http://127.0.0.1:8765/mcp" } }
```

Se i tool non sono agganciati, si può parlare col server via HTTP JSON-RPC senza
aspettare il riavvio — su Arcanium c'è `tools/cascadeur_mcp.py` che lo fa:

```bash
python tools/cascadeur_mcp.py --info          # server, tool, risorse
python tools/cascadeur_mcp.py script.py       # esegue un file
python tools/cascadeur_mcp.py -c "print(1)"   # esegue una stringa
```

L'output torna come lista di messaggi con un **livello**: `Info`, `Warning`,
`Success`, `Error`. Leggere i livelli, non solo i testi (vedi sotto).

## Come si scoprono le firme

`inspect.signature` **non funziona** sulle funzioni di `csc`: sono binding
pybind11 e sollevano
`ValueError: no signature found for builtin`.

Il modo che funziona: **chiamare la funzione sbagliata e leggere il TypeError**,
che elenca gli overload accettati.

```
TypeError: process_import(): incompatible function arguments.
The following argument types are supported:
    1. (arg0: csc.domain.Scene, arg1: str, arg2: csc.glb.ImportOptions) -> None
```

Costa una chiamata e dà la verità. Non tirare a indovinare l'ordine degli
argomenti.

## Import ed export GLB

Andata e ritorno in **GLB**, lo stesso formato delle pipeline Godot/Blender.

```python
import csc
app = csc.app.get_application()
scena = app.current_scene()
dominio = scena.domain_scene()

io = csc.glb.ImportOptions()
io.include_objects = True
io.include_animation = True        # ⚠️ il DEFAULT è False
io.is_update_mode = False
io.throw_exception = True          # senza questo gli errori restano avvisi
csc.glb.process_import(dominio, r"C:\percorso\file.glb", io)
```

⚠️⚠️ **`include_animation` è `False` di default.** È la trappola numero uno:
l'import "riesce" e non porta dentro nessun keyframe.

Altre opzioni di `ImportOptions`: `fps` (30.0), `scale_factor`,
`adjust_meshes_rotations`, `ignore_mesh_transform`, `move_meshes_to_root`,
`for_selected_objects`, `for_selected_interval`.

### ⚠️⚠️ Cascadeur lavora in CENTIMETRI: `scale_factor = 100.0`

`scale_factor` è `None` di default, cioè nessuna conversione. Un GLB di Arcanium
è in metri, quindi entra alto **1,7 unità** in una scena che si aspetta 170.

Non è un fastidio visivo — è la fisica che sbaglia di 100×. La prova sta nella
scena stessa: `scene.gravity_per_frame()` vale **1,0889**, cioè 9,81 m/s² a 30
fps espressi in centimetri (9,81/900 = 0,0109 m = 1,09 cm). Con il corpo in
metri, AutoPhysics e le traiettorie balistiche trattano un uomo come un insetto
di 1,7 cm.

```python
io.scale_factor = 100.0     # import: metri -> centimetri
eo.scale_factor = 0.01      # export: centimetri -> metri
```

Il sintomo che si nota per primo è banale: **il personaggio si vede minuscolo
sulla griglia**. Verificarlo misurando, non a occhio — l'estensione in Y dei
giunti deve stare intorno a 170 per un umano.

### Il viaggio di ritorno: da Cascadeur a Godot

```python
eo = csc.glb.ExportOptions()
eo.include_animation = True
eo.scale_factor = 0.01      # centimetri -> metri
eo.fps = 30.0
csc.glb.process_export(dominio, percorso, eo)
```

Cascadeur esporta la scena **com'è**: l'animazione senza nome (`Anim_0`) e la
mesh del corpo attaccata — su Arcanium 5,77 MB per una clip che ne pesa 89 KB
senza. Il passaggio di rifinitura è `arcanium/tools/rifinisci_clip_cascadeur.py`.

⚠️⚠️ **Due trappole sul TEMPO, e nessuna delle due si vede.**

1. **L'fps della scena Blender va messo PRIMA dell'import.** Il glTF tiene i
   tempi in SECONDI e l'importatore li converte in frame con
   `scene.render.fps`, che di default è **24**: una clip di 2,00 s entra come
   48 frame invece di 60. Riesportata a 30 fps dura 1,6 s — l'animazione esce
   **accelerata del 25%**, ed è fluida, completa e integra: solo più veloce di
   come l'ha fatta l'animatore. Se ne accorge solo un collaudo sulla DURATA.
2. **Le chiavi di Cascadeur cadono a 59,99998 invece di 60.** L'esportatore
   glTF campiona i frame INTERI e si ferma al 59: l'ultimo fotogramma sparisce.
   Vanno agganciate alla griglia (arrotondare `keyframe_points[].co.x` e
   traslare i due handle della stessa quantità) prima di riesportare.

Poi in Godot le tracce arrivano come `BaseArmature/Skeleton3D:<osso>` e vanno
rimappate su `%GeneralSkeleton:<osso>`, che è la convenzione delle librerie del
progetto (`MeleeLib`, `LucideLib`).

⚠️ **`AnimationNodeBlendTree.connect_node`: prima l'uscita, poi gli ingressi.**
Chiamare `connect_node("Nuovo", 0, "Precedente")` *prima* di
`connect_node("output", 0, "Nuovo")` non lascia traccia: la connessione sparisce
senza errori e il nodo resta con l'ingresso 0 scollegato — cioè tutto il resto
dell'albero orfano. E `AnimationNodeBlendTree` **non espone la lettura** delle
connessioni (`get_node_connection_array` non esiste): si verifica leggendo
`node_connections` dal `.tscn` salvato.

### Guardare il risultato: `RenderToFile`

```python
app = csc.app.get_application()
sc = app.current_scene()                   # È GIÀ un csc.view.Scene
rtf = [t for t in app.get_tools_manager().tools()
       if isinstance(t, csc.tools.RenderToFile)][0]
rp = csc.tools.RenderParameters()          # solo width, height, samples
rp.width, rp.height, rp.samples = 900, 900, 4
rtf.take_image(sc, rp, r"C:\percorso\foto.png")
```

⚠️ `take_image` **scrive il file in modo ASINCRONO**: subito dopo la chiamata il
file non esiste ancora, e `os.path.exists` dice `False`. Non è fallita —
ricontrollare dopo. Dichiararla fallita e riprovare è tempo buttato.

⚠️⚠️ **Con la finestra di Cascadeur MINIMIZZATA il file non arriva MAI**
(risolto il 2026-10-15). `take_image` mette il render in coda e lo esegue al
prossimo ridisegno del viewport; una finestra ridotta a icona non ridisegna.
Nessun errore, nessuna riga nel log: la richiesta resta lì. Appena la
finestra torna visibile, la foto in sospeso viene scritta da sola (misurato:
`prova_A.png` comparsa 4 s dopo il ripristino). Per questo il 2026-09-26 e il
2026-10-09 sembrava rotta. Prima di una foto, controllare e ripristinare
SENZA rubare il focus all'utente:

```powershell
Add-Type 'using System;using System.Runtime.InteropServices;public class W{[DllImport("user32.dll")]public static extern bool IsIconic(IntPtr h);[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);}'
$h = (Get-Process cascadeur).MainWindowHandle
if ([W]::IsIconic($h)) { [void][W]::ShowWindow($h, 4) }   # 4 = SW_SHOWNOACTIVATE
```

Basta che non sia ridotta a icona: dietro ad altre finestre funziona.

La camera si sposta dal viewport, e le posizioni sono in **centimetri**:

```python
import numpy as np
dvp = sc.active_viewport().domain_viewport()
cs = dvp.camera_struct()                   # solo position, target, type
cs.position = np.array([0.0, 95.0, 320.0])
cs.target = np.array([0.0, 95.0, 0.0])
dvp.set_camera_struct(cs)
```

### ⚠️⚠️ `play_to_images_sequence` dal ponte UCCIDE Cascadeur (2026-09-12)

Chiamata via `run_script` con la firma giusta
`(scene_view, RenderParameters, cartella)`, ha scritto `frame_00000000.png` e
`info.txt` e poi il processo è sparito: nel log l'ultima riga è il `print` che
precede la chiamata. La resa in sequenza vuole il play della timeline in tempo
reale, e il thread del ponte non glielo concede. **Non usarla.** Per guardare
più frame: un `take_image` per chiamata, impostando `set_current_frame`
prima, con qualche secondo fra una chiamata e l'altra — e mai dodici
`take_image` nello stesso script: sono asincroni e rendono tutti l'ULTIMO frame
impostato (verificato: dodici immagini identiche).

Se Cascadeur è caduto, il lavoro non salvato è perso: prima di ogni giro di
resa, `scene.save(path)`.

### Salvare la scena, e non pestare quella aperta

`scene.save(path_name: str)` — un solo argomento.

⚠️ `sm.scenes()` può contenere lavoro dell'utente: **elencarle prima di
importare**. Su Arcanium la scena corrente conteneva `Lupo_Howl_AP.casc` col rig
del lupo, e importarci sopra il protagonista avrebbe mescolato due personaggi.
`sm.create_application_scene()` + `sm.set_current_scene()` costa niente;
`sm.remove_application_scene(s)` toglie quelle di prova.

`ExportOptions` ha fra l'altro: `include_animation`, `fps`, `scale_factor`,
`normalize_weights`, `weights_per_vertex_limit`, `minimize_skins_count`,
`remove_empty_nodes`, `add_stub_material_if_need`.

### L'avviso che sembra un errore

```
No object with id <NomeArmatura> was found in import data
GLB/GLTF: Import: Success
```

**È un `Warning`, e l'import è riuscito.** Cascadeur mappa le ossa su giunti e
la mesh su un oggetto; il nodo *armatura*, che nel glTF esiste ma non ha né
mesh né skin, non ha un corrispondente e viene segnalato. Verificato su un GLB
di 28 ossa: dopo quell'avviso in scena c'erano tutti e 30 gli oggetti.

Prima di rifare l'export perché "l'import è fallito", **contare gli oggetti in
scena**: se ci sono, non è fallito.

## Scene

```python
sm = app.get_scene_manager()
nuova = sm.create_application_scene()   # non tocca quella aperta
sm.set_current_scene(nuova)
print(len(sm.scenes()))
```

Utile per provare un import senza disturbare il lavoro in corso dell'utente.

## Cosa c'è dentro, per fare cosa

- **`csc.tools`** — `AutoPosingTool`, `AutoPhysicTool`, `InbetweeningTool`,
  `MirrorTool`, `AttractorTool`, `BallisticTrajectory`, `AnimationUnbakingTool`,
  `RiggingModeTool`, `RenderToFile`.
- **`csc.tools.RenderToFile`** — `take_image`, `play_to_images_sequence`,
  `play_to_video_file`: si può **guardare** il risultato, non solo misurarlo.
  Su lavoro visivo è la differenza fra sapere e credere.
- **`domain_scene()`** — `modify_with_session`, `modify_update_with_session`,
  `layers_viewer`, `model_viewer`, `selector`, `get_current_frame`,
  `set_current_frame`. È da qui che si scrivono keyframe.
- **`csc.layers`**, **`csc.rig`**, **`csc.parts`**, **`csc.physics`**,
  **`csc.additive_layers`**.

⚠️ I nomi dei metodi **non** si indovinano: `layers_viewer().layers()` non
esiste. Fare `dir()` sull'oggetto che si ha in mano prima di scrivere la riga.

## Licenza

`app.is_pro_features_available()` restituisce **False** con la licenza perpetua
Indie (mentre `app.is_export_available()` è True). Se una funzione serve,
verificare che non sia dietro quel cancello **prima** di costruirci sopra un
piano.

⚠️ Caso concreto trovato dall'utente il 2026-08-08: il **meta rig per
l'inbetweening AI sui QUADRUPEDI richiede la PRO**. Sui quadrupedi, quindi, la
funzione-firma di Cascadeur non è disponibile con questa licenza — non è una
questione di API, è proprio il gate commerciale. Per i quadrupedi serve un'altra
strada (per Arcanium: le clip del lupo si autorano con
`arcanium/tools/author_wolf_attacks.py`, che le scrive a tabella in Blender).

## Leggere e scrivere i canali di un giunto

```python
mv = dominio.model_viewer(); dv = mv.data_viewer()
giunto = [o for o in mv.get_objects() if mv.get_object_name(o) == "Hips"][0]
canali = {dv.get_data_name(i): i for i in dv.get_all_data_id(giunto)}
n = dv.get_animation_size()                 # numero di frame
v = dv.get_data_value(canali["Position"], 12)   # (DataId, frame)
```

⚠️ `get_data_value` vuole **(DataId, frame)** e **non** l'oggetto: il DataId
identifica già la coppia oggetto+canale. Passare l'oggetto dà un TypeError.

Canali utili su un `Joint`: `Position`, `Rotation`, `Local Position`,
`Local Rotation`, `Global Matrix`, `Inverse Matrix`, e la posa di riferimento in
`Model Pose Local Position` / `Model Pose Local Rotation`.

`mv.get_object_type_name(o)` dice cos'è: per un osso restituisce `Joint`.

## Scrivere un keyframe: FUNZIONA (verificato 2026-08-20)

Una vecchia nota di questa skill diceva che `set_data_value` non scriveva. Era
sbagliato: **scrive**. L'errore stava nel canale e nel tipo, non nell'API.

```python
def scrivi(me, update, scene, session):        # 4 argomenti, in quest'ordine
    me.layers_editor().set_fixed_interpolation_or_key_if_need(layer_id, frame, True)
    me.data_editor().set_data_value(data_id, frame, valore)

ok = dominio.modify_update_with_session("scrivi chiave", scrivi)
```

Prova che lo dimostra: su `LeftArm`, canale `Local Rotation`, frame 26 — prima
`0.1350 0.0828 0.7229 0.6726`, dopo la sessione `0.5000 0.5000 0.5000 0.5000`,
riletto dal `data_viewer`.

`modify_with_session(nome: str, callable) -> bool`, e la callback riceve
**`(ModelEditor, Update, Scene, Session)`**.

⚠️⚠️ **`modify_with_session` scrive ma NON ricalcola.** È la differenza che
faceva sembrare rotta la scrittura: i frame interpolati restano quelli di prima.
Usare **`modify_update_with_session`**, che ha la stessa firma e fa girare
l'aggiornamento della scena. Misurato: cambiando l'interpolazione a `LINEAR` sul
frame 30, il valore al frame 40 passa da `0.0982 0.0454 0.7287 0.6762` a
`0.0547 0.0122 0.7311 0.6799` — cioè a metà strada fra 30 e 50, come deve.

⚠️ **`Local Rotation` è un `csc.math.Rotation`, non un `Quaternion`.** Passare un
`Quaternion` a `set_data_value` non solleva nulla di utile, e rileggendo si
ottiene un oggetto senza `.x`. Conversione:
`csc.math.Rotation.from_quaternion(csc.math.Quaternion(w, x, y, z))`, e
all'indietro `rot.to_quaternion()` (i componenti restano **metodi**: `q.x()`).

⚠️⚠️ **Il costruttore vuole `w` PER PRIMO.** Verificato il 2026-09-14:
`csc.math.Quaternion(0.1, 0.2, 0.3, 0.9)` rilegge `x=0.2 y=0.3 z=0.9 w=0.1`.
Una versione precedente di questa nota diceva `(x, y, z, w)`: con quell'ordine
le componenti ruotano di un posto e ogni rotazione scritta esce girata di
~120 gradi — sulla corsa dell'arciere la faretra è finita sopra la testa. Prima
di scrivere rotazioni, fare sempre l'andata e ritorno su un quaternione noto.

⚠️ **In una scena RIGGATA i giunti non si scrivono.** `set_data_value` su
`Local Rotation` di un `Joint` torna `ok=True` ma dopo `modify_update` il valore
è quello di prima: il rig risolve i giunti dai CONTROLLI (Point, Rigid Body,
Center of Mass…). Le attachment, le dita, i toes, Spine_02/03 e il Root invece
sono giunti LIBERI e la scrittura resta. Per copiare o spostare frame si copiano
TUTTI i canali animati di tutti gli oggetti (come `pycsc` `Timeline.move_frames`);
per cambiare una posa si scrivono i controlli. I canali costanti sollevano
`RuntimeError` su `get_data_value(did, frame)`: si saltano.

⚠️ **`SystemExit` uccide il server MCP.** Non è una `Exception`: il server non la
cattura e si spegne (`RemoteDisconnected`, la porta 8765 sparisce, Cascadeur
resta vivo). Si riaccende a mano da `Script → MCP → Start MCP`. Per uscire
presto da uno script si usa un flag, mai `exit`/`SystemExit`.

**Annullare da script:** `app.get_action_manager().call_action("Scene.Undo")`
annulla l'ultima sessione (`modify_update_with_session` = un passo di undo):
è così che si torna indietro da un taglio sbagliato senza riaprire il file.
Le clip "bakeate" hanno chiavi solo al primo e all'ultimo frame con intervallo
`FIXED` (ogni frame ha i suoi valori); la timeline si accorcia togliendo le
chiavi oltre il taglio (`unset_section`) + `fit_animation_size_by_layers()`.
Il taglio con chiusura del loop è `arcanium/tools/casc_taglia_loop.py`.

⚠️ `set_fixed_interpolation_or_key_if_need` torna `False` quando la chiave
c'è già: **`False` non è un fallimento.** Su una clip importata da GLB ogni
frame è già una chiave.

⚠️ **L'animazione dei giunti vive in `Local Rotation`.** Interpolare le
`Position` globali di una gerarchia **stira le ossa**: si interpolano le
rotazioni locali. `csc.math.Rotation` ha `to_quaternion` / `from_quaternion`,
`to_euler_angles`, `from_angle_axis`, `to_rotation_matrix`.

`set_data_value` accetta anche un **insieme di frame** al posto di uno solo:
`set_data_value(data_id, {10, 11, 12}, valore)`. I tre overload sono
`(id, valore)`, `(id, frame, valore)`, `(id, set[int], valore)`.

Su `pycsc` le sessioni hanno i loro decoratori, in `pycsc.runners`:
`run_update_session`, `run_edit_update`, `run_generate_update`,
`run_update_with_session`.

**Rileggere sempre il valore prima di dichiarare fatta una scrittura.** Il
ritorno `True` della sessione non è una conferma.

## Aggiungere, togliere e spostare chiavi

Le chiavi vivono sui **layer**, non sugli oggetti: un layer raccoglie più
oggetti (`Layer.obj_ids`) e porta una mappa `posizione -> Section`. Una
`Section` è la coppia **chiave + intervallo che la segue**:

- `csc.layers.layer.Key` — `common`, `label`, `tangents`,
  `left_weight_velocity`, `right_weight_velocity`
- `csc.layers.layer.Interval` — `common`, `interpolation`,
  `description_for_ai_interpolation`

Il layer di un oggetto si trova così:

```python
lv = dominio.layers_viewer()
lid = lv.layer_id_by_obj_id(oggetto)
layer = lv.layer(lid)
layer.is_key(26)                  # -> bool
list(layer.key_frame_indices())   # tutti i frame con chiave
layer.section(30).interval.interpolation
```

E si scrive dentro una sessione, via `me.layers_editor()`:

| Operazione | Chiamata |
|---|---|
| aggiungere una chiave | `set_fixed_interpolation_or_key_if_need(lid, frame, True)` |
| **togliere** una chiave | `unset_section(frame, lid)` |
| scrivere chiave + interpolazione | `set_section(section, frame, lid)` |
| riscrivere tutte le chiavi | `set_sections({frame: Section, ...}, lid)` |
| modificare in loco | `change_section(frame, lid, callable)` |
| **spostare** una chiave | `unset_section(vecchio)` + `set_section(sec, nuovo)` |

Verificato: tolte le chiavi 31→49 su `LeftArm`, `key_frame_indices()` è passato
da `[…25,26,27,28,29,30,31,…]` a `[25,26,27,28,29,30,50,51,…]`.

⚠️ **Non esiste un `move_section`**: lo spostamento è togli-e-rimetti. Leggere
la `Section` vecchia *prima* di toglierla, altrimenti si perdono tangenti e
label.

⚠️ `set_section` vuole una `Section` **costruita**, non quella restituita dal
viewer modificata in loco:

```python
sec = csc.layers.layer.Section()
sec.key = layer.key(30)                       # la chiave esistente si riusa
iv = csc.layers.layer.Interval()
iv.interpolation = csc.layers.layer.Interpolation.AI
sec.interval = iv
me.layers_editor().set_section(sec, 30, lid)
```

## L'interpolazione AI è un TIPO DI INTERVALLO, non un comando

Questa è la scoperta che ribalta la vecchia nota "non si può lanciare l'AI".
Non c'è nessuna funzione `run_ai_interpolation()` — **c'è un valore di enum**:

```python
csc.layers.layer.Interpolation   # NONE STEP LINEAR BEZIER CLAMPED_BEZIER
                                 # LOW_AMPLITUDE_BEZIER FIXED AI
csc.layers.layer.Interpolation.AI   # == 7, verificato dal vivo
```

Si assegna all'`Interval` della sezione che precede il tratto da riempire, e
c'è pure il campo testuale che la GUI chiama "descrizione":
`interval.description_for_ai_interpolation` (scritto `"collapse"`, riletto
`"collapse"`).

⚠️ **Impostare `AI` non basta a farla girare.** Misurato sulla clip
`player_poison_death` importata da GLB: con `LINEAR` il frame 40 si ricalcola,
con `AI` resta identico al valore lineare. Lo scheletro importato **non ha il
rig di Cascadeur** (niente `RigInfo`, niente centri di massa): l'interpolazione
AI lavora sul personaggio riggato, non su una gerarchia di giunti nuda. Prima di
aspettarsi un risultato, costruire il rig (vedi sopra: al 2026-08-20 da API non
ci siamo ancora riusciti) — e ricordare che sui quadrupedi il metarig è dietro
il gate PRO.

## La fisica su un tratto solo: "Work on interval"

**Si fa, ed è una spunta.** In **Physics settings** c'è **"Work on interval"**
(nei binari: `auto_physics::tool::settings::physics_settings::SettingWorkOnInterval`,
un bool). Con quella accesa, il bake lavora sull'intervallo invece che su tutta
la clip. Si accompagna alle **physics priority frames**: si sceglie il frame con
la posa — dev'essere una chiave — e si preme *Set physics priority frame*; nel
modello è `AutoPhysics.priority_frame`, un **bool per frame** sul Centro di
massa.

⚠️ `app.get_setting_manager()` (al **singolare**) espone solo getter
(`get_bool_value`, `get_float_value`, `get_color_value`) e **non serve a
sondare**: a una chiave che non conosce risponde `False` invece di protestare,
quindi non si distingue "spento" da "non esiste". Le impostazioni della fisica
si mettono dalla GUI.

### ⚠️ Quello che NON limita il bake, e che sembra doverlo fare

Prima di arrivarci sono state provate e misurate tre strade sbagliate. Restano
qui perché sono tutte plausibili:

1. **`AutoPhysics.frame_weight`** è il **peso** con cui la fisica si mescola
   all'animazione, non un interruttore per il comando. Messo a 0 fino al 111 e
   a 1 dal 112, il bake è ripartito lo stesso dal primo frame.
2. **La selezione della timeline** viene ignorata, anche impostata da script e
   riletta dalla scena per esserne certi.
3. **`only keys`** prende *tutte* le chiavi, comprese quelle autorate a mano.

Come si scrive comunque il peso, che serve a sé — l'overload con l'**insieme
di frame** non aggiunge nessuna chiave di posa:

```python
fw = pycsc.wrap(dominio).bv.get_behaviours("AutoPhysics")[0].frame_weight
did = fw.get_id().handle                       # ⚠️ pycsc lo restituisce avvolto
def s(me, update, scene, session):
    me.data_editor().set_data_value(did, set(range(112, 191)), 1.0)
dominio.modify_update_with_session("peso fisica", s)
```

⚠️ Scriverlo frame per frame **creando le chiavi** non funziona: il valore vive
solo *sulle* chiavi e in mezzo torna a zero (misurato: f112 = 1,00, f113 = 0,00).

### ⚠⚠ Il tasto `R` blocca i controller — e sembra un osso stirato

Con dei controller selezionati, **`R` li blocca**: restano inchiodati dove sono
mentre il resto simula. I segmenti diventano **rossi**, e il rosso in Cascadeur
vuol dire "la distanza fra i controller si scosta dalla lunghezza dell'osso" —
che si legge come una deformazione e manda a cercare il difetto nelle rigidita'.
Non lo e': si preme `R` di nuovo.

Come distinguerli in un colpo: **misurare le lunghezze d'osso**. Se ogni
segmento sta a `+0,0%` dal riposo su tutti i frame, lo scheletro non e' toccato
e il problema sta nei controlli. Vedi `game-animation-craft`.

### Le manopole della ragdoll

Stanno su 43 behaviour `Ragdoll`, uno per controller, e si scrivono per
intervallo come il peso:

| dato | default | cosa fa |
|---|---|---|
| `local_stiffness` | 9,0 | quanto il punto resta attaccato alla posa autorata |
| `local_damping` | 20,0 | quanto frena |
| `global_stiffness` / `global_damping` / `global_pin` | 0,0 | vincoli in spazio mondo |
| `muscle_friction`, `air_friction` | 0,0 | attriti |

⚠️ Su un *point controller* `local_stiffness` è **posizionale**: tiene il punto
fermo, non la rotazione. Valori disomogenei lungo una catena (mano a 9,
avambraccio a 0) tirano l'osso in mezzo da due parti.

⚠️ Scrivere questi valori **non fa girare la simulazione**: quella la lancia il
bake dalla GUI, e nei binari non c'è nessuna chiave d'azione per farlo da
script.

## ⚠⚠ Una posa non si descrive con le posizioni dei suoi controller

La tentazione successiva è: lascia che il bake rovini tutto, poi riscrivi le
pose autorate. **Non funziona.** Registrati tutti i 48 controller
(`Point`, `Limb Direction`, `Center of Mass`) alle chiavi e riscritti nella
stessa scena, il corpo è tornato **fino a 37 cm** diverso dall'originale.

Il motivo: i controller sono **interdipendenti**, e scriverli tutti insieme dà
una soluzione del rig diversa. I peggiori sono quelli derivati —
`Head_DirectionPoint` sbagliava di 38 cm, `LeftLowerArm_LimbDir` di 23 — ma
sbagliano anche i `MainPoint`. **Una posa di Cascadeur non si descrive con le
posizioni dei suoi controller.**

### Preparare una scena da AUTORARE: le chiavi si tengono, non si riscrivono

Per dare all'animatore due pose identiche agli estremi (partenza e arrivo
uguali a un idle, così la clip nuova vi si attacca da tutte e due le parti):

1. **la posa ferma si prepara FUORI** (in Blender: la posa del primo fotogramma
   tenuta per N frame, campionata frame per frame);
2. la si importa e la si rigga;
3. in Cascadeur si **tengono** solo le chiavi del primo e dell'ultimo frame,
   così come il rig le ha cotte, con `set_sections({0: sez, FINE: sez}, lid)`
   su ogni layer (la `Section` costruita con `s.key = layer.key(f)` e intervallo
   `BEZIER`), poi `fit_animation_size_by_layers()`.

⚠️ La strada ovvia è sbagliata: copiare dentro Cascadeur, canale per canale, i
valori del frame 0 sull'ultimo frame. Verificato il 2026-09-26: `ok=True`, 2941
canali scritti, e le mani spostate di **50 cm** — è la stessa ragione della
sezione sopra, i controlli si risolvono l'uno con l'altro.

Il collaudo: posizione dei giunti al primo, a metà e all'ultimo frame, che deve
coincidere al millimetro. E prima di rifare una scena che esiste già, guardare
che non ci siano chiavi oltre le due degli estremi: vorrebbe dire che
l'animatore ci ha già lavorato.

La mesh, in Cascadeur, è solo un'anteprima: quello che torna nel motore è la
clip (le ossa). Il formato e la topologia della mesh importata non cambiano il
risultato.

⚠️ `take_image` dal ponte, il 2026-09-26, non ha prodotto il file nemmeno dopo
parecchi secondi: la finestra era minimizzata (vedi la sezione `RenderToFile`
sopra — basta ripristinarla). Misurare dalla scena resta il controllo primo; la
foto serve a vedere quello che i numeri non dicono.

### Pose chiave NUOVE: FK sui giunti senza rig, poi il rig le cuoce (2026-10-23)

La via che ha funzionato per l'idle di Edran, e il perche' delle alternative:

1. **Scrivere i controlli del rig non basta.** Le braccia del biped sono IK:
   `Hand_MainPoint` resta dove lo scrivi, ma gomito (`Elbow_*Point`,
   `Elbow_LimbDir`) e orientamento della mano (`Hand_DirectionPoint`,
   `Hand_AdditionalPoint`) li ricalcola il rig — riletti fuori di 8-32 cm, e
   la lama ferma dov'era. (`arcanium/tools/casc_posa_controlli.py`, tolto.)
2. **Senza rig i giunti sono liberi**: `arcanium/tools/casc_pose_fk.py` gira
   i giunti in FK, con mire su una direzione o un asse di un'arma agganciata,
   rollio, IK a due ossa e «punta la lama sul bordo dello scudo» letto dalla
   scena. Le pose stanno in un generatore Python
   (`arcanium/animazioni/idle_campioni/idle_<nome>.py`). Dal 2026-10-26 anche
   le GAMBE (Rashan che molleggia sui talloni): `sposta` sul bacino, l'IK
   della gamba con `ruota_attorno` la pianta (il tallone si alza), le mire
   `verso_al_posto` che tengono pianta e dita a terra, e `come_base` che
   rimette un osso con l'orientamento globale della posa ferma (braccia e
   lama che non seguono il busto quando gira). Misurato dopo il bake:
   caviglia su di 3 cm, pianta e dita ferme entro 1 mm.
3. Si esporta il GLB, `casc_rigga_personaggio.py` ci costruisce il rig (il
   bake traduce i giunti nei controlli: polso destro riletto al millimetro),
   `casc_estremi_clip.py` con `chiavi_da_tenere.txt` tiene solo le chiavi
   delle pose, BEZIER in mezzo.

⚠️⚠️ **`modify_update_with_session` non ricalcola i canali GLOBALI su tutti
i frame.** Al frame 110, con la timeline a 90, la `Local Rotation` scritta
c'era e `Rotation`/`Position`/`Global Matrix` restavano vecchie: la mira dopo
leggeva una posa sbagliata. `set_current_frame` dentro lo script non serve
(vale a script finito). Si chiede il ricalcolo dentro la sessione: il terzo
argomento della callback e' lo `SceneUpdater`, e
`updater.run_update({DataId, ...}, frame)` lo fa.

⚠️ **La torsione dell'avambraccio non sopravvive al bake del rig.** Lo scudo
girato torcendo il gomito usciva ruotato di 25 gradi: si gira col POLSO
(`Hand_L`), che il rig conserva. Resta un piccolo scarto anche cosi' (8 gradi,
3 cm): si misura nella scena riggata e si compensa nelle pose.

⚠️ **Le armi agganciate rientrano dal GLB riesportato STACCATE e riscalate**
(lo scudo gigante nell'origine). `casc_arma_su_osso.py` non le riusa: si
cancellano e si riagganciano. ⚠️ `ModelEditor.delete_objects` in una
`modify_update_with_session` fallisce con `flat_map::at key not found`; la
cancellazione che funziona e' quella della GUI:
`common.delete_objects.delete_model_objects(domain_scene, {ObjectId, ...})`
(sessione `modify_update` a tre argomenti, poi `generate_update` e
`run_update`).

### In alternativa: tagliare la clip

Quando "Work on interval" non basta — o quando il tratto va lavorato per conto
suo — si può non fargli mai vedere la parte da proteggere. Si ritaglia il solo tratto da
simulare in un GLB a sé (`arcanium/tools/taglia_clip.py`), gli si costruisce il
rig, si lancia il bake su **tutta** quella clip corta — non c'è più niente da
rovinare — e poi si ricuce in Blender, dove il taglio è deterministico e
misurabile. Conviene ritagliare qualche frame di **rincorsa** prima dell'inizio
vero, così la fisica parte dalla posa autorata invece che da ferma.

⚠️ Il giro import + rig + uscita dalla rig mode su una clip lunga può far
**cadere la connessione del ponte** (`RemoteDisconnected`) mentre Cascadeur
continua a lavorare: la scena resta in rig mode, con gli elementi `Proto *`
creati e `RigInfo = 0`. Non è un fallimento — si finisce con
`rig_mode.off.run(dominio, True)` in una chiamata a parte.

## AutoPhysics: qui il muro c'è davvero

Questo pezzo della vecchia nota **regge**, e la doc ufficiale 2026.2 lo conferma
riga per riga:

- `csc.tools.AutoPhysicTool` espone **solo** `turn_off` e
  `turn_off_all_fulcrum_points`. Nessun "apply".
- `csc.tools.AutoPosingTool` espone **solo** `add` e `update`.
- **`InbetweeningTool` non compare nella doc** 2026.2 (`csc.tools` elenca 32
  classi e non c'è), ma **a runtime esiste**: si prende con
  `get_tool("InbetweeningTool").editor(scena)` ed espone solo
  `get_update_parameter` e `set_update_parameter` — si regolano i parametri,
  non si lancia. Morale: la doc è incompleta, `dir()` sulla scena viva vale di
  più.
- In `pycsc`, `AutoPhysics`, `AutoPhysicsApply`, `PhysicsCorrector`,
  `SecondaryMotion`, `Ragdoll`, `CompensationMotion` **non sono funzioni**: sono
  classi *behaviour*, con `add_data_to_range`, `creator`, `editing`, `dv`, `bv`.
  Si attaccano agli oggetti e la scena si aggiorna. Pilotarle significa lavorare
  sul grafo dei behaviour, non fare una chiamata.

⚠️ **Diffidare degli snippet inventati.** Girano riassunti della API che
suonano plausibili e non esistono: `csc.app.Application.instance()`,
`app.scene()`, `app.tools_manager()`, `tools_manager.auto_physic_tool()`,
`scene.layers()`, `layers.editor()`. **Nessuno di questi esiste.** I nomi veri
sono `csc.app.get_application()`, `app.current_scene()`,
`app.get_tools_manager()` (che ha solo `get_tool` e `tools`),
`scene.domain_scene()`, `domain_scene().layers_viewer()` e — dentro una
sessione — `model_editor.layers_editor()`.

## La doc ufficiale si può scaricare e leggere per intero

Vale più di qualsiasi riassunto: <https://cascadeur.com/python-api/csc.html> è
una pagina sola da ~2,6 MB con **tutte** le firme, e ogni classe ha la sua
pagina in `_generate/<nome-classe>.html`.

```bash
curl -sSL -o csc.html https://cascadeur.com/python-api/csc.html
grep -o 'href="_generate/[^"]*\.html"' csc.html | sed 's/.*generate\///;s/\.html"//' | sort -u
```

Le firme complete degli overload stanno nel testo della pagina: cercare il nome
del metodo dà direttamente `nome(self: Classe, arg: tipo) -> ritorno`. È più
veloce e più sicuro del trucco del `TypeError`.
## ⚠️ L'importer GLB non legge CUBICSPLINE

Sintomo: `process_import` muore con

    RuntimeError: unexpected times & values count: 14 vs 42

Il rapporto è sempre **1 a 3**: glTF CUBICSPLINE salva per ogni chiave la terna
`(tangente entrante, valore, tangente uscente)`, e Cascadeur si aspetta un
valore solo. Blender esporta CUBICSPLINE **ogni volta che le curve hanno le
tangenti**, cioè quasi sempre se non si spunta "Always Sample Animations".

Rimedio nel progetto: **`tools/glb_cubicspline_to_linear.py`**. Non appiattisce
la curva — valuta la spline di Hermite a ogni frame, quindi il movimento che
arriva in Cascadeur è quello autorato, non una spezzata fra le chiavi:

```bash
python tools/glb_cubicspline_to_linear.py ingresso.glb uscita.glb --fps 30
```

Lo stesso script, importato come modulo, sa anche solo diagnosticare: apre il
GLB e conta gli `interpolation` dei sampler. Misurato su
`player_poison_death.glb`: 25 sampler CUBICSPLINE, 14 chiavi → 191 frame,
import riuscito.

⚠️ L'avviso `No object with id BaseArmature was found in import data` che
compare dopo è **innocuo**: l'oggetto `Transform` radice esiste comunque nella
scena importata.

## Lanciare i comandi della GUI: `ActionManager.call_action`

Questa è la leva che mancava per il lavoro E2E. Ogni voce di menu di Cascadeur
ha una **chiave** testuale, e si chiama così:

```python
csc.app.get_application().get_action_manager().call_action("View.FixFoot")
```

⚠️⚠️ **`call_action` non solleva MAI e non torna nulla.** Verificato: una chiave
inventata (`"Chiave.Inventata"`) passa liscia esattamente come una vera, e non
esiste modo di enumerarle a runtime. **L'unica prova che un'azione abbia fatto
qualcosa è misurare la scena prima e dopo.**

Le chiavi non stanno in nessun file di configurazione: sono compilate dentro i
binari, e si estraggono da `C:\Program Files\Cascadeur` cercando nelle DLL le
stringhe che rispettano `Prefisso.Nome con spazi`. Quelle utili all'animazione,
già estratte:

| Chiave | Cosa fa |
|---|---|
| `AutoPosingTool.AutoPosing` | esegue AutoPosing |
| `AutoPosingTool.Update` | aggiorna la posa |
| `AutoPosingTool.SwitchLock` / `SwitchLockOnInterval` | blocca i controller |
| `AutoPosingTool.AutoUnlock` | sblocca |
| `View.AutoInterpolation_Keys` | interpolazione automatica sulle chiavi |
| `View.Inbetweening_` | pannello Inbetweening |
| `View.FixFoot` / `View.FixFoot_KeepKeyFrames` | correzione piedi |
| `View.FixCollisions` | correzione compenetrazioni |
| `View.Animation unbaking` | unbake |
| `View.Retargeting_` | retargeting |
| `View.MocapTool` | mocap |
| `Dialog.Quick Rigging Tool` / `Dialog.Generate rig` | finestre del rigging |
| `Scene.Undo` / `Scene.Redo` | annulla / ripeti |
| `MirrorTool.Mirror pelvis position` | specchia il bacino |
| `Commands.Reload scripts` | ricarica gli script |
| `MCP.Start script server` / `MCP.Stop script server` | il server di questo ponte |

⚠️ `Dialog.*` **apre una finestra**: in una sessione pilotata da agente resta lì
ad aspettare un umano. Da evitare, salvo che non sia l'utente a chiuderla.

## Il rig: associare le ossa del metarig SI PUÒ, dall'API

Sì, si fa tutto da Python — è la parte che rende possibile il lavoro E2E.
Il tool si prende **per nome**, e il nome è `RiggingToolWindowTool`:

```python
app = csc.app.get_application()
rw = app.get_tools_manager().get_tool("RiggingToolWindowTool").editor(app.current_scene())
# -> csc.tools.RiggingWindow
```

| Metodo | Uso |
|---|---|
| `create_from_qrt_by_fileName(path)` | costruisce il rig da un template `.qrigcasc` |
| `create_from_qrt_by_content(json_str)` | idem, ma con il JSON in memoria |
| `load_template_by_fileName(path)` / `load_template_by_content(str)` | carica la sola mappatura, senza costruire |
| `get_template_from_qrt()` | rilegge il template della scena corrente, come stringa |
| `generate_rig_elements()` | genera gli elementi del rig |
| `set_is_create_autoposing(bool)` / `get_is_create_autoposing()` | se creare anche l'AutoPosing |
| `set_character_mirror_plane(int)` / `get_character_mirror_plane()` | piano di simmetria |
| `set_axis_after_qrt(int)` | asse dopo il QRT |
| `open_quick_rigging_tool()` | apre la finestra (⚠️ blocca) |

⚠️ Il nome del tool **non** è `RiggingWindow`: `get_tool("RiggingWindow")`
torna `None` senza lamentarsi. Vale in generale — `get_tool` con un nome
sbagliato dà `None`, non un errore. I nomi veri si leggono così:
`[t.name() for t in app.get_tools_manager().tools()]` (56 tool; `RenderToFile`,
`DataSourceManager` e `FbxSceneLoader` non hanno `.name()` e vanno protetti).

### ⚠⚠ I template pronti NON vanno bene: contali prima di sperarci

In `C:\Program Files\Cascadeur\resources\autorig_templates\` ce ne sono 20, e
la tentazione è scegliere quello dal nome giusto. **Misurato sui giunti di
`protagonista_v4.glb` il 2026-08-20: `blender_autorig_pro.qrigcasc` fa 0 su
51.** Quel file mappa i **controlli** di ARP (`c_root_master.x`, `c_traj`,
`c_spine_01.x`), non le ossa che ARP *esporta*; il nostro GLB porta la
convenzione Nephilite (`Hips`, `Spine`, `Chest`, `UpperChest`,
`LeftUpperArm`...). Il migliore è `Mixamo_No_Namespace_Template_New` con 10
nomi su 21, e sono solo quelli che le due convenzioni hanno in comune.

Il conto si fa in dieci righe, e va fatto **prima** di costruire un piano:
leggere i `"Joint name"` di ogni `.qrigcasc` e intersecarli con i nomi dello
skin del proprio GLB. Per Arcanium il template se lo genera
`arcanium/tools/genera_qrt_cascadeur.py`, che legge la gerarchia dal GLB invece
di scrivere i percorsi a mano.

L'elenco di quelli che ci sono, per sapere cosa si sta scartando:

    blender_autorig_pro  (i CONTROLLI di ARP, non le sue ossa: 0 su 51)
    Blender_rig_fingers  Blender_Sample_Template_New
    Mixamo_Namespace_Template_New  Mixamo_No_Namespace_Template_New
    UE4_New  UE5  Metahuman  CC3_char  Daz3d_Gen8  Daz3d_Gen9
    meshy  MoveAI  Rokoko  Playerme  Cascy  Chibi  standard  Quadruped

Il formato è JSON in chiaro, e la mappatura si legge a occhio:

```json
{ "Document": [ { "Title": "Body", "Sections": [ { "Section": "Body", "Names": [
  { "Bone name": "pelvis",
    "Joint name": "c_root_master.x",
    "Joint path": ["c_pos", "c_traj"] },
  { "Bone name": "stomach",
    "Joint name": "spine_01.x",
    "Joint path": ["c_pos", "c_traj", "c_root_master.x", "c_spine_01.x"] }
] } ] } ] }
```

`Bone name` è il nome **del metarig di Cascadeur** (fisso: `pelvis`, `stomach`,
`chest`, `neck`, `head`, …); `Joint name` e `Joint path` sono il giunto **nella
tua scena** e la sua gerarchia. Per un rig diverso da ARP si copia il file più
vicino e si riscrivono `Joint name` / `Joint path`.

### Il flusso che porta al rig — e dove si inceppa

L'ordine conta, ed è questo (verificato dal vivo il 2026-08-20):

```python
import rig_mode.on as rm_on
import rig_mode.off as rm_off

# 1. importa il GLB (mesh + scheletro + clip)
# 2. ENTRA IN RIGGING MODE: senza, il QRT muore subito
rm_on.run_raw(dominio, [0.0, 0.5, 0.0])
# 3. il template
rw = app.get_tools_manager().get_tool("RiggingToolWindowTool").editor(vs)
rw.set_is_create_autoposing(True)
rw.create_from_qrt_by_fileName(percorso_qrigcasc)
# 4. a lavoro finito, esci dalla rig mode
rm_off.run(dominio, True)
```

⚠⚠ **Il passo 2 non è facoltativo.** Senza rig mode il QRT esce con
`Exception: Rig mode several animationInfo` da `_qrt.py`, che vuol dire il
contrario di quello che sembra: `add_qrt_json` pretende **esattamente un**
behaviour `AnimationInfo`, e su una scena appena importata ce ne sono **zero**.
È `rig_mode/on.py:288` a crearlo. Si conta così:

```python
len(pycsc.wrap(dominio).bv.get_behaviours("AnimationInfo"))   # dev'essere 1
```

La ricetta sta nel campione ufficiale
`resources/scripts/python/samples/casc_import_export.py`, che fa
carica → `rm_on.run_raw` → `rm_off.run` → esporta. **Guardare in `samples/`
prima di ricostruire un flusso per tentativi**: ce ne sono 14.

⚠️ `open_quick_rigging_tool()` **NON blocca**: apre una finestra agganciata e lo
script prosegue. (Le voci `Dialog.*` di `call_action` invece sì.)

⚠️ Il nome del tool è `RiggingToolWindowTool`, e `get_tool("RiggingWindow")`
torna `None` **senza lamentarsi**.

### Le ossa di TORSIONE si possono dichiarare (ma spesso non serve)

Il QRT ha un documento apposta, `"Title": "Twist bones"`, con voci che portano
anche `Strength` e `Axis`:

```json
{ "Bone name": "forearm_l", "Joint name": "LeftLowerArm_twist_01",
  "Joint path": ["Root","Hips","Spine","Chest","UpperChest",
                 "LeftShoulder","LeftUpperArm","LeftLowerArm"],
  "Strength": 0.8, "Axis": 0 }
```

`Bone name` è il campo del metarig del **genitore**, non del twist. `Strength`
= quanto il twist segue il figlio invece del padre: nei template di Cascadeur i
twist vicini a spalla e anca stanno a **0.0**, quelli dell'avambraccio a
**0.8** (li torce la mano).

⚠️ **Non è obbligatorio**, e all'inizio avevo creduto il contrario: i messaggi
`Twist X: could not find parent or child joint ids` sono una **conseguenza** del
fatto che non si era legato niente, non la causa. Il template estratto da un rig
funzionante sul nostro stesso scheletro non ha affatto il documento
`"Twist bones"`.

Resta utile saperlo perché nel nostro rig i twist stanno a offset **(0,0,0)** dal
padre — lunghezza zero, stessa posizione dell'osso vero — e in altri contesti
un twist non dichiarato si traveste da osso vero.

### ⚠️ `Can't find required nodes: ['arm_r', 'arm_l']` — cosa vuol dire davvero

Il biped dichiara `get_required_nodes() -> {ARM_L, ARM_R}`
(`prototypes/rigs/qrt/biped/_biped.py`). Quindi **quel messaggio non dice che
mancano solo le braccia**: dice che il controllo dei nodi obbligatori è
fallito, e siccome gli obbligatori sono due, di due parla. Se compare insieme a
`Twist ...: could not find parent or child joint ids` per **tutte** le
torsioni, la lettura giusta è che **nessun giunto si è legato**, non che ne
manchino due.

Chi lega non è `_fix_qrt_joints`: quella funzione ricontrolla soltanto i legami
già fatti — `if not bone_property.object_id.is_null():` — e su un template
appena caricato da file gli `object_id` sono nulli, quindi li salta tutti.

⚠⚠⚠ **`create_from_qrt_by_*` NON LEGA I GIUNTI. È questa la trappola.**

Legge il template — `get_template_from_qrt()` lo rilegge intero e giusto — ma
gli `object_id` delle `BoneProperty` restano **nulli**, e il rig non nasce mai.
Falliscono allo stesso modo: la chiamata da sola, con la rig mode accesa, con
`load_template_by_fileName` + `generate_rig_elements`, con la finestra aperta,
e con tutti i giunti selezionati.

E **non è colpa del template**: il nostro è stato reso identico byte per byte a
quello estratto dal `qrt_json` di un personaggio già riggato bene sullo stesso
scheletro, e falliva uguale.

**La via che funziona: costruire il `csc.rig.QrtData` a mano** e chiamare la
pipeline Python direttamente.

```python
import prototypes.qrt_prototypes.create as qrt_create

q = csc.rig.QrtData()
q.is_align_pelvis = True
q.is_create_layers = True
corpo = []
for sez in sezioni_body_del_template:
    gruppo = []
    for voce in sez["Names"]:
        oid = per_nome[voce["Joint name"]]          # il giunto VERO della scena
        bp = csc.rig.BoneProperty()
        bp.bone_name = voce["Bone name"]
        bp.object_id = oid                          # <-- il passo che manca
        bp.joint_path_name = csc.model.PathName.get_path_name(oid, mv)
        gruppo.append(bp)
    corpo.append(gruppo)
q.body = corpo                                      # lista di LISTE, una per sezione

qrt_create.create_rig_elements_by_qrt(dominio, q, 10.0, 10.0, [0.0, 0.5, 0.0], testo_json)
```

Misurato il 2026-08-21 su `protagonista_v4`: **65 → 222 oggetti** in rig mode
(21 Rig Element, 21 Proto Box, 44 Proto Point, 21 Proto Rigid Body), poi
`rig_mode.off.run(dominio, True)` cuoce il rig vero — **255 oggetti** con
21 Box, 43 Point, 21 Rigid Body, 1 Center of Mass, 4 Limb Direction, 52 Edge e
`RigInfo = 1`. Il giro completo sta in
`arcanium/tools/casc_rigga_personaggio.py`.

⚠️ Verificare sempre che `q.body = corpo` sia **rimasto**: passa per pybind, e
un valore che non tiene ridarebbe lo stesso identico `Can't find required nodes`.

⚠️ **L'uscita dalla rig mode ritocca l'animazione.** Escono centinaia di
`Local rotation of X has changed after rig generation in frame N` — su tutte le
ossa. Non è un errore, ma il gesto va **rimisurato** prima di lavorarci sopra.
Misurato sulla morte per veleno: bacino 101,4 → 90,7 cm, testa 170,7 → 88,4,
mano a 8,4 cm dal collo al frame 48. Sopravvissuto.

### Il trucco che sblocca tutto: rubare il `qrt_json` a un rig che funziona

Se in giro c'è un personaggio già riggato bene, il suo template esatto è dentro
di lui, e si legge:

```python
b = pycsc.wrap(dominio).bv.get_behaviours("RigInfo")[0]
print(b.get_property_names())      # ... proto_json, qrt_json ...
testo = b.get_string("qrt_json")   # il template, 4-5 KB
```

⚠️ Si legge con **`b.get_string(nome)`** sull'oggetto avvolto da `pycsc`, non
con `behaviour_viewer().get_behaviour_string(...)`, che rifiuta gli argomenti.

È la fonte migliore che esista per capire che forma deve avere un template per
il **proprio** scheletro, e ha risolto in un colpo la domanda "cosa manca al
mio". Nel caso nostro mancava il blocco di radice

```json
"Settings": { "Is align pelvis": true, "Is create layers": true }
```

— e in compenso il documento `"Twist bones"` che avevo aggiunto **non serviva
affatto**: il template funzionante non ce l'ha.

### La via strutturata: `csc.rig.QrtData`

Se il template va costruito a programma invece che da JSON:

```python
b = csc.rig.BoneProperty()   # bone_name, joint_path_name, object_id, required_field
q = csc.rig.QrtData()        # body, left_hand, right_hand, quadruped, twists,
                             # untwists  (liste, vuote all'inizio)
                             # is_align_pelvis, is_create_layers,
                             # is_replace_existing, is_spline_ik,
                             # hinge_arm_direction, hinge_leg_direction
```

più `TwistBoneProperty` (`bone_name`, `twist_properties`), `TwistProperty`
(`joint_path_name`, `object_id`, `twist_axis`, `twist_strength`,
`autocompute_strength`), `UntwistBoneProperty` e `QuadrupedBoneProperty`
(`trunk`, `left_fore_paw`, `right_fore_paw`, `left_hind_paw`,
`right_hind_paw`).

Il consumatore è nei sorgenti di Cascadeur:

```python
# resources/scripts/python/prototypes/qrt_prototypes/create.py
create_rig_elements_by_qrt(scene, csc_data, default_add_length,
                           default_dir_length, point_color, qrt_json)
create_biped_rig(...)      # stessa firma
create_quadruped_rig(...)  # vuole csc_data.quadruped non vuoto
```

⚠️ `create.py` fa `_fix_qrt_joints`, che **riassocia da solo** i giunti: prima
prova a far combaciare la gerarchia, poi ripiega sul nome semplice ignorando il
namespace. Un `Bone name` che non trova nulla finisce in
`print(f"Found bad joint:Print {error_names}")` — cioè nel log, **non** in
un'eccezione. Dopo il rig, ricontare i giunti mappati.

### `RiggingModeTool`: leggere e scrivere l'associazione

```python
rm = app.get_tools_manager().get_tool("RiggingModeTool").editor(app.current_scene())
rm.get_joints_data()      # dict: object_id -> dati del giunto
rm.set_joints_data(...)   # anche erase_joints_data
rm.get_layers_ids() / set_layers_ids() / erase_layers_ids()
rm.get_preserved_data() / set_preserved_data() / get_preserved_setting()
rm.set_undo_redo_context(...)
```

`get_joints_data().keys()` è il modo che usa Cascadeur stesso per sapere quali
oggetti della scena sono giunti riggabili.

## I sorgenti Python di Cascadeur sono in chiaro — leggerli

617 file in `C:\Program Files\Cascadeur\resources\scripts\python\`. È la
fonte più affidabile che esista: non è documentazione, è il codice che gira.

    prototypes/qrt_prototypes/{create,converters,struct}.py   il rigging da QRT
    prototypes/rigs/qrt/{biped,quadruped,layers}.py           i rig veri
    prototypes/add_rig_elements_actions/                      elementi del rig
    commands/                                                 i comandi Python del menu
    scripts/mcp/script_server/README.md                       questo ponte
    AGENTS.md                                                 note per agenti

Un comando del menu è un modulo con `name()`, `description()` e `run(scene)`:
`python_actions_rule.py` percorre il package `commands` e li registra. Per
aggiungere un comando nostro basta metterlo lì.

## ⚠️⚠️ `ok: true` NON vuol dire che ha funzionato

Sta scritto nel README del server, ed è la trappola peggiore del ponte: le
chiamate `pyscene.edit(...)` / `scene.modify*(...)` possono fallire — con
l'eccezione finita nel log eventi — mentre il tool riporta comunque `ok: true`.

`modify*` torna **`False`** quando la callback è esplosa. Quindi:

1. controllare sempre il valore di ritorno di `modify*`;
2. se è `False`, leggere la coda di
   `%LOCALAPPDATA%\Nekki Limited\Cascadeur\logs\cascadeur_log.log`, dove
   c'è il traceback Python;
3. e comunque **rileggere dalla scena** il valore che si è scritto.

Negli script sono già in scope `scene`, `csc` e `app`, e partono al prossimo
evento `scene_idle`.

## Il metarig quadrupede: cosa serve davvero

Il template esiste già (`resources/autorig_templates/Quadruped.qrigcasc`,
9,5 KB) e `csc.rig.QrtData.quadruped` lo accetta: quello che manca è il
permesso, non il dato.

L'auto-rigging quadrupede è dietro il gate PRO, ma **costruire il rig a mano è
lecito anche con la Indie**. Se l'inbetweening dà
`point not found: foot_self_l`, mancano i PUNTI del rig fisico, non lo scheletro.
Si legge dal behaviour `RigInfo` (proprietà `proto_json` e `qrt_json`):

- `proto_json` → `JointsLocalData`: la mappatura dei giunti. Se c'è, lo
  scheletro è a posto.
- `"IsCreateAutoPosing": false`, `"CMs": []`, `"Units": []` → il rig fisico non
  è mai stato generato: niente centri di massa, niente punti d'appoggio.
- `qrt_json` **vuoto** → manca il tipo di rig. E un nome di punto come
  `foot_self_l` è **bipede**: su un quadrupede sarebbero le zampe
  (`csc.rig.QuadrupedBoneProperty`: `trunk`, `left_fore_paw`, `right_fore_paw`,
  `left_hind_paw`, `right_hind_paw`). Se chiede un piede da bipede, il rig è
  stato creato col template sbagliato.

## Root motion: cosa aspettarsi da una clip importata

Su Arcanium la convenzione Godot è `root_motion_track = "%GeneralSkeleton:Root"`
— **un osso chiamato `Root`**, che ARP produce al suolo per gli umanoidi.

⚠️ Verificare **se la traslazione esiste** prima di progettare un'estrazione.
Sulla clip `bite` del lupo la `Position` del bacino era **costante su tutti i 41
frame**: il morso avviene sul posto. Non c'era niente da spostare su un osso
radice — il movimento va **scritto**, non estratto.

⚠️ Il rig del lupo **non ha** un osso `Root` (la sua radice è `Hips`, 28 ossa).
Aggiungere l'osso è lavoro da Blender, non da Cascadeur. Puntare
`root_motion_track` direttamente su `Hips` funziona ma costa il beccheggio del
bacino, che Godot consuma come movimento invece di mostrarlo: è la ragione per
cui esiste un osso radice dedicato a terra.

## Risorse MCP esposte

Oltre a `run_script`, il server espone due risorse leggibili:
`cascadeur://docs/python-api` e `cascadeur://modules` (moduli importabili e
nomi di primo livello). `cascadeur://modules` è il punto di partenza giusto per
orientarsi.

## ⚠️ Lupo (rig quadrupede costruito a mano): la coda e gli annulla (2026-10-15)

- La CODA del rig quadrupede e' una catena a **swing**: i suoi punti hanno
  `Swing Global/Local Rotation` animate, e `Position` e' DERIVATA. Scritta da
  script, `Position` non cambia niente (nemmeno con `modify_with_session`), e
  lo swing scritto sui tre assi non ha mosso la coda di un millimetro. La
  correzione della coda si fa sull'export, in Blender
  (`arcanium/tools/alza_coda_lupo.py`).
- **Mai `Scene.Undo` da script in una scena su cui l'utente ha lavorato.** Se
  la sessione dello script non ha scritto niente, l'annulla puo' togliere un
  passo DELL'UTENTE (la fisica, per esempio). Il 2026-10-15 e' andata bene
  (confronto di tutte le ossa su tutti i frame: 0,0000 cm), ma per saperlo e'
  servito riesportare e confrontare. Prima di provare qualcosa: copia del
  .casc, e per tornare indietro si ricarica la copia.
