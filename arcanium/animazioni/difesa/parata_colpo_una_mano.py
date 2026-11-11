# -*- coding: utf-8 -*-
"""Le POSE CHIAVE del COLPO PRESO SULLO SCUDO (GuardBlocked), a una mano su Edran.

    python arcanium/animazioni/difesa/parata_colpo_una_mano.py <uscita.json>

In guardia (parata_una_mano.py) un colpo arriva sullo scudo: il gioco suona questa clip una
volta (il oneshot `Block` del player), FILTRATA su bacino, colonna e braccio sinistro: testa,
gambe e spada restano quelle della guardia e del passo sotto. Si parte dalla guardia e ci si
torna, cosi' il oneshot entra ed esce senza salti.

Il colpo spinge lo scudo indietro verso il petto e lo inclina con la faccia in su; il busto
incassa all'indietro e la spalla sinistra cede girando indietro; poi il braccio riporta lo
scudo avanti con un filo di rimbalzo e si torna in guardia. Da fermo, senza motion
generation: chiavi raccordate in Bezier (l'utente, 2026-11-11).

16 frame a 30 fps (0,53 s) e un frame di riposo dopo.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parata_una_mano import posa_guardia  # noqa: E402

FRAMES = 16
CHIAVI = [0, 3, 7, 11, 15]

## Per chiave, quanto il colpo sposta la guardia (posa_guardia).
COLPO = {
    0: {},
    ## L'impatto: in tre frame lo scudo arretra di 14 cm e sale di 3, la faccia va in su.
    3: {"scudo": [2.0, 3.0, -14.0], "inclina": 14.0, "petto": 9.0, "schiena": 4.0, "giro": 10.0, "bacino": 2.0},
    ## Il massimo dell'incasso: il busto e' ancora indietro, lo scudo gia' torna.
    7: {"scudo": [1.0, 1.0, -9.0], "inclina": 8.0, "petto": 11.0, "schiena": 5.0, "giro": 7.0, "bacino": 2.5},
    ## Il rimbalzo: lo scudo torna avanti un poco oltre la guardia.
    11: {"scudo": [0.0, -1.0, 2.0], "inclina": -2.0, "petto": 2.0, "schiena": 1.0, "giro": -1.0},
    15: {},
}


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/difesa/parata_colpo_una_mano.py: non si modifica a mano.",
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa_guardia(0.0, COLPO[f]) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as uscita:
        json.dump(spec(), uscita, indent=1)
    print("scritto", sys.argv[1], len(CHIAVI), "pose")
