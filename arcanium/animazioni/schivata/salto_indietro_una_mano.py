# -*- coding: utf-8 -*-
"""Le POSE CHIAVE del SALTO ALL'INDIETRO a una mano (la schivata da fermi, root-BackstepLight)
sullo scheletro ARP, per il motion generation di Cascadeur.

    python arcanium/animazioni/schivata/salto_indietro_una_mano.py <uscita.json>

L'utente, 2026-11-10: da fermi la schivata non e' la rotolata suonata al contrario ma «un
piccolo salto all'indietro da soulslike». In guardia, si carica appena sulle ginocchia, si
stacca con tutti e due i piedi (le punte giu'), vola basso e indietro, atterra prima col
destro (quello dietro) e ammortizza, poi torna in guardia. Spada e scudo restano davanti.

Coi principi della fisica di Cascadeur (l'utente, 2026-11-10,
https://cascadeur.com/help/animation_pipeline/physics):
- lo STACCO (f4, l'ultimo frame coi piedi a terra) e l'ATTERRAGGIO (f12, il primo) sono chiavi;
- in volo il bacino (il baricentro) segue una PARABOLA vera: 8 frame (0,27 s) a 3,6 m/s
  all'indietro, e con g = 9,81 il colmo sale di g t^2 / 8 = 8,7 cm (f8). La prima versione
  volava a 6 m/s senza parabola;
- a terra fermi il baricentro sta fra i piedi (f0, f17); nella spinta e nella frenata sta
  fuori, perche' il corpo si muove;
- in volo il corpo gira a velocita' costante (il momento angolare non cambia): il pendere
  scende in modo regolare.
Dopo il rig, sull'intervallo 4-12 si rifinisce con Ballistic Trajectory e lo snap del
baricentro (i fantasmi rossi).

18 frame a 30 fps (0,6 s), 1,4 m indietro. Un frame di riposo dopo (`base`).

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm, dal
corpo ARP di Edran: bacino a 105,1, caviglia a 14,6.
"""
import json
import sys

FRAMES = 18
CHIAVI = [0, 4, 8, 12, 15, 17]

BACINO = 105.1
CAVIGLIA = 14.6
SPADA = "RightHand_Sword"
SCUDO = "LeftHand_Mesh"

G = 981.0  # cm/s^2
STACCO, ATTERRA = 4, 12
VOLO = (ATTERRA - STACCO) / 30.0
V_INDIETRO = 360.0  # cm/s in volo
Z_STACCO, GIU_STACCO = -22.0, 12.0


def _in_volo(f):
    """Il bacino sulla parabola fra lo stacco e l'atterraggio: (z, quanto sta sotto il riposo)."""
    t = (f - STACCO) / 30.0
    sale = V_SU * t - G * t * t / 2.0
    return Z_STACCO - V_INDIETRO * t, GIU_STACCO - sale


## La velocita' verticale allo stacco che riporta il bacino alla stessa altezza all'atterraggio.
V_SU = G * VOLO / 2.0

## Per chiave: dove sta il bacino lungo Z (cm, negativo = indietro), quanto scende sotto il
## riposo, di quanto pende avanti (gradi).
POSE = {
    0: {"z": 0.0, "giu": 4.0, "pende": 4.0},
    STACCO: {"z": Z_STACCO, "giu": GIU_STACCO, "pende": 10.0},
    8: {"z": _in_volo(8)[0], "giu": _in_volo(8)[1], "pende": 7.0},
    ATTERRA: {"z": _in_volo(ATTERRA)[0], "giu": _in_volo(ATTERRA)[1], "pende": 4.0},
    15: {"z": -134.0, "giu": 17.0, "pende": 12.0},
    17: {"z": -138.0, "giu": 5.0, "pende": 5.0},
}

## In guardia: il sinistro (lo scudo) avanti, il destro dietro.
GUARDIA = {"l": (10.0, 12.0), "r": (-10.0, -12.0)}
## Dove atterra, e resta fino alla fine: il bacino a fine salto sta fra i due piedi.
ARRIVO = {"l": (10.0, -125.0), "r": (-10.0, -150.0)}

## Le mani in guardia davanti al petto, dal bacino (come la corsa all'indietro).
MANO_SINISTRA = [20.0, 7.0, 26.0]
MANO_DESTRA = [-24.0, 5.0, 18.0]
SCUDO_VERSO = [0.1, 0.1, 1.0]
SPADA_VERSO = [0.1, 0.5, 1.0]


def _gamba(s, bersaglio, punte=0.0):
    lato = 1.0 if s == "l" else -1.0
    passi = [
        {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                "bersaglio": bersaglio, "polo": [0.1 * lato, 0, 1]}},
        {"osso": "foot." + s, "come_base": True},
        {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": -8.0 * lato},
    ]
    if punte:
        passi.append({"osso": "foot." + s, "asse": [1, 0, 0], "gradi": punte})
    return passi


def posa(f):
    p = POSE[f]
    z = p["z"]
    alto = BACINO - p["giu"]
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, -p["giu"], 0]},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": p["pende"]},
    ]
    for s in "lr":
        x, gz = GUARDIA[s]
        ax, az = ARRIVO[s]
        if f <= STACCO:
            passi += _gamba(s, [x, CAVIGLIA, gz])
        elif f < ATTERRA:
            ## In volo, basso: le ginocchia piegate, i piedi sotto il bacino, le punte giu'.
            passi += _gamba(s, [x, CAVIGLIA + (14.0 if s == "l" else 10.0), z + (14.0 if s == "l" else -6.0)], 25.0)
        elif f == ATTERRA and s == "l":
            ## Atterra il destro, dietro il bacino a frenare; il sinistro e' ancora su.
            passi += _gamba(s, [ax, CAVIGLIA + 6.0, az + 4.0], 15.0)
        else:
            passi += _gamba(s, [ax, CAVIGLIA, az])
    ## Il busto ripaga meta' del pendere: lo sguardo resta avanti.
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": -p["pende"] * 0.3},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": -p["pende"] * 0.2},
    ]
    sx, dx = MANO_SINISTRA, MANO_DESTRA
    passi += [
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": [sx[0], alto + sx[1], z + sx[2]], "polo": [1, -1, -0.3]}},
        {"osso": "forearm_stretch.l", "mira": {"punto": "hand.l"},
         "rollio": {"oggetto": SCUDO, "asse": [0, 0, 1], "verso": SCUDO_VERSO}},
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [dx[0], alto + dx[1], z + dx[2]], "polo": [-1, -1, -0.3]}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": SPADA_VERSO}},
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": -p["pende"] * 0.4},
    ]
    return passi


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/schivata/salto_indietro_una_mano.py: non si modifica a mano.",
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as uscita:
        json.dump(spec(), uscita, indent=1)
    print("scritto", sys.argv[1], len(CHIAVI), "pose")
