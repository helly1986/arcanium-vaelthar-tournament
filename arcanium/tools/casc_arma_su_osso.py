# -*- coding: utf-8 -*-
"""Aggancia le armi vere a un personaggio importato in Cascadeur.

Da eseguire DENTRO Cascadeur, tramite il ponte:

    python tools/cascadeur_mcp.py arcanium/tools/casc_arma_su_osso.py

L'allestimento si dichiara in `lavorazione/cascadeur/armi.json`.

═══════════════════════════════════════════════════════════════════════════
A COSA SERVONO, E A COSA NO
═══════════════════════════════════════════════════════════════════════════

Servono a GUARDARE. Una guardia con lo scudo non si giudica su uno scheletro
nudo: la domanda e' «lo scudo copre il petto?», e senza scudo non ha risposta.
Stessa cosa per lo spadone, dove il difetto tipico e' la punta che finisce sotto
il terreno.

⚠️ NON finiscono nella clip. Le clip del progetto escono di sola armatura
(`rifinisci_clip_cascadeur.py` toglie anche la mesh del corpo): queste sono
attrezzatura di lavorazione. Se un'arma comparisse in un GLB di animazione,
sarebbe un errore, non una comodita'.

═══════════════════════════════════════════════════════════════════════════
⚠️ PERCHE' L'AGGANCIO SI FA QUI E NON IN BLENDER
═══════════════════════════════════════════════════════════════════════════

Le trasformazioni d'aggancio sono gia' state calcolate una volta e cablate a
mano nei `.tscn` dei Fanti: vanno RIUSATE, non rifatte. Ma sono espresse nello
spazio di Godot, e per portarle in Blender bisognerebbe attraversare due
conversioni che sbagliano in silenzio — l'asse alto (Y-up del glTF contro Z-up
di Blender) e l'euristica con cui l'importatore glTF RIORIENTA le ossa, che
cambia il significato di ogni matrice locale.

Cascadeur invece lavora nello stesso spazio del glTF, solo in centimetri: la
matrice di Godot si usa TALE E QUALE, con la sola origine moltiplicata per 100.
Zero conversioni, zero occasioni di sbagliare.

⚠️ E il `transform` del nodo `MountArma` nel `.tscn` NON e' l'aggancio: e' la
posa dell'osso tenuta in cache dal `BoneAttachment3D`. Verificato — la sua
origine `(-0.478, 1.009, 0.306)` e' esattamente dove Cascadeur misura
`Prop_Attachment_R`. L'aggancio e' la trasformazione del nodo FIGLIO (`Spada`,
`Spadone`, `ScudoIntegro`), che e' relativa all'osso.

═══════════════════════════════════════════════════════════════════════════
LA MATRICE DI GODOT, LETTA GIUSTA
═══════════════════════════════════════════════════════════════════════════

`Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)` porta le tre terne che sono le
**RIGHE** della base, non le colonne.

⚠️⚠️ Questa riga diceva il contrario, e il contrario e' finito nella scena: la
spada si vedeva nel punto giusto e **storta**, perche' con la base trasposta
l'origine e la scala restano esatte e sbagliano solo gli assi. E' un errore che
supera qualunque controllo numerico sulla posizione — il mio diceva
`scarto 0.000 cm` — e lo si vede solo guardando.

La prova che decide, e che si puo' rifare in ogni momento: il nodo `MountArma`
nel `.tscn` E' la posa dell'osso tenuta in cache, e la stessa posa Cascadeur la
sa dire da se'. Confrontando le due basi:

    letta per COLONNE  -> 128,754 gradi di scarto
    letta per RIGHE    ->   0,076 gradi

Quando due sorgenti indipendenti descrivono lo STESSO oggetto, il verso di
lettura si misura invece di ricordarselo.

⚠️ Quelle basi NON sono ortonormali: portano dentro una scala (misurate — scudo
0,4573, spada 0,3443, spadone 0,6479, tutte e tre UNIFORMI). La scala si estrae
dalla lunghezza delle colonne, e cio' che resta e' una rotazione pura. Se un
giorno una colonna avesse lunghezza diversa dalle altre il tool si ferma: una
scala non uniforme non si scompone in posizione-rotazione-scala senza perderci
del taglio, e va saputo invece che subito.
"""

import json
import traceback

import numpy as np

import csc
import common.hierarchy as hierarchy

## L'allestimento da montare: c'e' un file per famiglia d'arma (spada+scudo,
## spadone), e sono scene di lavorazione diverse.
##
## ⚠️ Si sceglie con un FILE e non con una variabile d'ambiente. Provato: il
## ponte MCP spedisce il TESTO dello script e lo esegue dentro Cascadeur, che e'
## un altro processo — `os.environ` letto qui e' l'ambiente di Cascadeur, non
## quello di chi ha lanciato il comando. La variabile risultava semplicemente
## assente e il tool montava spada e scudo su una scena da spadone, senza
## lamentarsi di niente.
_CARTELLA = r"C:\Users\Adriano\LOCAL\arcanium---vaelthar-tournament\lavorazione\cascadeur"
_SCELTA = _CARTELLA + r"\armi_corrente.txt"
try:
    with open(_SCELTA, encoding="utf-8") as _f:
        ARMI = _f.read().strip()
