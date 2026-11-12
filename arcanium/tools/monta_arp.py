"""Monta un CAMPIONE sullo SCHELETRO ARP, senza il travaso sul Nephilite: la
pipeline nostra (fase 1, 2026-11-01; memoria pipeline-tutta-nostra).

Il corpo resta quello che ARP ha riggato (`CorpoSylvorn`, legato al rig `rig`
dopo `rigga()`), nella sua A-pose, con cinque dita vere e le ossa di torsione.
Si fanno solo i ritocchi del travaso che servono ancora, coi nomi di ARP, e si
esporta col glTF per Godot di ARP. In Godot la mappa
arcanium/resources/rigs/arp_humanoid.tres rinomina le ossa sul profilo
Humanoid (nodo `PATH:root/Skeleton3D` nell'.import).

Dentro Blender, dal ponte (arcanium/tools/ponte_blender.py) o in background,
dopo il montaggio fino a `rigga()` salvato in
lavorazione/blender/campione_<nome>.blend:

    exec(open(".../monta_arp.py").read())
    monta_arp("zarine")
"""
exec(open("C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/arcanium/tools/monta_campione.py", encoding="utf-8").read())
import bpy

## I nomi Nephilite che gli strumenti di monta_campione.py conoscono, sulle ossa
## di ARP che deformano.
OSSA_ARP = {"Root": "c_traj", "Hips": "root.x", "Spine_01": "spine_01.x", "Spine_02": "spine_02.x",
            "Spine_03": "spine_03.x", "Neck": "neck.x", "Head": "head.x"}
for _l, _a in (("L", "l"), ("R", "r")):
    OSSA_ARP.update({"Clavicle_" + _l: "shoulder." + _a, "Shoulder_" + _l: "arm_stretch." + _a,
                     "Elbow_" + _l: "forearm_stretch." + _a, "Hand_" + _l: "hand." + _a,
                     "UpperLeg_" + _l: "thigh_stretch." + _a, "LowerLeg_" + _l: "leg_stretch." + _a,
                     "Foot_" + _l: "foot." + _a})

## Le ossa delle BRACCIA di ARP (per la maschera della stoffa: cio' che pesa
## su di loro resta fermo, o le maniche passerebbero dentro l'avambraccio).
BRACCIA_ARP = ("shoulder.", "arm_stretch.", "arm_twist.", "forearm_stretch.", "forearm_twist.", "hand.",
               "thumb", "index", "middle", "ring", "pinky")

## La STOFFA di ogni campione sul corpo ARP: le ricette STOFFE di
## monta_campione.py, valide anche qui (le quote sono altezze dal suolo, uguali
## nella A-pose del corpo riggato e nella stance del Nephilite). Qui le
## eccezioni, se un corpo ARP ne chiede.
STOFFE_ARP = dict(STOFFE)

## La mantellina di Ilwen (2026-11-12): un guscio di 784 vertici dalla spalla destra al
## fianco, sopra il braccio. Il bind la dava per meta' ad avambraccio e coscia, e nello
## sprint partiva in schegge lunghe 60 cm («i pannelli dei fianchi»: era lei). Stoffa
## simulata, coi pesi di `pesi_mantellina`.
STOFFE_ARP["ilwen"] = dict(presso=(-0.173, 0.188, 0.939), alto=1.40, basso=1.27, mantellina=dict(lato="r"))

## Le PIASTRE: gusci rigidi piu' grandi di un pezzo piccolo, che il bind ha pesato vertice
## per vertice. I pannelli di legno ai fianchi di Ilwen (2026-11-12) stavano meta' sul
## bacino e meta' sulla coscia, con un confine netto: accovacciata, la piastra si spaccava
## in due (spigoli stirati 90 volte). Ogni guscio che sta per intero nella `scatola`, fino a
## `massimo` vertici, prende su tutti i vertici la MEDIA dei suoi pesi: si muove d'un pezzo.
PIASTRE = {
    "ilwen": dict(scatola=((-0.26, -0.20, 0.60), (0.26, 0.20, 1.06)), massimo=400),
}

