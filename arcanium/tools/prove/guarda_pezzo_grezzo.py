# -*- coding: utf-8 -*-
"""Che forma ha un pezzo appena uscito dal generatore? Quattro viste, niente altro.

Serve PRIMA di scrivere la riga in `VESTIZIONE`: le quote (`alto`, `basso`), le
ossa e il tipo di pezzo (in rilievo o avvolgente) si decidono guardando, non
leggendo il nome del file.

⚠️ Niente raddrizzamenti e niente ipotesi: il pezzo si mostra com'e', nel suo
orientamento normalizzato, cosi' si vede anche se e' storto o capovolto.

    blender --background --factory-startup --python arcanium/tools/prove/guarda_pezzo_grezzo.py -- <file.glb>
"""
import bpy, sys, os, math, bmesh
from mathutils import Vector

arg = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not arg:
    raise SystemExit(__doc__)
SORGENTE = arg[0]
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/bisezione/"
os.makedirs(FUORI, exist_ok=True)
ETICHETTA = os.path.splitext(os.path.basename(SORGENTE))[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SORGENTE)
m = max((o for o in bpy.data.objects if o.type == 'MESH'), key=lambda o: len(o.data.vertices))
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o is not m:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
m.select_set(True)
bpy.context.view_layer.objects.active = m
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

## quanti gusci, DOPO la saldatura: un pezzo Meshy arriva spezzato sulle cuciture
prima = len(m.data.vertices)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.object.mode_set(mode='OBJECT')
bm = bmesh.new()
bm.from_mesh(m.data)
bm.verts.ensure_lookup_table()
visti, isole = set(), []
for v in bm.verts:
    if v.index in visti:
        continue
    pila, gruppo = [v.index], 0
    visti.add(v.index)
    while pila:
        i = pila.pop()
        gruppo += 1
        for e in bm.verts[i].link_edges:
            k = e.other_vert(bm.verts[i]).index
            if k not in visti:
                visti.add(k)
                pila.append(k)
    isole.append(gruppo)
bordo = sum(1 for e in bm.edges if e.is_boundary)
bm.free()
isole.sort(reverse=True)
co = [v.co for v in m.data.vertices]
mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
print("%s: %d -> %d vertici dopo la saldatura" % (ETICHETTA, prima, len(m.data.vertices)))
print("  gusci: %d (i piu' grossi: %s)" % (len(isole), isole[:6]))
print("  spigoli di bordo: %d  (0 = guscio chiuso)" % bordo)
print("  ingombro: x %.3f  y %.3f  z %.3f" % (mx.x - mn.x, mx.y - mn.y, mx.z - mn.z))
print("  l'asse LUNGO e': %s" % ["x", "y", "z"][max(range(3), key=lambda i: (mx - mn)[i])])

mat = bpy.data.materials.new("acc")
mat.diffuse_color = (0.66, 0.68, 0.72, 1)
mat.metallic = 0.25
mat.roughness = 0.45
m.data.materials.clear()
m.data.materials.append(mat)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.render.resolution_x = 900
sc.render.resolution_y = 900
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.17, 0.19, 1)
sc.world.color = (0.16, 0.17, 0.19)
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.type = 'ORTHO'
centro = (mn + mx) * 0.5
cd.ortho_scale = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) * 1.12

for nome, dire in (("fronte", (0, 1, 0)), ("retro", (0, -1, 0)),
                   ("lato", (-1, 0, 0)), ("alto", (0, 0, -1))):
    d = Vector(dire).normalized()
    cam.location = centro - d * 6.0
    cam.rotation_euler = d.to_track_quat('-Z', 'Y' if abs(d.z) < 0.9 else 'Z').to_euler()
    sc.render.filepath = FUORI + "grezzo_%s_%s" % (ETICHETTA, nome)
    bpy.ops.render.render(write_still=True)
    print("  reso:", nome)
