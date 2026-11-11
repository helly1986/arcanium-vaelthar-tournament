# -*- coding: utf-8 -*-
"""Dopo il rig: i gomiti e le ginocchia tornano dalla parte delle pose FK.

    python tools/cascadeur_mcp.py arcanium/tools/casc_gomiti_dalle_pose.py

L'uscita dalla rig mode di Cascadeur ricava la direzione di ogni arto (`<osso>_LimbDir`, il
polo dell'IK del rig) dalla posa, e a volte la RIBALTA: sulla guardia con lo scudo di Edran
(2026-11-11) il gomito sinistro e' finito al centro del petto, sopra la spalla, con la
direzione esattamente rovesciata; l'utente l'ha visto in Cascadeur ("un'inclinazione
totalmente assurda"). Il punto del gomito non si scrive (lo ricalcola il rig): si scrive la
DIREZIONE, perpendicolare alla retta spalla-mano, verso il gomito della posa.

Legge la scena delle pose (FK, senza rig) dal nome in `lavorazione/cascadeur/scena_pose.txt`
e le chiavi da `chiavi_da_tenere.txt` (le stesse di `casc_estremi_clip`, spostate di
`sposta`); lavora sulla scena corrente, quella riggata. Corregge solo gli arti il cui gomito o
ginocchio sta a piu' di 3 cm da quello della posa, poi rimisura.
"""
import json
import traceback

import csc
import numpy as np

CARTELLA = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/lavorazione/cascadeur/"
## arto: (radice, giunto di mezzo, estremo)
ARTI = {
    "forearm_stretch.l": ("arm_stretch.l", "forearm_stretch.l", "hand.l"),
    "forearm_stretch.r": ("arm_stretch.r", "forearm_stretch.r", "hand.r"),
    "leg_stretch.l": ("thigh_stretch.l", "leg_stretch.l", "foot.l"),
    "leg_stretch.r": ("thigh_stretch.r", "leg_stretch.r", "foot.r"),
}
SOGLIA = 3.0  # cm


def _strumenti(sc):
    ds = sc.domain_scene()
    mv = ds.model_viewer()
    dv = mv.data_viewer()
    ob = {mv.get_object_name(o): o for o in mv.get_objects()}

    def ch(n, d):
        return {dv.get_data_name(i): i for i in dv.get_all_data_id(ob[n])}[d]

    def pos(n, f):
        return np.array(dv.get_data_value(ch(n, "Position"), f), dtype=float)
    return ds, dv, ch, pos


def correggi():
    app = csc.app.get_application()
    sm = app.get_scene_manager()
    riggata = app.current_scene()
    with open(CARTELLA + "scena_pose.txt", encoding="utf-8") as f:
        nome_pose = f.read().strip()
    with open(CARTELLA + "chiavi_da_tenere.txt", encoding="utf-8") as f:
        k = json.load(f)
    chiavi = [c + k.get("sposta", 0) for c in k["chiavi"]]
    pose = [s for s in sm.scenes() if s.name() == nome_pose]
    if not pose:
        print("[gomiti] NON trovo la scena delle pose %s" % nome_pose)
        return
    sm.set_current_scene(pose[0])
    _, _, _, pos_p = _strumenti(app.current_scene())
    attesi = {}
    for arto, (a, b, c) in ARTI.items():
        attesi[arto] = {f: (pos_p(a, f), pos_p(b, f), pos_p(c, f)) for f in chiavi}
    sm.set_current_scene(riggata)
    ds, dv, ch, pos = _strumenti(app.current_scene())

    da_scrivere = {}
    for arto, per_frame in attesi.items():
        scarto = max(np.linalg.norm(pos(arto, f) - per_frame[f][1]) for f in chiavi)
        if scarto <= SOGLIA:
            print("[gomiti] %s a posto (al piu' %.1f cm)" % (arto, scarto))
            continue
        direzioni = {}
        for f, (s, e, h) in per_frame.items():
            asse = (h - s) / np.linalg.norm(h - s)
            d = e - s
            d = d - asse * np.dot(d, asse)
            direzioni[f] = d / np.linalg.norm(d) * 50.0
        da_scrivere[arto] = (direzioni, scarto)

    if not da_scrivere:
        return

    def scrivi(me, up, upd, se):
        de = me.data_editor()
        for arto, (direzioni, _) in da_scrivere.items():
            for f, d in direzioni.items():
                de.set_data_value(ch(arto + "_LimbDir", "Direction"), f, d)
    ds.modify_update_with_session("gomiti e ginocchia dalle pose", scrivi)
    for arto, (_, prima) in da_scrivere.items():
        dopo = max(np.linalg.norm(pos(arto, f) - attesi[arto][f][1]) for f in chiavi)
        print("[gomiti] %s raddrizzato: era a %.1f cm dalla posa, ora a %.1f" % (arto, prima, dopo))


try:
    correggi()
except Exception:
    print("ECCEZIONE:\n" + traceback.format_exc())
