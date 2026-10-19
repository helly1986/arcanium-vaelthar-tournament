# -*- coding: utf-8 -*-
"""Perche' la conformazione sfrangia i gambali: si misura CHI muove.

`bisezione_gambali.py` ha isolato lo stadio: F (gonfiato) e' pulito, G
(conformato) e' scheggiato. Qui si guarda dentro lo shrinkwrap: quanti vertici
si muovono, di quanto, dove, e — la domanda che decide tutto — se a muoversi e'
la parete INTERNA del guscio (giusto: si appoggia) o anche quella ESTERNA
(sbagliato: il guscio si accartoccia).

Rende anche una MAPPA di calore dello spostamento sul pezzo, e le due varianti
che il sospetto suggerisce.

    blender --background --factory-startup --python arcanium/tools/prove/diagnosi_conformazione.py
"""
import bpy, os, math, bmesh
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
PEZZO = RADICE + "assets/characters/armor/gambali_prima_veglia.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/bisezione/"

CFG = dict(alto=1.06, basso=-0.01, centro_y=0.00, gonfia=1.12, ancora="basso",
           cinghia=1.02, centra_su="UpperLeg",
           ossa_lato=["UpperLeg", "LowerLeg", "Foot"],
           regione=["UpperLeg", "LowerLeg", "Foot", "Hips"],
           conforma=(0.010, 0.024))
SALDATURA = 0.0001
ANGOLO_SPIGOLO = math.radians(35)

os.makedirs(FUORI, exist_ok=True)

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
_gruppi_corpo = {g.name: g.index for g in corpo.vertex_groups}


def attivo(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def bbox(o):
    co = [o.matrix_world @ v.co for v in o.data.vertices]
    return (Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co))),
            Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co))))


def osso(nome):
    return rig.matrix_world @ rig.data.bones[nome].head_local


def _vicini(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    fuori = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    bm.free()
    return fuori


def liscia_campo(valori, vicini, giri=8, forza=0.65):
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
    return len(incroci), len(via)


# --- fino allo stadio F -----------------------------------------------------
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
lati = sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
              key=lambda o: len(o.data.vertices), reverse=True)
for o in lati[2:]:
    bpy.data.objects.remove(o, do_unlink=True)
lati = lati[:2]


def gonfia(o, fattore, ancora):
    mn, mx = bbox(o)
    fermo = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    o.scale = o.scale * fattore
    bpy.context.view_layer.update()
    mn2, mx2 = bbox(o)
    nuovo = Vector(((mn2.x + mx2.x) / 2, (mn2.y + mx2.y) / 2, mn2.z))
    o.location += fermo - nuovo
    bpy.context.view_layer.update()


for t in lati:
    mn, mx = bbox(t)
    lato = "Left" if (mn.x + mx.x) / 2 > 0 else "Right"
    t.name = "PV_Gambal_" + lato[0]
    scala = (CFG["alto"] - CFG["basso"]) / (mx.z - mn.z)
    cin = CFG["cinghia"]
    t.scale = (scala * cin, scala * cin, scala)
    bpy.context.view_layer.update()
    mn, mx = bbox(t)
    asse = osso(lato + CFG["centra_su"])
    t.location += Vector((asse.x - (mn.x + mx.x) / 2,
                          CFG["centro_y"] - (mn.y + mx.y) / 2,
                          (CFG["alto"] + CFG["basso"]) / 2 - (mn.z + mx.z) / 2))
    bpy.context.view_layer.update()
    gonfia(t, CFG["gonfia"], CFG["ancora"])
    attivo(t)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- il bersaglio regione ---------------------------------------------------
_bersagli = {}


def bersaglio_regione(ossa):
    chiave = tuple(sorted(ossa))
    if chiave in _bersagli:
        return _bersagli[chiave]
    idx = {_gruppi_corpo[n] for n in ossa if n in _gruppi_corpo}
    grezzo = [1.0 - min(1.0, sum(g.weight for g in v.groups if g.group in idx))
              for v in corpo.data.vertices]
    liscio = liscia_campo(grezzo, _vicini(corpo), giri=5, forza=0.6)
    attivo(corpo)
    bpy.ops.object.duplicate()
    reg = bpy.context.active_object
    reg.name = "Regione_" + "_".join(sorted(ossa))[:40]
    taglia_su_campo(reg, liscio, 0.7)
    reg.hide_render = True
    _bersagli[chiave] = reg
    mn, mx = bbox(reg)
    ## quanti spigoli di BORDO ha il bersaglio, e a che quota stanno
    bm = bmesh.new()
    bm.from_mesh(reg.data)
    bordo = [e for e in bm.edges if e.is_boundary]
    zb = sorted((reg.matrix_world @ v.co).z for e in bordo for v in e.verts)
    print("   bersaglio %-46s %6d vert  z %.3f..%.3f  spigoli di bordo %d  (bordo z %.3f..%.3f)"
          % (reg.name, len(reg.data.vertices), mn.z, mx.z, len(bordo),
             zb[0] if zb else 0, zb[-1] if zb else 0))
    bm.free()
    return reg


# --- la conformazione, misurata --------------------------------------------
stacco, fascia = CFG["conforma"]

