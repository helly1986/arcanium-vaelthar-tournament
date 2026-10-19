# -*- coding: utf-8 -*-
"""Chiude la bocca del lupo nella posa di BIND, e prepara i pesi della mandibola.

Perche' in bind e non animando la chiusura in ogni clip: cosi' l'osso `jaw`
nasce a bocca chiusa, tutte e 12 le clip esistenti mostrano la bocca chiusa
gratis, e solo il morso la apre.

SPAZI — in questo file la mesh locale e' Y-up ma il MONDO e' Z-up
(`matrix_world` NON e' l'identita' benche' `rotation_euler` sia (0,0,0)).
Qui si lavora in MONDO: X = asse della cerniera, -Y = avanti (muso), +Z = alto.

La sfumatura: i vertici della mandibola ruotano di w*ANGOLO, con w che vale 1 nel
corpo della mandibola e scende a 0 sulla cucitura verso la guancia (distanza
geodetica sugli spigoli, non in linea d'aria). La STESSA w diventa il peso
dell'osso `jaw`, cosi' mesh e pesi raccontano la stessa cosa e l'osso a riposo
riproduce esattamente la bocca chiusa.

Uso:
  blender -b lupo_moveset.blend --python chiudi_bocca.py -- [--salva] [gradi]
Senza --salva rende soltanto un provino e non tocca il file.
"""
import bpy, sys, math, heapq, os, tempfile
from mathutils import Vector, Matrix

OUT = os.path.join(tempfile.gettempdir(), "arcanium_provini") + os.sep
os.makedirs(OUT, exist_ok=True)
BLEND = ("C:/Users/adriano.pace/Downloads/LOCAL/arcanium/assets/characters/"
         "enemies/anims/_sorgenti/lupo_moveset.blend")

CERNIERA = Vector((0.0, -0.211, 0.214))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SALVA = "--salva" in argv
numeri = [float(a) for a in argv if a.replace(".", "").isdigit()]
ANGOLO = numeri[0] if numeri else 26.0
## metri di cucitura su cui w passa da 0 a 1. Su una mandibola di 5 cm, 10 mm
## sono troppi: il pezzo si PIEGA invece di ruotare.
SFUMATURA = numeri[1] if len(numeri) > 1 else 0.004
print("== chiusura %.1f gradi, sfumatura %.0f mm, salva=%s ==" % (
    ANGOLO, SFUMATURA * 1000, SALVA))

rig = bpy.data.objects["LupoRig"]
mesh = bpy.data.objects["WolfMesh"]
me = mesh.data
M = mesh.matrix_world.copy()
Minv = M.inverted()

# posa AZZERATA esplicitamente: togliere l'action non riporta il rig alla rest
rig.data.pose_position = 'REST'
if rig.animation_data:
    rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_euler = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)
bpy.context.view_layer.update()

gj = mesh.vertex_groups["jaw"].index
setj = {v.index for v in me.vertices if any(g.group == gj for g in v.groups)}
print("mandibola: %d vertici" % len(setj))

# ---- w: distanza geodetica dalla cucitura, dentro la sola mandibola ----
vicini = {i: [] for i in setj}
cucitura = set()
for e in me.edges:
    a, b = e.vertices
    if a in setj and b in setj:
        d = (me.vertices[a].co - me.vertices[b].co).length
        vicini[a].append((b, d))
        vicini[b].append((a, d))
    elif a in setj:
        cucitura.add(a)
    elif b in setj:
        cucitura.add(b)
print("vertici sulla cucitura: %d" % len(cucitura))

dist = {i: float("inf") for i in setj}
coda = []
for i in cucitura:
    dist[i] = 0.0
    heapq.heappush(coda, (0.0, i))
while coda:
    d, i = heapq.heappop(coda)
    if d > dist[i]:
        continue
    for j, w in vicini[i]:
        nd = d + w
        if nd < dist[j]:
            dist[j] = nd
            heapq.heappush(coda, (nd, j))


