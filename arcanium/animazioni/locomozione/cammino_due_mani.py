# -*- coding: utf-8 -*-
"""Le POSE CHIAVE del cammino A DUE MANI (root-HeavyWalking) sullo scheletro ARP.

    python arcanium/animazioni/locomozione/cammino_due_mani.py <campione> <uscita.json>

Le armi a due mani (albero HEAVY: l'asta di Zarine, la vanga di Aurin) si tengono con la
destra, e la sinistra le si appoggia. In gioco la sinistra la mette `seconda_mano.gd`, sopra
la clip; qui la si porta sull'arma (`bersaglio_su` di casc_pose_fk.py) perche' la posa si
giudichi con l'arma tenuta davvero, e perche' il gomito esca dalla parte giusta.

Il cammino e' quello di `cammino_una_mano.py` (stesse fasi del piede, stesso bacino), portato
sulle misure del corpo del campione (CORPI). Cambiano busto e braccia: l'arma si porta
APPOGGIATA SULLA SPALLA destra con due mani (l'utente, 2026-11-10), le braccia non oscillano,
l'asta sobbalza col passo e le spalle controgirano meno. In gioco la clip tiene la sinistra da
se': corpo_campione.gd spegne seconda_mano.gd sulle clip nostre.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti, +X la sua sinistra. Misure in cm.
"""
import json
import math
import sys

## Le misure dei corpi ARP (arcanium/tools: misurate dalle ossa del GLB), e l'arma in mano.
## `arma`: il nome dell'oggetto in Cascadeur (armi_per_cascadeur.gd); l'asta corre lungo il
## suo +Y, da -67 a +118 cm (la lama in cima), e il polso destro le sta a y -14, x -8.
CORPI = {
    "zarine": {
        "bacino": 92.4,
        "caviglia": 11.1,
        "scala": 92.4 / 105.1,  # rispetto a Edran, su cui sono nate le misure del passo
        "arma": "RightHand_asta_contrappeso",
        ## Il polso destro davanti al petto; il punto della spalla destra su cui poggia l'asta
        ## (sopra lo spallaccio: arm_stretch.r e' a -14,2 130,1 -1,6); il punto dell'asta
        ## nel pugno destro; dove guarda il polso dall'asta (il -X dell'asta), giu' verso il
        ## gomito.
        "mano_destra": [-13.0, 100.0, 22.0],
        "spalla": [-13.0, 142.0, -4.0],
        "presa_destra": [0.0, -14.0, 0.0],
        "polso_verso": [-0.2, -1.0, 0.1],
        ## La sinistra sull'asta come la mette il gioco: armi_per_cascadeur.gd, "seconda_mano"
        ## (righe della base, origine in metri, nello spazio della mesh dell'asta).
        "seconda_mano": [-0.0236305221915245, 0.342879593372345, 0.939082145690918,
                         0.955223202705383, 0.284872800111771, -0.0799766555428505,
                         -0.294941306114197, 0.895143091678619, -0.334258198738098,
                         0.00302350521087646, -0.391300201416016, -0.0763371586799622],
        ## ...ma in spalla la presa del gioco non si raggiunge: 25 cm sotto la destra, verso il
        ## contrappeso, la sinistra finiva all'anca, a 60 cm dalla spalla con un braccio di 44.
        ## Si fa scorrere lungo l'asta fin sopra la destra, verso la spalla (cm lungo +Y).
        "seconda_mano_scorre": 48.0,
        ## Le dita come in gioco (aethon.tres).
        "chiusura_destra": 0.9, "pollice_destra": 0.1,
        "chiusura_sinistra": 0.9, "pollice_sinistra": -0.3,
        "velocita": 120.0,  # cm/s; in gioco oggi l'HeavyWalking fa 1,14 m/s
    },
}

MEZZO_CICLO = 16
FRAMES = MEZZO_CICLO * 2 + 1
CHIAVI = list(range(0, FRAMES, 4))


