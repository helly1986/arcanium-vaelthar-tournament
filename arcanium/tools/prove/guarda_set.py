# -*- coding: utf-8 -*-
"""Il set esportato, indossato: figura intera piu' i tre punti che rompono.

Le piastre in acciaio, la pelle in carne: cosi' si vede subito se il corpo
sbuca, e le schegge sull'acciaio scuro non si nascondono.

    blender --background --factory-startup --python arcanium/tools/prove/guarda_set.py
"""
import bpy, os, sys, math
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
SET = RADICE + "assets/characters/armor/prima_veglia_set.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/bisezione/"
os.makedirs(FUORI, exist_ok=True)

## `-- <altro_set.glb> <prefisso>` per confrontare due versioni nella STESSA
## inquadratura: e' l'unico confronto che vale qualcosa.
PREFISSO = "set_"
if "--" in sys.argv:
    _a = sys.argv[sys.argv.index("--") + 1:]
    if len(_a) > 0:
        SET = _a[0].replace("\\", "/")
    if len(_a) > 1:
        PREFISSO = _a[1]
print("set:", SET, "| prefisso:", PREFISSO)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=CORPO)
corpo = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o is not corpo:
        bpy.data.objects.remove(o, do_unlink=True)
prima = set(bpy.data.objects.keys())
bpy.ops.import_scene.gltf(filepath=SET)
## ⚠️ L'importatore glTF di Blender 5.2 crea un `Icosphere` di 42 vertici come
## forma delle ossa: NON e' nell'asset (controllato nel json del GLB) ma se
## finisce nel conto rovina l'inquadratura, perche' sta all'origine con raggio 1.
piastre = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - prima
           if bpy.data.objects[n].type == 'MESH'
           and bpy.data.objects[n].name.startswith("PV_")]
for n in set(bpy.data.objects.keys()) - prima:
    o = bpy.data.objects[n]
    if o.type == 'MESH' and o not in piastre:
        bpy.data.objects.remove(o, do_unlink=True)
print("piastre:", sorted((o.name, len(o.data.vertices)) for o in piastre))

pelle = bpy.data.materials.new("pelle")
pelle.diffuse_color = (0.72, 0.55, 0.47, 1)
pelle.roughness = 0.9
acciaio = bpy.data.materials.new("acciaio")
acciaio.diffuse_color = (0.58, 0.61, 0.66, 1)
acciaio.metallic = 0.9
acciaio.roughness = 0.3
corpo.data.materials.clear()
corpo.data.materials.append(pelle)
for o in piastre:
    o.data.materials.clear()
    o.data.materials.append(acciaio)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.type = 'ORTHO'


def scatta(nome, mira, altezza_inquadratura, direzione, risoluzione=(900, 1400)):
    sc.render.resolution_x, sc.render.resolution_y = risoluzione
    cd.ortho_scale = altezza_inquadratura * max(1.0, risoluzione[0] / risoluzione[1])
    d = Vector(direzione).normalized()
    cam.location = mira - d * 4.0
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = FUORI + nome
    bpy.ops.render.render(write_still=True)
    print("reso:", nome)


tutti = [o.matrix_world @ v.co for o in [corpo] + piastre for v in o.data.vertices]
mn = Vector((min(c.x for c in tutti), min(c.y for c in tutti), min(c.z for c in tutti)))
mx = Vector((max(c.x for c in tutti), max(c.y for c in tutti), max(c.z for c in tutti)))
centro = (mn + mx) / 2
alt = mx.z - mn.z
print("figura: z %.3f..%.3f" % (mn.z, mx.z))

scatta(PREFISSO + "intero_fronte", centro, alt * 1.05, (0, 1, 0))
scatta(PREFISSO + "intero_retro", centro, alt * 1.05, (0, -1, 0))
scatta(PREFISSO + "intero_tre_quarti", centro, alt * 1.05, (-0.8, 1, 0))
## i tre punti dove si rompeva
scatta(PREFISSO + "ginocchia", Vector((0, centro.y, mn.z + alt * 0.32)), alt * 0.32,
       (0, 1, 0), (1200, 1000))
scatta(PREFISSO + "cosce", Vector((0, centro.y, mn.z + alt * 0.50)), alt * 0.26,
       (0, 1, 0), (1200, 1000))
scatta(PREFISSO + "braccio", Vector((0.30, centro.y, mn.z + alt * 0.62)), alt * 0.34,
       (0, 1, 0), (1000, 1200))
print("FATTO")
