# -*- coding: utf-8 -*-
"""Le POSE CHIAVE delle APERTURE a mani libere (porta, portone, leva, forziere), per Cascadeur.

    python arcanium/animazioni/interazioni/aperture.py <porta|portone|leva|forziere> <uscita.json>

L'utente, 2026-11-11: «come Elden Ring, prima di eseguirle le armi, scudi, sigilli spariscono e
dopo al termine dell'interazione vengono riequipaggiate tramite animazione di switch». Quindi
si aprono a MANI LIBERE, e le clip sono le stesse per tutti i campioni e tutti i tipi d'arma
(nate sul corpo di Edran, portate col retarget come le altre).

Le scelte, sempre del 2026-11-11:
- OpenDoor, «spinta di spalla»: un passo, la spalla sinistra e le due mani aperte sull'anta
  (45 cm davanti all'inizio), si spinge ed entra.
- OpenGate, «due mani, tutto il peso»: i palmi sulle due ante all'altezza delle spalle, il corpo
  che spinge e le gambe che puntano, passi faticosi.
- OpenLeverFloor, «tira verso di se'»: chino, le due mani sull'impugnatura (perno a 45 cm,
  impugnatura a 60 dal perno, da z 75 a z 15, a 52 cm da terra), la tira fino in fondo e il
  busto si raddrizza.
- OpenChest, «in ginocchio, alza il coperchio»: il ginocchio destro a terra, le due mani sotto
  il bordo del coperchio (z 45, 55 cm da terra, cerniera a z 80), lo alzano, si guarda dentro,
  ci si rialza.

Le mani dicono dove stanno (relative alla traiettoria), verso dove guarda il PALMO e verso dove
vanno le DITA, e quanto sono chiuse. Sulla mano ARP le dita vanno lungo +Y e il palmo guarda
-Z locale, su tutte e due le mani (misurato in Cascadeur dal pollice). Piedi nel mondo, come
in difesa/gruppo_scudo_una_mano.py. Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la
sua sinistra. Misure in cm, dal corpo ARP di Edran: bacino a 105,1, caviglia a 14,6.
"""
import json
import sys

CAVIGLIA = 14.6

## In piedi a mani libere (dopo aver riposto le armi): le braccia lungo i fianchi, i palmi
## verso le cosce.
LIBERE = {
    "z": 0.0, "giu": 3.0, "giro": 0.0, "pende": 2.0,
    "piedi": {"l": (10.0, 6.0), "r": (-10.0, -6.0)},
    "schiena": (2.0, 0.0), "petto": (2.0, 0.0),
    "sx": [22.0, 96.0, 4.0], "palmo_sx": [-1.0, 0.0, 0.1], "dita_sx": [0.0, -1.0, 0.1], "chiusa_sx": 0.25,
    "dx": [-22.0, 96.0, 4.0], "palmo_dx": [1.0, 0.0, 0.1], "dita_dx": [0.0, -1.0, 0.1], "chiusa_dx": 0.25,
    "testa": (0.0, 0.0),
}


def _con(base, **cambi):
    p = dict(base)
    p.update(cambi)
    return p


## Le mani aperte contro una superficie davanti: palmo avanti, dita in su.
SPINGE = dict(palmo_sx=[0.0, 0.0, 1.0], dita_sx=[0.1, 1.0, 0.1], chiusa_sx=0.1,
              palmo_dx=[0.0, 0.0, 1.0], dita_dx=[-0.1, 1.0, 0.1], chiusa_dx=0.1)
## Le mani strette sull'impugnatura della leva: palmo giu', dita avanti.
IMPUGNA = dict(palmo_sx=[0.0, -1.0, 0.2], dita_sx=[0.0, -0.3, 1.0], chiusa_sx=0.85,
               palmo_dx=[0.0, -1.0, 0.2], dita_dx=[0.0, -0.3, 1.0], chiusa_dx=0.85)
