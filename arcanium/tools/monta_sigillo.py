"""Monta un SIGILLO fatto con Tripo P2 (FBX quad) per la mano sinistra: FBX in,
GLB out, come monta_scudo.py per un pezzo che e' uno scettro.

Uso (Blender in background, per non toccare la scena aperta):
  blender --background --factory-startup --python arcanium/tools/monta_sigillo.py -- <nome> [lunghezza] [testa_da spessore]

- La sorgente e' assets/weapons/<nome>/sorgenti/<nome>.fbx, con la cartella .fbm
  di Tripo accanto.
- Il passaggio obbligato in Blender: `controlla_e_ripara` di monta_campione.py.
- Lo scettro va come quello della Prima Veglia, cosi' una presa vale per tutti:
  0,40 m, centrato nell'origine, asta lungo Y di Godot con la testa in alto e la
  faccia del medaglione verso -Z. Tripo lo fa nascere in piedi con la faccia verso
  -Y di Blender (+Z di Godot): si gira di mezzo giro. Va guardato: da solo il disco
  non dice qual e' il davanti.

- `testa_da spessore`: Tripo puo' dare al disco la profondita' di un martello
  (Verath, 17 cm): sopra la quota `testa_da` si schiaccia allo `spessore`, in metri.
  Davanti e dietro restano com'erano.

Esce assets/weapons/<nome>/<nome>.glb, solo la mesh, texture JPEG dentro.
"""
import math
import sys

import bpy
import mathutils

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
MONTA_CAMPIONE = RADICE + "arcanium/tools/monta_campione.py"


def monta(nome, lunghezza=0.40, testa_da=None, spessore=None):
    ns = {"__name__": "monta_sigillo"}
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

    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bm.to_mesh(me.data)
    bm.free()
    ns["controlla_e_ripara"](me.name)

    co = [v.co for v in me.data.vertices]
    mn = mathutils.Vector((min(p[i] for p in co) for i in range(3)))
    mx = mathutils.Vector((max(p[i] for p in co) for i in range(3)))
    misure = mx - mn
    print("sigillo %s: misure grezze %s" % (nome, tuple(round(x, 3) for x in misure)))
    if max(range(3), key=lambda i: misure[i]) != 2:
        raise RuntimeError("%s non nasce in piedi: si guarda prima di girarlo" % nome)
    me.data.transform(mathutils.Matrix.Translation(-(mn + mx) / 2))
    me.data.transform(mathutils.Matrix.Scale(lunghezza / misure.z, 4))
    me.data.transform(mathutils.Matrix.Rotation(math.pi, 4, 'Z'))
    if testa_da is not None:
        testa = [v for v in me.data.vertices if v.co.z >= testa_da]
        k = spessore / (max(v.co.y for v in testa) - min(v.co.y for v in testa))
        for v in testa:
            v.co.y *= k
    me.data.update()

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
    print("sigillo %s: %d vertici, %d facce, x %.3f y %.3f z %.3f -> %s" % (nome, len(me.data.vertices), len(me.data.polygons),
            max(p.x for p in co) - min(p.x for p in co), max(p.y for p in co) - min(p.y for p in co),
            max(p.z for p in co) - min(p.z for p in co), uscita))


if "--" in sys.argv:
    a = sys.argv[sys.argv.index("--") + 1:]
    monta(a[0], float(a[1]) if len(a) > 1 else 0.40, float(a[2]) if len(a) > 2 else None,
            float(a[3]) if len(a) > 3 else None)
