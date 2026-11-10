# -*- coding: utf-8 -*-
"""Prepara per Godot un GLB appena uscito da Cascadeur.

Cascadeur esporta la scena com'e': l'animazione senza nome, e la mesh del corpo
attaccata. Per una CLIP servono solo le ossa e un nome, cosi' la libreria di
animazioni non si porta dietro 5,7 MB di corpo che il gioco ha gia'.

    blender --background --factory-startup --python arcanium/tools/rifinisci_clip_cascadeur.py -- <file.glb> <NomeClip> [--radice-ferma] [--frame N] [--avanza V] [--sopra-terra]

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
dal suo punto piu' basso, come lo misura `prova_cammino.gd`, e si muove a meno di
tre quarti della velocita' del corpo (nel passo accostato i piedi si alzano appena,
ma chi fa il passo va al doppio del corpo; il piede d'appoggio dello sprint generato
scivola fino a 16 cm in due frame); per ogni fase a
terra il metatarso si inchioda in orizzontale alla mediana della fase, coscia
e stinco si ripiegano con un IK a due ossa (il ginocchio resta nel suo piano)
e il piede tiene la sua rotazione: il tallone si alza come prima. Dopo lo
stacco la correzione sfuma in due frame, senza mai riportare il metatarso
dietro al punto d'appoggio. La clip e' un loop che avanza: le fasi a cavallo
del giro si leggono srotolando il ciclo di un passo. Va dopo `--radice-lineare`.

`--piede-dritto` (con `--piedi-fermi`): il piede a terra si gira attorno al metatarso
fino a puntare dove si corre, con la pianta in piano (la pendenza resta): il motion
generation appoggiava il destro della corsa china girato di 100-130 gradi (2026-11-09).

`--specchia-gamba l|r`: l'altra gamba diventa lo specchio di questa, sfasata di mezzo
ciclo (solo loop simmetrici: la corsa). Il motion generation storceva la destra della corsa
china (2026-11-09).

`--specchio-di <gemella.glb>`: la clip diventa lo specchio della gemella gia' rifinita, tutte
le ossa (.l e .r scambiate), sfasata di mezzo ciclo. Gli strafe a destra sono lo specchio di
quelli a sinistra (2026-11-10): il motion generation non appoggiava mai il destro, e l'utente
li vuole "identici tra loro ma speculari", braccia comprese. Va da sola dopo `--taglia`: il
resto (piedi fermi, polso dritto) la gemella ce l'ha gia', e rifarlo romperebbe lo specchio.

`--presa-da <pose.glb> <frame>`: la seconda mano sull'arma a due mani torna a ogni frame dove
stava rispetto alla destra nella clip delle pose a quel frame (IK a due ossa sul braccio
sinistro, gomito nel suo piano): il motion generation staccava la sinistra di Zarine di 10 cm
dall'asta in spalla (2026-11-10). Va dopo `--chiudi-giro`, al posto di `--polso-dritto hand.l`.

`--arma-al-petto <pose.glb> <frame>`: la mano destra torna a ogni frame dove stava rispetto al
petto (spine_03.x) nella clip delle pose: l'arma in spalla si muove col busto. Il motion
generation girava il polso e l'asta di Zarine oscillava di 40 gradi nella corsa (2026-11-10).
Va con `--presa-da`, che porta dietro la sinistra.

`--taglia A B`: si tengono i frame A..B, riportati a 0..B-A. Per il motion generation su
due cicli (la corsa, 2026-11-09): il ciclo di mezzo, lontano dagli estremi dove il
generatore parte e arriva come da fermo. Va prima di tutto il resto.

`--polso-dritto hand.l[,hand.r]`: il polso torna dritto sull'avambraccio, con un filo di
ritardo. Le pose chiave orientavano lo scudo con una mira sulla mano, e con la presa fissa
la mira piegava il polso: 51-81 gradi verso il basso su cammino e corsa di Edran
(2026-11-09; a riposo 4). L'utente: "dovrebbe essere quasi dritto e seguire il flow della
corsa con piccoli sobbalzini". La mano prende l'orientamento che ha sull'avambraccio a
riposo, e se ne porta dietro il RITARDO (35%) di com'era due frame prima: segue il braccio
come un polso morbido. Le dita vengono con lei. Va dopo `--chiudi-giro`.

`--chiudi-giro`: il MOTION GENERATION non rispetta del tutto le chiavi, e
l'ultimo frame non torna sul primo (cammino di Edran, 2026-11-09: stinco
destro 27°, coscia 20°): in loop scatterebbe a ogni giro. Come in
`casc_taglia_loop.py`, la differenza si spalma su tutto il ciclo: al frame k
ogni osso riceve k/N della correzione che porta l'ultimo frame sul primo
(slerp per le rotazioni). La radice no, che avanza. Va dopo `--radice-lineare`
e prima di `--bacino-liscio` e `--piedi-fermi`.

`--bacino-liscio`: per le clip del MOTION GENERATION di Cascadeur (2026-11-09).
Il generatore e' obbligato a passare dalle pose chiave, e li' la traiettoria del
bacino fa uno spigolo: al giro del loop avanzava di 6,2 cm un frame e di 3,0 il
successivo, e a ogni chiave scendeva di 0,7 cm per risalire subito. Tolta la
retta da un capo all'altro, cio' che resta del bacino e' periodico e si liscia
col binomiale [1 4 6 4 1]/16 attorno al ciclo: gli spigoli spariscono e il
rimbalzo del passo perde il 7%. Solo la traslazione; i piedi che il bacino si
e' portato dietro li rimette a terra `--piedi-fermi`, che va insieme. Va dopo
`--radice-lineare`.

Le ossa sono quelle dello scheletro del GLB: `Root`/`Hips` sul Nephilite,
`c_traj`/`root.x` su ARP (le stesse che `arp_humanoid.tres` chiama Root/Hips).

⚠️ La mesh si toglie DOPO l'import, non chiedendo a Cascadeur di non esportarla:
serve che il GLB tenga la stessa armatura con cui la clip e' stata animata, e
farla uscire per un'altra strada e' un'occasione in piu' di sbagliare rig.
"""
import bpy, sys, os, math
from mathutils import Quaternion

