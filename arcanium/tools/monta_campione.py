"""Monta un CAMPIONE (docs/campioni_concept.md) con la ricetta dei corpi Tripo
vestiti di `monta_consumato_sylvorn.py` (docs/05_RIG_CANONICO.md §4-ter): stessa
pipeline di Arcanium, cambiano solo le cartelle.

Si esegue DENTRO Blender, dal ponte (arcanium/tools/ponte_blender.py), un passo
per chiamata: il ponte ricrea il namespace ogni volta, la scena invece resta.

    exec(open(".../monta_campione.py").read())
    m = carica("edran")                    # la ricetta, puntata sul campione
    m["prepara"]("edran", altezza=1.86)    # sorgenti/edran.fbx, coi piedi a terra,
                                           # topologia ispezionata e saldata, ritocchi di colore
    m["rigga"]()                           # ARP, guscio per guscio
    m["travasa"](affila=False, falde=False, gabbia=True)
    m["esporta_glb"](m["DIR_SYLVORN"] + "edran_rigged.glb")

Il campione sta in assets/characters/campioni/<nome>/, la sorgente FBX di
Tripo in <nome>/sorgenti/ (con .gdignore: versionata, Godot non la importa).
"""
import os

P = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/arcanium/tools/monta_consumato_sylvorn.py"


def carica(nome):
    ns = {"__name__": "monta_campione", "P": P}
    exec(compile(open(P, encoding="utf-8").read(), P, "exec"), ns)
    cartella = ns["RADICE"] + "assets/characters/campioni/%s/" % nome
    ## Le funzioni della ricetta leggono queste globali del loro namespace.
    ns["DIR_SYLVORN"] = cartella
    ns["DIR_SORGENTI"] = cartella + "sorgenti/"
    os.makedirs(ns["DIR_SORGENTI"], exist_ok=True)
    ## Il passaggio obbligato (richiesta dell'autore, 2026-10-21): `prepara`
    ## non consegna una mesh di Tripo senza averla ispezionata e saldata, e
    ## senza i ritocchi di colore del campione. Si avvolge qui, cosi' nessuno
    ## script di montaggio puo' saltarlo.
    prepara = ns["prepara"]

    def prepara_controllata(nome_corpo, *a, **k):
        import bpy
        ## Le immagini dei corpi montati prima nella stessa sessione fanno
        ## nascere `Baked_BaseColor.001`: via gli orfani prima di importare.
        bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
        me = prepara(nome_corpo, *a, **k)
        controlla_e_ripara(me.name)
        ritocchi(nome, me.name)
        return me

    ns["prepara"] = prepara_controllata
    return ns


def ritocchi(nome, nome_mesh="CorpoSylvorn"):
    """I ritocchi di COLORE di ogni campione sulla texture di Tripo, decisi
    guardando il modello (2026-10-21). Il dark fantasy vuole tinte spente."""
    if nome == "edran":
        ## Capelli scuri, senza la ciocca bianca (sembrava Verso di Expedition
        ## 33); azzurro piu' opaco e cupo.
        capelli_scuri(1.715, nome_mesh, tempie=(0.065, 1.68))
        smorza_tinta((185, 225), saturazione=0.8, valore=0.68, s_min=0.15, nome_mesh=nome_mesh)
    elif nome == "ilwen":
        ## Il verde di armatura e mantellina, scurito.
        smorza_tinta((70, 170), saturazione=0.6, valore=0.72, nome_mesh=nome_mesh)


def _anelli_di_bordo(bm):
    """I bordi aperti raggruppati in anelli: ogni anello e' un buco (o l'orlo
    di una stoffa a un solo strato). Ritorna liste di spigoli, dal piu' lungo."""
    bordi = set(e for e in bm.edges if e.is_boundary)
    anelli = []
    while bordi:
        e0 = bordi.pop()
        anello, coda = [e0], [e0]
        while coda:
            e = coda.pop()
            for v in e.verts:
                for f in v.link_edges:
                    if f in bordi:
                        bordi.discard(f)
                        anello.append(f)
                        coda.append(f)
        anelli.append(anello)
    anelli.sort(key=len, reverse=True)
    return anelli


