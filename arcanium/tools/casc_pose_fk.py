# -*- coding: utf-8 -*-
"""Pose chiave in FK sui GIUNTI di una scena Cascadeur SENZA rig.

Da eseguire DENTRO Cascadeur, tramite il ponte, sulla scena di lavorazione
(la base importata e le armi agganciate da `casc_arma_su_osso.py`, niente
rig):

    python tools/cascadeur_mcp.py arcanium/tools/casc_pose_fk.py

Le pose si scrivono nel json indicato da `lavorazione/cascadeur/pose_corrente.txt`:

    {"pose": {"45": [
        {"osso": "Shoulder_L", "mira": {"punto": "Elbow_L", "verso": [0.2, -1, 0.4]}},
        {"osso": "Elbow_L", "mira": {"punto": "Hand_L", "verso": [-0.8, 0.1, 0.6]},
         "rollio": {"oggetto": "LeftHand_Mesh", "asse": [0, 0, 1], "verso": [0, 0.2, 1]}},
        {"osso": "Hand_R", "mira": {"oggetto": "RightHand_Sword", "asse": [0, -1, 0], "verso": [1, 0.2, 0.3]},
         "rollio": {"asse": [0, 0, 1], "verso": [0, 1, 0]}},
        {"osso": "Spine_03", "asse": [0, 1, 0], "gradi": 8}
    ]}}

Gli assi sono quelli del MONDO di Cascadeur: +Y in alto, +Z davanti al
personaggio, +X la sua sinistra.

Per un braccio intero c'e' l'IK a due ossa: la mano va su un punto (cm), il
gomito si apre verso il polo. Si traduce in due mire, spalla e gomito.

        {"ik": {"spalla": "Shoulder_R", "gomito": "Elbow_R", "mano": "Hand_R",
                "bersaglio": [-20, 140, 30], "polo": [-1, -0.5, -0.5]}}

Il `verso` di una mira puo' anche essere il BORDO ALTO di un oggetto tondo
(lo scudo, letto dalla scena com'e' in quel momento): la lama punta li', e
il contatto resta esatto anche quando si cambia la posa dello scudo.

        "mira": {"oggetto": "RightHand_Sword", "asse": [0, -1, 0],
                 "verso_al_bordo": {"da": "Hand_R", "oggetto": "LeftHand_Mesh",
                                    "normale": [0, 0, 1], "raggio": 33, "sopra": 2}}

Una mira senza `verso` tiene la direzione che ha: serve a un rollio puro (lo
scudo girato attorno all'avambraccio senza spostarlo).

═══════════════════════════════════════════════════════════════════════════
PERCHE' SENZA RIG, E COME CI SI TORNA
═══════════════════════════════════════════════════════════════════════════

In una scena riggata i giunti non si scrivono, e i controlli delle braccia
sono IK: la mano resta dove la metti, ma il gomito e l'orientamento della
mano li ricalcola il rig dai punti derivati (misurato il 2026-10-23 girando
i controlli a catena: gomiti spostati di 11-21 cm, la lama ferma dov'era).
Senza rig invece i giunti sono liberi e l'FK e' esatto: si girano i giunti,
si esporta il GLB, e il rig si costruisce DOPO su quel GLB — il bake del rig
traduce le pose dei giunti nei controlli da se' (`casc_rigga_personaggio.py`),
e `casc_estremi_clip.py` tiene solo le chiavi delle pose.

La mira punta la direzione dal giunto a un punto (il figlio), o un asse
locale di un oggetto agganciato;
il rollio gira attorno alla direzione finche' un asse dell'oggetto guarda
dove deve. Un passo per sessione, in ordine dal busto alle mani: dopo ogni
sessione la scena si rilegge, perche' girare una spalla sposta mano e arma.

⚠️⚠️ `modify_update_with_session` NON ricalcola i canali GLOBALI (Rotation,
Position, Global Matrix) su tutti i frame: con la timeline ferma a 90 il
frame 110 restava indietro — la `Local Rotation` scritta c'era, la `Rotation`
globale era quella di prima, e la mira successiva leggeva una posa vecchia
(2026-10-23; spostare il frame corrente non basta, `set_current_frame` vale
solo a script finito). Il rimedio e' chiedere il ricalcolo di QUEL frame
dentro la sessione: `updater.run_update({DataId, ...}, frame)`, il terzo
argomento della callback.

⚠️ Idempotente: prima di posare un frame, i giunti che la posa tocca tornano
alla `Local Rotation` del frame `base` (default 0, la posa ferma).
"""

import json
import traceback

import numpy as np

import csc

