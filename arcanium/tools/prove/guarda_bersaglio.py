# -*- coding: utf-8 -*-
"""Che forma ha davvero il BERSAGLIO contro cui si conforma?

`diagnosi_conformazione.py` ha trovato 2.923 spigoli di BORDO nella regione
ritagliata, sparsi da z=0.00 a z=1.23. Un bersaglio bucato spiega tutto: su una
superficie aperta il punto-piu'-vicino cade sul bordo, il segno della normale
diventa arbitrario, e `OUTSIDE_SURFACE` spara i vertici a caso.

Qui si guarda: il corpo intero, e la regione ritagliata, con i bordi in rosso.

    blender --background --factory-startup --python arcanium/tools/prove/guarda_bersaglio.py
"""
import bpy, os, math, bmesh
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/bisezione/"
REGIONE = ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Hips"]

os.makedirs(FUORI, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=CORPO)
corpo = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o is not corpo:
        bpy.data.objects.remove(o, do_unlink=True)
_gruppi = {g.name: g.index for g in corpo.vertex_groups}


def conta_bordo(ob, etichetta):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bordo = [e for e in bm.edges if e.is_boundary]
    nonman = [e for e in bm.edges if not e.is_manifold]
    zs = sorted((ob.matrix_world @ v.co).z for e in bordo for v in e.verts)
    print("%-22s %6d vert %6d facce | bordo %d spigoli | non-manifold %d%s"
          % (etichetta, len(ob.data.vertices), len(ob.data.polygons), len(bordo),
             len(nonman), ("  (bordo z %.3f..%.3f)" % (zs[0], zs[-1])) if zs else ""))
    bm.free()
    return len(bordo)


conta_bordo(corpo, "corpo INTERO")


def attivo(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def _vicini(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    fuori = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    bm.free()
    return fuori


def liscia_campo(valori, vicini, giri=5, forza=0.6):
    v = list(valori)
    for _ in range(giri):
        nuovo = []
        for i, x in enumerate(v):
            vv = vicini[i]
            nuovo.append(x if not vv else
                         x * (1.0 - forza) + (sum(v[j] for j in vv) / len(vv)) * forza)
        v = nuovo
    return v


def taglia_su_campo(ob, campo, soglia=0.5):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    val = {v: campo[v.index] for v in bm.verts}
    incroci = []
    for e in list(bm.edges):
        a_, b_ = e.verts
        if (val[a_] - soglia) * (val[b_] - soglia) < 0.0:
            incroci.append((e, (soglia - val[a_]) / (val[b_] - val[a_])))
    for e, tt in incroci:
        try:
            _, nv = bmesh.utils.edge_split(e, e.verts[0], tt)
            val[nv] = soglia
        except (ValueError, RuntimeError):
            pass
    via = [v for v in bm.verts if val.get(v, 0.0) > soglia + 1e-9]
    bmesh.ops.delete(bm, geom=via, context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


idx = {_gruppi[n] for n in REGIONE if n in _gruppi}
grezzo = [1.0 - min(1.0, sum(g.weight for g in v.groups if g.group in idx))
          for v in corpo.data.vertices]
sotto = sum(1 for x in grezzo if x <= 0.7)
print("campo grezzo: %d vertici su %d sotto soglia 0.7 (cioe' in regione)"
      % (sotto, len(grezzo)))
liscio = liscia_campo(grezzo, _vicini(corpo))
print("campo lisciato: %d sotto soglia" % sum(1 for x in liscio if x <= 0.7))

attivo(corpo)
bpy.ops.object.duplicate()
reg = bpy.context.active_object
reg.name = "Regione"
taglia_su_campo(reg, liscio, 0.7)
conta_bordo(reg, "REGIONE ritagliata")

## i bordi in rosso, il resto grigio: cosi' si vede DOVE sono i buchi
me = reg.data
col = me.color_attributes.new(name="bordi", type='FLOAT_COLOR', domain='POINT')
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
suborodo = {v.index for e in bm.edges if e.is_boundary for v in e.verts}
bm.free()
for i in range(len(me.vertices)):
    col.data[i].color = (0.95, 0.15, 0.10, 1) if i in suborodo else (0.72, 0.74, 0.78, 1)
me.color_attributes.active_color = col

corpo.hide_render = True
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'VERTEX'
sc.display.shading.show_cavity = True
sc.render.resolution_x = 1100
sc.render.resolution_y = 1400
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.type = 'ORTHO'

co = [reg.matrix_world @ v.co for v in reg.data.vertices]
mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
centro = (mn + mx) / 2
cd.ortho_scale = (mx.z - mn.z) * 1.08
for nome, off, rot in (("bersaglio_fronte", (0, -3, 0), (math.radians(90), 0, 0)),
                       ("bersaglio_retro", (0, 3, 0), (math.radians(90), 0, math.radians(180))),
                       ("bersaglio_lato", (3, 0, 0), (math.radians(90), 0, math.radians(90)))):
    cam.location = centro + Vector(off)
    cam.rotation_euler = rot
    sc.render.filepath = FUORI + nome
    bpy.ops.render.render(write_still=True)
    print("reso:", nome)
print("FATTO")
