# -*- coding: utf-8 -*-
"""Le POSE CHIAVE del cammino a una mano (root-LightWalking) sullo scheletro ARP.

    python arcanium/animazioni/locomozione/cammino_una_mano.py <uscita.json>

Scrive il json che `arcanium/tools/casc_pose_fk.py` applica in Cascadeur sulla scena di
lavorazione senza rig. Un ciclo intero: due passi da 16 frame a 30 fps, in loop. La
velocita' e' quella del gioco di oggi, 1,436 m/s: il passo viene 76,6 cm.

Il personaggio avanza DAVVERO nel mondo, col c_traj che porta il root motion, e i piedi
d'appoggio stanno fermi a terra: e' quello che la fisica di Cascadeur vuole vedere.

Per ogni passo, da quando il tallone tocca:
    0 contatto, 4 carico, 8 passaggio, 12 sul metatarso, poi il piede diventa quello di
    dietro: 16 spinta, 20 stacco, 24 passaggio in volo, 28 si allunga verso il contatto.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm, dal
corpo ARP di Edran: bacino a 105,1, caviglia a 14,6, metatarso a 16,7 davanti alla caviglia.
"""
import json
import math
import sys

MEZZO_CICLO = 16
FRAMES = MEZZO_CICLO * 2 + 1
CHIAVI = list(range(0, FRAMES, 4))
PASSO = 76.6
AVANZA = PASSO / MEZZO_CICLO

## Il piede, dalla caviglia (nel piano Z-Y).
CAVIGLIA_SU = 14.6
TALLONE_DIETRO = 5.0
METATARSO_AVANTI = 16.7
METATARSO_SU = 2.6

## Dove si tocca, dalla proiezione del bacino: si mette il tallone qui davanti.
CONTATTO = 34.0
LARGHEZZA = 9.0

SPADA = "RightHand_Sword"
SCUDO = "LeftHand_Mesh"

## Il bacino nel mezzo ciclo: quanto sotto il riposo (105,1), verso il lato d'appoggio, e
## girato. Il secondo mezzo ciclo e' lo specchio.
BACINO_GIU = {0: 5.1, 4: 5.6, 8: 1.1, 12: 0.6}
BACINO_LATO = {0: 0.0, 4: 1.5, 8: 2.5, 12: 1.5}
BACINO_GIRO = {0: -6.0, 4: -3.0, 8: 0.0, 12: 3.0}
BACINO_ROLLIO = {0: 0.0, 4: 3.0, 8: 2.0, 12: 0.5}

## La mano della spada dal bacino (Z), mentre il piede sinistro e' avanti allo 0.
BRACCIO_DESTRO = {0: 16.0, 4: 12.0, 8: 4.0, 12: -4.0, 16: -10.0, 20: -6.0, 24: 4.0, 28: 12.0}
## Lo scudo invece va avanti CON la gamba sinistra, come chi cammina con uno scudo al
## braccio (l'utente, 2026-11-08): oscillando al contrario tornava indietro proprio mentre
## la coscia veniva avanti, e ci entrava di 8 cm. Arriva davanti un attimo prima di lei.
BRACCIO_SINISTRO = {0: 18.0, 4: 17.0, 8: 9.0, 12: 5.0, 16: 4.0, 20: 8.0, 24: 19.0, 28: 19.0}


def radice(f):
    return AVANZA * f


def specchio(f):
    """Il frame nel mezzo ciclo, e il segno del lato: +1 sinistro in appoggio."""
    f = f % (MEZZO_CICLO * 2)
    if f < MEZZO_CICLO:
        return f, 1.0
    return f - MEZZO_CICLO, -1.0


def _ruota_zy(z, y, gradi):
    """Rotazione attorno a +X: da Y verso Z. Positivo = le punte scendono."""
    t = math.radians(gradi)
    return y * math.sin(t) + z * math.cos(t), y * math.cos(t) - z * math.sin(t)


def caviglia_e_beccheggio(fase, tallone):
    """Dove sta la caviglia e quanto e' girato il piede, `fase` frame dopo il contatto del
    piede il cui tallone e' toccato in `tallone` (Z). Da fase 20 il piede vola."""
    metatarso = tallone + TALLONE_DIETRO + METATARSO_AVANTI
    if fase == 0:
        ## Punte in su, sul tallone.
        dz, dy = _ruota_zy(TALLONE_DIETRO, CAVIGLIA_SU, -18.0)
        return tallone + dz, dy, -18.0
    if fase in (4, 8):
        return tallone + TALLONE_DIETRO, CAVIGLIA_SU, 0.0
    if fase in (12, 16, 20):
        ## Il tallone sale, sul metatarso che resta a terra.
        gradi = {12: 8.0, 16: 30.0, 20: 48.0}[fase]
        dz, dy = _ruota_zy(-METATARSO_AVANTI, CAVIGLIA_SU - METATARSO_SU, gradi)
        stacco = 1.5 if fase == 20 else 0.0
        return metatarso + dz, METATARSO_SU + dy + stacco, gradi
    if fase == 24:
        ## Sotto al bacino, nel frame del passaggio.
        return tallone + TALLONE_DIETRO + AVANZA * 24 - CONTATTO - 3.0, 25.0, 22.0
    if fase == 28:
        return tallone + PASSO * 2 - 10.0, 18.0, -8.0
    raise ValueError(fase)


