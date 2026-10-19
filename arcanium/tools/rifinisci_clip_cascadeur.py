# -*- coding: utf-8 -*-
"""Prepara per Godot un GLB appena uscito da Cascadeur.

Cascadeur esporta la scena com'e': l'animazione senza nome, e la mesh del corpo
attaccata. Per una CLIP servono solo le ossa e un nome, cosi' la libreria di
animazioni non si porta dietro 5,7 MB di corpo che il gioco ha gia'.

    blender --background --factory-startup --python arcanium/tools/rifinisci_clip_cascadeur.py -- <file.glb> <NomeClip> [--radice-ferma] [--frame N] [--avanza V]

Lavora sul posto: riscrive il GLB che gli si passa.

`--frame N`: la clip viene RITMATA su N frame (a 30 fps), stirando o
comprimendo tutte le chiavi: serve quando la cadenza autorata non e' quella
che il gioco chiede. Si decide con `misura_locomozione.py`, che dice a che
velocita' corrono i PIEDI: una corsa sul posto con i piedi a 8,8 m/s, in un
gioco che avanza a 4,5, o scivola o si ritma (40 frame -> 78).

`--avanza V`: alla clip SUL POSTO si scrive sul `Root` un avanzamento
costante di V m/s lungo l'avanti del personaggio. E' l'inverso di
`--radice-ferma`: in gioco la traslazione del Root e' ROOT MOTION, e sia il
player (`set_root_move`) sia i nemici (`_chase`) avanzano di QUELLA — una
corsa senza Root e' una corsa da fermi. La velocita' giusta e' quella delle
clip di spada che la corsa affianca (player `root-LightRunning` 6,17 m/s,
nemici `sword_run_01` 4,5 m/s), e con `--frame` si fa in modo che i piedi
vadano alla stessa velocita' del Root: niente pattinamento.

`--radice-ferma`: per le clip SUL POSTO che devono girare in loop (l'idle). In
gioco la traslazione del `Root` e' ROOT MOTION: viene tolta dallo scheletro e
consegnata al corpo come spostamento. Se l'animatore ha messo il dondolio
dell'idle (anche solo in parte) sul Root, in gioco quel pezzo di dondolio
sparisce e — peggio — al riavvolgimento del loop il bacino SALTA di quanto il
Root si era spostato (3,6 cm sull'idle dell'arco, 2026-09-14). Con questa
opzione lo spostamento del Root si TRAVASA nell'Hips, frame per frame, e il
Root resta fermo al suo primo valore: il dondolio si vede tutto e il corpo non
salta. Non si usa sulle clip di locomozione, dove il Root deve muoversi.

⚠️ La mesh si toglie DOPO l'import, non chiedendo a Cascadeur di non esportarla:
serve che il GLB tenga la stessa armatura con cui la clip e' stata animata, e
farla uscire per un'altra strada e' un'occasione in piu' di sbagliare rig.
"""
import bpy, sys, os

argomenti = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argomenti) < 2:
    raise SystemExit("uso: ... -- <file.glb> <NomeClip> [--radice-ferma]")
GLB, NOME = argomenti[0], argomenti[1]
RADICE_FERMA = "--radice-ferma" in argomenti[2:]
FRAME = int(argomenti[argomenti.index("--frame") + 1]) if "--frame" in argomenti else 0
AVANZA = float(argomenti[argomenti.index("--avanza") + 1]) if "--avanza" in argomenti else 0.0

FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)

# ⚠️⚠️ L'fps va messo PRIMA dell'import, non dopo. Il glTF tiene i tempi in
# SECONDI e l'importatore li converte in frame con l'fps della scena, che di
# default e' 24: una clip di 2,00 s entra come 48 frame invece che 60. Se poi si
# esporta a 30 fps, quei 48 frame durano 1,6 s — l'animazione esce ACCELERATA
# del 25% e non se ne accorge nessuno, perche' e' fluida e completa: solo piu'
# veloce di come l'ha fatta l'animatore.
bpy.context.scene.render.fps = FPS
bpy.context.scene.render.fps_base = 1.0

bpy.ops.import_scene.gltf(filepath=GLB)

rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
print("rig:", rig.name, "| ossa:", len(rig.data.bones))

for o in list(bpy.data.objects):
    if o is not rig:
        print("  tolgo:", o.name, o.type)
        bpy.data.objects.remove(o, do_unlink=True)

# ⚠️ La posa VALUTATA e' quella che l'esportatore campiona: in 'REST' esce una
# clip ferma anche con le curve giuste. E' cosi' che si erano svuotate le nove
# clip del lupo.
rig.data.pose_position = 'POSE'

