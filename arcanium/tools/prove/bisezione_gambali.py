# -*- coding: utf-8 -*-
"""BISEZIONE del difetto dei gambali: rendere DOPO OGNI STADIO della pipeline.

Sintomo: le piastre delle gambe escono scheggiate attorno al ginocchio. Tre
ipotesi gia' escluse e misurate (scambio sinistra/destra, mesh sorgente,
conformazione), quindi il danno nasce fra il sorgente e l'export.

Qui si rifa' il ramo `dividi_lati` di `vesti_protagonista.py` fermandosi a ogni
stadio e rendendo il pezzo. **Stesso materiale e stessa inquadratura ortografica
a ogni stadio**: senza questo il confronto non vale niente — i due render gia'
fatti usavano materiali diversi (il sorgente col grigio Meshy allo slot 0, il
fittato col metallo scuro), e su metallo scuro un difetto di normali si vede
mentre su grigio opaco no.

    blender --background --factory-startup --python arcanium/tools/prove/bisezione_gambali.py
"""
import bpy, os, math, bmesh, tempfile
from mathutils import Vector
from mathutils.kdtree import KDTree

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
PEZZO = RADICE + "assets/characters/armor/gambali_prima_veglia.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/bisezione/"
TMP_GLB = os.path.join(tempfile.gettempdir(), "bisezione_gambali.glb").replace("\\", "/")

## copiata da VESTIZIONE["gambali"] — se cambia li', cambia qui
CFG = dict(alto=1.06, basso=-0.01, centro_y=0.00, gonfia=1.12, ancora="basso",
           cinghia=1.02, centra_su="UpperLeg",
           ossa_lato=["UpperLeg", "LowerLeg", "Foot"],
           regione=["UpperLeg", "LowerLeg", "Foot", "Hips"],
           conforma=(0.010, 0.024))
SALDATURA = 0.0001
ANGOLO_SPIGOLO = math.radians(35)
AFFILATURA = 6.0

os.makedirs(FUORI, exist_ok=True)

# --- scena ------------------------------------------------------------------
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


def osso(nome):
    return rig.matrix_world @ rig.data.bones[nome].head_local


def attivo(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def bbox(o):
    co = [o.matrix_world @ v.co for v in o.data.vertices]
    return (Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co))),
            Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co))))


# --- resa: identica a ogni stadio, o il confronto non vale ------------------
def monta_resa():
    mat = bpy.data.materials.new("acciaio_bisezione")
    mat.diffuse_color = (0.58, 0.61, 0.66, 1)
    mat.metallic = 0.9
    mat.roughness = 0.3
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_cavity = True
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
    return mat, cd, cam


ACCIAIO, _cd, cam = monta_resa()


def scatta(oggetti, stadio):
    """Due inquadrature: il pezzo INTERO e il ginocchio. Ortografiche, di fronte."""
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.hide_render = o not in oggetti
    for o in oggetti:
        o.data.materials.clear()
        o.data.materials.append(ACCIAIO)
    co = [o.matrix_world @ v.co for o in oggetti for v in o.data.vertices]
    mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    centro = (mn + mx) / 2
    larg, alt, prof = mx.x - mn.x, mx.z - mn.z, mx.y - mn.y
    sc = bpy.context.scene
    for etichetta, mira, scala in (
            ("intero", centro, max(larg, alt) * 1.10),
            ("ginocchio", Vector((centro.x, centro.y, mn.z + alt * 0.52)), larg * 0.85)):
        _cd.ortho_scale = scala
        cam.location = mira + Vector((0, -(prof * 2.0 + 2.0), 0))
        cam.rotation_euler = (math.radians(90), 0, 0)
        sc.render.filepath = "%s%s_%s" % (FUORI, stadio, etichetta)
        bpy.ops.render.render(write_still=True)
    print("  ~~ reso stadio %s  (bbox z %.3f..%.3f larg %.3f)" % (stadio, mn.z, mx.z, larg))


# --- A: importato, nient'altro ----------------------------------------------
prima = set(bpy.data.objects.keys())
bpy.ops.import_scene.gltf(filepath=PEZZO)
nuovi = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - prima]
m = max((o for o in nuovi if o.type == 'MESH'), key=lambda o: len(o.data.vertices))
for o in nuovi:
    if o is not m:
        bpy.data.objects.remove(o, do_unlink=True)
m.name = "PV_Gambali"
attivo(m)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print("A importato: %d vertici, %d facce | normali custom: %s | facce smooth: %d/%d"
      % (len(m.data.vertices), len(m.data.polygons), m.data.has_custom_normals,
         sum(1 for p in m.data.polygons if p.use_smooth), len(m.data.polygons)))