def gamba(lato, f, bacino_z):
    """`lato` +1 sinistra, -1 destra. Il sinistro tocca allo 0, il destro al 16."""
    s = "l" if lato > 0 else "r"
    primo_contatto = 0 if lato > 0 else MEZZO_CICLO
    ## L'ultimo contatto di questo piede prima di f.
    giri = math.floor((f - primo_contatto) / float(MEZZO_CICLO * 2))
    contatto = primo_contatto + giri * MEZZO_CICLO * 2
    tallone = radice(contatto) + bacino_z + CONTATTO
    z, y, gradi = caviglia_e_beccheggio(f - contatto, tallone)
    ## Le punte del riposo sono aperte di 17 gradi: ne restano 7.
    apri = -10.0 * lato
    passi = [
        {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                "bersaglio": [LARGHEZZA * lato, y, z], "polo": [0.08 * lato, 0, 1]}},
        {"osso": "foot." + s, "come_base": True},
        {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": apri},
    ]
    if gradi:
        passi.append({"osso": "foot." + s, "asse": [1, 0, 0], "gradi": gradi})
    ## Sul metatarso la punta resta piatta a terra.
    if gradi > 0.0 and f - contatto in (12, 16, 20):
        passi.append({"osso": "toes_01." + s, "come_base": True})
        passi.append({"osso": "toes_01." + s, "asse": [0, 1, 0], "gradi": apri})
    return passi


def busto(giro, rollio):
    """Le spalle controgirano il bacino, e il busto si porta un poco in avanti."""
    return [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 1.5},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -giro * 0.8},
        {"osso": "spine_01.x", "asse": [0, 0, 1], "gradi": -rollio * 0.6},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 2.0},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -giro * 1.5},
        {"osso": "spine_03.x", "asse": [0, 0, 1], "gradi": -rollio * 0.6},
    ]


def braccia(f, avanti):
    giro = f % (MEZZO_CICLO * 2)
    destra = BRACCIO_DESTRO[giro]
    sinistra = BRACCIO_SINISTRO[giro]
    return [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [-27.0, 101.0, avanti + destra], "polo": [-1, -0.3, -0.5]}},
        {"osso": "hand.r", "mira": {"oggetto": SPADA, "asse": [0, -1, 0],
                                    "verso": [0.1, -0.35 - destra * 0.004, 0.93]}},
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio": [26.0, 103.0, avanti + sinistra], "polo": [1, 0, -1]}},
        ## Niente mira sullo scudo: con la presa fissa piegava il polso fino a 80 gradi verso il
        ## basso (2026-11-09). Il polso resta dritto sull'avambraccio, come nel riposo.
    ]


def testa():
    """Lo sguardo resta dritto davanti, mentre sotto gira tutto."""
    return [
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": 2.0},
    ]


def posa(f):
    m, lato = specchio(f)
    giu = BACINO_GIU[m]
    x = BACINO_LATO[m] * lato
    giro = BACINO_GIRO[m] * lato
    rollio = BACINO_ROLLIO[m] * lato
    z = radice(f)
    ## Il bacino del riposo sta a 0,2 davanti alla radice: in cammino, 1 cm in piu'.
    avanti = 1.0
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [x, -giu, avanti]},
    ]
    if giro:
        passi.append({"osso": "root.x", "asse": [0, 1, 0], "gradi": giro})
    if rollio:
        passi.append({"osso": "root.x", "asse": [0, 0, 1], "gradi": rollio})
    passi += gamba(1.0, f, avanti) + gamba(-1.0, f, avanti)
    passi += busto(giro, rollio) + braccia(f, z + avanti) + testa()
    return passi


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/cammino_una_mano.py: non si modifica a mano.",
        "frames": FRAMES,
        ## La posa ferma sta DOPO il ciclo: anche il frame 0 e' una posa, e le misure partono da li'.
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as uscita:
        json.dump(spec(), uscita, indent=1)
    print("scritto", sys.argv[1], len(CHIAVI), "pose")
