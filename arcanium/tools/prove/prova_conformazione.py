# -*- coding: utf-8 -*-
"""PROVA STADIO 2: la mesh generata AVVOLTA sul corpo tiene le forme?

⚠️⚠️ SUPERATA SU UN PUNTO, il 2026-08-20: qui sotto si afferma che
`OUTSIDE_SURFACE` "sposta solo i vertici che stanno DENTRO". **E' falso**, ed e'
da qui che l'errore e' entrato in `docs/13` e nella pipeline. Misurato sui
gambali: `OUTSIDE_SURFACE` muove tutto cio' che ha peso, parete esterna compresa
(1.720 vertici su 3.894 invece di 689). Il modo che muove solo cio' che sta
dentro si chiama `OUTSIDE`. Vedi `prova_wrap_mode.py`.


Il rischio da misurare: uno shrinkwrap liscio appiattisce il rilievo — le piastre
finiscono spalmate sulla pelle e resta una muta lucida. Qui si prova la versione
che il dettaglio lo CONSERVA:

  1. si separa la bassa frequenza (una copia molto lisciata: la "vestibilita'")
  2. si misura il RILIEVO come scarto fra originale e lisciata, lungo la normale
  3. si appoggia la LISCIATA sul corpo, a distanza costante (lo stacco della piastra)
  4. si rimette il rilievo sopra, lungo la NUOVA normale

Tre casi, stessa inquadratura:
  A. com'e' oggi                     (posato rigido, gomito->dita)
  B. conformato senza conservare     (shrinkwrap liscio: il controllo negativo)
  C. conformato conservando          (la proposta)
  D. come C ma dichiarato spalla->dita (copertura + aderenza insieme)

    blender --background --factory-startup --python prova_conformazione.py
"""
import bpy, os, math, bmesh
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
PEZZO = RADICE + "assets/characters/armor/bracciali_prima_veglia.glb"
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/"

STACCO = 0.012      # quanto la piastra sta staccata dalla pelle
LISCIATURE = 25     # quanto si toglie di alta frequenza per avere la "vestibilita'"


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


def carica_pezzo(nome):
    """Importa il bracciale, salda le cuciture, tiene il troncone SINISTRO."""
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
    pezzi = sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
                   key=lambda o: len(o.data.vertices), reverse=True)
    scelto = None
    for t in pezzi[:2]:
        mn, mx = bbox(t)
        if (mn.x + mx.x) / 2 > 0:
            scelto = t
        else:
            bpy.data.objects.remove(t, do_unlink=True)
    for t in pezzi[2:]:
        bpy.data.objects.remove(t, do_unlink=True)
    scelto.name = nome
    return scelto


def posa(t, su, giu, margine=1.06):
    """Lo stesso posamento rigido della pipeline di oggi."""
    mn, mx = bbox(t)
    alto, punta = osso("Left" + su), osso("Left" + giu)
    direzione = punta - alto
    lung = direzione.length * margine
    direzione.normalize()
    scala = lung / (mx.z - mn.z)
    t.rotation_mode = 'QUATERNION'
    t.rotation_quaternion = Vector((0, 0, -1)).rotation_difference(direzione)
    t.scale = (scala, scala, scala)
    bpy.context.view_layer.update()
    mn2, mx2 = bbox(t)
    t.location += alto - ((mn2 + mx2) / 2 - direzione * (lung / 2))
    bpy.context.view_layer.update()
    attivo(t)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def normali(o):
    o.data.calc_normals_split() if hasattr(o.data, "calc_normals_split") else None
    return [v.normal.copy() for v in o.data.vertices]


def conforma(t, conserva):
    """Appoggia il pezzo sul corpo. Con `conserva` il rilievo si rimette sopra."""
    originali = [v.co.copy() for v in t.data.vertices]
    n_prima = [v.normal.copy() for v in t.data.vertices]

    ## 1-2. bassa frequenza: una copia molto lisciata
    liscia = [Vector(c) for c in originali]
    if conserva:
        bm = bmesh.new()
        bm.from_mesh(t.data)
        bm.verts.ensure_lookup_table()
        vicini = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
        bm.free()
        for _ in range(LISCIATURE):
            nuovo = []
            for i, v in enumerate(liscia):
                vv = vicini[i]
                if not vv:
                    nuovo.append(v)
                    continue
                media = Vector((0, 0, 0))
                for j in vv:
                    media += liscia[j]
                nuovo.append(v.lerp(media / len(vv), 0.6))
            liscia = nuovo
        rilievo = [(originali[i] - liscia[i]).dot(n_prima[i]) for i in range(len(originali))]
    else:
        rilievo = [0.0] * len(originali)

    ## 3-4. si appoggia la bassa frequenza sul corpo, e si rimette il rilievo
    mw = t.matrix_world
    inv = mw.inverted()
    fuori = 0
    for i, v in enumerate(t.data.vertices):
        base_mondo = mw @ liscia[i]
        ok, loc, nor, _ = corpo.closest_point_on_mesh(corpo.matrix_world.inverted() @ base_mondo)
        if not ok:
            fuori += 1
            continue
        loc_m = corpo.matrix_world @ loc
        nor_m = (corpo.matrix_world.to_3x3() @ nor).normalized()
        v.co = inv @ (loc_m + nor_m * (STACCO + rilievo[i]))
    t.data.update()
    if fuori:
        print("     %d vertici senza proiezione" % fuori)


