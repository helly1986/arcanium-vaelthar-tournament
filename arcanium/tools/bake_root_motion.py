# -*- coding: utf-8 -*-
"""Trasferisce l'avanzamento ORIZZONTALE da `Hips` a `Root` in una clip.

    blender --background --factory-startup --python arcanium/tools/bake_root_motion.py -- <file.glb>

Lavora sul posto: riscrive il GLB che gli si passa.

═══════════════════════════════════════════════════════════════════════════
PERCHE' SERVE, E COSA SUCCEDE SENZA
═══════════════════════════════════════════════════════════════════════════

In Godot il nemico dichiara

    anim_player.root_motion_track = "<scheletro>:Root"

(vedi `_carica_famiglia` in arcanium_humanoid_enemy.gd): l'AnimationMixer
ESTRAE la traslazione di quell'osso e la toglie dalla posa, e il CharacterBody
la usa per spostarsi davvero. Le clip del pack sono fatte cosi' — orizzontale
bakeata sul `Root`, verticale nativa sull'`Hips`, che e' il motivo per cui il
passo ha il suo saliscendi e il corpo avanza lo stesso.

⚠️ Una clip autorata in Cascadeur esce all'opposto: **tutto lo spostamento e'
sull'`Hips`** e il `Root` sta fermo. Misurato sulla botta di scudo: `Hips` 2,342
di traslazione, `Root` 0,028.

Il guasto che ne segue non assomiglia alla causa: il mixer estrae dal `Root`
quasi zero, i 2,34 m restano nella POSA, e il Fante scivola in avanti con la
mesh mentre il suo corpo di collisione resta dov'e'. Poi la clip finisce e la
mesh torna indietro di scatto. Non c'e' nessun errore da nessuna parte.

═══════════════════════════════════════════════════════════════════════════
COME
═══════════════════════════════════════════════════════════════════════════

`Root` e' il padre di `Hips`, quindi basta spostare del pari il padre e togliere
altrettanto al figlio: la posa finale non cambia di un millimetro, cambia solo
CHI porta il movimento.

Si lavora nello spazio dell'ARMATURA (`pose_bone.matrix`), non nelle location
locali: la `location` di un osso in posa corre lungo l'asse dell'osso, non lungo
gli assi del mondo, e sommarci uno spostamento orizzontale manda il personaggio
in diagonale.

⚠️ In Blender l'alto del MONDO e' **Z** (il glTF ha Y), ma lo spazio
dell'armatura e' ruotato come l'oggetto: per gli umanoidi coincide col mondo,
per il lupo (WolfRig +90 gradi su X) l'alto e' Y. Si ricava dall'oggetto e
la componente lungo l'alto resta all'`Hips`. Sbagliare asse qui produce un
personaggio che sprofonda invece di avanzare, e i numeri sembrano giusti.

Il collaudo e' dentro: dopo il travaso si ricontrolla che la posizione dell'Hips
nello spazio dell'armatura sia rimasta IDENTICA su ogni frame. Se cambia, il
travaso ha spostato il personaggio invece di ridistribuire il movimento.
"""
import os
import sys

import bpy
from mathutils import Vector

FPS = 30
TOLLERANZA = 1e-4        # metri: sopra questo, la posa e' cambiata davvero

argomenti = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not argomenti:
    raise SystemExit("uso: ... -- <file.glb>")
GLB = argomenti[0]
OSSO_RADICE = argomenti[1] if len(argomenti) > 1 else "Root"
OSSO_ANCA = argomenti[2] if len(argomenti) > 2 else "Hips"

# ⚠️ L'fps PRIMA dell'import: il glTF tiene i tempi in secondi e l'importatore
# li converte con l'fps della scena, che di default e' 24.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS
bpy.context.scene.render.fps_base = 1.0
bpy.ops.import_scene.gltf(filepath=GLB)

rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
rig.data.pose_position = 'POSE'
azioni = list(bpy.data.actions)
assert len(azioni) == 1, "attesa una sola action, trovate %d" % len(azioni)
azione = azioni[0]
if rig.animation_data is None:
    rig.animation_data_create()
rig.animation_data.action = azione
if azione.slots:
    rig.animation_data.action_slot = azione.slots[0]

for nome in (OSSO_RADICE, OSSO_ANCA):
    assert nome in rig.pose.bones, "manca l'osso %r nel rig" % nome
assert rig.pose.bones[OSSO_ANCA].parent is not None and \
    rig.pose.bones[OSSO_ANCA].parent.name == OSSO_RADICE, \
    "%r non e' figlio di %r: il travaso vale solo su quella gerarchia" % (OSSO_ANCA, OSSO_RADICE)

f0, f1 = (int(round(v)) for v in azione.frame_range)
bpy.context.scene.frame_start, bpy.context.scene.frame_end = f0, f1
frames = list(range(f0, f1 + 1))

radice_riposo = rig.pose.bones[OSSO_RADICE].bone.matrix_local.translation.copy()

