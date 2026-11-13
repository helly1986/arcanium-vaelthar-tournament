"""L'AMPOLLA DI LIQUIDO INFIAMMABILE (il primo oggetto da lancio, 2026-11-12): dall'FBX di
Tripo P2 al GLB per Godot.

    blender -b --factory-startup --python arcanium/tools/prepara_ampolla.py

- l'ispezione di tutta la mesh (ispeziona_topologia di monta_campione.py: buchi, spigoli
  non-manifold, farfalle, volanti, degeneri, normali) prima e dopo le saldature di rito
  (controlla_e_ripara), come per ogni mesh generata (collaudo-mesh-e-pesi);
- la misura: alta `ALTEZZA` m, come un'ampolla da lanciare che sta in un pugno;
- l'origine al COLLO, dove la mano la stringe per lanciarla; in piedi lungo +Y in Godot;
- triangolata (in Godot si esce in GLB), immagine rinominata `base_color` (tripo-p2-flusso);
- un render di controllo da quattro lati in assets/items/ampolla_infiammabile/sorgenti/.
"""
import glob
import math
import os
import bpy
import bmesh
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CARTELLA = RADICE + "assets/items/ampolla_infiammabile/"
ALTEZZA = 0.20  # m
## Dove sta il collo, in frazione dell'altezza dal fondo (la mano lo stringe).
COLLO = 0.72

_ns = {"__name__": "prepara_ampolla"}
exec(compile(open(RADICE + "arcanium/tools/monta_campione.py", encoding="utf-8").read(), "monta_campione", "exec"), _ns)

bpy.ops.wm.read_factory_settings(use_empty=True)
fbx = glob.glob(CARTELLA + "sorgenti/*.fbx")[0]
bpy.ops.import_scene.fbx(filepath=fbx)
mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in mesh:
    o.select_set(True)
bpy.context.view_layer.objects.active = mesh[0]
if len(mesh) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
ob.name = ob.data.name = "Ampolla"
for o in list(bpy.context.scene.objects):
    if o != ob:
        bpy.data.objects.remove(o, do_unlink=True)
ob.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

print("=== PRIMA")
_ns["ispeziona_topologia"](ob.name)
_ns["controlla_e_ripara"](ob.name)
print("=== DOPO")
_ns["ispeziona_topologia"](ob.name)

## In piedi lungo Z in Blender (+Y in Godot): l'asse piu' lungo.
co = [v.co for v in ob.data.vertices]
lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
dim = hi - lo
print("ingombro FBX", tuple(round(x, 3) for x in dim))
k = ALTEZZA / dim.z
centro = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z + dim.z * COLLO))
for v in ob.data.vertices:
    v.co = (v.co - centro) * k
ob.data.update()

bm = bmesh.new()
bm.from_mesh(ob.data)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(ob.data)
bm.free()
## Impacchettata e rinominata: un'immagine ancora legata al file dell'FBX esce col nome di
## Tripo, e Godot la estrae come `<glb>_tripo_image_<uuid>.jpg`.
for img in bpy.data.images:
    if img.source == "FILE":
        img.pack()
        img.name = "base_color"
        img.filepath_raw = "base_color.jpg"
print("triangoli", len(ob.data.polygons), "ingombro m", tuple(round(x * k, 3) for x in dim))

bpy.ops.export_scene.gltf(filepath=CARTELLA + "ampolla_infiammabile.glb", export_format="GLB", use_selection=False,
                          export_yup=True, export_apply=True)

## Il render di controllo.
scena = bpy.context.scene
scena.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
scena.render.resolution_x, scena.render.resolution_y = 600, 600
scena.world = bpy.data.worlds.new("mondo")
scena.world.color = (0.18, 0.18, 0.2)
luce = bpy.data.objects.new("luce", bpy.data.lights.new("luce", "SUN"))
luce.data.energy = 4.0
luce.rotation_euler = (math.radians(50), 0, math.radians(30))
scena.collection.objects.link(luce)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scena.collection.objects.link(cam)
scena.camera = cam
bersaglio = Vector((0, 0, -ALTEZZA * (COLLO - 0.5)))
for nome, ang in (("davanti", 0), ("lato", 90), ("dietro", 180), ("tre_quarti", 45)):
    a = math.radians(ang)
    cam.location = bersaglio + Vector((math.sin(a) * 0.6, -math.cos(a) * 0.6, 0.12))
    cam.rotation_euler = (bersaglio - cam.location).to_track_quat("-Z", "Y").to_euler()
    scena.render.filepath = CARTELLA + "sorgenti/render_%s.png" % nome
    bpy.ops.render.render(write_still=True)
print("FATTO")
