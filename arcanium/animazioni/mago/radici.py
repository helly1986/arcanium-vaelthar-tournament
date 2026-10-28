# -*- coding: utf-8 -*-
"""Le POSE CHIAVE delle RADICI DELLA VOCE, l'incantesimo del Mago Sylvorn
(richiesta dell'utente del 2026-10-28): raccoglie davanti al petto, si china e
affonda le mani verso il suolo, e le radici rispondono.

Prende il posto di `sword_cast_01` per il Mago: in quella clip, condivisa col
boss e l'arciere, nella carica le mani andavano fino a 31 cm dietro il busto e
bucavano il manto. Qui le braccia restano sempre davanti al corpo.

    python arcanium/animazioni/mago/radici.py <uscita.json>

Scrive il json che `arcanium/tools/casc_pose_fk.py` applica in Cascadeur sulla
scena senza rig fatta con `base_cascadeur.py ... sword_idle_01.glb ... tieni=91`:
91 frame a 30 fps (3 s), primo e ultimo nella posa d'idle. Il CONTATTO col
suolo e' al frame 59 (1,97 s): e' il `telegraph` della mossa nel moveset.

Assi di Cascadeur: +Y in alto, +Z davanti al Mago, +X la sua sinistra, cm.
Nell'idle: bacino 105,7; spalle 143; mani al fianco a 97-100; caviglie a
x +-30, la destra 11 cm indietro.
"""
import json
import sys

FRAMES = 91
CHIAVI = [0, 16, 30, 42, 52, 59, 68, 78, 90]


def bacino(giu):
    """Il bacino si abbassa di `giu` cm e i piedi restano dove sono."""
    passi = [{"osso": "Hips", "sposta": [0, -giu, 0]}]
    ## Le ginocchia in fuori: le mani scendono fra le due, fino a terra.
    for lato, polo in (("L", [1.0, 0, 0.6]), ("R", [-1.0, 0, 0.6])):
        passi.append({"ik": {"spalla": "UpperLeg_" + lato, "gomito": "LowerLeg_" + lato,
                             "mano": "Ankle_" + lato, "polo": polo}})
    return passi


def schiena(s1=0.0, s2=0.0, s3=0.0):
    """Le tre vertebre in avanti (positivo) o indietro, gradi."""
    return [{"osso": o, "asse": [1, 0, 0], "gradi": g}
            for o, g in (("Spine_01", s1), ("Spine_02", s2), ("Spine_03", s3)) if g]


def testa(china=0.0, collo=0.0):
    passi = []
    if collo:
        passi.append({"osso": "Neck", "asse": [1, 0, 0], "gradi": collo})
    if china:
        passi.append({"osso": "Head", "asse": [1, 0, 0], "gradi": china})
    return passi


def mani(x, y, z, dita=None, gomiti=(1.0, -1.0, -0.2)):
    """Le due mani in (+-x, y, z), il gomito verso `gomiti` (sinistra; la
    destra specchiata), le dita puntate verso `dita`."""
    passi = []
    for lato, s in (("L", 1.0), ("R", -1.0)):
        passi.append({"ik": {"spalla": "Shoulder_" + lato, "gomito": "Elbow_" + lato, "mano": "Hand_" + lato,
                             "bersaglio": [s * x, y, z], "polo": [s * gomiti[0], gomiti[1], gomiti[2]]}})
        if dita is not None:
            passi.append({"osso": "Hand_" + lato, "mira": {"punto": "Finger_01_" + lato,
                                                          "verso": [s * dita[0], dita[1], dita[2]]}})
    return passi


POSE = {
    ## Raccoglie: le mani salgono e si avvicinano davanti al petto, a coppa.
    16: schiena(0, 2, 2) + mani(9, 120, 30, dita=(-1, 0.4, 0.3)) + testa(12),
    ## Stringe: le mani quasi si toccano, il busto si raccoglie, lo sguardo sulle mani.
    30: schiena(0, 5, 6) + mani(5, 124, 28, dita=(-1, 0.6, 0.2), gomiti=(1, -0.8, -0.5)) + testa(16),
    ## Lo slancio: si alza un poco, le mani salgono al mento, il petto si apre.
    42: bacino(-3) + schiena(-4, -6, -6) + mani(8, 142, 26, dita=(-0.3, 1, 0.2), gomiti=(1, -0.6, -0.4)) + testa(-8),
    ## Cala: si piega, le mani scendono davanti al ventre, dita in giu'.
    52: bacino(26) + schiena(26, 16, 10) + mani(15, 70, 50, dita=(0, -1, 0.4)) + testa(-10, -4),
    ## IL CONTATTO: accovacciato, le dita affondano nel suolo davanti a se'.
    59: bacino(52) + schiena(34, 22, 14) + mani(15, 4, 50, dita=(0.1, -0.8, 0.6), gomiti=(1, 0.2, -0.3)) + testa(-26, -12),
    ## Tiene premuto: le radici rispondono.
    68: bacino(54) + schiena(36, 22, 14) + mani(16, 2, 52, dita=(0.15, -0.85, 0.55), gomiti=(1, 0.2, -0.3)) + testa(-28, -12),
    ## Si rialza, le mani tornano lungo le gambe.
    78: bacino(18) + schiena(14, 8, 4) + mani(26, 68, 28, dita=(0.2, -1, 0.2)) + testa(-6),
}


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/mago/radici.py: non si modifica a mano.",
        "frames": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): passi for f, passi in sorted(POSE.items())},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(spec(), f, indent=1)
    print("scritto", sys.argv[1], len(POSE), "pose")