# ─── 1. si LEGGE dove sta l'anca, frame per frame, nello spazio dell'armatura
anca = {}
for f in frames:
    bpy.context.scene.frame_set(f)
    anca[f] = rig.pose.bones[OSSO_ANCA].matrix.translation.copy()

partenza = anca[f0]
## L'ALTO nello spazio dell'armatura si ricava dall'oggetto, non si suppone:
## sugli umanoidi e' Z, ma il lupo ha l'oggetto WolfRig ruotato di +90 gradi
## su X e il suo alto e' Y. Con Z fisso il travaso del morso del lupo
## (2026-10-15) avrebbe passato al Root la SALITA del balzo e lasciato
## all'Hips l'avanzamento: il contrario di quello che serve.
alto = (rig.matrix_world.inverted().to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
print("[root] alto nello spazio dell'armatura: (%.2f, %.2f, %.2f)" % tuple(alto))


def _piano(v):
    return v - alto * v.dot(alto)


orizzontale = {f: _piano(anca[f] - partenza) for f in frames}
percorso = max(v.length for v in orizzontale.values())
print("[root] avanzamento orizzontale dell'anca: %.3f m (massimo dal frame %d)"
      % (percorso, f0))
if percorso < 0.01:
    print("[root] la clip non si sposta: niente da travasare, esco senza toccare il file.")
    raise SystemExit(0)

# ─── 2. si SCRIVE: la radice porta l'orizzontale, l'anca torna dov'era
pb_radice = rig.pose.bones[OSSO_RADICE]
pb_anca = rig.pose.bones[OSSO_ANCA]
for f in frames:
    bpy.context.scene.frame_set(f)

    m = pb_radice.matrix.copy()
    m.translation = radice_riposo + orizzontale[f]
    pb_radice.matrix = m
    bpy.context.view_layer.update()      # ⚠️ il figlio va risolto DOPO il padre

    m = pb_anca.matrix.copy()
    m.translation = anca[f]              # esattamente dov'era: la posa non cambia
    pb_anca.matrix = m
    bpy.context.view_layer.update()

    pb_radice.keyframe_insert("location", frame=f)
    pb_anca.keyframe_insert("location", frame=f)

# ⚠️ Le chiavi vanno messe LINEARI a mano. `keyframe_insert` su una chiave che
# ESISTE gia' ne aggiorna il valore e ne tiene l'interpolazione: se il Root
# era arrivato da Cascadeur come sampler STEP (succede quando nella scena il
# Root non si muove mai: la combo dello spadone), le sue chiavi sono CONSTANT,
# l'esportatore riscrive STEP, e Godot importa il Root a SCALINI. Il sintomo
# non e' visibile a occhio: e' il misuratore dei contatti che, campionando a
# 240 Hz, vede un bacino che salta a 31 m/s e sbaglia colpo. Sono campioni
# per frame: fra un campione e l'altro l'interpolazione giusta e' la lineare.
def _curve_location(azione, osso):
    percorso = 'pose.bones["%s"].location' % osso
    out = []
    curve = getattr(azione, "fcurves", None)
    if curve is None:
        curve = []
        for strato in azione.layers:
            for striscia in strato.strips:
                for cb in striscia.channelbags:
                    curve.extend(cb.fcurves)
    for fc in curve:
        if fc.data_path == percorso:
            out.append(fc)
    return out

raddrizzate = 0
for osso in (OSSO_RADICE, OSSO_ANCA):
    for fc in _curve_location(rig.animation_data.action, osso):
        for k in fc.keyframe_points:
            if k.interpolation != 'LINEAR':
                k.interpolation = 'LINEAR'
                raddrizzate += 1
        fc.update()
print("[root] chiavi rimesse LINEARI: %d" % raddrizzate)

# ─── 3. COLLAUDO: la posa non deve essersi mossa di un millimetro
peggio, dove = 0.0, f0
for f in frames:
    bpy.context.scene.frame_set(f)
    d = (rig.pose.bones[OSSO_ANCA].matrix.translation - anca[f]).length
    if d > peggio:
        peggio, dove = d, f
print("[root] la posa dell'anca si e' spostata al massimo di %.6f m (frame %d)"
      % (peggio, dove))
assert peggio < TOLLERANZA, \
    "il travaso ha MOSSO il personaggio invece di ridistribuire: %.6f m al frame %d" % (peggio, dove)

radice_percorso = 0.0
for f in frames:
    bpy.context.scene.frame_set(f)
    radice_percorso = max(radice_percorso,
                          (rig.pose.bones[OSSO_RADICE].matrix.translation - radice_riposo).length)
print("[root] la radice ora porta %.3f m" % radice_percorso)
assert abs(radice_percorso - percorso) < 1e-3, \
    "la radice non ha preso tutto l'avanzamento (%.3f contro %.3f)" % (radice_percorso, percorso)

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
prima = os.path.getsize(GLB)
bpy.ops.export_scene.gltf(
    filepath=GLB, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_yup=True, export_apply=False)
print("[root] RISCRITTO %s  %d -> %d byte" % (GLB, prima, os.path.getsize(GLB)))
