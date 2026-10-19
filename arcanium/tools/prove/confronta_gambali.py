# -*- coding: utf-8 -*-
"""Il set ESPORTATO, gambe di fronte: le alette del ginocchio vanno fuori o dentro?"""
import bpy, os
from mathutils import Vector

SET = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/assets/characters/armor/prima_veglia_set.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SET)
gambali = [o for o in bpy.data.objects if o.type == 'MESH' and "Gambal" in o.name]
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o not in gambali:
        bpy.data.objects.remove(o, do_unlink=True)
print("gambali trovati:", [o.name for o in gambali])

## dove sta il punto piu' ESTERNO all'altezza del ginocchio, per ciascuno
for o in gambali:
    co = [o.matrix_world @ v.co for v in o.data.vertices]
    zs = sorted(c.z for c in co)
    z_gin = zs[0] + (zs[-1] - zs[0]) * 0.46      # circa l'altezza del ginocchio
    vicini = [c for c in co if abs(c.z - z_gin) < 0.03]
    if not vicini:
        continue
    cx = sum(c.x for c in co) / len(co)
    est = max(vicini, key=lambda c: abs(c.x - cx))
    print("  %-16s centro x=%+.4f   punto piu' laterale al ginocchio x=%+.4f  -> sporge %s"
          % (o.name, cx, est.x, "FUORI" if (est.x - cx) * cx > 0 else "DENTRO"))

mat = bpy.data.materials.new("acc")
mat.diffuse_color = (0.58, 0.61, 0.66, 1)
mat.metallic = 0.9
mat.roughness = 0.3
for o in gambali:
    o.data.materials.clear()
    o.data.materials.append(mat)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.render.resolution_x = 1200
sc.render.resolution_y = 1000
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)
cd = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam); sc.camera = cam; cd.lens = 50
tutti = [o.matrix_world @ v.co for o in gambali for v in o.data.vertices]
centro = sum(tutti, Vector()) / len(tutti)
cam.location = centro + Vector((0, -1.5, 0.1))
cam.rotation_euler = (centro - cam.location).to_track_quat('-Z', 'Y').to_euler()
sc.render.filepath = FUORI + "gambali_senza_conforma"
bpy.ops.render.render(write_still=True)
print("reso: gambali_fittati")
