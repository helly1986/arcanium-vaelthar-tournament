# -*- coding: utf-8 -*-
"""Dove sta il DORSO della mano? Tre candidati, misurati e messi a confronto.

`rotation_difference` fissa solo l'asse dell'osso: il rollio resta arbitrario, e
la lamella esce di taglio. Serve una direzione dorsale, e va LETTA, non scritta.

Tre candidati:
  A. l'asse Z locale dell'osso (il rollio che il rig gia' porta con se');
  B. l'asse X locale dell'osso;
  C. la normale del piano della mano, ricavata dalle teste/code delle quattro
     dita, col segno preso dalla carne (il palmo ha le eminenze: il baricentro
     della carne della mano e' spostato VERSO il palmo rispetto all'asse osseo).

Se A o B coincidono con C su tutte le falangi, si usa quello — segue lo splay di
ogni dito invece di imporre una normale unica.

    blender --background --factory-startup --python arcanium/tools/prove/sonda_verso_dorsale.py
"""
import bpy, os
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
LATO = "Left"
DITA = {
    "Thumb":  ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"],
    "Index":  ["IndexProximal", "IndexIntermediate", "IndexDistal"],
    "Middle": ["MiddleProximal", "MiddleIntermediate", "MiddleDistal"],
    "Ring":   ["RingProximal", "RingIntermediate", "RingDistal"],
    "Little": ["LittleProximal", "LittleIntermediate", "LittleDistal"],
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=CORPO)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
corpo = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
R3 = rig.matrix_world.to_3x3()

nomi = [g.name for g in corpo.vertex_groups]
DOM = {}
for v in corpo.data.vertices:
    best, bw = None, 0.0
    for g in v.groups:
        if g.weight > bw:
            bw, best = g.weight, nomi[g.group]
    if best:
        DOM.setdefault(best, []).append(v.index)


def testa_coda(n):
    b = rig.data.bones[n]
    return (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local)


# --- C: il piano della mano dalle quattro dita ------------------------------
punti = []
for d in ("Index", "Middle", "Ring", "Little"):
    for n in DITA[d]:
        t, c = testa_coda(LATO + n)
        punti += [t, c]
centro = sum(punti, Vector()) / len(punti)
## normale = direzione di varianza MINIMA (una mano aperta e' piatta)
M = [[0.0] * 3 for _ in range(3)]
for p in punti:
    q = p - centro
    for i in range(3):
        for j in range(3):
            M[i][j] += q[i] * q[j]
from mathutils import Matrix
val, vec = Matrix(M).to_3x3().jacobi_eigenvalues() if hasattr(Matrix(M), "jacobi_eigenvalues") else (None, None)
if val is None:
    ## niente jacobi in questa versione: potenza inversa a mano su 3x3
    A = Matrix(M).to_3x3()
    tracc = A[0][0] + A[1][1] + A[2][2]
    B = A - Matrix.Scale(tracc * 1.001, 3)     # sposta lo spettro: il minimo diventa dominante
    v = Vector((0.31, 0.57, 0.76))
    for _ in range(200):
        v = (B @ v)
        if v.length < 1e-20:
            break
        v.normalize()
    n_piano = v
else:
    n_piano = vec[val.index(min(val))]
n_piano.normalize()

## segno: il baricentro della CARNE della mano e' spostato verso il PALMO
h_t, h_c = testa_coda(LATO + "Hand")
u_mano = (h_c - h_t).normalized()
carne = [corpo.matrix_world @ corpo.data.vertices[i].co for i in DOM.get(LATO + "Hand", [])]
bar = sum(carne, Vector()) / len(carne)
t = (bar - h_t).dot(u_mano)
scarto = bar - (h_t + u_mano * t)
verso_palmo = 1.0 if scarto.dot(n_piano) > 0 else -1.0
DORSALE = -verso_palmo * n_piano
print("carne della mano: %d vertici | scarto del baricentro dall'asse osseo %.4f m"
      % (len(carne), scarto.length))
print("C  normale del piano della mano (dorsale): (%+.3f, %+.3f, %+.3f)"
      % (DORSALE.x, DORSALE.y, DORSALE.z))
print("   proiezione dello scarto sulla normale: %+.4f m  (se e' piccola, il segno"
      " non e' affidabile)" % scarto.dot(n_piano))

# --- A e B: gli assi locali delle ossa --------------------------------------
print("\n%-24s %22s %22s %8s %8s" % ("osso", "Z locale (mondo)", "X locale (mondo)",
                                     "Z·dors", "X·dors"))
somme = {"Z": 0.0, "X": 0.0}
n_ossa = 0
for dito, ossa in DITA.items():
    for nome in ossa:
        pieno = LATO + nome
        if pieno not in rig.data.bones:
            continue
        b = rig.data.bones[pieno]
        z = (R3 @ b.z_axis).normalized()
        x = (R3 @ b.x_axis).normalized()
        dz, dx = z.dot(DORSALE), x.dot(DORSALE)
        somme["Z"] += dz
        somme["X"] += dx
        n_ossa += 1
        print("  %-22s (%+.2f,%+.2f,%+.2f) (%+.2f,%+.2f,%+.2f) %+8.3f %+8.3f"
              % (pieno, z.x, z.y, z.z, x.x, x.y, x.z, dz, dx))
print("\nmedia dei prodotti scalari:  Z·dorsale %+.3f   X·dorsale %+.3f  (su %d ossa)"
      % (somme["Z"] / n_ossa, somme["X"] / n_ossa, n_ossa))
print("un valore vicino a +1 vuol dire che quell'asse E' il dorso;"
      " vicino a -1 che e' il palmo; vicino a 0 che non c'entra.")
