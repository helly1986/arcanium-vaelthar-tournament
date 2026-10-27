# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dell'idle di Kessra (docs/campioni_concept.md): stringe con
due dita un ribattino del giogo vicino al collo, e cade una piccola pioggia di
scintille. «Ancora un giro di vite.» Poi alza il martello davanti a se' e ne
guarda la testa, che si scalda (la Fusione di Vorrkai).

    python arcanium/animazioni/idle_campioni/idle_kessra.py <uscita.json>

Scrive il json che `arcanium/tools/casc_pose_fk.py` applica in Cascadeur sulla
scena di lavorazione senza rig. 181 frame a 30 fps (6 s), in loop: il primo e
l'ultimo frame sono la `Posa` del menu (il Martello da Forgia e' a una mano,
quindi l'idle prende il posto di LightIdle).

Il ribattino e' la borchia alla sua sinistra sul fermaglio del giogo, sotto il
collo: misurato sulla mesh, 137 cm da terra, 4,5 cm a lato del centro, la
piastra 10 cm davanti al petto. Lo stringe la SINISTRA, pollice sotto e indice
sopra: la destra tiene il martello.

Assi del mondo di Cascadeur: +Y in alto, +Z davanti a Kessra, +X la sua
sinistra, in centimetri. La mano sinistra nella Posa: l'asse locale X va
lungo le dita, la Z dal lato del pollice, la Y esce dal dorso.
"""
import json
import math
import sys

FRAMES = 181
## Le chiavi da tenere dopo il rig (casc_estremi_clip.py): le pose e i riposi.
CHIAVI = [0, 18, 32, 40, 48, 54, 66, 82, 98, 112, 126, 142, 158, 168, 180]

RIBATTINO = (4.5, 137.0, 10.5)
## Il polso davanti al petto, da cui le dita arrivano al ribattino: a 19 cm
## il pollice (7,4 cm di catena, attaccato vicino al polso) non ci arrivava.
POLSO = (12.0, 130.0, 18.0)
MARTELLO = "RightHand_martello_da_forgia"


def _meno(a, b):
    return [x - y for x, y in zip(a, b)]


def _norm(v):
    n = math.sqrt(sum(x * x for x in v))
    return [x / n for x in v]


def _croce(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def mano_al_giogo(polso=POLSO, torsione=0.0):
    """Il braccio sinistro porta il polso davanti al petto, le dita puntate al
    ribattino e il pollice in basso. `torsione` gira la mano attorno alle dita
    (il giro di vite, positivo = in senso orario visto da Kessra)."""
    dita = _norm(_meno(RIBATTINO, polso))
    giu = [0.0, -1.0, 0.0]
    pollice = _norm(_meno(giu, [d * sum(x * y for x, y in zip(giu, dita)) for d in dita]))
    if torsione:
        t = math.radians(torsione)
        lato = _croce(dita, pollice)
        pollice = [math.cos(t) * p + math.sin(t) * l for p, l in zip(pollice, lato)]
    return [
        {"ik": {"spalla": "Shoulder_L", "gomito": "Elbow_L", "mano": "Hand_L",
                "bersaglio": list(polso), "polo": [0.6, -1, -0.2]}},
        {"osso": "Hand_L", "mira": {"oggetto": "Hand_L", "asse": [1, 0, 0], "verso": dita},
         "rollio": {"oggetto": "Hand_L", "asse": [0, 0, 1], "verso": pollice}},
    ]


def pizzica(polso=POLSO):
    """Indice sopra e pollice sotto il ribattino: le punte a 1,2 cm dalla
    borchia, le nocche che si piegano verso il palmo."""
    dita = _norm(_meno(RIBATTINO, polso))
    palmo = _norm(_croce([0.0, -1.0, 0.0], dita))
    r = RIBATTINO
    return [
        {"ik": {"spalla": "IndexFinger_01_L", "gomito": "IndexFinger_02_L", "mano": "IndexFinger_04_L",
                "bersaglio": [r[0], r[1] + 1.2, r[2] + 0.8], "polo": palmo}},
        {"ik": {"spalla": "Thumb_01_L", "gomito": "Thumb_02_L", "mano": "Thumb_03_L",
                "bersaglio": [r[0] + 0.8, r[1] - 2.0, r[2] + 1.5], "polo": [-p for p in palmo]}},
    ]


def martello_su(polso, manico, faccia):
    """La destra porta il polso in `polso` (cm), il manico punta verso
    `manico` (la testa del martello sta da quella parte, 48 cm dalla mano) e
    una faccia della testa guarda verso `faccia`. Nel GLB del martello il
    manico e' l'asse Y e la testa sta verso +Y, anche nella scena di
    Cascadeur: guardato su un render di Cascadeur, non sul GLB esportato, che
    perde l'aggancio delle armi (con -Y la testa scendeva verso la sua destra,
    2026-10-27). Le facce stanno sull'asse X."""
    return [
        {"ik": {"spalla": "Shoulder_R", "gomito": "Elbow_R", "mano": "Hand_R",
                "bersaglio": list(polso), "polo": [-0.7, -1, -0.3]}},
        {"osso": "Hand_R", "mira": {"oggetto": MARTELLO, "asse": [0, 1, 0], "verso": manico},
         "rollio": {"asse": [1, 0, 0], "verso": faccia}},
    ]


