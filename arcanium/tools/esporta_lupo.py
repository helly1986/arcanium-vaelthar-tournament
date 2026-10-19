# -*- coding: utf-8 -*-
"""Ri-esporta `wolf_animated.glb` dal blend di lavoro, con l'osso `jaw`.

⚠️ Questa e' l'UNICA eccezione legittima alla regola «non ri-esportare mai il
file base»: i pesi vivono con la mesh, quindi una mandibola pesata non puo'
arrivare in gioco come clip separata. Backup fatto prima; verifica strutturale
subito dopo, e `verifica_clip_nemico.gd` prima di rimettere in gioco.

Il file da sostituire contiene 9 animazioni con nomi PRECISI
(bite, bite_combo, death, hit, howl, idle, leap, run, walk) dove bite/bite_combo/
death sono gli ORIGINALI del pack — in gioco vengono gia' scavalcati dalla
libreria in anims/wolf/, ma il fallback li cerca qui. Vanno riprodotti uguali.
"""
import bpy, os, math, mathutils

## ⚠️ Ricavata dallo script (`<radice>/arcanium/tools/`), non scritta a mano:
## era fissata al percorso del PC vecchio.
RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")).replace("\\", "/")
DEST = RADICE + "/assets/characters/enemies/wolf_animated.glb"
SORGENTE = RADICE + "/assets/characters/enemies/anims/_sorgenti/lupo_moveset.blend"

## ⚠️ Lo script apre da se' il blend sorgente, e va lanciato in BACKGROUND:
##     blender --background --factory-startup --python arcanium/tools/esporta_lupo.py
## Piu' sotto cancella action e oggetti per ripulire l'export. Lanciato dentro
## una sessione aperta si porterebbe via il lavoro dell'utente — e siccome
## `pose_position` in memoria puo' essere gia' diverso da com'e' su disco (sul
## disco e' 'REST'), il risultato dipenderebbe pure da cosa e' successo prima.
bpy.ops.wm.open_mainfile(filepath=SORGENTE)

## nome nel GLB  <-  action nel blend
MAPPA = {
    "bite": "zz_ORIGINALE_bite",
    "bite_combo": "zz_ORIGINALE_bite_combo",
    "death": "zz_ORIGINALE_death",
    "hit": "hit",
    "howl": "howl",
    "idle": "idle",
    "leap": "leap",
    "run": "run",
    "walk": "walk",
}

rig = bpy.data.objects["LupoRig"]
mesh = bpy.data.objects["WolfMesh"]

# ⚠️⚠️ QUI SI ROMPEVANO TUTTE E NOVE LE CLIP. Due guasti sovrapposti, e
# sistemarne uno solo non si vedeva:
#
# 1. `pose_position` su disco e' 'REST'. L'esportatore campiona la posa
#    VALUTATA, che in REST e' la posa di riposo a ogni frame: la clip esce ferma
#    anche se le curve nel blend hanno ampiezza fino a 1,215.
#
# 2. C'era `pb.rotation_mode = 'XYZ'`. Le 28 ossa sono in QUATERNION e tutte le
#    action animano `rotation_quaternion`: passandole a Euler, quelle curve
#    restano orfane e non pilotano piu' niente. Sopravviveva solo la
#    TRASLAZIONE di `Hips` — ed e' precisamente l'unico osso che si muoveva nel
#    file consegnato.
#
# Misurato affiancando tre export (walk/run/howl, ossa mosse su 28):
#    POSE + rotation_mode XYZ ->  1 /  1 /  1     (il file rotto)
#    POSE, rotation_mode fermo -> 25 / 18 / 21    (giusto)
#    REST                      ->  0 /  0 /  0    (controllo negativo)
#
# La posa va azzerata, ma SENZA toccare `rotation_mode`.
rig.data.pose_position = 'POSE'
if rig.animation_data:
    rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.rotation_euler = (0, 0, 0)
    pb.scale = (1, 1, 1)

