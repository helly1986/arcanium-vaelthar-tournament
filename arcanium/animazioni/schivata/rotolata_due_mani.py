# -*- coding: utf-8 -*-
"""Le POSE CHIAVE della ROTOLATA a due mani (root-RollHeavy) sullo scheletro ARP, per il
motion generation di Cascadeur.

    python arcanium/animazioni/schivata/rotolata_due_mani.py <campione> <uscita.json>

La rotolata a una mano (rotolata_una_mano.py) portata sul corpo (CORPI di
cammino_due_mani.py), con l'arma a due mani DI TRAVERSO AL PETTO (l'utente, 2026-11-11):
l'asta sta lungo l'asse su cui gira la capriola (destra-sinistra), cosi' resta parallela al
suolo e non spazza il terreno. Le mani come nell'idle a bilancia (idle_zarine.py `giogo`):
la destra verso il contrappeso, la lama verso la sua sinistra.

L'asta pero' non e' centrata nelle mani: dal lato del contrappeso sporge 69 cm, da quello
della lama 116. Si rotola sopra la spalla DESTRA, cosi' scende il lato corto e la lama sale;
la testa si piega a sinistra.

Durata e strada come la rotolata a una mano (0,83 s, 4,5 m: i frame d'invulnerabilita' sono
gli stessi per tutte le armi). Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la
sua sinistra. Misure in cm.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "locomozione"))
from rotolata_una_mano import _gira_x, _rz, _piu, _gamba, FRAMES, CHIAVI, STRADA  # noqa: E402
from cammino_due_mani import CORPI  # noqa: E402

## Come la una mano, coi segni del fianco e della piega rovesciati (spalla destra).
POSE = {
    0: {"giro": 25.0, "alto": 80.0, "arrotola": 10.0, "testa": 10.0},
    5: {"giro": 80.0, "alto": 70.0, "arrotola": 25.0, "testa": 30.0, "fianco": 15.0, "piega": -10.0},
    9: {"giro": 165.0, "alto": 71.0, "arrotola": 35.0, "testa": 35.0, "fianco": 30.0, "piega": -40.0},
    13: {"giro": 270.0, "alto": 28.0, "arrotola": 35.0, "testa": 35.0, "fianco": 15.0, "piega": -15.0},
    17: {"giro": 390.0, "alto": 52.0, "arrotola": 15.0, "testa": -5.0},
    21: {"giro": 375.0, "alto": 82.0, "arrotola": 5.0, "testa": -5.0},
    24: {"giro": 366.0, "alto": 99.0, "arrotola": 2.0, "testa": 0.0},
}


def posa(nome, f):
    c = CORPI[nome]
    k = c["scala"]
    arma, sm = c["arma"], c["seconda_mano"]
    p = POSE[f]
    giro, alto = p["giro"], p["alto"] * k
    fianco = p.get("fianco", 0.0)
    caviglia = c["caviglia"]

    def _rx(v, gradi):
        return _rz(_gira_x(v, gradi), fianco)

    def s(v):
        return [x * k for x in v]

    z = STRADA * f / (FRAMES - 1)
    bacino = [0.0, alto, z]
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, alto - c["bacino"], 0]},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": giro},
        {"osso": "root.x", "asse": [0, 0, 1], "gradi": fianco},
    ]
    avanti_corpo = _rx([0, 1.0, 1.0], giro)
    raccolta = {"l": _rx(s([12.0, -22.0, 18.0]), giro), "r": _rx(s([-12.0, -22.0, 18.0]), giro)}
    if f == 0:
        passi += _gamba("r", [-10.0 * k, caviglia, z + 32.0 * k], [0, 0, 1])
        passi += _gamba("l", [10.0 * k, 26.0 * k, z - 38.0 * k], [0, 0, 1], 35.0)
    elif f == 5:
        passi += _gamba("l", [10.0 * k, 22.0 * k, z - 55.0 * k], [0, -0.3, 1], 45.0)
        passi += _gamba("r", _piu(bacino, raccolta["r"]), avanti_corpo, giro)
    elif f in (9, 13):
        for lato in "lr":
            passi += _gamba(lato, _piu(bacino, raccolta[lato]), avanti_corpo, giro)
    elif f == 17:
        passi += _gamba("l", [10.0 * k, caviglia, z + 12.0 * k], [0.1, 0, 1])
        passi += _gamba("r", [-10.0 * k, caviglia, z + 18.0 * k], [-0.1, 0, 1])
    elif f == 21:
        passi += _gamba("l", [10.0 * k, caviglia, z - 18.0 * k], [0.1, 0, 1], -10.0)
        passi += _gamba("r", [-10.0 * k, caviglia, z + 16.0 * k], [-0.1, 0, 1])
    else:
        passi += _gamba("l", [10.0 * k, caviglia, z - 10.0 * k], [0.1, 0, 1])
        passi += _gamba("r", [-10.0 * k, caviglia, z + 12.0 * k], [-0.1, 0, 1])
    arrotola = p["arrotola"]
    passi += [
        {"osso": "spine_01.x", "asse": _rx([1, 0, 0], giro), "gradi": arrotola * 0.5},
        {"osso": "spine_03.x", "asse": _rx([1, 0, 0], giro), "gradi": arrotola * 0.5},
    ]
    ## L'asta di traverso davanti al petto: la destra a destra del centro, l'asta verso la
    ## sua sinistra (l'asse X del corpo), il polso che guarda giu' verso il corpo.
    petto = giro + arrotola
    destra = _piu(bacino, _rx(s([-16.0, 26.0, 22.0]), petto))
    passi += [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": destra, "polo": _rx([-1, -1, -0.3], petto)}},
        {"osso": "hand.r", "mira": {"oggetto": arma, "asse": [0, 1, 0], "verso": _rx([1.0, 0.0, 0.0], petto)},
         "rollio": {"oggetto": arma, "asse": [-1, 0, 0], "verso": _rx([0.0, -0.6, -0.8], petto)}},
        {"chiudi_mano": {"lato": "r", "chiusura": c["chiusura_destra"], "pollice": c["pollice_destra"]}},
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio_su": {"oggetto": arma, "punto": [sm[9] * 100.0, sm[10] * 100.0 + c["seconda_mano_scorre"],
                                                           sm[11] * 100.0]},
                "polo": _rx([1, -1, -0.2], petto)}},
        {"osso": "hand.l", "orienta_su": {"oggetto": arma, "base": sm[:9]}},
        {"chiudi_mano": {"lato": "l", "chiusura": c["chiusura_sinistra"], "pollice": c["pollice_sinistra"]}},
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": _rx([1, 0, 0], petto), "gradi": p["testa"]},
        {"osso": "head.x", "asse": _rx([0, 0, 1], petto), "gradi": p.get("piega", 0.0)},
    ]
    return passi


def spec(nome):
    return {
        "_nota": "Generato da arcanium/animazioni/schivata/rotolata_due_mani.py (%s): non si modifica a mano." % nome,
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(nome, f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1]), uscita, indent=1)
    print("scritto", sys.argv[2], sys.argv[1], len(CHIAVI), "pose")
