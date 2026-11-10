# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dell'idle di Zarine (docs/campioni_concept.md), sullo scheletro ARP.

    python arcanium/animazioni/idle_campioni/idle_zarine.py <uscita.json>

Il concept: l'asta orizzontale davanti al corpo diventa il giogo di una bilancia; la lascia
pendere, la mano dal lato del contrappeso scende e quella dal lato della lama sale, poi il
contrario; la riporta in pari, resta un respiro col capo appena inclinato, come chi ha pesato.
Le mani non lasciano mai l'asta.

L'utente, 2026-11-10: la bilancia, ma PARTENDO DALL'ASTA IN SPALLA e tornandoci, come la porta
nel cammino a due mani (cammino_due_mani.py): cosi' l'idle si lega al cammino senza strappi.
L'idle prende il posto della HeavyIdle (CorpoCampione.idle_sostituita).

181 frame a 30 fps (6 s), in loop: il frame 0 e il 180 sono la stessa posa, l'asta in spalla.
La base di lavorazione tiene il riposo al frame 181 (`base`); per il rig la si porta in testa
(base_con_pose_cascadeur.py `riposo_in_testa`), perche' con la sinistra che attraversa il petto
il QRT di Cascadeur non costruisce il rig.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm.
L'asta corre lungo il suo +Y, da -67 (contrappeso) a +118 (lama); il polso destro le sta a
y -14. Orizzontale davanti a lei, la lama va verso la sua sinistra (+X): il contrappeso sta
dalla parte della destra.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "locomozione"))
from cammino_due_mani import CORPI  # noqa: E402

C = CORPI["zarine"]
ARMA = C["arma"]
SM = C["seconda_mano"]

FRAMES = 182
BASE = 181
CHIAVI = [0, 20, 40, 62, 88, 112, 135, 155, 180]


def _norm(v):
    n = math.sqrt(sum(x * x for x in v))
    return [x / n for x in v]


def gambe(giu=1.5):
    """In piedi: il bacino scende appena (le ginocchia morbide), i piedi restano dove sono."""
    passi = [{"osso": "root.x", "sposta": [0, -giu, 0]}]
    for s, lato in (("l", 1.0), ("r", -1.0)):
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "polo": [0.1 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
        ]
    return passi


def busto(respiro=0.0, gira=0.0):
    return [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 1.5},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 2.0 - respiro},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": gira},
    ]


def testa(china=2.0, inclina=0.0, gira=0.0):
    passi = [{"osso": "head.x", "come_base": True},
             {"osso": "head.x", "asse": [1, 0, 0], "gradi": china}]
    if inclina:
        passi.append({"osso": "head.x", "asse": [0, 0, 1], "gradi": inclina})
    if gira:
        passi.append({"osso": "head.x", "asse": [0, 1, 0], "gradi": gira})
    return passi


def sinistra():
    """La sinistra sull'asta dove la tiene nel cammino, con le dita chiuse; anche la destra."""
    return [
        {"chiudi_mano": {"lato": "r", "chiusura": C["chiusura_destra"], "pollice": C["pollice_destra"]}},
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio_su": {"oggetto": ARMA, "punto": [SM[9] * 100.0, SM[10] * 100.0 + C["seconda_mano_scorre"],
                                                           SM[11] * 100.0]},
                "polo": [1, -1, -0.2]}},
        {"osso": "hand.l", "orienta_su": {"oggetto": ARMA, "base": SM[:9]}},
        {"chiudi_mano": {"lato": "l", "chiusura": C["chiusura_sinistra"], "pollice": C["pollice_sinistra"]}},
    ]


def in_spalla(su=0.0):
    """L'asta appoggiata sulla spalla destra, come nel cammino."""
    d, sp = C["mano_destra"], C["spalla"]
    mira = {"osso": "hand.r", "mira": {"oggetto": ARMA, "asse": [0, 1, 0],
                                       "verso_punto": {"punto": [sp[0], sp[1] + su, sp[2]],
                                                       "da": C["presa_destra"]}}}
    rollio = {"osso": "hand.r", "mira": {"oggetto": ARMA, "asse": [0, 1, 0]},
              "rollio": {"oggetto": ARMA, "asse": [-1, 0, 0], "verso": C["polso_verso"]}}
    return [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [d[0], d[1] + su * 0.3, d[2]], "polo": [-1, -1, -0.2]}},
        mira, rollio, mira, mira,
    ] + sinistra()


def staccata():
    """A meta' strada: l'asta si alza dalla spalla e viene avanti, ancora inclinata."""
    return [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [-15.0, 106.0, 26.0], "polo": [-1, -1, -0.2]}},
        {"osso": "hand.r", "mira": {"oggetto": ARMA, "asse": [0, 1, 0], "verso": _norm([0.45, 0.6, -0.3])},
         "rollio": {"oggetto": ARMA, "asse": [-1, 0, 0], "verso": [-0.3, -1.0, 0.3]}},
    ] + sinistra()


def giogo(pende=0.0):
    """L'asta orizzontale davanti al petto, la lama verso la sua sinistra: il giogo. `pende`
    in gradi, positivo = la lama sale e il contrappeso (dalla parte della destra) scende."""
    t = math.radians(pende)
    ## La destra sta 12 cm a destra del centro del giogo: si alza e si abbassa con lui.
    giu = -12.0 * math.sin(t)
    return [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [-16.0, 109.0 + giu, 21.0], "polo": [-1, -1, -0.3]}},
        {"osso": "hand.r", "mira": {"oggetto": ARMA, "asse": [0, 1, 0], "verso": [math.cos(t), math.sin(t), 0.0]},
         "rollio": {"oggetto": ARMA, "asse": [-1, 0, 0], "verso": [0.0, -0.6, -0.8]}},
    ] + sinistra()


POSE = {
    0: gambe() + busto() + in_spalla() + testa(),
    20: gambe(2.0) + busto(1.0) + staccata() + testa(4),
    40: gambe(1.8) + busto(0.5) + giogo(0) + testa(8),
    62: gambe(1.8) + busto(0.0, -3.0) + giogo(12) + testa(10, 0.0, -6.0),
    88: gambe(1.8) + busto(0.0, 3.0) + giogo(-12) + testa(10, 0.0, 6.0),
    112: gambe(1.6) + busto(1.5) + giogo(0) + testa(6, 7.0),
    135: gambe(1.4) + busto(-0.5) + giogo(0) + testa(5, 5.0),
    155: gambe(2.0) + busto(1.0) + staccata() + testa(4),
    180: gambe() + busto() + in_spalla() + testa(),
}


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/idle_campioni/idle_zarine.py: non si modifica a mano.",
        "frames": FRAMES,
        "base": BASE,
        "chiavi": CHIAVI,
        "pose": {str(f): passi for f, passi in sorted(POSE.items())},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(spec(), f, indent=1)
    print("scritto", sys.argv[1], len(POSE), "pose")
