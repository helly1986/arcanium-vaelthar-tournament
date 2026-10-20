# -*- coding: utf-8 -*-
"""Dal baule Tripo (una mesh sola) a un baule che si APRE: corpo + coperchio
incernierato + animazione "Apri", pronto per Godot.

    blender --background --factory-startup --python arcanium/tools/baule_apribile.py -- \
        assets/environment/kalvorn/props/baule_sylvorn.glb \
        assets/environment/kalvorn/props/baule_sylvorn_apribile.glb

Legge il GLB grezzo e ne scrive uno NUOVO: il sorgente Tripo resta com'e', e
lo script si puo' rilanciare quante volte si vuole (rilanciarlo su un baule gia'
tagliato taglierebbe due volte).

─── PERCHE' UN PIANO E NON LE PARTI ─────────────────────────────────────────
Il modello Tripo e' una zuppa di triangoli: 3.673 "componenti connesse" e
27.226 spigoli aperti su 22.016 facce, perche' ogni cucitura UV sdoppia i
vertici. Non esiste un "coperchio" da selezionare per parte connessa. Si taglia
con un piano orizzontale, e l'altezza NON e' scelta a occhio: e' dove il
profilo delle larghezze cambia regime (misurato con baule_analisi, 2026-09-12):

    z 0,09..0,51   pareti del corpo, larghe 0,91..0,96
    z 0,545..0,72  il LABBRO del coperchio, largo 0,97..1,00 (sporge)
    z 0,73..0,91   la cupola, che si stringe fino a 0,23 di profondita'

Il taglio sta a 0,55: sotto il labbro, sopra le pareti.

─── IL CARDINE ──────────────────────────────────────────────────────────────
Il lucchetto sta sulla faccia a −Y (importato da glTF: il +Z del modello, che
in gioco guarda fuori dal mucchio). Il cardine e' quindi il bordo POSTERIORE,
+Y, all'altezza del taglio: l'origine del coperchio va li', e la rotazione che
apre e' NEGATIVA attorno a X (con +θ il davanti scenderebbe).

─── L'INTERNO ───────────────────────────────────────────────────────────────
Il taglio lascia il corpo aperto sopra e il coperchio aperto sotto. La mesh e'
a doppia faccia, quindi le pareti interne si vedono con la texture esterna
(legno: passa). Il FONDO no: senza, un baule aperto e' un tubo. Si aggiunge un
pavimento dentro il corpo e un sottocoperchio, con un materiale scuro a se'.

─── COSA ARRIVA IN GODOT ────────────────────────────────────────────────────
Una scena con `Corpo` e `Coperchio` (figlio con l'origine sul cardine) e un
AnimationPlayer con "Apri": una traccia sulla ROTAZIONE del nodo Coperchio,
non uno scheletro. `baule.gd` la fa partire all'apertura.
"""
import bpy, bmesh, math, sys
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(args) < 2:
    raise SystemExit("uso: ... -- <ingresso.glb> <uscita.glb>")
INGRESSO, USCITA = args[0], args[1]

FPS = 30
Z_TAGLIO = 0.55            # misurato, vedi cappello
APERTURA_GRADI = -100.0    # negativo = il davanti sale (cardine dietro)
FRAME_APERTO = 18          # 0,6 s a 30 fps
INSET_CAPPE = 0.025        # quanto rientrano il fondo e il sottocoperchio

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS
bpy.context.scene.render.fps_base = 1.0
bpy.ops.import_scene.gltf(filepath=INGRESSO)

orig = next(o for o in bpy.data.objects if o.type == 'MESH')
mat_legno = orig.data.materials[0]
print("ingresso:", orig.name, "facce", len(orig.data.polygons), "materiale", mat_legno.name)

# ─── 1. taglio ────────────────────────────────────────────────────────────
bm = bmesh.new(); bm.from_mesh(orig.data)
geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5,
                       plane_co=Vector((0, 0, Z_TAGLIO)), plane_no=Vector((0, 0, 1)),
                       clear_inner=False, clear_outer=False)
bm.faces.ensure_lookup_table(); bm.verts.ensure_lookup_table()
bm.verts.index_update()
sopra = [f for f in bm.faces if f.calc_center_median().z > Z_TAGLIO]
sotto = [f for f in bm.faces if f.calc_center_median().z <= Z_TAGLIO]
print("dopo il taglio: %d facce sopra (coperchio), %d sotto (corpo)" % (len(sopra), len(sotto)))