def ispeziona_topologia(nome_mesh="CorpoSylvorn", vicini=0.0005, stampa=True):
    """Il PASSAGGIO OBBLIGATO in Blender di ogni campione (richiesta
    dell'autore, 2026-10-21): i campioni sono i personaggi piu' importanti e
    non si monta una mesh di Tripo senza averla guardata.

    Conta le facce per lati (Tripo P2 deve dare quad, coi triangoli che lascia
    apposta, e nessun n-gon), i gusci, i bordi aperti raggruppati in anelli
    (buchi), gli spigoli non-manifold (piu' di due facce), i vertici a
    farfallino, spigoli e vertici volanti, le facce degeneri, le normali
    incoerenti fra facce vicine e i vertici ancora doppi entro `vicini` metri
    dopo la saldatura di `pulisci`. Ritorna un dizionario; con `stampa` lo
    scrive leggibile.
    """
    import bpy
    import bmesh
    from mathutils.kdtree import KDTree
    me = bpy.data.objects[nome_mesh]
    bm = bmesh.new()
    bm.from_mesh(me.data)
    bm.verts.ensure_lookup_table()
    lati = {}
    for f in bm.faces:
        k = min(len(f.verts), 5)
        lati[k] = lati.get(k, 0) + 1
    ## I gusci, e quali sono chiusi.
    visti, gusci = set(), []
    for v0 in bm.verts:
        if v0 in visti:
            continue
        pila, guscio = [v0], []
        visti.add(v0)
        while pila:
            v = pila.pop()
            guscio.append(v)
            for e in v.link_edges:
                w = e.other_vert(v)
                if w not in visti:
                    visti.add(w)
                    pila.append(w)
        gusci.append(guscio)
    aperti = 0
    for g in gusci:
        if any(e.is_boundary for v in g for e in v.link_edges):
            aperti += 1
    anelli = _anelli_di_bordo(bm)
    perimetri = [sum(e.calc_length() for e in a) for a in anelli]
    non_manifold = [e for e in bm.edges if len(e.link_faces) > 2]
    volanti_e = [e for e in bm.edges if not e.link_faces]
    volanti_v = [v for v in bm.verts if not v.link_edges]
    farfalle = [v for v in bm.verts if v.link_edges and not v.is_manifold and not v.is_boundary]
    degeneri = [f for f in bm.faces if f.calc_area() < 1e-10]
    incoerenti = [e for e in bm.edges if len(e.link_faces) == 2 and not e.is_contiguous]
    kd = KDTree(len(bm.verts))
    for v in bm.verts:
        kd.insert(v.co, v.index)
    kd.balance()
    doppi = sum(1 for v in bm.verts if len(kd.find_range(v.co, vicini)) > 1)
    esito = {
        "vertici": len(bm.verts), "facce": len(bm.faces),
        "triangoli": lati.get(3, 0), "quad": lati.get(4, 0), "ngon": lati.get(5, 0),
        "gusci": len(gusci), "gusci_aperti": aperti,
        "buchi": len(anelli), "spigoli_di_bordo": sum(len(a) for a in anelli),
        "anelli": [(len(a), round(p, 4)) for a, p in zip(anelli, perimetri)],
        "non_manifold": len(non_manifold), "farfalle": len(farfalle),
        "spigoli_volanti": len(volanti_e), "vertici_volanti": len(volanti_v),
        "degeneri": len(degeneri), "normali_incoerenti": len(incoerenti),
        "doppi": doppi,
    }
    bm.free()
    if stampa:
        print("topologia %s: %d vertici, %d facce = %d quad (%.1f%%) + %d triangoli + %d n-gon"
              % (nome_mesh, esito["vertici"], esito["facce"], esito["quad"],
                 100.0 * esito["quad"] / max(esito["facce"], 1), esito["triangoli"], esito["ngon"]))
        print("  gusci %d (aperti %d); buchi %d su %d spigoli di bordo; i piu' grandi (spigoli, perimetro m): %s"
              % (esito["gusci"], aperti, esito["buchi"], esito["spigoli_di_bordo"], esito["anelli"][:8]))
        print("  non-manifold %d, farfalle %d, volanti %d spigoli / %d vertici, degeneri %d, normali incoerenti %d, doppi entro %.1f mm %d"
              % (esito["non_manifold"], esito["farfalle"], esito["spigoli_volanti"], esito["vertici_volanti"],
                 esito["degeneri"], esito["normali_incoerenti"], vicini * 1000, doppi))
    return esito


def _gusci_per_faccia(bm):
    """Indice del guscio (componente connessa) di ogni faccia, per `f.index`.
    Gli indici si rinfrescano qui: dopo delete e split restano vecchi e
    doppi, e i gusci si mescolavano (Ilwen: mantellina girata a chiazze)."""
    bm.faces.index_update()
    bm.faces.ensure_lookup_table()
    gid = {}
    g = 0
    for f0 in bm.faces:
        if f0.index in gid:
            continue
        pila = [f0]
        gid[f0.index] = g
        while pila:
            f = pila.pop()
            for e in f.edges:
                for f2 in e.link_faces:
                    if f2.index not in gid:
                        gid[f2.index] = g
                        pila.append(f2)
        g += 1
    return gid


def _stacca_alette(bm):
    """Gli spigoli NON-MANIFOLD (tre o piu' facce: Tripo salda una ciocca, un
    colletto, una cinghia sulla superficie sotto) diventano gusci separati.

    Su ogni spigolo cattivo la coppia di facce che CONTINUA la superficie (la
    piu' vicina ai 180°, attorno allo spigolo) resta saldata; le altre sono
    alette. Si aprono TUTTI gli spigoli cattivi (`split_edges`), poi si
    risaldano solo le coppie che continuano: le alette restano dove sono, coi
    vertici sovrapposti. Nel render non cambia niente, i pesi della gabbia le
    trattano come gli altri strati. Staccare intere regioni non basta: un
    colletto saldato tutto attorno al collo separa testa e busto in due
    regioni, e una delle due finiva staccata.
    """
    import bmesh
    cattivi = [e for e in bm.edges if len(e.link_faces) > 2]
    if not cattivi:
        return 0
    coppie = []
    for e in cattivi:
        a, b = e.verts[0].co, e.verts[1].co
        asse = (b - a).normalized()
        mezzo = (a + b) / 2
        dirs = []
        for f in e.link_faces:
            d = f.calc_center_median() - mezzo
            d = (d - asse * d.dot(asse))
            dirs.append((f, d.normalized() if d.length > 1e-9 else d))
        p, q = min(((p, q) for i, p in enumerate(dirs) for q in dirs[i + 1:]),
                   key=lambda pq: pq[0][1].dot(pq[1][1]))
        coppie.append((p[0], q[0], a.copy(), b.copy()))
    bmesh.ops.split_edges(bm, edges=cattivi)

    def vertice(f, co):
        return min(f.verts, key=lambda v: (v.co - co).length_squared)

    unisci = {}

    def radice(v):
        while v in unisci:
            v = unisci[v]
        return v

    for f1, f2, a, b in coppie:
        for co in (a, b):
            v1, v2 = radice(vertice(f1, co)), radice(vertice(f2, co))
            if v1 is not v2:
                unisci[v2] = v1
    mappa = {v: radice(v) for v in unisci}
    bmesh.ops.weld_verts(bm, targetmap=mappa)
    return len(cattivi)


