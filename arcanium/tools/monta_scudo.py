"""Monta uno SCUDO fatto con Tripo P2 (FBX quad) per la mano sinistra: FBX in,
GLB out, il fratello di monta_arma.py per un pezzo che e' un disco e non un'asta.

Uso (Blender in background, per non toccare la scena aperta):
  blender --background --factory-startup --python arcanium/tools/monta_scudo.py -- <nome> <diametro> [saturazione valore]

- La sorgente e' assets/weapons/<nome>/sorgenti/<nome>.fbx, con la cartella .fbm
  di Tripo accanto.
- Il passaggio obbligato in Blender: `controlla_e_ripara` di monta_campione.py.
- Il disco si mette sul piano XY di Godot con il centro nell'origine e la FACCIA
  (l'umbone) verso -Z: la convenzione del nodo `Shield` della mano
  (player/equipment_system/equipment/shield.tscn). L'umbone si trova misurando.

Esce assets/weapons/<nome>/<nome>.glb, solo la mesh, texture JPEG dentro.
"""
import math
import sys

import bpy
import mathutils

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
MONTA_CAMPIONE = RADICE + "arcanium/tools/monta_campione.py"


def monta(nome, diametro, tinta=None):
    ns = {"__name__": "monta_scudo"}
    exec(compile(open(MONTA_CAMPIONE, encoding="utf-8").read(), MONTA_CAMPIONE, "exec"), ns)
    cartella = RADICE + "assets/weapons/%s/" % nome
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.import_scene.fbx(filepath=cartella + "sorgenti/%s.fbx" % nome, use_image_search=True)
    mesh = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in list(bpy.data.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in mesh:
        o.select_set(True)
    bpy.context.view_layer.objects.active = mesh[0]
    if len(mesh) > 1:
        bpy.ops.object.join()
    me = bpy.context.view_layer.objects.active
    me.name = nome
    me.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    _salda(me)
    ns["controlla_e_ripara"](me.name)

    ## L'asse sottile e' la normale del disco: va su Y di Blender (Z di Godot).
    co = [v.co.copy() for v in me.data.vertices]
    mn = mathutils.Vector((min(p[i] for p in co) for i in range(3)))
    mx = mathutils.Vector((max(p[i] for p in co) for i in range(3)))
    misure = mx - mn
    sottile = min(range(3), key=lambda i: misure[i])
    print("scudo %s: misure grezze %s, asse sottile %s" % (nome, tuple(round(x, 3) for x in misure), "XYZ"[sottile]))
    if sottile == 0:
        me.data.transform(mathutils.Matrix.Rotation(math.pi / 2, 4, 'Z'))
    elif sottile == 2:
        me.data.transform(mathutils.Matrix.Rotation(math.pi / 2, 4, 'X'))

    ## Il centro nell'origine e il diametro vero.
    co = [v.co for v in me.data.vertices]
    mn = mathutils.Vector((min(p[i] for p in co) for i in range(3)))
    mx = mathutils.Vector((max(p[i] for p in co) for i in range(3)))
    me.data.transform(mathutils.Matrix.Translation(-(mn + mx) / 2))
    k = diametro / max(mx.x - mn.x, mx.z - mn.z)
    me.data.transform(mathutils.Matrix.Scale(k, 4))

    ## La faccia: Godot -Z e' Blender +Y. L'umbone e' una cupola fitta di vertici
    ## al centro del disco: la media sta dalla sua parte (gli estremi no, una
    ## fascia sul retro sporge quanto lui).
    co = [v.co for v in me.data.vertices]
    centro = [p.y for p in co if math.hypot(p.x, p.z) < diametro * 0.08]
    media = sum(centro) / len(centro)
    print("scudo %s: al centro %d vertici, y %.3f..%.3f, media %.3f" % (nome, len(centro), min(centro), max(centro), media))
    if media < 0.0:
        me.data.transform(mathutils.Matrix.Rotation(math.pi, 4, 'Z'))
        print("scudo %s: girato, l'umbone stava dietro" % nome)
    me.data.update()

    if tinta is not None:
        ns["smorza_tinta"](tinta[0], saturazione=tinta[1], valore=tinta[2], nome_mesh=me.name)
    for img in bpy.data.images:
        if img.name.startswith("tripo_image") or img.name == "Baked_BaseColor":
            if not img.packed_file:
                img.pack()
            img.filepath_raw = "//Baked_BaseColor.jpg"
            img.name = "Baked_BaseColor"

    bpy.ops.object.select_all(action='DESELECT')
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    bpy.ops.object.shade_smooth()
    uscita = cartella + "%s.glb" % nome
    bpy.ops.export_scene.gltf(filepath=uscita, export_format='GLB', use_selection=True,
                              export_animations=False, export_skins=False, export_apply=True)
    co = [v.co for v in me.data.vertices]
    print("scudo %s: %d vertici, %d facce, x %.3f y %.3f z %.3f -> %s" % (nome, len(me.data.vertices), len(me.data.polygons),
            max(p.x for p in co) - min(p.x for p in co), max(p.y for p in co) - min(p.y for p in co),
            max(p.z for p in co) - min(p.z for p in co), uscita))


def _salda(me):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bm.to_mesh(me.data)
    bm.free()
    me.data.update()


if "--" in sys.argv:
    a = sys.argv[sys.argv.index("--") + 1:]
    monta(a[0], float(a[1]), (0.0, float(a[2]), float(a[3])) if len(a) > 3 else None)