azioni = list(bpy.data.actions)
assert len(azioni) == 1, "attesa una sola action, trovate %d: %s" % (
    len(azioni), [a.name for a in azioni])
azione = azioni[0]
print("action:", repr(azione.name), "->", repr(NOME),
      "| frame_range:", tuple(azione.frame_range))
azione.name = NOME
azione.use_fake_user = True

if rig.animation_data is None:
    rig.animation_data_create()
rig.animation_data.action = azione
if azione.slots:
    rig.animation_data.action_slot = azione.slots[0]

# ⚠️ Le chiavi di Cascadeur arrivano a tempi tipo 59,99998 invece di 60: il glTF
# tiene i tempi in secondi e la conversione in frame lascia una deriva minima.
# L'esportatore pero' campiona i frame INTERI, e con l'ultima chiave appena
# sotto il 60 si ferma al 59 — l'ultimo fotogramma sparisce. Si aggancia tutto
# alla griglia dei frame prima di riesportare.
spostate = 0
for strato in azione.layers:
    for striscia in strato.strips:
        for cb in striscia.channelbags:
            for f in cb.fcurves:
                for k in f.keyframe_points:
                    intero = round(k.co.x)
                    if abs(k.co.x - intero) > 1e-6:
                        d = intero - k.co.x
                        k.co.x = intero
                        k.handle_left.x += d
                        k.handle_right.x += d
                        spostate += 1
                f.update()
print("chiavi agganciate ai frame interi:", spostate)

f0, f1 = (int(round(v)) for v in azione.frame_range)

if FRAME > 0 and FRAME != f1 - f0:
    # Il ritmo: ogni chiave (e i suoi manici) scalata attorno al primo frame.
    # Le chiavi finiscono su frame frazionari e restano li': l'esportatore
    # campiona i frame interi interpolando, e con chiavi lineari di Cascadeur
    # (una per frame) e' esattamente la clip rallentata. Riagganciarle alla
    # griglia darebbe un passo irregolare (1,1,2,1,1,2...).
    fattore = FRAME / float(f1 - f0)
    for strato in azione.layers:
        for striscia in strato.strips:
            for cb in striscia.channelbags:
                for f in cb.fcurves:
                    for k in f.keyframe_points:
                        k.co.x = f0 + (k.co.x - f0) * fattore
                        k.handle_left.x = f0 + (k.handle_left.x - f0) * fattore
                        k.handle_right.x = f0 + (k.handle_right.x - f0) * fattore
                    f.update()
    print("ritmo: %d -> %d frame (x%.3f: la clip va a %.0f%% della velocita' autorata)"
          % (f1 - f0, FRAME, fattore, 100.0 / fattore))
    f0, f1 = (int(round(v)) for v in azione.frame_range)
    assert f1 - f0 == FRAME, "il ritmo non e' uscito a %d frame ma a %d" % (FRAME, f1 - f0)

bpy.context.scene.frame_start, bpy.context.scene.frame_end = f0, f1
bpy.context.view_layer.update()
DURATA_ATTESA = (f1 - f0) / float(FPS)
print("durata attesa: %.3f s (%d frame a %d fps)" % (DURATA_ATTESA, f1 - f0, FPS))


def _fcurve(nome_osso, canale):
    percorso = 'pose.bones["%s"].%s' % (nome_osso, canale)
    for strato in azione.layers:
        for striscia in strato.strips:
            for cb in striscia.channelbags:
                for f in cb.fcurves:
                    if f.data_path == percorso:
                        yield f


if RADICE_FERMA:
    # Il Root fermo e il suo spostamento nell'Hips: si registra dov'e' l'Hips
    # nel mondo a ogni frame, si inchioda il Root al primo valore, e si
    # riscrive la location dell'Hips perche' l'Hips torni esattamente li'.
    pb_root, pb_hips = rig.pose.bones["Root"], rig.pose.bones["Hips"]
    frames = list(range(f0, f1 + 1))
    dove = {}
    for f in frames:
        bpy.context.scene.frame_set(f)
        dove[f] = (rig.matrix_world @ pb_hips.matrix).translation.copy()
    bpy.context.scene.frame_set(f0)
    partenza = pb_root.location.copy()
    corsa = 0.0
    for f in frames:
        bpy.context.scene.frame_set(f)
        corsa = max(corsa, (pb_root.location - partenza).length)
    for fc in _fcurve("Root", "location"):
        for k in fc.keyframe_points:
            k.co.y = partenza[fc.array_index]
            k.handle_left.y = k.co.y
            k.handle_right.y = k.co.y
        fc.update()
    for f in frames:
        bpy.context.scene.frame_set(f)
        m = pb_hips.matrix.copy()
        m.translation = rig.matrix_world.inverted() @ dove[f]
        pb_hips.matrix = m
        pb_hips.keyframe_insert("location", frame=f)
    bpy.context.scene.frame_set(f0)
    peggio = 0.0
    for f in frames:
        bpy.context.scene.frame_set(f)
        peggio = max(peggio, ((rig.matrix_world @ pb_hips.matrix).translation - dove[f]).length)
    print("radice ferma: il Root correva %.4f m, ora sta a %s; l'Hips e' tornato dov'era entro %.5f m"
          % (corsa, tuple(round(v, 4) for v in partenza), peggio))
    assert peggio < 0.001, "l'Hips non e' tornato al suo posto"