scatta([m], "A_importato")

# --- B: saldatura (remove_doubles) ------------------------------------------
attivo(m)
_n = len(m.data.vertices)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=SALDATURA)
bpy.ops.object.mode_set(mode='OBJECT')
print("B saldato: %d -> %d vertici | normali custom: %s"
      % (_n, len(m.data.vertices), m.data.has_custom_normals))
scatta([m], "B_saldato")

# --- C: normali buttate + shade auto smooth ---------------------------------
attivo(m)
if m.data.has_custom_normals:
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
try:
    bpy.ops.object.shade_auto_smooth(angle=ANGOLO_SPIGOLO)
except (AttributeError, RuntimeError) as e:
    print("   shade_auto_smooth non disponibile (%s): shade smooth totale" % e)
    for p in m.data.polygons:
        p.use_smooth = True
print("C normali: custom=%s | modificatori: %s | facce smooth %d/%d"
      % (m.data.has_custom_normals, [x.name for x in m.modifiers],
         sum(1 for p in m.data.polygons if p.use_smooth), len(m.data.polygons)))
scatta([m], "C_normali")

# --- D: separate LOOSE, si tengono i due gusci piu' grossi ------------------
attivo(m)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='LOOSE')
bpy.ops.object.mode_set(mode='OBJECT')
lati = sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
              key=lambda o: len(o.data.vertices), reverse=True)
print("D diviso: %d gusci, vertici %s" % (len(lati), [len(t.data.vertices) for t in lati[:6]]))
for o in lati[2:]:
    bpy.data.objects.remove(o, do_unlink=True)
lati = lati[:2]
for t in lati:
    mn, mx = bbox(t)
    print("   guscio %5d vert  centro x=%+.4f  z %.3f..%.3f  modificatori %s"
          % (len(t.data.vertices), (mn.x + mx.x) / 2, mn.z, mx.z,
             [x.name for x in t.modifiers]))
scatta(lati, "D_diviso")

# --- E: scala e posizione su ciascuna gamba ---------------------------------
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
    print("E %-16s x%.3f  -> centro x=%+.4f"
          % (t.name, scala, (bbox(t)[0].x + bbox(t)[1].x) / 2))
scatta(lati, "E_scalato")

# --- F: gonfiatura ----------------------------------------------------------
def gonfia(o, fattore, ancora, riferimento=None):
    if abs(fattore - 1.0) < 1e-6:
        return
    mn, mx = bbox(o)
    if ancora == "basso":
        fermo = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    elif ancora == "polsino":
        fermo = riferimento
    else:
        fermo = (mn + mx) / 2
    o.scale = o.scale * fattore
    bpy.context.view_layer.update()
    mn2, mx2 = bbox(o)
    if ancora == "basso":
        nuovo = Vector(((mn2.x + mx2.x) / 2, (mn2.y + mx2.y) / 2, mn2.z))
    elif ancora == "polsino":
        nuovo = riferimento
    else:
        nuovo = (mn2 + mx2) / 2
    o.location += fermo - nuovo
    bpy.context.view_layer.update()


for t in lati:
    gonfia(t, CFG["gonfia"], CFG["ancora"])
print("F gonfiato x%.2f" % CFG["gonfia"])
scatta(lati, "F_gonfiato")

# --- G: conformazione -------------------------------------------------------
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
    print("   bersaglio %s: %d vertici" % (reg.name, len(reg.data.vertices)))
    return reg


def conforma_al_corpo(pezzo, stacco, fascia, ber):
    g = pezzo.vertex_groups.new(name="aderenza")
    mw = pezzo.matrix_world
    inv = ber.matrix_world.inverted()
    dentro = 0
    for v in pezzo.data.vertices:
        p_mondo = mw @ v.co
        ok, loc, nor, _ = ber.closest_point_on_mesh(inv @ p_mondo)
        if not ok:
            g.add([v.index], 0.0, 'REPLACE')
            continue
        lm = ber.matrix_world @ loc
        nm = (ber.matrix_world.to_3x3() @ nor).normalized()
        d = (p_mondo - lm).dot(nm)
        if d < 0.0:
            dentro += 1
        if d < stacco:
            peso = 1.0
        elif d > stacco + fascia:
            peso = 0.0
        else:
            peso = 1.0 - (d - stacco) / fascia
        g.add([v.index], peso, 'REPLACE')
    attivo(pezzo)
    mod = pezzo.modifiers.new("Conforma", 'SHRINKWRAP')
    mod.target = ber
    mod.wrap_method = 'NEAREST_SURFACEPOINT'
    mod.wrap_mode = 'OUTSIDE_SURFACE'
    mod.offset = stacco
    mod.vertex_group = g.name
    bpy.ops.object.modifier_apply(modifier=mod.name)
    pezzo.vertex_groups.remove(pezzo.vertex_groups[g.name])
    return dentro


