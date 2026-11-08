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

`--radice-lineare`: per le clip di locomozione che AVANZANO davvero (il cammino
fatto in Cascadeur col `c_traj` che porta il corpo, 2026-11-08). Fra le chiavi
la Bezier fa partire e arrivare la radice rallentata (1,9 cm il primo frame
invece di 4,8): in gioco e' root motion, e il corpo inciamperebbe a ogni giro
del loop. La radice diventa una retta dal primo all'ultimo valore, e la
differenza passa al bacino, frame per frame: il corpo resta dov'era nel mondo.

`--piedi-fermi`: il piede A TERRA non scivola (solo scheletro ARP). Allo stacco
la fisica di Cascadeur lascia il metatarso arretrare mentre il tallone sale:
7,3 cm sul cammino di Edran (2026-11-08), e in gioco si vede il piede che
pattina. Un piede e' a terra quando il metatarso (`toes_01`) sta entro 1,5 cm
dal suo punto piu' basso, come lo misura `prova_cammino.gd`; per ogni fase a
terra il metatarso si inchioda in orizzontale alla mediana della fase, coscia
e stinco si ripiegano con un IK a due ossa (il ginocchio resta nel suo piano)
e il piede tiene la sua rotazione: il tallone si alza come prima. Dopo lo
stacco la correzione sfuma in due frame, senza mai riportare il metatarso
dietro al punto d'appoggio. La clip e' un loop che avanza: le fasi a cavallo
del giro si leggono srotolando il ciclo di un passo. Va dopo `--radice-lineare`.

Le ossa sono quelle dello scheletro del GLB: `Root`/`Hips` sul Nephilite,
`c_traj`/`root.x` su ARP (le stesse che `arp_humanoid.tres` chiama Root/Hips).

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
RADICE_LINEARE = "--radice-lineare" in argomenti[2:]
PIEDI_FERMI = "--piedi-fermi" in argomenti[2:]

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
ARP = "c_traj" in rig.data.bones
OSSO_RADICE, OSSO_BACINO = ("c_traj", "root.x") if ARP else ("Root", "Hips")

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
    pb_root, pb_hips = rig.pose.bones[OSSO_RADICE], rig.pose.bones[OSSO_BACINO]
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
    for fc in _fcurve(OSSO_RADICE, "location"):
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

if RADICE_LINEARE:
    # Dov'e' il bacino (nello spazio dell'armatura) a ogni frame; poi la radice
    # in retta fra il primo e l'ultimo frame; poi il bacino rimesso li'.
    pb_root, pb_hips = rig.pose.bones[OSSO_RADICE], rig.pose.bones[OSSO_BACINO]
    frames = list(range(f0, f1 + 1))
    bacino, radice = {}, {}
    for f in frames:
        bpy.context.scene.frame_set(f)
        bacino[f] = pb_hips.matrix.copy()
        radice[f] = pb_root.matrix.copy()
    giro = max(radice[f].to_quaternion().rotation_difference(radice[f0].to_quaternion()).angle for f in frames)
    assert giro < 0.01, "la radice ruota (%.3f rad): la retta vale solo per una radice che trasla" % giro
    da, a = radice[f0].translation, radice[f1].translation
    scarto = 0.0
    for f in frames:
        m = radice[f].copy()
        m.translation = da.lerp(a, (f - f0) / float(f1 - f0))
        scarto = max(scarto, (m.translation - radice[f].translation).length)
        bpy.context.scene.frame_set(f)
        pb_root.matrix = m
        bpy.context.view_layer.update()
        pb_root.keyframe_insert("location", frame=f)
    for fc in _fcurve(OSSO_RADICE, "location"):
        for k in fc.keyframe_points:
            k.interpolation = 'LINEAR'
        fc.update()
    for f in frames:
        bpy.context.scene.frame_set(f)
        pb_hips.matrix = bacino[f]
        bpy.context.view_layer.update()
        pb_hips.keyframe_insert("location", frame=f)
        pb_hips.keyframe_insert("rotation_quaternion", frame=f)
    peggio = 0.0
    for f in frames:
        bpy.context.scene.frame_set(f)
        peggio = max(peggio, (pb_hips.matrix.translation - bacino[f].translation).length)
    print("radice lineare: %.3f m in %d frame; si scostava fino a %.4f m dalla retta; il bacino e' tornato entro %.5f m"
          % ((a - da).length, f1 - f0, scarto, peggio))
    assert peggio < 0.001, "il bacino non e' tornato al suo posto"

