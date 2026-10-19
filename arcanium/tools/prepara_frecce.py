# -*- coding: utf-8 -*-
"""Frecce e faretra: dai GLB di Tripo ai prop di gioco.

    blender --background --factory-startup --python arcanium/tools/prepara_frecce.py -- \
        freccia <tripo.glb> <uscita.glb> [lunghezza_m=0.70] [spirito] [penne=F] [punta=F]
    blender --background --factory-startup --python arcanium/tools/prepara_frecce.py -- \
        faretra <tripo.glb> <uscita.glb> [altezza_m=0.75]

FRECCIA. Tripo la consegna lunga un metro esatto lungo X, con la punta a -X
e le penne a +X, e con l'asta sollevata dal piano (z ~ 0.1). In gioco la
freccia e' `arcanium/systems/enemies/freccia.gd`, che vola lungo il SUO -Z e
si orienta con `look_at`: qui la si gira con la punta verso +Y di Blender
(che il glTF manda su -Z), si centra l'ASTA sull'origine — non la scatola,
che le penne allargano — e la si porta alla lunghezza vera. La lunghezza e'
UNA: `freccia.gd` (LUNGHEZZA) la ripete, e la freccia in mano e i misuratori
la leggono da li'. 70 cm e' una freccia vera (28 pollici); a 85 la punta
occupava la mano dell'arciere.

Le PROPORZIONI di Tripo sono quelle del concept (punta lunga un terzo
dell'asta), ma le penne vengono un cespuglio: lo span e' un quarto della
lunghezza contro un sesto del disegno. `penne=F` riduce l'altezza delle
alette di F (solo la parte che sporge dall'asta: l'asta e le legature restano
dove sono); `punta=F` accorcia e stringe la punta di F attorno alla sua base,
e l'asta si allunga di quel tanto (e' fatta di facce lunghe senza vertici nel
mezzo: si stira senza cuciture) cosi' la lunghezza totale non cambia.

FARETRA. Arriva in piedi lungo Z (che diventa Y in Godot), alta un metro con
le frecce che sporgono: si porta all'altezza data, con la base a y = 0 e
l'asse del fodero sull'origine, cosi' il BoneAttachment sulla schiena la
inclina attorno al suo piede.

Entrambe escono con le immagini rinominate `base_color` (Godot le estrae
accanto al GLB con quel suffisso). Le misure stampate sono in metri, in
coordinate Godot.
"""
import bpy, sys, os, json, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
MODO, SRC, DST = argv[0], argv[1], argv[2]
MISURA = 0.70 if MODO == "freccia" else 0.75
## "spirito": la parte teal si illumina da sola (texture di emissione ricavata
## dalla basecolor, come per l'Arco di Spirito).
SPIRITO = False
PENNE = 1.0
PUNTA = 1.0
for tok in argv[3:]:
    if tok == "spirito":
        SPIRITO = True
    elif tok.startswith("penne="):
        PENNE = float(tok[6:])
    elif tok.startswith("punta="):
        PUNTA = float(tok[6:])
    else:
        MISURA = float(tok)
## Faretra: un guscio che sta tutto sotto questa quota (il collare e le frecce
## stanno sopra) e sporge dal tubo oltre questo margine e' una cinghia.
BRETELLE_MARGINE = 0.03
BRETELLE_Z = 0.62

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
obj = [o for o in bpy.data.objects if o.type == "MESH"][0]
me = obj.data
print("IMPORT", obj.name, "verts", len(me.vertices), "facce", len(me.polygons))

