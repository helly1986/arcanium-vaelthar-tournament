# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dello STRAFE CAMMINANDO a una mano col nemico agganciato: passi accorti,
pronti, senza mai incrociare le gambe, in quattro direzioni.

    python arcanium/animazioni/locomozione/guardia_una_mano.py <sinistra|destra|avanti|indietro> <uscita.json>

Scelta dell'utente, 2026-11-09: lo strafe camminando a passi accostati (quello correndo sara'
col bacino girato, alla souls-like), in tutte le direzioni. PRONTI, non in parata: lo scudo
alto e' la PARATA, che il gioco fonde sulla parte alta del corpo sopra qualunque clip delle
gambe quando si tiene premuto il blocco (`Guarding`, blend filtrato su braccia e petto). Qui
lo scudo sta all'altezza della vita davanti al fianco, la spada pronta e bassa.

Il passo, ALLA ELDEN RING (l'utente, 2026-11-09: il passo accostato faceva troppi passetti,
circa 5 al secondo a 1,1 m/s, perche' il corpo avanza solo di quanto si allarga il piede).
I piedi restano SFALSATI, il sinistro (lato dello scudo) avanti e il destro indietro, e si
SUPERANO: chi segue passa dietro all'altro, alla sua profondita', senza sforbiciare davanti.
Ogni passo copre il doppio: a 1,1 m/s un passo ogni 12 frame (2,5 al secondo), ciclo di 24
frame e 88 cm. Al contatto di un piede, chi tocca sta mezzo passo (22 cm) avanti nella
direzione di marcia rispetto alla sua posizione di guardia, l'altro mezzo passo indietro: il
piede d'appoggio sta fermo nel mondo mentre il bacino scorre (verificato a mano: dal contatto
del sinistro a quello del destro il bacino fa 44 cm, e il sinistro da +22 finisce a -22).

Chiavi ogni 12 frame su due cicli (0-48: la base da 50 frame, `base_cascadeur.py ... tieni=50`)
per il motion generation di Cascadeur; dalla generazione si tiene il ciclo di mezzo
(`rifinisci ... --taglia 12 36`).

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm, dal
corpo ARP di Edran: bacino a 105,1, caviglia a 14,6.
"""
import json
import sys

FRAMES = 49
MEZZO = 12
CHIAVI = [0, 12, 24, 36, 48]
VELOCITA = 110.0  # cm/s
AVANZA = VELOCITA / 30.0
PASSO = AVANZA * MEZZO  # 44 cm a passo, 88 per ciclo

DIREZIONI = {"sinistra": (1.0, 0.0), "destra": (-1.0, 0.0), "avanti": (0.0, 1.0), "indietro": (0.0, -1.0)}
## Il piede che tocca al frame 0: quello dal lato dove si va.
GUIDA = {"sinistra": "l", "destra": "r", "avanti": "l", "indietro": "r"}

CAVIGLIA_SU = 14.6
## La guardia ferma: piedi a 22 cm di larghezza, il sinistro (lato dello scudo) avanti e il
## destro indietro di 32 cm: e' la profondita' a cui si superano.
STRETTA = {"l": (11.0, 16.0), "r": (-11.0, -16.0)}
## Le punte un poco aperte, e il destro girato verso fuori come chi sta in guardia.
PUNTE = {"l": -8.0, "r": 18.0}

## Gambe flesse: il bacino scende, di piu' quando i piedi sono larghi; girato di 12 gradi con
## il fianco destro indietro, e pende appena avanti.
BACINO_GIU = 9.0
BACINO_GIRO = 12.0
BACINO_PENDE = 3.0

## Pronti: lo scudo alla vita davanti al fianco sinistro (dritto, col rollio dell'avambraccio),
## la spada bassa con la punta avanti.
MANO_SINISTRA = [24.0, 100.0, 20.0]
MANO_DESTRA = [-26.0, 102.0, 18.0]

SPADA = "RightHand_Sword"
SCUDO = "LeftHand_Mesh"


def posa(f, direzione):
    dx, dz = DIREZIONI[direzione]
    guida = GUIDA[direzione]
    ## Al frame 0 tocca chi guida, a 12 l'altro, e cosi' via.
    tocca = guida if (f // MEZZO) % 2 == 0 else ("r" if guida == "l" else "l")
    centro = (dx * AVANZA * f, dz * AVANZA * f)
    passi = [
        {"osso": "c_traj", "sposta": [centro[0], 0, centro[1]]},
        {"osso": "root.x", "sposta": [0, -BACINO_GIU, 1.0]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": BACINO_GIRO},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": BACINO_PENDE},
    ]
    for s in "lr":
        x, z = STRETTA[s]
        ## Mezzo passo avanti nella direzione di marcia per chi tocca, mezzo indietro per l'altro.
        segno = 1.0 if s == tocca else -1.0
        x += dx * PASSO / 2.0 * segno
        z += dz * PASSO / 2.0 * segno
        lato = 1.0 if s == "l" else -1.0
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": [centro[0] + x, CAVIGLIA_SU, centro[1] + z], "polo": [0.25 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": PUNTE[s] * lato},
        ]
    ## Le spalle tornano verso il bersaglio: il busto ripaga il giro del bacino.
    passi += [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 3.0},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -BACINO_GIRO * 0.5},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 3.0},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -BACINO_GIRO * 0.5},
    ]
    s, d = MANO_SINISTRA, MANO_DESTRA
    passi += [
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": [centro[0] + s[0], s[1], centro[1] + s[2]], "polo": [1, -1, -0.3]}},
        ## Lo scudo si orienta girando l'AVAMBRACCIO su se stesso, non il polso: con
        ## l'avambraccio davanti al petto e il polso dritto lo scudo stava sdraiato, e la
        ## mira sulla mano piegava il polso fino a 93 gradi (2026-11-09). Una mira senza
        ## `verso` tiene la direzione e fa solo il rollio.
        {"osso": "forearm_stretch.l", "mira": {"punto": "hand.l"},
         "rollio": {"oggetto": SCUDO, "asse": [0, 0, 1], "verso": [-0.15, 0.1, 1]}},
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [centro[0] + d[0], d[1], centro[1] + d[2]], "polo": [-1, -1, -0.3]}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": [0.1, 0.1, 1.0]}},
        {"osso": "head.x", "come_base": True},
    ]
    return passi


def spec(direzione):
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/guardia_una_mano.py (%s): non si modifica a mano." % direzione,
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(f, direzione) for f in CHIAVI},
    }


if __name__ == "__main__":
    direzione = sys.argv[1]
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(direzione), uscita, indent=1)
    print("scritto", sys.argv[2], direzione, len(CHIAVI), "pose")
