# -*- coding: utf-8 -*-
"""Misura una clip di LOCOMOZIONE: velocita', cadenza, chiusura del loop.

    blender --background --factory-startup --python arcanium/tools/misura_locomozione.py -- <clip.glb>

Stampa, in metri e secondi:

  • quanto avanza il ROOT (root motion: e' cio' che in gioco muove il corpo);
  • a che velocita' vanno i PIEDI: sui frame in cui la palla del piede sta
    a terra (entro 6 cm dal suo minimo) il piede d'appoggio arretra rispetto
    al Root alla velocita' con cui il corpo avanza — se il Root avanza di
    meno, i piedi PATTINANO di quel tanto. Una clip "sul posto" ha Root zero
    e piedi che vanno comunque a una loro velocita': e' il numero che
    `rifinisci_clip_cascadeur.py --frame/--avanza` deve rispettare;
  • la CADENZA: il periodo del passo, dai passaggi del piede destro davanti;
  • la CHIUSURA DEL LOOP: primo contro ultimo frame, media e peggiore delle
    rotazioni (20 ossa del corpo) e spostamento dell'Hips; e la finestra
    interna che chiuderebbe meglio, se la clip non chiude — cosi' si dice
    all'animatore DOVE, non solo "non chiude".

Nato sulla corsa con l'arco (2026-09-14): autorata sul posto a 40 frame,
piedi a 8,8 m/s (una volata), 2,7 passi — nessuna coppia di frame a distanza
di un passo si somigliava sotto i 12 gradi di media.
"""
import bpy, sys, math
from mathutils import Vector

SRC = sys.argv[sys.argv.index("--") + 1]
FPS = 30
OSSA = ["Hips", "UpperLeg_R", "LowerLeg_R", "Ankle_R", "UpperLeg_L", "LowerLeg_L", "Ankle_L",
        "Spine_01", "Spine_02", "Spine_03", "Neck", "Head", "Clavicle_R", "Shoulder_R", "Elbow_R",
        "Hand_R", "Clavicle_L", "Shoulder_L", "Elbow_L", "Hand_L"]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS
bpy.ops.import_scene.gltf(filepath=SRC)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
act = list(bpy.data.actions)[0]
arm.animation_data_create(); arm.animation_data.action = act
if act.slots:
    arm.animation_data.action_slot = act.slots[0]
f0, f1 = int(round(act.frame_range[0])), int(round(act.frame_range[1]))
sc = bpy.context.scene
frames = list(range(f0, f1 + 1))
durata = (f1 - f0) / float(FPS)
ossa = [n for n in OSSA if n in arm.pose.bones]


def mondo(f, n):
    sc.frame_set(f)
    return arm.matrix_world @ arm.pose.bones[n].matrix


print("clip %s: %d frame (%d..%d), %.3f s" % (SRC.replace("\\", "/").split("/")[-1], f1 - f0, f0, f1, durata))

## Il Root: quanto avanza, e lungo cosa.
r0 = mondo(f0, "Root").translation.copy(); r1 = mondo(f1, "Root").translation.copy()
avanti = mondo(f0, "Root").col[2].to_3d().normalized()
print("root motion: %.3f m in %.3f s = %.2f m/s  (avanti del Root: %s)"
      % ((r1 - r0).length, durata, (r1 - r0).length / durata, tuple(round(v, 2) for v in avanti)))

## I piedi rispetto al Root: velocita' d'appoggio.
palle = [n for n in ("Ball_R", "Ball_L") if n in arm.pose.bones]
rel = {}
for n in palle:
    rel[n] = []
    for f in frames:
        mr = mondo(f, "Root")
        rel[n].append(mr.inverted() @ mondo(f, n).translation)
## Nel riferimento del Root l'asse Z locale e' l'avanti e l'asse Y l'alto.
zmin = min(min(v.y for v in rel[n]) for n in palle) if palle else 0.0
vel = []
for i in range(1, len(frames)):
    n = min(palle, key=lambda k: rel[k][i].y)
    if rel[n][i].y < zmin + 0.06:
        v = (rel[n][i] - rel[n][i - 1]) * FPS
        ## il piede d'appoggio arretra: la componente lungo -avanti
        vel.append(-v.z)
if vel:
    vel.sort()
    print("piedi: il piede d'appoggio arretra a %.2f m/s (mediana su %d frame a terra; massimo %.2f)"
          % (vel[len(vel) // 2], len(vel), vel[-1]))
    if (r1 - r0).length / durata < vel[len(vel) // 2] * 0.9:
        print("  ⚠️ il Root avanza meno dei piedi: in gioco pattinano di %.2f m/s"
              % (vel[len(vel) // 2] - (r1 - r0).length / durata))

## La cadenza: periodo del piede destro davanti (massimi della Z locale).
if "Ball_R" in rel:
    zs = [v.z for v in rel["Ball_R"]]
    picchi = [i for i in range(1, len(zs) - 1) if zs[i] > zs[i - 1] and zs[i] >= zs[i + 1] and zs[i] > 0.2]
    if len(picchi) >= 2:
        periodi = [picchi[i + 1] - picchi[i] for i in range(len(picchi) - 1)]
        print("cadenza: piede destro davanti ai frame %s -> passo (due appoggi) di %.1f frame = %.2f s; la clip contiene %.1f passi"
              % (picchi, sum(periodi) / len(periodi), sum(periodi) / len(periodi) / FPS, (f1 - f0) / (sum(periodi) / len(periodi))))

## La chiusura del loop.
pose = {}
for f in frames:
    sc.frame_set(f)
    pose[f] = {n: arm.pose.bones[n].matrix_basis.to_quaternion() for n in ossa}
    pose[f]["_hips"] = arm.pose.bones["Hips"].matrix_basis.translation.copy()


def dist(a, b):
    tot = 0.0; peggio = (0.0, "")
    for n in ossa:
        ang = math.degrees(a[n].rotation_difference(b[n]).angle); ang = min(ang, 360.0 - ang)
        tot += ang
        if ang > peggio[0]:
            peggio = (ang, n)
    return tot / len(ossa), peggio, (a["_hips"] - b["_hips"]).length


m, p, dt = dist(pose[f0], pose[f1])
print("loop: primo vs ultimo frame, media %.1f gradi, peggio %s %.1f, Hips %.1f cm  -> %s"
      % (m, p[1], p[0], dt * 100.0, "chiude" if m < 4.0 and p[0] < 10.0 else "NON CHIUDE"))
if m >= 4.0 or p[0] >= 10.0:
    coppie = []
    for i in frames:
        for j in frames:
            if j - i >= 8:
                mm, pp, dd = dist(pose[i], pose[j])
                coppie.append((mm, i, j, pp, dd))
    coppie.sort()
    print("  le finestre interne che chiuderebbero meglio (inizio -> fine, lunghezza, media, peggiore, Hips):")
    for mm, i, j, pp, dd in coppie[:5]:
        print("    f%02d -> f%02d  %2d frame  %5.1f gradi  %s %.1f  %.1f cm" % (i, j, j - i, mm, pp[1], pp[0], dd * 100.0))