def scortica(t):
    """Tiene solo la superficie ESTERNA del guscio.

    ⚠️ E' il passo che mancava. La ricetta dello shrinkwrap presuppone una
    superficie SOTTILE, che si avvolge e poi si ingrossa con Solidify. Il pezzo
    generato lo spessore ce l'ha gia' dentro: senza scorticarlo, anche la parete
    interna viene spinta fuori e si fonde con quella esterna — piastre spianate.

    Si tiene una faccia se la sua normale punta VIA dal corpo: si confronta con
    la direzione dal punto piu' vicino del corpo al centro della faccia.
    """
    me = t.data
    me.calc_loop_triangles()
    mw = t.matrix_world
    inv_corpo = corpo.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    via = []
    for f in bm.faces:
        centro = mw @ f.calc_center_median()
        ok, loc, _, _ = corpo.closest_point_on_mesh(inv_corpo @ centro)
        if not ok:
            continue
        fuori = (centro - (corpo.matrix_world @ loc)).normalized()
        nor = (mw.to_3x3() @ f.normal).normalized()
        if nor.dot(fuori) < 0.0:
            via.append(f)
    bmesh.ops.delete(bm, geom=via, context='FACES')
    bm.to_mesh(me)
    bm.free()
    me.update()
    print("     scorticato: tolte %d facce, restano %d" % (len(via), len(me.polygons)))


def ingrossa(t, spessore=0.012):
    attivo(t)
    m = t.modifiers.new("Spessore", 'SOLIDIFY')
    m.thickness = spessore
    m.offset = 1.0
    bpy.ops.object.modifier_apply(modifier=m.name)


def conforma_modificatore(t, stacco=0.010, modo='OUTSIDE_SURFACE', gruppo=None):
    """Lo Shrinkwrap di Blender, configurato come dice la guida.

    ⚠️ La differenza che conta: `OUTSIDE_SURFACE` non PROIETTA tutti i vertici
    sulla superficie — sposta solo quelli che stanno DENTRO il corpo, spingendoli
    fuori di `offset`. Quelli gia' fuori restano dove sono, quindi un guscio con
    spessore non collassa su se' stesso. La proiezione vertice-per-vertice, che e'
    quello che avevo fatto a mano, mandava parete interna ed esterna sullo stesso
    punto e strappava il pezzo.
    """
    attivo(t)
    m = t.modifiers.new("Conforma", 'SHRINKWRAP')
    m.target = corpo
    m.wrap_method = 'NEAREST_SURFACEPOINT'
    m.wrap_mode = modo
    m.offset = stacco
    if gruppo:
        m.vertex_group = gruppo
    bpy.ops.object.modifier_apply(modifier=m.name)


def gruppo_aderenza(t, stacco=0.009, fascia=0.022):
    """Dipinge da solo QUANTO ogni vertice deve aderire.

    ⚠️ E' questo che toglie gli strappi, non la scorticatura. La guida lo dice:
    lo shrinkwrap accetta un vertex group come influenza. Invece di decidere
    quali facce buttare via, si decide quanto ogni vertice deve muoversi:

      • vertice DENTRO il corpo, o piu' vicino di `stacco`  -> peso 1, aderisci
      • vertice a piu' di `stacco + fascia`                 -> peso 0, resta li'
      • in mezzo                                            -> sfuma

    Cosi' la parete INTERNA del guscio (vicina alla pelle) si appoggia, quella
    ESTERNA (le cime delle piastre) non si muove, e lo spessore si conserva da
    solo. Niente facce tolte, niente buchi.

    Il peso non si dipinge a mano: si CALCOLA dalla distanza dal corpo, quindi
    vale per qualunque pezzo e qualunque corpo senza intervento.
    """
    g = t.vertex_groups.new(name="aderenza")
    mw = t.matrix_world
    inv_corpo = corpo.matrix_world.inverted()
    dentro = 0
    for v in t.data.vertices:
        p_mondo = mw @ v.co
        ok, loc, nor, _ = corpo.closest_point_on_mesh(inv_corpo @ p_mondo)
        if not ok:
            g.add([v.index], 0.0, 'REPLACE')
            continue
        loc_m = corpo.matrix_world @ loc
        nor_m = (corpo.matrix_world.to_3x3() @ nor).normalized()
        d = (p_mondo - loc_m).dot(nor_m)      # negativo = dentro la carne
        if d < stacco:
            peso = 1.0
            if d < 0.0:
                dentro += 1
        elif d > stacco + fascia:
            peso = 0.0
        else:
            peso = 1.0 - (d - stacco) / fascia
        g.add([v.index], peso, 'REPLACE')
    print("     aderenza: %d vertici erano DENTRO la carne su %d" % (dentro, len(t.data.vertices)))
    return g.name


