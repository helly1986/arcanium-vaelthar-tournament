# -*- coding: utf-8 -*-
"""L'Arco di Spirito Sylvorn: dal GLB di Tripo al prop di gioco.

    blender --background --factory-startup --python arcanium/tools/prepara_arco_spirito.py -- \
        <tripo.glb> <uscita.glb> [cartella_render]

Quattro passaggi, e ognuno stampa quello che ha misurato:

  1. VIA LA CORDA dalla mesh. Tripo l'ha modellata come un tubo fisso fra le
     due punte: in gioco la disegna `arcanium/systems/world/corda_arco.gd`,
     punta -> mano -> punta, cosi' si tende quando l'arciere tira. Della corda
     si tengono le misure (le due punte e l'incocco a riposo) che quel nodo
     usa come posizioni di riposo.
  2. L'IMPUGNATURA ALL'ORIGINE: il mount della mano E' la mano, e il transform
     del BoneAttachment non deve compensare mezzo metro di offset.
  3. TEXTURE DI EMISSIONE: lo Spirito (il teal) si illumina da solo, il legno
     dell'impugnatura no. Si ricava dalla basecolor per colore.
  4. Export GLB con le texture dentro, come gli altri pezzi Sylvorn.

Il GLB di Tripo arriva come ZUPPA DI TRIANGOLI (899 parti sconnesse su 5088
facce): la corda non e' "una parte", e si trova per GEOMETRIA. E' un tubo
quadro di 5 mm fatto di 24 TRIANGOLI LUNGHI — ognuno va da una punta fino
all'incocco, mezzo metro in un triangolo solo — piu' il rombo dell'incocco a
meta'. Si cancellano le facce i cui vertici stanno tutti entro `RAGGIO` dalla
spezzata punta-incocco-punta E che sono lunghe (le pareti del tubo) o dentro
la scatola dell'incocco. I tappi dei tubi, che sono minuscoli e sepolti nel
legno delle punte, restano: toccarli vorrebbe dire rischiare le punte.

⚠️ Il primo tentativo cercava i vertici per fetta di z, come per un tubo
segmentato: ha trovato tutti i vertici e cancellato solo il tratto centrale,
perche' i triangoli lunghi hanno un vertice fuori dalla fascia di z a ogni
estremo. Guardare il render, non il conteggio.
"""
import bpy, bmesh, sys, os, json
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]
RENDER = argv[2] if len(argv) > 2 else ""

## Dove sta la corda, in coordinate Blender (Z su) del GLB di Tripo — misurato
## sui triangoli lunghi: asse y = -0.003; il tubo basso va da (0.172, 0.050)
## a (0.1425, 0.480), quello alto da (0.1385, 0.532) a (0.1205, 0.9385); in
## mezzo il rombo dell'incocco.
SPEZZATA = [Vector((0.172, -0.003, 0.050)), Vector((0.1425, -0.003, 0.480)),
            Vector((0.1385, -0.003, 0.532)), Vector((0.1205, -0.003, 0.9385))]
RAGGIO = 0.007             # tubo quadro di 5 mm: mezza diagonale 3,6 mm, e margine
LATO_LUNGO = 0.10          # una parete del tubo e' un triangolo da 40-45 cm
INCOCCO = {"x": (0.118, 0.162), "y": (-0.0085, 0.0025), "z": (0.475, 0.535)}
## L'impugnatura: la sezione di legno a meta' arco. Il centro della mano.
Z_MANO = 0.44

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
obj = [o for o in bpy.data.objects if o.type == "MESH"][0]
me = obj.data
print("IMPORT", obj.name, "verts", len(me.vertices), "facce", len(me.polygons))


def dentro(v, box):
    return all(box[k][0] <= getattr(v, k) <= box[k][1] for k in ("x", "y", "z"))


