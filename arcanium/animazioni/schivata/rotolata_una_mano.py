# -*- coding: utf-8 -*-
"""Le POSE CHIAVE della ROTOLATA a una mano (root-Roll) sullo scheletro ARP, per il motion
generation di Cascadeur.

    python arcanium/animazioni/schivata/rotolata_una_mano.py <uscita.json>

L'utente, 2026-11-10: la schivata nostra PER ARMA, prima quella a una mano su Edran (spada e
scudo), poi quella a due mani su Zarine; da fermi, al posto della rotolata suonata al
contrario, un piccolo salto all'indietro alla souls-like (un'altra clip).

La rotolata in avanti sopra la spalla, alla souls-like: si accuccia, si tuffa con lo scudo
avanti, tocca terra con la spalla e la schiena col bacino che passa sopra la testa, si
raccoglie con le ginocchia al petto, poggia i piedi accosciato e si rialza in guardia. Il
corpo gira di 360 gradi attorno al suo asse laterale (+X): `GIRO` per chiave, il bacino e'
il perno.

Durata e strada come la rotolata di MeleeLib che sostituisce (0,83 s, 4,5 m): da quella
durata il gioco misura i frame d'invulnerabilita' (player_charbody3D.gd `dodge`).
25 frame a 30 fps (0..24) e un frame di riposo dopo (`base`). Non e' un ciclo: si tagliano
solo gli estremi.

Le gambe e le braccia si danno nel riferimento del CORPO (girato col bacino) quando non
toccano terra, nel mondo quando poggiano.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm, dal
corpo ARP di Edran: bacino a 105,1, caviglia a 14,6.
"""
import json
import math
import sys

FRAMES = 25
CHIAVI = [0, 5, 9, 13, 17, 21, 24]
STRADA = 450.0

BACINO = 105.1
CAVIGLIA = 14.6
SPADA = "RightHand_Sword"

## Per chiave: giro del bacino attorno a +X (positivo = il busto va avanti), altezza del
## bacino da terra, quanto il busto si arrotola in piu' (gradi, diviso fra spine_01 e
## spine_03), la testa china; `fianco` gira il corpo attorno a +Z (la direzione di corsa),
## `piega` la testa di lato.
##
## L'utente, 2026-11-10, sul primo foglio: a f9 la testa entrava nel terreno. Si rotola in
## DIAGONALE sopra la spalla SINISTRA (quella dello scudo: la spada resta dal lato libero),
## e la testa si piega verso destra, fuori dalla strada.
POSE = {
    0: {"giro": 25.0, "alto": 80.0, "arrotola": 10.0, "testa": 10.0},
    5: {"giro": 80.0, "alto": 70.0, "arrotola": 25.0, "testa": 30.0, "fianco": -15.0, "piega": 10.0},
    9: {"giro": 165.0, "alto": 65.0, "arrotola": 35.0, "testa": 35.0, "fianco": -35.0, "piega": 35.0},
    13: {"giro": 270.0, "alto": 28.0, "arrotola": 35.0, "testa": 35.0, "fianco": -20.0, "piega": 15.0},
    ## Uscendo in avanti il petto passa SOPRA le ginocchia: il giro supera il giro intero e
    ## torna (a 315 il busto stava indietro).
    17: {"giro": 390.0, "alto": 52.0, "arrotola": 15.0, "testa": -5.0},
    21: {"giro": 375.0, "alto": 82.0, "arrotola": 5.0, "testa": -5.0},
    24: {"giro": 366.0, "alto": 99.0, "arrotola": 2.0, "testa": 0.0},
}


def _gira_x(v, gradi):
    """Rotazione attorno a +X: positivo porta +Y verso +Z."""
    t = math.radians(gradi)
    x, y, z = v
    return [x, y * math.cos(t) - z * math.sin(t), y * math.sin(t) + z * math.cos(t)]


def _rz(v, gradi):
    """Rotazione attorno a +Z: positivo porta +X verso +Y."""
    t = math.radians(gradi)
    x, y, z = v
    return [x * math.cos(t) - y * math.sin(t), x * math.sin(t) + y * math.cos(t), z]


def _piu(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]


