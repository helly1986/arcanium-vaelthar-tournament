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
    pesi_per_regione(me, rig)
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
