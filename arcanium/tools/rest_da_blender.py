# -*- coding: utf-8 -*-
"""Scrive il REST di uno scheletro come lo vede BLENDER, per confrontarlo con Godot.

Meta' del cancello `verifica_rest_import.gd`: quello legge il rest DOPO l'import
di Godot, questo lo prende dal `.glb` cosi' com'e'. La differenza fra i due e'
tutto cio' che le impostazioni di retarget hanno riscritto — ed e' esattamente
dove nascono i difetti che sembrano di modellazione e non lo sono (i piedi
all'insu' erano questo).

⚠️ La conversione degli assi: glTF/Godot sono Y-alto, Blender e' Z-alto. Un
punto Blender (x, y, z) diventa Godot **(x, z, -y)**. Sbagliarla fa sembrare che
scarti tutto, e si perde un'ora a cercare un difetto che non c'e'.

    blender --background --factory-startup --python arcanium/tools/rest_da_blender.py -- <file.glb> <fuori.json>
"""
import bpy, sys, os, json

arg = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arg) < 2:
    raise SystemExit(__doc__)
SORGENTE, FUORI = arg[0], arg[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SORGENTE)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mw = rig.matrix_world

fuori = {}
for b in rig.data.bones:
    testa = mw @ b.head_local
    coda = mw @ b.tail_local
    ## in coordinate GODOT: (x, z, -y)
    fuori[b.name] = {
        "testa": [testa.x, testa.z, -testa.y],
        "coda": [coda.x, coda.z, -coda.y],
    }
with open(FUORI, "w", encoding="utf-8") as f:
    json.dump(fuori, f, indent=1)
print("scritte %d ossa in %s" % (len(fuori), FUORI))