argomenti = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argomenti) < 2:
    raise SystemExit("uso: ... -- <file.glb> <NomeClip> [--radice-ferma]")
GLB, NOME = argomenti[0], argomenti[1]
RADICE_FERMA = "--radice-ferma" in argomenti[2:]
FRAME = int(argomenti[argomenti.index("--frame") + 1]) if "--frame" in argomenti else 0
POLSI = argomenti[argomenti.index("--polso-dritto") + 1].split(",") if "--polso-dritto" in argomenti else []
TAGLIA = tuple(int(argomenti[argomenti.index("--taglia") + k]) for k in (1, 2)) if "--taglia" in argomenti else None
AVANZA = float(argomenti[argomenti.index("--avanza") + 1]) if "--avanza" in argomenti else 0.0
RADICE_LINEARE = "--radice-lineare" in argomenti[2:]
PIEDI_FERMI = "--piedi-fermi" in argomenti[2:]
PIEDE_DRITTO = "--piede-dritto" in argomenti[2:]
SPECCHIA = argomenti[argomenti.index("--specchia-gamba") + 1] if "--specchia-gamba" in argomenti else ""
SPECCHIO_DI = argomenti[argomenti.index("--specchio-di") + 1] if "--specchio-di" in argomenti else ""
PRESA_DA = argomenti[argomenti.index("--presa-da") + 1] if "--presa-da" in argomenti else ""
PRESA_FRAME = int(argomenti[argomenti.index("--presa-da") + 2]) if "--presa-da" in argomenti else 0
ARMA_AL_PETTO = argomenti[argomenti.index("--arma-al-petto") + 1] if "--arma-al-petto" in argomenti else ""
PRESA_FRAME_PETTO = int(argomenti[argomenti.index("--arma-al-petto") + 2]) if "--arma-al-petto" in argomenti else 0
BACINO_LISCIO = "--bacino-liscio" in argomenti[2:]
CHIUDI_GIRO = "--chiudi-giro" in argomenti[2:]
SOPRA_TERRA = "--sopra-terra" in argomenti[2:]

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