except OSError:
    ARMI = _CARTELLA + r"\armi.json"


class Fermata(Exception):
    """Errore riportabile: `SystemExit` farebbe cadere il ponte MCP."""


def _log(*a):
    print("[armi]", *a)


def _da_godot(dodici):
    """I 12 float di un Transform3D -> matrice 4x4, origine in CENTIMETRI."""
    v = [float(x) for x in dodici]
    if len(v) != 12:
        raise Fermata("un Transform3D ha 12 numeri, non %d" % len(v))
    base = np.array([v[0:3], v[3:6], v[6:9]], dtype=float)     # RIGHE, non colonne
    m = np.eye(4)
    m[:3, :3] = base
    m[:3, 3] = np.array(v[9:12], dtype=float) * 100.0
    return m


def _scomponi(m):
    """4x4 -> (posizione, rotazione ortonormale 3x3, scala uniforme)."""
    base = m[:3, :3]
    lung = [float(np.linalg.norm(base[:, i])) for i in range(3)]
    if max(lung) - min(lung) > 1e-4 * max(lung):
        raise Fermata("scala NON uniforme sugli assi (%.4f %.4f %.4f): "
                      "non si scompone senza perderci del taglio" % tuple(lung))
    s = sum(lung) / 3.0
    return m[:3, 3], base / s, s


class Scena(object):
    def __init__(self):
        app = csc.app.get_application()
        self.ds = app.current_scene().domain_scene()
        self.mv = self.ds.model_viewer()
        self.dv = self.mv.data_viewer()
        self.lv = self.ds.layers_viewer()

    def per_nome(self, tipo=None):
        d = {}
        for o in self.mv.get_objects():
            if tipo is None or self.mv.get_object_type_name(o) == tipo:
                d.setdefault(self.mv.get_object_name(o), o)
        return d

    def canale(self, oggetto, nome):
        return {self.dv.get_data_name(i): i
                for i in self.dv.get_all_data_id(oggetto)}[nome]

    def globale(self, oggetto, f):
        return np.array(self.dv.get_data_value(self.canale(oggetto, "Global Matrix"), f),
                        dtype=float).reshape(4, 4)


def importa_arma(sc, percorso, nome):
    """Importa un GLB nella scena CORRENTE e restituisce l'oggetto mesh nuovo.

    ⚠️ E POI LO RINOMINA, che non e' cosmesi. Tutti e tre i GLB
    dell'equipaggiamento portano dentro una mesh che si chiama `mesh_node`, e in
    `is_update_mode` Cascadeur salta cio' che gia' c'e' PER NOME: importata la
    spada, lo scudo entrava con

        Some objects already exist in the scene and were not imported
        No objects were imported
        GLB/GLTF: error while applying

    che sembra un file rotto e invece e' una collisione di nomi. Rinominare
    subito dopo l'import e' cio' che permette di allestire due armi.
    """
    prima = {o for o in sc.mv.get_objects()}
    io_ = csc.glb.ImportOptions()
    io_.include_objects = True
    io_.include_animation = False
    io_.is_update_mode = True          # ⚠️ senza questo si perde la scena
    io_.throw_exception = True
    io_.scale_factor = 100.0
    csc.glb.process_import(sc.ds, percorso, io_)
    nuovi = [o for o in sc.mv.get_objects()
             if o not in prima and sc.mv.get_object_type_name(o) == "Mesh Object"]
    if len(nuovi) != 1:
        raise Fermata("%s ha portato %d mesh, ne serve una" % (percorso, len(nuovi)))
    arma = nuovi[0]

    def rinomina(me, update, scene, session):
        me.set_object_name(arma, nome)

    sc.ds.modify_with_session("rinomina arma", rinomina)
    letto = sc.mv.get_object_name(arma)
    if letto != nome:
        raise Fermata("la rinomina non ha tenuto: %r invece di %r" % (letto, nome))
    return arma


