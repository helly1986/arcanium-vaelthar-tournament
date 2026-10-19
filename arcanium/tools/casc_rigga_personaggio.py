# -*- coding: utf-8 -*-
"""Importa un personaggio in Cascadeur e gli costruisce il rig, da script.

Da eseguire DENTRO Cascadeur, tramite il ponte:

    python tools/cascadeur_mcp.py arcanium/tools/casc_rigga_personaggio.py

I percorsi si cambiano in fondo, in `PRINCIPALE`.

═══════════════════════════════════════════════════════════════════════════
LA SCOPERTA CHE RENDE POSSIBILE TUTTO QUESTO
═══════════════════════════════════════════════════════════════════════════

`RiggingWindow.create_from_qrt_by_fileName()` **non lega i giunti**. Legge il
template (verificato: `get_template_from_qrt()` lo rilegge intero e corretto),
ma gli `object_id` delle `BoneProperty` restano nulli, e il rig non si costruisce
mai. L'errore che si vede e'

    Can't find required nodes: ['arm_r', 'arm_l']

che inganna due volte: quei due nomi sono gli unici nodi **obbligatori** del
biped (`get_required_nodes()` in `prototypes/rigs/qrt/biped/_biped.py`), quindi
il messaggio non dice che mancano le braccia — dice che **non si e' legato
niente**.

E non c'e' rimedio dal lato template: il nostro e' stato reso IDENTICO byte per
byte a quello estratto dal `qrt_json` di un personaggio gia' riggato bene, e
falliva lo stesso. Non lo risolvono nemmeno aprire la finestra, selezionare
tutti i giunti, o passare da `load_template_by_fileName` +
`generate_rig_elements`.

La via che funziona e' saltare il caricatore: **costruire il `csc.rig.QrtData`
a mano**, mettendo negli `object_id` i giunti veri presi per nome dalla scena, e
chiamare direttamente `create_rig_elements_by_qrt`. Misurato: 65 -> 222 oggetti
in rig mode, poi 255 dopo l'uscita, con `RigInfo = 1`.
"""

import json
import traceback

import csc
import pycsc
import rig_mode.on as rm_on
import rig_mode.off as rm_off
import prototypes.qrt_prototypes.create as qrt_create

COLORE_PUNTI = [0.0, 0.5, 0.0]
LUNGHEZZA_AGGIUNTE = 10.0
LUNGHEZZA_DIREZIONI = 10.0


class Fermata(Exception):
    """Errore riportabile al chiamante.

    ⚠️ `raise Fermata(...)` dentro uno script del ponte MCP non arriva a chi
    ha chiamato: il server va in `KeyError: 'ok'` e CHIUDE la connessione. Da
    fuori si legge `RemoteDisconnected` e si conclude che Cascadeur e' morto,
    mentre sta benissimo e il messaggio utile e' solo nel `cascadeur_log.log`.
    """


def _log(*a):
    print("[rigga]", *a)


def importa(percorso_glb, scala=100.0):
    """Scena nuova + import. ⚠️ Cascadeur lavora in CENTIMETRI: scala 100."""
    app = csc.app.get_application()
    sm = app.get_scene_manager()
    sc = sm.create_application_scene()
    sm.set_current_scene(sc)
    ds = app.current_scene().domain_scene()

    io_ = csc.glb.ImportOptions()
    io_.include_objects = True
    io_.include_animation = True
    io_.is_update_mode = False
    io_.throw_exception = True
    io_.scale_factor = scala
    csc.glb.process_import(ds, percorso_glb, io_)

    mv = ds.model_viewer()
    _log("importati %d oggetti, %d frame"
         % (len(mv.get_objects()), mv.data_viewer().get_animation_size()))
    return ds