class Corpo(object):
    def __init__(self, nome):
        c = CORPI[nome]
        k = c["scala"]
        self.c = c
        self.passo = c["velocita"] / 30.0 * MEZZO_CICLO
        self.avanza = self.passo / MEZZO_CICLO
        self.caviglia_su = c["caviglia"]
        self.tallone_dietro = 5.0 * k
        self.metatarso_avanti = 16.7 * k
        self.metatarso_su = 2.6 * k
        self.contatto = 30.0 * k
        self.larghezza = 8.0 * k
        ## Il bacino nel mezzo ciclo, come in cammino_una_mano.py: un poco meno di dondolio,
        ## l'arma a due mani tiene il busto piu' fermo.
        self.bacino_giu = {0: 5.0 * k, 4: 5.5 * k, 8: 1.5 * k, 12: 2.0 * k}
        self.bacino_lato = {0: 0.0, 4: 1.5 * k, 8: 2.5 * k, 12: 1.5 * k}
        self.bacino_giro = {0: -5.0, 4: -2.5, 8: 0.0, 12: 2.5}
        self.bacino_rollio = {0: 0.0, 4: 2.5, 8: 1.5, 12: 0.5}


def specchio(f):
    f = f % (MEZZO_CICLO * 2)
    if f < MEZZO_CICLO:
        return f, 1.0
    return f - MEZZO_CICLO, -1.0


def _ruota_zy(z, y, gradi):
    t = math.radians(gradi)
    return y * math.sin(t) + z * math.cos(t), y * math.cos(t) - z * math.sin(t)


def caviglia_e_beccheggio(C, fase, tallone):
    metatarso = tallone + C.tallone_dietro + C.metatarso_avanti
    if fase == 0:
        dz, dy = _ruota_zy(C.tallone_dietro, C.caviglia_su, -16.0)
        return tallone + dz, dy, -16.0
    if fase in (4, 8):
        return tallone + C.tallone_dietro, C.caviglia_su, 0.0
    if fase in (12, 16, 20):
        gradi = {12: 8.0, 16: 28.0, 20: 45.0}[fase]
        dz, dy = _ruota_zy(-C.metatarso_avanti, C.caviglia_su - C.metatarso_su, gradi)
        stacco = 1.5 if fase == 20 else 0.0
        return metatarso + dz, C.metatarso_su + dy + stacco, gradi
    if fase == 24:
        return tallone + C.tallone_dietro + C.avanza * 24 - C.contatto - 3.0, C.caviglia_su + 9.0, 20.0
    if fase == 28:
        return tallone + C.passo * 2 - 9.0, C.caviglia_su + 3.0, -8.0
    raise ValueError(fase)


def gamba(C, lato, f, bacino_z):
    s = "l" if lato > 0 else "r"
    primo_contatto = 0 if lato > 0 else MEZZO_CICLO
    giri = math.floor((f - primo_contatto) / float(MEZZO_CICLO * 2))
    contatto = primo_contatto + giri * MEZZO_CICLO * 2
    tallone = C.avanza * contatto + bacino_z + C.contatto
    z, y, gradi = caviglia_e_beccheggio(C, f - contatto, tallone)
    apri = -10.0 * lato
    passi = [
        {"ik": {"spalla": "thigh_stretch." + s, "gomito": "leg_stretch." + s, "mano": "foot." + s,
                "bersaglio": [C.larghezza * lato, y, z], "polo": [0.08 * lato, 0, 1]}},
        {"osso": "foot." + s, "come_base": True},
        {"osso": "foot." + s, "asse": [0, 1, 0], "gradi": apri},
    ]
    if gradi:
        passi.append({"osso": "foot." + s, "asse": [1, 0, 0], "gradi": gradi})
    if gradi > 0.0 and f - contatto in (12, 16, 20):
        passi.append({"osso": "toes_01." + s, "come_base": True})
        passi.append({"osso": "toes_01." + s, "asse": [0, 1, 0], "gradi": apri})
    return passi


def busto(giro, rollio):
    """Con l'arma a due mani le spalle controgirano poco: le braccia sono legate."""
    return [
        {"osso": "spine_01.x", "asse": [1, 0, 0], "gradi": 2.0},
        {"osso": "spine_01.x", "asse": [0, 1, 0], "gradi": -giro * 0.5},
        {"osso": "spine_01.x", "asse": [0, 0, 1], "gradi": -rollio * 0.6},
        {"osso": "spine_03.x", "asse": [1, 0, 0], "gradi": 3.0},
        {"osso": "spine_03.x", "asse": [0, 1, 0], "gradi": -giro * 0.6},
        {"osso": "spine_03.x", "asse": [0, 0, 1], "gradi": -rollio * 0.6},
    ]


