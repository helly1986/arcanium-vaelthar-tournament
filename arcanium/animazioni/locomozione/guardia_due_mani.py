# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dello STRAFE CAMMINANDO A DUE MANI col nemico agganciato, IN GUARDIA: l'arma
puntata davanti con la lama verso il nemico, in quattro direzioni.

    python arcanium/animazioni/locomozione/guardia_due_mani.py <campione> <sinistra|destra|avanti|indietro> <uscita.json>

Scelta dell'utente, 2026-11-10: agganciata Zarine va IN GUARDIA al passo e si rimette l'asta in
spalla di corsa. La guardia e' quella del gioco: la destra davanti sull'asta, la sinistra 25 cm
piu' indietro verso il contrappeso (la presa per cui e' nata seconda_mano.gd, qui senza farla
scorrere), la lama avanti e un poco in alto.

Il passo e' quello della guardia a una mano di Edran (guardia_una_mano.py): i piedi SFALSATI
che si SUPERANO, un passo ogni 12 frame, chiavi ogni 12 frame su due cicli (base da 50 frame),
dalla generazione si tiene il ciclo di mezzo (`--taglia 12 36`). Ma qui avanti sta il DESTRO,
dalla parte della mano che sta davanti sull'asta, e il bacino gira col fianco sinistro
indietro. Tutto in scala sul corpo del campione (CORPI).

Destra e sinistra NON sono una lo specchio dell'altra: la guardia e' asimmetrica (il destro
avanti, la destra davanti sull'asta) e uno specchio cambierebbe guardia passando da una
direzione all'altra. Si generano tutte e quattro con la stessa guardia.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm.
"""
import json
import sys

from cammino_due_mani import CORPI

FRAMES = 49
MEZZO = 12
CHIAVI = [0, 12, 24, 36, 48]
VELOCITA = 100.0  # cm/s

DIREZIONI = {"sinistra": (1.0, 0.0), "destra": (-1.0, 0.0), "avanti": (0.0, 1.0), "indietro": (0.0, -1.0)}
GUIDA = {"sinistra": "l", "destra": "r", "avanti": "r", "indietro": "l"}


def posa(nome, f, direzione):
    c = CORPI[nome]
    k = c["scala"]
    sm = c["seconda_mano"]
    avanza = VELOCITA / 30.0
    passo = avanza * MEZZO
    ## La guardia ferma: piedi a 20 cm di larghezza, il DESTRO avanti di 28 cm sul sinistro.
    stretta = {"r": (-10.0 * k, 14.0 * k), "l": (10.0 * k, -14.0 * k)}
    punte = {"r": -6.0, "l": 18.0}
    dx, dz = DIREZIONI[direzione]
    guida = GUIDA[direzione]
    tocca = guida if (f // MEZZO) % 2 == 0 else ("r" if guida == "l" else "l")
    centro = (dx * avanza * f, dz * avanza * f)
    giro = -14.0
    passi = [
        {"osso": "c_traj", "sposta": [centro[0], 0, centro[1]]},
        {"osso": "root.x", "sposta": [0, -8.0 * k, 1.0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": giro},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": 3.0},
    ]
    for s in "lr":
        x, z = stretta[s]
        segno = 1.0 if s == tocca else -1.0
        x += dx * passo / 2.0 * segno
        z += dz * passo / 2.0 * segno
        lato = 1.0 if s == "l" else -1.0
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": [centro[0] + x, c["caviglia"], centro[1] + z], "polo": [0.25 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": punte[s] * lato},
        ]
    ## Il busto ripaga meta' del giro: il petto resta un poco di tre quarti, la destra avanti.
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 3.0},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -giro * 0.3},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 4.0},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -giro * 0.3},
    ]
    ## L'utente, 2026-11-10, su una foto di guardia con l'arma lunga: la destra la tiene DA
    ## SOPRA (il polso sopra l'asta: serve al fendente a due mani dall'alto, e il thrust si fa
    ## lo stesso), e l'arma non punta dritta al nemico ma avanti e IN FUORI A DESTRA, come la
    ## terrebbe uno spadone. Le mani stanno verso il centro, davanti alla vita; la lama sale un
    ## poco.
    ## Il polso NATURALE (l'utente, 2026-11-10: «il polso e' piegato al contrario... da sopra
    ## non c'e' estensione dei legamenti, la presa e' normale e naturale»): ogni mano si gira
    ## attorno all'asta finche' il lato del polso guarda il gomito, cioe' continua
    ## l'avambraccio; i gomiti in fuori e un poco alti, come chi impugna da sopra.
    passi += [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [centro[0] - 2.0, 104.0, centro[1] + 28.0], "polo": [-1, 0.3, -0.6]}},
        {"osso": "hand.r", "mira": {"oggetto": c["arma"], "asse": [0, 1, 0], "verso": [-0.55, 0.25, 1.0]},
         "rollio": {"oggetto": c["arma"], "asse": [-1, 0, 0], "verso_osso": ["hand.r", "forearm_stretch.r"]}},
        {"chiudi_mano": {"lato": "r", "chiusura": c["chiusura_destra"], "pollice": c["pollice_destra"]}},
        {"presa_su": {"lato": "l", "oggetto": c["arma"], "base": sm[:9], "punto": [v * 100.0 for v in sm[9:12]],
                      "polo": [1, 0.2, -0.6]}},
        {"chiudi_mano": {"lato": "l", "chiusura": c["chiusura_sinistra"], "pollice": c["pollice_sinistra"]}},
        {"osso": "head.x", "come_base": True},
    ]
    return passi


def spec(nome, direzione):
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/guardia_due_mani.py (%s, %s): non si modifica a mano." % (nome, direzione),
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(nome, f, direzione) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[3], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1], sys.argv[2]), uscita, indent=1)
    print("scritto", sys.argv[3], sys.argv[1], sys.argv[2], len(CHIAVI), "pose")
