# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dello sprint a una mano (root-Sprint): la corsa spinta.

    python arcanium/animazioni/locomozione/sprint_una_mano.py <uscita.json>

Le stesse chiavi della corsa (`corsa_una_mano.py`): un contatto a ogni passo, il sinistro ai
frame 0, 16 e 32 e il destro specchiato a 8 e 24, per il motion generation di Cascadeur. Cambia
la misura: la velocita' e' quella dello sprint di oggi in gioco, 8,34 m/s (MeleeLib/root-Sprint:
4,86 m in 17 frame), cioe' 889 cm in 32 frame e passi da 222 cm; il busto pende di piu', il
bacino sta piu' basso, il piede dietro sale di piu' e le braccia pompano.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corsa_una_mano as corsa  # noqa: E402

corsa.VELOCITA = 834.0
corsa.AVANZA = corsa.VELOCITA / 30.0
corsa.BACINO_GIU = 11.0
corsa.BACINO_AVANTI = 5.0
corsa.BACINO_PENDE = 7.0
corsa.PENDE_BASSO = 9.0
corsa.PENDE_ALTO = 8.0
corsa.CONTATTO = 24.0
corsa.DIETRO_Z = -60.0
corsa.DIETRO_Y = 50.0
corsa.DIETRO_PUNTE = 65.0
corsa.MANO_DESTRA = [-20.0, 110.0, 32.0]
## Lo scudo non pompa: si porta. Con il polso dritto una mano alta e avanti mette
## l'avambraccio in orizzontale, e lo scudo si sdraia (2026-11-09).
corsa.MANO_SINISTRA = [25.0, 102.0, 14.0]
corsa.MANO_DESTRA_DIETRO = [-24.0, 99.0, -26.0]
corsa.MANO_SINISTRA_DIETRO = [25.0, 100.0, 2.0]


def spec():
    s = corsa.spec()
    s["_nota"] = "Generato da arcanium/animazioni/locomozione/sprint_una_mano.py: non si modifica a mano."
    return s


if __name__ == "__main__":
    import json
    with open(sys.argv[1], "w", encoding="utf-8") as uscita:
        json.dump(spec(), uscita, indent=1)
    print("scritto", sys.argv[1], len(corsa.CHIAVI), "pose")
