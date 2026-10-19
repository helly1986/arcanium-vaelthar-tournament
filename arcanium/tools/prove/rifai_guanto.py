# -*- coding: utf-8 -*-
"""Il bracciale a SEI dita si aggiusta: si butta il guanto e si rifa' dal corpo.

E' quello che farebbe un artista 3D ricevuto un pezzo sbagliato dal generatore:
non lo si rigenera sperando meglio, si tiene la parte buona e si rifa' quella
rotta. La manica dal gomito al polso Meshy l'ha fatta bene; la mano no.

  1. si posa il pezzo generato come fa la pipeline
  2. si TAGLIA al polso — non a occhio: per ogni vertice si guarda su quale osso
     pesa il punto del corpo piu' vicino. Pesa su mano/dita -> e' guanto, via.
  3. si RICAVA il guanto dalla superficie della mano del corpo, staccata e
     ingrossata: quattro dita e un pollice, per costruzione
  4. si conforma la manica col vertex group di aderenza (docs/13)

    blender --background --factory-startup --python rifai_guanto.py
"""
import bpy, bmesh, os
from mathutils import Vector
from mathutils.kdtree import KDTree

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
PEZZO = RADICE + "assets/characters/armor/bracciali_prima_veglia.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"

LATO = "Left"
## le ossa che definiscono "questa e' mano", e quelle che definiscono "e' manica"
OSSA_MANO = ["Hand", "ThumbMetacarpal", "ThumbProximal", "ThumbDistal",
             "IndexProximal", "IndexIntermediate", "IndexDistal",
             "MiddleProximal", "MiddleIntermediate", "MiddleDistal",
             "RingProximal", "RingIntermediate", "RingDistal",
             "LittleProximal", "LittleIntermediate", "LittleDistal"]
OSSA_MANICA = ["LowerArm", "LowerArm_twist_01", "UpperArm"]

STACCO_GUANTO = 0.006   # un guanto sta aderente: pochi millimetri
SPESSORE_GUANTO = 0.006
STACCO_MANICA = 0.009
SOGLIA_MANO = 0.5        # peso minimo perche' un vertice del corpo sia "mano"