# il GLB in gioco ha la radice `WolfRig`: il nome del nodo va riprodotto
rig.name = "WolfRig"

## L'osso `Root` a terra, per il root motion: Godot lo cerca con quel nome
## esatto (`root_motion_track = "%GeneralSkeleton:Root"`). Il rig del blend non
## ce l'ha — la sua radice è `Hips` — quindi va creato qui, o ri-esportare il
## file base lo cancellerebbe ogni volta.
if "Root" not in rig.data.bones:
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    r = eb.new("Root")
    r.head = (0.0, 0.0, 0.0)
    r.tail = (0.0, 0.10, 0.0)   # +Y locale = l'alto: matrice locale = identità
    r.roll = 0.0
    r.use_deform = False
    h = eb["Hips"]
    h.parent = r
    h.use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    print("  aggiunto osso Root")

# via tutto cio' che non deve essere esportato (la modalita' ACTIONS esporta
# DAVVERO tutte le action del file, comprese quelle che non c'entrano)
tenere = set(MAPPA.values())
for a in list(bpy.data.actions):
    if a.name not in tenere:
        print("  scarto action:", a.name)
        bpy.data.actions.remove(a)
for nuovo, vecchio in MAPPA.items():
    if vecchio != nuovo:
        bpy.data.actions[vecchio].name = nuovo
for o in list(bpy.data.objects):
    if o not in (rig, mesh):
        print("  scarto oggetto:", o.name, o.type)
        bpy.data.objects.remove(o, do_unlink=True)

print("action esportate:", sorted(a.name for a in bpy.data.actions))
assert sorted(a.name for a in bpy.data.actions) == sorted(MAPPA), "action sbagliate"

# ─── ROOT MOTION su walk e run ───────────────────────────────────────────────
## Le clip sono authorate SUL POSTO. Finora l'avanzamento lo metteva il
## controller con `walk_speed`/`run_speed`, due numeri scelti a occhio: il lupo
## andava il 34% piu' veloce della sua falcata e le zampe strisciavano.
##
## Qui l'avanzamento si SCRIVE sull'osso `Root`, alla velocita' MISURATA da
## `arcanium/tools/misura_falcata_lupo.py`. Godot lo estrae (`root_motion_track`
## punta a `Root`) e lo consegna al controller, che smette di inventarselo.
##
## ⚠️ La direzione NON si indovina: si ricava dal segno dello scivolamento delle
## zampe a terra. In una clip sul posto la zampa piantata scorre all'INDIETRO,
## quindi il verso di marcia e' l'opposto.
##
## ⚠️⚠️ Qui si scrive la FALCATA (metri per ciclo), non la velocita'. La falcata
## e' spazio: non dipende da quanti fotogrammi al secondo gira la scena. La
## velocita' si', ed e' gia' costata un errore del 25% — il blend del lupo gira
## a 24 fps, e la prima misura contava i suoi fotogrammi come se fossero 30.
## Scrivendo metri-per-ciclo la durata se la prende la clip da sola, e l'fps
## esce completamente dal discorso.
FALCATA = {"walk": 0.284, "run": 0.546}     # metri per ciclo, misurati
SOGLIA_APPOGGIO = 0.25

zampe = [b.name for b in rig.data.bones
         if len(b.children) == 0 and "leg" in b.name.lower()]
assert len(zampe) == 4, "attese 4 zampe, trovate %d: %s" % (len(zampe), zampe)

bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='OBJECT')


def estensione_esportata(azione):
    """I fotogrammi INTERI che l'esportatore campionera' davvero.

    ⚠️ Le chiavi di queste clip cadono a fotogrammi FRAZIONARI: 0, 0.8, 1.6 ...
    12.8, perche' sono state authorate a 30 fps e il blend gira a 24. L'esportatore
    glTF campiona i fotogrammi interi, quindi l'ultima chiave (12.8) non viene mai
    raggiunta e la clip finisce al 12.

    Arrotondando si otterrebbe 13, e una chiave di `Root` li' allunga la clip di
    un fotogramma: su tredici e' l'8% di velocita' in meno, cioe' esattamente il
    pattinaggio che questo lavoro doveva togliere. Va troncato, non arrotondato.

    La falcata misurata si riferisce alla clip COSI' COM'E' NEL GLB — cioe' a
    questa estensione — quindi e' su questa che va distribuita.
    """
    return int(math.floor(azione.frame_range[0])), int(math.floor(azione.frame_range[1]))