co = [v.co.copy() for v in me.vertices]
lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
print("ingombro Tripo (blender): x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % (lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))

if MODO == "freccia":
    ## L'asse dell'asta: il centro dei vertici SOTTILI (vicini al piano y=0)
    ## fra la punta e le penne. Non "il terzo centrale": l'asta di Tripo e'
    ## fatta di facce lunghe, e nel mezzo non ha nessun vertice.
    centro = [c for c in co if -0.42 <= c.x <= 0.22 and abs(c.y) < 0.03]
    if not centro:
        centro = [c for c in co if -0.42 <= c.x <= 0.22]
    asse = sum(centro, Vector()) / len(centro)
    print("asse dell'asta (y, z): %.4f %.4f  su %d vertici" % (asse.y, asse.z, len(centro)))
    scala = MISURA / (hi.x - lo.x)
    ## -90 gradi attorno a Z: la punta (-X) va a +Y, le penne (+X) a -Y.
    rot = Matrix.Rotation(math.radians(-90.0), 4, "Z")
    for v in me.vertices:
        p = v.co - Vector(((lo.x + hi.x) * 0.5, asse.y, asse.z))
        v.co = (rot @ p) * scala
    me.update()
    co = [v.co.copy() for v in me.vertices]
    ## L'asta: le facce lunghe (piu' di un quinto della freccia) fra i due
    ## anelli che la chiudono; il suo raggio e quei due anelli decidono dove
    ## cominciano la punta (oltre l'anello di testa) e le penne (dall'anello
    ## di coda in giu' il fusto e' tutto dentro le alette).
    lunghe = [p for p in me.polygons
              if max(co[i].y for i in p.vertices) - min(co[i].y for i in p.vertices) > MISURA * 0.2]
    v_asta = sorted({i for p in lunghe for i in p.vertices})
    r_asta = sorted(math.hypot(co[i].x, co[i].z) for i in v_asta)[len(v_asta) // 2]
    y_testa = max(co[i].y for i in v_asta)
    y_coda = min(co[i].y for i in v_asta)
    print("asta: raggio %.4f, anelli a y %.3f (coda) e %.3f (testa)" % (r_asta, y_coda, y_testa))

    def sporgenza(v, f):
        ## Solo cio' che sporge dall'asta si stringe: il fusto resta intero.
        r = math.hypot(v.x, v.z)
        if r <= r_asta or f == 1.0:
            return v
        k = (r_asta + (r - r_asta) * f) / r
        return Vector((v.x * k, v.y, v.z * k))

    if PENNE != 1.0:
        n = 0
        for v in me.vertices:
            if v.co.y < y_testa - 1e-6 and math.hypot(v.co.x, v.co.z) > r_asta:
                v.co = sporgenza(v.co, PENNE); n += 1
        print("penne: %d vertici stretti di %.2f" % (n, PENNE))
    if PUNTA != 1.0:
        ## Attorno alla base (l'anello di testa dell'asta): lungo l'asse e in
        ## larghezza; poi tutta la testa, anello compreso, torna in su di quanto
        ## si e' accorciata, e le facce lunghe dell'asta si stirano.
        y_tip = max(c.y for c in co)
        delta = (y_tip - y_testa) * (1.0 - PUNTA)
        n = 0
        for v in me.vertices:
            if v.co.y > y_testa - 1e-6:
                p = v.co
                p = Vector((p.x, y_testa + (p.y - y_testa) * PUNTA, p.z))
                p = sporgenza(p, PUNTA)
                v.co = Vector((p.x, p.y + delta, p.z)); n += 1
        print("punta: %d vertici, lunga %.3f -> %.3f, asta stirata di %.3f" % (
            n, y_tip - y_testa, (y_tip - y_testa) * PUNTA, delta))
    me.update()
    co = [v.co.copy() for v in me.vertices]
    misure = {"lunghezza": round(max(c.y for c in co) - min(c.y for c in co), 4),
              "punta_godot": (0.0, 0.0, round(-max(c.y for c in co), 4)),
              "cocca_godot": (0.0, 0.0, round(-min(c.y for c in co), 4)),
              "raggio_asta": round(r_asta, 4), "penne": PENNE, "punta": PUNTA}
else:
    ## ⚠️ Tripo la consegna INCLINATA dentro la sua scatola (un metro di
    ## altezza per 0,7 di larghezza: e' il fodero di sbieco, non un fodero
    ## largo). Prima la si RADDRIZZA: l'asse principale dei vertici del fodero
    ## (i due terzi bassi, senza le penne che sporgono) portato su +Z. Poi
    ## base a z = 0 e asse sull'origine, cosi' il BoneAttachment la inclina
    ## attorno al piede e non attorno a un'inclinazione gia' nel modello.
    import numpy as np
    corpo = np.array([[c.x, c.y, c.z] for c in co if c.z <= lo.z + (hi.z - lo.z) * 0.66])
    centro = corpo.mean(axis=0)
    _val, vet = np.linalg.eigh(np.cov((corpo - centro).T))
    asse = vet[:, -1]                       # autovettore della varianza massima
    if asse[2] < 0:
        asse = -asse
    asse = Vector(asse.tolist())
    print("asse del fodero: %s  (inclinazione %.1f gradi)" % (
        tuple(round(a, 3) for a in asse), math.degrees(asse.angle(Vector((0, 0, 1))))))
    rot = asse.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4()
    for v in me.vertices:
        v.co = rot @ (v.co - Vector(centro.tolist()))
    me.update()
    co = [v.co.copy() for v in me.vertices]
    lo2 = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi2 = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    ## L'asse del tubo si prende dal COLLARE (fra il 60 e il 70% dell'altezza),
    ## che e' un anello simmetrico: il terzo basso e' sbilanciato dalle bretelle
    ## e dava un asse fuori di 3 cm, abbastanza da tagliare via una parete.
    collare = [c for c in co if lo2.z + (hi2.z - lo2.z) * 0.60 <= c.z <= lo2.z + (hi2.z - lo2.z) * 0.70]
    piede = sum(collare, Vector()) / len(collare)
    scala = MISURA / (hi2.z - lo2.z)
    ## Girata di 180 gradi attorno a Z: lo stemma, che Tripo mette a -Y, va a
    ## +Y — cioe' a -Z di Godot, il lato che guarda VIA dalla schiena. Le
    ## bretelle stanno dall'altra parte, e vanno via (sotto).
    for v in me.vertices:
        p = (v.co - Vector((piede.x, piede.y, lo2.z))) * scala
        v.co = Vector((-p.x, -p.y, p.z))
    me.update()
    co = [v.co.copy() for v in me.vertices]
    ## LE BRETELLE: cinghie da zainetto appese al collare, con la fibbia, che
    ## girano attorno al tubo e passano sotto il piede. Riggarle per farle
    ## aderire alle spalle costerebbe piu' di quanto rendono (deciso con
    ## l'utente il 2026-09-13): si tolgono.
    ##
    ## ⚠️ Non per raggio: il pannello di cuoio inciso sporge quanto le cinghie
    ## (tre tagli a raggio hanno aperto la parete con lo stemma e lasciato le
    ## cinghie). Per COMPONENTI: la zuppa di Tripo, SALDATA a mezzo millimetro,
    ## torna in ~30 gusci — il tubo (il piu' grande), le frecce (arrivano
    ## sopra il collare), e le cinghie: gusci che stanno sotto il collare e
    ## sporgono dal tubo. Si cancellano le facce di quei gusci.
    import bmesh
    bm = bmesh.new(); bm.from_mesh(me)
    bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
    ## `remove_doubles` fonde i vertici e le facce restano: la faccia i-esima
    ## del bmesh e' ancora la faccia i-esima della mesh.
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
    comp_di = {}
    componenti = []
    for v0 in bm.verts:
        if v0.index in comp_di:
            continue
        pila = [v0]; comp_di[v0.index] = len(componenti); comp = [v0]
        while pila:
            v = pila.pop()
            for e in v.link_edges:
                w = e.other_vert(v)
                if w.index not in comp_di:
                    comp_di[w.index] = len(componenti); pila.append(w); comp.append(w)
        componenti.append(comp)
    ordine = sorted(range(len(componenti)), key=lambda i: -len(componenti[i]))
    tubo = ordine[0]
    mezzo = sorted(math.hypot(c.x, c.y) for c in co if 0.25 <= c.z <= 0.40)
    r_tubo = mezzo[len(mezzo) // 2]
    bretelle = set()
    for i in ordine:
        comp = componenti[i]
        zmax = max(v.co.z for v in comp); zmin = min(v.co.z for v in comp)
        rmax = max(math.hypot(v.co.x, v.co.y) for v in comp)
        cinghia = i != tubo and zmax < BRETELLE_Z and rmax > r_tubo + BRETELLE_MARGINE and len(comp) >= 20
        print("  guscio %2d: %4d verts  z %.3f..%.3f  rmax %.3f  %s" % (i, len(comp), zmin, zmax, rmax, "CINGHIA" if cinghia else ("tubo" if i == tubo else "")))
        if cinghia:
            bretelle.add(i)
    via = [f for f in bm.faces if all(comp_di[v.index] in bretelle for v in f.verts)]
    bmesh.ops.delete(bm, geom=via, context="FACES")
    bm.to_mesh(me); bm.free(); me.update()
    print("bretelle: %d gusci, tolte %d facce (raggio tubo %.3f)" % (len(bretelle), len(via), r_tubo))
    co = [v.co.copy() for v in me.vertices]
    misure = {"altezza": round(scala * (hi2.z - lo2.z), 4), "bretelle_facce_tolte": len(via)}

xs = [c.x for c in co]; ys = [c.y for c in co]; zs = [c.z for c in co]
misure["ingombro_godot"] = {"x": (round(min(xs), 4), round(max(xs), 4)),
                            "y": (round(min(zs), 4), round(max(zs), 4)),
                            "z": (round(-max(ys), 4), round(-min(ys), 4))}
print("MISURE", json.dumps(misure))

## Immagini col nome che Godot usa come suffisso del file estratto.
for m in me.materials:
    if not m or not m.use_nodes:
        continue
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            dest = [l.to_socket.name for l in n.outputs[0].links]
            if "Base Color" in dest:
                n.image.name = "base_color"
            elif any("Normal" in d for d in dest):
                n.image.name = "normal"
            elif any("Metallic" in d or "Roughness" in d for d in dest):
                n.image.name = "metallic_roughness"
    m.name = os.path.splitext(os.path.basename(DST))[0]
    if SPIRITO:
        import numpy as np
        bsdf = [n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
        tex = [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image and n.image.name == "base_color"][0]
        w, h = tex.image.size
        px = np.array(tex.image.pixels[:], dtype=np.float32).reshape(h, w, 4)
        r, g, b = px[..., 0], px[..., 1], px[..., 2]
        maschera = (g > r * 1.35) & (b > r * 1.2) & (g > 0.22)
        peso = np.clip((g - r * 1.35) / 0.25, 0.0, 1.0) * maschera
        em = px.copy()
        em[..., 0] *= peso; em[..., 1] *= peso; em[..., 2] *= peso; em[..., 3] = 1.0
        img_em = bpy.data.images.new("emissive", w, h, alpha=False)
        img_em.pixels = em.ravel().tolist()
        img_em.pack()
        n_em = m.node_tree.nodes.new("ShaderNodeTexImage")
        n_em.image = img_em
        m.node_tree.links.new(n_em.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 0.7
        print("emissione: %.1f%% dei texel" % (100.0 * maschera.mean()))

obj.name = me.name = os.path.splitext(os.path.basename(DST))[0].capitalize()
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", use_selection=True,
                          export_apply=True, export_animations=False, export_lights=False,
                          export_cameras=False, export_yup=True, export_image_format="AUTO")
print("EXPORT", DST, os.path.getsize(DST), "byte")
with open(os.path.splitext(DST)[0] + "_misure.json", "w", encoding="utf-8") as f:
    json.dump(misure, f, indent=2)
