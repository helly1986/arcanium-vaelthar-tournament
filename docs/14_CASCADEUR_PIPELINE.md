# Cascadeur pilotato da Claude Code — cosa si può fare davvero

> Verificato dal vivo su **Cascadeur 2026.2** il 2026-08-20, via il ponte MCP
> (`tools/cascadeur_mcp.py`, porta 8765). Ogni riga qui sotto è stata eseguita e
> misurata, non dedotta dalla documentazione.
>
> Il manuale operativo completo — firme, trappole, tabelle — sta nella skill
> `.claude/skills/cascadeur-mcp/SKILL.md`. Questo documento dice **cosa è
> possibile** e **cosa no**, per decidere il lavoro.

## Il verdetto, in breve

Una vecchia esplorazione aveva concluso che dall'API non si potessero toccare i
keyframe né lanciare l'AI. **Era sbagliata su quasi tutto.** Il quadro reale:

| Cosa | Si può? | Come |
|---|---|---|
| Scrivere il valore di un keyframe | **Sì** | `DataEditor.set_data_value` dentro `modify_update_with_session` |
| Aggiungere una chiave | **Sì** | `layers_editor().set_fixed_interpolation_or_key_if_need(lid, frame, True)` |
| Togliere una chiave | **Sì** | `layers_editor().unset_section(frame, lid)` |
| Spostare una chiave | **Sì** | togli e rimetti: non esiste un `move_section` |
| Cambiare l'interpolazione | **Sì** | `Interval.interpolation = Interpolation.LINEAR / BEZIER / STEP / AI` |
| Scrivere la mappa osso-metarig → giunto | **Sì** | template QRT in JSON; Cascadeur lo rilegge identico |
| **Costruire** il rig da API | **Sì** | ⚠️ non con `create_from_qrt_*`: si costruisce `csc.rig.QrtData` a mano e si chiama `create_rig_elements_by_qrt` |
| Lanciare comandi della GUI | **Sì** | `ActionManager.call_action("View.FixFoot")` |
| Marcare un tratto come interpolazione AI | **Sì** | `Interpolation.AI` (= 7) sull'intervallo |
| **Far girare** l'interpolazione AI | **non ancora** | serve il rig di Cascadeur, non basta lo scheletro importato |
| Applicare AutoPhysics con una chiamata | **No** | l'API espone solo `turn_off` e `turn_off_all_fulcrum_points` |
| Auto-rigging quadrupede | **No** | gate commerciale PRO, non è un limite dell'API |

## Le tre prove che contano

**Scrivere un keyframe.** Osso `LeftArm`, canale `Local Rotation`, frame 26:
prima `0.1350 0.0828 0.7229 0.6726`, dopo la sessione
`0.5000 0.5000 0.5000 0.5000`, riletto dalla scena. Funziona.

**Togliere le chiavi.** Tolte le 31→49: `key_frame_indices()` è passato da
`[… 29, 30, 31 …]` a `[25, 26, 27, 28, 29, 30, 50, 51 …]`.

**L'interpolazione ricalcola.** Messo `LINEAR` sull'intervallo che parte dal
frame 30, il valore al frame 40 è passato da `0.0982 0.0454 0.7287 0.6762` a
`0.0547 0.0122 0.7311 0.6799` — cioè a metà strada fra il 30 e il 50.

Quest'ultima è anche la spiegazione di perché prima sembrava tutto rotto:
`modify_with_session` **scrive ma non ricalcola**. Serve
`modify_update_with_session`.

## Il pezzo che rende possibile il lavoro E2E

L'associazione osso-del-metarig → giunto-della-scena si fa dall'API, con un
template **QRT** in JSON.

⚠️ **Correzione**: qui era scritto che `blender_autorig_pro.qrigcasc` fosse
già il nostro rig. È falso, misurato: fa **0 nomi su 51**, perché mappa i
*controlli* di ARP (`c_root_master.x`, `c_traj`) e non le ossa che ARP esporta.
Nessuno dei 20 template combacia — il migliore è Mixamo con 10 su 21. Il nostro
se lo genera `arcanium/tools/genera_qrt_cascadeur.py` leggendo la gerarchia dal
GLB, e sta in `arcanium/rigs/arcanium_canonico.qrigcasc`
(vedi [05_RIG_CANONICO.md](05_RIG_CANONICO.md)).

