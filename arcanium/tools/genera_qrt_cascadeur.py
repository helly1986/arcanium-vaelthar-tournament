# -*- coding: utf-8 -*-
"""Genera il template QRT di Cascadeur per il rig canonico di Arcanium.

Cascadeur costruisce il rig da un file `.qrigcasc`: un JSON che associa i nomi
FISSI del suo metarig (`pelvis`, `stomach`, `chest`, `arm_l`, `thigh_r`, ...) ai
giunti della scena, ciascuno con il suo percorso nella gerarchia.

⚠️ Nessuno dei 20 template che Cascadeur porta con se' va bene per noi.
Misurato il 2026-08-20 sui giunti di `protagonista_v4.glb`: il migliore e'
`Mixamo_No_Namespace_Template_New` con 10 nomi su 21, e **`blender_autorig_pro`
fa 0 su 51** — quel file mappa i CONTROLLI di ARP (`c_root_master.x`,
`c_traj`), non le ossa che ARP esporta. Il nostro GLB porta la convenzione
Nephilite (`Hips`, `Spine`, `Chest`, `UpperChest`, `LeftUpperArm`, ...), quindi
il template ce lo facciamo.

Il percorso gerarchico si LEGGE dal GLB invece di scriverlo a mano: se un
giorno il rig cambia (per esempio sparisce `Root`), il template segue senza che
nessuno se ne debba ricordare.

Uso:

    python arcanium/tools/genera_qrt_cascadeur.py corpo.glb uscita.qrigcasc
                                                 [--rig=canonico|pack]

`--rig=pack` e' la convenzione del pack dei nemici, che NON e' quella del
protagonista: vedi il commento sulle due convenzioni qui sotto.
"""
import json
import struct
import sys

# ─── LE DUE CONVENZIONI DI OSSA ─────────────────────────────────────────────
# ⚠️ Arcanium ne ha DUE, e non si somigliano quasi per niente:
#
#   `canonico`  il rig del PROTAGONISTA, convenzione Nephilite-Godot
#               (`Hips`, `Spine`, `Chest`, `LeftUpperArm`, `LeftFoot`, ...)
#   `pack`      il rig del PACK dei nemici, convenzione a NOME DI GIUNTO
#               (`Hips`, `Spine_01/02/03`, `Shoulder_L`, `Elbow_L`, `Ankle_L`)
#
# Misurato il 2026-08-24: il QRT canonico sul rig del pack fa **3 su 21** —
# combaciano solo `Hips`, `Neck` e `Head`. Prendere l'uno per l'altro non da'
# un errore: da' un rig che non nasce, e il messaggio parla di braccia mancanti
# (vedi la skill cascadeur-mcp).
#
# ⚠️⚠️ Nel rig del pack i nomi MENTONO sulla catena, ed e' la trappola classica:
# `Shoulder_L` **non e' la clavicola, e' l'OMERO** (`arm_l`), ed `Elbow_L` non
# e' il gomito ma l'**AVAMBRACCIO** (`forearm_l`) — sono ossa battezzate col
# nome del giunto PROSSIMALE. La clavicola vera si chiama `Clavicle_L`.
# La mappatura qui sotto e' stata ricavata dalla GERARCHIA letta nel GLB, non
# dai nomi: `Clavicle_L -> Shoulder_L -> Elbow_L -> Hand_L`.
#
# Stessa cosa in fondo alla gamba: `Ankle_L` e' il piede (`foot_l`) e il dito
# e' `Ball_L`, che di `Ankle_L` e' figlio; `Toes_L` e' la punta, un livello piu'
# in giu', e nel metarig di Cascadeur non ha un campo.
#
# nome del metarig di Cascadeur -> nome dell'osso nel nostro rig canonico
SEZIONI_CANONICO = [
    ("Body", "Body", [
        ("pelvis", "Hips"),
        ("stomach", "Spine"),
        ("chest", "Chest"),
        ("neck", "Neck"),
        ("head", "Head"),
    ]),
    ("Body", "Left arm", [
        ("clavicle_l", "LeftShoulder"),
        ("arm_l", "LeftUpperArm"),
        ("forearm_l", "LeftLowerArm"),
        ("hand_l", "LeftHand"),
    ]),
    ("Body", "Right arm", [
        ("clavicle_r", "RightShoulder"),
        ("arm_r", "RightUpperArm"),
        ("forearm_r", "RightLowerArm"),
        ("hand_r", "RightHand"),
    ]),
    ("Body", "Left leg", [
        ("thigh_l", "LeftUpperLeg"),
        ("calf_l", "LeftLowerLeg"),
        ("foot_l", "LeftFoot"),
        ("toe_l", "LeftToes"),
    ]),
    ("Body", "Right leg", [
        ("thigh_r", "RightUpperLeg"),
        ("calf_r", "RightLowerLeg"),
        ("foot_r", "RightFoot"),
        ("toe_r", "RightToes"),
    ]),
]

