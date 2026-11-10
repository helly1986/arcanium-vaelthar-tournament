# -*- coding: utf-8 -*-
"""Le POSE CHIAVE della corsa A DUE MANI (root-HeavyRunning) sullo scheletro ARP.

    python arcanium/animazioni/locomozione/corsa_due_mani.py <campione> <uscita.json>

Come il cammino a due mani (cammino_due_mani.py): l'arma APPOGGIATA SULLA SPALLA destra,
tenuta con due mani, la sinistra dove la tiene il cammino e le dita chiuse. Le gambe sono
quelle della corsa a una mano (corsa_una_mano.py: una chiave a ogni contatto, il sinistro a
0, 16 e 32, il destro a 8 e 24; dalla generazione si tiene il ciclo di mezzo, `--taglia 8
24`), portate sulle misure del corpo (CORPI).

Con l'arma in spalla il busto pende meno che nella corsa china di Edran (le braccia non
oscillano a bilanciare) e le spalle girano poco. La mano destra e il punto della spalla su
cui poggia l'asta si prendono dalla spalla del corpo IN QUELLA POSA (`bersaglio_da`,
`verso_punto` con `osso`): col busto chino si spostano con lui.

Velocita' 4,7 m/s, quella della corsa pesante in gioco oggi (HeavyRunning, 4,69).

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm.
"""
import json
import math
import sys

from cammino_due_mani import CORPI

FRAMES = 33
CHIAVI = [0, 8, 16, 24, 32]
CICLO = 16


class Corpo(object):
    def __init__(self, nome):
        c = CORPI[nome]
        k = c["scala"]
        self.c = c
        self.avanza = 470.0 / 30.0
        self.caviglia_su = c["caviglia"]
        self.tallone_dietro = 5.0 * k
        ## Dalla corsa a una mano di Edran, in scala.
        self.bacino_giu = 11.0 * k
        self.bacino_avanti = 3.0 * k
        self.bacino_giro = -5.0
        self.bacino_pende = 9.0
        self.contatto = 28.0 * k
        self.larghezza = 8.0 * k
        self.punte_su = -8.0
        self.dietro_z = -58.0 * k
        self.dietro_y = 38.0 * k
        self.dietro_punte = 60.0
        self.pende_basso = 7.0
        self.pende_alto = 5.0
        self.testa = -12.0


def _ruota_zy(z, y, gradi):
    t = math.radians(gradi)
    return y * math.sin(t) + z * math.cos(t), y * math.cos(t) - z * math.sin(t)


def gambe(C, bacino_z, tocca):
    tallone = bacino_z + C.contatto
    dz, dy = _ruota_zy(C.tallone_dietro, C.caviglia_su, C.punte_su)
    davanti = ((tallone + dz, dy), C.punte_su)
    dietro = ((bacino_z + C.dietro_z, C.dietro_y), C.dietro_punte)
    passi = []
    for lato, s in ((1.0, "l"), (-1.0, "r")):
        (z, y), gradi = davanti if lato == tocca else dietro
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": [C.larghezza * lato, y, z], "polo": [0.08 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": -10.0 * lato},
            {"osso": "foot." + s, "asse": [1, 0, 0], "gradi": gradi},
        ]
    return passi


def busto(C, tocca):
    return [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": C.pende_basso},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -C.bacino_giro * 0.5 * tocca},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": C.pende_alto},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -C.bacino_giro * 0.6 * tocca},
    ]


## La mano destra e il punto d'appoggio sulla spalla, dal giunto della spalla destra
## (arm_stretch.r): misurati nel cammino a due mani, dove l'asta passa sulla spalla.
DA_SPALLA_MANO = [1.0, -25.0, 21.0]
DA_SPALLA_APPOGGIO = [1.0, 16.0, -5.0]


def braccia(C, tocca):
    c = C.c
    sm = c["seconda_mano"]
    ## Sobbalza col passo: al contatto la mano scende appena e va avanti col lato che spinge.
    mano = [DA_SPALLA_MANO[0], DA_SPALLA_MANO[1] - 2.0, DA_SPALLA_MANO[2] + 2.0 * tocca]
    mira = {"osso": "hand.r", "mira": {"oggetto": c["arma"], "asse": [0, 1, 0],
                                       "verso_punto": {"osso": "arm_stretch.r", "scarto": DA_SPALLA_APPOGGIO,
                                                       "da": c["presa_destra"]}}}
    rollio = {"osso": "hand.r", "mira": {"oggetto": c["arma"], "asse": [0, 1, 0]},
              "rollio": {"oggetto": c["arma"], "asse": [-1, 0, 0], "verso": c["polso_verso"]}}
    return [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio_da": {"osso": "arm_stretch.r", "scarto": mano}, "polo": [-1, -1, -0.2]}},
        mira, rollio, mira, mira,
        {"chiudi_mano": {"lato": "r", "chiusura": c["chiusura_destra"], "pollice": c["pollice_destra"]}},
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio_su": {"oggetto": c["arma"], "punto": [sm[9] * 100.0, sm[10] * 100.0 + c["seconda_mano_scorre"],
                                                                 sm[11] * 100.0]},
                "polo": [1, -1, -0.2]}},
        {"osso": "hand.l", "orienta_su": {"oggetto": c["arma"], "base": sm[:9]}},
        {"chiudi_mano": {"lato": "l", "chiusura": c["chiusura_sinistra"], "pollice": c["pollice_sinistra"]}},
    ]


def testa(C):
    return [
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": C.testa},
    ]


def posa(C, f):
    z = C.avanza * f
    tocca = 1.0 if f % CICLO == 0 else -1.0
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, -C.bacino_giu, C.bacino_avanti]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": C.bacino_giro * tocca},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": C.bacino_pende},
    ]
    bacino_z = z + C.bacino_avanti
    return passi + gambe(C, bacino_z, tocca) + busto(C, tocca) + braccia(C, tocca) + testa(C)


def spec(nome):
    C = Corpo(nome)
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/corsa_due_mani.py (%s): non si modifica a mano." % nome,
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(C, f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1]), uscita, indent=1)
    print("scritto", sys.argv[2], sys.argv[1], len(CHIAVI), "pose")
