# -*- coding: utf-8 -*-
"""Il FONDO della fascia di aderenza: fin dove ha senso tirare fuori un vertice.

Con `wrap_mode='OUTSIDE'` la fascia del ginocchio e il calzare tornano interi,
ma il TOP del cosciale resta a schegge. La misura dice perche': li' il pezzo e'
sepolto fino a **12 cm** dentro il bacino, e la regola di oggi dice `d < stacco
-> peso 1` senza fondo — quindi un vertice a -0,12 vale 1 e viene catapultato
fuori di 13 cm. Non e' "la parete interna che si appoggia alla pelle": e' una
parte del pezzo che sta semplicemente DENTRO il corpo.

Una piastra sepolta e' invisibile. Una piastra catapultata e' una scheggia
visibile. Quindi il peso 1 vale solo in una FASCIA attorno alla superficie:
da -`affondo` a +`stacco`, e sfuma da tutte e due le parti.

    blender --background --factory-startup --python arcanium/tools/prove/prova_fondo_aderenza.py
"""
import bpy, os, math, bmesh
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
PEZZO = RADICE + "assets/characters/armor/gambali_prima_veglia.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/bisezione/"

CFG = dict(alto=1.06, basso=-0.01, centro_y=0.00, gonfia=1.12, cinghia=1.02,
           centra_su="UpperLeg", regione=["UpperLeg", "LowerLeg", "Foot", "Hips"],
           conforma=(0.010, 0.024))
SALDATURA = 0.0001
ANGOLO_SPIGOLO = math.radians(35)
LATO = "Left"
## None = la regola di oggi, senza fondo
AFFONDI = [None, 0.060, 0.035, 0.018]

os.makedirs(FUORI, exist_ok=True)


def attivo(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def bbox(o):
    co = [o.matrix_world @ v.co for v in o.data.vertices]
    return (Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co))),
            Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co))))


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
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if val.get(v, 0.0) > soglia + 1e-9],
                     context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=CORPO)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
corpo = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o is not corpo:
        bpy.data.objects.remove(o, do_unlink=True)
corpo.hide_render = True
rig.hide_render = True
attivo(corpo)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=SALDATURA)
bpy.ops.object.mode_set(mode='OBJECT')

gruppi = {g.name: g.index for g in corpo.vertex_groups}
ossa = [(LATO + n) if (LATO + n) in gruppi else n for n in CFG["regione"]]
idx = {gruppi[n] for n in ossa if n in gruppi}
grezzo = [1.0 - min(1.0, sum(g.weight for g in v.groups if g.group in idx))
          for v in corpo.data.vertices]
liscio = liscia_campo(grezzo, _vicini(corpo))
attivo(corpo)
bpy.ops.object.duplicate()
REG = bpy.context.active_object
REG.name = "Regione"
taglia_su_campo(REG, liscio, 0.7)
REG.hide_render = True
print("regione: %d vertici" % len(REG.data.vertices))

prima = set(bpy.data.objects.keys())
bpy.ops.import_scene.gltf(filepath=PEZZO)
nuovi = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - prima]
m = max((o for o in nuovi if o.type == 'MESH'), key=lambda o: len(o.data.vertices))
for o in nuovi:
    if o is not m:
        bpy.data.objects.remove(o, do_unlink=True)
attivo(m)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=SALDATURA)
bpy.ops.object.mode_set(mode='OBJECT')
if m.data.has_custom_normals:
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
try:
    bpy.ops.object.shade_auto_smooth(angle=ANGOLO_SPIGOLO)
except (AttributeError, RuntimeError):
    for p in m.data.polygons:
        p.use_smooth = True
attivo(m)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='LOOSE')
bpy.ops.object.mode_set(mode='OBJECT')
tutti = sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
               key=lambda o: len(o.data.vertices), reverse=True)
base = next(t for t in tutti if (bbox(t)[0].x + bbox(t)[1].x) / 2 > 0)
for o in tutti:
    if o is not base:
        bpy.data.objects.remove(o, do_unlink=True)
base.name = "F_gonfiato"
mn, mx = bbox(base)
scala = (CFG["alto"] - CFG["basso"]) / (mx.z - mn.z)
base.scale = (scala * CFG["cinghia"], scala * CFG["cinghia"], scala)
bpy.context.view_layer.update()
mn, mx = bbox(base)
asse = rig.matrix_world @ rig.data.bones[LATO + CFG["centra_su"]].head_local
base.location += Vector((asse.x - (mn.x + mx.x) / 2,
                         CFG["centro_y"] - (mn.y + mx.y) / 2,
                         (CFG["alto"] + CFG["basso"]) / 2 - (mn.z + mx.z) / 2))