if AVANZA > 0.0:
    # L'avanti del personaggio e' l'asse Z del Root nello spazio dell'armatura
    # (sul Nephilite: -Y di Blender, cioe' +Z di Godot, dove i nemici guardano).
    # Si scrive la location del Root per frame passando dalla matrice, perche'
    # la `location` corre lungo gli assi dell'osso e non del mondo. L'Hips, che
    # e' figlio, viene avanti da solo: e' tutto il corpo che avanza.
    pb_root = rig.pose.bones["Root"]
    frames = list(range(f0, f1 + 1))
    bpy.context.scene.frame_set(f0)
    avanti = pb_root.matrix.col[2].to_3d().normalized()
    riposo = pb_root.matrix.translation.copy()
    for f in frames:
        bpy.context.scene.frame_set(f)
        m = pb_root.matrix.copy()
        m.translation = riposo + avanti * (AVANZA * (f - f0) / float(FPS))
        pb_root.matrix = m
        bpy.context.view_layer.update()
        pb_root.keyframe_insert("location", frame=f)
    # ⚠️ Lineari a mano: un Root che in Cascadeur non si muoveva mai arriva
    # come sampler STEP, e `keyframe_insert` su una chiave che esiste ne tiene
    # l'interpolazione: Godot importerebbe un avanzamento a scalini.
    for fc in _fcurve("Root", "location"):
        for k in fc.keyframe_points:
            k.interpolation = 'LINEAR'
        fc.update()
    bpy.context.scene.frame_set(f0)
    p0 = (rig.matrix_world @ pb_root.matrix).translation.copy()
    bpy.context.scene.frame_set(f1)
    p1 = (rig.matrix_world @ pb_root.matrix).translation.copy()
    print("avanza: il Root percorre %.3f m in %.3f s lungo %s = %.2f m/s"
          % ((p1 - p0).length, DURATA_ATTESA, tuple(round(v, 2) for v in avanti), (p1 - p0).length / DURATA_ATTESA))
    assert abs((p1 - p0).length / DURATA_ATTESA - AVANZA) < 0.01, "il Root non avanza alla velocita' chiesta"

rig.hide_set(False)
rig.hide_viewport = False
rig.hide_render = False
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig

prima = os.path.getsize(GLB)
bpy.ops.export_scene.gltf(
    filepath=GLB, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_yup=True, export_apply=False)
print("RISCRITTO: %s  %d -> %d byte" % (GLB, prima, os.path.getsize(GLB)))

# ─── Collaudo: la clip si muove ancora? ──────────────────────────────────────
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from varianza_clip_glb import analizza, osso_mosso

for c in analizza(GLB):
    mosse = [n for n, ch in c["ossa"].items() if osso_mosso(ch, 1.0, 0.001)]
    ruotate = [n for n, ch in c["ossa"].items()
               if ch.get("rotation", (0.0,))[0] >= 1.0]
    print("COLLAUDO  %s  %.2fs  ruotate %d | mosse %d / %d"
          % (c["nome"], c["durata"], len(ruotate), len(mosse), len(c["ossa"])))
    assert len(ruotate) >= 2, "la clip e' una posa ferma"
    assert c["nome"] == NOME, "il nome non e' arrivato nel GLB: %r" % c["nome"]
    # ⚠️ La DURATA e' un collaudo a se': una clip accelerata e' fluida, completa
    # e passa qualunque controllo sul movimento. Se non torna, quasi sempre e'
    # l'fps della scena letto al momento sbagliato.
    assert abs(c["durata"] - DURATA_ATTESA) < 0.02, \
        "durata cambiata: %.3f s invece di %.3f" % (c["durata"], DURATA_ATTESA)
print("ok")
