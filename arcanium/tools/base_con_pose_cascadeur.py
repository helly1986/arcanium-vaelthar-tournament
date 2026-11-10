# -*- coding: utf-8 -*-
"""La BASE DA RIGGARE per Cascadeur: il corpo buono con le pose chiave fatte in Cascadeur.

    blender --background --factory-startup --python arcanium/tools/base_con_pose_cascadeur.py --         <base.glb> <pose_esportate.glb> <uscita_arp.glb> [riposo_in_testa]

Le pose chiave si scrivono in FK su una scena SENZA rig (`casc_pose_fk.py`), poi la scena si
esporta e si rigga (`casc_rigga_personaggio.py`, che vuole un GLB `*_arp*.glb`). Ma l'export GLB
di Cascadeur ROVINA il corpo: lo sostituisce con una mesh di 1.814 vertici tutta pesata sulla
testa (in Cascadeur il corpo collassa sulla testa), e lo scudo perde la sua scala (esce largo
1,9 m invece di 0,66). Scoperto sulla corsa di Edran, 2026-11-09; era cosi' anche nel cammino.

Qui si prende la base buona (`base_cascadeur.py`, il corpo vero da 48.000 vertici) e le si da'
l'animazione delle pose esportate: stesse ossa, stessi nomi. Il corpo rotto e le armi
dell'export restano fuori; le armi si rimettono dopo il rig con `casc_arma_su_osso.py`.
"""
import bpy, sys
base, pose, uscita = sys.argv[sys.argv.index("--") + 1:][:3]
RIPOSO_IN_TESTA = "riposo_in_testa" in sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=pose)
rig_pose = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
azione = rig_pose.animation_data.action
azione.use_fake_user = True
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
prima = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=base)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for a in set(bpy.data.actions) - prima:
    bpy.data.actions.remove(a)
rig.animation_data_create()
rig.animation_data.action = azione
if azione.slots:
    rig.animation_data.action_slot = azione.slots[0]
mancano = [b.name for b in rig.data.bones if b.name not in {g.name for g in rig_pose.pose.bones}] if False else []
if RIPOSO_IN_TESTA:
    # `riposo_in_testa`: la posa di riposo (l'ultimo frame della base) va al frame 0 e le pose
    # slittano di uno. Il QRT di Cascadeur costruisce il rig sulla posa del frame 0, e con la
    # sinistra di Zarine che attraversa il petto fino alla spalla destra (l'asta in spalla) si
    # fermava su un popup, "Hinge forearm_l might be bent backwards", e non creava niente
    # (2026-11-10). Dopo il rig `casc_estremi_clip.py` riporta le chiavi indietro di uno.
    for strato in azione.layers:
        for striscia in strato.strips:
            for cb in striscia.channelbags:
                for fc in cb.fcurves:
                    punti = fc.keyframe_points
                    if not len(punti):
                        continue
                    ultimo = max(punti, key=lambda k: k.co.x).co.y
                    for k in punti:
                        k.co.x += 1
                        k.handle_left.x += 1
                        k.handle_right.x += 1
                    punti.insert(0, ultimo, options={'FAST'}).interpolation = 'LINEAR'
                    fc.update()
    print("RIPOSO IN TESTA: frame 0 a riposo, le pose da 1")
f0, f1 = (int(round(v)) for v in azione.frame_range)
bpy.context.scene.frame_start, bpy.context.scene.frame_end = f0, f1
print("OGGETTI", [(o.name, o.type) for o in bpy.data.objects], "frame", f0, f1)
for f in ((1, 17, 33) if RIPOSO_IN_TESTA else (0, 16, 32)):
    bpy.context.scene.frame_set(f)
    print("POSA f%d piede.l %s c_traj %s" % (f, tuple(round(v, 3) for v in (rig.matrix_world @ rig.pose.bones["foot.l"].head)),
          tuple(round(v, 3) for v in (rig.matrix_world @ rig.pose.bones["c_traj"].head))))
bpy.ops.export_scene.gltf(filepath=uscita, export_format='GLB', export_animations=True,
                          export_animation_mode='ACTIONS', export_yup=True, export_apply=False)
print("SCRITTO", uscita)