def liscio(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


W = {i: liscio(dist[i] / SFUMATURA) for i in setj}
pieni = sum(1 for i in setj if W[i] > 0.999)
print("w=1 su %d vertici, sfumati %d" % (pieni, len(setj) - pieni))

# ---- chiusura della mesh in bind ----
for i in setj:
    p = M @ me.vertices[i].co
    R = (Matrix.Translation(CERNIERA)
         @ Matrix.Rotation(math.radians(-ANGOLO * W[i]), 4, 'X')
         @ Matrix.Translation(-CERNIERA))
    me.vertices[i].co = Minv @ (R @ p)
me.update()
bpy.context.view_layer.update()

if SALVA:
    # ---- osso `jaw`, figlio di `head`, IN FONDO alla lista (indici stabili) ----
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    assert "jaw" not in eb, "l'osso jaw esiste gia'"
    padre = eb["head"]
    Ainv = rig.matrix_world.inverted()          # mondo -> armatura
    testa = Ainv @ CERNIERA
    # la coda punta alla PUNTA del mento: presa dai vertici, non dagli assi
    # ossei (su Meshy `headend` guarda il collo, non il muso)
    punta = min((M @ me.vertices[i].co for i in setj), key=lambda c: c.y)
    coda_osso = Ainv @ punta
    b = eb.new("jaw")
    b.head = testa
    b.tail = coda_osso
    b.parent = padre
    b.use_deform = True
    b.use_connect = False
    # il roll conta: la cerniera e' l'asse X del MONDO, e l'osso deve avere il
    # suo X li' sopra, altrimenti ruotare "di X" in posa non apre la bocca.
    A3 = rig.matrix_world.inverted().to_3x3()
    ydir = (coda_osso - testa).normalized()
    xw = (A3 @ Vector((1.0, 0.0, 0.0))).normalized()
    b.align_roll(xw.cross(ydir))
    bpy.ops.object.mode_set(mode='OBJECT')
    print("osso jaw: indice %d su %d, padre %s" % (
        list(rig.data.bones).index(rig.data.bones["jaw"]),
        len(rig.data.bones), rig.data.bones["jaw"].parent.name))

    # ---- pesi: jaw = w, tutto il resto scalato di (1-w) ----
    vg_jaw = mesh.vertex_groups["jaw"]
    ## Leggere i pesi PRIMA e riscriverli dopo: `add(..., 'REPLACE')` rimaneggia
    ## l'elenco dei gruppi del vertice, e continuare a iterarlo mentre lo si
    ## modifica legge valori gia' riscritti.
    da_scrivere = []
    for i in setj:
        vecchi = [(g.group, g.weight) for g in me.vertices[i].groups if g.group != gj]
        da_scrivere.append((i, W[i], vecchi))
    for i, w, vecchi in da_scrivere:
        for gidx, peso in vecchi:
            mesh.vertex_groups[gidx].add([i], peso * (1.0 - w), 'REPLACE')
        vg_jaw.add([i], w, 'REPLACE')
    somma = 0.0
    for i in setj:
        somma += sum(g.weight for g in me.vertices[i].groups)
    print("peso medio totale per vertice della mandibola: %.4f (deve essere 1)"
          % (somma / len(setj)))

    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("SALVATO", BLEND)

# ---- provino ----
## La marcatura rossa serve a capire COSA si muove, ma inganna sul risultato:
## la cavita' interna della bocca e' nel gruppo, si vede in trasparenza dalla
## bocca aperta e sembra geometria che sbuca dalla guancia. Per giudicare la
## silhouette va spenta.
if "--marca" in argv:
    rosso = bpy.data.materials.new("QA_jaw")
    rosso.diffuse_color = (0.85, 0.12, 0.10, 1.0)
    me.materials.append(rosso)
    slot = len(me.materials) - 1
    for poly in me.polygons:
        if all(v in setj for v in poly.vertices):
            poly.material_index = slot

scn = bpy.context.scene
scn.render.engine = 'BLENDER_WORKBENCH'
scn.display.shading.light = 'STUDIO'
scn.display.shading.color_type = 'MATERIAL'
scn.render.resolution_x = 640
scn.render.resolution_y = 512
cd = bpy.data.cameras.new("QA")
cd.type = 'ORTHO'
cam = bpy.data.objects.new("QA", cd)
scn.collection.objects.link(cam)
scn.camera = cam
centro = Vector((0.0, -0.238, 0.202))


def scatta(nome, occhio, larg):
    cd.ortho_scale = larg
    cam.location = centro + occhio
    # 'Y' = asse LOCALE della camera tenuto in alto: giusto in un mondo Z-up
    cam.rotation_euler = (centro - cam.location).normalized().to_track_quat('-Z', 'Y').to_euler()
    scn.render.filepath = OUT + nome
    bpy.ops.render.render(write_still=True)
    print("  reso", nome)


tag = "salvata" if SALVA else ("%02d_s%d" % (ANGOLO, SFUMATURA * 1000))
scatta("chiusa_%s_prof.png" % tag, Vector((0.5, 0, 0)), 0.17)
scatta("chiusa_%s_34.png" % tag, Vector((0.35, 0.20, 0.12)), 0.19)
scatta("chiusa_%s_alto.png" % tag, Vector((0.05, 0.02, 0.5)), 0.17)
print("FINE")