if TAGLIA is not None:
    # Il pezzo da tenere, riportato a partire da 0. Le chiavi sono una per frame
    # (la clip e' cotta): fuori dal pezzo si tolgono, dentro si spostano.
    da, a = TAGLIA
    assert f0 <= da < a <= f1, "taglio %s fuori dalla clip %d-%d" % (TAGLIA, f0, f1)
    for strato in azione.layers:
        for striscia in strato.strips:
            for cb in striscia.channelbags:
                for f in cb.fcurves:
                    for k in reversed(list(f.keyframe_points)):
                        if round(k.co.x) < da or round(k.co.x) > a:
                            f.keyframe_points.remove(k)
                    for k in f.keyframe_points:
                        k.co.x -= da
                        k.handle_left.x -= da
                        k.handle_right.x -= da
                    f.update()
    f0, f1 = 0, a - da
    print("taglio: frame %d-%d -> 0-%d" % (da, a, f1))

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

if CHIUDI_GIRO:
    # Per ogni osso (la radice no: avanza) la correzione C porta l'ultimo frame
    # sul primo, C @ q(fine) = q(inizio); al frame k se ne applica la frazione
    # k/N, con lo slerp per le rotazioni e in proporzione per le traslazioni.
    N = f1 - f0
    rot, loc = {}, {}
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        for pb in rig.pose.bones:
            rot[(f, pb.name)] = pb.rotation_quaternion.copy()
            loc[(f, pb.name)] = pb.location.copy()
    scarti = []
    for pb in rig.pose.bones:
        if pb.name == OSSO_RADICE:
            continue
        q0, q1 = rot[(f0, pb.name)], rot[(f1, pb.name)]
        if q0.dot(q1) < 0.0:
            q1 = -q1
        C = q0 @ q1.inverted()
        dl = loc[(f0, pb.name)] - loc[(f1, pb.name)]
        if C.angle < 1e-4 and dl.length < 1e-5:
            continue
        scarti.append((math.degrees(C.angle), dl.length, pb.name))
        I = C.copy()
        I.identity()
        prima = None
        for f in range(f0, f1 + 1):
            t = (f - f0) / float(N)
            q = I.slerp(C, t) @ rot[(f, pb.name)]
            if prima is not None and q.dot(prima) < 0.0:
                q.negate()
            prima = q
            pb.rotation_quaternion = q
            pb.location = loc[(f, pb.name)] + dl * t
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    scarti.sort(reverse=True)
    print("chiudi giro: %d ossa chiuse; le piu' aperte: %s" % (len(scarti), ", ".join(
        "%s %.1f° %.1f cm" % (n, a, l * 100.0) for a, l, n in scarti[:6])))

if BACINO_LISCIO:
    # Il bacino, tolta la retta da un capo all'altro, e' periodico: lo si
    # liscia col binomiale [1 4 6 4 1]/16, girando attorno al ciclo.
    pb_hips = rig.pose.bones[OSSO_BACINO]
    N = f1 - f0
    bacino = {}
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        bacino[f] = pb_hips.matrix.copy()
    t0, t1 = bacino[f0].translation, bacino[f1].translation
    retta = lambda f: t0.lerp(t1, (f - f0) / float(N))
    resto = [bacino[f0 + i].translation - retta(f0 + i) for i in range(N)]
    PESI = (1.0, 4.0, 6.0, 4.0, 1.0)
    liscio = [sum((resto[(i + k - 2) % N] * p for k, p in enumerate(PESI)), resto[0] * 0.0) / 16.0
              for i in range(N)]

    def passi(serie):
        v = [serie[(i + 1) % N] - serie[i] for i in range(N)]
        return max((v[(i + 1) % N] - v[i]).length for i in range(N))

    spostato = 0.0
    for f in range(f0, f1 + 1):
        m = bacino[f].copy()
        m.translation = retta(f) + liscio[(f - f0) % N]
        spostato = max(spostato, (m.translation - bacino[f].translation).length)
        bpy.context.scene.frame_set(f)
        pb_hips.matrix = m
        bpy.context.view_layer.update()
        pb_hips.keyframe_insert("location", frame=f)
    print("bacino liscio: spostato al piu' di %.4f m; strappo massimo (accelerazione) da %.4f a %.4f m/frame2"
          % (spostato, passi(resto), passi(liscio)))