def braccio_giu(lato="L"):
    """Il braccio torna appeso come nella Posa."""
    return [{"osso": osso + "_" + lato, "come_base": True} for osso in ("Shoulder", "Elbow", "Hand")]


def testa(gira=0.0, china=0.0):
    """Gira (positivo = verso la sua sinistra) e china (positivo = giu')."""
    passi = []
    if gira:
        passi.append({"osso": "Head", "asse": [0, 1, 0], "gradi": gira})
    if china:
        passi.append({"osso": "Neck", "asse": [1, 0, 0], "gradi": china})
    return passi


def spalla_su(gradi):
    return [{"osso": "Clavicle_L", "asse": [0, 0, 1], "gradi": gradi}]


POSE = {
    ## La mano sale verso il giogo.
    18: [{"ik": {"spalla": "Shoulder_L", "gomito": "Elbow_L", "mano": "Hand_L",
                 "bersaglio": [25, 110, 16], "polo": [0.6, -1, -0.4]}}] + testa(4, 6),
    ## Al ribattino, le dita ancora aperte; lo sguardo giu' sulla borchia.
    32: spalla_su(3) + mano_al_giogo() + testa(8, 14),
    ## Lo stringe fra pollice e indice.
    40: spalla_su(4) + mano_al_giogo() + pizzica() + testa(8, 16),
    ## Il giro di vite: il polso gira di 25 gradi.
    48: spalla_su(4) + mano_al_giogo(torsione=25) + pizzica() + testa(7, 16),
    ## Le scintille: la testa si scansa appena, la presa tiene.
    54: spalla_su(3) + mano_al_giogo(torsione=28) + pizzica() + testa(4, 6),
    ## Lascia: la mano si stacca e scende.
    66: spalla_su(1) + mano_al_giogo(polso=(15.0, 127.0, 21.0), torsione=20) + testa(2, 4),
    82: [{"ik": {"spalla": "Shoulder_L", "gomito": "Elbow_L", "mano": "Hand_L",
                 "bersaglio": [25, 106, 12], "polo": [0.6, -1, -0.4]}}] + testa(0, 2),
    ## Di nuovo nella Posa.
    98: braccio_giu("L"),
    ## Il martello sale davanti a lei.
    112: martello_su((-20.0, 106.0, 26.0), [0.4, 0.3, 0.8], [0, 0, -1]) + testa(-4, 8),
    ## Ne guarda la testa, alta davanti a se': a 26 cm dal petto e girato
    ## verso la spalla la testa del martello finiva contro la spallina.
    126: martello_su((-14.0, 115.0, 35.0), [0.55, 0.5, 0.65], [0, 0, -1]) + testa(10, 18),
    ## Lo gira per vedere l'altra faccia.
    142: martello_su((-13.0, 116.0, 35.0), [0.5, 0.55, 0.65], [0, 0.7, -0.7]) + testa(8, 16),
    ## E lo riabbassa.
    158: martello_su((-23.0, 100.0, 14.0), [0.3, -0.1, 0.9], [0, 0, -1]) + testa(2, 4),
    168: braccio_giu("R"),
}


def spec():
    return {
        "_nota": "Generato da arcanium/animazioni/idle_campioni/idle_kessra.py: non si modifica a mano.",
        "frames": FRAMES,
        "chiavi": CHIAVI,
        "pose": {str(f): passi for f, passi in sorted(POSE.items())},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(spec(), f, indent=1)
    print("scritto", sys.argv[1], len(POSE), "pose")
