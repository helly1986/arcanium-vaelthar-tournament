# -*- coding: utf-8 -*-
"""La coda del lupo non deve bucare il suolo: la si alza dove serve, frame per frame.

    blender --background --factory-startup --python arcanium/tools/alza_coda_lupo.py -- <in.glb> <out.glb>

`in.glb` e' l'export di Cascadeur CON la mesh (scala 1/260, vedi
cascadeur-lupo-rig-fisico): serve la mesh, perche' a bucare il suolo e' il
PELO, non le ossa. Va prima di rifinisci_clip_cascadeur.py, che la mesh la toglie.

Perche' qui e non in Cascadeur: nella carica del morso (2026-10-15, dopo la
fisica) il pelo della coda scendeva fino a 20,6 cm sotto il suolo (f20), da f6
a f24, e di 2,4 cm all'atterraggio. Nel rig quadrupede la coda e' una catena a
SWING: la `Position` dei suoi punti e' derivata, e scriverla da script non
cambia niente; lo swing scritto non la muove nemmeno (tre assi provati, zero
millimetri). Qui la correzione e' una rotazione IN PIU' sull'osso alla base
(`tailstart`), sopra quella che arriva da Cascadeur: si rifa' da sola a ogni
nuovo export.

Come: per ogni frame si cerca per bisezione l'angolo minimo che porta il
vertice piu' basso della coda (vertici pesati soprattutto su ossa `tail*`) a
QUOTA cm; poi l'angolo si liscia nel tempo (inviluppo su +-2 frame e media),
perche' una coda che scatta si vede piu' di una che sfiora terra.
"""
import bpy, sys, math
from mathutils import Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SORGENTE, DEST = argv[0], argv[1]
SCALA = 260.0           # cm di Cascadeur per metro del modello
QUOTA = 4.0             # cm: il pelo della coda non scende sotto (le suole stanno a ~2,5)
OSSO = "tailstart"
MAX_GRADI = 75.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30                      # ⚠️ prima dell'import
bpy.ops.import_scene.gltf(filepath=SORGENTE)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
me = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
az = list(bpy.data.actions)[0]
arm.animation_data.action = az
if az.slots:
    arm.animation_data.action_slot = az.slots[0]
## ⚠️ Le chiavi di Cascadeur cadono a 46,99996 invece di 47: senza agganciarle
## ai frame interi l'export campiona fino al 46 e l'ultimo fotogramma sparisce
## (successo al primo giro: clip da 1,533 s invece di 1,567). Stessa cura di
## rifinisci_clip_cascadeur.py.
agganciate = 0
for strato in az.layers:
    for striscia in strato.strips:
        for cb in striscia.channelbags:
            for fc in cb.fcurves:
                for k in fc.keyframe_points:
                    intero = round(k.co.x)
                    if abs(k.co.x - intero) > 1e-6:
                        d = intero - k.co.x
                        k.co.x = intero
                        k.handle_left.x += d
                        k.handle_right.x += d
                        agganciate += 1
                fc.update()
print("chiavi agganciate ai frame interi:", agganciate)
f0, f1 = (int(round(x)) for x in az.frame_range)
scn = bpy.context.scene
scn.frame_start, scn.frame_end = f0, f1
pb = arm.pose.bones[OSSO]
pb.rotation_mode = "QUATERNION"

gruppi = {g.index: g.name for g in me.vertex_groups}
coda = [v.index for v in me.data.vertices
        if v.groups and gruppi[max(v.groups, key=lambda g: g.weight).group].startswith("tail")]


def minimo_coda() -> float:
    dg = bpy.context.evaluated_depsgraph_get()
    ev = me.evaluated_get(dg)
    m = ev.to_mesh()
    mw = me.matrix_world
    z = min((mw @ m.vertices[i].co).z for i in coda)
    ev.to_mesh_clear()
    return z * SCALA


## L'asse che ALZA la coda: si prova a f0 (l'asse X locale dell'osso, nei due
## versi) invece di dedurlo dalle convenzioni del rig.
base = {}
for f in range(f0, f1 + 1):
    scn.frame_set(f)
    base[f] = pb.rotation_quaternion.copy()


def prova(f, gradi, asse):
    scn.frame_set(f)
    pb.rotation_quaternion = base[f] @ Quaternion(asse, math.radians(gradi))
    bpy.context.view_layer.update()
    return minimo_coda()


scn.frame_set(f0)
asse = Vector((1, 0, 0)) if prova(f0, 15, Vector((1, 0, 0))) > prova(f0, 15, Vector((-1, 0, 0))) else Vector((-1, 0, 0))
print("asse che alza la coda: %s" % (tuple(asse),))

grezzo = {}
for f in range(f0, f1 + 1):
    z0 = prova(f, 0.0, asse)
    if z0 >= QUOTA:
        grezzo[f] = 0.0
        continue
    lo, hi = 0.0, MAX_GRADI
    if prova(f, hi, asse) < QUOTA:
        print("  f%02d: nemmeno %d gradi bastano (%.1f cm)" % (f, MAX_GRADI, prova(f, hi, asse)))
        grezzo[f] = hi
        continue
    for _ in range(14):
        mid = (lo + hi) / 2
        if prova(f, mid, asse) >= QUOTA:
            hi = mid
        else:
            lo = mid
    grezzo[f] = hi
fr = list(range(f0, f1 + 1))
inv = {f: max(grezzo[g] for g in fr if abs(g - f) <= 2) for f in fr}
liscio = {f: sum(inv[g] for g in fr if abs(g - f) <= 2) / len([g for g in fr if abs(g - f) <= 2]) for f in fr}

prima_min, dopo_min = {}, {}
for f in fr:
    prima_min[f] = prova(f, 0.0, asse)
for f in fr:
    scn.frame_set(f)
    pb.rotation_quaternion = base[f] @ Quaternion(asse, math.radians(liscio[f]))
    pb.keyframe_insert("rotation_quaternion", frame=f)
for f in fr:
    scn.frame_set(f)
    dopo_min[f] = minimo_coda()
for f in fr:
    if liscio[f] > 0.05:
        print("  f%02d  +%5.1f gradi   pelo della coda %+6.1f -> %+6.1f cm" % (f, liscio[f], prima_min[f], dopo_min[f]))
print("PELO PIU' BASSO: prima %.1f cm (f%d), dopo %.1f cm (f%d)" % (
    min(prima_min.values()), min(prima_min, key=prima_min.get),
    min(dopo_min.values()), min(dopo_min, key=dopo_min.get)))

bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
me.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=DEST, export_format="GLB", use_selection=True, export_animations=True,
                          export_skins=True, export_apply=False, export_yup=True, export_image_format="NONE",
                          export_force_sampling=True, export_optimize_animation_size=False)
print("ESPORTATO", DEST)