def verso_di_marcia(azione):
    """Versore orizzontale in cui la clip avanza, dal segno dello scivolamento."""
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = azione
    if azione.slots:
        rig.animation_data.action_slot = azione.slots[0]
    f0, f1 = (int(round(v)) for v in azione.frame_range)

    tracce = {z: [] for z in zampe}
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        for z in zampe:
            tracce[z].append((rig.matrix_world @ rig.pose.bones[z].head).copy())

    somma = mathutils.Vector((0.0, 0.0, 0.0))
    campioni = 0
    for z in zampe:
        zs = [p.z for p in tracce[z]]
        lo, hi = min(zs), max(zs)
        limite = lo + SOGLIA_APPOGGIO * (hi - lo)
        a_terra = {i for i, v in enumerate(zs) if v <= limite}
        for i in sorted(a_terra):
            if i + 1 in a_terra:
                d = tracce[z][i + 1] - tracce[z][i]
                d.z = 0.0
                somma += d
                campioni += 1
    assert campioni > 0, "nessun appoggio trovato in %s" % azione.name
    scivolamento = somma / campioni
    assert scivolamento.length > 1e-5, "le zampe non scivolano: clip gia' in moto?"
    return -scivolamento.normalized(), campioni


for nome, falcata in FALCATA.items():
    azione = bpy.data.actions[nome]
    avanti, campioni = verso_di_marcia(azione)
    f0, f1 = estensione_esportata(azione)
    dichiarato = tuple(int(round(v)) for v in azione.frame_range)
    if (f0, f1) != dichiarato:
        print("  %s: campionati %s, dichiarato %s" % (nome, (f0, f1), dichiarato))
    assert f1 > f0, "clip %s senza durata" % nome

    ## ⚠️ Si azzera tutto il resto della posa di `Root` PRIMA di scrivere: se
    ## restasse una rotazione, Godot la consumerebbe come rotazione del corpo.
    pb = rig.pose.bones["Root"]
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)
    for f in range(f0, f1 + 1):
        avanzamento = (f - f0) / float(f1 - f0)   # 0 all'inizio, 1 alla fine
        pb.location = avanti * falcata * avanzamento
        pb.keyframe_insert("location", frame=f)

    ## ⚠️ Interpolazione LINEARE, non Bezier. Con le morbidezze di default la
    ## velocita' non e' costante: accelera e rallenta dentro il ciclo, e in un
    ## anello di camminata quello e' pattinaggio a ogni giro.
    for strato in azione.layers:
        for striscia in strato.strips:
            for cb in striscia.channelbags:
                for fc in cb.fcurves:
                    if fc.data_path.endswith('["Root"].location') or \
                            '"Root"' in fc.data_path and fc.data_path.endswith("location"):
                        for k in fc.keyframe_points:
                            k.interpolation = 'LINEAR'
                        fc.update()

    print("  root motion su %-5s: falcata %.3f m su %d frame  verso (%.2f, %.2f, %.2f)  [%d appoggi]"
          % (nome, falcata, f1 - f0, avanti.x, avanti.y, avanti.z, campioni))

rig.animation_data.action = None

# tutto visibile: un oggetto nascosto viene ESCLUSO senza errore
for o in (rig, mesh):
    o.hide_set(False)
    o.hide_viewport = False
    o.hide_render = False
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = rig

bpy.ops.export_scene.gltf(
    filepath=DEST, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_yup=True, export_apply=False)
print("ESPORTATO:", DEST, os.path.getsize(DEST), "byte")