_CARTELLA = r"C:\Users\Adriano\LOCAL\arcanium---vaelthar-tournament\lavorazione\cascadeur"
try:
    with open(_CARTELLA + r"\pose_corrente.txt", encoding="utf-8") as _f:
        POSE = _f.read().strip()
except OSError:
    POSE = _CARTELLA + r"\pose_chiave.json"


class Fermata(Exception):
    """Errore riportabile: `SystemExit` farebbe cadere il ponte MCP."""


def _log(*a):
    print("[fk]", *a)


def _rotazione(asse, gradi):
    a = np.array(asse, dtype=float)
    a = a / np.linalg.norm(a)
    t = np.radians(float(gradi))
    x, y, z = a
    c, s, u = np.cos(t), np.sin(t), 1.0 - np.cos(t)
    return np.array([
        [c + x * x * u,     x * y * u - z * s, x * z * u + y * s],
        [y * x * u + z * s, c + y * y * u,     y * z * u - x * s],
        [z * x * u - y * s, z * y * u + x * s, c + z * z * u],
    ])


def _fra_versori(d, t):
    d = d / np.linalg.norm(d)
    t = t / np.linalg.norm(t)
    asse = np.cross(d, t)
    sen = float(np.linalg.norm(asse))
    cos = float(np.dot(d, t))
    if sen < 1e-9:
        if cos > 0.0:
            return np.eye(3)
        perp = np.array([0.0, 1.0, 0.0]) if abs(d[0]) > 0.9 else np.array([1.0, 0.0, 0.0])
        return _rotazione(np.cross(d, perp), 180.0)
    return _rotazione(asse, np.degrees(np.arctan2(sen, cos)))


def _mat(rot):
    return np.array(rot.to_rotation_matrix(), dtype=float).reshape(3, 3)


def _rot(m):
    return csc.math.Rotation.from_rotation_matrix(m.tolist())


class Scena(object):
    def __init__(self):
        app = csc.app.get_application()
        self.ds = app.current_scene().domain_scene()
        self.mv = self.ds.model_viewer()
        self.dv = self.mv.data_viewer()
        self.lv = self.ds.layers_viewer()
        self.ogg = {}
        for o in self.mv.get_objects():
            self.ogg.setdefault(self.mv.get_object_name(o), o)
        self._canali = {}

    def canale(self, nome, dato):
        if (nome, dato) not in self._canali:
            if nome not in self.ogg:
                raise Fermata("assente dalla scena: %s" % nome)
            o = self.ogg[nome]
            self._canali[(nome, dato)] = {self.dv.get_data_name(i): i
                                          for i in self.dv.get_all_data_id(o)}[dato]
        return self._canali[(nome, dato)]

    def pos(self, nome, f):
        return np.array(self.dv.get_data_value(self.canale(nome, "Position"), f), dtype=float)

    def globale(self, nome, f):
        return _mat(self.dv.get_data_value(self.canale(nome, "Rotation"), f))

    def locale(self, nome, f):
        return _mat(self.dv.get_data_value(self.canale(nome, "Local Rotation"), f))

    def assi_oggetto(self, nome, f):
        m = np.array(self.dv.get_data_value(self.canale(nome, "Global Matrix"), f),
                     dtype=float).reshape(4, 4)[:3, :3]
        return m / np.linalg.norm(m, axis=0)

    def scrivi(self, valori, f, nome_sessione):
        """{osso: matrice locale} al frame f, in una sessione."""
        dati = {o: (self.canale(o, "Local Rotation"), self.lv.layer_id_by_obj_id(self.ogg[o]), _rot(m))
                for o, m in valori.items()}

        def s(me, update, aggiornatore, session):
            le = me.layers_editor()
            de = me.data_editor()
            for did, lid, r in dati.values():
                le.set_fixed_interpolation_or_key_if_need(lid, f, True)
                de.set_data_value(did, f, r)
            aggiornatore.run_update({d[0] for d in dati.values()}, f)

        if not self.ds.modify_update_with_session(nome_sessione, s):
            raise Fermata("sessione fallita: %s (cascadeur_log.log)" % nome_sessione)


def _bordo_alto(sc, b, f):
    """Il punto piu' alto del bordo di un oggetto tondo, piu' `sopra` cm."""
    m = np.array(sc.dv.get_data_value(sc.canale(b["oggetto"], "Global Matrix"), f),
                 dtype=float).reshape(4, 4)
    n = sc.assi_oggetto(b["oggetto"], f) @ np.array(b["normale"], dtype=float)
    su = np.array([0.0, 1.0, 0.0]) - n * n[1]
    su = su / np.linalg.norm(su)
    return m[:3, 3] + su * float(b["raggio"]) + np.array([0.0, float(b.get("sopra", 0.0)), 0.0])


