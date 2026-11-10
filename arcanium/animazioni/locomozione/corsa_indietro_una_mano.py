# -*- coding: utf-8 -*-
"""Le POSE CHIAVE della CORSA ALL'INDIETRO a una mano col nemico agganciato, per il motion
generation di Cascadeur (stile Run).

    python arcanium/animazioni/locomozione/corsa_indietro_una_mano.py <uscita.json>

Agganciati, con la corsa chiesta (Alt tenuto o L3) e la levetta indietro, la blend space
`MoveStrafe` arriva al punto (0, -0,9): fino al 2026-11-10 li' suonava la corsa in avanti
AL CONTRARIO. Questa e' la clip nostra, `root-LightStrafeBrun` (player_anim_tree.gd,
AGGANCIO).

Alla souls-like: si arretra di corsa guardando il bersaglio, con passi corti e svelti. Il
busto pende un poco AVANTI, verso il nemico, per non cadere all'indietro; il piede che
arriva tocca DIETRO il bacino sull'avampiede (tallone su), l'altro ha appena spinto
davanti e si stacca col ginocchio piegato. Le braccia restano in guardia davanti al petto,
uguali sui due contatti: la clip e' simmetrica, come le coppie destra/sinistra
([[clip-coppie-speculari]]).

Stessa struttura della corsa (`corsa_una_mano.py`): 33 frame, una chiave a ogni contatto (il
sinistro a 0, 16 e 32, il destro a 8 e 24), dalla generazione si tiene il ciclo di mezzo.

Velocita' 3,6 m/s: meno dello strafe di corsa (4,8), come nei souls, dove arretrare costa.
12 cm per frame, passi da 96 cm.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti (il bersaglio), +X la sua sinistra.
Misure in cm, dal corpo ARP di Edran: bacino a 105,1, caviglia a 14,6.
"""
import json
import sys

FRAMES = 33
CHIAVI = [0, 8, 16, 24, 32]
CICLO = 16
VELOCITA = 360.0  # cm/s
AVANZA = -VELOCITA / 30.0  # si va verso -Z

SPADA = "RightHand_Sword"
SCUDO = "LeftHand_Mesh"

## Il bacino: basso (le ginocchia lavorano), un poco girato verso la gamba che arriva
## dietro, chino verso il bersaglio.
BACINO_GIU = 9.0
BACINO_GIRO = 5.0
BACINO_PENDE = 6.0
## Il piede che arriva tocca dietro il bacino, sull'avampiede: caviglia piu' alta del
## riposo e punte giu'.
CONTATTO = -22.0
CONTATTO_Y = 19.0
CONTATTO_PUNTE = 28.0
## L'altro ha appena spinto davanti: su, ginocchio piegato, punte un poco giu'.
DAVANTI = 30.0
DAVANTI_Y = 34.0
DAVANTI_PUNTE = 18.0
LARGHEZZA = 10.0
## Il busto pende avanti (gradi su X, positivo = avanti); la testa ripaga per guardare il
## bersaglio.
PENDE_BASSO = 5.0
PENDE_ALTO = 4.0
TESTA = -10.0

## Le mani in guardia, nel mondo dal centro del corpo; sobbalzano al contatto.
MANO_SINISTRA = [20.0, 112.0, 26.0]
MANO_DESTRA = [-24.0, 110.0, 18.0]
SOBBALZO = 3.0
SCUDO_VERSO = [0.1, 0.1, 1.0]
SPADA_VERSO = [0.1, 0.5, 1.0]


def posa(f):
    z = AVANZA * f
    tocca = 1.0 if f % CICLO == 0 else -1.0  # +1: arriva il sinistro
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, -BACINO_GIU, 0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": -BACINO_GIRO * tocca},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": BACINO_PENDE},
    ]
    for lato, s in ((1.0, "l"), (-1.0, "r")):
        if lato == tocca:
            avanti, su, punte = CONTATTO, CONTATTO_Y, CONTATTO_PUNTE
        else:
            avanti, su, punte = DAVANTI, DAVANTI_Y, DAVANTI_PUNTE
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": [LARGHEZZA * lato, su, z + avanti], "polo": [0.08 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": -8.0 * lato},
            {"osso": "foot." + s, "asse": [1, 0, 0], "gradi": punte},
        ]
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": PENDE_BASSO},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": BACINO_GIRO * 0.8 * tocca},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": PENDE_ALTO},
    ]
    sx, dx = MANO_SINISTRA, MANO_DESTRA
    passi += [
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": [sx[0], sx[1] - SOBBALZO, z + sx[2]], "polo": [1, -1, -0.3]}},
        {"osso": "forearm_stretch.l", "mira": {"punto": "hand.l"},
         "rollio": {"oggetto": SCUDO, "asse": [0, 0, 1], "verso": SCUDO_VERSO}},
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [dx[0], dx[1] - SOBBALZO, z + dx[2]], "polo": [-1, -1, -0.3]}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": SPADA_VERSO}},
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": TESTA},
    ]
    return passi


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/corsa_indietro_una_mano.py: non si modifica a mano.",
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as uscita:
        json.dump(spec(), uscita, indent=1)
    print("scritto", sys.argv[1], len(CHIAVI), "pose")
