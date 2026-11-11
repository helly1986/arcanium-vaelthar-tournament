# -*- coding: utf-8 -*-
"""Le POSE CHIAVE del SALTO ALL'INDIETRO a due mani (la schivata da fermi, root-BackstepHeavy)
sullo scheletro ARP, per il motion generation di Cascadeur.

    python arcanium/animazioni/schivata/salto_indietro_due_mani.py <campione> <uscita.json>

Il salto a una mano (salto_indietro_una_mano.py) portato IN GUARDIA a due mani (l'utente,
2026-11-11): la guardia di guardia_due_mani.py, col DESTRO avanti, il bacino girato col fianco
sinistro indietro, la destra davanti sull'asta presa da sopra e la sinistra al suo posto del
gioco, la lama avanti e in fuori a destra. Le braccia restano in guardia per tutto il salto:
l'arma non si muove rispetto al petto.

Stessa fisica e stessi tempi del salto a una mano (i frame d'invulnerabilita' sono gli stessi
per tutte le armi): stacco a f4, atterraggio a f12, in volo il bacino sulla parabola vera a
3,6 m/s all'indietro (colmo g t^2 / 8 = 8,7 cm a f8). Atterra prima il SINISTRO, quello
dietro, e frena; poi torna in guardia. Le misure del corpo sono in scala (CORPI), le
distanze del volo no: sono fisica.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "locomozione"))
from salto_indietro_una_mano import FRAMES, CHIAVI, STACCO, ATTERRA, _in_volo  # noqa: E402
from cammino_due_mani import CORPI  # noqa: E402

## La guardia (guardia_due_mani.py): il bacino scende di 8 cm (in scala), gira di -14 gradi
## attorno a Y e pende di 3 in avanti.
GIRO = -14.0

## Per chiave: dove sta il bacino lungo Z, quanto scende sotto il riposo, di quanto pende
## avanti in piu' della guardia. Il volo (f4-f12) e' la parabola del salto a una mano.
POSE = {
    0: {"z": 0.0, "giu": 8.0, "pende": 0.0},
    STACCO: {"z": _in_volo(STACCO)[0], "giu": 15.0, "pende": 7.0},
    8: {"z": _in_volo(8)[0], "giu": 15.0 - (12.0 - _in_volo(8)[1]), "pende": 4.0},
    ATTERRA: {"z": _in_volo(ATTERRA)[0], "giu": 15.0, "pende": 1.0},
    15: {"z": -134.0, "giu": 20.0, "pende": 9.0},
    17: {"z": -138.0, "giu": 9.0, "pende": 2.0},
}


def posa(nome, f):
    c = CORPI[nome]
    k = c["scala"]
    sm = c["seconda_mano"]
    p = POSE[f]
    z = p["z"]
    ## Non in scala: la parabola e' fisica (il colmo resta 8,7 cm).
    giu = p["giu"]
    alto = c["bacino"] - giu
    caviglia = c["caviglia"]
    ## In guardia: il DESTRO avanti di 28 cm (in scala), piedi a 20 cm di larghezza; dove
    ## atterra, la stessa guardia attorno al bacino arrivato.
    guardia = {"r": (-10.0 * k, 14.0 * k), "l": (10.0 * k, -14.0 * k)}
    z_fine = POSE[17]["z"]
    punte = {"r": -6.0, "l": 18.0}
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, -giu, 1.0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": GIRO},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": 3.0 + p["pende"]},
    ]
    for s in "lr":
        x, gz = guardia[s]
        lato = 1.0 if s == "l" else -1.0
        giu_punte = 0.0
        if f <= STACCO:
            bersaglio = [x, caviglia, gz]
        elif f < ATTERRA:
            ## In volo, basso: le ginocchia piegate, i piedi sotto il bacino, le punte giu'.
            ## Il destro (davanti) piu' su e avanti, il sinistro pronto a toccare.
            bersaglio = [x, caviglia + (14.0 if s == "r" else 10.0) * k, z + (14.0 if s == "r" else -10.0) * k]
            giu_punte = 25.0
        elif f == ATTERRA and s == "r":
            ## Atterra il sinistro, dietro il bacino a frenare; il destro e' ancora su.
            bersaglio = [x, caviglia + 6.0 * k, z_fine + gz + 4.0 * k]
            giu_punte = 15.0
        else:
            bersaglio = [x, caviglia, z_fine + gz]
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": bersaglio, "polo": [0.25 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": punte[s] * lato},
        ]
        if giu_punte:
            passi.append({"osso": "foot." + s, "asse": [1, 0, 0], "gradi": giu_punte})
    ## Il busto della guardia, e ripaga meta' del pendere: lo sguardo resta avanti.
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 3.0 - p["pende"] * 0.3},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -GIRO * 0.3},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 4.0 - p["pende"] * 0.2},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -GIRO * 0.3},
    ]
    ## Le mani della guardia, che seguono il bacino: nella guardia ferma la destra sta 18,6 cm
    ## sopra il bacino (a 104 col bacino a 92,4 - 8 in scala) e 27 cm davanti.
    sopra = 104.0 - (c["bacino"] - 8.0 * k)
    passi += [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [-2.0, alto + sopra, z + 28.0], "polo": [-1, 0.3, -0.6]}},
        {"osso": "hand.r", "mira": {"oggetto": c["arma"], "asse": [0, 1, 0], "verso": [-0.55, 0.25, 1.0]},
         "rollio": {"oggetto": c["arma"], "asse": [-1, 0, 0], "verso_osso": ["hand.r", "forearm_stretch.r"]}},
        {"chiudi_mano": {"lato": "r", "chiusura": c["chiusura_destra"], "pollice": c["pollice_destra"]}},
        {"presa_su": {"lato": "l", "oggetto": c["arma"], "base": sm[:9], "punto": [v * 100.0 for v in sm[9:12]],
                      "polo": [1, 0.2, -0.6]}},
        {"chiudi_mano": {"lato": "l", "chiusura": c["chiusura_sinistra"], "pollice": c["pollice_sinistra"]}},
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": -p["pende"] * 0.4},
    ]
    return passi


def spec(nome):
    return {
        "_nota": "Generato da arcanium/animazioni/schivata/salto_indietro_due_mani.py (%s): non si modifica a mano." % nome,
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(nome, f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1]), uscita, indent=1)
    print("scritto", sys.argv[2], sys.argv[1], len(CHIAVI), "pose")
