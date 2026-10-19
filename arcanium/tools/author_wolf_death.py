import bpy, math, os
from mathutils import Vector, Quaternion, Euler

OUT = "C:/Users/ADRIAN~1.PAC/AppData/Local/Temp/claude/C--Users-adriano-pace-Downloads-LOCAL/b352305a-4ec5-4168-975c-644953562362/scratchpad/"
GLB = "C:/Users/adriano.pace/Downloads/LOCAL/arcanium/assets/characters/enemies/wolf_animated.glb"

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)

bpy.ops.import_scene.gltf(filepath=GLB)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')

bpy.context.view_layer.objects.active = rig
rig.animation_data_clear()
# Le azioni importate dal GLB vanno via PRIMA di creare la nostra, o la nuova
# diventa "death.001" e all'export uscirebbero due clip con la vecchia buona.
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
act = bpy.data.actions.new("death")
rig.animation_data_create()
rig.animation_data.action = act
# Blender 5.x: slotted actions — assegna lo slot, o le fcurve non si vedono
try:
    slot = act.slots.new(id_type='OBJECT', name="WolfRig")
    rig.animation_data.action_slot = slot
except Exception as e:
    print("slot:", e)

bpy.ops.object.mode_set(mode='POSE')
for pb in rig.pose.bones:
    pb.rotation_mode = 'XYZ'
    pb.location = (0, 0, 0)
    pb.rotation_euler = (0, 0, 0)

FPS = 24
# (frame, {osso: (rx,ry,rz) in gradi}, {osso: (lx,ly,lz)})
# Y = alto, Z = avanti nello spazio di questo rig.
# La caduta: sussulto -> le zampe anteriori cedono -> il corpo ruota sul fianco
# sinistro -> testa e coda si abbandonano.
## Il bacino si comanda in spazio ARMATURA (dove Y = alto, Z = avanti, X =
## laterale), non con gli euler locali dell'osso: la `location` di un pose bone
## corre lungo l'asse dell'OSSO, quindi "scendi di 18 cm" mandava il lupo a
## volare in diagonale fuori campo. Qui si costruisce la matrice voluta e si
## ricava il basis a mano (`rest.inverted() @ target`), che è anche l'unico modo
## robusto: assegnare `pose_bone.matrix` diretto degenera quando rest e target
## divergono.
from mathutils import Matrix

HIPS_BONE = rig.data.bones["Hips"]
PIVOT = HIPS_BONE.head_local.copy()

def hips_basis(roll_deg, pitch_deg, drop):
    ## roll = rotazione attorno all'asse AVANTI (Z): è il ribaltarsi sul fianco.
    ## pitch = attorno al laterale (X): il muso che va giù.
    ## drop = discesa reale lungo -Y.
    R = (Matrix.Rotation(math.radians(roll_deg), 4, 'Z')
         @ Matrix.Rotation(math.radians(pitch_deg), 4, 'X'))
    attorno = Matrix.Translation(PIVOT) @ R @ Matrix.Translation(-PIVOT)
    target = Matrix.Translation(Vector((0, drop, 0))) @ attorno @ HIPS_BONE.matrix_local
    return HIPS_BONE.matrix_local.inverted() @ target

# f, (roll, pitch, drop del bacino), chest, head, zampe ant, zampe post, coda
KEYS = [
    ## La discesa è tarata sulla QUOTA MINIMA misurata sotto: col ribaltamento
    ## sul fianco è il corpo, non le zampe, a diventare il punto più basso, e
    ## -0.170 lo mandava a -0.091 contro i -0.026 del rest — col modello scalato
    ## 2.6 in gioco erano ~23 cm di lupo dentro il terreno.
    (0,  (0, 0, 0.0),        (0, 0, 0),    (0, 0, 0),    0,   0,   0),
    (5,  (0, -7, 0.010),     (-6, 0, 0),   (-20, 0, 0),  -6,  -4,  -12),
    (12, (-16, 6, -0.022),   (6, 0, 0),    (10, 0, 0),   26,  10,  8),
    (20, (-48, 10, -0.059),  (10, 0, 0),   (20, 0, 0),   48,  26,  16),
    (30, (-78, 8, -0.093),   (6, 0, 0),    (26, 0, 0),   58,  46,  22),
    (38, (-86, 5, -0.104),   (3, 0, 0),    (20, 0, 0),   56,  50,  26),
    (44, (-86, 5, -0.105),   (2, 0, 0),    (15, 0, 0),   55,  49,  28),
]