def materiali(gusci):
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.data.materials.clear()
    ## ⚠️ Workbench in modalita' MATERIAL usa `diffuse_color` (il colore di
    ## VIEWPORT), non il Principled: settando solo il BSDF resta tutto grigio.
    mp = bpy.data.materials.new("pelle")
    mp.diffuse_color = (0.72, 0.55, 0.47, 1)
    mp.roughness = 0.85
    corpo.data.materials.append(mp)
    ma = bpy.data.materials.new("acciaio")
    ma.diffuse_color = (0.22, 0.42, 0.72, 1)
    ma.metallic = 1.0
    ma.roughness = 0.30
    for g in gusci:
        g.data.materials.append(ma)


## ─── i quattro casi ─────────────────────────────────────────────────────────
casi = []

a = carica_pezzo("A_oggi")
posa(a, "LowerArm", "MiddleDistal")
casi.append(("A_oggi", a, "com'e' oggi: posato rigido"))

b = carica_pezzo("B_schiacciato")
posa(b, "LowerArm", "MiddleDistal")
conforma(b, conserva=False)
casi.append(("B_schiacciato", b, "conformato SENZA conservare (controllo negativo)"))

e = carica_pezzo("E_outside")
posa(e, "LowerArm", "MiddleDistal")
conforma_modificatore(e, 0.010, 'OUTSIDE_SURFACE')
casi.append(("E_outside", e, "Shrinkwrap OUTSIDE_SURFACE, come da guida"))

f = carica_pezzo("F_outside_braccio")
posa(f, "UpperArm", "MiddleDistal", margine=1.0)
conforma_modificatore(f, 0.010, 'OUTSIDE_SURFACE')
casi.append(("F_outside_braccio", f, "spalla->dita + OUTSIDE_SURFACE"))

j = carica_pezzo("J_sartoriale")
posa(j, "UpperArm", "MiddleDistal", margine=1.0)
gr = gruppo_aderenza(j)
conforma_modificatore(j, 0.009, 'OUTSIDE_SURFACE', gr)
casi.append(("J_sartoriale", j, "vertex group di aderenza, niente scorticatura"))

h = carica_pezzo("H_ricetta")
posa(h, "LowerArm", "MiddleDistal")
scortica(h)
conforma_modificatore(h, 0.009, 'OUTSIDE_SURFACE')
ingrossa(h, 0.012)
casi.append(("H_ricetta", h, "scortica -> shrinkwrap -> Solidify (la ricetta intera)"))

i_ = carica_pezzo("I_ricetta_braccio")
posa(i_, "UpperArm", "MiddleDistal", margine=1.0)
scortica(i_)
conforma_modificatore(i_, 0.009, 'OUTSIDE_SURFACE')
ingrossa(i_, 0.012)
casi.append(("I_ricetta_braccio", i_, "la ricetta intera, spalla->dita"))

for nome, o, che in casi:
    mn, mx = bbox(o)
    print("  %-18s %-46s z %.3f..%.3f" % (nome, che, mn.z, mx.z))

## ─── resa: un caso per volta, stessa inquadratura ───────────────────────────
materiali([o for _, o, _ in casi])
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.render.resolution_x = 1150
sc.render.resolution_y = 900
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.lens = 45

bersaglio = (osso("LeftUpperArm") + osso("LeftMiddleDistal")) / 2
cam.location = bersaglio + Vector((0.28, -1.05, 0.42))
d_ = bersaglio - cam.location
cam.rotation_euler = d_.to_track_quat('-Z', 'Y').to_euler()

for nome, o, _ in casi:
    for _, altro, _ in casi:
        altro.hide_render = (altro is not o)
    sc.render.filepath = FUORI + "conf_" + nome
    bpy.ops.render.render(write_still=True)
    print("reso:", sc.render.filepath + ".png")
print("FATTO")
