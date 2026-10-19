# -*- coding: utf-8 -*-
"""Renderizza una clip su un corpo, a passo fisso, per farne un provino.

Una clip non si giudica dai numeri e non si giudica su un frame: si guarda tutta
insieme, con il numero di frame scritto sopra. Questo script produce i PNG; a
montarli ci pensa `arcanium/tools/monta_provino.py`.

Renderizza la MESH deformata, non lo scheletro: settantanove ossa ottaedriche
sono illeggibili, e comunque si giudica la pelle.

Uso:

    blender.exe --background --python arcanium/tools/provino_clip.py -- \
        corpo.glb clip.glb cartella_uscita [passo] [vista]

`vista` = `profilo` (default), `fronte` o `trequarti`. Per una caduta serve il
profilo: di fronte l'avanzamento non si vede.
"""
import math
import os
import sys

import bpy
from mathutils import Vector


def _importa(percorso):
    prima = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=percorso)
    return [o for o in bpy.context.scene.objects if o not in prima]


def provino(corpo, clip, cartella, passo=8, vista="profilo", fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = fps
    sc.render.fps_base = 1.0

    nuovi = _importa(corpo)
    arm = [o for o in nuovi if o.type == "ARMATURE"][0]
    mesh = [o for o in nuovi if o.type == "MESH"]

    # la clip: si prende l'azione e la si appiccica all'armatura del corpo
    nuovi_clip = _importa(clip)
    arm_clip = [o for o in nuovi_clip if o.type == "ARMATURE"][0]
    azione = arm_clip.animation_data.action
    arm.animation_data_create()
    arm.animation_data.action = azione
    # ⚠️⚠️ Da Blender 4.4 le azioni hanno gli SLOT, e assegnare `action` senza
    # assegnare `action_slot` non anima NIENTE. In silenzio: nessun errore, la
    # posa resta quella di riposo. Costato un provino intero in cui il
    # personaggio stava impalato per 190 frame mentre i numeri dicevano che
    # cadeva.
    slot = next((s for s in azione.slots), None)
    if slot is None:
        raise SystemExit("l'azione '%s' non ha slot" % azione.name)
    arm.animation_data.action_slot = slot
    for o in nuovi_clip:
        bpy.data.objects.remove(o, do_unlink=True)

    f0, f1 = (int(round(v)) for v in azione.frame_range)
    print("[provino] clip '%s': %d -> %d, passo %d" % (azione.name, f0, f1, passo))

    # --- inquadratura -------------------------------------------------------
    # ⚠️ Il riquadro si calcola sull'INTERA clip, non sul primo frame: un corpo
    # che cade esce dall'inquadratura tarata sulla posa iniziale.
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for f in range(f0, f1 + 1, max(1, passo // 2)):
        sc.frame_set(f)
        for pb in arm.pose.bones:
            p = arm.matrix_world @ pb.head
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    lo.z = min(lo.z, 0.0)          # il suolo deve stare sempre nell'inquadratura
    centro = (lo + hi) / 2.0
    dim = max((hi - lo).x, (hi - lo).y, (hi - lo).z) * 1.35 + 0.2

    cam_dati = bpy.data.cameras.new("Provino")
    cam_dati.type = "ORTHO"
    cam_dati.ortho_scale = dim
    cam = bpy.data.objects.new("Provino", cam_dati)
    sc.collection.objects.link(cam)
    sc.camera = cam

    # ⚠️ Una vista di profilo PERFETTA rende il pavimento di taglio, cioe'
    # invisibile: senza un filo di inclinazione verso il basso non si vede a che
    # quota sta il corpo, che e' proprio quello che si vuole giudicare. 0.18 in
    # z basta a far leggere il piano senza rovinare il profilo.
    direzioni = {
        "profilo":   Vector((1.0, 0.0, 0.18)),
        "fronte":    Vector((0.0, -1.0, 0.18)),
        "trequarti": Vector((0.9, -0.7, 0.28)),
    }
    if vista not in direzioni:
        raise SystemExit("vista sconosciuta: %s" % vista)
    d = direzioni[vista].normalized()
    cam.location = centro + d * (dim * 3.0)
    # puntare si calcola, non si scrive a mano: un eulero sbagliato da' render
    # vuoti, e un render vuoto sembra un bug del render.
    cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler()

    # --- resa ---------------------------------------------------------------
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "SINGLE"
    sc.display.shading.single_color = (0.72, 0.70, 0.68)
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("Sfondo")
    sc.world.color = (0.09, 0.10, 0.12)
    sc.render.resolution_x = 520
    sc.render.resolution_y = 900
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"

    for o in mesh:
        o.display_type = "TEXTURED"

    # ⚠️ Il PAVIMENTO non e' decorazione: senza un riferimento a quota zero non
    # si distingue un corpo che crolla a terra da uno che resta orizzontale a un
    # metro d'altezza, e sono difetti opposti. Un piano a z=0, largo quanto
    # serve, lo rende evidente in un colpo d'occhio.
    bpy.ops.mesh.primitive_plane_add(size=dim * 3.0, location=(centro.x, centro.y, 0.0))
    suolo = bpy.context.active_object
    suolo.name = "Suolo"
    mat = bpy.data.materials.new("Suolo")
    mat.diffuse_color = (0.32, 0.30, 0.29, 1.0)
    suolo.data.materials.append(mat)
    sc.display.shading.color_type = "MATERIAL"
    for o in mesh:
        if not o.data.materials:
            m = bpy.data.materials.new("Pelle")
            m.diffuse_color = (0.78, 0.76, 0.73, 1.0)
            o.data.materials.append(m)
        else:
            for m in o.data.materials:
                if m:
                    m.diffuse_color = (0.78, 0.76, 0.73, 1.0)

    os.makedirs(cartella, exist_ok=True)
    scritti = []
    for f in range(f0, f1 + 1, passo):
        sc.frame_set(f)
        percorso = os.path.join(cartella, "f%04d.png" % f)
        sc.render.filepath = percorso
        bpy.ops.render.render(write_still=True)
        scritti.append((percorso, f))
    # sempre l'ultimo frame, anche se il passo non ci arriva
    if scritti and scritti[-1][1] != f1:
        sc.frame_set(f1)
        percorso = os.path.join(cartella, "f%04d.png" % f1)
        sc.render.filepath = percorso
        bpy.ops.render.render(write_still=True)
        scritti.append((percorso, f1))

    print("[provino] resi %d fotogrammi in %s" % (len(scritti), cartella))
    for p, f in scritti:
        print("[provino-file] %s|frame %d" % (p, f))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) < 3:
        raise SystemExit(__doc__)
    passo = int(argv[3]) if len(argv) > 3 else 8
    vista = argv[4] if len(argv) > 4 else "profilo"
    provino(argv[0], argv[1], argv[2], passo, vista)