FRONT = ["frontleg", "R_frontleg"]
FRONT2 = ["frontleg0", "R_frontleg0"]
BACK = ["backleg", "R_backleg"]
BACK2 = ["backleg0", "R_backleg0"]
TAIL = ["tailstart", "tail1", "tail2", "tail3"]

def setrot(name, deg):
    pb = rig.pose.bones.get(name)
    if pb is None:
        return
    pb.rotation_euler = Euler([math.radians(d) for d in deg], 'XYZ')
    pb.keyframe_insert("rotation_euler", frame=f)

for (f, hips_p, chest_r, head_r, front, back, tail) in KEYS:
    hp = rig.pose.bones["Hips"]
    hp.matrix_basis = hips_basis(hips_p[0], hips_p[1], hips_p[2])
    hp.keyframe_insert("rotation_euler", frame=f)
    hp.keyframe_insert("location", frame=f)

    setrot("chest", chest_r)
    setrot("head", head_r)
    # le zampe si piegano attorno alla X locale (asse di flessione dell'arto)
    for n in FRONT:
        setrot(n, (front, 0, 0))
    for n in FRONT2:
        setrot(n, (-front * 0.8, 0, 0))
    for n in BACK:
        setrot(n, (-back, 0, 0))
    for n in BACK2:
        setrot(n, (back * 0.9, 0, 0))
    for i, n in enumerate(TAIL):
        setrot(n, (tail * (0.6 + 0.2 * i), 0, tail * 0.3))

bpy.ops.object.mode_set(mode='OBJECT')
act.use_fake_user = True
print("AZIONE:", act.name, "range", tuple(act.frame_range))

# ─── render di controllo ────────────────────────────────────────────────────
scn = bpy.context.scene
scn.render.engine = 'BLENDER_WORKBENCH'
scn.render.resolution_x = 640
scn.render.resolution_y = 420
scn.render.film_transparent = False

## Inquadratura calcolata sull'ingombro REALE in spazio MONDO: il rig ha Y in
## alto nei propri dati, ma l'oggetto armatura porta la rotazione della
## conversione glTF, quindi indovinare le coordinate a mano dà campo vuoto.
## Dalle OSSA, non dalla mesh: i vertici di questo GLB stanno dentro una gabbia
## normalizzata ±1 che non c'entra con l'ingombro reale dell'animale (misurato:
## dim 2.0 contro i ~0.5 veri), e inquadrando su quella il lupo esce grande come
## una formica.
pts = []
for b in rig.data.bones:
    pts.append(rig.matrix_world @ b.head_local)
    pts.append(rig.matrix_world @ b.tail_local)
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
centro = (lo + hi) * 0.5
dim = max((hi - lo).x, (hi - lo).y, (hi - lo).z)
print("bbox mondo lo=%s hi=%s centro=%s dim=%.3f" % (
    tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi),
    tuple(round(v, 3) for v in centro), dim))

cam_data = bpy.data.cameras.new("QA")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = dim * 1.7
cam = bpy.data.objects.new("QA", cam_data)
scn.collection.objects.link(cam)
# 3/4 anteriore ribassato: si legge il fianco su cui cade e insieme il muso
occhio = centro + Vector((dim * 1.3, -dim * 1.5, dim * 0.55))
cam.location = occhio
d = (centro - occhio).normalized()
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
scn.camera = cam

## Pavimento di riferimento a z=0 (nel MONDO l'alto è Z): serve a vedere se il
## corpo appoggia o sprofonda — a occhio, senza un piano, non si distingue.
bpy.ops.mesh.primitive_plane_add(size=dim * 3, location=(centro.x, centro.y, 0.0))

for f in [0, 12, 20, 30, 44]:
    scn.frame_set(f)
    bpy.context.view_layer.update()
    scn.render.filepath = OUT + "wolf_death_f%02d.png" % f
    bpy.ops.render.render(write_still=True)
print("render fatti")

## Quota più bassa raggiunta dalle ossa lungo la clip: se scende sotto zero il
## lupo entra nel terreno.
peggio = 999.0
for f in range(0, 45):
    scn.frame_set(f)
    bpy.context.view_layer.update()
    for pb in rig.pose.bones:
        z = (rig.matrix_world @ pb.matrix).translation.z
        peggio = min(peggio, z)
print("QUOTA MINIMA raggiunta dalle ossa: %.4f (0 = terreno)" % peggio)

# ─── export: solo armatura + questa clip ────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
dest = "C:/Users/adriano.pace/Downloads/LOCAL/arcanium/assets/characters/enemies/anims/wolf_death_01.glb"
bpy.ops.export_scene.gltf(
    filepath=dest, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS', export_yup=True)
print("ESPORTATO:", dest, os.path.getsize(dest), "byte")
