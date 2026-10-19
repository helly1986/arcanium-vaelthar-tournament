# -*- coding: utf-8 -*-
"""Porta a terra una clip in cui il corpo si stacca dal suolo.

Il difetto che cura: una caduta autorata ruotando il corpo attorno al bacino,
senza mai far scendere il bacino. Il personaggio si irrigidisce, diventa
orizzontale e resta sospeso — misurato sulla morte per veleno del protagonista,
il punto più basso di TUTTO il corpo finiva a 69 cm dal pavimento.

Il conto è semplice e non inventa niente: per ogni frame si guarda il punto più
basso del corpo, e si abbassa l'intero personaggio di quanto serve perche' quel
punto torni a sfiorare terra. Dove il corpo già tocca (la parte in piedi) lo
scarto e' zero e la clip non viene toccata; dove si stacca, la discesa segue da
sola l'inclinazione, perche' e' ricavata dalla posa e non da una rampa scritta a
mano.

⚠️ Non e' una simulazione: non fa piegare le ginocchia e non aggiunge
l'assestamento. Toglie il fluttuamento, che e' il difetto piu' grosso e il piu'
visibile. Il resto e' lavoro d'animatore.

Uso:

    blender.exe --background --python arcanium/tools/porta_a_terra.py -- \
        corpo.glb clip.glb uscita.glb [--soglia 0.03] [--lisciatura 5]
"""
import sys

import bpy
from mathutils import Vector

# ossa da ignorare quando si cerca il punto piu' basso: pseudo-ossa che stanno
# gia' a terra per convenzione e falserebbero la misura
IGNORA = {"Root"}


def _importa(percorso):
    prima = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=percorso)
    return [o for o in bpy.context.scene.objects if o not in prima]


def _minimo(arm, ossa):
    return min((arm.matrix_world @ arm.pose.bones[n].head).z for n in ossa)


def porta_a_terra(corpo, clip, uscita, soglia=0.03, lisciatura=5, fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = int(fps)
    sc.render.fps_base = 1.0

    nuovi = _importa(corpo)
    arm = [o for o in nuovi if o.type == "ARMATURE"][0]

    nuovi_clip = _importa(clip)
    arm_clip = [o for o in nuovi_clip if o.type == "ARMATURE"][0]
    azione = arm_clip.animation_data.action
    arm.animation_data_create()
    arm.animation_data.action = azione
    # ⚠️ Da Blender 4.4 senza action_slot non anima nulla, in silenzio.
    slot = next(iter(azione.slots), None)
    if slot is None:
        raise SystemExit("l'azione '%s' non ha slot" % azione.name)
    arm.animation_data.action_slot = slot
    for o in nuovi_clip:
        bpy.data.objects.remove(o, do_unlink=True)

    f0, f1 = (int(round(v)) for v in azione.frame_range)
    ossa = [b.name for b in arm.data.bones if b.name not in IGNORA]
    if "Hips" not in arm.pose.bones:
        raise SystemExit("nessun osso 'Hips': rig non canonico")

    # --- 1. misura: quanto sta staccato, frame per frame -------------------
    scarti = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        scarti.append(max(0.0, _minimo(arm, ossa) - soglia))
    print("[terra] staccato al massimo di %.1f cm (frame %d)"
          % (max(scarti) * 100, f0 + scarti.index(max(scarti))))

    # --- 2. lisciatura: una discesa a scatti si vede ------------------------
    if lisciatura > 1:
        r = lisciatura // 2
        lisci = []
        for i in range(len(scarti)):
            fetta = scarti[max(0, i - r):i + r + 1]
            lisci.append(sum(fetta) / len(fetta))
        scarti = lisci

    # --- 3. applica: abbassa tutto il personaggio ---------------------------
    # Si scrive sull'`Hips`, che porta l'intero corpo. Root resta dov'e': e' lo
    # pseudo-osso del root motion e il gioco ci legge lo spostamento.
    hips = arm.pose.bones["Hips"]
    for i, f in enumerate(range(f0, f1 + 1)):
        sc.frame_set(f)
        m = hips.matrix.copy()          # spazio armatura
        m.translation = m.translation - Vector((0.0, 0.0, scarti[i]))
        hips.matrix = m
        hips.keyframe_insert("location", frame=f)
        hips.keyframe_insert("rotation_quaternion", frame=f)

    # --- 4. verifica: rimisura dopo aver scritto ---------------------------
    peggio = 0.0
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        peggio = max(peggio, _minimo(arm, ossa) - soglia)
    print("[terra] dopo la correzione, distacco massimo residuo: %.2f cm"
          % (peggio * 100))
    if peggio > 0.02:
        print("[terra] ⚠️ residuo sopra i 2 cm: la lisciatura sta mangiando la discesa")

    for o in list(bpy.context.scene.objects):
        if o is not arm:
            bpy.data.objects.remove(o, do_unlink=True)

    bpy.ops.export_scene.gltf(
        filepath=uscita, export_format="GLB", export_animations=True,
        export_force_sampling=True, export_animation_mode="ACTIONS",
        export_frame_range=True, export_yup=True)
    print("[terra] scritto", uscita)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    opz = {argv[i]: argv[i + 1] for i in range(len(argv)) if argv[i].startswith("--")}
    pos = [a for a in argv if not a.startswith("--") and a not in opz.values()]
    if len(pos) != 3:
        raise SystemExit(__doc__)
    porta_a_terra(pos[0], pos[1], pos[2],
                  soglia=float(opz.get("--soglia", 0.03)),
                  lisciatura=int(opz.get("--lisciatura", 5)))
