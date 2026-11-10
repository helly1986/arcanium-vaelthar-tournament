# -*- coding: utf-8 -*-
"""Le due clip di una coppia destra/sinistra sono lo SPECCHIO l'una dell'altra?

    blender -b --factory-startup --python arcanium/tools/controllo_specchio_clip.py -- <sinistra.glb> <destra.glb>

L'utente (2026-11-10): "gli strafe destra/sinistra devono essere identici tra loro ma
speculari, sia lo strafe normale che quello in corsa".

Per ogni frame della prima si prende la seconda allo sfasamento che le accosta meglio (le
due clip possono partire da piedi diversi), la si specchia sul piano di mezzo (X
dell'armatura) scambiando le ossa .l e .r, e si misura di quanto stanno lontane le teste e
le code di ogni osso, dalla radice. Le distanze si danno per gruppo, e devono
tornare a zero tutto, braccia e dita comprese: l'utente le vuole speculari anche con spada e
scudo in mano, perche' non e' detto che il giocatore porti lo scudo.

Scheletro ARP: radice `c_traj`, bacino `root.x`.
"""
import bpy
import sys
from mathutils import Matrix, Vector

A, B = sys.argv[sys.argv.index("--") + 1:][:2]
SX = Matrix.Diagonal((-1.0, 1.0, 1.0))
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS


def carica(percorso):
    prima = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=percorso)
    rig = next(o for o in bpy.data.objects if o not in prima and o.type == 'ARMATURE')
    rig.data.pose_position = 'POSE'
    f0, f1 = (int(round(v)) for v in rig.animation_data.action.frame_range)
    return rig, f0, f1


def gruppo(nome):
    n = nome.lower()
    if n.startswith(("thigh", "leg", "foot", "toes")):
        return "gambe"
    if n.startswith("root"):
        return "bacino"
    if n.startswith(("spine", "neck", "head", "jaw")):
        return "colonna e testa"
    if n.startswith(("shoulder", "arm", "forearm", "hand")):
        return "braccia"
    if n.startswith(("thumb", "index", "middle", "ring", "pinky", "c_thumb", "c_index")):
        return "dita"
    return None


def speculare(nome):
    if nome.endswith(".l"):
        return nome[:-2] + ".r"
    if nome.endswith(".r"):
        return nome[:-2] + ".l"
    return nome


def pose(rig, f0, f1):
    """Per frame: {osso: (testa, coda)} dalla radice, e la radice."""
    ossa = [b.name for b in rig.data.bones if b.use_deform and gruppo(b.name)]
    out, radice = [], []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        r = rig.pose.bones["c_traj"].head.copy()
        radice.append(r)
        out.append({n: (rig.pose.bones[n].head - r, rig.pose.bones[n].tail - r) for n in ossa})
    return out, radice


ra, a0, a1 = carica(A)
rb, b0, b1 = carica(B)
pa, rad_a = pose(ra, a0, a1)
pb, rad_b = pose(rb, b0, b1)
N = a1 - a0
assert b1 - b0 == N, "le due clip hanno durate diverse: %d e %d frame" % (N, b1 - b0)
comuni = [n for n in pa[0] if speculare(n) in pb[0]]


def scarto(i, j):
    """Distanze di ogni osso fra il frame i della prima e lo specchio del frame j della seconda."""
    d = {}
    for n in comuni:
        ta, ca = pa[i][n]
        tb, cb = pb[j][speculare(n)]
        d[n] = max((ta - SX @ tb).length, (ca - SX @ cb).length)
    return d


# Lo sfasamento: quello che accosta meglio le gambe, su tutto il ciclo.
gambe = [n for n in comuni if gruppo(n) == "gambe"]
migliore = min(range(N), key=lambda s: sum(
    scarto(i, (i + s) % N)[n] for i in range(N) for n in gambe))

peggio, somma, dove = {}, {}, {}
for i in range(N):
    d = scarto(i, (i + migliore) % N)
    for n, v in d.items():
        g = gruppo(n)
        somma[g] = somma.get(g, 0.0) + v
        if v > peggio.get(g, -1.0):
            peggio[g], dove[g] = v, "%s al frame %d" % (n, i)
conta = {}
for n in comuni:
    conta[gruppo(n)] = conta.get(gruppo(n), 0) + N

va = (rad_a[-1] - rad_a[0]) / (N / float(FPS))
vb = (rad_b[-1] - rad_b[0]) / (N / float(FPS))
print("SPECCHIO %s <-> %s" % (A.replace("\\", "/").split("/")[-1], B.replace("\\", "/").split("/")[-1]))
print("  %d frame, sfasamento %d; velocita' %s e %s m/s (specchiata: %s)" % (
    N, migliore, tuple(round(v, 2) for v in va), tuple(round(v, 2) for v in vb),
    tuple(round(v, 2) for v in SX @ vb)))
for g in ("gambe", "bacino", "colonna e testa", "braccia", "dita"):
    if g in peggio:
        print("  %-16s media %5.1f cm, peggio %5.1f cm (%s)" % (
            g, somma[g] / conta[g] * 100.0, peggio[g] * 100.0, dove[g]))