Quindi il giro completo, senza mai toccare la GUI:

1. esporta il GLB da Blender;
2. converti se serve (vedi sotto) e importa in Cascadeur;
3. entra in rigging mode (`rig_mode.on.run_raw`), costruisci il `QrtData` con
   gli `object_id` risolti e chiama `create_rig_elements_by_qrt`, poi esci con
   `rig_mode.off.run` — tutto in `arcanium/tools/casc_rigga_personaggio.py`;
4. scrivi, togli, sposta le chiavi; imposta le interpolazioni;
5. `call_action` per i correttivi (`View.FixFoot`, `View.FixCollisions`);
6. riesporta in GLB e rientra in Godot.

Il giro è chiuso: il 2026-08-21 il rig è stato costruito **interamente da
script** su `protagonista_v4` con la clip sopra — 255 oggetti, `RigInfo = 1`, e
il gesto della clip sopravvissuto alla generazione (bacino 101,4 → 90,7 cm,
mano a 8,4 cm dal collo al frame 48).

⚠️ Il passo che inganna è il 3: `create_from_qrt_by_fileName` **legge** il
template ma non lega i giunti, e fallisce con un messaggio che sembra parlare
delle sole braccia. Dettagli e ricetta nella skill.

## ⚠️ Blender esporta CUBICSPLINE, Cascadeur non lo legge

È il muro che ha fermato la morte per veleno. `process_import` muore con:

    RuntimeError: unexpected times & values count: 14 vs 42

Il rapporto è sempre 1 a 3: glTF CUBICSPLINE salva per ogni chiave la terna
`(tangente entrante, valore, tangente uscente)`. Blender lo produce ogni volta
che le curve hanno le tangenti, cioè **quasi sempre** se all'export non si
spunta "Always Sample Animations".

Rimedio nel repo:

```bash
python tools/glb_cubicspline_to_linear.py ingresso.glb uscita.glb --fps 30
```

Non appiattisce la curva: valuta la spline di Hermite a ogni frame, così il
movimento che arriva in Cascadeur è quello autorato e non una spezzata fra le
chiavi. Su `player_poison_death.glb`: 25 sampler convertiti, 14 chiavi → 191
frame, import riuscito.

L'avviso `No object with id BaseArmature was found in import data` che compare
dopo è innocuo.

## ⚠️ Due modi di credere a un risultato che non c'è

**`ok: true` non vuol dire riuscito.** Sta scritto nel README del server dentro
Cascadeur: `modify*` può fallire con l'eccezione finita nel log mentre il ponte
riporta comunque `ok: true`. `modify*` torna `False` quando la callback è
esplosa; il traceback sta in coda a
`%LOCALAPPDATA%\Nekki Limited\Cascadeur\logs\cascadeur_log.log`.

**`call_action` non fallisce mai.** Una chiave inventata passa liscia
esattamente come una vera, senza eccezione e senza valore di ritorno.

In tutti e due i casi l'unica prova è **rileggere la scena e misurare**. Vale la
regola che già abbiamo sugli asset 3D: verificare, non dedurre.

## Diffidare degli snippet plausibili

Girano riassunti dell'API `csc` che suonano giusti e non esistono. Questi nomi
**non esistono**, e vengono proposti spesso:

    csc.app.Application.instance()      app.scene()
    app.tools_manager()                 tools_manager.auto_physic_tool()
    scene.layers()                      layers.editor()

I nomi veri sono `csc.app.get_application()`, `app.current_scene()`,
`app.get_tools_manager()` (che ha solo `get_tool` e `tools`),
`scene.domain_scene()`, `domain_scene().layers_viewer()` e — dentro una sessione
— `model_editor.layers_editor()`.