bpy.context.view_layer.update()
mn, mx = bbox(base)
fermo = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
base.scale = base.scale * CFG["gonfia"]
bpy.context.view_layer.update()
mn2, mx2 = bbox(base)
base.location += fermo - Vector(((mn2.x + mx2.x) / 2, (mn2.y + mx2.y) / 2, mn2.z))
bpy.context.view_layer.update()
attivo(base)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
base.hide_render = True

stacco, fascia = CFG["conforma"]
inv = REG.matrix_world.inverted()
distanza = []
for v in base.data.vertices:
    p = base.matrix_world @ v.co
    ok, loc, nor, _ = REG.closest_point_on_mesh(inv @ p)
    if not ok:
        distanza.append(999.0)
        continue
    lm = REG.matrix_world @ loc
    nm = (REG.matrix_world.to_3x3() @ nor).normalized()
    distanza.append((p - lm).dot(nm))
sepolti = sorted(d for d in distanza if d < 0)
print("vertici dentro la carne: %d | i piu' profondi: %.4f %.4f %.4f m"
      % (len(sepolti), sepolti[0], sepolti[1], sepolti[2]))
print("quanti oltre 2 cm dentro: %d | oltre 5 cm: %d | oltre 10 cm: %d"
      % (sum(1 for d in sepolti if d < -0.02), sum(1 for d in sepolti if d < -0.05),
         sum(1 for d in sepolti if d < -0.10)))


def peso_di(d, affondo):
    """1 nella fascia attorno alla pelle, sfumato ai due capi."""
    if d > stacco + fascia:
        return 0.0
    if d > stacco:
        return 1.0 - (d - stacco) / fascia
    if affondo is None or d >= -affondo:
        return 1.0
    if d < -(affondo + fascia):
        return 0.0
    return 1.0 - (-d - affondo) / fascia


def conforma(etichetta, affondo):
    attivo(base)
    bpy.ops.object.duplicate()
    o = bpy.context.active_object
    o.name = etichetta
    g = o.vertex_groups.new(name="aderenza")
    for i in range(len(o.data.vertices)):
        g.add([i], peso_di(distanza[i], affondo), 'REPLACE')
    partenza = [v.co.copy() for v in o.data.vertices]
    attivo(o)
    mod = o.modifiers.new("Conforma", 'SHRINKWRAP')
    mod.target = REG
    mod.wrap_method = 'NEAREST_SURFACEPOINT'
    mod.wrap_mode = 'OUTSIDE'
    mod.offset = stacco
    mod.vertex_group = g.name
    bpy.ops.object.modifier_apply(modifier=mod.name)
    o.vertex_groups.remove(o.vertex_groups["aderenza"])
    sp = sorted((o.data.vertices[i].co - partenza[i]).length for i in range(len(partenza)))
    n = len(sp)
    print("  %-16s mossi>0.5mm %4d | >20mm %4d | >50mm %3d | p99 %.4f | MAX %.4f"
          % (etichetta, sum(1 for s in sp if s > 0.0005),
             sum(1 for s in sp if s > 0.020), sum(1 for s in sp if s > 0.050),
             sp[int(n * 0.99)], sp[-1]))
    o.hide_render = True
    return o


print("\n=== fondo della fascia di aderenza (wrap_mode OUTSIDE) ===")
varianti = [("fondo_NESSUNO" if a is None else "fondo_%03d" % round(a * 1000),
             conforma("fondo_NESSUNO" if a is None else "fondo_%03d" % round(a * 1000), a))
            for a in AFFONDI]

mat = bpy.data.materials.new("acciaio")
mat.diffuse_color = (0.58, 0.61, 0.66, 1)
mat.metallic = 0.9
mat.roughness = 0.3
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.render.resolution_x = 900
sc.render.resolution_y = 1300
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.type = 'ORTHO'
mn, mx = bbox(base)
centro = (mn + mx) / 2
cd.ortho_scale = (mx.z - mn.z) * 1.06
for etichetta, ob in varianti:
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.hide_render = o is not ob
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    cam.location = centro + Vector((0, -3.0, 0))
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.render.filepath = FUORI + "aderenza_" + etichetta
    bpy.ops.render.render(write_still=True)
    print("reso: aderenza_" + etichetta)
print("FATTO")
