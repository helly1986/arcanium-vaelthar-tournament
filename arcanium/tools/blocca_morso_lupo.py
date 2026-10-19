# -*- coding: utf-8 -*-
"""La BOZZA del morso del lupo per Cascadeur: il balzo portato dal CORPO.

    blender --background --factory-startup --python arcanium/tools/blocca_morso_lupo.py -- \
        <base.glb> <uscita.glb> [provini_dir]

`base.glb` e' la base fatta da `base_cascadeur.py ... root_fermo`
(lavorazione/cascadeur/lupo_bite_01_base.glb): corpo + morso, Root fermo.

═══════════════════════════════════════════════════════════════════════════
PERCHE'
═══════════════════════════════════════════════════════════════════════════
Il morso singolo e' un attacco IN SALTO (author_wolf_attacks.py, MOTO): 1 m di
gioco in avanti e 18 cm di stacco. Ma quel moto sta tutto sull'osso `Root`, che
trasla il lupo INTERO come un pezzo rigido: le zampe scivolano insieme al
corpo, nessuna posteriore spinge, e la parabola e' una tabella invece di una
traiettoria balistica. Misurato sul rig fisico di Cascadeur col Root fermo
(2026-10-09): mentre morde il centro di massa ARRETRA di 14 cm, il bacino non
avanza mai, le zampe dietro bucano il suolo fino a 6,8 cm.

Qui lo stesso metro si rifa' col corpo: carica col peso dietro, spinta delle
posteriori a zampe PIANTATE (IK), volo, atterraggio prima delle anteriori e poi
delle posteriori. Lo stesso istante di contatto del gioco (25/24 s = f31,25 a
30 fps) e lo stesso avanzamento totale: il gameplay non cambia.

E' una BOZZA: in Cascadeur si rigga (casc_rigga_lupo.py), poi l'utente rifinisce
e lancia la fisica sul centro di massa, che rende vera la parabola.

⚠️ UNITA': i numeri delle tabelle sono in CENTIMETRI DI CASCADEUR, cioe' la
scena importata a scala 260 (= 100 cm × 2,6, il lupo comune in gioco). 100 cm
qui = 1 m di gioco. In Blender il lupo e' alto 33 cm: si divide per SCALA.
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
BASE, DST = argv[0], argv[1]
PROVINI = argv[2] if len(argv) > 2 else ""

SCALA = 260.0
ULTIMO = 47

## Il corpo (osso `Hips`), spostamento AGGIUNTO alla posa originale, in cm:
##            (frame, avanti, su)
## Fra le chiavi: Hermite con tangenti nel tempo, e nel volo la
## parabola vera con g = 9,81 m/s² (1,09 cm/frame² a 30 fps).
CORPO = [
    (0,    0.0,  0.0),
    ## ⚠️ Con -4/-6 cm il centro di massa arretrava di 1,2 cm soltanto: la
    ## testa che si alza nella carica compensa il bacino che va indietro.
    (14,  -9.0, -1.0),   # il peso va indietro, sulle posteriori
    (22, -14.0, -2.0),   # carica al massimo (stasi a bocca aperta)
    (24,   4.0,  3.0),   # le posteriori cominciano a distendersi
    (26,  16.0,  9.0),   # STACCO delle posteriori
    ## volo 26 -> 36: balistico, vedi VOLO
    (36,  81.0,  2.0),   # atterrano le anteriori
    (38,  92.0, -4.0),   # atterrano le posteriori, il corpo ammortizza
    (42,  99.0, -3.0),
    (47, 100.0,  0.0),   # fermo: 1 m di gioco piu' avanti
]
## Nel volo il corpo segue la parabola: orizzontale a velocita' costante,
## verticale con la gravita' di Cascadeur (G cm/frame²).
VOLO = (26, 36)
G = 981.0 / 900.0

## Le zampe: quando sono a terra (piantate) e quando volano.
##   stacco: da qui la zampa lascia il punto d'appoggio iniziale
##   atterra: da qui la zampa e' piantata nel punto d'appoggio finale
##   arco: quanto si alza a meta' volo (cm)
##   passo: come avanza in volo, da 0 (stacco) a 1 (atterraggio).
##     "allunga" = subito avanti (le anteriori vanno a cercare il suolo),
##     "trascina" = resta indietro e recupera alla fine (le posteriori, distese
##     dalla spinta, poi richiamate sotto il corpo).
## Il punto finale e' quello della posa dell'ultimo frame, spostata col corpo.
## ⚠️ Prima in volo le zampe seguivano la posa del morso originale, che e' un
## morso da FERMI: le posteriori pendevano dritte sotto il bacino e il lupo
## sembrava appeso, non lanciato.
ZAMPE = {
    "frontleg2":   {"ik": "frontleg1",   "stacco": 24, "atterra": 36, "arco": 12.0, "passo": "allunga"},
    "R_frontleg2": {"ik": "R_frontleg1", "stacco": 24, "atterra": 36, "arco": 12.0, "passo": "allunga"},
    "backleg2":    {"ik": "backleg1",    "stacco": 26, "atterra": 38, "arco": 8.0,  "passo": "trascina"},
    "R_backleg2":  {"ik": "R_backleg1",  "stacco": 26, "atterra": 38, "arco": 8.0,  "passo": "trascina"},
}
PASSO = {"allunga": lambda u: 1.0 - (1.0 - u) ** 2.2, "trascina": lambda u: u ** 2.2}


def velocita_volo():
    """(avanti, su) in cm/frame allo stacco e all'atterraggio: la parabola."""
    a, b = VOLO
    fa = [c for c in CORPO if c[0] == a][0]
    fb = [c for c in CORPO if c[0] == b][0]
    T = float(b - a)
    va = (fb[1] - fa[1]) / T
    v0 = (fb[2] - fa[2]) / T + 0.5 * G * T
    return {a: (va, v0), b: (va, v0 - G * T)}


