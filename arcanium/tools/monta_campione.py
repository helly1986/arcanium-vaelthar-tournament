"""Monta un CAMPIONE (docs/campioni_concept.md) con la ricetta dei corpi Tripo
vestiti di `monta_consumato_sylvorn.py` (docs/05_RIG_CANONICO.md §4-ter): stessa
pipeline di Arcanium, cambiano solo le cartelle.

Si esegue DENTRO Blender, dal ponte (arcanium/tools/ponte_blender.py), un passo
per chiamata: il ponte ricrea il namespace ogni volta, la scena invece resta.

    exec(open(".../monta_campione.py").read())
    m = carica("edran")                    # la ricetta, puntata sul campione
    m["prepara"]("edran", altezza=1.86)    # sorgenti/edran.fbx, coi piedi a terra
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
    return ns


def pesi_gonna(nome_mesh="FanteSylvorn", nome_rig="FanteRig", raggio=None, sfuma=0.10, fascia=0.12):
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
    """
    import bpy
    from mathutils import Vector
    from mathutils.geometry import intersect_point_line
    me = bpy.data.objects[nome_mesh]
    rig = bpy.data.objects[nome_rig]
    mw = rig.matrix_world
    ossa = rig.data.bones
    segmenti = []
    for lato in ("L", "R"):
        for n in ("UpperLeg_%s" % lato, "LowerLeg_%s" % lato):
            b = ossa[n]
            segmenti.append((mw @ b.head_local, mw @ b.tail_local))
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
    toccati = 0
    for v in me.data.vertices:
        p = me.matrix_world @ v.co
        if p.z > anca + 0.02 or p.z < caviglia:
            continue
        pesi_gamba = [(g.group, g.weight) for g in v.groups if g.group in gambe and g.weight > 0.0]
        w = sum(x[1] for x in pesi_gamba)
        if w < 0.05:
            continue
        d = 1e9
        for a, b in segmenti:
            q, t = intersect_point_line(p, a, b)
            q = a if t < 0 else (b if t > 1 else q)
            d = min(d, (p - q).length)
        f = min(max((d - raggio) / sfuma, 0.0), 1.0)
        f = f * f * (3 - 2 * f)
        h = min(max((anca - p.z) / fascia, 0.0), 1.0)
        f *= h * h * (3 - 2 * h)
        if f <= 0.0:
            continue
        for gi, gw in pesi_gamba:
            me.vertex_groups[gi].add([v.index], gw * (1.0 - f), 'REPLACE')
        attuale = next((g.weight for g in v.groups if g.group == hips.index), 0.0)
        hips.add([v.index], attuale + w * f, 'REPLACE')
        toccati += 1
    print("pesi gonna: %d vertici passati (in parte) dalle gambe al bacino, raggio %.3f m" % (toccati, raggio))
    return toccati


def gonna_prima_della_cottura(m):
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
            pesi_gonna(me.name, puppet.name)
            fatto.append(True)
        return originale(me, puppet, fante)

    m["cuoci_nella_stance"] = cuoci
