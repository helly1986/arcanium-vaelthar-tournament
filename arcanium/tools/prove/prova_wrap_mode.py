# -*- coding: utf-8 -*-
"""Le due cure candidate per lo sfrangiamento, in matrice.

La diagnosi ha dato due indiziati:

1. **`wrap_mode`.** Si muovono 1.720 vertici su 3.894 (45%), e 1.075 di quelli
   sono la parete ESTERNA — la faccia che si vede. Se il modo muovesse "solo
   quelli dentro", come dice `docs/13`, i mossi sarebbero 689. Sospetto:
   `OUTSIDE_SURFACE` PROIETTA tutto sulla superficie (a distanza `offset`),
   e il modo che muove solo cio' che sta dentro e' `OUTSIDE`.
2. **Il bersaglio bucato.** Il corpo arriva da glTF NON SALDATO: 12.312 spigoli
   di bordo, spezzato su ogni cucitura UV, e nella regione ritagliata il PIEDE
   resta staccato dalla gamba. Su una superficie aperta il dentro/fuori non e'
   definito.

Quattro combinazioni, stessa camera, stesso materiale, e il conto di chi si
muove. Si guarda, non si deduce.

    blender --background --factory-startup --python arcanium/tools/prove/prova_wrap_mode.py
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
    via = [v for v in bm.verts if val.get(v, 0.0) > soglia + 1e-9]
    bmesh.ops.delete(bm, geom=via, context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def bordi(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    n = sum(1 for e in bm.edges if e.is_boundary)
    bm.free()
    return n


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

## un secondo corpo, SALDATO: e' l'indiziato numero due
attivo(corpo)
bpy.ops.object.duplicate()
corpo_saldato = bpy.context.active_object
corpo_saldato.name = "Corpo_saldato"
corpo_saldato.hide_render = True
attivo(corpo_saldato)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=SALDATURA)
bpy.ops.object.mode_set(mode='OBJECT')
print("corpo:          %6d vert, %5d spigoli di bordo" % (len(corpo.data.vertices), bordi(corpo)))
print("corpo saldato:  %6d vert, %5d spigoli di bordo"
      % (len(corpo_saldato.data.vertices), bordi(corpo_saldato)))


def fai_regione(base, etichetta):
    gruppi = {g.name: g.index for g in base.vertex_groups}
    ossa = [(LATO + n) if (LATO + n) in gruppi else n for n in CFG["regione"]]
    idx = {gruppi[n] for n in ossa if n in gruppi}
    grezzo = [1.0 - min(1.0, sum(g.weight for g in v.groups if g.group in idx))
              for v in base.data.vertices]
    liscio = liscia_campo(grezzo, _vicini(base))
    attivo(base)
    bpy.ops.object.duplicate()
    reg = bpy.context.active_object
    reg.name = "Reg_" + etichetta
    taglia_su_campo(reg, liscio, 0.7)
    reg.hide_render = True
    print("regione %-10s %6d vert, %5d spigoli di bordo"
          % (etichetta, len(reg.data.vertices), bordi(reg)))
    return reg


REG_CRUDA = fai_regione(corpo, "cruda")
REG_SALDA = fai_regione(corpo_saldato, "saldata")

# --- il pezzo, fino allo stadio F ------------------------------------------
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
## solo la gamba SINISTRA: una basta per decidere, e il confronto e' piu' netto
sinistro = next(t for t in tutti if (bbox(t)[0].x + bbox(t)[1].x) / 2 > 0)
for o in tutti:
    if o is not sinistro:
        bpy.data.objects.remove(o, do_unlink=True)
base = sinistro
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
print("pezzo base: %d vertici" % len(base.data.vertices))

# --- la matrice ------------------------------------------------------------
stacco, fascia = CFG["conforma"]


def conforma(etichetta, modo, ber):
    attivo(base)
    bpy.ops.object.duplicate()
    o = bpy.context.active_object
    o.name = etichetta
    g = o.vertex_groups.new(name="aderenza")
    inv = ber.matrix_world.inverted()
    n_dentro = 0
    for v in o.data.vertices:
        p = o.matrix_world @ v.co
        ok, loc, nor, _ = ber.closest_point_on_mesh(inv @ p)
        if not ok:
            g.add([v.index], 0.0, 'REPLACE')
            continue
        lm = ber.matrix_world @ loc
        nm = (ber.matrix_world.to_3x3() @ nor).normalized()
        d = (p - lm).dot(nm)
        if d < 0.0:
            n_dentro += 1
        peso = 1.0 if d < stacco else (0.0 if d > stacco + fascia
                                       else 1.0 - (d - stacco) / fascia)
        g.add([v.index], peso, 'REPLACE')
    partenza = [v.co.copy() for v in o.data.vertices]
    attivo(o)
    mod = o.modifiers.new("Conforma", 'SHRINKWRAP')
    mod.target = ber
    mod.wrap_method = 'NEAREST_SURFACEPOINT'
    mod.wrap_mode = modo
    mod.offset = stacco
    mod.vertex_group = g.name
    bpy.ops.object.modifier_apply(modifier=mod.name)
    o.vertex_groups.remove(o.vertex_groups["aderenza"])
    sp = sorted((o.data.vertices[i].co - partenza[i]).length for i in range(len(partenza)))
    n = len(sp)
    print("  %-28s dentro la carne %4d | mossi>0.5mm %4d (%2.0f%%) | "
          ">20mm %4d | p99 %.4f | MAX %.4f"
          % (etichetta, n_dentro, sum(1 for s in sp if s > 0.0005),
             100.0 * sum(1 for s in sp if s > 0.0005) / n,
             sum(1 for s in sp if s > 0.020), sp[int(n * 0.99)], sp[-1]))
    o.hide_render = True
    return o


print("\n=== matrice: modo x bersaglio ===")
varianti = [("V0_nessuna", None, None)]
for nome_modo, modo in (("OUTSIDE_SURFACE", 'OUTSIDE_SURFACE'), ("OUTSIDE", 'OUTSIDE')):
    for nome_ber, ber in (("cruda", REG_CRUDA), ("saldata", REG_SALDA)):
        varianti.append((("%s_%s" % (nome_modo, nome_ber)),
                         conforma("%s_%s" % (nome_modo, nome_ber), modo, ber), None))

# --- resa -------------------------------------------------------------------
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

for etichetta, ob, _ in varianti:
    target = base if ob is None else ob
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.hide_render = o is not target
    target.data.materials.clear()
    target.data.materials.append(mat)
    cam.location = centro + Vector((0, -3.0, 0))
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.render.filepath = FUORI + "wrap_" + etichetta
    bpy.ops.render.render(write_still=True)
    print("reso: wrap_" + etichetta)
print("FATTO")