def aggancia(sc, arma, osso, m_aggancio, frames):
    """IMPARENTA l'arma al giunto, poi le da' la trasformazione del `.tscn`.

    ⚠️ La prima versione scriveva invece la posa dell'arma frame per frame,
    calcolata dalla matrice globale dell'osso. Funzionava — e non serviva a
    niente: quei valori sono ASSOLUTI, quindi appena qualcuno riposava il
    braccio a mano lo scudo restava indietro. Una scena in cui l'arma si stacca
    quando la muovi non e' una scena in cui si puo' lavorare.

    L'imparentamento e' la via ufficiale (nell'interfaccia si trascina la mesh
    sopra il giunto nell'Outliner) e da API e'
    `common.hierarchy.set_parent_mod`, la stessa che chiama il comando di menu
    `Transform.Set parent`.

    E rende il resto banale: una volta che il padre e' l'osso d'aggancio, la
    trasformazione LOCALE dell'arma **e' esattamente quella del `.tscn`** — che
    li' e' relativa allo stesso osso. Nessuna chiave, nessun frame: un valore
    solo, e l'arma segue qualunque posa.
    """
    giunti = sc.per_nome("Joint")
    if osso not in giunti:
        raise Fermata("osso assente dalla scena: %s" % osso)
    o_osso = giunti[osso]

    hierarchy.set_parent_mod(sc.ds, [arma], o_osso)

    pos_id = sc.canale(arma, "Local Position")
    rot_id = sc.canale(arma, "Local Rotation")
    sca_id = sc.canale(arma, "Local Scale")
    t, r, s = _scomponi(m_aggancio)
    rot = csc.math.Rotation.from_rotation_matrix(r.tolist())

    def scrivi(me, update, scene, session):
        de = me.data_editor()
        de.set_data_value(pos_id, t)
        de.set_data_value(rot_id, rot)
        de.set_data_value(sca_id, np.array([s, s, s]))

    if not sc.ds.modify_update_with_session("aggancio", scrivi):
        raise Fermata("la sessione di aggancio e' fallita")

    # ⚠️ Il ritorno True non e' una conferma: si rilegge dalla scena. E si
    # controlla su PIU' frame, che e' cio' che distingue un'arma imparentata da
    # una posata: se seguisse solo al frame 0, qui si vedrebbe.
    nome = sc.mv.get_object_name(arma)
    peggio = 0.0
    for f in (frames[0], frames[len(frames) // 2], frames[-1]):
        voluto = (sc.globale(o_osso, f) @ m_aggancio)[:3, 3]
        ottenuto = sc.globale(arma, f)[:3, 3]
        peggio = max(peggio, float(np.linalg.norm(voluto - ottenuto)))
    _log("%-22s imparentata a %-22s scarto peggiore %.3f cm su 3 frame"
         % (nome, osso, peggio))
    if peggio > 0.05:
        raise Fermata("%s non segue l'osso (%.3f cm)" % (nome, peggio))


def _controlla_verso_di_lettura(sc, voce):
    """Il MountArma del `.tscn` contro l'osso misurato da Cascadeur.

    Due sorgenti indipendenti che descrivono lo STESSO oggetto — la posa
    dell'osso d'aggancio. Se il verso di lettura dei 12 float fosse sbagliato,
    qui le due basi divergono di un angolo enorme, e ci si ferma PRIMA di
    piazzare un'arma che sarebbe nel punto giusto e storta.
    """
    dodici = voce.get("posa_osso_tscn")
    if not dodici:
        return
    ## ⚠️ Questo controllo confronta la posa d'osso MISURATA con quella che il
    ## `.tscn` teneva in cache: vale solo se la base sta in quella stessa posa.
    ## Su una base autorata in un'altra posa — per esempio la guardia da cui
    ## nasce l'affondo della Testuggine — le due divergono di decine di gradi
    ## ed e' un falso positivo: l'arma andrebbe benissimo dov'e'.
    ##
    ## Si spegne da `armi.json` (`controlla_posa_osso: false`), e allora la
    ## verifica sono le altre due, che non dipendono dalla posa: l'arma deve
    ## SEGUIRE l'osso su piu' frame, e l'immagine deve mostrarla in mano.
    if not _SPEC.get("controlla_posa_osso", True):
        _log("verso di lettura: controllo spento per questa base "
             "(vedi `_controllo` in armi.json) — resta l'aggancio + l'immagine")
        return
    giunti = sc.per_nome("Joint")
    misurata = sc.globale(giunti[voce["osso"]], 0)
    dichiarata = _da_godot(dodici)
    r = dichiarata[:3, :3].T @ misurata[:3, :3]
    gradi = float(np.degrees(np.arccos(np.clip((np.trace(r) - 1.0) / 2.0, -1.0, 1.0))))
    cm = float(np.linalg.norm(dichiarata[:3, 3] - misurata[:3, 3]))
    _log("verso di lettura su %-22s %.3f gradi, %.3f cm" % (voce["osso"], gradi, cm))
    if gradi > 1.0 or cm > 0.5:
        raise Fermata(
            "la posa d'osso del .tscn e quella di Cascadeur non coincidono "
            "(%.2f gradi, %.2f cm): i 12 float sono le RIGHE della base, non le "
            "colonne — o l'osso e' su un frame diverso" % (gradi, cm))


def allestisci(spec):
    sc = Scena()
    n = sc.dv.get_animation_size()
    frames = list(range(n))
    for voce in spec["armi"]:
        _controlla_verso_di_lettura(sc, voce)
        arma = importa_arma(sc, voce["glb"], voce["nome"])
        aggancia(sc, arma, voce["osso"], _da_godot(voce["transform_godot"]), frames)
    _log("allestite %d armi su %d frame" % (len(spec["armi"]), n))


_SPEC = {}

try:
    with open(ARMI, encoding="utf-8") as _f:
        _spec = json.load(_f)
    _SPEC = _spec
    allestisci(_spec)
except Fermata as _e:
    _log("FERMATO:", _e)
except Exception:
    print("ECCEZIONE:\n" + traceback.format_exc())
