# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dello STRAFE DI CORSA a una mano col nemico agganciato, col BACINO GIRATO
alla souls-like (l'utente, 2026-11-09), per il motion generation di Cascadeur (stile Run).

    python arcanium/animazioni/locomozione/strafe_corsa_una_mano.py <sinistra|destra> <uscita.json>

Agganciati si va a passo; la corsa di lato si chiede con Alt tenuto o L3 (player_charbody3D
`corsa_chiesta`) e suona i punti (+-1, 0) della blend space `MoveStrafe`.

Alla souls-like: le gambe CORRONO verso dove si va, il bacino e' girato quasi del tutto
in quella direzione (BACINO_GIRO), e il busto si avvita indietro per tenere petto, scudo e
sguardo sul bersaglio. Le braccia non oscillano come nella corsa in avanti: restano pronte
davanti al petto e sobbalzano col passo.

Stessa struttura della corsa (`corsa_una_mano.py`): 33 frame, una chiave a ogni contatto
(il sinistro a 0, 16 e 32, il destro a 8 e 24), dalla generazione si tiene il ciclo di mezzo
(`rifinisci ... --taglia 8 24`).

Velocita' 4,8 m/s, come gli strafe di corsa della MeleeLib (4,2-5,3): 16 cm per frame,
passi da 128 cm.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti (il bersaglio), +X la sua sinistra.
Misure in cm, dal corpo ARP di Edran: bacino a 105,1, caviglia a 14,6.
"""
import json
import math
import sys

FRAMES = 33
CHIAVI = [0, 8, 16, 24, 32]
CICLO = 16
VELOCITA = 480.0  # cm/s
AVANZA = VELOCITA / 30.0

## Dove si va (x, z) e di quanti gradi gira il bacino attorno a +Y (positivo = il davanti
## del bacino va verso +X, la sua sinistra).
DIREZIONI = {"sinistra": ((1.0, 0.0), 70.0), "destra": ((-1.0, 0.0), -70.0)}

SPADA = "RightHand_Sword"
SCUDO = "LeftHand_Mesh"

CAVIGLIA_SU = 14.6
## Il bacino: piu' basso che da fermi, un poco girato verso la gamba che arriva, chino nella
## direzione di corsa.
BACINO_GIU = 10.0
BACINO_ONDA = 6.0
BACINO_PENDE = 8.0
## I piedi lungo la direzione di corsa, dal bacino: chi tocca davanti, chi ha staccato dietro
## e su; di lato (sull'asse del bacino) la larghezza.
CONTATTO = 24.0
DIETRO = -55.0
DIETRO_Y = 38.0
DIETRO_PUNTE = 50.0
PUNTE_SU = -6.0
LARGHEZZA = 9.0
## Il busto si avvita indietro verso il bersaglio: 70 gradi del bacino, 45 li ripaga la
## schiena; la testa il resto, quasi.
AVVITA_BASSO = 0.25
AVVITA_ALTO = 0.4
TESTA_AVVITA = 0.25

## Le mani, nel mondo dal centro del corpo: pronte davanti al petto verso il bersaglio, e
## sobbalzano (piu' basse al contatto, quando il corpo ammortizza).
MANO_SINISTRA = [20.0, 112.0, 26.0]
MANO_DESTRA = [-24.0, 110.0, 18.0]
SOBBALZO = 4.0
SCUDO_VERSO = [0.1, 0.1, 1.0]
SPADA_VERSO = [0.1, 0.5, 1.0]


def _ruota_y(v, gradi):
    """Rotazione attorno a +Y: positivo porta +Z verso +X."""
    t = math.radians(gradi)
    x, y, z = v
    return [x * math.cos(t) + z * math.sin(t), y, -x * math.sin(t) + z * math.cos(t)]


def posa(f, direzione):
    (dx, dz), giro = DIREZIONI[direzione]
    tocca = "l" if f % CICLO == 0 else "r"
    segno_tocca = 1.0 if tocca == "l" else -1.0
    centro = [dx * AVANZA * f, 0.0, dz * AVANZA * f]
    ## Il bacino guarda `giro` gradi verso dove si va, e ondeggia verso la gamba che arriva.
    giro_bacino = giro - BACINO_ONDA * segno_tocca
    sinistra_bacino = _ruota_y([1.0, 0.0, 0.0], giro_bacino)
    davanti_bacino = _ruota_y([0.0, 0.0, 1.0], giro_bacino)
    ## Asse attorno a cui si china verso dove si va (per l'avanti e' +X).
    china = [dz, 0.0, -dx]
    passi = [
        {"osso": "c_traj", "sposta": [centro[0], 0, centro[2]]},
        {"osso": "root.x", "sposta": [0, -BACINO_GIU, 0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": giro_bacino},
        {"osso": "root.x", "asse": china, "gradi": BACINO_PENDE},
    ]
    for s in "lr":
        lato = 1.0 if s == "l" else -1.0
        avanti, su = (CONTATTO, CAVIGLIA_SU) if s == tocca else (DIETRO, DIETRO_Y)
        punte = PUNTE_SU if s == tocca else DIETRO_PUNTE
        bersaglio = [centro[0] + dx * avanti + sinistra_bacino[0] * LARGHEZZA * lato, su,
                     centro[2] + dz * avanti + sinistra_bacino[2] * LARGHEZZA * lato]
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": bersaglio,
                    "polo": [davanti_bacino[0] + 0.08 * lato * sinistra_bacino[0], 0,
                             davanti_bacino[2] + 0.08 * lato * sinistra_bacino[2]]}},
            ## Il piede punta dove va la corsa (fra il bacino e la direzione), le punte su o giu'.
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": giro * 1.2},
            {"osso": "foot." + s, "asse": china, "gradi": punte},
        ]
    ## Il busto si avvita indietro verso il bersaglio e pende appena avanti.
    passi += [
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -giro * AVVITA_BASSO},
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 4.0},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -giro * AVVITA_ALTO},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 4.0},
    ]
    giu = SOBBALZO  # ogni chiave e' un contatto
    sx, dx_ = MANO_SINISTRA, MANO_DESTRA
    passi += [
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": [centro[0] + sx[0], sx[1] - giu, centro[2] + sx[2]], "polo": [1, -1, -0.3]}},
        {"osso": "forearm_stretch.l", "mira": {"punto": "hand.l"},
         "rollio": {"oggetto": SCUDO, "asse": [0, 0, 1], "verso": SCUDO_VERSO}},
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [centro[0] + dx_[0], dx_[1] - giu, centro[2] + dx_[2]], "polo": [-1, -1, -0.3]}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": SPADA_VERSO}},
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [0, 1, 0], "gradi": -giro * TESTA_AVVITA},
    ]
    return passi


def spec(direzione):
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/strafe_corsa_una_mano.py (%s): non si modifica a mano." % direzione,
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(f, direzione) for f in CHIAVI},
    }


if __name__ == "__main__":
    direzione = sys.argv[1]
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(direzione), uscita, indent=1)
    print("scritto", sys.argv[2], direzione, len(CHIAVI), "pose")
