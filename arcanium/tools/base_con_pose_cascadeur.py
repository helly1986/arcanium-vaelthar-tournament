# -*- coding: utf-8 -*-
"""La BASE DA RIGGARE per Cascadeur: il corpo buono con le pose chiave fatte in Cascadeur.

    blender --background --factory-startup --python arcanium/tools/base_con_pose_cascadeur.py --         <base.glb> <pose_esportate.glb> <uscita_arp.glb>

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
f0, f1 = (int(round(v)) for v in azione.frame_range)
bpy.context.scene.frame_start, bpy.context.scene.frame_end = f0, f1
print("OGGETTI", [(o.name, o.type) for o in bpy.data.objects], "frame", f0, f1)
for f in (0, 16, 32):
    bpy.context.scene.frame_set(f)
    print("POSA f%d piede.l %s c_traj %s" % (f, tuple(round(v, 3) for v in (rig.matrix_world @ rig.pose.bones["foot.l"].head)),
          tuple(round(v, 3) for v in (rig.matrix_world @ rig.pose.bones["c_traj"].head))))
bpy.ops.export_scene.gltf(filepath=uscita, export_format='GLB', export_animations=True,
                          export_animation_mode='ACTIONS', export_yup=True, export_apply=False)
print("SCRITTO", uscita)