Le due fonti che si possono controllare:

- la doc ufficiale, una pagina sola da 2,6 MB con tutte le firme:
  <https://cascadeur.com/python-api/csc.html>;
- meglio ancora, i **617 file Python in chiaro** dentro
  `C:\Program Files\Cascadeur\resources\scripts\python\` — non è
  documentazione, è il codice che gira.

## Stato di `player_poison_death`

**Rifatta da capo il 2026-08-21, e adesso e' una morte vera.** Il giro completo:
retarget sul rig canonico → messa a terra → rig di Cascadeur → poche pose
autorate a mano con interpolazione **AI** in mezzo → **ragdoll** sull'ultima
parte, con "Work on interval".

Cosa fa adesso, guardata nel provino: si porta le mani alla gola, barcolla,
cade sulle ginocchia, si accartoccia in avanti, ha uno **spasmo finale** e
rotola sul fianco.

Le misure, contro l'originale (in altezze di bacino, l'angolo in gradi):

| | ginocchio | bacino a fine | testa a fine | mano-collo (minimo) |
|---|---|---|---|---|
| originale | 150°–172° (gambe dritte) | 0,895 | 0,852 | 0,113 |
| adesso | scende a **18,8°** | **0,321** | **0,151** | **0,133** |

Le tre cose che erano rotte all'inizio — scheletro sbagliato con 15 tracce su
24 perse in silenzio, corpo che non arrivava mai a terra, caduta rigida come un
asse — sono tutte chiuse. La clip pesa **147 KB**, una sola animazione
`PoisonDeath`, 62 ossa tutte sul rig canonico.

I file di lavorazione (scene `.casc`, GLB intermedi) stanno in
`lavorazione/cascadeur/`, fuori da git: si ricostruiscono con gli strumenti in
`arcanium/tools/`.


## Una clip NUOVA da autorare: la scena di partenza (standard dal 2026-09-30)

Per dare all'animatore una scena pronta — personaggio riggato in Cascadeur,
posa di partenza e di arrivo uguali all'idle, niente in mezzo — ci sono tre
passi, tutti nel repo:

```
# 1. in Blender: corpo riggato + la posa del primo fotogramma dell'idle tenuta per N frame
blender --background --factory-startup --python arcanium/tools/base_cascadeur.py --     <corpo>_rigged.glb anims/sword/sword_idle_01.glb lavorazione/cascadeur/<clip>_base.glb <Clip> tieni=91

# 2. in Cascadeur: il rig (la base si sceglie scrivendola in lavorazione/cascadeur/base_corrente.txt)
python tools/cascadeur_mcp.py arcanium/tools/casc_rigga_personaggio.py

# 3. in Cascadeur: solo le chiavi al primo e all'ultimo frame, BEZIER, e salvataggio
#    (dove salvare: lavorazione/cascadeur/salva_come.txt)
python tools/cascadeur_mcp.py arcanium/tools/casc_estremi_clip.py
```

Il passo 3 misura la posa al primo, a metà e all'ultimo frame: deve dire
`scarto massimo … 0.000 cm`. `N` frame a 30 fps: 91 sono 3 s.

⚠️ **La posa ferma si prepara in Blender, non in Cascadeur.** Riscrivere dentro
Cascadeur, canale per canale, la posa del frame 0 sull'ultimo frame spostava le
mani di 50 cm: i controlli del rig dipendono l'uno dall'altro, e una posa non si
descrive coi valori dei suoi canali. Si tengono invece le chiavi che il rig cuoce
da una clip già ferma.

⚠️ **Prima di sovrascrivere una scena, guardare che non ci si stia lavorando**:
chiavi diverse dalle due degli estremi o un file salvato dopo l'ultima
preparazione vogliono dire che l'animatore l'ha toccata.

⚠️ **In Cascadeur la mesh è solo un'anteprima.** Quello che torna in gioco è la
clip, cioè le ossa: la topologia della mesh in Cascadeur non cambia il
risultato, ed è per questo che verso Cascadeur si resta sul GLB.

