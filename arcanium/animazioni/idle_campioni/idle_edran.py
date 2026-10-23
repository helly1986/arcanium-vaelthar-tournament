# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dell'idle di Edran (docs/campioni_concept.md): due rintocchi
lenti della lama piatta sul bordo dello scudo, poi lo sguardo attorno.

    python arcanium/animazioni/idle_campioni/idle_edran.py <uscita.json>

Scrive il json che `arcanium/tools/casc_pose_fk.py` applica in Cascadeur sulla
scena di lavorazione senza rig. 181 frame a 30 fps (6 s), in loop: il primo e
l'ultimo frame sono la `Posa` del menu.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti a Edran, +X la sua
sinistra. Le misure sono in centimetri (spalle a 148, mani a riposo a 101).
"""
import json
import sys

FRAMES = 181
## Le chiavi da tenere dopo il rig (casc_estremi_clip.py): le pose e i riposi.
CHIAVI = [0, 26, 38, 50, 62, 74, 88, 110, 132, 150, 166, 180]

SCUDO = "LeftHand_Mesh"
SPADA = "RightHand_Sword"


def busto(girata, petto=0.0):
    """Il petto girato verso lo scudo (gradi attorno all'alto) e alzato dal
    respiro (negativo = indietro)."""
    passi = []
    if girata:
        passi.append({"osso": "Spine_03", "asse": [0, 1, 0], "gradi": girata})
    if petto:
        passi.append({"osso": "Spine_03", "asse": [1, 0, 0], "gradi": petto})
    return passi


def scudo(su, avanti):
    """Lo scudo sollevato davanti al fianco sinistro, la faccia di fronte.
    `su` 0..1 da riposo a pronto; `avanti` gradi di flessione della spalla.

    ⚠️ La faccia si gira col POLSO, non torcendo l'avambraccio: il rig di
    Cascadeur non conserva la torsione del gomito, e lo scudo usciva dal bake
    girato di 25 gradi (2026-10-23)."""
    mano = [24, 103 + 5 * su, 4 + 8 * su]
    return [
        {"ik": {"spalla": "Shoulder_L", "gomito": "Elbow_L", "mano": "Hand_L",
                "bersaglio": mano, "polo": [1, 0, -1]}},
        {"osso": "Shoulder_L", "asse": [1, 0, 0], "gradi": -avanti * 0.35},
        {"osso": "Hand_L", "mira": {"oggetto": SCUDO, "asse": [0, 0, 1], "verso": [-0.2, 0.15, 1]}},
    ]


def lama_sul_bordo(mano, sopra):
    """La mano destra in `mano` (cm), la lama puntata sul bordo alto dello
    scudo `sopra` cm sopra di esso, il piatto in giu'. Il contatto e' -1,5 e
    non 2: il bake del rig rigira un poco il polso sinistro, e nella scena
    riggata la lama restava 3,6 cm sopra il bordo (2026-10-23)."""
    return [
        {"ik": {"spalla": "Shoulder_R", "gomito": "Elbow_R", "mano": "Hand_R",
                "bersaglio": mano, "polo": [-1, -0.3, -0.4]}},
        {"osso": "Hand_R",
         "mira": {"oggetto": SPADA, "asse": [0, -1, 0],
                  "verso_al_bordo": {"da": "Hand_R", "oggetto": SCUDO, "normale": [0, 0, 1],
                                     "raggio": 33, "sopra": sopra}},
         "rollio": {"asse": [0, 0, 1], "verso": [0, 1, 0]}},
    ]


def testa(gira=0.0, china=0.0):
    """Gira (negativo = verso la sua destra) e china (positivo = giu')."""
    passi = []
    if gira:
        passi.append({"osso": "Head", "asse": [0, 1, 0], "gradi": gira})
    if china:
        passi.append({"osso": "Neck", "asse": [1, 0, 0], "gradi": china})
    return passi


POSE = {
    ## Si prepara: lo scudo sale, la spada si alza sopra il bordo.
    26: busto(5, -1.5) + scudo(0.8, 16) + lama_sul_bordo([-10, 150, 22], 20) + testa(china=3),
    ## Primo rintocco.
    38: busto(6, -1) + scudo(1.0, 22) + lama_sul_bordo([-8, 142, 24], -1.5) + testa(china=6),
    ## Rimbalzo, piu' basso del primo caricamento: il secondo e' gia' in mano.
    50: busto(6, -2) + scudo(1.0, 22) + lama_sul_bordo([-9, 146, 23], 13) + testa(china=4),
    ## Secondo rintocco.
    62: busto(6, -1) + scudo(1.0, 22) + lama_sul_bordo([-8, 142, 24], -1.5) + testa(china=6),
    ## La lama resta appoggiata: il suono si spegne.
    74: busto(5, -1) + scudo(1.0, 21) + lama_sul_bordo([-8, 141, 24], -0.5) + testa(china=4),
    88: busto(4, -2) + scudo(0.9, 19) + lama_sul_bordo([-9, 142, 23], 0.5) + testa(china=2),
    ## Le braccia scendono.
    110: busto(2, -1) + scudo(0.35, 7) + [
        {"ik": {"spalla": "Shoulder_R", "gomito": "Elbow_R", "mano": "Hand_R",
                "bersaglio": [-25, 114, 14], "polo": [-1, -0.2, -0.6]}},
        {"osso": "Hand_R", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": [0.1, -0.35, 0.93]}},
    ] + testa(),
    ## A riposo (132), poi uno sguardo alla sua destra e di nuovo avanti.
    150: busto(-3) + testa(gira=-20),
    166: busto(-1) + testa(gira=-6),
}


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/idle_campioni/idle_edran.py: non si modifica a mano.",
        "frames": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): passi for f, passi in sorted(POSE.items())},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(spec(), f, indent=1)
    print("scritto", sys.argv[1], len(POSE), "pose")