def _gamba(s, bersaglio, polo, piede_giro=None):
    passi = [
        {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                "bersaglio": bersaglio, "polo": polo}},
        {"osso": "foot." + s, "come_base": True},
    ]
    if piede_giro:
        passi.append({"osso": "foot." + s, "asse": [1, 0, 0], "gradi": piede_giro})
    return passi


def posa(f):
    p = POSE[f]
    giro, alto = p["giro"], p["alto"]
    fianco = p.get("fianco", 0.0)

    def _rx(v, gradi):
        ## Il riferimento del corpo: prima il giro, poi il fianco.
        return _rz(_gira_x(v, gradi), fianco)

    z = STRADA * f / (FRAMES - 1)
    bacino = [0.0, alto, z]
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, alto - BACINO, 0]},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": giro},
        {"osso": "root.x", "asse": [0, 0, 1], "gradi": fianco},
    ]
    ## Le gambe. A terra all'inizio e alla fine; in aria raccolte, i talloni sotto il sedere e
    ## le ginocchia verso il petto (nel riferimento del corpo).
    ## Le ginocchia verso il petto: il polo guarda avanti e in su nel corpo.
    avanti_corpo = _rx([0, 1.0, 1.0], giro)
    raccolta = {"l": _rx([12.0, -22.0, 18.0], giro), "r": _rx([-12.0, -22.0, 18.0], giro)}
    if f == 0:
        passi += _gamba("r", [-10.0, CAVIGLIA, z + 32.0], [0, 0, 1])
        passi += _gamba("l", [10.0, 26.0, z - 38.0], [0, 0, 1], 35.0)
    elif f == 5:
        passi += _gamba("l", [10.0, 22.0, z - 55.0], [0, -0.3, 1], 45.0)
        passi += _gamba("r", _piu(bacino, raccolta["r"]), avanti_corpo, giro)
    elif f in (9, 13):
        for s in "lr":
            passi += _gamba(s, _piu(bacino, raccolta[s]), avanti_corpo, giro)
    elif f == 17:
        passi += _gamba("l", [10.0, CAVIGLIA, z + 12.0], [0.1, 0, 1])
        passi += _gamba("r", [-10.0, CAVIGLIA, z + 18.0], [-0.1, 0, 1])
    elif f == 21:
        passi += _gamba("l", [10.0, CAVIGLIA, z - 18.0], [0.1, 0, 1], -10.0)
        passi += _gamba("r", [-10.0, CAVIGLIA, z + 16.0], [-0.1, 0, 1])
    else:
        passi += _gamba("l", [10.0, CAVIGLIA, z - 10.0], [0.1, 0, 1])
        passi += _gamba("r", [-10.0, CAVIGLIA, z + 12.0], [-0.1, 0, 1])
    ## Il busto si arrotola (per arrivare a terra con la schiena tonda) e la testa si china:
    ## nel tuffo va giu' il mento, non la nuca.
    arrotola = p["arrotola"]
    passi += [
        {"osso": "spine_01.x", "asse": _rx([1, 0, 0], giro), "gradi": arrotola * 0.5},
        {"osso": "spine_03.x", "asse": _rx([1, 0, 0], giro), "gradi": arrotola * 0.5},
    ]
    ## Le braccia raccolte, nel riferimento del petto: lo scudo davanti al petto, la spada
    ## stretta lungo il fianco con la lama verso i piedi, perche' non tocchi terra.
    petto = giro + arrotola
    scudo = _piu(bacino, _rx([14.0, 26.0, 26.0], petto))
    mano_spada = _piu(bacino, _rx([-20.0, 22.0, 12.0], petto))
    passi += [
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": scudo, "polo": _rx([1, -1, -0.3], petto)}},
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": mano_spada, "polo": _rx([-1, -0.3, -0.6], petto)}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": _rx([-0.1, -1.0, -0.35], petto)}},
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": _rx([1, 0, 0], petto), "gradi": p["testa"]},
        {"osso": "head.x", "asse": _rx([0, 0, 1], petto), "gradi": p.get("piega", 0.0)},
    ]
    return passi


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/schivata/rotolata_una_mano.py: non si modifica a mano.",
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as uscita:
        json.dump(spec(), uscita, indent=1)
    print("scritto", sys.argv[1], len(CHIAVI), "pose")
