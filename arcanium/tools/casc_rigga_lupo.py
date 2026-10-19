# -*- coding: utf-8 -*-
"""Il RIG FISICO quadrupede del lupo in Cascadeur, costruito a mano.

    python tools/cascadeur_mcp.py arcanium/tools/casc_rigga_lupo.py
    (le variabili GLB / SCALA / SALVA qui sotto dicono cosa importare e dove salvare)

Perche' esiste: l'ululato fatto a mano dall'utente (Lupo_Howl_AP.casc, 2026-08-09)
ha lo scheletro mappato ma NESSUN rig fisico (CMs 0, Units 0): senza centro di
massa non si sposta il peso e la fisica non ha niente da muovere. L'auto-rig
quadrupede di Cascadeur e' dietro la licenza PRO, ma la pipeline Python
(`create_quadruped_rig`) chiede solo il QrtData: lo si costruisce qui, con gli
object_id GIA' risolti (la trappola della skill cascadeur-mcp: il caricatore da
template non lega i giunti).

Il template di Cascadeur (Quadruped.qrigcasc) ha una colonna a cinque giunti e la
zampa anteriore a cinque ossa; il nostro lupo ha `Hips -> chest -> head` e
quattro ossa per zampa. Il rig chiede solo FEMUR_L/R (`get_required_nodes`):
le voci senza giunto si omettono, non si inventano.

⚠️ TAGLIA: in scena il lupo nasce alto 33 cm; Cascadeur conta in centimetri con
la gravita' vera, quindi per la fisica sarebbe un cagnolino. Si importa a
SCALA = 100 * 2.6 (il lupo comune in gioco, ~86 cm al garrese). All'export si
divide per lo stesso numero.
"""
import os
import csc
import pycsc

import rig_mode.on as rm_on
import rig_mode.off as rm_off
import prototypes.qrt_prototypes.create as qrt_create

GLB = r"C:\Users\Adriano\LOCAL\arcanium---vaelthar-tournament\lavorazione\cascadeur\lupo_bite_01_base.glb"
SCALA = 100.0 * 2.6
SALVA = r"C:\Users\Adriano\LOCAL\arcanium---vaelthar-tournament\lavorazione\cascadeur\lupo_bite_01_rig.casc"
COLORE_PUNTI = [0.0, 0.5, 0.0]

## Sezioni del QrtData quadrupede (QuadrupedBoneProperty): nome del metarig ->
## giunto del NOSTRO lupo. Gerarchia letta dal GLB:
##   Root > Hips > {backleg.., chest > {frontleg.., head > {jaw, headend, ears}}, tail > tailstart > tail1..3}
SEZIONI = {
    "trunk": [("pelvis", "Hips"), ("spine_1", "chest"), ("head", "head"), ("head_end", "headend"),
              ("tail_1", "tailstart"), ("tail_2", "tail1"), ("tail_3", "tail2"), ("tail_4", "tail3")],
    ## Anteriore: spalla -> gomito -> polso -> zampa. Manca la scapola come osso
    ## a se': il primo giunto della catena fa da omero.
    "left_fore_paw": [("humerus_l", "frontleg"), ("radius_l", "frontleg0"), ("carpals_l", "frontleg1"), ("paw_f_l", "frontleg2")],
    "right_fore_paw": [("humerus_r", "R_frontleg"), ("radius_r", "R_frontleg0"), ("carpals_r", "R_frontleg1"), ("paw_f_r", "R_frontleg2")],
    "left_hind_paw": [("femur_l", "backleg"), ("tibia_l", "backleg0"), ("tarsals_l", "backleg1"), ("paw_h_l", "backleg2")],
    "right_hind_paw": [("femur_r", "R_backleg"), ("tibia_r", "R_backleg0"), ("tarsals_r", "R_backleg1"), ("paw_h_r", "R_backleg2")],
}

def conta(ds):
    mv = ds.model_viewer()
    tipi = {}
    for o in mv.get_objects():
        t = mv.get_object_type_name(o)
        tipi[t] = tipi.get(t, 0) + 1
    return len(mv.get_objects()), tipi


app = csc.app.get_application()
sm = app.get_scene_manager()

## 1. Scena NUOVA: niente di quello che l'utente ha aperto viene toccato.
## ⚠️ Sempre nuova: riusare un "untitled" rimasto aperto ha riggato una base
## vecchia al posto di quella appena rigenerata (2026-10-09).
scena = sm.create_application_scene()
sm.set_current_scene(scena)
ds = scena.domain_scene()
io = csc.glb.ImportOptions()
io.include_objects = True
io.include_animation = True          # ⚠️ il default e' False
io.is_update_mode = False
io.throw_exception = True
io.scale_factor = SCALA
io.fps = 30.0
csc.glb.process_import(ds, GLB, io)
n, tipi = conta(ds)
print("IMPORT oggetti", n, tipi)

mv = ds.model_viewer()
per_nome = {mv.get_object_name(o): o for o in mv.get_objects() if mv.get_object_type_name(o) == "Joint"}
dv = mv.data_viewer()
ids = {dv.get_data_name(i): i for i in dv.get_all_data_id(per_nome["Hips"])}
print("BACINO a frame 0 (cm):", [round(float(x), 1) for x in dv.get_data_value(ids["Position"], 0)])

## 2. Il QrtData quadrupede, con gli object_id gia' legati.
q = csc.rig.QrtData()
q.is_align_pelvis = True
q.is_create_layers = True
qp = csc.rig.QuadrupedBoneProperty()
legati = 0
for sezione, voci in SEZIONI.items():
    gruppo = []
    for bone, giunto in voci:
        oid = per_nome.get(giunto)
        if oid is None:
            print("MANCA", giunto)
            continue
        bp = csc.rig.BoneProperty()
        bp.bone_name = bone
        bp.object_id = oid
        bp.joint_path_name = csc.model.PathName.get_path_name(oid, mv)
        gruppo.append(bp)
        legati += 1
    ## ⚠️ Ogni sezione vuole una LISTA DI LISTE (un gruppo per catena):
    ## con una lista semplice pybind solleva un TypeError.
    setattr(qp, sezione, [gruppo])
q.quadruped = [qp]
print("QRT legati", legati, "| quadruped tenuto:", len(q.quadruped) == 1)

## 3. Rig mode, rig, uscita.
rm_on.run_raw(ds, COLORE_PUNTI)
qrt_create.create_quadruped_rig(ds, q, 10.0, 10.0, COLORE_PUNTI, "")
n, tipi = conta(ds)
print("IN RIG MODE oggetti", n, tipi)
rm_off.run(ds, True)
n, tipi = conta(ds)
print("RIG FATTO oggetti", n, tipi)
ri = pycsc.wrap(ds).bv.get_behaviours("RigInfo")
print("RigInfo", len(ri))
scena.save(SALVA)
print("SALVATA", SALVA, os.path.exists(SALVA))