def vicini_di(ob):
    """Per ogni vertice, gli indici dei vertici collegati da uno spigolo."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    fuori = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    bm.free()
    return fuori


def liscia_campo(valori, vicini, giri=8, forza=0.65):
    """Media il campo scalare coi vicini, PRIMA di tagliarlo.

    ⚠️ E' questo che toglie i denti di sega. Tagliare su una soglia vertice per
    vertice da' un bordo che segue il rumore dei pesi: frastagliato, e con buchi
    dove un vertice isolato sta appena sotto. Lisciando il campo prima, il bordo
    diventa una curva e i buchi si richiudono da soli.
    """
    v = list(valori)
    for _ in range(giri):
        nuovo = []
        for i, x in enumerate(v):
            vv = vicini[i]
            if not vv:
                nuovo.append(x)
                continue
            nuovo.append(x * (1.0 - forza) + (sum(v[j] for j in vv) / len(vv)) * forza)
        v = nuovo
    return v


def taglia_su_campo(ob, campo, soglia=0.5, tieni_sotto=True):
    """Taglia la mesh ESATTAMENTE sulla curva di livello del campo.

    ⚠️ Lisciare il campo NON basta: se poi si cancellano VERTICI interi il bordo
    puo' solo seguire gli spigoli esistenti, e viene a scaletta lo stesso. Qui si
    spezzano gli spigoli che attraversano la soglia nel punto esatto — cosi' il
    bordo cade dove il campo vale davvero `soglia`, e la scaletta sparisce.
    """
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    val = {v: campo[v.index] for v in bm.verts}

    incroci = []
    for e in list(bm.edges):
        a, b = e.verts
        va, vb = val[a], val[b]
        if (va - soglia) * (vb - soglia) < 0.0:
            incroci.append((e, (soglia - va) / (vb - va)))
    for e, t in incroci:
        try:
            _, nv = bmesh.utils.edge_split(e, e.verts[0], t)
            val[nv] = soglia
        except (ValueError, RuntimeError):
            pass

    eps = 1e-9
    if tieni_sotto:
        via = [v for v in bm.verts if val.get(v, 0.0) > soglia + eps]
    else:
        via = [v for v in bm.verts if val.get(v, 0.0) < soglia - eps]
    bmesh.ops.delete(bm, geom=via, context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return len(incroci), len(via)


def attivo(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def bbox(o):
    co = [o.matrix_world @ v.co for v in o.data.vertices]
    return (Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co))),
            Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co))))


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=CORPO)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
corpo = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
corpo.name = "Corpo"


def osso(n):
    return rig.matrix_world @ rig.data.bones[n].head_local


## ─── indice dei pesi del corpo, per sapere "di chi e'" ogni punto ───────────
gruppi = {g.name: g.index for g in corpo.vertex_groups}
idx_mano = {gruppi[LATO + n] for n in OSSA_MANO if LATO + n in gruppi}
idx_manica = {gruppi[LATO + n] for n in OSSA_MANICA if LATO + n in gruppi}
print("gruppi mano: %d, manica: %d" % (len(idx_mano), len(idx_manica)))

kd = KDTree(len(corpo.data.vertices))
for i, v in enumerate(corpo.data.vertices):
    kd.insert(corpo.matrix_world @ v.co, i)
kd.balance()


def e_mano(punto_mondo):
    """Il punto del corpo piu' vicino pesa piu' sulla mano o sulla manica?"""
    _, i, _ = kd.find(punto_mondo)
    p_mano = p_manica = 0.0
    for g in corpo.data.vertices[i].groups:
        if g.group in idx_mano:
            p_mano += g.weight
        elif g.group in idx_manica:
            p_manica += g.weight
    return p_mano > p_manica


## ─── 1. il pezzo generato, posato come fa la pipeline ───────────────────────
prima = set(bpy.data.objects.keys())
bpy.ops.import_scene.gltf(filepath=PEZZO)
nuovi = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - prima]
m = max((o for o in nuovi if o.type == 'MESH'), key=lambda o: len(o.data.vertices))
for o in nuovi:
    if o is not m:
        bpy.data.objects.remove(o, do_unlink=True)
attivo(m)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.mesh.separate(type='LOOSE')
bpy.ops.object.mode_set(mode='OBJECT')
tronconi = sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
                  key=lambda o: len(o.data.vertices), reverse=True)
manica = None
for t in tronconi[:2]:
    mn, mx = bbox(t)
    if (mn.x + mx.x) / 2 > 0:
        manica = t
    else:
        bpy.data.objects.remove(t, do_unlink=True)
for t in tronconi[2:]:
    bpy.data.objects.remove(t, do_unlink=True)
manica.name = "Manica"

mn, mx = bbox(manica)
alto, punta = osso(LATO + "LowerArm"), osso(LATO + "MiddleDistal")
direzione = punta - alto
lung = direzione.length * 1.06
direzione.normalize()
scala = lung / (mx.z - mn.z)
manica.rotation_mode = 'QUATERNION'
manica.rotation_quaternion = Vector((0, 0, -1)).rotation_difference(direzione)
manica.scale = (scala, scala, scala)
bpy.context.view_layer.update()
mn2, mx2 = bbox(manica)
manica.location += alto - ((mn2 + mx2) / 2 - direzione * (lung / 2))
bpy.context.view_layer.update()
attivo(manica)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

## ─── 2. via il guanto sbagliato ─────────────────────────────────────────────
mw = manica.matrix_world
campo = [1.0 if e_mano(mw @ v.co) else 0.0 for v in manica.data.vertices]
campo = liscia_campo(campo, vicini_di(manica))
n_inc, n_via = taglia_su_campo(manica, campo, 0.5, tieni_sotto=True)
print("taglio al polso: %d spigoli spezzati sulla curva, %d vertici tolti" % (n_inc, n_via))

## ─── 3. il guanto ricavato dal corpo ────────────────────────────────────────
grezzo = []
for v in corpo.data.vertices:
    grezzo.append(sum(g.weight for g in v.groups if g.group in idx_mano))
mano_liscia = liscia_campo(grezzo, vicini_di(corpo), giri=6, forza=0.6)
dentro = {i for i, x in enumerate(mano_liscia) if x >= SOGLIA_MANO}
print("mano del corpo: %d vertici (grezzo %d)" %
      (len(dentro), sum(1 for x in grezzo if x >= SOGLIA_MANO)))

attivo(corpo)
bpy.ops.object.duplicate()
guanto = bpy.context.active_object
guanto.name = "Guanto"
n_inc, n_via = taglia_su_campo(guanto, mano_liscia, SOGLIA_MANO, tieni_sotto=False)
print("guanto: %d spigoli spezzati sulla curva, %d vertici tolti" % (n_inc, n_via))
guanto.vertex_groups.clear()

attivo(guanto)
## ⚠️ Una MANO non e' un arto: sono cinque tubi sottili con pieghe profonde in
## mezzo. Staccare lungo la normale li fa compenetrare nelle pieghe; lisciare per
## rimediare li COLLASSA, perche' la lisciatura laplaciana restringe il volume e
## su un tubo sottile lo chiude. Provate e guardate tutte e due.
##
## Lo strumento giusto e' il VOXEL REMESH: ricostruisce la superficie campionando
## un volume, quindi fonde le pieghe da solo e NON collassa niente. E' il modo
## standard per ottenere una forma "a manopola" da geometria sottile.
d = guanto.modifiers.new("Stacco", 'DISPLACE')
d.mid_level = 0.0
d.strength = STACCO_GUANTO
bpy.ops.object.modifier_apply(modifier=d.name)
rm = guanto.modifiers.new("Remesh", 'REMESH')
rm.mode = 'VOXEL'
## ⚠️ La grana del voxel deve essere PIU' FINE dello spessore del guscio, o il
## guscio sparisce: a 4,5 mm su uno stacco di 3,5 il remesh si e' mangiato tutto
## e sono rimasti 590 vertici di schegge.
rm.voxel_size = 0.0028
bpy.ops.object.modifier_apply(modifier=rm.name)
sm = guanto.modifiers.new("Liscia", 'SMOOTH')
sm.factor = 0.30
sm.iterations = 2
bpy.ops.object.modifier_apply(modifier=sm.name)
sd = guanto.modifiers.new("Spessore", 'SOLIDIFY')
sd.thickness = SPESSORE_GUANTO
sd.offset = 1.0
bpy.ops.object.modifier_apply(modifier=sd.name)
print("guanto ricavato: %d vertici" % len(guanto.data.vertices))

## ─── 4. la manica si conforma, col vertex group di aderenza ─────────────────
g = manica.vertex_groups.new(name="aderenza")
mw = manica.matrix_world
inv_corpo = corpo.matrix_world.inverted()
for v in manica.data.vertices:
    p = mw @ v.co
    ok, loc, nor, _ = corpo.closest_point_on_mesh(inv_corpo @ p)
    if not ok:
        g.add([v.index], 0.0, 'REPLACE')
        continue
    lm = corpo.matrix_world @ loc
    nm = (corpo.matrix_world.to_3x3() @ nor).normalized()
    dist = (p - lm).dot(nm)
    peso = 1.0 if dist < STACCO_MANICA else (
        0.0 if dist > STACCO_MANICA + 0.022 else 1.0 - (dist - STACCO_MANICA) / 0.022)
    g.add([v.index], peso, 'REPLACE')
attivo(manica)
sw = manica.modifiers.new("Conforma", 'SHRINKWRAP')
sw.target = corpo
sw.wrap_method = 'NEAREST_SURFACEPOINT'
sw.wrap_mode = 'OUTSIDE_SURFACE'
sw.offset = STACCO_MANICA
sw.vertex_group = "aderenza"
bpy.ops.object.modifier_apply(modifier=sw.name)

## ─── resa ───────────────────────────────────────────────────────────────────
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.materials.clear()
mp = bpy.data.materials.new("pelle")
mp.diffuse_color = (0.72, 0.55, 0.47, 1)
mp.roughness = 0.85
corpo.data.materials.append(mp)
ma = bpy.data.materials.new("acciaio")
ma.diffuse_color = (0.24, 0.44, 0.72, 1)
ma.metallic = 1.0
ma.roughness = 0.30
manica.data.materials.append(ma)
mg = bpy.data.materials.new("guanto")
mg.diffuse_color = (0.62, 0.30, 0.16, 1)   # cuoio: si distingue dalla manica
mg.roughness = 0.55
guanto.data.materials.append(mg)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.render.resolution_x = 1250
sc.render.resolution_y = 950
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.lens = 60


def scatta(bersaglio, offset, nome):
    cam.location = bersaglio + Vector(offset)
    dd = bersaglio - cam.location
    cam.rotation_euler = dd.to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = FUORI + nome
    bpy.ops.render.render(write_still=True)
    print("reso:", nome)


mano = osso(LATO + "Hand")
scatta(mano + Vector((0.10, 0, -0.05)), (0.34, -0.72, 0.30), "rifatto_mano")
braccio = (osso(LATO + "LowerArm") + mano) / 2
scatta(braccio, (0.25, -0.95, 0.30), "rifatto_braccio")
print("FATTO")
