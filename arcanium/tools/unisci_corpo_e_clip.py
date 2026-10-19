# -*- coding: utf-8 -*-
"""Mette insieme un corpo (mesh + scheletro) e una clip in un GLB solo.

Serve per portare in Cascadeur qualcosa che si possa guardare: le clip del
progetto sono file di sola armatura, e uno scheletro nudo non dice se il corpo
tocca terra o se le braccia compenetrano il busto.

⚠️ Questo file e' materiale di LAVORAZIONE, non un asset: non va scritto sopra
il corpo base ne' sopra la clip. Da Cascadeur si riesporta la sola animazione.

Uso:

    blender.exe --background --python arcanium/tools/unisci_corpo_e_clip.py -- \
        corpo.glb clip.glb uscita.glb [--senza-texture]
"""
import sys

import bpy


def _importa(percorso):
    prima = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=percorso)
    return [o for o in bpy.context.scene.objects if o not in prima]


def unisci(corpo, clip, uscita, senza_texture=False, fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = int(fps)
    bpy.context.scene.render.fps_base = 1.0

    nuovi = _importa(corpo)
    arm = [o for o in nuovi if o.type == "ARMATURE"][0]
    mesh = [o for o in nuovi if o.type == "MESH"]

    nuovi_clip = _importa(clip)
    arm_clip = [o for o in nuovi_clip if o.type == "ARMATURE"][0]
    azione = arm_clip.animation_data.action
    arm.animation_data_create()
    arm.animation_data.action = azione
    # ⚠️ Da Blender 4.4 assegnare `action` senza `action_slot` non anima nulla,
    # e non protesta: il GLB esce con lo scheletro fermo in posa di riposo.
    slot = next(iter(azione.slots), None)
    if slot is None:
        raise SystemExit("l'azione '%s' non ha slot" % azione.name)
    arm.animation_data.action_slot = slot
    for o in nuovi_clip:
        bpy.data.objects.remove(o, do_unlink=True)

    # ⚠️ `export_animation_mode="ACTIONS"` esporta TUTTE le action del file, non
    # quella assegnata: il corpo si porta dietro le sue e la clip la propria, e
    # ne uscivano TRE animazioni per un GLB che ne doveva avere una. Non protesta
    # nessuno, e chi importa a valle sceglie la sua — Cascadeur la prima, e la
    # prima qui era l'idle che il corpo aveva gia' dentro, non la clip chiesta.
    # Si tolgono, invece di sperare nell'ordine.
    for altra in list(bpy.data.actions):
        if altra is not azione:
            bpy.data.actions.remove(altra)

    f0, f1 = (int(round(v)) for v in azione.frame_range)
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = f0, f1

    if senza_texture:
        for m in mesh:
            m.data.materials.clear()

    bpy.ops.export_scene.gltf(
        filepath=uscita,
        export_format="GLB",
        export_animations=True,
        export_force_sampling=True,
        export_animation_mode="ACTIONS",
        export_frame_range=True,
        export_yup=True,
    )
    print("[unisci] '%s' (%d-%d) su %d mesh -> %s" % (azione.name, f0, f1, len(mesh), uscita))

    # Un export puo' riuscire producendo un file vuoto, o con l'animazione
    # sbagliata: si guarda dentro il file scritto, non il fatto che l'export
    # non abbia protestato.
    _controlla(uscita)


def _controlla(percorso):
    import json
    import struct
    with open(percorso, "rb") as f:
        d = f.read()
    off, js = 12, None
    while off < len(d):
        ln, ty = struct.unpack_from("<II", d, off)
        off += 8
        if ty == 0x4E4F534A:
            js = json.loads(d[off:off + ln].decode("utf-8"))
        off += ln
    anim = js.get("animations", [])
    if len(anim) != 1:
        raise SystemExit("%s: %d animazioni, ne serve UNA" % (percorso, len(anim)))
    if not js.get("skins"):
        raise SystemExit("%s: nessuno skin" % percorso)
    dur = max(js["accessors"][s["input"]]["max"][0] for s in anim[0]["samplers"])
    print("[unisci] verificato: 1 animazione, %d canali, %.2fs, %d mesh"
          % (len(anim[0]["channels"]), dur, len(js.get("meshes", []))))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    opzioni = [a for a in argv if a.startswith("--")]
    argv = [a for a in argv if not a.startswith("--")]
    if len(argv) != 3:
        raise SystemExit(__doc__)
    unisci(argv[0], argv[1], argv[2], senza_texture="--senza-texture" in opzioni)
