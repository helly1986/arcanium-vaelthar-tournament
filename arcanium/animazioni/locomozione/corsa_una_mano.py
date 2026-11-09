# -*- coding: utf-8 -*-
"""Le POSE CHIAVE della corsa a una mano (root-LightRunning) sullo scheletro ARP, per il
MOTION GENERATION di Cascadeur (stile Run).

    python arcanium/animazioni/locomozione/corsa_una_mano.py <uscita.json>

Scrive il json che `arcanium/tools/casc_pose_fk.py` applica in Cascadeur sulla scena di
lavorazione senza rig, la stessa base del cammino (33 frame, la posa ferma al 33).

Il metodo dell'utente (2026-11-09): la stessa durata del cammino, una traiettoria piu' lunga,
e il generatore in modalita' Run fa il resto. Si lavora bene sulle pose di partenza e di
arrivo, che e' da li' che veniva lo strappo del cammino ([[motion-generation-pose-prima]]).

Con le sole chiavi 0 e 32 il generatore ha inventato male (passi a 0, 9, 17, 27, 32; il
bacino da 13 a 36 cm per frame; rimbalzo di 16 cm): "guidiamolo di piu'" (l'utente). Quindi
una chiave a OGNI CONTATTO: il sinistro ai frame 0, 16 e 32, il destro, specchiato, a 8 e
24. Fra un contatto e l'altro il generatore riempie solo il volo. Le pose dello stesso
piede sono identiche, cambia solo la traiettoria; dalla generazione si tiene il ciclo di
MEZZO (8 -> 24), lontano dagli estremi dove il generatore parte e arriva come da fermo.

La velocita' e' quella della corsa di oggi in gioco, 6,49 m/s (MeleeLib/root-LightRunning:
3,78 m in 17 frame): 692 cm in 32 frame, 346 per ciclo, passi da 173 cm.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm, dal
corpo ARP di Edran: bacino a 105,1, caviglia a 14,6, metatarso a 16,7 davanti alla caviglia.
"""
import json
import math
import sys

FRAMES = 33
CHIAVI = [0, 8, 16, 24, 32]
CICLO = 16
VELOCITA = 649.0  # cm/s
AVANZA = VELOCITA / 30.0  # cm per frame: 21,6

## Il piede, dalla caviglia (nel piano Z-Y).
CAVIGLIA_SU = 14.6
TALLONE_DIETRO = 5.0

SPADA = "RightHand_Sword"
SCUDO = "LeftHand_Mesh"

## Il bacino nel contatto della corsa: piu' basso che nel cammino (il ginocchio d'appoggio
## ammortizza), un poco avanti sotto un busto che pende, girato verso la gamba che arriva.
## 2026-11-09, l'utente sulla corsa vecchia della MeleeLib (Amareth, bacino a 68 cm): "il
## busto e' chino e la falcata e' ampia, molto molto ampia, le braccia non puntano in alto
## ma sono molto libere. Replichiamo una cosa simile". Quindi bacino giu' di 20, busto chino
## in tutto ~40 gradi, piedi lontani davanti e dietro. Con bacino -20, contatto 40 e stacco -78
## il motion generation non rispettava le chiavi dei piedi (il destro mai sotto 8 cm, spesso a
## 15-30): ridotti a -14, 32 e -68.
BACINO_GIU = 14.0
BACINO_AVANTI = 3.0
BACINO_GIRO = -8.0
## E pende avanti con il busto (gradi su X, positivo = avanti).
BACINO_PENDE = 14.0

## Il sinistro tocca davanti al bacino: nella corsa si appoggia vicino al baricentro, non
## lontano come nel cammino (34 cm), sul tallone appena, punte su di 8 gradi.
CONTATTO = 32.0
LARGHEZZA = 8.0
PUNTE_SU = -8.0

## Il destro ha appena staccato: dietro e su, il ginocchio piegato, le punte giu'.
DIETRO_Z = -68.0
DIETRO_Y = 42.0
DIETRO_PUNTE = 65.0

## Il busto pende avanti (gradi su X, positivo = avanti) e le spalle controgirano.
PENDE_BASSO = 14.0
PENDE_ALTO = 12.0
## La testa ripaga la pendenza per guardare avanti (gradi su X, negativo = su).
TESTA = -22.0