def _qrt_data_da_template(ds, percorso_template):
    """Costruisce il QrtData con gli object_id GIA' risolti.

    E' questo il passo che il caricatore di Cascadeur non fa.
    """
    mv = ds.model_viewer()
    per_nome = {mv.get_object_name(o): o for o in mv.get_objects()}
    testo = open(percorso_template, encoding="utf-8").read()
    tpl = json.loads(testo)

    q = csc.rig.QrtData()
    impostazioni = tpl.get("Settings", {})
    q.is_align_pelvis = bool(impostazioni.get("Is align pelvis", True))
    q.is_create_layers = bool(impostazioni.get("Is create layers", True))
    q.is_replace_existing = False

    corpo, mancanti = [], []
    for doc in tpl["Document"]:
        if doc.get("Title") != "Body":
            continue
        for sez in doc["Sections"]:
            gruppo = []
            for voce in sez["Names"]:
                nome = voce["Joint name"]
                oid = per_nome.get(nome)
                if oid is None:
                    mancanti.append(nome)
                    continue
                bp = csc.rig.BoneProperty()
                bp.bone_name = voce["Bone name"]
                bp.object_id = oid
                bp.joint_path_name = csc.model.PathName.get_path_name(oid, mv)
                gruppo.append(bp)
            corpo.append(gruppo)
    if mancanti:
        raise Fermata("giunti del template assenti dalla scena: %s" % mancanti)
    q.body = corpo

    legate = sum(len(g) for g in corpo)
    # ⚠️ Verificare che l'assegnazione sia RIMASTA: `q.body = corpo` passa per
    # pybind, e un oggetto che non tiene il valore darebbe di nuovo il falso
    # "Can't find required nodes".
    riletto = q.body
    if sum(len(g) for g in riletto) != legate or riletto[0][0].object_id.is_null():
        raise Fermata("il QrtData non ha tenuto i legami")
    _log("QrtData: %d sezioni, %d ossa legate" % (len(corpo), legate))
    return q, testo


def rigga(ds, percorso_template):
    # ⚠️⚠️ Senza la rig mode il QRT muore con `Rig mode several animationInfo`,
    # che vuol dire il contrario di come suona: ne serve ESATTAMENTE UNO, e su
    # una scena appena importata ce ne sono zero. Lo crea rig_mode/on.py.
    rm_on.run_raw(ds, COLORE_PUNTI)
    quanti = len(pycsc.wrap(ds).bv.get_behaviours("AnimationInfo"))
    if quanti != 1:
        raise Fermata("AnimationInfo = %d, doveva essere 1" % quanti)

    q, testo = _qrt_data_da_template(ds, percorso_template)

    prima = len(ds.model_viewer().get_objects())
    qrt_create.create_rig_elements_by_qrt(
        ds, q, LUNGHEZZA_AGGIUNTE, LUNGHEZZA_DIREZIONI, COLORE_PUNTI, testo)
    dopo = len(ds.model_viewer().get_objects())
    if dopo <= prima:
        raise Fermata("il rig non ha creato nulla (%d -> %d)" % (prima, dopo))
    _log("elementi proto creati: %d -> %d oggetti" % (prima, dopo))

    # uscire dalla rig mode cuoce il rig vero e crea il RigInfo
    rm_off.run(ds, True)

    mv = ds.model_viewer()
    tipi = {}
    for o in mv.get_objects():
        t = mv.get_object_type_name(o)
        tipi[t] = tipi.get(t, 0) + 1
    rig_info = len(pycsc.wrap(ds).bv.get_behaviours("RigInfo"))
    _log("rig cotto: %d oggetti, RigInfo = %d" % (len(mv.get_objects()), rig_info))
    _log("tipi:", tipi)
    if rig_info != 1:
        raise Fermata("RigInfo = %d dopo l'uscita dalla rig mode" % rig_info)
    # ⚠️ L'uscita dalla rig mode RITOCCA l'animazione: si vedono centinaia di
    # `Local rotation of X has changed after rig generation`. Non e' un errore,
    # ma va misurato che il gesto sia sopravvissuto prima di lavorarci sopra.
    return ds


# ⚠️ Il TEMPLATE va scelto in base al CORPO, non "quello del progetto": Arcanium
# ha due convenzioni di ossa e il QRT canonico sul rig del pack dei nemici fa 3
# nomi su 21. Per i Consumati e i Fanti serve `nephilite_pack.qrigcasc`.
PRINCIPALE = dict(
    glb="C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/lavorazione/cascadeur/fante_spadone_base.glb",
    template="C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/arcanium/rigs/nephilite_pack.qrigcasc",
)

## La base si sceglie con un FILE, come le armi (`armi_corrente.txt`): il ponte
## esegue il testo dentro Cascadeur, e una variabile d'ambiente non arriva.
try:
    with open("C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/lavorazione/cascadeur/base_corrente.txt",
              encoding="utf-8") as _f:
        _base = _f.read().strip()
    if _base:
        PRINCIPALE["glb"] = _base
except OSError:
    pass

try:
    _ds = importa(PRINCIPALE["glb"])
    rigga(_ds, PRINCIPALE["template"])
except Exception:
    print("ECCEZIONE:\n" + traceback.format_exc())
