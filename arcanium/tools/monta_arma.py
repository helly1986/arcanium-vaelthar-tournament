"""Monta un'ARMA IMPUGNATA fatta con Tripo P2 (FBX quad) per la mano del
giocatore: FBX in, GLB out, come i campioni ma senza scheletro.

Si esegue DENTRO Blender, dal ponte (arcanium/tools/ponte_blender.py):

    exec(open(".../monta_arma.py").read())
    monta("martello_da_forgia", lunghezza=0.70, presa=0.12)

- La sorgente e' assets/weapons/<nome>/sorgenti/<nome>.fbx (con la cartella
  .fbm di Tripo accanto, come per i campioni).
- Il passaggio obbligato in Blender (richiesta dell'autore, 2026-10-21, per
  ogni pezzo): `controlla_e_ripara` di monta_campione.py, che ispeziona quad,
  buchi e non-manifold, salda e si ferma se resta sporca.
- L'asse lungo dell'arma va in verticale (Z di Blender, +Y in Godot), con la
  testa o la lama in alto: decide `testa_in_alto`, che si guarda a occhio sul
  concept (l'arma nasce in piedi come nel concept, o coricata).
- `lunghezza` (metri) e' la misura vera da punta a punta; `presa` e' la quota
  dell'impugnatura come frazione della lunghezza dal basso: li' va l'origine,
  dove il nodo `Sword` della mano tiene i suoi modelli (lama lungo +Y, presa
  nell'origine: la stessa convenzione della Spada del Senza Nome).
- `tinta`: (tonalita', saturazione, luce) per `smorza_tinta`, se serve
  spegnerla (dark fantasy).

Esce assets/weapons/<nome>/<nome>.glb, solo la mesh, texture JPEG dentro.
"""
import os

import bpy

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
MONTA_CAMPIONE = RADICE + "arcanium/tools/monta_campione.py"


def monta(nome, lunghezza, presa, testa_in_alto=True, tinta=None):
    ns = {"__name__": "monta_arma"}
    exec(compile(open(MONTA_CAMPIONE, encoding="utf-8").read(), MONTA_CAMPIONE, "exec"), ns)
    cartella = RADICE + "assets/weapons/%s/" % nome
    fbx = cartella + "sorgenti/%s.fbx" % nome

    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    bpy.ops.import_scene.fbx(filepath=fbx, use_image_search=True)
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

    ## Le cuciture UV saldate, poi il passaggio obbligato sulla topologia.
    _salda(me)
    ns["controlla_e_ripara"](me.name)

    ## L'asse lungo in verticale, la testa in alto.
    import mathutils
    co = [v.co.copy() for v in me.data.vertices]
    mn = mathutils.Vector((min(p.x for p in co), min(p.y for p in co), min(p.z for p in co)))
    mx = mathutils.Vector((max(p.x for p in co), max(p.y for p in co), max(p.z for p in co)))
    misure = mx - mn
    asse = max(range(3), key=lambda i: misure[i])
    if asse == 0:
        me.data.transform(mathutils.Matrix.Rotation(1.5707963, 4, 'Y'))
    elif asse == 1:
        me.data.transform(mathutils.Matrix.Rotation(-1.5707963, 4, 'X'))
    if not testa_in_alto:
        me.data.transform(mathutils.Matrix.Rotation(3.1415927, 4, 'X'))
    co = [v.co for v in me.data.vertices]
    basso, alto = min(p.z for p in co), max(p.z for p in co)
    k = lunghezza / (alto - basso)
    me.data.transform(mathutils.Matrix.Scale(k, 4))
    co = [v.co for v in me.data.vertices]
    basso = min(p.z for p in co)
    cx = (min(p.x for p in co) + max(p.x for p in co)) / 2
    cy = (min(p.y for p in co) + max(p.y for p in co)) / 2
    me.data.transform(mathutils.Matrix.Translation((-cx, -cy, -(basso + presa * lunghezza))))
    me.data.update()
    print("arma %s: asse lungo %s, scala x%.3f, %.2f m, presa a %.0f%% dal basso"
          % (nome, "XYZ"[asse], k, lunghezza, presa * 100))

    ## La texture col nome giusto e in JPEG (come i campioni), spenta se serve.
    if tinta is not None:
        ns["smorza_tinta"](tinta[0], saturazione=tinta[1], valore=tinta[2], nome_mesh=me.name)
    ## L'esportatore glTF chiama l'immagine come il suo FILE: impacchettata e
    ## col percorso giusto esce `<nome>_Baked_BaseColor.jpg` accanto al GLB.
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
    print("arma %s: %d vertici, %d facce -> %s" % (nome, len(me.data.vertices), len(me.data.polygons), uscita))
    return uscita


def _salda(me):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bm.to_mesh(me.data)
    bm.free()
    me.data.update()
