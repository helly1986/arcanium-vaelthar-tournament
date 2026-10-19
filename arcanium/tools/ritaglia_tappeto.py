# -*- coding: utf-8 -*-
"""Da quadratone a macchia: ritaglia e alleggerisce un tappeto piatto.

    blender -b --python arcanium/tools/ritaglia_tappeto.py -- ingresso.glb uscita.glb [facce]

⚠️ PERCHE' SERVE. I generatori 3D, quando gli si chiede un tappeto "molto largo
e senza altezza", producono una LASTRA RETTANGOLARE: la texture e' bellissima e
il bordo e' un quadrato. In uno scatter da millecinquecento istanze quel bordo
si riconosce, e il tappeto si legge come una piastrellatura.

Qui il bordo diventa irregolare tagliando le facce oltre un raggio che varia
con l'angolo (rumore periodico, niente boolean: piu' semplice e non lascia
n-gon sporchi). Poi si decima.

⚠️ La decimazione qui e' LEGITTIMA, al contrario che sui grappoli. Una lastra
piatta e' una superficie unica con UV planari: il collapse ha spigoli condivisi
su cui lavorare e non la disintegra. Sul sottobosco a grappolo (sassolini,
funghi, rametti) la stessa operazione produceva coriandoli — vedi la memoria
[[generatori-3d-erba-sotto-mille]].

Costa ZERO crediti: il pezzo generato si tiene, si butta solo il bordo.
"""
import bpy, bmesh, math, sys, os

argv = sys.argv[sys.argv.index("--") + 1:]
SORGENTE = argv[0]
USCITA = argv[1]
FACCE = int(argv[2]) if len(argv) > 2 else 320

## Quanto il bordo rientra e sporge. 0 = cerchio netto, 0.35 = molto frastagliato.
## ⚠️ Tarato GUARDANDO IL RENDER: a 0.30 il tappeto spariva — la lastra ha
## poche facce grandi al centro e i denti sul bordo, quindi un taglio profondo
## si mangia proprio la parte che si vede.
## ⚠️ 0 = NESSUN taglio, solo alleggerimento. Scoperto guardando i numeri: su
## questa edera la lastra centrale e' 42 triangoli e gli altri ~1900 sono i
## DENTELLI del bordo, cioe' le foglie sporgenti. Il bordo non e' un quadrato
## netto: e' gia' irregolare, ed e' la parte che si vede. Tagliarlo buttava
## proprio quella e lasciava una piastrella nuda.
IRREGOLARITA = 0.0
## Quante gobbe attorno al giro: poche = macchia larga, tante = merlettatura.
GOBBE = 7


def bbox(oggetti):
    import mathutils
    mn = mathutils.Vector((1e9,) * 3)
    mx = mathutils.Vector((-1e9,) * 3)
    for o in oggetti:
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            mn = mathutils.Vector(tuple(min(mn[i], w[i]) for i in range(3)))
            mx = mathutils.Vector(tuple(max(mx[i], w[i]) for i in range(3)))
    return mn, mx


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SORGENTE)

mesh_obj = [o for o in bpy.context.scene.objects if o.type == 'MESH']
mn, mx = bbox(mesh_obj)
centro_x = (mn.x + mx.x) / 2.0
centro_y = (mn.y + mx.y) / 2.0
## Il raggio di riferimento e' il SEMILATO MINORE: usando il maggiore il taglio
## mangerebbe i lati corti e resterebbe una lente, non una macchia.
raggio = min((mx.x - mn.x), (mx.y - mn.y)) / 2.0

prima = 0
dopo = 0
for ob in mesh_obj:
    me = ob.data
    me.calc_loop_triangles()
    prima += len(me.loop_triangles)

    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)

    ## Si giudica la faccia sul suo CENTRO, non sui vertici: tagliando per
    ## vertice si aprono buchi dove un solo angolo esce dal bordo.
    ## ⚠️ A IRREGOLARITA 0 il taglio NON va solo "attenuato": va SALTATO. La
    ## soglia sarebbe il semilato, e gli angoli di un rettangolo stanno a 1.41
    ## semilati — quindi taglierebbe comunque, ed e' cosi' che il tappeto e'
    ## sparito due volte di fila.
    morte = []
    for f in (bm.faces if IRREGOLARITA > 0.0 else []):
        c = f.calc_center_median()
        dx = c.x - centro_x
        dy = c.y - centro_y
        d = math.sqrt(dx * dx + dy * dy)
        ang = math.atan2(dy, dx)
        soglia = raggio * (1.0 - IRREGOLARITA * 0.5
                           + IRREGOLARITA * 0.5 * math.sin(GOBBE * ang)
                           + IRREGOLARITA * 0.25 * math.sin(GOBBE * 2.7 * ang + 1.3))
        if d > soglia:
            morte.append(f)
    if morte and len(morte) < len(bm.faces):
        bmesh.ops.delete(bm, geom=morte, context='FACES')
    ## Vertici rimasti orfani dopo il taglio
    soli = [v for v in bm.verts if not v.link_faces]
    if soli:
        bmesh.ops.delete(bm, geom=soli, context='VERTS')
    bm.to_mesh(me)
    bm.free()
    me.update()

    me.calc_loop_triangles()
    resta = len(me.loop_triangles)
    if FACCE > 0 and resta > FACCE:
        bpy.context.view_layer.objects.active = ob
        m = ob.modifiers.new("dec", 'DECIMATE')
        m.decimate_type = 'COLLAPSE'
        m.ratio = FACCE / float(resta)
        bpy.ops.object.modifier_apply(modifier="dec")
    me.calc_loop_triangles()
    dopo += len(me.loop_triangles)

os.makedirs(os.path.dirname(USCITA), exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=USCITA, export_format='GLB',
                          use_selection=True, export_yup=True, export_apply=True)
print("RITAGLIO %s: %d -> %d triangoli" % (os.path.basename(USCITA), prima, dopo))