def braccia(C, m, lato, z):
    """L'arma APPOGGIATA SULLA SPALLA destra, tenuta con due mani (l'utente, 2026-11-10: «le
    mani compenetrano l'asta... dovrebbe portarla con due mani in maniera che sia appoggiata
    sulla spalla»). La destra davanti al petto, l'asta che sale e passa sulla spalla con la
    lama dietro; la sinistra dove la mette il gioco (seconda_mano.gd), piu' giu' verso il
    contrappeso, col suo orientamento; le dita chiuse come in gioco (presa_mano.gd). Sobbalza
    col passo."""
    c = C.c
    giu = {0: 1.0, 4: 1.8, 8: 0.0, 12: -0.4}[m]
    d = c["mano_destra"]
    sp = c["spalla"]
    sm = c["seconda_mano"]
    punto_spalla = [sp[0], sp[1] - giu * 0.5, z + sp[2]]
    mira = {"osso": "hand.r", "mira": {"oggetto": c["arma"], "asse": [0, 1, 0],
                                       "verso_punto": {"punto": punto_spalla, "da": c["presa_destra"]}}}
    rollio = {"osso": "hand.r", "mira": {"oggetto": c["arma"], "asse": [0, 1, 0]},
              "rollio": {"oggetto": c["arma"], "asse": [-1, 0, 0], "verso": c["polso_verso"]}}
    return [
        {"ik": {"spalla": "arm_stretch.r", "gomito": "forearm_stretch.r", "mano": "hand.r",
                "bersaglio": [d[0], d[1] - giu, z + d[2]], "polo": [-1, -1, -0.2]}},
        mira, rollio, mira, mira,
        {"chiudi_mano": {"lato": "r", "chiusura": c["chiusura_destra"], "pollice": c["pollice_destra"]}},
        {"ik": {"spalla": "arm_stretch.l", "gomito": "forearm_stretch.l", "mano": "hand.l",
                "bersaglio_su": {"oggetto": c["arma"], "punto": [sm[9] * 100.0, sm[10] * 100.0 + c["seconda_mano_scorre"],
                                                                 sm[11] * 100.0]},
                "polo": [1, -1, -0.2]}},
        {"osso": "hand.l", "orienta_su": {"oggetto": c["arma"], "base": sm[:9]}},
        {"chiudi_mano": {"lato": "l", "chiusura": c["chiusura_sinistra"], "pollice": c["pollice_sinistra"]}},
    ]


def testa():
    return [
        {"osso": "head.x", "come_base": True},
        {"osso": "head.x", "asse": [1, 0, 0], "gradi": 2.0},
    ]


def posa(C, f):
    m, lato = specchio(f)
    giu = C.bacino_giu[m]
    x = C.bacino_lato[m] * lato
    giro = C.bacino_giro[m] * lato
    rollio = C.bacino_rollio[m] * lato
    z = C.avanza * f
    avanti = 1.0
    passi = [
        {"osso": "c_traj", "sposta": [0, 0, z]},
        {"osso": "root.x", "sposta": [x, -giu, avanti]},
    ]
    if giro:
        passi.append({"osso": "root.x", "asse": [0, 1, 0], "gradi": giro})
    if rollio:
        passi.append({"osso": "root.x", "asse": [0, 0, 1], "gradi": rollio})
    passi += gamba(C, 1.0, f, avanti) + gamba(C, -1.0, f, avanti)
    passi += busto(giro, rollio) + braccia(C, m, lato, z + avanti) + testa()
    return passi


def spec(nome):
    C = Corpo(nome)
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/cammino_due_mani.py (%s): non si modifica a mano." % nome,
        "frames": FRAMES,
        "base": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): posa(C, f) for f in CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1]), uscita, indent=1)
    print("scritto", sys.argv[2], sys.argv[1], len(CHIAVI), "pose")
