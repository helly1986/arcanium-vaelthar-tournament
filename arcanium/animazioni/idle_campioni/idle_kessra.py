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
## Il polso di lato, all'altezza del giogo, col gomito alzato verso fuori:
## l'avambraccio va di traverso sul petto e la mano lo continua, quasi dritta.
## Col gomito basso e il polso davanti al petto (12, 130, 18) la mano doveva
## piegarsi di 90 gradi per riportare le dita indietro sulla borchia, e ogni
## uscita da quella posa (un fendente, una schivata, il primo passo) la
## raddrizzava in un decimo di secondo: 26-28 gradi di strappo per fotogramma
## (misura_uscita_idle.gd, 2026-10-27). Con l'avambraccio lungo 22,5 cm e il
## braccio 25,9, a polso dritto il gomito sta solo in fuori, quasi all'altezza
## della spalla: il gesto di chi si aggiusta una fibbia sotto il colletto.
POLSO = (14.5, 135.0, 14.0)
## Verso cui va il gomito.
GOMITO = [1.0, 0.2, -0.3]
MARTELLO = "RightHand_martello_da_forgia"


def _meno(a, b):
    return [x - y for x, y in zip(a, b)]


def _norm(v):
    n = math.sqrt(sum(x * x for x in v))
    return [x / n for x in v]


def _croce(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def mano_al_giogo(polso=POLSO, torsione=0.0, mira=RIBATTINO):
    """Il braccio sinistro porta il polso di lato al giogo e le dita puntano
    al ribattino. La mano NON si gira per mettere il pollice in un verso
    scelto: si punta con la rotazione piu' corta, e resta girata come
    l'avambraccio. Imporre il pollice in alto la lasciava a 97 gradi dalla Posa
    anche col polso piegato di soli 44: era la torsione sull'avambraccio, ed e'
    quella che ogni uscita deve disfare di colpo. `torsione` gira la mano
    attorno alle dita (il giro di vite, positivo = in senso orario visto da
    Kessra). `mira` e' dove puntano le dita: davanti alla borchia finche' la
    mano e' aperta, o l'indice dritto entra nella piastra."""
    dita = _norm(_meno(mira, polso))
    passi = [
        {"ik": {"spalla": "Shoulder_L", "gomito": "Elbow_L", "mano": "Hand_L",
                "bersaglio": list(polso), "polo": GOMITO}},
        {"osso": "Hand_L", "mira": {"oggetto": "Hand_L", "asse": [1, 0, 0], "verso": dita}},
    ]
    if torsione:
        passi.append({"osso": "Hand_L", "asse": [1, 0, 0], "gradi": -torsione})
    return passi


def pizzica(polso=POLSO):
    """Pollice sopra e indice sotto il ribattino (la mano ha il pollice in
    alto): le punte a 1,2 cm dalla borchia, le nocche che si piegano verso il
    palmo, che guarda il petto."""
    dita = _norm(_meno(RIBATTINO, polso))
    palmo = _norm(_croce([0.0, -1.0, 0.0], dita))
    r = RIBATTINO
    return [
        {"ik": {"spalla": "IndexFinger_01_L", "gomito": "IndexFinger_02_L", "mano": "IndexFinger_04_L",
                "bersaglio": [r[0], r[1] - 1.2, r[2] + 0.8], "polo": palmo}},
        {"ik": {"spalla": "Thumb_01_L", "gomito": "Thumb_02_L", "mano": "Thumb_03_L",
                "bersaglio": [r[0] + 0.8, r[1] + 1.5, r[2] + 1.5], "polo": [-p for p in palmo]}},
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
    ## La mano sale verso il giogo, il gomito comincia ad aprirsi.
    18: [{"ik": {"spalla": "Shoulder_L", "gomito": "Elbow_L", "mano": "Hand_L",
                 "bersaglio": [27, 118, 14], "polo": [1.0, -0.6, -0.3]}}] + testa(4, 6),
    ## Al ribattino, le dita ancora aperte; lo sguardo giu' sulla borchia.
    32: spalla_su(3) + mano_al_giogo(polso=(16.0, 134.0, 18.0), mira=(4.5, 137.0, 18.0)) + testa(8, 14),
    ## Lo stringe fra pollice e indice.
    40: spalla_su(4) + mano_al_giogo() + pizzica() + testa(8, 16),
    ## Il giro di vite: il polso gira di 25 gradi.
    48: spalla_su(4) + mano_al_giogo(torsione=25) + pizzica() + testa(7, 16),
    ## Le scintille: la testa si scansa appena, la presa tiene.
    54: spalla_su(3) + mano_al_giogo(torsione=28) + pizzica() + testa(4, 6),
    ## Lascia: la mano si stacca e scende.
    ## La mano lascia e torna nel verso dell'avambraccio: puntata ancora
    ## alla borchia da qui si piegava di 74 gradi.
    66: spalla_su(1) + [{"ik": {"spalla": "Shoulder_L", "gomito": "Elbow_L", "mano": "Hand_L",
                                "bersaglio": [19, 130, 16], "polo": GOMITO}},
                         ## Un passo nullo: rimette la mano come nella Posa
                         ## (si riparte dalla base solo per le ossa toccate).
                         {"osso": "Hand_L", "asse": [1, 0, 0], "gradi": 0}] + testa(2, 4),
    82: [{"ik": {"spalla": "Shoulder_L", "gomito": "Elbow_L", "mano": "Hand_L",
                 "bersaglio": [27, 110, 12], "polo": [1.0, -0.8, -0.3]}}] + testa(0, 2),
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