def render(nome, punti=()):
    if not RENDER:
        return
    os.makedirs(RENDER, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 700, 1100
    sc.render.film_transparent = False
    if sc.camera is None:
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
    cam = sc.camera
    xs = [(obj.matrix_world @ v.co) for v in me.vertices]
    cz = (min(p.z for p in xs) + max(p.z for p in xs)) / 2.0
    cx = (min(p.x for p in xs) + max(p.x for p in xs)) / 2.0
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.15
    cam.location = (cx, -3.0, cz)
    cam.rotation_euler = (1.5708, 0.0, 0.0)
    for i, p in enumerate(punti):
        m = bpy.data.objects.new("Punto%d" % i, None)
        m.empty_display_type = "SPHERE"
        m.empty_display_size = 0.015
        m.location = p
        sc.collection.objects.link(m)
    sc.render.filepath = os.path.join(RENDER, nome)
    bpy.ops.render.render(write_still=True)
    for o in list(sc.collection.objects):
        if o.name.startswith("Punto"):
            bpy.data.objects.remove(o)
    print("RENDER", sc.render.filepath)


render("01_prima.png")

# ─── 1. la corda ─────────────────────────────────────────────────────────────
def dist_segmento(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def vicino_alla_corda(co):
    if dentro(co, INCOCCO):
        return True
    return min(dist_segmento(co, SPEZZATA[i], SPEZZATA[i + 1]) for i in (0, 2)) <= RAGGIO


corda_f = []
for p in me.polygons:
    cs = [me.vertices[i].co for i in p.vertices]
    if not all(vicino_alla_corda(c) for c in cs):
        continue
    lati = [(cs[i] - cs[(i + 1) % len(cs)]).length for i in range(len(cs))]
    if max(lati) >= LATO_LUNGO or all(dentro(c, INCOCCO) for c in cs):
        corda_f.append(p.index)
corda_v = sorted({i for f in corda_f for i in me.polygons[f].vertices})
print("corda: %d vertici, %d facce" % (len(corda_v), len(corda_f)))

## Le misure della corda PRIMA di toglierla: punte e incocco, in coordinate
## Blender e gia' relative all'impugnatura (vedi passo 2).
cos = [me.vertices[i].co.copy() for i in corda_v]
alto = [c for c in cos if c.z >= max(c.z for c in cos) - 0.012]
basso = [c for c in cos if c.z <= min(c.z for c in cos) + 0.012]
incocco = [c for c in cos if dentro(c, INCOCCO)]


def media(cs):
    return sum(cs, Vector()) / len(cs)


p_alto, p_basso, p_incocco = media(alto), media(basso), media(incocco)
print("punta alta   (blender) %.4f %.4f %.4f" % tuple(p_alto))
print("punta bassa  (blender) %.4f %.4f %.4f" % tuple(p_basso))
print("incocco      (blender) %.4f %.4f %.4f" % tuple(p_incocco))

bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table(); bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.faces[i] for i in corda_f], context="FACES")
bm.to_mesh(me); bm.free()
me.update()
print("dopo: verts", len(me.vertices), "facce", len(me.polygons))

# ─── 2. l'impugnatura all'origine ────────────────────────────────────────────
mano = [v.co for v in me.vertices if abs(v.co.z - Z_MANO) <= 0.02 and v.co.x < 0.05]
c_mano = media(mano)
c_mano.z = Z_MANO
print("impugnatura  (blender) %.4f %.4f %.4f  (%d vertici)" % (c_mano.x, c_mano.y, c_mano.z, len(mano)))
for v in me.vertices:
    v.co -= c_mano
p_alto -= c_mano; p_basso -= c_mano; p_incocco -= c_mano
me.update()


def godot(p):
    ## glTF/Godot: Y su, e la y di Blender diventa -z.
    return (round(p.x, 4), round(p.z, 4), round(-p.y, 4))


misure = {
    "punta_alta": godot(p_alto),
    "punta_bassa": godot(p_basso),
    "incocco": godot(p_incocco),
    "corda_vertici": len(corda_v),
    "corda_facce": len(corda_f),
}
xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
misure["ingombro_godot"] = {"x": (round(min(xs), 4), round(max(xs), 4)),
                            "y": (round(min(zs), 4), round(max(zs), 4)),
                            "z": (round(-max(ys), 4), round(-min(ys), 4))}
print("MISURE", json.dumps(misure))

render("02_senza_corda.png", punti=[p_alto, p_basso, p_incocco])

# ─── 3. emissione: lo Spirito si illumina ────────────────────────────────────
import numpy as np
mat = me.materials[0]
bsdf = [n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
tex = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image][0]
img = tex.image
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
r, g, b = px[..., 0], px[..., 1], px[..., 2]
## Teal: verde e blu alti e vicini fra loro, rosso basso. Il legno e' bruno
## (rosso sopra il verde) e non passa; la gemma turchese passa.
maschera = (g > r * 1.35) & (b > r * 1.2) & (g > 0.22)
peso = np.clip((g - r * 1.35) / 0.25, 0.0, 1.0) * maschera
em = px.copy()
em[..., 0] *= peso; em[..., 1] *= peso; em[..., 2] *= peso; em[..., 3] = 1.0
print("emissione: %.1f%% dei texel" % (100.0 * maschera.mean()))
## I nomi delle immagini diventano il suffisso dei file che Godot estrae
## accanto al GLB (`<glb>_<immagine>.jpg`): "base_color" come sugli altri
## pezzi Sylvorn, non il nome del file ripetuto due volte.
img_em = bpy.data.images.new("emissive", w, h, alpha=False)
img_em.pixels = em.ravel().tolist()
img_em.pack()
n_em = mat.node_tree.nodes.new("ShaderNodeTexImage")
n_em.image = img_em
n_em.location = (tex.location.x, tex.location.y - 320)
mat.node_tree.links.new(n_em.outputs["Color"], bsdf.inputs["Emission Color"])
## Sotto 1 resta `emissiveFactor` nel GLB (sopra servirebbe un'estensione):
## 0.7 lascia leggere la texture delle spire invece di spianarle in un neon.
bsdf.inputs["Emission Strength"].default_value = 0.7
mat.name = "arco_di_spirito_sylvorn"
img.name = "base_color"

# ─── 4. export ───────────────────────────────────────────────────────────────
obj.name = "Arco"
me.name = "Arco"
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", use_selection=True,
                          export_apply=True, export_animations=False, export_lights=False,
                          export_cameras=False, export_yup=True, export_image_format="AUTO")
print("EXPORT", DST, os.path.getsize(DST), "byte")
with open(os.path.splitext(DST)[0] + "_misure.json", "w", encoding="utf-8") as f:
    json.dump(misure, f, indent=2)