## I CAPELLI LUNGHI (2026-11-12, l'utente: una soluzione diversa dai soli pesi, come per
## le vesti). I gusci indicati passano tutti sulla testa, rigidi, e diventano la mesh
## `StoffaCapelli`: stoffa simulata, ferma vicino al cranio e libera in punta. Coi pesi
## di ARP la coda di Aurin stava per meta' su spalla e braccio sinistri, la treccia di
## Ilwen al 60% sulla schiena, e nello sprint si allungavano a strisce.
##   presso:   punti (metri, mondo) sui gusci;
##   scatola:  ((x0, y0, z0), (x1, y1, z1)): i gusci che ci stanno dentro per intero;
##   vicino, lontano: metri dall'osso della testa fra cui la maschera sfuma da ferma a libera.
CAPELLI = {
    "aurin": dict(scatola=((0.0, -0.02, 1.55), (0.28, 0.22, 1.70))),
    "ilwen": dict(presso=[(-0.079, 0.160, 1.233)]),
}
NOME_CAPELLI = "StoffaCapelli"

## Gli aiuti di ARP che non deformano ma seguono un osso che deforma: la mandibola
## va con la testa, il tallone col piede (vedi solo_ossa_che_deformano).
AIUTI_SULLE_OSSA = {"jaw_h_helper.x": "head.x", "foot_heel_h.l": "foot.l", "foot_heel_h.r": "foot.r"}

CORPO = "CorpoSylvorn"
RIG = "rig"


def _apri(nome):
    """Il blend del montaggio, con dentro solo il rig ARP e il corpo legato."""
    bpy.ops.wm.open_mainfile(filepath=RADICE_PROGETTO + "lavorazione/blender/campione_%s.blend" % nome)
    tieni = {CORPO, RIG}
    for o in list(bpy.data.objects):
        if o.name not in tieni and not (o.type == 'MESH' and o.name.startswith("cs_")):
            if o.type in ('MESH', 'ARMATURE'):
                bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.view_layer.update()
    return bpy.data.objects[CORPO], bpy.data.objects[RIG]


def solo_ossa_che_deformano(me, rig):
    """Via i gruppi delle ossa di ARP che NON deformano.

    Il bind di ARP lascia pesi su ossa di aiuto che l'export per Godot non
    porta: su Zarine (2026-11-01) `jaw_h_helper.x` su 5.842 vertici di viso e
    collo, `c_thigh_b.*` sulle cosce, `foot_heel_h.*` sui talloni. Nel glTF
    quella quota spariva, e in gioco il naso restava nella posa di riposo
    mentre il corpo si accovacciava: un'asta color pelle dalla faccia in su.
    Passarli all'antenato che deforma non va: in ARP quelle ossa pendono dalla
    radice, e il viso finiva sul bacino. Si tolgono e basta: ogni vertice
    resta sulle sue ossa vere (normalizza_pesi), e chi pesava solo su quelle
    resta orfano e prende i pesi del vicino (chiudi_orfani).

    ⚠️ Tranne gli aiuti che seguono un osso vero (AIUTI_SULLE_OSSA): il loro peso
    passa a quell'osso, per nome, prima di togliere il gruppo. Buttati via, i
    vertici restavano sulle ossa rimaste rinormalizzate (2026-11-09, corsa china
    di Edran): il mento per un terzo sul collo, e con la testa piegata si
    allungava verso il petto; il retro del tallone per il 60-90% sullo stinco,
    e con la punta giu' allo stacco il piede si storceva."""
    deform = {b.name for b in rig.data.bones if b.use_deform}
    for aiuto, vero in AIUTI_SULLE_OSSA.items():
        dest, src = me.vertex_groups.get(vero), me.vertex_groups.get(aiuto)
        if dest is None or src is None:
            continue
        passati = 0
        for v in me.data.vertices:
            for g in v.groups:
                if g.group == src.index and g.weight > 0.0:
                    vecchio = 0.0
                    for h in v.groups:
                        if h.group == dest.index:
                            vecchio = h.weight
                    dest.add([v.index], vecchio + g.weight, 'REPLACE')
                    passati += 1
        print("%s su %s: %d vertici" % (aiuto, vero, passati))
    via = [g for g in me.vertex_groups if g.name not in deform]
    for g in via:
        me.vertex_groups.remove(g)
    print("solo ossa che deformano: tolti %d gruppi" % len(via))
    return len(via)


