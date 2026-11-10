# -*- coding: utf-8 -*-
"""Le POSE CHIAVE della CORSA A DUE MANI col nemico agganciato, con l'ASTA IN SPALLA: di lato
(sinistra, destra) e all'indietro.

    python arcanium/animazioni/locomozione/corsa_agganciata_due_mani.py <campione> <sinistra|destra|indietro> <uscita.json>

Scelta dell'utente, 2026-11-10: agganciata Zarine va in guardia al passo (guardia_due_mani.py)
e si rimette l'asta in spalla di corsa. Le braccia sono quelle della corsa a due mani
(corsa_due_mani.py `braccia`): la destra davanti alla spalla, l'asta appoggiata sopra, la
sinistra chiusa sull'asta.

Le gambe vengono dalle corse agganciate a una mano di Edran, in scala sul corpo (CORPI):
- di lato, alla souls-like (strafe_corsa_una_mano.py): le gambe corrono verso dove si va, il
  bacino e' girato di 70 gradi in quella direzione e il busto si avvita indietro verso il
  bersaglio. Il petto resta girato di quello che il busto non ripaga, e le braccia girano con
  lui (`braccia(..., giro)`);
- all'indietro (corsa_indietro_una_mano.py): passi corti sull'avampiede, il busto chino verso
  il nemico.

Destra e sinistra NON sono una lo specchio dell'altra: l'asta sta sulla spalla destra, e uno
specchio la porterebbe sulla sinistra. Si generano tutte e due.

Stessa struttura della corsa: 33 frame, una chiave a ogni contatto (il sinistro a 0, 16 e 32,
il destro a 8 e 24), dalla generazione si tiene il ciclo di mezzo (`--taglia 8 24`).

Velocita': quelle di Edran in scala, 4,2 m/s di lato e 3,2 all'indietro.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti (il bersaglio), +X la sua sinistra. Misure in cm.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corsa_due_mani as corsa  # noqa: E402
from corsa_due_mani import _ruota_y  # noqa: E402

FRAMES = corsa.FRAMES
CHIAVI = corsa.CHIAVI
CICLO = corsa.CICLO

## Dove si va (x, z) e di quanti gradi gira il bacino attorno a +Y (positivo = verso +X).
DI_LATO = {"sinistra": ((1.0, 0.0), 70.0), "destra": ((-1.0, 0.0), -70.0)}
## Quanto del giro del bacino ripaga la schiena (strafe_corsa_una_mano.py); la testa quasi
## tutto il resto.
AVVITA_BASSO = 0.25
AVVITA_ALTO = 0.4
TESTA_AVVITA = 0.25


def di_lato(C, f, direzione):
    k = C.c["scala"]
    (dx, dz), giro = DI_LATO[direzione]
    avanza = 420.0 / 30.0
    tocca = "l" if f % CICLO == 0 else "r"
    segno = 1.0 if tocca == "l" else -1.0
    centro = [dx * avanza * f, 0.0, dz * avanza * f]
    giro_bacino = giro - 6.0 * segno
    sinistra_bacino = _ruota_y([1.0, 0.0, 0.0], giro_bacino)
    davanti_bacino = _ruota_y([0.0, 0.0, 1.0], giro_bacino)
    china = [dz, 0.0, -dx]
    passi = [
        {"osso": "c_traj", "sposta": [centro[0], 0, centro[2]]},
        {"osso": "root.x", "sposta": [0, -10.0 * k, 0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": giro_bacino},
        {"osso": "root.x", "asse": china, "gradi": 8.0},
    ]
    for s in "lr":
        lato = 1.0 if s == "l" else -1.0
        if s == tocca:
            avanti, su, punte = 24.0 * k, C.c["caviglia"], -6.0
        else:
            avanti, su, punte = -55.0 * k, 38.0 * k, 50.0
        larga = 9.0 * k * lato
        bersaglio = [centro[0] + dx * avanti + sinistra_bacino[0] * larga, su,
                     centro[2] + dz * avanti + sinistra_bacino[2] * larga]
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": bersaglio,
                    "polo": [davanti_bacino[0] + 0.08 * lato * sinistra_bacino[0], 0,
                             davanti_bacino[2] + 0.08 * lato * sinistra_bacino[2]]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": giro * 1.2},
            {"osso": "foot." + s, "asse": china, "gradi": punte},
        ]
    passi += [
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -giro * AVVITA_BASSO},
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 4.0},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -giro * AVVITA_ALTO},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 4.0},
    ]
    petto = giro_bacino - giro * (AVVITA_BASSO + AVVITA_ALTO)
    passi += corsa.braccia(C, segno, petto)
    passi += [
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [0, 1, 0], "gradi": -giro * TESTA_AVVITA},
    ]
    return passi


def indietro(C, f):
    k = C.c["scala"]
    z = -320.0 / 30.0 * f
    tocca = 1.0 if f % CICLO == 0 else -1.0
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, -9.0 * k, 0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": -5.0 * tocca},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": 6.0},
    ]
    for lato, s in ((1.0, "l"), (-1.0, "r")):
        if lato == tocca:
            avanti, su, punte = -22.0 * k, C.c["caviglia"] + 4.4 * k, 28.0
        else:
            avanti, su, punte = 30.0 * k, 34.0 * k, 18.0
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": [10.0 * k * lato, su, z + avanti], "polo": [0.08 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": -8.0 * lato},
            {"osso": "foot." + s, "asse": [1, 0, 0], "gradi": punte},
        ]
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 5.0},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": 4.0 * tocca},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 4.0},
    ]
    passi += corsa.braccia(C, tocca, -1.0 * tocca)
    passi += [
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": -10.0},
    ]
    return passi


def posa(C, f, direzione):
    return indietro(C, f) if direzione == "indietro" else di_lato(C, f, direzione)


def spec(nome, direzione):
    C = corsa.Corpo(nome)
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/corsa_agganciata_due_mani.py (%s, %s): non si modifica a mano." % (nome, direzione),
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(C, f, direzione) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[3], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1], sys.argv[2]), uscita, indent=1)
    print("scritto", sys.argv[3], sys.argv[1], sys.argv[2], len(CHIAVI), "pose")
