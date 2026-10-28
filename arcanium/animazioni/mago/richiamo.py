# -*- coding: utf-8 -*-
"""Le POSE CHIAVE del RICHIAMO DELLE ECO, l'incantesimo del Mago Sylvorn che
sveglia le Eco Radicate Guaste (docs/10_ARMATA_SYLVORN.md: «le braccia che si
alzano e restano alzate un istante di troppo»).

Fino al 2026-10-28 il richiamo era la `sword_cast_01` rallentata, quella con
le mani che andavano dietro il busto e bucavano il manto.

    python arcanium/animazioni/mago/richiamo.py <uscita.json>

Per `casc_pose_fk.py`, sulla scena senza rig fatta con
`base_cascadeur.py ... sword_idle_01.glb ... tieni=121`: 121 frame a 30 fps
(4 s), primo e ultimo nella posa d'idle. Le Eco escono al frame 85 (2,83 s):
e' il `telegraph` della mossa nel moveset.

Il racconto: china il capo e apre le mani verso il suolo, come a sentire chi
c'e' sotto; poi le braccia salgono ai lati coi palmi in su, come a tirare su
qualcosa di pesante; arrivate in alto restano li', tremando, un istante di
troppo, la testa all'indietro; le Eco escono, e le braccia ricadono stanche.

Assi e misure: vedi radici.py (stesso corpo, stessa base).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from radici import bacino, schiena, testa, mani  # noqa: E402

FRAMES = 121
CHIAVI = [0, 18, 34, 50, 64, 76, 85, 96, 108, 120]

## Le braccia aperte ai lati, gomito che guarda in basso e indietro.
LATI = (1.0, -0.6, -0.4)

POSE = {
    ## Ascolta: capo chino, mani aperte verso terra, un poco staccate dai fianchi.
    18: schiena(4, 3, 2) + mani(34, 92, 18, dita=(0.3, -1, 0.3), gomiti=LATI) + testa(18, 6),
    ## Afferra: si piega appena, le mani scendono un poco come a prendere.
    34: bacino(6) + schiena(10, 6, 4) + mani(38, 82, 24, dita=(0.2, -1, 0.5), gomiti=LATI) + testa(22, 8),
    ## Tira su: le braccia salgono ai lati, palmi in su, il busto si raddrizza.
    50: bacino(2) + schiena(0, 0, -2) + mani(52, 128, 14, dita=(0.6, 1, 0.1), gomiti=LATI) + testa(4),
    ## In alto: braccia larghe e alte, la testa che sale.
    64: schiena(-4, -6, -8) + mani(40, 182, 12, dita=(0.2, 1, 0.1), gomiti=(1.0, -0.2, -0.3)) + testa(-14, -6),
    ## L'istante di troppo: ancora piu' su, il petto aperto, il capo all'indietro.
    76: schiena(-6, -8, -10) + mani(36, 190, 8, dita=(0.1, 1, 0.0), gomiti=(1.0, -0.1, -0.3)) + testa(-22, -10),
    ## Le Eco escono: un sussulto, le mani si aprono di piu'.
    85: schiena(-3, -5, -7) + mani(46, 184, 14, dita=(0.5, 1, 0.2), gomiti=(1.0, -0.3, -0.3)) + testa(-16, -6),
    ## Ricadono, stanche: le braccia scendono pesanti, il capo si abbassa.
    96: bacino(4) + schiena(8, 6, 4) + mani(40, 112, 22, dita=(0.4, -0.6, 0.4), gomiti=LATI) + testa(14, 4),
    ## Quasi in idle, ancora curvo.
    108: bacino(2) + schiena(5, 3, 2) + mani(32, 96, 12, dita=(0.2, -1, 0.2), gomiti=LATI) + testa(8),
}


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/mago/richiamo.py: non si modifica a mano.",
        "frames": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): passi for f, passi in sorted(POSE.items())},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(spec(), f, indent=1)
    print("scritto", sys.argv[1], len(POSE), "pose")
