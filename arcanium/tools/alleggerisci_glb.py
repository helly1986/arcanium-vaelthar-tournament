"""Alleggerisce un GLB a un numero di triangoli (Blender, decimazione a collasso).

    blender --background --factory-startup --python arcanium/tools/alleggerisci_glb.py -- <in.glb> <out.glb> <triangoli> [lato_texture]

Per i prop Meshy presi da Arcanium (barili, casse, sacchi, vessilli), nati a
5.000-30.000 triangoli: forme semplici, che il collasso regge. Non per pezzi
fini o a grappolo, che diventano coriandoli (vedi tripo-p2-flusso).
Anche le texture: i Meshy le hanno a 4K (3-5 MB l'una dentro il GLB, e Godot
le estrae una seconda volta). Si riducono a `lato_texture` (1024 di default) e
si riscrivono in JPEG.
Stampa ALLEGGERITO: nome prima -> dopo.
"""

import sys
from pathlib import Path

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, out, voluti = argv[0], argv[1], int(argv[2])
lato = int(argv[3]) if len(argv) > 3 else 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"]


def triangoli():
    t = 0
    for o in mesh:
        o.data.calc_loop_triangles()
        t += len(o.data.loop_triangles)
    return t


prima = triangoli()
if prima > voluti:
    rapporto = voluti / prima
    for o in mesh:
        m = o.modifiers.new("alleggerisci", "DECIMATE")
        m.ratio = rapporto
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
dopo = triangoli()
for img in bpy.data.images:
    w, h = img.size
    if max(w, h) > lato:
        img.scale(max(1, w * lato // max(w, h)), max(1, h * lato // max(w, h)))
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=88)
print("ALLEGGERITO: %s %d -> %d" % (Path(out).stem, prima, dopo))
