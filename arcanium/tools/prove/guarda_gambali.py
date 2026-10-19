# -*- coding: utf-8 -*-
"""Che forma ha davvero il pezzo dei gambali, come esce da Meshy?"""
import bpy, os
from mathutils import Vector

PEZZO = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/assets/characters/armor/gambali_prima_veglia.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=PEZZO)
m = max((o for o in bpy.data.objects if o.type == 'MESH'), key=lambda o: len(o.data.vertices))
for o in list(bpy.data.objects):
    if o is not m:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT'); m.select_set(True)
bpy.context.view_layer.objects.active = m
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.mesh.separate(type='LOOSE')
bpy.ops.object.mode_set(mode='OBJECT')
pezzi = sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
               key=lambda o: len(o.data.vertices), reverse=True)
print("gusci dopo la saldatura:", [len(p.data.vertices) for p in pezzi[:6]])
for p in pezzi[:4]:
    co = [v.co for v in p.data.vertices]
    cx = sum(c.x for c in co) / len(co)
    print("  guscio %5d vert  centro x=%+.4f  z %.3f..%.3f  largh %.3f" %
          (len(co), cx, min(c.z for c in co), max(c.z for c in co),
           max(c.x for c in co) - min(c.x for c in co)))
for p in pezzi[2:]:
    bpy.data.objects.remove(p, do_unlink=True)

mat = bpy.data.materials.new("acc")
mat.diffuse_color = (0.55, 0.58, 0.63, 1)
mat.metallic = 0.9
mat.roughness = 0.3
sx = bpy.data.materials.new("sx")
sx.diffuse_color = (0.85, 0.40, 0.20, 1)
sx.roughness = 0.4
pezzi[0].data.materials.append(mat)
if len(pezzi) > 1:
    pezzi[1].data.materials.append(sx)   # il secondo guscio in arancio: si distingue

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

tutti = [v.co for p in pezzi[:2] for v in p.data.vertices]
centro = sum(tutti, Vector()) / len(tutti)
raggio = max((c - centro).length for c in tutti)

def scatta(off, nome):
    cam.location = centro + Vector(off) * raggio
    d = centro - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = FUORI + nome
    bpy.ops.render.render(write_still=True)
    print("reso:", nome)

scatta((0, -2.6, 0), "gambali_fronte")
scatta((2.2, -1.6, 0.5), "gambali_tre_quarti")