def mesh_da_facce(nome, facce, sorgente_bm):
    """Copia le facce in una mesh nuova, con UV e materiale.

    I vertici si CONDIVIDONO come nel sorgente (una mappa indice -> vertice
    nuovo): il primo giro ne creava tre per faccia e il GLB era raddoppiato.
    """
    nb = bmesh.new()
    uv_src = sorgente_bm.loops.layers.uv.active
    uv_dst = nb.loops.layers.uv.new(uv_src.name if uv_src else "UVMap")
    nuovi = {}
    for f in facce:
        vs = []
        for v in f.verts:
            if v.index not in nuovi:
                nuovi[v.index] = nb.verts.new(v.co.copy())
            vs.append(nuovi[v.index])
        try:
            nf = nb.faces.new(vs)
        except ValueError:
            continue
        nf.material_index = 0
        nf.smooth = f.smooth
        if uv_src:
            for lo, ln in zip(f.loops, nf.loops):
                ln[uv_dst].uv = lo[uv_src].uv.copy()
    me = bpy.data.meshes.new(nome)
    nb.to_mesh(me); nb.free()
    me.materials.append(mat_legno)
    return me

me_corpo = mesh_da_facce("Corpo", sotto, bm)
me_cop = mesh_da_facce("Coperchio", sopra, bm)
bm.free()

corpo = bpy.data.objects.new("Corpo", me_corpo)
cop = bpy.data.objects.new("Coperchio", me_cop)
scena = bpy.context.scene
scena.collection.objects.link(corpo); scena.collection.objects.link(cop)
bpy.data.objects.remove(orig, do_unlink=True)

# ─── 2. materiale dell'interno e cappe ───────────────────────────────────
mat_interno = bpy.data.materials.new("baule_interno")
mat_interno.use_nodes = True
bsdf = mat_interno.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.055, 0.040, 0.028, 1.0)
bsdf.inputs["Roughness"].default_value = 0.92
mat_interno.use_backface_culling = False

def estensione(me):
    xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))

def aggiungi_cappa(me, z, inset):
    x0, x1, y0, y1, _, _ = estensione(me)
    x0 += inset; x1 -= inset; y0 += inset; y1 -= inset
    nb = bmesh.new(); nb.from_mesh(me)
    vs = [nb.verts.new(Vector((x, y, z))) for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1))]
    f = nb.faces.new(vs)
    if len(me.materials) < 2:
        me.materials.append(mat_interno)
    f.material_index = 1
    nb.to_mesh(me); nb.free()

ext_c = estensione(me_corpo); ext_l = estensione(me_cop)
print("corpo: X %.3f..%.3f Y %.3f..%.3f Z %.3f..%.3f" % ext_c)
print("coperchio: X %.3f..%.3f Y %.3f..%.3f Z %.3f..%.3f" % ext_l)
# pavimento dentro il corpo, un po' sotto il taglio; sottocoperchio appena sopra
aggiungi_cappa(me_corpo, Z_TAGLIO - 0.06, INSET_CAPPE)
aggiungi_cappa(me_cop, Z_TAGLIO + 0.015, INSET_CAPPE)
# ⚠️ Le normali delle cappe devono guardare verso l'interno del volume che
# chiudono... ma il materiale e' a doppia faccia: si vede comunque.

# ─── 3. il cardine: origine del coperchio sul bordo posteriore (+Y) ──────
cardine = Vector((0.0, ext_l[3], Z_TAGLIO))
for v in me_cop.vertices:
    v.co -= cardine
cop.location = cardine
cop.parent = corpo
cop.matrix_parent_inverse = corpo.matrix_world.inverted()
print("cardine a", tuple(round(c, 3) for c in cardine))

# ─── 4. l'animazione "Apri" sul coperchio ─────────────────────────────────
cop.rotation_mode = 'XYZ'
cop.rotation_euler = (0.0, 0.0, 0.0)
cop.keyframe_insert(data_path="rotation_euler", frame=0)
cop.rotation_euler = (math.radians(APERTURA_GRADI), 0.0, 0.0)
cop.keyframe_insert(data_path="rotation_euler", frame=FRAME_APERTO)
azione = cop.animation_data.action
azione.name = "Apri"
azione.use_fake_user = True
## Blender >= 4.4 ha le action a STRATI: le curve stanno in
## layers[].strips[].channelbags[].fcurves, e `Action.fcurves` non esiste piu'.
def _curve(az):
    if hasattr(az, "fcurves"):
        return list(az.fcurves)
    out = []
    for layer in az.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out

for fc in _curve(azione):
    for kp in fc.keyframe_points:
        kp.interpolation = 'BEZIER'
        kp.easing = 'EASE_OUT'
scena.frame_start = 0
scena.frame_end = FRAME_APERTO
## ⚠️ Un coperchio che rimbalza sarebbe piu' bello, ma una chiave in piu' e'
## un secondo posto da tarare a vista: prima si guarda questo in gioco.

# ─── 5. export ────────────────────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
corpo.select_set(True); cop.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=USCITA, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_apply=False, export_yup=True,
    export_image_format='AUTO', export_materials='EXPORT')
print("scritto:", USCITA)
print("facce corpo %d, coperchio %d" % (len(me_corpo.polygons), len(me_cop.polygons)))
