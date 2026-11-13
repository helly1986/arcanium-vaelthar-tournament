# -*- coding: utf-8 -*-
"""Le POSE CHIAVE del primo gruppo di clip a una mano su Edran (spada e scudo), per Cascadeur:
il colpo di scudo, la parata perfetta, la pozione e l'oggetto che non va.

    python arcanium/animazioni/difesa/gruppo_scudo_una_mano.py <clip> <uscita.json>

con <clip> fra: colpo_scudo, parata_perfetta, pozione, uso_fallito, cambio_arma,
cambio_gadget.

L'utente, 2026-11-11: le clip si fanno a gruppi di 3-4 («cosi' facciamo prima e abbiamo meno
scambio di input»). Le scelte, una per clip:
- ShieldBash, il colpo di scudo: «spinta con passo», un passo avanti col sinistro e lo scudo
  spinto dritto con tutto il peso, poi di nuovo in guardia. Si sposta: motion generation e
  fisica. Il oneshot `Gadget` del player la suona su tutto il corpo.
- GuardParry, la parata perfetta: «spazzata in fuori», lo scudo devia il colpo spazzando a
  sinistra e in fuori, il busto segue, poi in guardia. Da fermo; in gioco filtrata su petto e
  braccio sinistro come il colpo parato (si para anche camminando).
- UsePotion: «mano sinistra, spada pronta», la sinistra porta la fiala alla bocca, la testa va
  indietro, la spada resta pronta. Lo scudo e' nella sinistra: col gomito alzato in fuori finiva
  sopra la testa come un cappello (primo foglio); l'utente ha scelto lo SCUDO DAVANTI AL VISO,
  la guardia alzata fino alla bocca: l'avambraccio orizzontale col gomito in fuori, lo scudo
  davanti al viso (con l'avambraccio verticale lo scudo, che si allunga oltre la mano, saliva
  ancora sopra la testa), si beve al riparo. Il oneshot `UseItem` la filtra sulla
  parte alta: si beve camminando.
- ItemUseFail: «mano alla cintura e gesto che scuote la testa subito dopo».

Le pose si danno per chiave con poche grandezze (`_posa`): dove sta la traiettoria, il
bacino, i piedi, il busto, le due mani (con dove guardano scudo e spada) e la testa. Le mani
e i piedi sono relativi alla traiettoria (+Z avanti). Assi del mondo di Cascadeur: +Y in alto,
+Z davanti, +X la sua sinistra. Misure in cm, dal corpo ARP di Edran: bacino a 105,1,
caviglia a 14,6.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

CAVIGLIA = 14.6
SPADA = "RightHand_Sword"
SCUDO = "LeftHand_Mesh"

## In guardia (parata_una_mano.py): il sinistro avanti, il bacino basso e girato, lo scudo alto.
GUARDIA = {
    "z": 0.0, "giu": 9.0, "giro": 12.0, "pende": 4.0,
    "piedi": {"l": (11.0, 16.0), "r": (-11.0, -16.0)},
    "schiena": (4.0, -6.0), "petto": (6.0, -6.0),
    "sx": [10.0, 124.0, 30.0], "scudo": [-0.1, 0.05, 1.0],
    "dx": [-30.0, 126.0, 16.0], "spada": [-0.04, 0.06, 1.0],
    "testa": (10.0, 0.0),
}
## Pronti (guardia_una_mano.py, gli strafe al passo): lo scudo alla vita, la spada bassa.
PRONTI = dict(GUARDIA, pende=3.0, schiena=(3.0, -6.0), petto=(3.0, -6.0),
              sx=[24.0, 100.0, 20.0], scudo=[-0.15, 0.1, 1.0],
              dx=[-26.0, 102.0, 18.0], spada=[0.1, 0.1, 1.0], testa=(0.0, 0.0))


def _con(base, **cambi):
    p = dict(base)
    p.update(cambi)
    return p


CLIP = {
    ## 20 frame (0,67 s). Carica (f4), impatto col passo (f8), tiene (f12), guardia (f19).
    "colpo_scudo": {
        "frames": 20,
        "chiavi": {
            0: GUARDIA,
            4: _con(GUARDIA, z=-4.0, giu=12.0, pende=0.0, petto=(4.0, 6.0),
                    sx=[8.0, 122.0, 20.0], dx=[-30.0, 124.0, 10.0]),
            8: _con(GUARDIA, z=26.0, giu=14.0, pende=14.0, schiena=(2.0, -10.0), petto=(2.0, -14.0),
                    piedi={"l": (11.0, 58.0), "r": (-11.0, -16.0)},
                    sx=[14.0, 124.0, 64.0], scudo=[0.0, 0.05, 1.0], dx=[-30.0, 122.0, 8.0], testa=(4.0, 0.0)),
            12: _con(GUARDIA, z=30.0, giu=12.0, pende=10.0, schiena=(3.0, -8.0), petto=(4.0, -10.0),
                     piedi={"l": (11.0, 58.0), "r": (-11.0, 6.0)},
                     sx=[12.0, 124.0, 54.0], scudo=[-0.05, 0.05, 1.0], dx=[-30.0, 124.0, 12.0]),
            19: _con(GUARDIA, z=34.0, piedi={"l": (11.0, 50.0), "r": (-11.0, 18.0)}),
        },
    },
    ## 18 frame (0,6 s). Va incontro (f3), spazza in fuori (f7), resta aperto (f11), guardia.
    "parata_perfetta": {
        "frames": 18,
        "chiavi": {
            0: GUARDIA,
            3: _con(GUARDIA, petto=(6.0, -12.0), sx=[2.0, 127.0, 34.0], scudo=[0.25, 0.1, 1.0]),
            7: _con(GUARDIA, schiena=(4.0, 0.0), petto=(4.0, 12.0),
                    sx=[42.0, 120.0, 22.0], scudo=[0.75, 0.1, 0.65], testa=(8.0, 6.0)),
            11: _con(GUARDIA, schiena=(4.0, -1.0), petto=(5.0, 9.0),
                     sx=[40.0, 118.0, 22.0], scudo=[0.7, 0.05, 0.7], testa=(9.0, 4.0)),
            17: GUARDIA,
        },
    },
    ## 40 frame (1,33 s). Alla cintura (f6), su alla bocca (f12), beve (f20), giu' (f28).
    "pozione": {
        "frames": 40,
        "chiavi": {
            0: PRONTI,
            6: _con(PRONTI, sx=[16.0, 96.0, 6.0], scudo=[0.6, -0.2, 0.8], testa=(12.0, 8.0)),
            12: _con(PRONTI, sx=[4.0, 150.0, 20.0], scudo=[-0.1, 0.05, 1.0], polo_sx=[1.0, -0.35, -0.2], testa=(0.0, 0.0)),
            20: _con(PRONTI, petto=(-2.0, -6.0), sx=[3.0, 155.0, 17.0], scudo=[-0.1, 0.2, 1.0], polo_sx=[1.0, -0.35, -0.2],
                     testa=(-22.0, 0.0)),
            28: _con(PRONTI, sx=[12.0, 128.0, 26.0], scudo=[-0.1, 0.05, 1.0], testa=(2.0, 0.0)),
            39: PRONTI,
        },
    },
    ## 30 frame (1 s). Alla cintura (f7), torna vuota e la testa scuote (f14, f21).
    "uso_fallito": {
        "frames": 30,
        "chiavi": {
            0: PRONTI,
            7: _con(PRONTI, sx=[16.0, 96.0, 6.0], scudo=[0.6, -0.2, 0.8], testa=(14.0, 8.0)),
            14: _con(PRONTI, sx=[22.0, 102.0, 16.0], testa=(4.0, 14.0)),
            21: _con(PRONTI, testa=(4.0, -12.0)),
            29: PRONTI,
        },
    },
    ## Gruppo 3 (2026-11-12). Il CAMBIO ARMA, «sopra la spalla destra»: la destra va dietro
    ## la spalla a riporre o prendere l'arma sulla schiena e torna in guardia. 24 frame (0,8 s);
    ## a meta' (f12) il gioco scambia l'arma, e lo stesso gesto ripone e riprende le armi
    ## attorno alle aperture. In gioco e' filtrato su busto, testa e braccio destro.
    "cambio_arma": {
        "frames": 24,
        "chiavi": {
            0: PRONTI,
            6: _con(PRONTI, petto=(0.0, -14.0), dx=[-20.0, 150.0, -6.0], spada=[0.1, -1.0, -0.3],
                    polo_dx=[-1.0, 0.7, 0.3], testa=(-4.0, -12.0)),
            12: _con(PRONTI, petto=(-2.0, -18.0), dx=[-14.0, 156.0, -18.0], spada=[0.15, -1.0, -0.15],
                     polo_dx=[-1.0, 0.8, 0.2], testa=(-6.0, -16.0)),
            18: _con(PRONTI, petto=(2.0, -8.0), dx=[-26.0, 118.0, 12.0], polo_dx=[-1.0, -0.2, -0.3], testa=(0.0, -4.0)),
            23: PRONTI,
        },
    },
    ## Il CAMBIO GADGET, «mano al fianco sinistro»: la sinistra scende al fianco, aggancia o
    ## sgancia scudo e sigillo e risale. 21 frame (0,7 s), lo scambio a f10.
    "cambio_gadget": {
        "frames": 21,
        "chiavi": {
            0: PRONTI,
            6: _con(PRONTI, petto=(4.0, 10.0), sx=[26.0, 96.0, -4.0], scudo=[1.0, 0.0, 0.2], testa=(8.0, 10.0)),
            10: _con(PRONTI, petto=(5.0, 14.0), sx=[26.0, 94.0, -10.0], scudo=[1.0, -0.1, 0.0], testa=(10.0, 14.0)),
            15: _con(PRONTI, petto=(3.0, 2.0), sx=[24.0, 100.0, 12.0], testa=(2.0, 4.0)),
            20: PRONTI,
        },
    },
}


def _posa(p):
    z = p["z"]
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, -p["giu"], 1.0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": p["giro"]},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": p["pende"]},
    ]
    punte = {"l": -8.0, "r": 18.0}
    for s in "lr":
        ## (x, z) a terra, oppure (x, z, quanto sale la caviglia, gradi in punta).
        piede = p["piedi"][s]
        x, pz = piede[0], piede[1]
        su = piede[2] if len(piede) > 2 else 0.0
        lato = 1.0 if s == "l" else -1.0
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": [x, CAVIGLIA + su, pz], "polo": p.get("polo_" + s, [0.25 * lato, 0, 1])}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": punte[s] * lato},
        ]
        if len(piede) > 3:
            passi.append({"osso": "foot." + s, "asse": [1, 0, 0], "gradi": piede[3]})
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": p["schiena"][0]},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": p["schiena"][1]},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": p["petto"][0]},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": p["petto"][1]},
    ]
    sx, dx = p["sx"], p["dx"]
    ## Il gomito sinistro in fuori e in basso, o dove dice la chiave (`polo_sx`).
    polo_sx = p.get("polo_sx", [1, -1, -0.2])
    passi += [
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": [sx[0], sx[1], z + sx[2]], "polo": polo_sx}},
        ## Lo scudo si orienta girando l'avambraccio su se stesso, non il polso
        ## (guardia_una_mano.py).
        {"osso": "forearm_stretch.l", "mira": {"punto": "hand.l"},
         "rollio": {"oggetto": SCUDO, "asse": [0, 0, 1], "verso": p["scudo"]}},
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [dx[0], dx[1], z + dx[2]], "polo": p.get("polo_dx", [-1, -0.6, -0.4])}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": p["spada"]}},
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": p["testa"][0]},
        {"osso": "head.x", "asse": [0, 1, 0], "gradi": p["testa"][1]},
    ]
    return passi


def spec(nome):
    c = CLIP[nome]
    chiavi = sorted(c["chiavi"])
    return {
        "_nota": "Generato da arcanium/animazioni/difesa/gruppo_scudo_una_mano.py (%s): non si modifica a mano." % nome,
        "frames": c["frames"],
        "base": c["frames"],
        "chiavi": chiavi,
        "pose": {str(f): _posa(c["chiavi"][f]) for f in chiavi},
    }


if __name__ == "__main__":
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1]), uscita, indent=1)
    print("scritto", sys.argv[2], sys.argv[1])