# ⚠️ `Spine_02` resta nella gerarchia e nei percorsi ma non e' un campo del
# metarig, che di vertebre ne ha tre: `chest` e' la vertebra che PORTA LE
# CLAVICOLE, e nel rig del pack quella e' `Spine_03`. Sceglierla per posizione
# nel nome (`Spine_02`, "quella di mezzo") avrebbe messo la rotazione dell'alto
# torace una vertebra piu' in basso.
SEZIONI_PACK = [
    ("Body", "Body", [
        ("pelvis", "Hips"),
        ("stomach", "Spine_01"),
        ("chest", "Spine_03"),
        ("neck", "Neck"),
        ("head", "Head"),
    ]),
    ("Body", "Left arm", [
        ("clavicle_l", "Clavicle_L"),
        ("arm_l", "Shoulder_L"),
        ("forearm_l", "Elbow_L"),
        ("hand_l", "Hand_L"),
    ]),
    ("Body", "Right arm", [
        ("clavicle_r", "Clavicle_R"),
        ("arm_r", "Shoulder_R"),
        ("forearm_r", "Elbow_R"),
        ("hand_r", "Hand_R"),
    ]),
    ("Body", "Left leg", [
        ("thigh_l", "UpperLeg_L"),
        ("calf_l", "LowerLeg_L"),
        ("foot_l", "Ankle_L"),
        ("toe_l", "Ball_L"),
    ]),
    ("Body", "Right leg", [
        ("thigh_r", "UpperLeg_R"),
        ("calf_r", "LowerLeg_R"),
        ("foot_r", "Ankle_R"),
        ("toe_r", "Ball_R"),
    ]),
]

CONVENZIONI = {"canonico": SEZIONI_CANONICO, "pack": SEZIONI_PACK}
# ⚠️ Il rig del pack NON ha ossa di torsione: `TORSIONI` qui sotto vale solo per
# il canonico, e `genera` salta da se' quelle che non trova nel GLB.
# ⚠️ `UpperChest` non ha un campo nel metarig di Cascadeur, che di vertebre ne
# ha tre (pelvis/stomach/chest) e poi passa al collo. Resta nella gerarchia e
# nei percorsi, semplicemente non e' un campo del QRT. Stessa cosa fa il
# template Mixamo con `Spine2`.

# ⚠️⚠️ Le ossa di TORSIONE vanno DICHIARATE, non lasciate in giro. Nel nostro rig
# `LeftUpperArm_twist_01` sta a offset (0,0,0) dal padre — lunghezza zero, stessa
# posizione dell'osso vero. Un twist non dichiarato resta un giunto qualunque e
# il preprocess del biped fallisce con
# `Can't find required nodes: ['arm_r', 'arm_l']`.
# La sezione si chiama "Twist bones" e ogni voce porta anche `Strength` e `Axis`.
# `Strength` = quanto il twist segue il figlio invece del padre: nei template di
# Cascadeur i twist vicini alla spalla e all'anca stanno a 0.0 (seguono il
# padre), quelli dell'avambraccio a 0.8 (seguono la mano, che e' chi torce).
TORSIONI = [
    ("Left arm",  "arm_l",     "LeftUpperArm_twist_01",  0.0),
    ("Left arm",  "forearm_l", "LeftLowerArm_twist_01",  0.8),
    ("Right arm", "arm_r",     "RightUpperArm_twist_01", 0.0),
    ("Right arm", "forearm_r", "RightLowerArm_twist_01", 0.8),
    ("Left leg",  "thigh_l",   "LeftUpperLeg_twist_01",  0.0),
    ("Left leg",  "calf_l",    "LeftLowerLeg_twist_01",  0.0),
    ("Right leg", "thigh_r",   "RightUpperLeg_twist_01", 0.0),
    ("Right leg", "calf_r",    "RightLowerLeg_twist_01", 0.0),
]