def _separa_farfalle(bm):
    """Un vertice dove due ventagli di facce si toccano solo in un punto
    (farfallino) diventa un vertice per ventaglio."""
    import bmesh
    farfalle = [v for v in bm.verts if v.link_edges and not v.is_manifold and not v.is_boundary]
    n = 0
    for v in farfalle:
        if v.is_valid and not v.is_manifold:
            n += len(bmesh.utils.vert_separate(v, [])) - 1
    return n


def _chiudi_buchi(bm, buco_max, coperto=0.004):
    """Chiude i buchi VERI: anelli di bordo con perimetro sotto `buco_max` che
    non poggiano su un altro guscio. Gli orli lunghi (fondo della tunica,
    maniche, ciocche) sono il bordo della stoffa e restano; gli orli che
    poggiano su un altro guscio (una piastra appoggiata al busto) sono
    giunzioni nascoste. La faccia nuova si triangola, e prende le UV dei
    vertici dalle facce accanto."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    bm.faces.ensure_lookup_table()
    gid = _gusci_per_faccia(bm)
    bvh = BVHTree.FromBMesh(bm)
    da_chiudere = []
    for a in _anelli_di_bordo(bm):
        if sum(e.calc_length() for e in a) >= buco_max:
            continue
        vs = set(v for e in a for v in e.verts)
        mio = gid[a[0].link_faces[0].index]
        sopra = sum(1 for v in vs if any(gid[i] != mio for (_c, _n, i, _d) in bvh.find_nearest_range(v.co, coperto)))
        if sopra < 0.6 * len(vs):
            da_chiudere.append(a)
    uv = bm.loops.layers.uv.active
    chiusi = 0
    for a in da_chiudere:
        vecchie = set(f for e in a for v in e.verts for f in v.link_faces)
        nuove = bmesh.ops.holes_fill(bm, edges=a, sides=0)["faces"]
        if not nuove:
            continue
        tri = bmesh.ops.triangulate(bm, faces=nuove, quad_method='BEAUTY', ngon_method='BEAUTY')["faces"]
        if uv is not None:
            for f in tri:
                for l in f.loops:
                    altra = next((l2 for l2 in l.vert.link_loops if l2.face in vecchie), None)
                    if altra is not None:
                        l[uv].uv = altra[uv].uv
        ## Il verso come le facce accanto.
        for f in tri:
            vicine = [f2 for e in f.edges for f2 in e.link_faces if f2 in vecchie]
            if vicine and sum(1 for f2 in vicine if f.normal.dot(f2.normal) < 0) * 2 > len(vicine):
                f.normal_flip()
        chiusi += 1
    return chiusi


def _degeneri(bm):
    """Via le facce degeneri: spigoli sotto il micron, e facce ad area nulla
    con spigoli lunghi (tre vertici in fila), dove si fonde lo spigolo piu'
    corto e la faccia sparisce. Ritorna quante facce sono sparite."""
    import bmesh
    n = len(bm.faces)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-6)
    for f in [f for f in bm.faces if f.calc_area() < 1e-10]:
        if f.is_valid:
            e = min(f.edges, key=lambda e: e.calc_length())
            bmesh.ops.pointmerge(bm, verts=list(e.verts), merge_co=e.verts[0].co)
    return n - len(bm.faces)


def ripara_topologia(nome_mesh="CorpoSylvorn", buco_max=0.05):
    """Le SALDATURE di rito su una mesh di Tripo, dopo `pulisci` (che salda le
    cuciture UV a 0,1 mm): via le facce degeneri e i vertici volanti, facce
    interne buttate, alette non-manifold staccate in gusci loro, farfallini
    separati, buchi veri chiusi, n-gon triangolati, spigoli fra facce di
    verso opposto aperti. I quad restano quad: niente
    `tris_convert_to_quads` (fonderebbe i triangoli che Tripo lascia apposta,
    vedi `prepara`). Ritorna il conto di cio' che ha fatto; l'esito si legge
    con `ispeziona_topologia`."""
    import bpy
    import bmesh
    me = bpy.data.objects[nome_mesh]
    bm = bmesh.new()
    bm.from_mesh(me.data)
    fatto = {}
    fatto["degeneri"] = _degeneri(bm)
    volanti = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=volanti, context='VERTS')
    fatto["volanti"] = len(volanti)
    ## Le facce INTERNE: ogni loro spigolo ha piu' di due facce, sono pareti
    ## dentro il volume (Ilwen: un grumo di triangoli da un millimetro sotto la
    ## fibbia del petto). Si buttano, come `select_interior_faces`, finche' ce
    ## ne sono: toglierne una puo' scoprirne un'altra.
    fatto["interne"] = 0
    while True:
        interne = [f for f in bm.faces if all(len(e.link_faces) > 2 for e in f.edges)]
        if not interne:
            break
        bmesh.ops.delete(bm, geom=interne, context='FACES_ONLY')
        fatto["interne"] += len(interne)
    sciolti = [e for e in bm.edges if not e.link_faces]
    bmesh.ops.delete(bm, geom=sciolti, context='EDGES')
    sciolti = [v for v in bm.verts if not v.link_edges]
    bmesh.ops.delete(bm, geom=sciolti, context='VERTS')
    fatto["alette"] = 0
    for _giro in range(3):
        k = _stacca_alette(bm)
        fatto["alette"] += k
        if k == 0:
            break
    fatto["farfalle"] = _separa_farfalle(bm)
    ## Risaldare le alette puo' schiacciare qualche faccia.
    fatto["degeneri"] += _degeneri(bm)
    ## I buchi si chiudono PRIMA dell'ultima passata, che sistema anche il
    ## verso dei triangoli nuovi.
    fatto["buchi"] = _chiudi_buchi(bm, buco_max)
    ngon = [f for f in bm.faces if len(f.verts) > 4]
    bmesh.ops.triangulate(bm, faces=ngon, quad_method='BEAUTY', ngon_method='BEAUTY')
    fatto["ngon"] = len(ngon)
    ## Cio' che resta si apre e basta: spigoli ancora non-manifold (le coppie
    ## risaldate possono ricucirne qualcuno), spigoli fra facce che non si
    ## mettono d'accordo sul verso e facce degeneri sopravvissute. Vertici
    ## sovrapposti, nel render non si vede.
    ## ⚠️ Il verso delle facce NON si ricalcola: `recalc_face_normals`, anche
    ## tenendo il verso della maggioranza di ogni guscio, girava 913 facce di
    ## Ilwen e la mantellina si vedeva dal rovescio a chiazze. Il verso di
    ## Tripo e' giusto nel render; dove due zone non concordano si apre lo
    ## spigolo fra loro e ognuna tiene il suo.
    fatto["aperti"] = 0
    for _giro in range(3):
        resto = [e for e in bm.edges if len(e.link_faces) > 2
                 or (len(e.link_faces) == 2 and not e.is_contiguous)]
        piatte = [f for f in bm.faces if f.calc_area() < 1e-10]
        if not resto and not piatte:
            break
        bmesh.ops.delete(bm, geom=piatte, context='FACES_ONLY')
        if resto:
            bmesh.ops.split_edges(bm, edges=[e for e in resto if e.is_valid])
        fatto["aperti"] += len(resto)
        fatto["farfalle"] += _separa_farfalle(bm)
        sciolti = [e for e in bm.edges if not e.link_faces]
        bmesh.ops.delete(bm, geom=sciolti, context='EDGES')
        sciolti = [v for v in bm.verts if not v.link_edges]
        bmesh.ops.delete(bm, geom=sciolti, context='VERTS')
    bm.normal_update()
    bm.to_mesh(me.data)
    bm.free()
    me.data.update()
    print("riparazione %s: %s" % (nome_mesh, fatto))
    return fatto


def controlla_e_ripara(nome_mesh="CorpoSylvorn", buco_max=0.05):
    """Il passaggio obbligato: ispezione, saldature, ispezione di nuovo.
    Fallisce se dopo le saldature restano n-gon, spigoli non-manifold,
    farfallini, degeneri o normali incoerenti: allora si guarda la mesh a mano
    prima di riggarla."""
    prima = ispeziona_topologia(nome_mesh)
    fatto = ripara_topologia(nome_mesh, buco_max)
    dopo = ispeziona_topologia(nome_mesh)
    resta = {k: dopo[k] for k in ("ngon", "non_manifold", "farfalle", "degeneri", "normali_incoerenti", "vertici_volanti")
             if dopo[k]}
    if resta:
        raise RuntimeError("topologia di %s ancora sporca dopo le saldature: %s" % (nome_mesh, resta))
    return prima, fatto, dopo


def _texture(nome_mesh="CorpoSylvorn"):
    """La texture del corpo come array numpy alto x largo x 4, con l'immagine.
    Si prende dal MATERIALE della mesh, non per nome: nella stessa sessione
    di Blender restano le immagini dei corpi montati prima, e la nuova si
    chiama `Baked_BaseColor.001` (si ridipingeva la texture di un altro)."""
    import bpy
    import numpy as np
    me = bpy.data.objects[nome_mesh]
    img = next(n.image for s in me.material_slots if s.material and s.material.node_tree
               for n in s.material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    return img, px.reshape(h, w, 4)


def _salva_texture(img, px):
    """Rimette i pixel nell'immagine e la reimpacchetta in JPEG: l'export
    glTF la scrive cosi' com'e' impacchettata, e Godot ritrova
    `<corpo>_rigged_Baked_BaseColor.jpg` (un PNG sarebbe un file nuovo)."""
    img.pixels.foreach_set(px.ravel())
    img.file_format = 'JPEG'
    img.pack()
    img.filepath_raw = "//Baked_BaseColor.jpg"


def _hsv(rgb):
    import numpy as np
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == r, ((g - b) / dd) % 6, np.where(mx == g, (b - r) / dd + 2, (r - g) / dd + 4)) * 60.0
    return np.where(d > 1e-6, h, 0.0), s, mx


def _rgb(h, s, v):
    import numpy as np
    c = v * s
    x = c * (1 - np.abs((h / 60.0) % 2 - 1))
    m = v - c
    z = np.zeros_like(h)
    k = (h // 60).astype(int) % 6
    r = np.choose(k, [c, x, z, z, x, c])
    g = np.choose(k, [x, c, c, x, z, z])
    b = np.choose(k, [z, z, x, c, c, x])
    return np.stack([r + m, g + m, b + m], -1)


def smorza_tinta(tonalita, saturazione=0.6, valore=0.75, s_min=0.10, sfuma=12.0, nome_mesh="CorpoSylvorn"):
    """Spegne UNA tinta della texture: il dark fantasy (richiesta dell'autore,
    2026-10-21: il verde di Ilwen e l'azzurro di Edran erano troppo accesi).

    I pixel con tonalita' fra `tonalita` (gradi, (da, a)) e saturazione sopra
    `s_min` prendono saturazione x`saturazione` e luminosita' x`valore`; ai
    bordi della fascia di tonalita' (`sfuma` gradi) e sopra `s_min` (0,08 di
    rampa) l'effetto entra piano, cosi' non restano scalini. Pelle, capelli e
    metallo grigio, fuori fascia o quasi senza saturazione, non si toccano.
    Ritorna la quota di pixel toccati in pieno."""
    import numpy as np
    img, px = _texture(nome_mesh)
    h, s, v = _hsv(px[..., :3])
    da, a = tonalita
    dentro = np.minimum(np.clip((h - (da - sfuma)) / sfuma, 0, 1), np.clip(((a + sfuma) - h) / sfuma, 0, 1))
    w = dentro * np.clip((s - s_min) / 0.08, 0, 1)
    s2 = s * (1 - w * (1 - saturazione))
    v2 = v * (1 - w * (1 - valore))
    px[..., :3] = _rgb(h, s2, v2)
    _salva_texture(img, px)
    pieno = float((w > 0.99).mean())
    print("tinta %s smorzata (saturazione x%.2f, luce x%.2f): %.1f%% dei pixel" % (tonalita, saturazione, valore, 100 * pieno))
    return pieno


def _rasterizza(poligoni, uvl, W, H, margine=0):
    """I pixel della texture coperti dai triangoli UV di `poligoni`, piu'
    `margine` pixel attorno ai lati: maschera booleana alto x largo."""
    import numpy as np
    maschera = np.zeros((H, W), dtype=bool)
    for p in poligoni:
        uv = [(uvl[i].uv[0] * W, uvl[i].uv[1] * H) for i in p.loop_indices]
        for k in range(1, len(uv) - 1):
            tri = np.array([uv[0], uv[k], uv[k + 1]])
            x0, y0 = np.floor(tri.min(0)).astype(int) - margine
            x1, y1 = np.ceil(tri.max(0)).astype(int) + margine
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, W - 1), min(y1, H - 1)
            if x1 < x0 or y1 < y0:
                continue
            yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
            px, py = xx + 0.5, yy + 0.5
            a, b, c = tri
            def lato(p1, p2):
                return (p2[0] - p1[0]) * (py - p1[1]) - (p2[1] - p1[1]) * (px - p1[0])
            d1, d2, d3 = lato(a, b), lato(b, c), lato(c, a)
            dentro = ((d1 >= 0) & (d2 >= 0) & (d3 >= 0)) | ((d1 <= 0) & (d2 <= 0) & (d3 <= 0))
            if margine > 0:
                def dist(p1, p2, d):
                    return np.abs(d) / max(np.hypot(p2[0] - p1[0], p2[1] - p1[1]), 1e-6)
                dentro |= (dist(a, b, d1) < margine) | (dist(b, c, d2) < margine) | (dist(c, a, d3) < margine)
            maschera[y0:y1 + 1, x0:x1 + 1] |= dentro
    return maschera


def capelli_scuri(sopra, nome_mesh="CorpoSylvorn", chiari=0.42, colore=None, tempie=None):
    """Ridipinge di scuro le CIOCCHE CHIARE dei capelli (Edran, 2026-10-21:
    la ciocca bianca alla tempia lo faceva sembrare Verso di Expedition 33).

    Si prendono le facce sopra la quota `sopra` (metri: sotto la riga dei
    capelli, sopra gli occhi); con `tempie=(x, quota)`, di lato agli occhi
    (|x| oltre `x` metri) si scende fino a `quota`, per le ciocche che pendono
    sulle tempie. Nei loro triangoli UV, piu' due pixel di margine, ogni pixel
    CHIARO (luce sopra `chiari`) e NEUTRO O FREDDO (quasi senza saturazione, o
    poco saturo e azzurrino) prende il colore medio dei capelli scuri
    (`colore`, o la media dei texel scuri di quelle facce), tenendo le sue
    variazioni di luce. La pelle della fronte e' chiara ma CALDA, e resta.
    Scegliere le facce dal texel al centro non bastava: meta' ciocca restava,
    e un riquadro di fronte diventava nero. Ritorna le facce guardate."""
    import bpy
    import numpy as np
    img, px = _texture(nome_mesh)
    H, W = px.shape[:2]
    me = bpy.data.objects[nome_mesh]
    uvl = me.data.uv_layers.active.data
    def texel(poly):
        u = sum(uvl[i].uv[0] for i in poly.loop_indices) / poly.loop_total
        v = sum(uvl[i].uv[1] for i in poly.loop_indices) / poly.loop_total
        return px[min(int(v * H), H - 1), min(int(u * W), W - 1), :3]
    mw = me.matrix_world
    ciocca, scure = [], []
    for p in me.data.polygons:
        c = mw @ p.center
        soglia = tempie[1] if tempie and abs(c.x) > tempie[0] else sopra
        if c.z < soglia:
            continue
        ciocca.append(p)
        t = texel(p)
        if t.max() < 0.25:
            scure.append(t)
    if colore is None:
        colore = np.mean(scure, axis=0) if scure else np.array([0.06, 0.06, 0.07])
    colore = np.asarray(colore, dtype=np.float32)
    ## Il margine di due pixel sconfina sulle isole vicine dell'atlas (barba,
    ## gorgiera, spallaccio a chiazze nere): i pixel coperti da una faccia
    ## NON di capelli sono protetti, il margine resta solo nel vuoto fra isole.
    scelte = set(p.index for p in ciocca)
    maschera = _rasterizza(ciocca, uvl, W, H, margine=2)
    protetti = _rasterizza([p for p in me.data.polygons if p.index not in scelte], uvl, W, H, margine=0)
    maschera &= ~protetti
    h, s, v = _hsv(px[..., :3])
    tocca = maschera & (v > chiari) & ((s < 0.08) | ((s < 0.30) & (h > 170) & (h < 270)))
    luce = v[tocca]
    if luce.size:
        rel = (luce - luce.min()) / max(luce.max() - luce.min(), 1e-6)
        px[tocca, :3] = colore[None, :] * (0.7 + 0.7 * rel)[:, None]
        _salva_texture(img, px)
    print("capelli scuri: %d facce sopra %.2f m, %d pixel ridipinti col colore %s"
          % (len(ciocca), sopra, int(tocca.sum()), np.round(colore, 3)))
    return ciocca


def pesi_gonna(nome_mesh="FanteSylvorn", nome_rig="FanteRig", raggio=None, sfuma=0.10, fascia=0.12,
               strati=False, segue_gamba=0.2, strato_da=None):
    """Le VESTI LUNGHE che non si stendono fra le gambe (Ilwen, 2026-10-21).

    Una tunica o un grembiule con un pannello unico fra le gambe, pesato a meta'
    fra le due cosce, nella posa larga del moveset si apre come una membrana.
    Qui ogni vertice fra l'anca e la caviglia che pesa sulle gambe passa al
    bacino (`Hips`) tanto piu' quanto e' LONTANO dall'asse della gamba piu'
    vicina: pantaloni e stivali (entro `raggio`) restano alle gambe, la stoffa
    che si allarga e il pannello in mezzo seguono il bacino, con `sfuma` metri
    di passaggio. Si chiama dopo `travasa`, prima di `esporta_glb`.

    In alto l'effetto parte da zero all'altezza dell'anca e arriva pieno
    `fascia` metri piu' giu': la cintura della veste resta col busto. Senza,
    piegando la colonna la fascia alta del grembiule si staccava dal corpetto
    (Kessra, 2026-10-21: schegge alla vita, e nella idle sopra le braccia).

    E la stoffa sotto la vita, vicino all'asse del corpo, non pesa MAI su
    braccia e mani: in A-pose le mani pendono accanto alle falde di una veste
    larga, la gabbia dei pesi le mescola, e nella idle il grembiule di Kessra
    seguiva gli avambracci in avanti. Quel peso passa al bacino.

    `strati=True` per le vesti LUNGHE fuse col corpo in un guscio solo (Aurin,
    Rashan): l'orlo che pende accanto allo stinco sta dentro `raggio` e
    restava sulla gamba, e i pannelli si aprivano ad ali. Un vertice e' lo
    STRATO ESTERNO se sta oltre `raggio` e il raggio dall'asse della gamba
    verso di lui incontra prima un'altra superficie (i pantaloni): allora segue la gamba solo per
    `segue_gamba`, e solo la coscia; il resto passa al bacino, a qualunque
    distanza. `strato_da` (metri) abbassa la soglia per un grembiule stretto
    sui pantaloni larghi (Kessra), che sta tutto dentro `raggio`.
    """
    import bpy
    from mathutils import Vector
    from mathutils.geometry import intersect_point_line
    me = bpy.data.objects[nome_mesh]
    rig = bpy.data.objects[nome_rig]
    mw = rig.matrix_world
    ossa = rig.data.bones
    ## Ogni segmento va dalla testa dell'osso a quella del FIGLIO (ginocchio,
    ## caviglia): le code delle ossa Nephilite sono corte (`UpperLeg` 6 cm,
    ## `LowerLeg` 1,5 cm), e fino al 2026-10-21 la distanza si misurava da due
    ## moncherini vicino ad anca e ginocchio, e la "caviglia" usciva al
    ## ginocchio (0,46 m su 1,78): la veste sotto il ginocchio restava sugli
    ## stinchi (Rashan e Aurin ad ali, e i pantaloni di Kessra).
    segmenti = []
    for lato in ("L", "R"):
        for n in ("UpperLeg_%s" % lato, "LowerLeg_%s" % lato):
            b = ossa[n]
            figli = [c for c in b.children if "Attachment" not in c.name]
            fine = min(figli, key=lambda c: c.head_local.z).head_local if figli else b.tail_local
            segmenti.append((mw @ b.head_local, mw @ fine))
    anca = max(s[0].z for s in segmenti[0::2])
    caviglia = min(s[1].z for s in segmenti[1::2])
    altezza = max((me.matrix_world @ v.co).z for v in me.data.vertices)
    if raggio is None:
        raggio = 0.085 * altezza / 1.8
    gruppi = {g.name: g.index for g in me.vertex_groups}
    gambe = [gruppi[n] for n in ("UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R") if n in gruppi]
    hips = me.vertex_groups["Hips"]
    braccia = [g.index for g in me.vertex_groups
               if any(k in g.name for k in ("Clavicle", "Shoulder", "Elbow", "Hand", "Finger", "Thumb", "Wrist", "Arm"))]
    asse = 0.30 * altezza / 1.8
    tolti = 0
    for v in me.data.vertices:
        p = me.matrix_world @ v.co
        if p.z > anca + 0.05 or abs(p.x) > asse:
            continue
        sulle_braccia = [(g.group, g.weight) for g in v.groups if g.group in braccia and g.weight > 0.0]
        if not sulle_braccia:
            continue
        w = sum(x[1] for x in sulle_braccia)
        for gi, _gw in sulle_braccia:
            me.vertex_groups[gi].remove([v.index])
        attuale = next((g.weight for g in v.groups if g.group == hips.index), 0.0)
        hips.add([v.index], attuale + w, 'REPLACE')
        tolti += 1
    print("pesi gonna: %d vertici della veste tolti da braccia e mani" % tolti)
    bvh = None
    if strati:
        import bmesh
        from mathutils.bvhtree import BVHTree
        bm = bmesh.new()
        bm.from_mesh(me.data)
        bm.transform(me.matrix_world)
        bvh = BVHTree.FromBMesh(bm)
        bm.free()
    toccati = esterni = 0
    for v in me.data.vertices:
        p = me.matrix_world @ v.co
        if p.z > anca + 0.02 or p.z < caviglia:
            continue
        pesi_gamba = [(g.group, g.weight) for g in v.groups if g.group in gambe and g.weight > 0.0]
        w = sum(x[1] for x in pesi_gamba)
        if w < 0.05:
            continue
        d, qq = 1e9, None
        for a, b in segmenti:
            q, t = intersect_point_line(p, a, b)
            q = a if t < 0 else (b if t > 1 else q)
            if (p - q).length < d:
                d, qq = (p - q).length, q
        f = min(max((d - raggio) / sfuma, 0.0), 1.0)
        f = f * f * (3 - 2 * f)
        h = min(max((anca - p.z) / fascia, 0.0), 1.0)
        h = h * h * (3 - 2 * h)
        esterno = False
        if bvh is not None and d > (raggio if strato_da is None else strato_da):
            loc, _n, _i, dist = bvh.ray_cast(qq, (p - qq).normalized(), d - 0.01)
            if loc is not None:
                f = max(f, 1.0 - segue_gamba)
                esterno = True
                esterni += 1
        f *= h
        if f <= 0.0:
            continue
        ## Lo strato esterno si appoggia al ginocchio, non segue lo stinco: il
        ## peso dello stinco passa alla coscia dello stesso lato. Con lo
        ## stinco (leva lunga) l'orlo di Rashan si apriva ad ali nella idle.
        resto = {}
        for gi, gw in pesi_gamba:
            nome = me.vertex_groups[gi].name
            if esterno and nome.startswith("LowerLeg_"):
                me.vertex_groups[gi].remove([v.index])
                gi = gruppi["UpperLeg_" + nome[-1]]
            resto[gi] = resto.get(gi, 0.0) + gw * (1.0 - f)
        for gi, gw in resto.items():
            me.vertex_groups[gi].add([v.index], gw, 'REPLACE')
        attuale = next((g.weight for g in v.groups if g.group == hips.index), 0.0)
        hips.add([v.index], attuale + w * f, 'REPLACE')
        toccati += 1
    print("pesi gonna: %d vertici passati (in parte) dalle gambe al bacino, raggio %.3f m%s"
          % (toccati, raggio, ", %d sullo strato esterno" % esterni if strati else ""))
    return toccati


def capelli_alla_testa(nome_mesh="FanteSylvorn", nome_rig="FanteRig", quota_testa=0.8):
    """I CAPELLI LUNGHI seguono la testa, rigidi (Aurin, 2026-10-21).

    I capelli fino alle spalle toccano clavicole e spallacci: ARP e la gabbia
    dei pesi li mescolano a quelle ossa, e nella posa di guardia le ciocche
    schizzavano di lato e una passava davanti alla fronte. Qui ogni guscio
    che e' attaccato alla testa (almeno un vertice con `Head` sopra
    `quota_testa`), che arriva sopra gli occhi e che non e' il corpo (meno
    di un quinto dei vertici) passa tutto su `Head`. Colletti e sciarpe non
    hanno vertici sulla testa e restano come sono. Ritorna i gusci toccati.
    """
    import bpy
    import bmesh
    me = bpy.data.objects[nome_mesh]
    rig = bpy.data.objects[nome_rig]
    head = me.vertex_groups.get("Head")
    if head is None:
        return 0
    occhi = (rig.matrix_world @ rig.data.bones["Head"].head_local).z + 0.06
    bm = bmesh.new()
    bm.from_mesh(me.data)
    bm.verts.ensure_lookup_table()
    visti, gusci = set(), []
    for v0 in bm.verts:
        if v0.index in visti:
            continue
        pila, g = [v0], []
        visti.add(v0.index)
        while pila:
            v = pila.pop()
            g.append(v.index)
            for e in v.link_edges:
                w = e.other_vert(v)
                if w.index not in visti:
                    visti.add(w.index)
                    pila.append(w)
        gusci.append(g)
    bm.free()
    mw = me.matrix_world
    totale = len(me.data.vertices)
    toccati = 0
    for g in gusci:
        if len(g) > totale / 5:
            continue
        vs = [me.data.vertices[i] for i in g]
        if max((mw @ v.co).z for v in vs) < occhi:
            continue
        if max((x.weight for v in vs for x in v.groups if x.group == head.index), default=0.0) < quota_testa:
            continue
        for v in vs:
            for x in list(v.groups):
                me.vertex_groups[x.group].remove([v.index])
            head.add([v.index], 1.0, 'REPLACE')
        toccati += 1
    print("capelli alla testa: %d gusci, sopra gli occhi (%.2f m) e attaccati alla testa" % (toccati, occhi))
    return toccati


def capelli_prima_della_cottura(m):
    """`capelli_alla_testa` anche PRIMA della cottura, sul puppet in A-pose:
    se no le ciocche cuociono gia' spostate dalle spalle nel riposo del GLB.
    Si chiama di nuovo dopo `travasa`, perche' la gabbia rimescola i pesi."""
    originale = m["cuoci_nella_stance"]
    fatto = []

    def cuoci(me, puppet, fante):
        if not fatto:
            capelli_alla_testa(me.name, puppet.name)
            fatto.append(True)
        return originale(me, puppet, fante)

    m["cuoci_nella_stance"] = cuoci