## Sotto il bordo del coperchio: palmo in su, dita avanti.
SOTTO = dict(palmo_sx=[0.0, 1.0, 0.0], dita_sx=[0.0, 0.0, 1.0], chiusa_sx=0.35,
             palmo_dx=[0.0, 1.0, 0.0], dita_dx=[0.0, 0.0, 1.0], chiusa_dx=0.35)

CLIP = {
    ## 30 frame (1 s): passo e mani sull'anta (f8), spallata (f14), dentro (f20), in piedi (f29).
    "porta": {
        "frames": 30,
        "chiavi": {
            0: LIBERE,
            8: _con(LIBERE, z=18.0, giu=10.0, giro=10.0, pende=8.0, petto=(4.0, -14.0),
                    piedi={"l": (10.0, 46.0), "r": (-10.0, -10.0)},
                    sx=[16.0, 128.0, 34.0], dx=[-12.0, 116.0, 36.0], **SPINGE),
            14: _con(LIBERE, z=30.0, giu=12.0, giro=12.0, pende=12.0, petto=(8.0, -18.0),
                     piedi={"l": (10.0, 50.0), "r": (-10.0, 8.0)},
                     sx=[16.0, 126.0, 42.0], dx=[-12.0, 116.0, 44.0], **SPINGE),
            20: _con(LIBERE, z=46.0, giu=8.0, giro=6.0, pende=6.0, petto=(4.0, -8.0),
                     piedi={"l": (10.0, 50.0), "r": (-10.0, 40.0)},
                     sx=[20.0, 108.0, 24.0], dx=[-18.0, 104.0, 20.0],
                     palmo_sx=[-0.5, 0.0, 1.0], palmo_dx=[0.5, 0.0, 1.0]),
            29: _con(LIBERE, z=56.0, piedi={"l": (10.0, 62.0), "r": (-10.0, 50.0)}),
        },
    },
    ## 48 frame (1,6 s): mani sulle ante (f8), spinge (f16), un passo (f24), l'altro (f32), le
    ## ante cedono (f40), in piedi (f47).
    "portone": {
        "frames": 48,
        "chiavi": {
            0: LIBERE,
            8: _con(LIBERE, z=5.0, giu=10.0, pende=10.0, petto=(6.0, 0.0),
                    sx=[22.0, 134.0, 40.0], dx=[-22.0, 134.0, 40.0], **SPINGE),
            16: _con(LIBERE, z=12.0, giu=16.0, pende=22.0, schiena=(6.0, 0.0), petto=(8.0, 0.0),
                     piedi={"l": (10.0, 30.0), "r": (-10.0, -26.0)},
                     sx=[22.0, 132.0, 42.0], dx=[-22.0, 132.0, 42.0], testa=(-8.0, 0.0), **SPINGE),
            24: _con(LIBERE, z=30.0, giu=16.0, pende=22.0, schiena=(6.0, 0.0), petto=(8.0, 0.0),
                     piedi={"l": (10.0, 50.0), "r": (-10.0, -26.0)},
                     sx=[22.0, 132.0, 42.0], dx=[-22.0, 132.0, 42.0], testa=(-8.0, 0.0), **SPINGE),
            32: _con(LIBERE, z=50.0, giu=15.0, pende=20.0, schiena=(6.0, 0.0), petto=(8.0, 0.0),
                     piedi={"l": (10.0, 50.0), "r": (-10.0, 20.0)},
                     sx=[22.0, 132.0, 44.0], dx=[-22.0, 132.0, 44.0], testa=(-8.0, 0.0), **SPINGE),
            40: _con(LIBERE, z=64.0, giu=10.0, pende=10.0, petto=(4.0, 0.0),
                     piedi={"l": (10.0, 80.0), "r": (-10.0, 20.0)},
                     sx=[30.0, 128.0, 48.0], dx=[-30.0, 128.0, 48.0], **SPINGE),
            47: _con(LIBERE, z=72.0, piedi={"l": (10.0, 78.0), "r": (-10.0, 66.0)}),
        },
    },
    ## 40 frame (1,33 s): chino afferra (f8), comincia a tirare (f16), a meta' (f24), in fondo
    ## (f32), lascia (f39).
    "leva": {
        "frames": 40,
        "chiavi": {
            0: LIBERE,
            8: _con(LIBERE, giu=24.0, pende=30.0, schiena=(10.0, 0.0), petto=(8.0, 0.0),
                    piedi={"l": (10.0, 14.0), "r": (-10.0, -14.0)},
                    sx=[6.0, 56.0, 72.0], dx=[-6.0, 56.0, 72.0], testa=(10.0, 0.0), **IMPUGNA),
            16: _con(LIBERE, giu=26.0, pende=24.0, schiena=(8.0, 0.0), petto=(6.0, 0.0),
                     piedi={"l": (10.0, 14.0), "r": (-10.0, -22.0)},
                     sx=[6.0, 54.0, 62.0], dx=[-6.0, 54.0, 62.0], testa=(8.0, 0.0), **IMPUGNA),
            24: _con(LIBERE, giu=21.0, pende=12.0, schiena=(2.0, 0.0), petto=(0.0, 0.0),
                     piedi={"l": (10.0, 14.0), "r": (-10.0, -26.0)},
                     sx=[6.0, 58.0, 44.0], dx=[-6.0, 58.0, 44.0], testa=(4.0, 0.0),
                     **dict(IMPUGNA, palmo_sx=[0.0, -1.0, -0.4], palmo_dx=[0.0, -1.0, -0.4])),
            32: _con(LIBERE, giu=15.0, pende=0.0, schiena=(-4.0, 0.0), petto=(-6.0, 0.0),
                     piedi={"l": (10.0, 14.0), "r": (-10.0, -30.0)},
                     sx=[6.0, 56.0, 20.0], dx=[-6.0, 56.0, 20.0], testa=(0.0, 0.0),
                     **dict(IMPUGNA, palmo_sx=[0.0, -0.6, -1.0], palmo_dx=[0.0, -0.6, -1.0])),
            39: _con(LIBERE, piedi={"l": (10.0, 14.0), "r": (-10.0, -16.0)}),
        },
    },
    ## 45 frame (1,5 s): in ginocchio, mani sotto il bordo (f10), alza (f18), coperchio dritto
    ## (f26), guarda dentro con le mani sulle ginocchia (f34), in piedi (f44).
    "forziere": {
        "frames": 45,
        "chiavi": {
            0: LIBERE,
            10: _con(LIBERE, giu=52.0, pende=10.0, schiena=(6.0, 0.0), petto=(6.0, 0.0),
                     piedi={"l": (10.0, 30.0), "r": (-10.0, -28.0, 6.0, 55.0)}, polo_r=[-0.1, -0.3, 1],
                     sx=[20.0, 56.0, 44.0], dx=[-20.0, 56.0, 44.0], testa=(18.0, 0.0), **SOTTO),
            18: _con(LIBERE, giu=50.0, pende=8.0, schiena=(4.0, 0.0), petto=(4.0, 0.0),
                     piedi={"l": (10.0, 30.0), "r": (-10.0, -28.0, 6.0, 55.0)}, polo_r=[-0.1, -0.3, 1],
                     sx=[20.0, 80.0, 56.0], dx=[-20.0, 80.0, 56.0], testa=(12.0, 0.0),
                     **dict(SOTTO, palmo_sx=[0.0, 1.0, 0.5], palmo_dx=[0.0, 1.0, 0.5])),
            26: _con(LIBERE, giu=46.0, pende=12.0, schiena=(4.0, 0.0), petto=(6.0, 0.0),
                     piedi={"l": (10.0, 30.0), "r": (-10.0, -28.0, 6.0, 55.0)}, polo_r=[-0.1, -0.3, 1],
                     sx=[20.0, 94.0, 66.0], dx=[-20.0, 94.0, 66.0], testa=(14.0, 0.0),
                     **dict(SPINGE, dita_sx=[0.0, 1.0, 0.4], dita_dx=[0.0, 1.0, 0.4])),
            34: _con(LIBERE, giu=50.0, pende=16.0, schiena=(6.0, 0.0), petto=(8.0, 0.0),
                     piedi={"l": (10.0, 30.0), "r": (-10.0, -28.0, 6.0, 55.0)}, polo_r=[-0.1, -0.3, 1],
                     sx=[14.0, 64.0, 28.0], dx=[-16.0, 60.0, 6.0], testa=(28.0, 0.0),
                     palmo_sx=[0.0, -1.0, 0.0], dita_sx=[0.0, -0.2, 1.0], chiusa_sx=0.3,
                     palmo_dx=[0.0, -1.0, 0.0], dita_dx=[0.0, -0.2, 1.0], chiusa_dx=0.3),
            44: LIBERE,
        },
    },
}