def corpo_a(f):
    """(avanti, su) in cm al frame f."""
    a, b = VOLO
    if a < f < b:
        fa = [c for c in CORPO if c[0] == a][0]
        va, v0 = velocita_volo()[a]
        return fa[1] + va * (f - a), fa[2] + v0 * (f - a) - 0.5 * G * (f - a) ** 2
    ## Fuori dal volo: Hermite con le tangenti NEL TEMPO (differenze divise sui
    ## vicini), e allo stacco/atterraggio la velocita' della parabola.
    ## ⚠️ Prima era Catmull-Rom per INDICE di chiave: con intervalli diseguali
    ## (10 frame di volo, poi 2) all'atterraggio il corpo scattava di 9 cm in un
    ## frame.
    vv = velocita_volo()
    def tangente(i):
        fi = CORPO[i][0]
        if fi in vv:
            return vv[fi]
        if i == 0 or i == len(CORPO) - 1:
            return (0.0, 0.0)
        p, n = CORPO[i - 1], CORPO[i + 1]
        dt = float(n[0] - p[0])
        return ((n[1] - p[1]) / dt, (n[2] - p[2]) / dt)
    for i in range(len(CORPO) - 1):
        f0, a0, s0 = CORPO[i]
        f1, a1, s1 = CORPO[i + 1]
        if f0 <= f <= f1:
            dt = float(f1 - f0)
            t = (f - f0) / dt
            m0, m1 = tangente(i), tangente(i + 1)
            t2, t3 = t * t, t * t * t
            h00, h10 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t
            h01, h11 = -2 * t3 + 3 * t2, t3 - t2
            return (h00 * a0 + h10 * dt * m0[0] + h01 * a1 + h11 * dt * m1[0],
                    h00 * s0 + h10 * dt * m0[1] + h01 * s1 + h11 * dt * m1[1])
    return CORPO[-1][1], CORPO[-1][2]


bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = 30                    # ⚠️ PRIMA dell'import: il glTF conta in secondi
bpy.ops.import_scene.gltf(filepath=BASE)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
scn.frame_start, scn.frame_end = 0, ULTIMO
bpy.context.view_layer.objects.active = arm
A = arm.matrix_world.copy()
Ainv = A.inverted()

## 1. Tutto a chiavi INTERE: la clip arriva da 24 fps con chiavi a frame
## frazionari, e lo spostamento del corpo si scrive frame per frame.
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.select_all(action="SELECT")
bpy.ops.nla.bake(frame_start=0, frame_end=ULTIMO, only_selected=False, visual_keying=False,
                 clear_constraints=False, use_current_action=True, bake_types={"POSE"})

pb = arm.pose.bones
scn.frame_set(0)
su_w = Vector((0, 0, 1))
muso = (A @ pb["headend"].head) - (A @ pb["Hips"].head)
muso.z = 0.0
## ⚠️ headend sta DIETRO la testa in questo rig: si prende la direzione
## bacino -> testa, che e' quella del muso.
muso_t = (A @ pb["head"].head) - (A @ pb["Hips"].head)
muso_t.z = 0.0
avanti_w = muso_t.normalized()
print("AVANTI (mondo) =", tuple(round(c, 3) for c in avanti_w))

## 2. Il corpo: spostamento dell'Hips in spazio armatura, frame per frame.
for f in range(ULTIMO + 1):
    scn.frame_set(f)
    av, su = corpo_a(f)
    d_w = avanti_w * (av / SCALA) + su_w * (su / SCALA)
    d_a = Ainv.to_3x3() @ d_w
    M = pb["Hips"].matrix.copy()
    M.translation = M.translation + d_a
    pb["Hips"].matrix = M
    bpy.context.view_layer.update()
    pb["Hips"].keyframe_insert("location", frame=f)

## 3. Le zampe in FK (corpo gia' spostato), frame per frame, in mondo.
fk = {z: [] for z in ZAMPE}
for f in range(ULTIMO + 1):
    scn.frame_set(f)
    for z in ZAMPE:
        fk[z].append((A @ pb[z].matrix).copy())
terra = {z: (fk[z][0].translation.z) for z in ZAMPE}

## 4. I bersagli: piantata all'inizio, libera in volo, piantata alla fine.
bersagli = {}
for z, cfg in ZAMPE.items():
    inizio = fk[z][0]
    fine = fk[z][ULTIMO]
    s, t = cfg["stacco"], cfg["atterra"]
    serie = []
    for f in range(ULTIMO + 1):
        if f <= s:
            m = inizio
        elif f >= t:
            m = fine
        else:
            u = (f - s) / float(t - s)
            k = PASSO[cfg["passo"]](u)
            pos = inizio.translation.lerp(fine.translation, k)
            pos.z += math.sin(math.pi * u) * cfg["arco"] / SCALA
            ## la zampa si flette in volo come nella posa originale, e torna
            ## piatta per appoggiarsi
            rot = inizio.to_quaternion().slerp(fine.to_quaternion(), k)
            rot = rot.slerp(fk[z][f].to_quaternion(), math.sin(math.pi * u))
            m = Matrix.Translation(pos) @ rot.to_matrix().to_4x4()
        serie.append(m)
    bersagli[z] = serie

## 5. Vuoti come bersagli, IK sulla catena e rotazione della zampa dal vuoto.
bpy.ops.object.mode_set(mode="OBJECT")
vuoti = {}
for z, cfg in ZAMPE.items():
    e = bpy.data.objects.new("IK_" + z, None)
    scn.collection.objects.link(e)
    e.rotation_mode = "QUATERNION"
    for f, m in enumerate(bersagli[z]):
        e.matrix_world = m
        e.keyframe_insert("location", frame=f)
        e.keyframe_insert("rotation_quaternion", frame=f)
    vuoti[z] = e
    ik = pb[cfg["ik"]].constraints.new("IK")
    ik.target = e
    ik.chain_count = 3
    ik.use_tail = True
    cr = pb[z].constraints.new("COPY_ROTATION")
    cr.target = e