def veste_a_piombo(m, fascia=0.20):
    """Le vesti LUNGHE restano a piombo nella posa di guardia (Aurin e Rashan,
    2026-10-21).

    Nella stance del FanteRig il bacino ruota di ~28° rispetto all'A-pose:
    quasi tutto torsione attorno alla verticale, ma con ~8° di beccheggio e
    ~6° di rollio. Una veste che pende dal bacino (i pesi che `pesi_gonna`
    porta su `Hips`) cuocendo ruota con lui tutta intera: l'orlo di un
    cappotto lungo 90 cm si stacca di 10-15 cm e nel riposo del GLB i pannelli
    stanno aperti ad ali ai lati delle ginocchia.

    Qui si avvolge `cuoci_nella_stance`: dopo la cottura ogni vertice sotto
    l'anca che pende dal bacino prende la posizione che avrebbe se il bacino
    avesse fatto solo lo SPOSTAMENTO e la TORSIONE (la veste gira attorno al
    corpo e resta un tubo verticale), non l'inclinazione. L'effetto parte da
    zero all'anca e arriva pieno `fascia` metri sotto, cosi' la cintura resta
    attaccata al busto; e si sostituisce SOLO la parte del bacino nella somma
    pesata della pelle (quota di `Hips` del vertice): pantaloni e stivali,
    sulle gambe, non si toccano, e dove la veste passa alle gambe non escono
    scalini (con una soglia sulla quota l'orlo si staccava a meta' coscia). Si ricalcola a ogni
    cottura dall'A-pose (anche quelle di `ripara_stirati`): non si compone.
    """
    from mathutils import Quaternion
    originale = m["cuoci_nella_stance"]

    def cuoci(me, puppet, fante):
        mw = me.matrix_world.copy()
        A = [mw @ v.co for v in me.data.vertices]
        out = originale(me, puppet, fante)
        bp, bf = puppet.data.bones["Hips"], fante.data.bones["Hips"]
        hA = puppet.matrix_world @ bp.head_local
        hS = fante.matrix_world @ bf.head_local
        RA = (puppet.matrix_world.to_3x3() @ bp.matrix_local.to_3x3()).to_quaternion()
        RS = (fante.matrix_world.to_3x3() @ bf.matrix_local.to_3x3()).to_quaternion()
        q = RS @ RA.inverted()
        torsione = Quaternion((q.w, 0.0, 0.0, q.z)).normalized()
        anca = sum((puppet.matrix_world @ puppet.data.bones[n].head_local).z for n in ("UpperLeg_L", "UpperLeg_R")) / 2
        hips = me.vertex_groups.get("Hips")
        if hips is None:
            return out
        mw = me.matrix_world
        inv = mw.inverted()
        R = q.to_matrix()
        Rt = torsione.to_matrix()
        toccati = 0
        for v, a in zip(me.data.vertices, A):
            h = min(max((anca - a.z) / fascia, 0.0), 1.0)
            if h <= 0.0:
                continue
            tot = sum(g.weight for g in v.groups)
            wh = next((g.weight for g in v.groups if g.group == hips.index), 0.0) / tot if tot > 0 else 0.0
            if wh <= 0.0:
                continue
            ## La pelle e' una somma pesata di trasformazioni: si sostituisce
            ## solo quella del bacino, col suo peso. Lineare, niente scalini
            ## dove la veste passa dal bacino alle gambe.
            delta = (hS + Rt @ (a - hA)) - (hS + R @ (a - hA))
            v.co = inv @ ((mw @ v.co) + delta * (wh * h * h * (3 - 2 * h)))
            toccati += 1
        print("veste a piombo: %d vertici, inclinazione del bacino tolta %.1f° (torsione %.1f° tenuta)"
              % (toccati, __import__("math").degrees((torsione.inverted() @ q).angle),
                 __import__("math").degrees(torsione.angle)))
        return out

    m["cuoci_nella_stance"] = cuoci


def gonna_prima_della_cottura(m, **opzioni):
    """Applica `pesi_gonna` anche PRIMA della cottura nella posa di guardia.

    `travasa` cuoce la mesh dall'A-pose alla stance del FanteRig: una veste
    pesata sulle cosce viene SOLLEVATA dalle cosce piegate e resta cosi' nel
    riposo del GLB (Kessra, 2026-10-21: il grembiule ai fianchi, e nella idle
    fino al petto, sopra le braccia). Si avvolge `cuoci_nella_stance` nel
    namespace della ricetta: la prima volta i pesi della veste passano al
    bacino sul puppet in A-pose, poi la cottura procede. Una volta sola,
    perche' `ripara_stirati` ricuoce e la correzione non va composta.
    """
    originale = m["cuoci_nella_stance"]
    fatto = []

    def cuoci(me, puppet, fante):
        if not fatto:
            pesi_gonna(me.name, puppet.name, **opzioni)
            fatto.append(True)
        return originale(me, puppet, fante)

    m["cuoci_nella_stance"] = cuoci
