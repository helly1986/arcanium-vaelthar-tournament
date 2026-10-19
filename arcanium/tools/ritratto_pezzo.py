# -*- coding: utf-8 -*-
"""Il RITRATTO di un pezzo d'armatura: isolato, dritto, quadrato, fondo neutro.

Non e' un render di collaudo — quelli stanno in `prove/`. Questo e' il
**riferimento da dare a un generatore d'immagini** per ricavarne l'illustrazione
d'inventario, e le regole sono diverse:

- **isolato**: niente corpo, niente altri pezzi. Un manichino nel riferimento si
  porta dentro il manichino, e poi va ritagliato a mano.
- **dritto**: i pezzi degli arti nel `.glb` stanno alla loro inclinazione in
  A-pose, cioe' storti. Ogni pezzo si raddrizza sul PROPRIO asse principale e si
  mette accanto all'altro, come nelle illustrazioni gia' in inventario.
- **fondo neutro CHIARO**: su fondo scuro l'acciaio scuro sparisce e il
  generatore non vede la sagoma.
- **quadrato**: e' il formato del pannello.

    blender --background --factory-startup --python arcanium/tools/ritratto_pezzo.py -- \\
        <file.glb> <fuori.png> <NomePezzo> [altroPezzo...]
"""
import bpy, sys, os, math
from mathutils import Vector, Matrix

argomenti = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argomenti) < 3:
    raise SystemExit(__doc__)
SORGENTE, FUORI, NOMI = argomenti[0], argomenti[1], argomenti[2:]

RISOLUZIONE = 1024
FONDO = (0.58, 0.60, 0.63)
DISTANZA = 3.0          # quanto stanno larghi i pezzi, in frazioni della loro larghezza


def asse_principale(punti):
    """La direzione di varianza MASSIMA: per un pezzo d'arto e' il suo asse."""
    centro = sum(punti, Vector()) / len(punti)
    M = [[0.0] * 3 for _ in range(3)]
    for p in punti:
        q = p - centro
        for i in range(3):
            for j in range(3):
                M[i][j] += q[i] * q[j]
    A = Matrix(M).to_3x3()
    v = Vector((0.31, 0.57, 0.76))
    for _ in range(200):
        v = A @ v
        if v.length < 1e-20:
            break
        v.normalize()
    return v, centro


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SORGENTE)
pezzi = [o for o in bpy.data.objects if o.type == 'MESH' and o.name in NOMI]
if not pezzi:
    raise SystemExit("nessun pezzo di nome %s dentro %s" % (NOMI, SORGENTE))
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o not in pezzi:
        bpy.data.objects.remove(o, do_unlink=True)
print("pezzi:", [o.name for o in pezzi])

## ⚠️ I modificatori Armature vanno via PRIMA di raddrizzare: il pezzo e' legato
## a uno scheletro, e ruotando l'oggetto la deformazione lo riporterebbe dov'era.
for o in pezzi:
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    o.parent = None
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

## ogni pezzo si raddrizza sul SUO asse e si mette in fila
pezzi.sort(key=lambda o: sum((o.matrix_world @ v.co).x for v in o.data.vertices))
larghezze = []
for i, o in enumerate(pezzi):
    punti = [o.matrix_world @ v.co for v in o.data.vertices]
    asse, centro = asse_principale(punti)
    if asse.z < 0:
        asse = -asse
    rot = asse.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4()
    for v in o.data.vertices:
        v.co = rot @ (v.co - centro)
    o.data.update()
    co = [v.co for v in o.data.vertices]
    larghezze.append(max(c.x for c in co) - min(c.x for c in co))

passo = max(larghezze) * (DISTANZA / max(1, len(pezzi)))
for i, o in enumerate(pezzi):
    o.location = Vector(((i - (len(pezzi) - 1) * 0.5) * passo, 0.0, 0.0))
bpy.context.view_layer.update()

acciaio = bpy.data.materials.new("acciaio")
## ⚠️ Metallico BASSO, anche se il pezzo e' d'acciaio. Col metallico a 0,95 il
## workbench rende superfici grandi quasi nere e la forma sparisce: al
## generatore serve la SAGOMA e il rilievo, non il cromo. Il metallo glielo si
## chiede a parole nel prompt.
acciaio.diffuse_color = (0.66, 0.68, 0.72, 1)
acciaio.metallic = 0.25
acciaio.roughness = 0.45
for o in pezzi:
    o.data.materials.clear()
    o.data.materials.append(acciaio)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = False
sc.render.resolution_x = RISOLUZIONE
sc.render.resolution_y = RISOLUZIONE
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = FONDO + (1,)
## ⚠️ In Blender 5.2 il workbench prende il fondo da `world.color`, non dal nodo.
sc.world.color = FONDO
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.type = 'ORTHO'

tutti = [o.matrix_world @ v.co for o in pezzi for v in o.data.vertices]
mn = Vector((min(c.x for c in tutti), min(c.y for c in tutti), min(c.z for c in tutti)))
mx = Vector((max(c.x for c in tutti), max(c.y for c in tutti), max(c.z for c in tutti)))
centro = (mn + mx) * 0.5
cd.ortho_scale = max(mx.x - mn.x, mx.z - mn.z) * 1.16
## tre quarti leggero, come le illustrazioni gia' in inventario
d = Vector((0.34, 1.0, -0.16)).normalized()
cam.location = centro - d * 5.0
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
sc.render.filepath = os.path.abspath(FUORI)
bpy.ops.render.render(write_still=True)
print("SCRITTO:", os.path.abspath(FUORI))
