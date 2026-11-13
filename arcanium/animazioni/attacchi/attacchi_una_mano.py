# -*- coding: utf-8 -*-
"""Le POSE CHIAVE degli ATTACCHI a una mano su Edran (spada e scudo), per Cascadeur.

    python arcanium/animazioni/attacchi/attacchi_una_mano.py <clip> <uscita.json>

con <clip> fra: obliquo, contro_obliquo, affondo, forte.

L'utente, 2026-11-13: attacchi a una mano «soulslike, con scia visibile», e la catena
leggera da TRE: «due spadate in slash obliquo» e «un affondo finale».
- `obliquo` (root-Slash1): dall'alto a destra al basso a sinistra, col passo del sinistro.
- `contro_obliquo` (root-Slash2): di rovescio, dall'alto a sinistra al basso a destra.
- `affondo` (root-SlashThrust, il terzo della catena): la spada si ritira al fianco e parte
  dritta in allungo, il peso tutto avanti; chiude la catena ed e' piu' lento a rientrare.
- `forte` (root-Slash3, il colpo forte col tasto secondario): dall'alto in verticale, con la
  carica sopra la testa e il passo pesante.

I TEMPI seguono il gioco (player_charbody3D.gd, equipment_system.gd): la lama colpisce dal 30%
all'80% della clip, e la catena si apre al 55%. Quindi la carica finisce prima del 30%, il
filo passa fra il 30% e il 50%, e il recupero comincia dopo il 55%. Lo scudo resta davanti
al petto per tutto il colpo, come si attacca in un souls con lo scudo.

Le pose usano `_posa` di gruppo_scudo_una_mano.py: traiettoria (`z`, +Z avanti), bacino,
piedi, busto, mani con dove guardano scudo e spada, testa. Assi di Cascadeur: +Y su, +Z
davanti, +X la sua sinistra; cm. La spada (`spada`) e' la direzione in cui punta la lama.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "difesa"))
from gruppo_scudo_una_mano import PRONTI, _con, _posa  # noqa: E402

## In attacco lo scudo sta davanti al petto, non alla vita.
ATTACCO = _con(PRONTI, sx=[18.0, 114.0, 24.0], scudo=[-0.1, 0.05, 1.0])


def _passo(z, avanti=0.0, dietro=0.0):
    """I piedi col sinistro avanti di `avanti` cm e il destro indietro di `dietro`."""
    return {"l": (11.0, 16.0 + avanti), "r": (-11.0, -16.0 - dietro)}


CLIP = {
    ## 26 frame (0,87 s). Carica alta a destra (f6, 23%), il filo passa davanti (f9, 35%),
    ## finisce basso a sinistra (f13, 50%), tiene (f17), torna pronto (f25). Col NUOVO STILE
    ## (l'utente, 2026-11-13: tutto il corpo, pose esagerate): nella carica i fianchi girano
    ## indietro e il peso va sul destro col sinistro leggero, lo scudo va avanti a
    ## controbilanciare; nel colpo il sinistro si pianta, i fianchi girano per primi e il
    ## tallone destro si alza; nel seguito il busto si avvolge e lo scudo torna al petto.
    "obliquo": {
        "frames": 26,
        "chiavi": {
            0: ATTACCO,
            6: _con(ATTACCO, z=-4.0, giu=13.0, giro=-18.0, pende=-5.0,
                    piedi={"l": (11.0, 12.0, 4.0, -8.0), "r": (-11.0, -18.0)},
                    schiena=(-2.0, -14.0), petto=(-8.0, -32.0),
                    sx=[26.0, 120.0, 36.0], scudo=[0.1, 0.05, 1.0],
                    dx=[-40.0, 168.0, -16.0], spada=[-0.35, 0.7, -0.6], polo_dx=[-1.0, 0.4, -0.6],
                    testa=(4.0, 26.0)),
            9: _con(ATTACCO, z=14.0, giu=17.0, giro=6.0, pende=12.0,
                    piedi={"l": (11.0, 44.0), "r": (-11.0, -16.0, 3.0, 14.0)},
                    schiena=(6.0, 6.0), petto=(10.0, 16.0),
                    sx=[16.0, 112.0, 14.0],
                    dx=[-2.0, 124.0, 56.0], spada=[0.55, -0.15, 0.82], polo_dx=[-1.0, -0.3, -0.4],
                    testa=(10.0, -8.0)),
            13: _con(ATTACCO, z=20.0, giu=19.0, giro=20.0, pende=16.0,
                     piedi={"l": (11.0, 48.0), "r": (-11.0, -12.0, 5.0, 24.0)},
                     schiena=(9.0, 12.0), petto=(15.0, 30.0),
                     sx=[14.0, 110.0, 8.0],
                     dx=[28.0, 90.0, 30.0], spada=[0.8, -0.5, -0.3], polo_dx=[-1.0, -0.6, 0.2],
                     testa=(12.0, -20.0)),
            17: _con(ATTACCO, z=22.0, giu=15.0, giro=12.0, pende=10.0,
                     piedi={"l": (11.0, 46.0), "r": (-11.0, -6.0, 2.0, 10.0)},
                     schiena=(6.0, 6.0), petto=(10.0, 18.0),
                     dx=[16.0, 100.0, 30.0], spada=[0.7, -0.35, 0.2], testa=(10.0, -10.0)),
            25: _con(ATTACCO, z=22.0),
        },
    },
    ## 26 frame. Di rovescio: carica alta a sinistra sopra la spalla dello scudo coi fianchi
    ## girati a sinistra e lo scudo raccolto al petto (f6), il filo passa davanti mentre i
    ## fianchi tornano (f9), finisce basso a destra avvolto dall'altra parte con lo scudo che
    ## si apre a bilanciare (f13), tiene, pronto.
    "contro_obliquo": {
        "frames": 26,
        "chiavi": {
            0: ATTACCO,
            6: _con(ATTACCO, z=-2.0, giu=13.0, giro=16.0, pende=-4.0,
                    piedi={"l": (11.0, 16.0), "r": (-11.0, -14.0, 3.0, 10.0)},
                    schiena=(-2.0, 12.0), petto=(-6.0, 28.0),
                    sx=[14.0, 108.0, 12.0],
                    dx=[18.0, 160.0, 0.0], spada=[0.45, 0.7, -0.5], polo_dx=[-0.4, 1.0, -0.4],
                    testa=(6.0, -22.0)),
            9: _con(ATTACCO, z=12.0, giu=17.0, giro=-4.0, pende=12.0,
                    piedi={"l": (11.0, 40.0), "r": (-11.0, -18.0)},
                    schiena=(6.0, -4.0), petto=(10.0, -12.0),
                    sx=[18.0, 112.0, 18.0],
                    dx=[-8.0, 124.0, 54.0], spada=[-0.55, -0.15, 0.82], polo_dx=[-1.0, -0.2, -0.5],
                    testa=(10.0, 6.0)),
            13: _con(ATTACCO, z=18.0, giu=19.0, giro=-20.0, pende=16.0,
                     piedi={"l": (11.0, 44.0, 2.0, 12.0), "r": (-11.0, -16.0)},
                     schiena=(9.0, -12.0), petto=(14.0, -32.0),
                     sx=[28.0, 118.0, 32.0], scudo=[0.15, 0.05, 1.0],
                     dx=[-46.0, 92.0, 16.0], spada=[-0.8, -0.5, -0.3], polo_dx=[-1.0, -0.2, 0.4],
                     testa=(12.0, 18.0)),
            17: _con(ATTACCO, z=20.0, giu=15.0, giro=-12.0, pende=10.0,
                     piedi={"l": (11.0, 42.0), "r": (-11.0, -14.0)},
                     schiena=(6.0, -8.0), petto=(9.0, -18.0),
                     dx=[-36.0, 100.0, 24.0], spada=[-0.6, -0.35, 0.4], testa=(10.0, 8.0)),
            25: _con(ATTACCO, z=20.0),
        },
    },
    ## 32 frame (1,07 s). Si ritira (f8, 25%): la mano al fianco destro, la punta avanti,
    ## il peso dietro. Parte in allungo (f12, 37%): il sinistro avanti di mezzo metro, il
    ## braccio disteso, la punta dritta. Resta disteso (f17), poi rientra lento (f31).
    "affondo": {
        "frames": 32,
        "chiavi": {
            0: ATTACCO,
            8: _con(ATTACCO, z=-8.0, giu=16.0, giro=-14.0, pende=-4.0, schiena=(-2.0, -14.0), petto=(-2.0, -28.0),
                    piedi=_passo(-6.0, avanti=4.0, dietro=4.0),
                    sx=[22.0, 118.0, 30.0],
                    dx=[-26.0, 110.0, -12.0], spada=[0.08, 0.04, 1.0], polo_dx=[-1.0, -0.2, -0.6],
                    testa=(8.0, 16.0)),
            12: _con(ATTACCO, z=34.0, giu=26.0, giro=8.0, pende=18.0, schiena=(9.0, 8.0), petto=(9.0, 14.0),
                     piedi={"l": (11.0, 84.0), "r": (-11.0, -30.0, 6.0, 28.0)},
                     sx=[24.0, 116.0, 10.0], scudo=[0.3, 0.05, 0.9],
                     dx=[-8.0, 120.0, 84.0], spada=[0.12, 0.06, 1.0], polo_dx=[-1.0, -0.8, -0.2],
                     testa=(12.0, -6.0)),
            17: _con(ATTACCO, z=34.0, giu=19.0, pende=14.0, schiena=(7.0, 3.0), petto=(7.0, 8.0),
                     piedi={"l": (11.0, 70.0), "r": (-11.0, -22.0, 2.0, 12.0)},
                     sx=[24.0, 116.0, 12.0], scudo=[0.3, 0.05, 0.9],
                     dx=[-10.0, 118.0, 80.0], spada=[0.1, 0.02, 1.0], polo_dx=[-1.0, -0.8, -0.2],
                     testa=(12.0, -4.0)),
            24: _con(ATTACCO, z=38.0, giu=13.0, pende=6.0, piedi=_passo(38.0, avanti=16.0),
                     dx=[-18.0, 108.0, 40.0], spada=[0.1, 0.0, 1.0]),
            31: _con(ATTACCO, z=40.0),
        },
    },
    ## 36 frame (1,2 s). Carica sopra la testa (f10, 28%): la lama dietro le spalle, il
    ## petto indietro. Cala dritta (f14, 39%) e finisce bassa davanti (f17, 47%) col passo
    ## pesante; tiene giu' (f23), rientra (f35).
    "forte": {
        "frames": 36,
        "chiavi": {
            0: ATTACCO,
            10: _con(ATTACCO, z=-8.0, giu=10.0, giro=-6.0, pende=-12.0, schiena=(-8.0, -10.0), petto=(-14.0, -16.0),
                     piedi={"l": (11.0, 10.0, 6.0, -12.0), "r": (-11.0, -20.0)},
                     sx=[20.0, 120.0, 22.0],
                     dx=[-14.0, 178.0, -8.0], spada=[0.0, 0.3, -1.0], polo_dx=[-1.0, 0.6, -0.4],
                     testa=(-4.0, 6.0)),
            14: _con(ATTACCO, z=10.0, giu=14.0, pende=10.0, schiena=(6.0, 0.0), petto=(10.0, 2.0),
                     piedi=_passo(10.0, avanti=22.0),
                     dx=[-10.0, 150.0, 46.0], spada=[0.0, 0.55, 0.85], polo_dx=[-1.0, 0.2, -0.4],
                     testa=(8.0, 0.0)),
            17: _con(ATTACCO, z=26.0, giu=28.0, giro=10.0, pende=26.0, schiena=(14.0, 6.0), petto=(20.0, 8.0),
                     piedi={"l": (11.0, 50.0), "r": (-11.0, -22.0, 5.0, 24.0)},
                     dx=[-8.0, 90.0, 56.0], spada=[0.0, -0.7, 0.7], polo_dx=[-1.0, -0.4, 0.0],
                     sx=[28.0, 98.0, 26.0], scudo=[0.2, -0.2, 1.0], polo_sx=[1.0, -0.6, -0.4],
                     testa=(16.0, 0.0)),
            23: _con(ATTACCO, z=28.0, giu=24.0, giro=8.0, pende=20.0, schiena=(11.0, 4.0), petto=(15.0, 6.0),
                     piedi={"l": (11.0, 48.0), "r": (-11.0, -20.0, 3.0, 14.0)},
                     dx=[-8.0, 92.0, 52.0], spada=[0.0, -0.75, 0.65], polo_dx=[-1.0, -0.4, 0.0],
                     sx=[28.0, 98.0, 26.0], scudo=[0.2, -0.2, 1.0], polo_sx=[1.0, -0.6, -0.4],
                     testa=(14.0, 0.0)),
            35: _con(ATTACCO, z=28.0),
        },
    },
}


def spec(nome):
    c = CLIP[nome]
    chiavi = sorted(c["chiavi"])
    return {
        "_nota": "Generato da arcanium/animazioni/attacchi/attacchi_una_mano.py (%s): non si modifica a mano." % nome,
        "frames": c["frames"],
        "base": c["frames"],
        "chiavi": chiavi,
        "pose": {str(f): _posa(c["chiavi"][f]) for f in chiavi},
    }


if __name__ == "__main__":
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1]), uscita, indent=1)
    print("scritto", sys.argv[2], sys.argv[1])