def _leggi_glb(percorso):
    with open(percorso, "rb") as f:
        d = f.read()
    off, js = 12, None
    while off < len(d):
        ln, ty = struct.unpack_from("<II", d, off)
        off += 8
        if ty == 0x4E4F534A:
            js = json.loads(d[off:off + ln].decode("utf-8"))
        off += ln
    return js


def genera(corpo, uscita, con_torsioni=False, convenzione="canonico"):
    SEZIONI = CONVENZIONI[convenzione]
    js = _leggi_glb(corpo)
    nomi = [n.get("name") for n in js["nodes"]]
    padre = {}
    for i, n in enumerate(js["nodes"]):
        for c in n.get("children", []):
            padre[c] = i
    indice = {n: i for i, n in enumerate(nomi)}
    giunti = {nomi[j] for j in js["skins"][0]["joints"]}

    def percorso(nome):
        """Antenati dal piu' alto al padre diretto, esclusa l'armatura."""
        catena = []
        i = padre.get(indice[nome])
        while i is not None and nomi[i] in giunti:
            catena.append(nomi[i])
            i = padre.get(i)
        return list(reversed(catena))

    mancanti = [osso for _, _, coppie in SEZIONI for _, osso in coppie
                if osso not in giunti]
    if mancanti:
        raise SystemExit("ossa assenti in %s: %s" % (corpo, mancanti))

    sezioni = []
    for _, nome_sez, coppie in SEZIONI:
        sezioni.append({
            "Section": nome_sez,
            "Names": [
                {"Bone name": meta, "Joint name": osso, "Joint path": percorso(osso)}
                for meta, osso in coppie
            ],
        })
    documenti = [{"Title": "Body", "Sections": sezioni}]

    torsioni = [t for t in TORSIONI if t[2] in giunti] if con_torsioni else []
    saltate = [t[2] for t in TORSIONI if t[2] not in giunti]
    if torsioni:
        documenti.append({
            "Title": "Twist bones",
            "Sections": [
                {"Section": sezione,
                 "Names": [{"Bone name": padre_meta,
                            "Joint name": osso,
                            "Joint path": percorso(osso),
                            "Strength": forza,
                            "Axis": 0}]}
                for sezione, padre_meta, osso, forza in torsioni
            ],
        })
    # ⚠⚠ Il blocco `Settings` NON e' decorazione: il template estratto dal
    # `qrt_json` di un personaggio gia' riggato ce l'ha, e un template senza
    # non produce niente. Corrisponde a `QrtData.is_align_pelvis` e
    # `is_create_layers`, che in un QrtData appena costruito sono entrambi
    # `False`.
    documento = {"Document": documenti,
                 "Settings": {"Is align pelvis": True, "Is create layers": True}}

    with open(uscita, "w", encoding="utf-8") as f:
        json.dump(documento, f, indent=4, ensure_ascii=False)
    n = sum(len(s["Names"]) for s in sezioni)
    print("scritto %s: %d campi del metarig, %d torsioni" % (uscita, n, len(torsioni)))
    for s in sezioni:
        for v in s["Names"]:
            print("   %-12s -> %-16s %s" % (v["Bone name"], v["Joint name"],
                                            "/".join(v["Joint path"]) or "(radice)"))
    for sezione, padre_meta, osso, forza in torsioni:
        print("   torsione di %-10s -> %-24s forza %.1f" % (padre_meta, osso, forza))
    if saltate:
        print("   torsioni assenti dal rig, saltate:", saltate)


if __name__ == "__main__":
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(argv) != 2:
        raise SystemExit(__doc__)
    conv = "canonico"
    for a in sys.argv[1:]:
        if a.startswith("--rig="):
            conv = a.split("=", 1)[1]
    if conv not in CONVENZIONI:
        raise SystemExit("--rig deve essere uno di: %s" % ", ".join(CONVENZIONI))
    genera(argv[0], argv[1], con_torsioni="--con-torsioni" in sys.argv,
           convenzione=conv)