stacco, fascia = CFG["conforma"]
for t in lati:
    lato = "Left" if t.name.endswith("_L") else "Right"
    regione = [(lato + n) if (lato + n) in _gruppi_corpo else n for n in CFG["regione"]]
    d = conforma_al_corpo(t, stacco, fascia, bersaglio_regione(regione))
    print("G %-16s conformato: %d/%d vertici erano dentro la carne | modificatori %s"
          % (t.name, d, len(t.data.vertices), [x.name for x in t.modifiers]))
scatta(lati, "G_conformato")

# --- H: legatura (pesi + affilatura) e la RIMOZIONE DEI MODIFICATORI --------
def mappa_ai_dichiarati(rig, ossa):
    vicini = {}
    for b in rig.data.bones:
        vicini.setdefault(b.name, set())
        if b.parent:
            vicini[b.name].add(b.parent.name)
            vicini.setdefault(b.parent.name, set()).add(b.name)
    fuori = {n: n for n in ossa}
    fronte = list(ossa)
    while fronte:
        prossimo = []
        for n in fronte:
            for v in vicini.get(n, ()):
                if v not in fuori:
                    fuori[v] = fuori[n]
                    prossimo.append(v)
        fronte = prossimo
    return fuori


for t in lati:
    lato = "Left" if t.name.endswith("_L") else "Right"
    ossa = [lato + n for n in CFG["ossa_lato"]]
    attivo(t)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action='DESELECT')
    t.select_set(True)
    corpo.select_set(True)
    bpy.context.view_layer.objects.active = corpo
    bpy.ops.object.data_transfer(
        data_type='VGROUP_WEIGHTS', use_create=True,
        vert_mapping='POLYINTERP_NEAREST',
        layers_select_src='ALL', layers_select_dst='NAME', mix_mode='REPLACE')
    attivo(t)
    nomi = [g.name for g in t.vertex_groups]
    verso = mappa_ai_dichiarati(rig, ossa)
    gruppi = {}
    for v in t.data.vertices:
        sommati = {}
        for g in v.groups:
            if g.weight <= 0.0:
                continue
            n = verso.get(nomi[g.group])
            if n is not None:
                sommati[n] = sommati.get(n, 0.0) + g.weight
        pesi = list(sommati.items())
        if not pesi:
            raise SystemExit("%s: vertice senza peso" % t.name)
        aff = [(n, w ** AFFILATURA) for n, w in pesi]
        tot = sum(w for _, w in aff)
        for n, w in aff:
            if w / tot > 0.001:
                gruppi.setdefault(n, []).append((v.index, w / tot))
    for g in list(t.vertex_groups):
        t.vertex_groups.remove(g)
    for n, coppie in gruppi.items():
        g = t.vertex_groups.new(name=n)
        for i, w in coppie:
            g.add([i], w, 'REPLACE')
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    print("H %-16s modificatori PRIMA della pulizia: %s"
          % (t.name, [x.name for x in t.modifiers]))
    for mod in list(t.modifiers):
        t.modifiers.remove(mod)
    mod = t.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    t.parent = rig
    t.matrix_parent_inverse = rig.matrix_world.inverted()
    print("H %-16s legato, %d gruppi | facce smooth %d/%d | normali custom %s"
          % (t.name, len(gruppi), sum(1 for p in t.data.polygons if p.use_smooth),
             len(t.data.polygons), t.data.has_custom_normals))
scatta(lati, "H_legato")

# --- I: export + reimport ---------------------------------------------------
bpy.data.objects.remove(corpo, do_unlink=True)
for r in list(_bersagli.values()):
    bpy.data.objects.remove(r, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for t in lati:
    t.hide_set(False)
    t.hide_viewport = False
    t.hide_render = False
    t.select_set(True)
rig.hide_set(False)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=TMP_GLB, export_format='GLB', use_selection=True,
                          export_animations=False, export_yup=True,
                          export_apply=False, export_skins=True)
print("I esportato:", TMP_GLB, os.path.getsize(TMP_GLB), "byte")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=TMP_GLB)
gambali = [o for o in bpy.data.objects if o.type == 'MESH']
print("I reimportato: %s" % [(o.name, len(o.data.vertices), o.data.has_custom_normals,
                              sum(1 for p in o.data.polygons if p.use_smooth),
                              len(o.data.polygons)) for o in gambali])
ACCIAIO, _cd, cam = monta_resa()
scatta(gambali, "I_esportato")
print("FATTO")