## 6. Bake visivo e via i vincoli.
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.select_all(action="SELECT")
bpy.ops.nla.bake(frame_start=0, frame_end=ULTIMO, only_selected=False, visual_keying=True,
                 clear_constraints=True, use_current_action=True, bake_types={"POSE"})
bpy.ops.object.mode_set(mode="OBJECT")
for e in vuoti.values():
    bpy.data.objects.remove(e, do_unlink=True)

## 7. Misure, in cm di Cascadeur. Errore d'appoggio = quanto la caviglia manca
## il bersaglio quando la zampa dovrebbe essere PIANTATA (scivola o non arriva).
print("\n  f   corpo_av  corpo_su | quota zampe (ant s/d, post s/d)        | errore appoggio max")
scn.frame_set(0)
h0 = (A @ pb["Hips"].head).copy()
errori = []
for f in range(ULTIMO + 1):
    scn.frame_set(f)
    h = A @ pb["Hips"].head
    quote = []
    err = 0.0
    for z, cfg in ZAMPE.items():
        p = A @ pb[z].head
        quote.append((p.z - terra[z]) * SCALA)
        if f <= cfg["stacco"] or f >= cfg["atterra"]:
            err = max(err, (p - bersagli[z][f].translation).length * SCALA)
    errori.append(err)
    print(" %2d   %+6.1f   %+6.1f  | %s | %.1f" % (
        f, (h - h0).dot(avanti_w) * SCALA, (h - h0).z * SCALA,
        "  ".join("%+5.1f" % q for q in quote), err))
print("ERRORE D'APPOGGIO MASSIMO %.1f cm (frame %d)" % (max(errori), errori.index(max(errori))))

## 8. Provini di PROFILO, con un pavimento: la carica, lo stacco e l'atterraggio
## si giudicano solo cosi'.
if PROVINI:
    os.makedirs(PROVINI, exist_ok=True)
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.render.resolution_x, scn.render.resolution_y = 480, 300
    cd = bpy.data.cameras.new("QA")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.4 / 2.6
    cam = bpy.data.objects.new("QA", cd)
    scn.collection.objects.link(cam)
    lato = avanti_w.cross(su_w)
    ## centrata a meta' del balzo (50 cm di Cascadeur avanti), un filo dall'alto:
    ## di profilo esatto il pavimento si vede di taglio e sparisce
    centro = h0 + avanti_w * (50.0 / SCALA)
    centro.z = 0.13
    occhio = (lato + su_w * 0.18).normalized()
    cam.location = centro + occhio * 3.0
    cam.rotation_euler = (-occhio).to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    bpy.ops.mesh.primitive_plane_add(size=4.0, location=(centro.x, centro.y, terra["backleg2"] - 0.012))
    for f in range(0, ULTIMO + 1, 2):
        scn.frame_set(f)
        scn.render.filepath = os.path.join(PROVINI, "blocco_f%02d.png" % f)
        bpy.ops.render.render(write_still=True)
    for o in [o for o in bpy.data.objects if o.type in ("CAMERA",) or o.name.startswith("Plane")]:
        bpy.data.objects.remove(o, do_unlink=True)

## 9. Export come base_cascadeur: armatura + mesh pesate, niente texture.
pesate = [o for o in bpy.data.objects if o.type == "MESH"
          and any(md.type == "ARMATURE" and md.object == arm for md in o.modifiers)]
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
for o in pesate:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", use_selection=True,
                          export_animations=True, export_skins=True, export_apply=False,
                          export_yup=True, export_image_format="NONE",
                          export_force_sampling=True, export_frame_range=True,
                          export_optimize_animation_size=False)
print("EXPORT", DST, os.path.getsize(DST), "byte")