## Le mani, gomiti piegati: al contatto del sinistro la spada e' avanti (braccio opposto
## alla gamba) e lo scudo anche, perche' va avanti CON la gamba sinistra (l'utente,
## 2026-11-08: oscillando al contrario entrava nella coscia).
## 2026-11-09, l'utente: prima "le braccia si muovono troppo poco rispetto al busto e alle
## gambe e restano verso il basso", poi sulla corsa vecchia "le braccia non puntano in alto ma
## sono molto libere". Oscillano larghe, dalla spalla, e col busto chino stanno davanti al
## petto quando vanno avanti e dietro il fianco quando vanno indietro.
MANO_DESTRA = [-18.0, 104.0, 58.0]
MANO_SINISTRA = [22.0, 106.0, 52.0]
## Al contatto del destro le braccia vanno indietro: la spada col braccio opposto alla
## gamba, lo scudo con la gamba sinistra che ora e' dietro (ma resta davanti al fianco).
MANO_DESTRA_DIETRO = [-27.0, 92.0, -12.0]
MANO_SINISTRA_DIETRO = [26.0, 98.0, 14.0]
## La punta della spada (il suo -Y) segue il braccio, libera: avanti un po' su quando il
## braccio va avanti, indietro e giu' quando va indietro, come la lama trascinata della
## corsa vecchia.
SPADA_VERSO = [0.1, 0.35, 1.0]
SPADA_VERSO_DIETRO = [0.1, -0.5, -1.0]
## Dove guarda la faccia dello scudo (il suo +Z).
SCUDO_VERSO = [0.5, 0.1, 1.0]


def _ruota_zy(z, y, gradi):
    """Rotazione attorno a +X: da Y verso Z. Positivo = le punte scendono."""
    t = math.radians(gradi)
    return y * math.sin(t) + z * math.cos(t), y * math.cos(t) - z * math.sin(t)


def gambe(bacino_z, tocca):
    """`tocca` +1: il sinistro e' a terra davanti e il destro dietro; -1 lo specchio."""
    tallone = bacino_z + CONTATTO
    dz, dy = _ruota_zy(TALLONE_DIETRO, CAVIGLIA_SU, PUNTE_SU)
    passi = []
    davanti = ((tallone + dz, dy), PUNTE_SU)
    dietro = ((bacino_z + DIETRO_Z, DIETRO_Y), DIETRO_PUNTE)
    for lato, s in ((1.0, "l"), (-1.0, "r")):
        (z, y), gradi = davanti if lato == tocca else dietro
        apri = -10.0 * lato
        passi += [
            {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                    "bersaglio": [LARGHEZZA * lato, y, z], "polo": [0.08 * lato, 0, 1]}},
            {"osso": "foot." + s, "come_base": True},
            {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": apri},
            {"osso": "foot." + s, "asse": [1, 0, 0], "gradi": gradi},
        ]
    return passi


def busto(tocca):
    return [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": PENDE_BASSO},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -BACINO_GIRO * 0.8 * tocca},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": PENDE_ALTO},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -BACINO_GIRO * 1.5 * tocca},
    ]


def braccia(bacino_z, tocca):
    d, s = (MANO_DESTRA, MANO_SINISTRA) if tocca > 0 else (MANO_DESTRA_DIETRO, MANO_SINISTRA_DIETRO)
    v = SPADA_VERSO if tocca > 0 else SPADA_VERSO_DIETRO
    return [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [d[0], d[1], bacino_z + d[2]], "polo": [-1, -0.6, -0.4]}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0], "verso": v}},
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": [s[0], s[1], bacino_z + s[2]], "polo": [1, -0.3, -1]}},
        ## Niente mira sullo scudo: con la presa fissa piegava il polso fino a 80 gradi verso il
        ## basso (2026-11-09). Il polso resta dritto sull'avambraccio, come nel riposo.
        ## Con l'avambraccio quasi orizzontale lo scudo si coricava come un vassoio: lo si
        ## raddrizza girando l'avambraccio su se stesso (rollio puro, come nella guardia),
        ## la faccia verso avanti e un po' in fuori.
        {"osso": "forearm_stretch.l", "mira": {"punto": "hand.l"},
         "rollio": {"oggetto": SCUDO, "asse": [0, 0, 1], "verso": SCUDO_VERSO}},
    ][:None if SCUDO_VERSO else -1]


def testa():
    """Lo sguardo resta dritto davanti: la testa ripaga la pendenza del busto."""
    return [
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": TESTA},
    ]


def posa(f):
    z = AVANZA * f
    tocca = 1.0 if f % CICLO == 0 else -1.0
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [0, -BACINO_GIU, BACINO_AVANTI]},
        {"osso": "root.x", "asse": [0, 1, 0], "gradi": BACINO_GIRO * tocca},
        {"osso": "root.x", "asse": [1, 0, 0], "gradi": BACINO_PENDE},
    ]
    bacino_z = z + BACINO_AVANTI
    return passi + gambe(bacino_z, tocca) + busto(tocca) + braccia(bacino_z, tocca) + testa()


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/corsa_una_mano.py: non si modifica a mano.",
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as uscita:
        json.dump(spec(), uscita, indent=1)
    print("scritto", sys.argv[1], len(CHIAVI), "pose")