if PIEDI_FERMI:
    import math
    from mathutils import Matrix, Vector
    assert ARP, "--piedi-fermi conosce solo le gambe ARP (thigh_stretch, leg_stretch, foot, toes_01)"
    A_TERRA, SFUMA = 0.015, 2
    W = rig.matrix_world
    Wi = W.inverted()
    N = f1 - f0

    def catena(s):
        return ("thigh_stretch." + s, "leg_stretch." + s, "foot." + s, "toes_01." + s)

    def piatto(v):
        return Vector((v.x, v.y, 0.0))

    def terna(x, rif):
        # Base ortonormale con il primo asse lungo `x` e il terzo normale al piano (x, rif).
        e1 = x.normalized()
        e3 = e1.cross(rif).normalized()
        return Matrix((e1, e3.cross(e1), e3)).transposed()

    def attorno(m, perno, r3):
        return Matrix.Translation(perno) @ r3.to_4x4() @ Matrix.Translation(-perno) @ m

    # Le pose originali nel mondo, prima di toccare qualunque chiave.
    orig = {}
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        for s in "lr":
            for n in catena(s):
                orig[(f, n)] = (W @ rig.pose.bones[n].matrix).copy()

    # Per lato, la correzione orizzontale del metatarso a ogni frame del ciclo.
    correzione = {s: [Vector() for _ in range(N)] for s in "lr"}
    resoconto = []
    for s in "lr":
        palla = [orig[(f, "toes_01." + s)].translation.copy() for f in range(f0, f1 + 1)]
        passo = palla[N] - palla[0]
        avanti = piatto(passo).normalized()
        basso = min(p.z for p in palla[:N])

        def dove(i):
            # Il ciclo srotolato: il giro dopo e' lo stesso passo, un passo piu' avanti.
            q, r = divmod(i, N)
            return palla[r] + passo * q

        giu = {i: dove(i).z < basso + A_TERRA for i in range(-N - SFUMA, 2 * N + SFUMA)}
        for a in range(N):
            # Un frame solo sopra la soglia non stacca il piede (il destro di Edran
            # al frame 26 risale di 1,5 mm): le due meta' sono la stessa fase.
            if not giu[a] or giu[a - 1] or giu[a - 2]:
                continue
            b = a
            while giu[b + 1] or giu[b + 2]:
                b += 1 if giu[b + 1] else 2
            punti = [piatto(dove(i)) for i in range(a, b + 1)]
            xs, ys = sorted(p.x for p in punti), sorted(p.y for p in punti)
            fermo = Vector((xs[len(xs) // 2], ys[len(ys) // 2], 0.0))
            prima = max((p - fermo).length for p in punti)
            for i in range(a, b + 1):
                correzione[s][i % N] += fermo - piatto(dove(i))
            for k in range(1, SFUMA + 1):
                w = (SFUMA + 1 - k) / float(SFUMA + 1)
                correzione[s][(a - k) % N] += (fermo - piatto(dove(a))) * w
                p = piatto(dove(b + k))
                nuovo = p + (fermo - piatto(dove(b))) * w
                indietro = (fermo - nuovo).dot(avanti)
                if indietro > 0.0:
                    nuovo += avanti * indietro   # mai dietro al punto d'appoggio
                correzione[s][(b + k) % N] += nuovo - p
            resoconto.append("%s frame %d-%d: scorreva fino a %.1f cm" % (s, a % N, b % N, prima * 100.0))

    ultimo = {}
    tesa = tesa_prima = 0.0
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        for s in "lr":
            d = correzione[s][(f - f0) % N]
            if d.length < 1e-5:
                continue
            nc, ns, npi, _ = catena(s)
            Mc, Ms, Mp = orig[(f, nc)], orig[(f, ns)], orig[(f, npi)]
            H, K, A = Mc.translation, Ms.translation, Mp.translation
            A2 = A + d
            l1, l2, dist = (K - H).length, (A - K).length, (A2 - H).length
            tesa = max(tesa, dist / (l1 + l2))
            tesa_prima = max(tesa_prima, (A - H).length / (l1 + l2))
            assert dist < (l1 + l2) * 0.999, "f%d %s: la gamba non arriva (%.4f su %.4f)" % (f, s, dist, l1 + l2)
            u = (A2 - H).normalized()
            v = (K - H) - u * (K - H).dot(u)
            v.normalize()
            lungo = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
            K2 = H + u * lungo + v * math.sqrt(max(l1 * l1 - lungo * lungo, 0.0))
            R1 = terna(K2 - H, A2 - H) @ terna(K - H, A - H).transposed()
            A1 = H + R1 @ (A - H)
            R2 = (A1 - K2).rotation_difference(A2 - K2).to_matrix()
            Mp2 = Mp.copy()
            Mp2.translation = A2
            for n, m in ((nc, attorno(Mc, H, R1)), (ns, attorno(attorno(Ms, H, R1), K2, R2)), (npi, Mp2)):
                pb = rig.pose.bones[n]
                pb.matrix = Wi @ m
                bpy.context.view_layer.update()
        # Le chiavi, con il quaternione dallo stesso lato del frame prima: una
        # chiave col segno girato fa fare al Godot il giro lungo fra due frame.
        for s in "lr":
            for n in catena(s)[:3]:
                pb = rig.pose.bones[n]
                q = pb.rotation_quaternion.copy()
                if n in ultimo and q.dot(ultimo[n]) < 0.0:
                    q.negate()
                    pb.rotation_quaternion = q
                ultimo[n] = q
                if correzione[s][(f - f0) % N].length >= 1e-5:
                    pb.keyframe_insert("rotation_quaternion", frame=f)
                    pb.keyframe_insert("location", frame=f)

    # Collaudo: il metatarso sta dove doveva, e il piede ha la rotazione di prima.
    peggio = giro = 0.0
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        for s in "lr":
            m = W @ rig.pose.bones["toes_01." + s].matrix
            voluto = orig[(f, "toes_01." + s)].translation + correzione[s][(f - f0) % N]
            peggio = max(peggio, (m.translation - voluto).length)
            giro = max(giro, m.to_quaternion().rotation_difference(
                orig[(f, "toes_01." + s)].to_quaternion()).angle)
    for r in resoconto:
        print("piedi fermi:", r)
    print("piedi fermi: metatarso al suo posto entro %.5f m, rotazione del piede entro %.4f rad, gamba tesa al %.1f%% (era al %.1f%%)"
          % (peggio, giro, tesa * 100.0, tesa_prima * 100.0))
    assert peggio < 0.001 and giro < 0.001, "il piede non e' finito dove doveva"

if AVANZA > 0.0:
    # L'avanti del personaggio e' l'asse Z del Root nello spazio dell'armatura
    # (sul Nephilite: -Y di Blender, cioe' +Z di Godot, dove i nemici guardano).
    # Si scrive la location del Root per frame passando dalla matrice, perche'
    # la `location` corre lungo gli assi dell'osso e non del mondo. L'Hips, che
    # e' figlio, viene avanti da solo: e' tutto il corpo che avanza.
    pb_root = rig.pose.bones[OSSO_RADICE]
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
    for fc in _fcurve(OSSO_RADICE, "location"):
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