def ritocchi_arp(me, rig):
    """I ritocchi del travaso che servono anche senza Nephilite: i vertici
    senza peso (il `neutral_bone` dell'export, un'asta piantata nell'origine),
    gli strati di Tripo che si muovono insieme (gabbia), e la somma a 1."""
    ns = carica_ricetta()
    solo_ossa_che_deformano(me, rig)
    ns["normalizza_pesi"](me)
    ns["chiudi_orfani"](me)
    ns["pesi_dalla_gabbia"](me, rig, mani=(OSSA_ARP["Hand_L"], OSSA_ARP["Hand_R"]), testa=OSSA_ARP["Head"])
    ns["chiudi_orfani"](me)
    ns["normalizza_pesi"](me)


def texture_del_montaggio(nome, me):
    """La texture del GLB del montaggio (`<nome>_rigged_Baked_BaseColor.jpg`),
    con i suoi ritocchi di colore, sul corpo ARP se e' diversa.

    Il corpo legato da ARP porta la texture di Tripo. I ritocchi venuti dopo,
    come i gambali di Ilwen ridipinti (`gambali_scuri`), stavano solo sulla
    texture del montaggio. Rifatti sul corpo ARP, il guscio vicino al punto
    era un altro, di 481 vertici, e le cosce restavano rosa sotto la tunica
    (2026-11-02). Le UV sono le stesse: si copia l'immagine."""
    import os
    import numpy as np
    percorso = RADICE_PROGETTO + "assets/characters/campioni/%s/%s_rigged_Baked_BaseColor.jpg" % (nome, nome)
    if not os.path.exists(percorso):
        return False
    img, px = _texture(me.name)
    src = bpy.data.images.load(percorso)
    if tuple(src.size) != tuple(img.size):
        bpy.data.images.remove(src)
        print("texture del montaggio: misure diverse, resta quella di ARP")
        return False
    nuovo = np.empty(len(px.ravel()), dtype=np.float32)
    src.pixels.foreach_get(nuovo)
    bpy.data.images.remove(src)
    nuovo = nuovo.reshape(px.shape)
    diversi = int((np.abs(nuovo[..., :3] - px[..., :3]).sum(-1) > 0.25).sum())
    print("texture del montaggio: %d pixel diversi" % diversi)
    if diversi == 0:
        return False
    _salva_texture(img, nuovo)
    return True


