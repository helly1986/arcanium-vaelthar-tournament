# -*- coding: utf-8 -*-
"""Le POSE CHIAVE della GUARDIA con lo scudo (Guarding), a una mano su Edran, per il motion
generation di Cascadeur.

    python arcanium/animazioni/difesa/parata_una_mano.py <uscita.json>

L'utente, 2026-11-11: «il blocco fa salire lo scudo per protezione». Tenendo premuto il blocco
il gioco fonde questa clip sulla parte ALTA del corpo (petto, collo, testa, braccia: il blend
`Guarding` filtrato del player) sopra qualunque clip delle gambe, e la toglie quando si
rilascia. Le gambe qui sono solo quelle della guardia ferma (guardia_una_mano.py), per
vederla intera.

Alla souls-like: lo scudo davanti al petto, alto fino al mento, la faccia verso il nemico; il
busto un poco raccolto dietro, il mento basso che guarda sopra il bordo; la spada accanto
al bordo destro dello scudo, la punta avanti, pronta all'affondo. Un ciclo di respiro
lento (1,6 s): il petto sale di poco e lo scudo con lui.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm, dal
corpo ARP di Edran: bacino a 105,1, caviglia a 14,6.
"""
import json
import math
import sys

FRAMES = 49
CHIAVI = [0, 24, 48]

CAVIGLIA = 14.6
SPADA = "RightHand_Sword"
SCUDO = "LeftHand_Mesh"

## La guardia ferma di guardia_una_mano.py: il sinistro avanti, il bacino basso e girato.
STRETTA = {"l": (11.0, 16.0), "r": (-11.0, -16.0)}
PUNTE = {"l": -8.0, "r": 18.0}
BACINO_GIU = 9.0
BACINO_GIRO = 12.0

## Per chiave: quanto sale il respiro (cm), quanto si raccoglie il busto (gradi).
RESPIRO = {0: 0.0, 24: 1.2, 48: 0.0}

## Lo scudo davanti al petto, a sinistra del centro, alto: il bordo sopra copre il mento.
MANO_SINISTRA = [10.0, 124.0, 30.0]
## La spada FUORI dal bordo destro dello scudo, la punta avanti: lo scudo e' largo (il bordo
## destro sta a x -25), e una spada che punta al centro lo attraversava (primo foglio).
MANO_DESTRA = [-30.0, 126.0, 16.0]
SCUDO_VERSO = [-0.1, 0.05, 1.0]
SPADA_VERSO = [-0.04, 0.06, 1.0]


def posa(f):
    return posa_guardia(RESPIRO[f])


def posa_guardia(su=0.0, colpo=None):
    """La guardia col respiro `su`; `colpo` la sposta per il colpo preso sullo scudo
    (parata_colpo_una_mano.py): `scudo` [x, y, z] cm, `inclina` gradi (la faccia dello scudo
    verso l'alto), `petto` e `schiena` gradi all'indietro (spine_03, spine_01), `giro` gradi
    (la spalla sinistra indietro), `bacino` gradi all'indietro."""
    c = colpo or {}
    passi = [
        {"osso": "root.x", "sposta": [0, -BACINO_GIU, 1.0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": BACINO_GIRO},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": 4.0 - c.get("bacino", 0.0)},
    ]
    for s in "lr":
        x, z = STRETTA[s]
        lato = 1.0 if s == "l" else -1.0
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": [x, CAVIGLIA, z], "polo": [0.25 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": PUNTE[s] * lato},
        ]
    ## Il busto raccolto dietro lo scudo: le spalle un poco avanti e chiuse, e tornano verso il
    ## nemico ripagando il giro del bacino. Col respiro il petto si apre appena.
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 4.0 - c.get("schiena", 0.0)},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -BACINO_GIRO * 0.5 + c.get("giro", 0.0) * 0.4},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 6.0 - su * 1.5 - c.get("petto", 0.0)},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -BACINO_GIRO * 0.5 + c.get("giro", 0.0) * 0.6},
    ]
    sx, dx = MANO_SINISTRA, MANO_DESTRA
    sp = c.get("scudo", [0.0, 0.0, 0.0])
    sx = [sx[0] + sp[0], sx[1] + sp[1], sx[2] + sp[2]]
    t = math.radians(c.get("inclina", 0.0))
    v = SCUDO_VERSO
    scudo_verso = [v[0], v[1] * math.cos(t) + v[2] * math.sin(t), -v[1] * math.sin(t) + v[2] * math.cos(t)]
    passi += [
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": [sx[0], sx[1] + su, sx[2]], "polo": [1, -1, -0.2]}},
        ## Lo scudo si orienta girando l'avambraccio su se stesso, non il polso
        ## (guardia_una_mano.py).
        {"osso": "forearm_stretch.l", "mira": {"punto": "hand.l"},
         "rollio": {"oggetto": SCUDO, "asse": [0, 0, 1], "verso": scudo_verso}},
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [dx[0], dx[1] + su, dx[2]], "polo": [-1, -0.6, -0.4]}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": SPADA_VERSO}},
        ## Il mento basso: guarda sopra il bordo dello scudo.
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": 10.0},
    ]
    return passi


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/difesa/parata_una_mano.py: non si modifica a mano.",
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as uscita:
        json.dump(spec(), uscita, indent=1)
    print("scritto", sys.argv[1], len(CHIAVI), "pose")
