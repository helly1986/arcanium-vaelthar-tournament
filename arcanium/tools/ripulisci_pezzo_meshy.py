# -*- coding: utf-8 -*-
"""Toglie le seghettature da un pezzo Meshy generato ad alta densita'.

    blender --background --factory-startup --python arcanium/tools/ripulisci_pezzo_meshy.py -- <in.glb> <out.glb> [--tri 60000] [--smussa 3]

## Il problema

A poligoni bassi (15.000 quad) il ricostruttore di Meshy semplifica troppo e
sbrecciai bordi: sulla corazza la fascia in vita usciva strappata e bucata. A
poligoni alti (300.000 triangoli) la forma e' giusta — fauld intero, nessuna
cucitura da simmetria — ma ogni bordo si riempie di PUNTE: a quella risoluzione
il rumore della ricostruzione diventa geometria invece di sparire.

Le due cose non si sistemano con la stessa leva, e nessun valore intermedio le
risolve entrambe. Ma le punte sono rumore ad ALTA frequenza, e uno smoothing
leggero le abbatte lasciando intatta la forma larga — che e' proprio cio' che
alla densita' alta era venuto bene.

Quindi: si genera ALTO, si smussa, si riduce. Costa zero crediti.

⚠️ Lo smoothing va MISURATO, non regolato a sentimento: lo script stampa di
quanto si e' spostata la superficie. Se lo spostamento massimo si avvicina alla
profondita' del rilievo dello stemma, lo si sta appiattendo.
"""
import bpy, sys, os
from mathutils import Vector

argomenti = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argomenti) < 2:
    raise SystemExit("uso: ... -- <in.glb> <out.glb> [--tri N] [--smussa N]")
SRC, DEST = argomenti[0], argomenti[1]
TRI = 60000
SMUSSA = 3
for i, a in enumerate(argomenti):
    if a == "--tri":
        TRI = int(argomenti[i + 1])
    if a == "--smussa":
        SMUSSA = int(argomenti[i + 1])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=SRC)

o = max((x for x in bpy.data.objects if x.type == 'MESH'),
        key=lambda x: len(x.data.vertices))
for x in list(bpy.data.objects):
    if x is not o:
        bpy.data.objects.remove(x, do_unlink=True)

prima_v = len(o.data.vertices)
prima_t = sum(len(p.vertices) - 2 for p in o.data.polygons)
originali = [v.co.copy() for v in o.data.vertices]
print("in:  %d vertici, %d triangoli" % (prima_v, prima_t))

bpy.ops.object.select_all(action='DESELECT')
o.select_set(True)
bpy.context.view_layer.objects.active = o

## ⚠️ Le normali custom vanno tolte PRIMA di toccare la geometria, o lo
## smoothing muove i vertici lasciando le normali dov'erano e la superficie si
## copre di brulichio — lo stesso guasto gia' visto sul corpo del protagonista.
if o.data.has_custom_normals:
    bpy.ops.mesh.customdata_custom_splitnormals_clear()

if SMUSSA > 0:
    m = o.modifiers.new("Smussa", 'SMOOTH')
    m.factor = 0.5
    m.iterations = SMUSSA
    bpy.ops.object.modifier_apply(modifier=m.name)

    spostamenti = [(v.co - originali[i]).length for i, v in enumerate(o.data.vertices)]
    spostamenti.sort()
    print("smussatura: spostamento mediano %.5f m, 99%% %.5f, massimo %.5f"
          % (spostamenti[len(spostamenti) // 2],
             spostamenti[int(len(spostamenti) * 0.99)], spostamenti[-1]))

dopo_smussa = sum(len(p.vertices) - 2 for p in o.data.polygons)
if TRI and dopo_smussa > TRI:
    d = o.modifiers.new("Riduci", 'DECIMATE')
    d.ratio = TRI / float(dopo_smussa)
    bpy.ops.object.modifier_apply(modifier=d.name)

for p in o.data.polygons:
    p.use_smooth = True

fine_v = len(o.data.vertices)
fine_t = sum(len(p.vertices) - 2 for p in o.data.polygons)
print("out: %d vertici, %d triangoli" % (fine_v, fine_t))

o.hide_set(False)
o.hide_viewport = False
o.hide_render = False
bpy.ops.object.select_all(action='DESELECT')
o.select_set(True)
bpy.context.view_layer.objects.active = o
bpy.ops.export_scene.gltf(filepath=DEST, export_format='GLB', use_selection=True,
                          export_animations=False, export_yup=True, export_apply=False)
print("SCRITTO:", DEST, os.path.getsize(DEST), "byte")