def _mano(lato, p):
    s = "sx" if lato == "l" else "dx"
    segno = 1.0 if lato == "l" else -1.0
    t = p[s]
    z = p["z"]
    return [
        {"ik": {"spalla": "arm_stretch." + lato, "gomito": "forearm_stretch." + lato, "mano": "hand." + lato,
                "bersaglio": [t[0], t[1], z + t[2]], "polo": p.get("polo_" + s, [segno, -1, -0.3])}},
        ## Le dita verso `dita`, poi la mano gira su se stessa finche' il palmo (-Z locale)
        ## guarda `palmo`.
        {"osso": "hand." + lato, "mira": {"punto": "middle1." + lato, "verso": p["dita_" + s]},
         "rollio": {"oggetto": "hand." + lato, "asse": [0, 0, -1], "verso": p["palmo_" + s]}},
        {"chiudi_mano": {"lato": lato, "chiusura": p["chiusa_" + s], "pollice": 0.3}},
    ]


def _posa(p):
    z = p["z"]
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, -p["giu"], 1.0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": p["giro"]},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": p["pende"]},
    ]
    for lato in "lr":
        piede = p["piedi"][lato]
        x, pz = piede[0], piede[1]
        su = piede[2] if len(piede) > 2 else 0.0
        segno = 1.0 if lato == "l" else -1.0
        passi += [
            {"ik": {"spalla": "thigh_stretch." + lato, "gomito": "leg_stretch." + lato, "mano": "foot." + lato,
                    "bersaglio": [x, CAVIGLIA + su, pz], "polo": p.get("polo_" + lato, [0.2 * segno, 0, 1])}},
            {"osso": "foot." + lato, "come_base": True},
            {"osso": "foot." + lato, "asse": [0, 1, 0], "gradi": -6.0 * segno},
        ]
        if len(piede) > 3:
            passi.append({"osso": "foot." + lato, "asse": [1, 0, 0], "gradi": piede[3]})
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": p["schiena"][0]},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": p["schiena"][1]},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": p["petto"][0]},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": p["petto"][1]},
    ]
    passi += _mano("l", p) + _mano("r", p)
    passi += [
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": p["testa"][0]},
        {"osso": "head.x", "asse": [0, 1, 0], "gradi": p["testa"][1]},
    ]
    return passi


def spec(nome):
    c = CLIP[nome]
    chiavi = sorted(c["chiavi"])
    return {
        "_nota": "Generato da arcanium/animazioni/interazioni/aperture.py (%s): non si modifica a mano." % nome,
        "frames": c["frames"],
        "base": c["frames"],
        "chiavi": chiavi,
        "pose": {str(f): _posa(c["chiavi"][f]) for f in chiavi},
    }


if __name__ == "__main__":
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1]), uscita, indent=1)
    print("scritto", sys.argv[2], sys.argv[1])
