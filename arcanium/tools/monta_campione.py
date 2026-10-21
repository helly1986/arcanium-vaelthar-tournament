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


def pesi_gonna(nome_mesh="FanteSylvorn", nome_rig="FanteRig", raggio=None, sfuma=0.10):
    """Le VESTI LUNGHE che non si stendono fra le gambe (Ilwen, 2026-10-21).

    Una tunica o un grembiule con un pannello unico fra le gambe, pesato a meta'
    fra le due cosce, nella posa larga del moveset si apre come una membrana.
    Qui ogni vertice fra l'anca e la caviglia che pesa sulle gambe passa al
    bacino (`Hips`) tanto piu' quanto e' LONTANO dall'asse della gamba piu'
    vicina: pantaloni e stivali (entro `raggio`) restano alle gambe, la stoffa
    che si allarga e il pannello in mezzo seguono il bacino, con `sfuma` metri
    di passaggio. Si chiama dopo `travasa`, prima di `esporta_glb`.
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
        if f <= 0.0:
            continue
        for gi, gw in pesi_gamba:
            me.vertex_groups[gi].add([v.index], gw * (1.0 - f), 'REPLACE')
        attuale = next((g.weight for g in v.groups if g.group == hips.index), 0.0)
        hips.add([v.index], attuale + w * f, 'REPLACE')
        toccati += 1
    print("pesi gonna: %d vertici passati (in parte) dalle gambe al bacino, raggio %.3f m" % (toccati, raggio))
    return toccati
