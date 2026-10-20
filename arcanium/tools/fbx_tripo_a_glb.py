"""Porta un oggetto statico generato con Tripo (FBX, preset Blender) a GLB per Godot.

Per i pezzi d'ambiente, senza scheletro: sassi, muri, colonne. I corpi con il
rig seguono un'altra strada (docs/05 §4-ter).

Cosa fa:
  - importa l'FBX e unisce le mesh in un solo oggetto;
  - applica rotazione e scala, e porta l'origine al centro della base
    (l'arena appoggia i pezzi a terra misurandone l'ingombro);
  - la texture resta quella di Tripo: Godot la estrae accanto al GLB come
    `<glb>_<nome>_basecolor.jpg` (il nome viene dal file scaricato, quindi si
    esporta da Tripo col nome del pezzo);
  - esporta il GLB con la texture dentro, e stampa triangoli e misure.

Uso (Blender in background):
  blender --background --factory-startup --python arcanium/tools/fbx_tripo_a_glb.py -- \
      <sorgente.fbx> <uscita.glb> <nome>
"""

import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
sorgente, uscita, nome = argv[0], argv[1], argv[2]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=sorgente)

mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(o in mesh)
bpy.context.view_layer.objects.active = mesh[0]
if len(mesh) > 1:
    bpy.ops.object.join()
ogg = bpy.context.view_layer.objects.active
ogg.name = nome
ogg.data.name = nome

## Via i genitori vuoti dell'FBX, tenendo la posa nel mondo.
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
for o in list(bpy.context.scene.objects):
    if o is not ogg:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

## Origine al centro della base.
vs = [ogg.matrix_world @ v.co for v in ogg.data.vertices]
minimo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
massimo = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
base = Vector(((minimo.x + massimo.x) / 2, (minimo.y + massimo.y) / 2, minimo.z))
for v in ogg.data.vertices:
    v.co -= base

bpy.ops.export_scene.gltf(
    filepath=uscita,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_animations=False,
    export_yup=True,
)

triangoli = sum(len(p.vertices) - 2 for p in ogg.data.polygons)
dim = massimo - minimo
print("FBX_A_GLB: %s  triangoli %d  misure (x %.2f, y %.2f, z-alto %.2f)" % (
    nome, triangoli, dim.x, dim.y, dim.z))
