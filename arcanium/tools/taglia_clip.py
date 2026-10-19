# -*- coding: utf-8 -*-
"""Ritaglia un tratto di animazione da un GLB, in un GLB a se'.

Serve quando un momento della clip va lavorato da solo. Il caso che l'ha fatto
nascere: **"Snap to AutoPhysics" di Cascadeur non si lascia limitare a un
tratto** — non lo limita `AutoPhysics.frame_weight`, non lo limita la selezione
della timeline (provate e misurate tutte e due), riparte sempre dal primo frame.
L'unico modo di applicare la fisica solo al crollo e' consegnare a Cascadeur una
clip in cui c'e' **soltanto** il crollo.

Il taglio ricampiona ogni frame del tratto, quindi non dipende da dove cadevano
le chiavi: quello che esce e' esattamente quello che si vedeva.

Uso:

    blender.exe --background --python arcanium/tools/taglia_clip.py -- \
        ingresso.glb uscita.glb PRIMO ULTIMO [--tieni-numeri] [--nome NomeClip]

Di default il tratto viene riportato a partire da 0 (comodo per lavorarlo);
`--tieni-numeri` conserva la numerazione originale (comodo per ricucire).
"""
import sys

import bpy


def _importa(percorso):
    prima = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=percorso)
    return [o for o in bpy.context.scene.objects if o not in prima]


def taglia(ingresso, uscita, primo, ultimo, a_zero=True, nome=None, fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    # ⚠️ prima dell'import: il glTF tiene i tempi in secondi e il caricatore li
    # converte con l'fps della scena, che di default e' 24.
    sc.render.fps = int(fps)
    sc.render.fps_base = 1.0

    nuovi = _importa(ingresso)
    arm = [o for o in nuovi if o.type == "ARMATURE"][0]
    az = arm.animation_data.action
    f0, f1 = (int(round(v)) for v in az.frame_range)
    if primo < f0 or ultimo > f1:
        raise SystemExit("tratto %d..%d fuori dalla clip (%d..%d)" % (primo, ultimo, f0, f1))
    print("[taglia] clip '%s' %d..%d -> tratto %d..%d" % (az.name, f0, f1, primo, ultimo))

    ossa = [pb.name for pb in arm.pose.bones]
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    # 1. campiona il tratto
    campioni = []
    for f in range(primo, ultimo + 1):
        sc.frame_set(f)
        campioni.append({n: arm.pose.bones[n].matrix_basis.copy() for n in ossa})

    # 2. riscrivilo in un'azione nuova
    vecchia = az
    arm.animation_data.action = None
    nuova = bpy.data.actions.new("__taglio__")
    arm.animation_data.action = nuova
    sposta = primo if a_zero else 0
    for i, posa in enumerate(campioni):
        f = primo + i - sposta
        for n, m in posa.items():
            pb = arm.pose.bones[n]
            pb.matrix_basis = m
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("scale", frame=f)

    # ⚠️ l'azione vecchia va tolta di mezzo o l'esportatore scrive DUE animazioni
    # e chi legge `get_animation_list()[0]` puo' pescare quella sbagliata.
    bpy.data.actions.remove(vecchia)
    nuova.name = nome or ("%s_%d_%d" % (az.name if az else "Clip", primo, ultimo))

    sc.frame_start = primo - sposta
    sc.frame_end = ultimo - sposta
    bpy.ops.export_scene.gltf(
        filepath=uscita, export_format="GLB", export_animations=True,
        export_force_sampling=True, export_animation_mode="ACTIONS",
        export_frame_range=True, export_yup=True)
    print("[taglia] '%s': %d frame -> %s" % (nuova.name, len(campioni), uscita))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    nome = None
    if "--nome" in argv:
        i = argv.index("--nome")
        nome = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    a_zero = "--tieni-numeri" not in argv
    pos = [a for a in argv if not a.startswith("--")]
    if len(pos) != 4:
        raise SystemExit(__doc__)
    taglia(pos[0], pos[1], int(pos[2]), int(pos[3]), a_zero=a_zero, nome=nome)
