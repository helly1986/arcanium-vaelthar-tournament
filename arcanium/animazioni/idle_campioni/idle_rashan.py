# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dell'idle di Rashan (docs/campioni_concept.md): non sta mai
fermo. Molleggia sui talloni, fa ruotare le spalle, guarda il sole con un
mezzo sorriso, e ricomincia a molleggiare.

    python arcanium/animazioni/idle_campioni/idle_rashan.py <uscita.json>

Scrive il json che `arcanium/tools/casc_pose_fk.py` applica in Cascadeur sulla
scena di lavorazione senza rig. 181 frame a 30 fps (6 s), in loop: il primo e
l'ultimo frame sono la `Posa` del menu (la Lama Ricurva e' a una mano, quindi
l'idle prende il posto di LightIdle).

Assi del mondo di Cascadeur: +Y in alto, +Z davanti a Rashan, +X la sua
sinistra. Le misure sono in centimetri (bacino a 104, caviglie a 13, la
pianta del piede 16 cm davanti alla caviglia).
"""
import json
import sys

FRAMES = 181
## Le chiavi da tenere dopo il rig (casc_estremi_clip.py): le pose e i riposi.
CHIAVI = [0, 10, 20, 30, 40, 52, 62, 74, 90, 106, 130, 150, 160, 168, 180]


def sui_talloni(gradi, bacino):
    """Sale sulla pianta dei piedi: i talloni si alzano di `gradi` attorno a
    `Ball`, il bacino si sposta di `bacino` cm e le gambe lo inseguono. Con
    gradi 0 e il bacino in giu' e' l'atterraggio: talloni a terra, ginocchia
    morbide. La pianta resta dov'era nella Posa, le dita piatte."""
    passi = [{"osso": "Hips", "sposta": bacino}]
    for lato in "LR":
        ik = {"spalla": "UpperLeg_" + lato, "gomito": "LowerLeg_" + lato, "mano": "Ankle_" + lato,
              "polo": [0, 0, 1]}
        if gradi:
            ik["ruota_attorno"] = {"punto": "Ball_" + lato, "asse": [1, 0, 0], "gradi": gradi}
        passi += [
            {"ik": ik},
            {"osso": "Ankle_" + lato, "mira": {"punto": "Ball_" + lato, "verso_al_posto": "Ball_" + lato}},
            {"osso": "Ball_" + lato, "mira": {"punto": "Toes_" + lato, "verso_al_posto": "Toes_" + lato}},
        ]
    return passi


def su(gradi=12.0):
    """Sulle punte: per 12 gradi la caviglia sale di 3 cm e avanza di 2,3; il
    bacino un po' meno, cosi' le ginocchia non si bloccano tese."""
    return sui_talloni(gradi, [0, 2.6 * gradi / 12.0, 2.0 * gradi / 12.0])


def giu(quanto=1.5):
    """Di nuovo sui talloni, le ginocchia che assorbono."""
    return sui_talloni(0, [0, -quanto, -0.2 * quanto])


def braccia_giu():
    """Le braccia restano appese come nella Posa, e la lama com'era, mentre
    clavicole e petto girano: senza, la spalla che sale porta in fuori la
    mano e la lama cambia verso."""
    return [{"osso": osso + "_" + lato, "come_base": True}
            for lato in "LR" for osso in ("Shoulder", "Elbow", "Hand")]


def spalle(alza, indietro=0.0):
    """Le clavicole: `alza` gradi verso le orecchie, `indietro` gradi all'indietro."""
    passi = []
    for lato, verso in (("L", 1), ("R", -1)):
        passi.append({"osso": "Clavicle_" + lato, "asse": [0, 0, 1], "gradi": verso * alza})
        if indietro:
            passi.append({"osso": "Clavicle_" + lato, "asse": [0, 1, 0], "gradi": verso * indietro})
    return passi + braccia_giu()


def petto(gira=0.0, indietro=0.0):
    """Il petto girato (positivo = verso la sua sinistra) e aperto all'indietro."""
    passi = []
    if gira:
        passi.append({"osso": "Spine_03", "asse": [0, 1, 0], "gradi": gira})
    if indietro:
        passi.append({"osso": "Spine_03", "asse": [1, 0, 0], "gradi": -indietro})
    return passi


def sguardo(gira, alza, piega=0.0):
    """Collo e testa verso il sole: `gira` gradi alla sua sinistra, `alza`
    gradi in su, `piega` gradi di testa inclinata (l'orecchio verso la spalla
    destra), il mezzo sorriso di chi si gode il caldo."""
    passi = [
        {"osso": "Neck", "asse": [0, 1, 0], "gradi": gira * 0.45},
        {"osso": "Neck", "asse": [1, 0, 0], "gradi": -alza * 0.4},
        {"osso": "Head", "asse": [0, 1, 0], "gradi": gira * 0.55},
        {"osso": "Head", "asse": [1, 0, 0], "gradi": -alza * 0.6},
    ]
    if piega:
        passi.append({"osso": "Head", "asse": [0, 0, 1], "gradi": -piega})
    return passi


POSE = {
    ## Due molleggi sui talloni.
    10: su(12),
    20: giu(1.5),
    30: su(10),
    40: giu(1.0),
    ## Le spalle ruotano: su, indietro col petto che si apre, giu' sciolte.
    52: spalle(12),
    62: petto(indietro=3) + spalle(5, 10),
    74: spalle(-2),
    ## Il sole, alto alla sua sinistra.
    90: sguardo(14, 8) + petto(3, 1) + braccia_giu(),
    106: sguardo(26, 22) + petto(5, 3) + braccia_giu(),
    130: sguardo(30, 20, piega=6) + petto(5, 3) + braccia_giu(),
    150: sguardo(6, 3),
    ## E ricomincia.
    160: su(7),
    168: giu(0.8),
}


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/idle_campioni/idle_rashan.py: non si modifica a mano.",
        "frames": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): passi for f, passi in sorted(POSE.items())},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(spec(), f, indent=1)
    print("scritto", sys.argv[1], len(POSE), "pose")
