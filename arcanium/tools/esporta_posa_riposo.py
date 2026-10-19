# -*- coding: utf-8 -*-
"""Esporta una clip VUOTA del protagonista, per andarci ad animare sopra.

Serve a dare a Cascadeur (o a qualunque altro software di animazione) un file
di partenza pulito: l'armatura e la mesh del corpo v4, con UNA sola animazione
che tiene la posa di RIPOSO per tutta la sua durata. Niente da disfare prima di
cominciare: quello che si vede al frame 0 e' esattamente il rig a riposo.

Si lancia in background, senza toccare la sessione Blender aperta:

    blender --background --factory-startup --python arcanium/tools/esporta_posa_riposo.py

⚠️ Il sorgente e' `protagonista_v4.glb`, cioe' il corpo che il gioco importa
gia' (61 ossa, radice `Root` a terra, nomi del profilo Humanoid). Partire da
li' e non dal .blend di lavoro garantisce che le ossa siano ESATTAMENTE quelle
che Godot si aspetta: una clip animata su un rig diverso non torna indietro.

⚠️ Le due chiavi (prima e ultima) sono entrambe a riposo, ed esistono solo per
dare al file una DURATA. Senza una seconda chiave l'animazione dura zero e
l'importatore costruisce una timeline di un frame sola, su cui non si anima.
La chiave finale si cancella dall'animatore se non serve un ritorno a riposo.
"""
import bpy, os, math

RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")).replace("\\", "/")
SRC = RADICE + "/assets/characters/base_body/protagonista_v4.glb"
DEST_DIR = RADICE + "/assets/characters/anims/_sorgenti"
DEST = DEST_DIR + "/protagonista_posa_riposo.glb"

NOME_CLIP = "posa_riposo"
FPS = 30
ULTIMO_FRAME = 60          # 2 secondi: spazio per lavorare, non una scelta artistica

# Oggetti che il GLB sorgente si porta dietro e che non c'entrano nulla col corpo.
INTRUSI = {"Icosphere"}

# ─────────────────────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

for nome in INTRUSI:
    o = bpy.data.objects.get(nome)
    if o is not None:
        print("  scarto oggetto intruso:", nome)
        bpy.data.objects.remove(o, do_unlink=True)

rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
print("rig:", rig.name, "| ossa:", len(rig.data.bones), "| mesh:", mesh.name)
assert "Root" in rig.data.bones, "manca l'osso Root: non e' il rig v4"

# ⚠️ Il campionamento dell'esportatore legge la posa VALUTATA. In 'REST' quella
# posa e' il riposo a OGNI frame, e la clip esce statica anche con le curve
# giuste: e' esattamente l'errore che ha svuotato le nove clip del lupo.
rig.data.pose_position = 'POSE'

bpy.context.scene.render.fps = FPS
bpy.context.scene.frame_start = 0
bpy.context.scene.frame_end = ULTIMO_FRAME

# ─── La posa di riposo, esplicita ────────────────────────────────────────────
bpy.context.view_layer.objects.active = rig
rig.animation_data_clear()
azione = bpy.data.actions.new(NOME_CLIP)
rig.animation_data_create()
rig.animation_data.action = azione
# Blender 4.4+: una action va assegnata a uno slot, o le fcurve non pilotano nulla.
if hasattr(rig.animation_data, "action_slot") and azione.slots:
    rig.animation_data.action_slot = azione.slots[0]

for pb in rig.pose.bones:
    pb.rotation_mode = 'QUATERNION'
    pb.location = (0.0, 0.0, 0.0)
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)

for frame in (0, ULTIMO_FRAME):
    bpy.context.scene.frame_set(frame)
    for pb in rig.pose.bones:
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("scale", frame=frame)

bpy.context.view_layer.update()


def fcurve_di(azione):
    """Le fcurve di una action, in Blender 5.x.

    ⚠️ `Action.fcurves` NON esiste piu': dalle action a slot (4.4+) le curve
    stanno in `layers[].strips[].channelbag(slot).fcurves`, e in 5.2 la vecchia
    scorciatoia e' stata tolta del tutto.
    """
    curve = []
    for strato in azione.layers:
        for striscia in strato.strips:
            for cb in striscia.channelbags:
                curve.extend(cb.fcurves)
    return curve


print("action:", azione.name, "| slot:", [s.identifier for s in azione.slots],
      "| fcurve:", len(fcurve_di(azione)),
      "| frame_range:", tuple(azione.frame_range))
assert len(fcurve_di(azione)) > 0, "action senza curve: le chiavi non sono entrate"

# ─── Export ──────────────────────────────────────────────────────────────────
for o in (rig, mesh):
    o.hide_set(False)
    o.hide_viewport = False
    o.hide_render = False
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = rig

os.makedirs(DEST_DIR, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=DEST, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_yup=True, export_apply=False)
print("ESPORTATO:", DEST, os.path.getsize(DEST), "byte")