print("\n=== chi si muove, e di quanto ===")
for t in lati:
    lato = "Left" if t.name.endswith("_L") else "Right"
    regione = [(lato + n) if (lato + n) in _gruppi_corpo else n for n in CFG["regione"]]
    ber = bersaglio_regione(regione)

    t.data.calc_normals_split() if hasattr(t.data, "calc_normals_split") else None
    normali = [v.normal.copy() for v in t.data.vertices]
    verso_corpo = []          # +1 se la normale del vertice guarda VERSO il corpo
    inv = ber.matrix_world.inverted()
    dentro = []
    pesi = []
    for i, v in enumerate(t.data.vertices):
        p = t.matrix_world @ v.co
        ok, loc, nor, _ = ber.closest_point_on_mesh(inv @ p)
        if not ok:
            pesi.append(0.0)
            dentro.append(0.0)
            verso_corpo.append(0)
            continue
        lm = ber.matrix_world @ loc
        nm = (ber.matrix_world.to_3x3() @ nor).normalized()
        d = (p - lm).dot(nm)
        dentro.append(d)
        peso = 1.0 if d < stacco else (0.0 if d > stacco + fascia
                                       else 1.0 - (d - stacco) / fascia)
        pesi.append(peso)
        nv = (t.matrix_world.to_3x3() @ normali[i]).normalized()
        verso_corpo.append(1 if nv.dot(nm) < 0.0 else 0)

    g = t.vertex_groups.new(name="aderenza")
    for i, w in enumerate(pesi):
        g.add([i], w, 'REPLACE')
    partenza = [v.co.copy() for v in t.data.vertices]
    attivo(t)
    mod = t.modifiers.new("Conforma", 'SHRINKWRAP')
    mod.target = ber
    mod.wrap_method = 'NEAREST_SURFACEPOINT'
    mod.wrap_mode = 'OUTSIDE_SURFACE'
    mod.offset = stacco
    mod.vertex_group = g.name
    bpy.ops.object.modifier_apply(modifier=mod.name)
    t.vertex_groups.remove(t.vertex_groups["aderenza"])

    sposta = [(t.data.vertices[i].co - partenza[i]).length for i in range(len(partenza))]
    n = len(sposta)
    ordinati = sorted(sposta)
    mossi = [i for i, s in enumerate(sposta) if s > 0.0005]
    print("\n%s  %d vertici" % (t.name, n))
    print("  mossi >0.5mm: %d (%.0f%%)   >5mm: %d   >20mm: %d   >50mm: %d"
          % (len(mossi), 100.0 * len(mossi) / n,
             sum(1 for s in sposta if s > 0.005),
             sum(1 for s in sposta if s > 0.020),
             sum(1 for s in sposta if s > 0.050)))
    print("  spostamento  mediana %.4f  p90 %.4f  p99 %.4f  MAX %.4f m"
          % (ordinati[n // 2], ordinati[int(n * 0.90)], ordinati[int(n * 0.99)],
             ordinati[-1]))
    print("  distanza dal corpo dei mossi:  dentro la carne %d,  fuori %d"
          % (sum(1 for i in mossi if dentro[i] < 0.0),
             sum(1 for i in mossi if dentro[i] >= 0.0)))
    print("  ⚠ parete: dei mossi, %d guardano VERSO il corpo (parete interna),"
          " %d guardano FUORI (parete esterna, cioe' la faccia che si VEDE)"
          % (sum(1 for i in mossi if verso_corpo[i]),
             sum(1 for i in mossi if not verso_corpo[i])))
    grossi = sorted(mossi, key=lambda i: -sposta[i])[:12]
    print("  i 12 spostamenti piu' grossi:")
    for i in grossi:
        p = t.matrix_world @ partenza[i]
        print("     z=%.3f x=%+.3f  d_corpo=%+.4f  peso=%.2f  %s  ->  %.4f m"
              % (p.z, p.x, dentro[i], pesi[i],
                 "interna" if verso_corpo[i] else "ESTERNA", sposta[i]))
    ## dove stanno, in quota
    fasce = {}
    for i in mossi:
        z = (t.matrix_world @ partenza[i]).z
        fasce.setdefault(round(z * 10) / 10, []).append(sposta[i])
    print("  per fascia di quota (z: quanti mossi / spostamento max):")
    for z in sorted(fasce):
        print("     z~%.1f  %4d vertici  max %.4f" % (z, len(fasce[z]), max(fasce[z])))
    t["_sposta"] = sposta

# --- mappa di calore --------------------------------------------------------
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'VERTEX'
sc.render.resolution_x = 1200
sc.render.resolution_y = 1200
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.type = 'ORTHO'

SCALA_MAPPA = 0.030   # rosso pieno = 30 mm di spostamento
for t in lati:
    sposta = t["_sposta"]
    col = t.data.color_attributes.new(name="calore", type='FLOAT_COLOR', domain='POINT')
    for i, s in enumerate(sposta):
        q = min(1.0, s / SCALA_MAPPA)
        col.data[i].color = (0.12 + 0.88 * q, 0.14 * (1.0 - q) + 0.35 * q,
                             0.55 * (1.0 - q), 1.0)
    t.data.color_attributes.active_color = col
    t.hide_render = False

co = [o.matrix_world @ v.co for o in lati for v in o.data.vertices]
mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
centro = (mn + mx) / 2
cd.ortho_scale = max(mx.x - mn.x, mx.z - mn.z) * 1.10
cam.location = centro + Vector((0, -3.0, 0))
cam.rotation_euler = (math.radians(90), 0, 0)
sc.render.filepath = FUORI + "mappa_spostamento_fronte"
bpy.ops.render.render(write_still=True)
cam.location = centro + Vector((0, 3.0, 0))
cam.rotation_euler = (math.radians(90), 0, math.radians(180))
sc.render.filepath = FUORI + "mappa_spostamento_retro"
bpy.ops.render.render(write_still=True)
print("\nmappa: blu = fermo, rosso = %.0f mm o piu'" % (SCALA_MAPPA * 1000))
print("FATTO")