def stoffe_arp(nome, me, rig):
    """Il tessuto simulato come in `riesporta`, coi nomi di ARP."""
    st = STOFFE_ARP.get(nome)
    if st is None:
        return []
    ns = carica_ricetta()
    if "sotto" in st:
        stacca_sotto(me, st["presso"], st["sotto"], isola_maggiore=st.get("isola_maggiore", False))
    else:
        ## Il guscio intero del tessuto (il mantello di Edran).
        ns["separa_stoffe"](me, presso=st["presso"])
    stoffe = sorted(o.name for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith("Stoffa"))
    for n in stoffe:
        ob = bpy.data.objects[n]
        if st.get("un_foglio"):
            un_foglio(ob)
        if "per_lato" in st:
            pesi_per_lato(ob, nome_rig=rig.name, ossa=OSSA_ARP, **st["per_lato"])
        if "dal_corpo" in st:
            pesi_dal_corpo(ob, me, **st["dal_corpo"])
        if "mantellina" in st:
            pesi_mantellina(ob, rig, **st["mantellina"])
        ns["normalizza_pesi"](ob)
        if st.get("simulata", True):
            ns["maschera_stoffa"](ob, alto=st["alto"], basso=st["basso"],
                                  fermo_se=lambda g: g.startswith(BRACCIA_ARP))
    if nome in GAMBE_PULITE:
        gambe_senza_bacino(nome_mesh=me.name, nome_rig=rig.name, ossa=OSSA_ARP)
        ns["normalizza_pesi"](me)
    if not st.get("simulata", True):
        ## Solo i pesi (il cappotto di Aurin): la veste torna nel corpo e
        ## nessuna `Stoffa<N>` arriva al gioco da simulare.
        bpy.ops.object.select_all(action='DESELECT')
        for n in stoffe:
            bpy.data.objects[n].select_set(True)
        me.select_set(True)
        bpy.context.view_layer.objects.active = me
        bpy.ops.object.join()
        stoffe = []
    return stoffe


def _gusci(me):
    """Le liste di indici dei vertici di ogni guscio (pezzo connesso) di una mesh."""
    vicini = [[] for _ in me.data.vertices]
    for e in me.data.edges:
        i, j = e.vertices
        vicini[i].append(j)
        vicini[j].append(i)
    visti, gusci = set(), []
    for i0 in range(len(vicini)):
        if i0 in visti:
            continue
        g, pila = [i0], [i0]
        visti.add(i0)
        while pila:
            for j in vicini[pila.pop()]:
                if j not in visti:
                    visti.add(j)
                    g.append(j)
                    pila.append(j)
        gusci.append(g)
    return gusci