# ─── Collaudo, sul file appena scritto ───────────────────────────────────────
# ⚠️ Controllare che i canali ci siano NON basta: le nove clip rotte avevano
# tutti i canali al loro posto, con dentro lo stesso valore a ogni chiave. Qui
# si misura la VARIANZA, ed e' l'unico motivo per cui l'errore non torna.
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from varianza_clip_glb import analizza, osso_mosso

## Il cancello guarda le ossa che RUOTANO, non quante si muovono in tutto.
## ⚠️ La prima versione chiedeva almeno 8 ossa mosse e bocciava `hit`, che e'
## sana: e' un sussulto di 0,38 s in cui si muovono solo testa (18,9°) e petto
## (11,2°) mentre le zampe restano piantate. Il cancello va tarato sul GUASTO,
## non su un'idea di quanto debba essere ricca un'animazione — e il guasto era
## ZERO ossa in rotazione, con in piedi solo la traslazione di `Hips`.
MINIMO_OSSA_RUOTATE = 2
SOGLIA_GRADI = 1.0

print("=== COLLAUDO: varianza per osso ===")
guasti = []
for c in analizza(DEST):
    ruotate = [n for n, ch in c["ossa"].items()
               if ch.get("rotation", (0.0,))[0] >= SOGLIA_GRADI]
    mosse = [n for n, ch in c["ossa"].items() if osso_mosso(ch, SOGLIA_GRADI, 0.001)]
    ok = len(ruotate) >= MINIMO_OSSA_RUOTATE
    print("  %-12s %5.2fs  ruotate %3d | mosse %3d / %3d   [%s]"
          % (c["nome"], c["durata"], len(ruotate), len(mosse),
             len(c["ossa"]), "ok" if ok else "POSA FERMA"))
    if not ok:
        guasti.append(c["nome"])

assert not guasti, "clip senza rotazione, sono pose ferme: %s" % ", ".join(guasti)
print("Tutte e %d le clip ruotano davvero delle ossa." % len(MAPPA))

# ─── Collaudo del ROOT MOTION, letto dal GLB ─────────────────────────────────
## ⚠️ Si rilegge la falcata dal file scritto invece di fidarsi di quella
## chiesta: fra la posa in Blender e il GLB ci sono la conversione Y-up, il
## campionamento a frame interi e l'fps della scena. Se uno dei tre sposta il
## numero, il lupo pattina — e pattinare e' esattamente il difetto che questo
## lavoro doveva togliere.
from varianza_clip_glb import leggi_glb, leggi_accessor

js, binario = leggi_glb(DEST)
nomi = [n.get("name", "?") for n in js["nodes"]]
print("=== COLLAUDO: root motion ===")
for anim in js.get("animations", []):
    nome = anim.get("name")
    atteso = FALCATA.get(nome)
    for canale in anim.get("channels", []):
        b = canale["target"]
        if b.get("path") != "translation" or nomi[b["node"]] != "Root":
            continue
        camp = anim["samplers"][canale["sampler"]]
        v = leggi_accessor(js, binario, camp["output"])
        t = [x[0] for x in leggi_accessor(js, binario, camp["input"])]
        percorso = sum((v[i + 1][k] - v[i][k]) ** 2 for i in range(len(v) - 1)
                       for k in range(3)) ** 0.5
        netto = sum((v[-1][k] - v[0][k]) ** 2 for k in range(3)) ** 0.5
        if atteso is None:
            assert netto < 1e-4, \
                "%s non deve avere root motion, e ne ha %.4f m" % (nome, netto)
            continue
        print("  %-5s falcata nel GLB %.4f m (chiesta %.4f)  durata %.2f s"
              "  -> %.3f m/s" % (nome, netto, atteso, t[-1], netto / t[-1]))
        assert abs(netto - atteso) < 0.005, \
            "%s: falcata %.4f invece di %.4f" % (nome, netto, atteso)
print("Root motion come misurato.")
