# -*- coding: utf-8 -*-
"""Aggiunge l'osso `Root` a terra al file base del lupo, per il root motion.

⚠️ Tocca `wolf_animated.glb`, che è il FILE BASE: è lo stesso genere di
eccezione dichiarata in `esporta_lupo.py` («l'unica eccezione legittima alla
regola: non ri-esportare mai il file base»), e per la stessa ragione — lo
scheletro vive col file, quindi un osso nuovo non può arrivare come clip
separata.

Perché serve: Godot legge il root motion da un osso chiamato `Root`
(`root_motion_track = "%GeneralSkeleton:Root"`, come in player_dawnkeep.tscn e
in arcanium_humanoid_enemy.gd). Il lupo non ce l'ha: la sua radice è `Hips`.
Finché quell'osso manca, le tracce di root motion nelle clip di
`anims/wolf/` puntano a un osso inesistente e vengono IGNORATE — misurato.

Il `Root` nasce a terra (origine), non deforma nulla e diventa genitore di
`Hips`: è puramente un portatore di movimento. Le 9 animazioni esistenti non lo
animano, quindi restano identiche.

Uso:
  blender --background --python arcanium/tools/aggiungi_root_lupo.py
Fai il backup PRIMA (il file base non si rigenera da solo).
"""
import bpy, os, sys

RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")).replace("\\", "/")
GLB = RADICE + "/assets/characters/enemies/wolf_animated.glb"

ATTESE = ["bite", "bite_combo", "death", "hit", "howl", "idle", "leap", "run", "walk"]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = [o for o in bpy.data.objects if o.type == 'MESH']
prima_ossa = len(rig.data.bones)
prima_azioni = sorted(a.name for a in bpy.data.actions)
print("PRIMA: %d ossa, azioni %s" % (prima_ossa, prima_azioni))
assert prima_azioni == sorted(ATTESE), "il file base non ha le 9 azioni attese: %s" % prima_azioni
assert "jaw" in rig.data.bones, "manca `jaw`: file base vecchio?"

if "Root" in rig.data.bones:
    print("Root già presente: niente da fare")
    sys.exit(0)

bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
eb = rig.data.edit_bones
root = eb.new("Root")
root.head = (0.0, 0.0, 0.0)
## punta lungo +Y locale (l'ALTO in questo rig): così la matrice locale è
## l'identità e `location` si legge senza conversioni
root.tail = (0.0, 0.10, 0.0)
root.roll = 0.0
root.use_deform = False
h = eb["Hips"]
h.parent = root
h.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')

## ⚠️ Nessun peso sul Root, ma serve che l'esportatore lo includa comunque:
## `export_def_bones=False` (il default) esporta TUTTE le ossa dell'armatura.
bpy.ops.object.select_all(action='DESELECT')
for m in mesh:
    m.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=GLB, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=False, export_skins=True,
    export_materials='EXPORT', export_yup=True)
print("DOPO: %d ossa (era %d) — scritto %s" % (len(rig.data.bones), prima_ossa, GLB))