def _rotazione_del_passo(sc, p, f):
    osso = p["osso"]
    if "mira" not in p:
        return _rotazione(p["asse"], p["gradi"])
    m = p["mira"]
    if "punto" in m:
        d = sc.pos(m["punto"], f) - sc.pos(osso, f)
    else:
        d = sc.assi_oggetto(m["oggetto"], f) @ np.array(m["asse"], dtype=float)
    if "verso_al_bordo" in m:
        t = _bordo_alto(sc, m["verso_al_bordo"], f) - sc.pos(m["verso_al_bordo"]["da"], f)
    else:
        t = np.array(m["verso"], dtype=float) if "verso" in m else d
    t = t / np.linalg.norm(t)
    r = _fra_versori(d, t)
    if "rollio" in p:
        ro = p["rollio"]
        n = r @ sc.assi_oggetto(ro.get("oggetto", m.get("oggetto", "")), f) @ np.array(ro["asse"], dtype=float)
        v = np.array(ro["verso"], dtype=float)
        n = n - t * np.dot(n, t)
        v = v - t * np.dot(v, t)
        if np.linalg.norm(n) > 1e-6 and np.linalg.norm(v) > 1e-6:
            r = _fra_versori(n, v) @ r
    return r


def _ik(sc, p, f):
    """Due mire che portano la mano sul bersaglio, il gomito verso il polo."""
    k = p["ik"]
    s0 = sc.pos(k["spalla"], f)
    a = float(np.linalg.norm(sc.pos(k["gomito"], f) - s0))
    b = float(np.linalg.norm(sc.pos(k["mano"], f) - sc.pos(k["gomito"], f)))
    t = np.array(k["bersaglio"], dtype=float)
    v = t - s0
    dist = float(np.linalg.norm(v))
    if dist > a + b - 0.5:
        _log("    %s: bersaglio a %.1f cm, il braccio ne arriva a %.1f: si stende" % (k["mano"], dist, a + b))
        dist = a + b - 0.5
        t = s0 + v / np.linalg.norm(v) * dist
    asse = v / np.linalg.norm(v)
    ## Il gomito sul cerchio fra spalla e mano, dalla parte del polo.
    x = (a * a - b * b + dist * dist) / (2.0 * dist)
    h = float(np.sqrt(max(a * a - x * x, 0.0)))
    polo = np.array(k["polo"], dtype=float)
    polo = polo - asse * np.dot(polo, asse)
    polo = polo / np.linalg.norm(polo)
    gomito = s0 + asse * x + polo * h
    return [
        {"osso": k["spalla"], "mira": {"punto": k["gomito"], "verso": (gomito - s0).tolist()}},
        {"osso": k["gomito"], "mira": {"punto": k["mano"], "verso": (t - gomito).tolist()}},
    ]


def _esegui_passo(sc, p, f):
    osso = p["osso"]
    r = _rotazione_del_passo(sc, p, f)
    g = sc.globale(osso, f)
    padre = g @ sc.locale(osso, f).T
    voluta = r @ g
    sc.scrivi({osso: padre.T @ voluta}, f, "fk %d %s" % (f, osso))
    ## Il ritorno True non e' una conferma: si rilegge.
    scarto = np.degrees(np.arccos(np.clip((np.trace(voluta.T @ sc.globale(osso, f)) - 1.0) / 2.0, -1.0, 1.0)))
    if scarto > 0.5:
        raise Fermata("frame %d, %s: la rotazione non ha tenuto (%.2f gradi)" % (f, osso, scarto))


def applica(spec):
    sc = Scena()
    base = int(spec.get("base", 0))
    n = sc.dv.get_animation_size()
    for chiave, passi in sorted(spec["pose"].items(), key=lambda kv: int(kv[0])):
        f = int(chiave)
        if not (0 <= f < n):
            raise Fermata("frame %d fuori dalla clip (0..%d)" % (f, n - 1))
        ossa = set()
        for p in passi:
            if "ik" in p:
                ossa.update([p["ik"]["spalla"], p["ik"]["gomito"]])
            else:
                ossa.add(p["osso"])
        ossa = sorted(ossa)
        sc.scrivi({o: sc.locale(o, base) for o in ossa}, f, "riparti %d" % f)
        for p in passi:
            for q in (_ik(sc, p, f) if "ik" in p else [p]):
                _esegui_passo(sc, q, f)
        _log("frame %3d: %d passi su %s" % (f, len(passi), ", ".join(ossa)))


try:
    with open(POSE, encoding="utf-8") as _f:
        applica(json.load(_f))
except Fermata as _e:
    _log("FERMATO:", _e)
except Exception:
    print("ECCEZIONE:\n" + traceback.format_exc())
