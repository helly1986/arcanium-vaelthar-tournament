# -*- coding: utf-8 -*-
"""PROVA: il guscio d'armatura DERIVATO DAL CORPO invece che scalato da un blob.

Domanda che deve rispondere: se invece di prendere una mesh Meshy e scalarla si
RITAGLIA la superficie del corpo sulla regione che l'armatura deve coprire e la
si ingrossa, si ottiene un pezzo che (a) copre esattamente cio' che si dichiara e
(b) aderisce per costruzione?

Non e' una proposta a parole: qui si fa e si guarda.

    blender --background --factory-startup --python prova_guscio_derivato.py
"""
import bpy, os, math
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"

## Le regioni: quali ossa devono restare COPERTE, e quanto stacca la piastra.
REGIONI = {
    "brachiale":  {"ossa": ["LeftShoulder", "LeftUpperArm", "LeftLowerArm",
                            "LeftUpperArm_twist_01", "LeftLowerArm_twist_01"],
                   "spessore": 0.014, "stacco": 0.008},
    "cosciale":   {"ossa": ["LeftUpperLeg", "LeftUpperLeg_twist_01",
                            "LeftLowerLeg", "LeftLowerLeg_twist_01"],
                   "spessore": 0.016, "stacco": 0.010},
}
SOGLIA = 0.35   # peso minimo perche' un vertice conti come "in regione"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=CORPO)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
corpo = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
print("corpo:", corpo.name, len(corpo.data.vertices), "vertici")


def attivo(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def guscio(nome, cfg):
    """Ritaglia la regione dal corpo e la ingrossa: un pezzo che aderisce
    per costruzione, perche' E' la superficie del corpo."""
    gruppi = {g.name: g.index for g in corpo.vertex_groups}
    voluti = [gruppi[n] for n in cfg["ossa"] if n in gruppi]
    if not voluti:
        print("  %s: nessun gruppo trovato" % nome)
        return None

    dentro = set()
    for v in corpo.data.vertices:
        peso = sum(g.weight for g in v.groups if g.group in voluti)
        if peso >= SOGLIA:
            dentro.add(v.index)
    print("  %-11s vertici in regione: %d su %d" % (nome, len(dentro), len(corpo.data.vertices)))
    if len(dentro) < 50:
        return None

    attivo(corpo)
    bpy.ops.object.duplicate()
    g = bpy.context.active_object
    g.name = "Guscio_" + nome

    ## via tutto cio' che non e' in regione
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(g.data)
    bm.verts.ensure_lookup_table()
    da_togliere = [v for v in bm.verts if v.index not in dentro]
    bmesh.ops.delete(bm, geom=da_togliere, context='VERTS')
    bm.to_mesh(g.data)
    bm.free()
    g.data.update()
    if len(g.data.vertices) == 0:
        return None

    ## stacco: si spinge lungo la normale, cosi' la piastra sta SOPRA la pelle
    attivo(g)
    m = g.modifiers.new("Stacco", 'DISPLACE')
    m.mid_level = 0.0
    m.strength = cfg["stacco"]
    bpy.ops.object.modifier_apply(modifier=m.name)
    ## spessore vero: una lamina, non un foglio
    m = g.modifiers.new("Spessore", 'SOLIDIFY')
    m.thickness = cfg["spessore"]
    m.offset = 1.0
    bpy.ops.object.modifier_apply(modifier=m.name)
    ## un filo di lisciatura, o si vede la tassellatura del corpo
    m = g.modifiers.new("Liscia", 'SMOOTH')
    m.factor = 0.5
    m.iterations = 3
    bpy.ops.object.modifier_apply(modifier=m.name)

    mn = Vector((min(v.co.x for v in g.data.vertices),
                 min(v.co.y for v in g.data.vertices),
                 min(v.co.z for v in g.data.vertices)))
    mx = Vector((max(v.co.x for v in g.data.vertices),
                 max(v.co.y for v in g.data.vertices),
                 max(v.co.z for v in g.data.vertices)))
    print("     -> %d vertici, %d triangoli, z %.3f..%.3f" %
          (len(g.data.vertices), len(g.data.loop_triangles), mn.z, mx.z))
    return g


gusci = []
for nome, cfg in REGIONI.items():
    o = guscio(nome, cfg)
    if o:
        gusci.append(o)

## ─── resa: corpo grigio, gusci accesi, tre quarti da sinistra ───────────────
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.materials.clear()

mat_pelle = bpy.data.materials.new("pelle")
mat_pelle.use_nodes = True
mat_pelle.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.62, 0.48, 0.42, 1)
corpo.data.materials.append(mat_pelle)

mat_acc = bpy.data.materials.new("acciaio")
mat_acc.use_nodes = True
b = mat_acc.node_tree.nodes["Principled BSDF"]
b.inputs[0].default_value = (0.30, 0.34, 0.40, 1)
b.inputs["Metallic"].default_value = 1.0
b.inputs["Roughness"].default_value = 0.35
for g in gusci:
    g.data.materials.append(mat_acc)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.render.resolution_x = 1100
sc.render.resolution_y = 1400
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)

cam_dato = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_dato)
sc.collection.objects.link(cam)
sc.camera = cam
cam_dato.lens = 60


def scatta(pos, mira, nome):
    cam.location = Vector(pos)
    d = Vector(mira) - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = FUORI + nome
    bpy.ops.render.render(write_still=True)
    print("reso:", sc.render.filepath + ".png")


scatta((1.9, -1.9, 1.25), (0.25, 0, 1.10), "guscio_tre_quarti")
scatta((0.0, -2.4, 1.05), (0, 0, 1.00), "guscio_fronte")
print("FATTO")