def _dal_segmento(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
    return (p - (a + ab * t)).length


def pesi_mantellina(ob, rig, lato="r", attacco=0.02, caduta=0.18):
    """I pesi di una stoffa che pende da UNA SPALLA sopra il braccio (la mantellina di Ilwen).

    Cio' che pende segue il TRONCO, non il braccio: sotto la spalla il peso di ARP
    (braccio, avambraccio, e in fondo la coscia) sfuma in `caduta` metri verso le ossa
    del petto (spine_03, e sotto spine_02 fino all'orlo: pende dal petto, e la pulizia dei
    pesi toglierebbe il braccio accanto a spine_01, a quattro passi). Avambraccio e mano, dove restano, passano
    all'omero: e' la parte del braccio che la stoffa copre. Il resto lo fa la simulazione."""
    mw = rig.matrix_world
    spalla = (mw @ rig.data.bones["arm_stretch." + lato].head_local).z
    colonna = [(n, (mw @ ((rig.data.bones[n].head_local + rig.data.bones[n].tail_local) / 2)).z)
               for n in ("spine_02.x", "spine_03.x")]
    omero = "arm_stretch." + lato
    sotto = ("forearm", "c_forearm", "hand.", "thumb", "index", "middle", "ring", "pinky", "c_thumb", "c_index",
             "c_middle", "c_ring", "c_pinky")
    gambe = ("thigh", "c_thigh", "leg_", "c_leg", "foot", "toes")
    nomi = {g.index: g.name for g in ob.vertex_groups}
    for n in [omero] + [c[0] for c in colonna]:
        if ob.vertex_groups.get(n) is None:
            ob.vertex_groups.new(name=n)
    toccati = 0
    for v in ob.data.vertices:
        z = (ob.matrix_world @ v.co).z
        a = 1.0 - max(0.0, min(1.0, (spalla - z - attacco) / caduta))
        a = a * a * (3.0 - 2.0 * a)
        nuovi = {}
        for g in v.groups:
            n = nomi[g.group]
            if n.startswith(sotto):
                n = omero
            elif n.startswith(gambe) or n in ("root.x", "spine_01.x"):
                n = "spine_02.x"
            nuovi[n] = nuovi.get(n, 0.0) + g.weight * a
        ## Il tronco alla quota del vertice, fra i centri di due ossa della colonna.
        if z <= colonna[0][1]:
            tronco = {colonna[0][0]: 1.0}
        elif z >= colonna[-1][1]:
            tronco = {colonna[-1][0]: 1.0}
        else:
            for (n0, z0), (n1, z1) in zip(colonna, colonna[1:]):
                if z0 <= z <= z1:
                    t = (z - z0) / max(z1 - z0, 1e-6)
                    tronco = {n0: 1.0 - t, n1: t}
                    break
        for n, w in tronco.items():
            nuovi[n] = nuovi.get(n, 0.0) + w * (1.0 - a)
        for g in list(v.groups):
            ob.vertex_groups[g.group].remove([v.index])
        for n, w in nuovi.items():
            if w > 1e-4:
                ob.vertex_groups[n].add([v.index], w, 'REPLACE')
        toccati += a < 0.999
    print("pesi mantellina su %s: %d vertici su %d passati al tronco sotto la spalla (%.2f m)" % (
        ob.name, toccati, len(ob.data.vertices), spalla))


def pezzi_rigidi(me, rig, diagonale=0.12, passi=3, quota=0.15):
    """I PEZZI PICCOLI non stanno su ossa lontane: vanno rigidi su un osso solo.

    Un guscio chiuso in 12 cm (un pendente, una fibbia, una borchia) non si piega. Il
    bind di ARP ne pesa i vertici uno per uno: i piatti della bilancia sul petto di Zarine
    stavano per il 40% sulla TESTA e per il resto fra colonna e spalla, e nella rotolata
    si stiravano di 35 volte. Se i dominanti dei suoi vertici distano `passi` o piu'
    nell'albero delle ossa, il pezzo passa intero all'osso piu' vicino al suo centro fra
    quelli che contano (almeno `quota` del peso). Le dita (falangi a un passo l'una
    dall'altra) e le ginocchiere restano come sono."""
    import sys
    from collections import Counter
    from mathutils import Vector
    sys.path.insert(0, RADICE_PROGETTO + "arcanium/tools")
    import verifica_pesi
    dist = verifica_pesi._distanze()
    nomi = {g.index: g.name for g in me.vertex_groups}
    mw, mr = me.matrix_world, rig.matrix_world
    fatti = []
    for g in _gusci(me):
        co = [mw @ me.data.vertices[i].co for i in g]
        lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
        hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
        if (hi - lo).length > diagonale or len(g) < 4:
            continue
        massa, dominanti = Counter(), set()
        for i in g:
            pesi = Counter()
            for x in me.data.vertices[i].groups:
                massa[nomi[x.group]] += x.weight
                pesi[verifica_pesi._canonico(nomi[x.group])] += x.weight
            if pesi:
                dominanti.add(pesi.most_common(1)[0][0])
        if max((dist.get(a, {}).get(b, 99) for a in dominanti for b in dominanti), default=0) < passi:
            continue
        centro = (lo + hi) / 2
        totale = sum(massa.values()) or 1.0
        candidati = ([n for n, w in massa.items() if w / totale >= quota and n in rig.data.bones]
                     or [massa.most_common(1)[0][0]])
        osso = min(candidati, key=lambda n: _dal_segmento(centro, mr @ rig.data.bones[n].head_local,
                                                          mr @ rig.data.bones[n].tail_local))
        for i in g:
            for x in list(me.data.vertices[i].groups):
                me.vertex_groups[x.group].remove([i])
        me.vertex_groups[osso].add(g, 1.0, 'REPLACE')
        fatti.append((len(g), osso, tuple(round(c, 2) for c in centro)))
    print("pezzi rigidi su %s: %d gusci su un osso solo" % (me.name, len(fatti)))
    for n, osso, c in sorted(fatti, reverse=True)[:12]:
        print("   %4d vertici su %s, centro %s" % (n, osso, c))
    return fatti


def piastre_arp(nome, me, rig):
    """Le piastre di PIASTRE[nome] coi pesi uguali su tutto il guscio: la media dei suoi,
    senza le braccia se il pezzo non e' del braccio (pendono li' accanto, e il bind gliele
    passa) e senza le ossa sotto il 5%."""
    import sys
    from collections import Counter
    r = PIASTRE.get(nome)
    if r is None:
        return 0
    sys.path.insert(0, RADICE_PROGETTO + "arcanium/tools")
    import verifica_pesi
    lo, hi = r["scatola"]
    mw = me.matrix_world
    nomi = {g.index: g.name for g in me.vertex_groups}
    fatte = 0
    for g in _gusci(me):
        if len(g) > r.get("massimo", 400) or len(g) < 4:
            continue
        if not all(lo[k] <= (mw @ me.data.vertices[i].co)[k] <= hi[k] for i in g for k in range(3)):
            continue
        massa = Counter()
        for i in g:
            for x in me.data.vertices[i].groups:
                massa[nomi[x.group]] += x.weight
        braccio = sum(w for n, w in massa.items() if verifica_pesi._braccio(verifica_pesi._canonico(n)))
        if braccio * 2 < sum(massa.values()):
            massa = Counter({n: w for n, w in massa.items()
                             if not verifica_pesi._braccio(verifica_pesi._canonico(n))})
        totale = sum(massa.values())
        massa = {n: w for n, w in massa.items() if w / totale >= 0.05}
        totale = sum(massa.values())
        for i in g:
            for x in list(me.data.vertices[i].groups):
                me.vertex_groups[x.group].remove([i])
        for n, w in massa.items():
            me.vertex_groups[n].add(g, w / totale, 'REPLACE')
        fatte += 1
        print("   piastra di %4d vertici: %s" % (len(g), " ".join("%s=%.2f" % (n, w / totale) for n, w in
                                                                  sorted(massa.items(), key=lambda t: -t[1]))))
    print("piastre su %s: %d gusci coi pesi uguali" % (me.name, fatte))
    return fatte


def capelli_arp(nome, me, rig):
    """I capelli lunghi di CAPELLI[nome]: tutti sulla testa, in una mesh `StoffaCapelli`
    con la maschera per distanza dal cranio. Ritorna l'oggetto, o None."""
    from mathutils import Vector
    r = CAPELLI.get(nome)
    if r is None:
        return None
    mw = me.matrix_world
    gusci = _gusci(me)
    scelti = set()
    for q in r.get("presso", ()):
        q = Vector(q)
        vicino = min(range(len(me.data.vertices)), key=lambda i: (mw @ me.data.vertices[i].co - q).length_squared)
        scelti.update(next(g for g in gusci if vicino in g))
    if "scatola" in r:
        lo, hi = r["scatola"]
        for g in gusci:
            if all(lo[k] <= (mw @ me.data.vertices[i].co)[k] <= hi[k] for i in g for k in range(3)):
                scelti.update(g)
    if not scelti:
        print("capelli: nessun guscio trovato per", nome)
        return None
    testa = me.vertex_groups["head.x"]
    for i in scelti:
        for x in list(me.data.vertices[i].groups):
            me.vertex_groups[x.group].remove([i])
    testa.add(sorted(scelti), 1.0, 'REPLACE')
    dati = me.data
    for v in dati.vertices:
        v.select = v.index in scelti
    for e in dati.edges:
        e.select = all(i in scelti for i in e.vertices)
    for f in dati.polygons:
        f.select = all(i in scelti for i in f.vertices)
    bpy.ops.object.select_all(action='DESELECT')
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    prima = set(bpy.data.objects)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    ob = [o for o in bpy.data.objects if o not in prima][0]
    ob.name = ob.data.name = NOME_CAPELLI
    ## La maschera: ferma entro `vicino` dall'osso della testa, libera oltre `lontano`.
    osso = rig.data.bones["head.x"]
    a, b = rig.matrix_world @ osso.head_local, rig.matrix_world @ osso.tail_local
    vicino, lontano = r.get("vicino", 0.13), r.get("lontano", 0.24)
    if ATTRIBUTO_MASCHERA_ARP in ob.data.color_attributes:
        ob.data.color_attributes.remove(ob.data.color_attributes[ATTRIBUTO_MASCHERA_ARP])
    attr = ob.data.color_attributes.new(ATTRIBUTO_MASCHERA_ARP, 'FLOAT_COLOR', 'POINT')
    ob.data.color_attributes.active_color = attr
    liberi = 0
    for v in ob.data.vertices:
        t = max(0.0, min(1.0, (_dal_segmento(ob.matrix_world @ v.co, a, b) - vicino) / (lontano - vicino)))
        w = t * t * (3.0 - 2.0 * t)
        attr.data[v.index].color = (w, 0.0, 0.0, 1.0)
        liberi += w > 0.5
    print("%s: %d vertici in %d gusci, tutti sulla testa; %d liberi" % (
        NOME_CAPELLI, len(ob.data.vertices), len(_gusci(ob)), liberi))
    return ob


def rifinisci_topologia(nome, oggetti):
    """La topologia DOPO i tagli del montaggio: staccare la veste (stacca_sotto), ridurla a
    un foglio, riunirla al corpo lasciano farfalle, spigoli volanti e qualche buco, e
    `controlla_e_ripara` e' passato prima del rig. Trovati dal collaudo del 2026-11-12:
    2 farfalle e 1 spigolo volante sul cappotto di Aurin, due triangoli mancanti sul
    davanti della tunica di Zarine. Pesi, UV e maschera restano: sono strati della mesh."""
    import bmesh
    from mathutils import Vector
    for ob in oggetti:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        volanti = [e for e in bm.edges if not e.link_faces]
        bmesh.ops.delete(bm, geom=volanti, context='EDGES')
        soli = [v for v in bm.verts if not v.link_edges]
        bmesh.ops.delete(bm, geom=soli, context='VERTS')
        farfalle = _separa_farfalle(bm)
        ## Le BRICIOLE: un guscio di pochi vertici lontano da tutto il resto. Su Aurin un
        ## quadratino di 2 mm a mezzo metro dal corpo, pesato sullo stinco: in gioco un
        ## puntino che gli vola accanto.
        briciole = []
        if len(bm.faces) > 8:
            from mathutils.bvhtree import BVHTree
            gid = _gusci_per_faccia(bm)
            per_guscio = {}
            for f in bm.faces:
                per_guscio.setdefault(gid[f.index], []).append(f)
            bvh = BVHTree.FromBMesh(bm)
            for k, facce in per_guscio.items():
                vs = set(v for f in facce for v in f.verts)
                if len(vs) <= 8 and not any(gid[i] != k for v in vs
                                            for (_c, _n, i, _d) in bvh.find_nearest_range(v.co, 0.05)):
                    briciole.extend(vs)
            bmesh.ops.delete(bm, geom=briciole, context='VERTS')
        inv = ob.matrix_world.inverted()
        salta = [inv @ Vector(q) for q in BUCHI_LEGITTIMI.get(nome, ())]
        chiusi = _chiudi_buchi(bm, 0.05, salta=salta)
        if chiusi:
            ## Un buco stretto si chiude con facce ad area nulla (10 su Kessra).
            _degeneri(bm)
        if volanti or soli or farfalle or chiusi or briciole:
            bm.normal_update()
            bm.to_mesh(ob.data)
            ob.data.update()
        bm.free()
        print("rifinitura %s: %d spigoli volanti, %d vertici soli, %d farfalle, %d vertici di briciole, %d buchi chiusi"
              % (ob.name, len(volanti), len(soli), farfalle, len(briciole), chiusi))


def esporta_arp(percorso, me, rig):
    """Il glTF per Godot di ARP: rig UNIVERSAL con torsioni e metacarpi, la
    maschera della stoffa come colore dei vertici per nome."""
    sc = bpy.context.scene
    oggetti = [me] + [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith("Stoffa")]
    bpy.ops.object.select_all(action='DESELECT')
    for o in oggetti:
        o.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    sc.arp_engine_type = 'GODOT'
    sc.arp_export_rig_type = 'UNIVERSAL'
    sc.arp_export_twist = True
    sc.arp_ge_export_metacarp = True
    sc.arp_keep_bend_bones = False
    sc.arp_ge_sel_only = True
    sc.arp_ge_add_dummy_mesh = False
    sc.arp_ge_gltf_export_vertex_color = 'NAME'
    sc.arp_ge_gltf_export_vertex_color_name = ATTRIBUTO_MASCHERA_ARP
    r = bpy.ops.arp.arp_export_gltf_panel('EXEC_DEFAULT', filepath=percorso)
    print("export ARP:", r, percorso, [o.name for o in oggetti])
    return percorso


def pesi_per_regione(me, rig):
    """Ogni osso solo sulla sua parte del corpo (verifica_pesi.py), sul corpo e su ogni
    stoffa, prima dell'export. L'utente, 2026-11-12: le punte all'inguine di Edran venivano
    dal pollice pesato sulla veste e dalle due cosce sui pannelli fra le gambe."""
    import sys
    sys.path.insert(0, RADICE_PROGETTO + "arcanium/tools")
    import verifica_pesi
    for ob in [me] + [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith("Stoffa")]:
        verifica_pesi.pulisci_pesi(ob, rig)
        carica_ricetta()["chiudi_orfani"](ob)
        carica_ricetta()["normalizza_pesi"](ob)


def monta_arp(nome, uscita=None):
    """`uscita`: dove scrivere il GLB (di prova); senza, quello del gioco, e si salva il
    .blend del montaggio."""
    me, rig = _apri(nome)
    me.name = me.data.name = "Corpo"
    ritocchi_arp(me, rig)
    ## I ritocchi del montaggio (riesporta) sul corpo ARP: la texture gia'
    ## ritoccata, e la tunica di Ilwen sotto i pannelli dei fianchi.
    texture_del_montaggio(nome, me)
    if nome in PEZZI_SULLA_VESTE:
        pezzi, veste = PEZZI_SULLA_VESTE[nome]
        veste_sotto_ai_pezzi(pezzi, veste, nome_mesh=me.name)
    stoffe = stoffe_arp(nome, me, rig)
    print("stoffe ARP:", stoffe)
    rifinisci_topologia(nome, [me] + [bpy.data.objects[n] for n in stoffe])
    piastre_arp(nome, me, rig)
    pezzi_rigidi(me, rig)
    pesi_per_regione(me, rig)
    ## I capelli DOPO la pulizia: la regola della testa li lascerebbe com'erano, ma le
    ## isole li confronterebbero con le spalle su cui poggiano.
    capelli_arp(nome, me, rig)
    if uscita:
        return esporta_arp(uscita, me, rig)
    bpy.ops.wm.save_as_mainfile(filepath=RADICE_PROGETTO + "lavorazione/blender/campione_%s_arp.blend" % nome)
    return esporta_arp(RADICE_PROGETTO + "assets/characters/campioni/%s/%s_arp.glb" % (nome, nome), me, rig)


RADICE_PROGETTO = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
ATTRIBUTO_MASCHERA_ARP = "cloth_weight"
_RICETTA = None


def carica_ricetta():
    """Il namespace di monta_consumato_sylvorn.py (orfani, gabbia, maschera),
    una volta sola."""
    global _RICETTA
    if _RICETTA is None:
        _RICETTA = {"__name__": "monta_arp", "P": P}
        exec(compile(open(P, encoding="utf-8").read(), P, "exec"), _RICETTA)
    return _RICETTA
