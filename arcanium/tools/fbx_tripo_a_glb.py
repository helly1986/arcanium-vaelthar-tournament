"""Porta un oggetto statico generato con Tripo (FBX, preset Blender) a GLB per Godot.

Per i pezzi d'ambiente, senza scheletro: sassi, muri, colonne. I corpi con il
rig seguono un'altra strada (docs/05 §4-ter).

Cosa fa:
  - importa l'FBX e unisce le mesh in un solo oggetto;
  - applica rotazione e scala, e porta l'origine al centro della base
    (l'arena appoggia i pezzi a terra misurandone l'ingombro);
  - la texture resta quella di Tripo: Godot la estrae accanto al GLB come
    `<glb>_<nome>_basecolor.jpg` (il nome viene dal file scaricato, quindi si
    esporta da Tripo col nome del pezzo);
  - esporta il GLB con la texture dentro, e stampa triangoli e misure.

Uso (Blender in background):
  blender --background --factory-startup --python arcanium/tools/fbx_tripo_a_glb.py -- \
      <sorgente.fbx> <uscita.glb> <nome>
"""

import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
sorgente, uscita, nome = argv[0], argv[1], argv[2]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=sorgente)

mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(o in mesh)
bpy.context.view_layer.objects.active = mesh[0]
if len(mesh) > 1:
    bpy.ops.object.join()
ogg = bpy.context.view_layer.objects.active
ogg.name = nome
ogg.data.name = nome

## Via i genitori vuoti dell'FBX, tenendo la posa nel mondo.
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
for o in list(bpy.context.scene.objects):
    if o is not ogg:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

## `corica`: i pezzi piatti (tappeti) che Tripo fa nascere in piedi si
## coricano, portando l'asse piu' sottile in verticale. Si ruotano i VERTICI:
## l'oggetto ha gia' le trasformazioni applicate (tripo-p2-flusso, trappola 4).
opzioni = argv[3:]
if "corica" in opzioni or "corica-" in opzioni:
    ## `corica-` gira dall'altra parte: se il disegno finisce sotto.
    segno = -1 if "corica-" in opzioni else 1
    from mathutils import Matrix
    import math
    vs0 = [v.co for v in ogg.data.vertices]
    dims = [max(v[k] for v in vs0) - min(v[k] for v in vs0) for k in range(3)]
    sottile = dims.index(min(dims))
    if sottile == 0:
        rot = Matrix.Rotation(math.radians(90 * segno), 4, "Y")
    elif sottile == 1:
        rot = Matrix.Rotation(math.radians(90 * segno), 4, "X")
    else:
        rot = Matrix.Identity(4)
    ogg.data.transform(rot)
    ## E si schiaccia: Tripo li fa a cupola o coi bordi arricciati, spessi fino
    ## a un quinto del lato; un tappeto e' alto un centimetro e mezzo ogni metro.
    vs1 = [v.co for v in ogg.data.vertices]
    lato = max(max(v.x for v in vs1) - min(v.x for v in vs1), max(v.y for v in vs1) - min(v.y for v in vs1))
    zmin = min(v.z for v in vs1)
    alto = max(v.z for v in vs1) - zmin
    if alto > 0:
        k = (lato * 0.015) / alto
        for v in ogg.data.vertices:
            v.co.z = zmin + (v.co.z - zmin) * k
    ogg.data.update()
    print("FBX_A_GLB: coricato (asse sottile %s)" % "xyz"[sottile])

## `ruota=G`: gira i vertici di G gradi intorno alla verticale (un modulo di
## muro nato di fianco: il fronte deve guardare -y in Blender, +z in Godot).
for o in opzioni:
    if o.startswith("ruota="):
        from mathutils import Matrix
        import math
        ogg.data.transform(Matrix.Rotation(math.radians(float(o.split("=")[1])), 4, "Z"))
        ogg.data.update()
        print("FBX_A_GLB: girato di %s gradi" % o.split("=")[1])

## Origine al centro della base.
vs = [ogg.matrix_world @ v.co for v in ogg.data.vertices]
minimo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
massimo = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
base = Vector(((minimo.x + massimo.x) / 2, (minimo.y + massimo.y) / 2, minimo.z))
for v in ogg.data.vertices:
    v.co -= base

## `scurisci=F` moltiplica tutta la texture per F; `intonaco=F` solo i pixel
## chiari e poco saturi (intonaco, legno sbiancato): Tripo li fa quasi bianchi,
## e sotto i lampadari della dimora bruciavano (dark fantasy: tinte spente).
def _ritocca(img, tutto, chiari):
    import numpy as np
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    rgb = px[:, :3]
    if chiari is not None:
        mx = rgb.max(axis=1)
        mn = rgb.min(axis=1)
        sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
        peso = np.clip((mx - 0.45) / 0.3, 0, 1) * np.clip((0.4 - sat) / 0.25, 0, 1)
        f = 1.0 - peso * (1.0 - chiari)
        rgb *= f[:, None]
        ## Un filo di calore nei chiari spenti, che non diventino grigio cemento.
        rgb[:, 0] += peso * 0.015
    if tutto is not None:
        rgb *= tutto
    px[:, :3] = np.clip(rgb, 0, 1)
    img.pixels[:] = px.ravel().tolist()
    img.update()


tutto = chiari = None
for o in opzioni:
    if o.startswith("scurisci="):
        tutto = float(o.split("=")[1])
    if o.startswith("intonaco="):
        chiari = float(o.split("=")[1])
if tutto is not None or chiari is not None:
    for img in bpy.data.images:
        if img.users and img.size[0] > 0:
            _ritocca(img, tutto, chiari)
            ## Impacchettata da qui: la modifica deve finire nel GLB, non il file.
            img.pack()
    print("FBX_A_GLB: texture ritoccata (tutto %s, chiari %s)" % (tutto, chiari))

## Le immagini con un nome corto: Godot le estrae accanto al GLB come
## `<glb>_<immagine>`, e l'esportatore glTF chiama l'immagine come il suo FILE
## (come in monta_arma.py): impacchettata e col percorso rinominato esce
## `<nome>_basecolor.jpg`, non `<nome>_tripo_image_<uuid>_0_0.jpg`.
for i, img in enumerate(im for im in bpy.data.images if im.users):
    corto = "basecolor" if i == 0 else "mappa_%d" % i
    if not img.packed_file:
        img.pack()
    img.filepath_raw = "//%s.jpg" % corto
    img.name = corto

bpy.ops.export_scene.gltf(
    filepath=uscita,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_animations=False,
    export_yup=True,
)

triangoli = sum(len(p.vertices) - 2 for p in ogg.data.polygons)
dim = massimo - minimo
print("FBX_A_GLB: %s  triangoli %d  misure (x %.2f, y %.2f, z-alto %.2f)" % (
    nome, triangoli, dim.x, dim.y, dim.z))