if SPECCHIA:
    # La gamba opposta come SPECCHIO di questa, sfasata di mezzo ciclo. Il motion
    # generation faceva la gamba sinistra della corsa china pulita e la destra storta:
    # il piede appoggiato girato di 100-130 gradi e in volo coricato fino a 65 (2026-11-09,
    # l'utente: "perche' il piede destro ruota e si deforma?"). Le ossa ARP delle due
    # gambe sono una lo specchio dell'altra sul piano di mezzo (riposo destro = sinistro
    # con y e z del quaternione cambiati di segno), e cosi' le rotazioni locali.
    # Va prima di --piedi-fermi, che poi inchioda anche il piede specchiato.
    ALTRO = {"l": "r", "r": "l"}[SPECCHIA]
    N = f1 - f0
    # Prima il BACINO simmetrico: ogni frame e' la media fra se' e lo specchio del frame
    # a mezzo ciclo. Con il bacino del motion generation (piu' alto e girato da un lato)
    # la gamba specchiata non arrivava a terra: il destro restava a 9-11 cm.
    from mathutils import Matrix
    SX = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    pb_r, pb_b = rig.pose.bones[OSSO_RADICE], rig.pose.bones[OSSO_BACINO]
    bacino = {}
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        m = pb_b.matrix.copy()
        m.translation -= pb_r.matrix.translation
        bacino[f] = m
    for f in range(f0, f1 + 1):
        g = f0 + (f - f0 + N // 2) % N
        a_, b_ = bacino[f], SX @ bacino[g] @ SX
        q = a_.to_quaternion().slerp(b_.to_quaternion(), 0.5)
        m = q.to_matrix().to_4x4()
        bpy.context.scene.frame_set(f)
        m.translation = (a_.translation + b_.translation) * 0.5 + pb_r.matrix.translation
        pb_b.matrix = m
        bpy.context.view_layer.update()
        pb_b.keyframe_insert("location", frame=f)
        pb_b.keyframe_insert("rotation_quaternion", frame=f)
    GAMBA = ("thigh_twist", "thigh_stretch", "leg_stretch", "leg_twist", "foot", "toes_01")
    copiate = 0
    for nome in GAMBA:
        src, dst = nome + "." + SPECCHIA, nome + "." + ALTRO
        if src not in rig.pose.bones or dst not in rig.pose.bones:
            continue
        curve = {fc.array_index: fc for fc in _fcurve(src, "rotation_quaternion")}
        if len(curve) < 4:
            continue
        pb = rig.pose.bones[dst]
        ultimo = None
        for f in range(f0, f1 + 1):
            g = f0 + (f - f0 + N // 2) % N
            w, x, y, z = (curve[i].evaluate(g) for i in range(4))
            q = Quaternion((w, x, -y, -z)).normalized()
            if ultimo is not None and q.dot(ultimo) < 0.0:
                q.negate()
            ultimo = q.copy()
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
        copiate += 1
    print("specchia gamba: %d ossa della %s copiate sulla %s, sfasate di %d frame" % (copiate, SPECCHIA, ALTRO, N // 2))

if SPECCHIO_DI:
    # Questa clip diventa lo SPECCHIO della gemella, gia' rifinita: tutte le ossa, scambiando
    # le .l con le .r, sul piano di mezzo, sfasate di mezzo ciclo (la gemella parte dall'altro
    # piede). Lo strafe a destra e' lo specchio di quello a sinistra (2026-11-10).
    # Prima solo gambe e bacino: il motion generation non appoggiava mai la gamba che corre
    # davanti nello strafe di corsa (il destro a 13-27 cm in quattro generazioni). Poi
    # l'utente: "identici tra loro ma speculari", anche colonna e testa; e anche le braccia,
    # "perche' non e' detto che il giocatore scelga di dotarsi di scudo": con un sigillo
    # leggero in mano un braccio diverso dall'altro lato non avrebbe senso.
    # Le ossa ARP dei due lati sono una lo specchio dell'altra (riposo destro = sinistro con
    # y e z del quaternione cambiati di segno) e le centrali (.x) hanno la X laterale: la
    # rotazione locale si specchia in (w, x, -y, -z), la posizione locale in (-x, y, z).
    from mathutils import Matrix, Vector
    SX = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    N = f1 - f0
    prima_di = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SPECCHIO_DI)
    nuovi = [o for o in bpy.data.objects if o not in prima_di]
    gemello = next(o for o in nuovi if o.type == 'ARMATURE')
    ag = gemello.animation_data.action
    g0, g1 = (int(round(v)) for v in ag.frame_range)
    assert g1 - g0 == N, "la gemella ha %d frame, questa %d" % (g1 - g0, N)
    CENTRO = (OSSO_RADICE, OSSO_BACINO)

    def speculare(nome):
        if nome.endswith(".l"):
            return nome[:-2] + ".r"
        if nome.endswith(".r"):
            return nome[:-2] + ".l"
        return nome

    altre = [pb.name for pb in gemello.pose.bones
             if pb.name not in CENTRO and speculare(pb.name) in rig.pose.bones]
    # Radice e bacino nello spazio dell'armatura; tutte le altre in locale.
    centro, locale = {}, {}
    for i in range(N + 1):
        bpy.context.scene.frame_set(g0 + i)
        for n in CENTRO:
            centro[(i, n)] = gemello.pose.bones[n].matrix.copy()
        for n in altre:
            pb = gemello.pose.bones[n]
            locale[(i, n)] = (pb.rotation_quaternion.copy(), pb.location.copy())
    for o in nuovi:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a is not azione:
            bpy.data.actions.remove(a)
    peggio = 0.0
    ultimo = {}
    # La radice avanza: sfasando di mezzo ciclo, i frame che ripartono dall'inizio della
    # gemella vanno portati avanti di un ciclo intero (prima tornavano indietro di 2,56 m).
    passo = centro[(N, OSSO_RADICE)].translation - centro[(0, OSSO_RADICE)].translation
    for f in range(f0, f1 + 1):
        giri, g = divmod(f - f0 + N // 2, N)
        bpy.context.scene.frame_set(f)
        for n in CENTRO:
            m = centro[(g, n)].copy()
            m.translation += passo * giri
            m = SX @ m @ SX
            pb = rig.pose.bones[n]
            pb.matrix = m
            bpy.context.view_layer.update()
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            peggio = max(peggio, (pb.matrix.translation - m.translation).length)
        for n in altre:
            (w, x, y, z), l = locale[(g, n)]
            q = Quaternion((w, x, -y, -z)).normalized()
            k = speculare(n)
            if k in ultimo and q.dot(ultimo[k]) < 0.0:
                q.negate()
            ultimo[k] = q.copy()
            pb = rig.pose.bones[k]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q
            pb.location = Vector((-l.x, l.y, l.z))
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    bpy.context.view_layer.update()
    print("specchio di %s: radice, bacino e %d ossa specchiate, sfasate di %d frame; "
          "radice e bacino al posto entro %.5f m" % (os.path.basename(SPECCHIO_DI), len(ultimo), N // 2, peggio))
    assert peggio < 0.001, "radice o bacino non sono finiti dove dovevano"

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
    # Con --piede-dritto, quanto il piede a terra va raddrizzato (0..1, sfuma con lo stacco).
    dritto = {s: [0.0] * N for s in "lr"}
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

        # A terra: basso E quasi fermo. Nel passo accostato dello strafe i piedi si alzano
        # appena e con la sola altezza il piede risultava a terra anche mentre faceva il
        # passo (inchiodato, la gamba non ci arrivava: 2026-11-09). Fermo = meno di tre quarti
        # della velocita' del corpo, sul piu' lento dei due tratti (prima o dopo il frame):
        # i contatti dello sprint durano due frame, e sulla differenza centrata il bordo
        # del contatto prendeva il frame in volo.
        lento = piatto(passo).length / N * 0.75

        def fermo(i):
            return min((piatto(dove(i + 1)) - piatto(dove(i))).length,
                       (piatto(dove(i)) - piatto(dove(i - 1))).length) < lento

        giu = {i: dove(i).z < basso + A_TERRA and fermo(i) for i in range(-N - SFUMA, 2 * N + SFUMA)}
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
                dritto[s][i % N] = 1.0
            for k in range(1, SFUMA + 1):
                w = (SFUMA + 1 - k) / float(SFUMA + 1)
                correzione[s][(a - k) % N] += (fermo - piatto(dove(a))) * w
                dritto[s][(a - k) % N] = max(dritto[s][(a - k) % N], w)
                dritto[s][(b + k) % N] = max(dritto[s][(b + k) % N], w)
                p = piatto(dove(b + k))
                nuovo = p + (fermo - piatto(dove(b))) * w
                indietro = (fermo - nuovo).dot(avanti)
                if indietro > 0.0:
                    nuovo += avanti * indietro   # mai dietro al punto d'appoggio
                correzione[s][(b + k) % N] += nuovo - p
            resoconto.append("%s frame %d-%d: scorreva fino a %.1f cm" % (s, a % N, b % N, prima * 100.0))

    ultimo = {}
    atteso = {}
    from mathutils import Quaternion
    tesa = tesa_prima = manca = 0.0
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        for s in "lr":
            d = correzione[s][(f - f0) % N]
            peso_dritto = dritto[s][(f - f0) % N] if PIEDE_DRITTO else 0.0
            if d.length < 1e-5 and peso_dritto <= 0.0:
                continue
            nc, ns, npi, _ = catena(s)
            Mc, Ms, Mp = orig[(f, nc)], orig[(f, ns)], orig[(f, npi)]
            if peso_dritto > 0.0:
                # Il piede a terra punta dove si corre, con la pianta in piano: il motion
                # generation appoggiava il destro della corsa china girato di 100-130 gradi e
                # coricato di 20-45 (2026-11-09, l'utente: "perche' il piede destro ruota?").
                # Si gira attorno al metatarso, che resta inchiodato; la pendenza resta.
                T = orig[(f, "toes_01." + s)].translation
                punta = T - Mp.translation
                pend = math.atan2(punta.z, piatto(punta).length)
                voluta = avanti * math.cos(pend) + Vector((0.0, 0.0, math.sin(pend)))
                r1 = punta.normalized().rotation_difference(voluta.normalized())
                fianco = r1 @ Mp.to_3x3().col[0].normalized()
                piano = voluta.normalized().cross(Vector((0.0, 0.0, 1.0))).normalized()
                if piano.dot(fianco) < 0.0:
                    piano = -piano
                r2 = fianco.rotation_difference(piano)
                r = Quaternion().slerp(r2 @ r1, peso_dritto)
                Mp = attorno(Mp, T, r.to_matrix())
                atteso[(f, s)] = (r.to_matrix().to_4x4() @ orig[(f, "toes_01." + s)]).to_quaternion()
            H, K, A = Mc.translation, Ms.translation, Mp.translation
            A2 = A + d
            l1, l2, dist = (K - H).length, (A - K).length, (A2 - H).length
            tesa_prima = max(tesa_prima, (A - H).length / (l1 + l2))
            if dist > (l1 + l2) * 0.999:
                # La gamba non ci arriva (il ginocchio del motion generation e'
                # gia' dritto a fine appoggio): resta tesa al 99,9% verso il
                # punto, e il piede manca il bersaglio di quel poco.
                A2 = H + (A2 - H).normalized() * (l1 + l2) * 0.999
                manca = max(manca, (A + d - A2).length)
                d = A2 - A
                correzione[s][(f - f0) % N] = d
                dist = (A2 - H).length
            tesa = max(tesa, dist / (l1 + l2))
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
                if correzione[s][(f - f0) % N].length >= 1e-5 or (PIEDE_DRITTO and dritto[s][(f - f0) % N] > 0.0):
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
            q_ora = m.to_quaternion().normalized()
            q_voluto = atteso.get((f, s), orig[(f, "toes_01." + s)].to_quaternion()).normalized()
            giro = max(giro, 2.0 * math.acos(min(1.0, abs(q_ora.dot(q_voluto)))))
    for r in resoconto:
        print("piedi fermi:", r)
    print("piedi fermi: metatarso al suo posto entro %.5f m, rotazione del piede entro %.4f rad, gamba tesa al %.1f%% (era al %.1f%%), dove non arrivava manca di %.4f m"
          % (peggio, giro, tesa * 100.0, tesa_prima * 100.0, manca))
    assert peggio < 0.001 and giro < 0.001, "il piede non e' finito dove doveva"

if POLSI:
    from mathutils import Quaternion
    RITARDO, INDIETRO = 0.35, 2
    N = f1 - f0
    W3 = rig.matrix_world.to_quaternion()
    for nome in POLSI:
        pb = rig.pose.bones[nome]
        riposo = (pb.parent.bone.matrix_local.inverted() @ pb.bone.matrix_local).to_quaternion()
        dritta, pos, piega = {}, {}, []
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            dritta[f] = pb.parent.matrix.to_quaternion() @ riposo
            pos[f] = pb.matrix.translation.copy()
            piega.append(math.degrees(pb.matrix.to_quaternion().rotation_difference(dritta[f]).angle))
        ultimo = None
        for f in range(f0, f1 + 1):
            prima = dritta[f0 + (f - f0 - INDIETRO) % N]
            q = dritta[f].slerp(prima, RITARDO)
            bpy.context.scene.frame_set(f)
            m = q.to_matrix().to_4x4()
            m.translation = pos[f]
            pb.matrix = m
            bpy.context.view_layer.update()
            if ultimo is not None and pb.rotation_quaternion.dot(ultimo) < 0.0:
                pb.rotation_quaternion = -pb.rotation_quaternion
            ultimo = pb.rotation_quaternion.copy()
            pb.keyframe_insert("rotation_quaternion", frame=f)
        dopo = []
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            dopo.append(math.degrees(pb.matrix.to_quaternion().rotation_difference(
                pb.parent.matrix.to_quaternion() @ riposo).angle))
        print("polso dritto %s: piegato %.0f-%.0f gradi -> %.0f-%.0f (il ritardo)" % (
            nome, min(piega), max(piega), min(dopo), max(dopo)))

def _rel_da(percorso, frame, da, a):
    """La posa di `a` nello spazio di `da` al `frame` della clip in `percorso` (stesso scheletro)."""
    prima_di = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=percorso)
    nuovi = [o for o in bpy.data.objects if o not in prima_di]
    gemello = next(o for o in nuovi if o.type == 'ARMATURE')
    bpy.context.scene.frame_set(frame)
    rel = gemello.pose.bones[da].matrix.inverted() @ gemello.pose.bones[a].matrix
    for o in nuovi:
        bpy.data.objects.remove(o, do_unlink=True)
    for a_ in list(bpy.data.actions):
        if a_ is not azione:
            bpy.data.actions.remove(a_)
    return rel


def _mano_su(s, da, rel, etichetta):
    """IK a due ossa sul braccio `s` ("l"/"r"): a ogni frame la mano torna a `rel` nello spazio
    dell'osso `da`, il gomito nel suo piano (come seconda_mano.gd del gioco)."""
    from mathutils import Matrix
    SPALLA, GOMITO, MANO = (rig.pose.bones[n + "." + s] for n in ("arm_stretch", "forearm_stretch", "hand"))

    def attorno(pb, perno, r3):
        pb.matrix = Matrix.Translation(perno) @ r3.to_4x4() @ Matrix.Translation(-perno) @ pb.matrix
        bpy.context.view_layer.update()

    peggio, spostata = 0.0, 0.0
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        T = rig.pose.bones[da].matrix @ rel
        a, b, c = SPALLA.head.copy(), GOMITO.head.copy(), MANO.head.copy()
        spostata = max(spostata, (c - T.translation).length)
        l1, l2 = (b - a).length, (c - b).length
        t = T.translation
        verso = t - a
        d = min(max(verso.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
        verso.normalize()
        fuori = (b - a) - verso * (b - a).dot(verso)
        fuori.normalize()
        cos_a = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)))
        gomito = a + (verso * cos_a + fuori * math.sqrt(1.0 - cos_a * cos_a)) * l1
        attorno(SPALLA, a, (b - a).rotation_difference(gomito - a).to_matrix())
        b, c = GOMITO.head.copy(), MANO.head.copy()
        attorno(GOMITO, b, (c - b).rotation_difference(t - b).to_matrix())
        m = T.copy()
        m.translation = MANO.head.copy()
        MANO.matrix = m
        bpy.context.view_layer.update()
        for pb in (SPALLA, GOMITO, MANO):
            pb.keyframe_insert("rotation_quaternion", frame=f)
        peggio = max(peggio, (MANO.head - t).length)
    print("%s: la mano si era staccata fino a %.1f cm, ora e' al suo posto entro %.2f cm"
          % (etichetta, spostata * 100.0, peggio * 100.0))


if ARMA_AL_PETTO:
    # L'arma APPOGGIATA SULLA SPALLA si muove col busto: la destra torna a ogni frame dove
    # stava rispetto al petto (spine_03.x) nelle pose chiave. Fra una chiave e l'altra il motion
    # generation girava il polso, e l'asta di Zarine passava da verticale a 40 gradi a ogni
    # passo della corsa (2026-11-10). Va prima di `--presa-da`, che le porta dietro la sinistra.
    _mano_su("r", "spine_03.x", _rel_da(ARMA_AL_PETTO, PRESA_FRAME_PETTO, "spine_03.x", "hand.r"),
             "arma al petto da %s f%d" % (os.path.basename(ARMA_AL_PETTO), PRESA_FRAME_PETTO))

if PRESA_DA:
    # La SECONDA MANO sull'arma a due mani, come nelle pose chiave: la sinistra torna a ogni
    # frame dove stava rispetto alla destra nella clip delle pose (frame PRESA_FRAME). E'
    # seconda_mano.gd del gioco, con la presa di questa clip. Il motion generation la staccava
    # di 10 cm dall'asta anche col constraint Points attivo (Zarine, l'asta in spalla, 2026-11-10).
    _mano_su("l", "hand.r", _rel_da(PRESA_DA, PRESA_FRAME, "hand.r", "hand.l"),
             "presa a due mani da %s f%d" % (os.path.basename(PRESA_DA), PRESA_FRAME))

if SOPRA_TERRA:
    # I PIEDI SUL PAVIMENTO in una clip che non e' un ciclo (la rotolata, 2026-11-10: le dita
    # andavano 4-7 cm sotto terra all'appoggio accosciato). Il pavimento corre col Root
    # (c_traj); ogni dito (metatarso e punta) non scende sotto l'altezza che ha da in piedi a
    # riposo. Dove scende, il bacino sale di quanto manca, preso al massimo su due frame per
    # parte perche' non salti. Sale tutto il corpo: e' giusto finche' sono i piedi a toccare.
    from mathutils import Vector
    assert ARP, "--sopra-terra conosce solo le dita ARP (toes_01)"
    W = rig.matrix_world
    pb_hips, pb_root = rig.pose.bones[OSSO_BACINO], rig.pose.bones[OSSO_RADICE]
    DITA = [("toes_01." + s_, capo) for s_ in "lr" for capo in ("head", "tail")]
    rig.data.pose_position = 'REST'
    bpy.context.view_layer.update()
    a_riposo = {d: (W @ getattr(rig.pose.bones[d[0]], d[1])).z - (W @ pb_root.head).z for d in DITA}
    rig.data.pose_position = 'POSE'
    bpy.context.view_layer.update()

    def manca_a(f):
        bpy.context.scene.frame_set(f)
        terra = (W @ pb_root.head).z
        return max(0.0, max(terra + a_riposo[d] - (W @ getattr(rig.pose.bones[d[0]], d[1])).z for d in DITA))

    manca = {f: manca_a(f) for f in range(f0, f1 + 1)}
    alza = {f: max(manca[g] for g in range(max(f0, f - 2), min(f1, f + 2) + 1)) for f in manca}
    for f in range(f0, f1 + 1):
        if alza[f] <= 0.0:
            continue
        bpy.context.scene.frame_set(f)
        m = W @ pb_hips.matrix
        m.translation = m.translation + Vector((0.0, 0.0, alza[f]))
        pb_hips.matrix = W.inverted() @ m
        bpy.context.view_layer.update()
        pb_hips.keyframe_insert("location", frame=f)
    dopo = max(manca_a(f) for f in range(f0, f1 + 1))
    print("sopra terra: dita a riposo %s m dal pavimento; scendevano fino a %.3f m sotto, il bacino "
          "e' salito fino a %.3f m; ora al piu' %.4f m sotto"
          % (", ".join("%.3f" % v for v in a_riposo.values()), max(manca.values()), max(alza.values()), dopo))

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
