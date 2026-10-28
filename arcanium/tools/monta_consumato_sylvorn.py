"""Monta un corpo dell'ARMATA CONSUMATA SYLVORN sul rig condiviso.

PIPELINE (confermata dall'utente il 2026-08-17): **ARP rigga, poi si travasa sul
Nephilite.** ARP fa rilevazione dei giunti e binding sul corpo nuovo — il suo
heat map e' molto meglio dell'auto-weight su ascelle e spalle — e poi mesh e
pesi si portano sul rig Nephilite INTATTO, cosi' le clip di `anims/sword` e
`anims/spear` restano native e non si retargetta niente.

Uso, dentro Blender (Blender 5.1 + Auto-Rig Pro con gli AI Tools installati):

    P = r"...\\arcanium\\tools\\monta_consumato_sylvorn.py"
    exec(compile(open(P, encoding='utf-8').read(), P, 'exec'), globals())
    prepara("sylvorn_fante")     # importa, pulisce, misura
    rigga()                      # catena ARP completa + i due collaudi

⚠️ PREREQUISITO: gli AI Tools di ARP devono stare in
`Documents\\AutoRigPro\\AI\\` — `info.dat` nella radice e i modelli `.pth` +
gli `inference_*.exe` dentro `inference/`. Il pacchetto e' `AI_win_1.22`.
Se mancano, `guess_markers` non parte: FERMARSI e chiederli, non inventare una
strada alternativa (e' gia' costato un giro).

⚠️ DAL PONTE MCP anche l'IMPORT glTF vuole il `temp_override`, non solo gli
operatori Smart di ARP: senza, `bpy.context.object` e' None e l'importatore muore
dentro `armature_display`. Si avvolge l'intera `prepara()`:

    with bpy.context.temp_override(**_ctx()):
        prepara("sylvorn_fante")

⚠️ E il ponte MCP RICREA IL NAMESPACE a ogni chiamata: una variabile globale
messa da una chiamata non c'e' piu' nella successiva. Per seguire una catena
lunga senza andare in timeout si scrive l'esito in `bpy.app.driver_namespace`,
che sopravvive, e la si lancia da un `bpy.app.timers` (gli operatori Blender non
sono sicuri fuori dal thread principale, un thread vero non va bene).

⚠️ IL RIG NON E' NEL REPO. I blend sono file di lavoro e stanno in .gitignore:
la ricostruzione si fa rilanciando questo script, che e' deterministico
(verificato due volte, marker riprodotti entro pochi millimetri).
"""

import bpy
import os
import io
import time
import contextlib

def _radice():
    """La radice del progetto, DEDOTTA invece che cablata.

    ⚠️ Era scritta a mano col percorso di una macchina sola
    (`C:/Users/adriano.pace/Downloads/LOCAL/arcanium/`), e sul secondo PC lo
    script moriva alla prima riga — proprio il caso per cui il passaggio di
    consegne dice che il rig si RICOSTRUISCE lanciando questo file.

    Lo script si esegue con `exec(compile(open(P)...))`, che NON definisce
    `__file__`: quindi si prova prima `__file__` (quando lo si lancia con
    `blender --python`), poi la `P` che la docstring dice di impostare, e solo
    da ultimo i percorsi noti.
    """
    fuori = []
    for cand in (globals().get("__file__"), globals().get("P")):
        if cand:
            fuori.append(os.path.abspath(
                os.path.join(os.path.dirname(str(cand)), "..", "..")).replace("\\", "/") + "/")
    fuori += ["C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/",
              "C:/Users/adriano.pace/Downloads/LOCAL/arcanium/"]
    for r in fuori:
        if os.path.isdir(r + "assets"):
            return r
    raise SystemExit("radice del progetto non trovata; provati: %s" % fuori)


RADICE = _radice()
DIR_SYLVORN = RADICE + "assets/characters/enemies/consumati_sylvorn/"
RIG_DONATORE = RADICE + "assets/characters/enemies/consumato_rigged.glb"
## Le SORGENTI dei corpi (FBX quad, texture incorporata) stanno qui dentro: la
## cartella ha un `.gdignore`, quindi e' versionata ma Godot non la importa. In
## Godot entra solo il `<nome>_rigged.glb` che esce da `esporta_glb`.
DIR_SORGENTI = DIR_SYLVORN + "sorgenti/"


def sorgente(nome):
    """Il file da cui si monta un corpo: `sorgenti/<nome>.fbx` (lo standard dal
    2026-09-30), altrimenti il vecchio `<nome>.glb` (i corpi Meshy)."""
    for p in (DIR_SORGENTI + nome + ".fbx", DIR_SYLVORN + nome + ".glb"):
        if os.path.exists(p):
            return p
    raise FileNotFoundError("nessuna sorgente per %s in %s o %s" % (nome, DIR_SORGENTI, DIR_SYLVORN))


def importa_file(percorso):
    """GLB o FBX, secondo l'estensione. L'FBX e' quello che conserva i QUAD."""
    if percorso.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=percorso, use_image_search=True)
    else:
        bpy.ops.import_scene.gltf(filepath=percorso)


# ═══════════════════════════════════════════════════════════════════════════
# Contesto: gli operatori Smart di ARP vogliono un'area VIEW_3D vera
# ═══════════════════════════════════════════════════════════════════════════
# Eseguiti dal ponte MCP falliscono con `'NoneType' object has no attribute
# 'spaces'` oppure `poll() failed` — e ⚠️ IL PRIMO TENTATIVO LASCIA COMUNQUE
# `body_temp` IN SCENA e tutto il resto nascosto. Dopo un fallimento si ricarica
# il blend, non si prosegue sullo stato sporco.

def _ctx():
    win = next(w for w in bpy.context.window_manager.windows)
    area = next(a for a in win.screen.areas if a.type == 'VIEW_3D')
    region = next(r for r in area.regions if r.type == 'WINDOW')
    return dict(window=win, area=area, region=region,
                space_data=area.spaces.active, screen=win.screen)


def _zitto(fn, *a, **k):
    """Gli operatori ARP stampano migliaia di righe: qui interessa solo l'esito."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        out = fn(*a, **k)
    return out, buf.getvalue().splitlines()


# ═══════════════════════════════════════════════════════════════════════════
# 1. Preparazione della mesh
# ═══════════════════════════════════════════════════════════════════════════

def pulisci(ob):
    """Salda le cuciture e butta le normali custom.

    Le mesh generate arrivano coi vertici SPEZZATI sulle cuciture UV: sul Fante
    meta' dei 40.958 vertici erano doppioni (scesi a 20.588). Saldare senza poi
    ripulire le normali e' peggio che non saldare — i loop sopravvissuti restano
    con normali incoerenti e la superficie si copre di un brulichio fine che
    sembra un difetto della mesh e non lo e' (docs/05_RIG_CANONICO.md §3).
    """
    import bmesh
    prima = len(ob.data.vertices)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bmesh.update_edit_mesh(ob.data)
    bpy.ops.object.mode_set(mode='OBJECT')
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception:
        pass
    bpy.ops.object.shade_smooth()
    return prima, len(ob.data.vertices)


def battezza_texture(img, nome="Baked_BaseColor"):
    """Il nome con cui la texture esce nel GLB, e quindi il file che Godot estrae.

    ⚠️ Il NOME non basta: se l'immagine ha un percorso su disco (le texture
    degli FBX), l'esportatore glTF la chiama come il FILE — `tripo_image_<uuid>
    _0_0.jpg` — e Godot estrae una texture nuova accanto al GLB invece di
    riusare `<corpo>_rigged_Baked_BaseColor.jpg` (2026-09-30). Si incorpora
    l'immagine e le si da' anche il percorso col nome giusto.
    """
    if not img.packed_file:
        img.pack()
    est = os.path.splitext(img.filepath_raw or "")[1] or ".jpg"
    img.filepath_raw = "//" + nome + est
    img.name = nome


def prepara(nome, importa_rig_donatore=True, altezza=None, quad=False):
    """Scena pulita, mesh importata coi piedi a terra, rig Nephilite di confronto.

    `altezza` (metri): per i corpi di TRIPO, che arrivano normalizzati a un
    metro esatto (vedi mesh-misure-in-metri): si scala a questa altezza PRIMA
    di ogni misura. Il Soldato Scelto rifatto il 2026-09-14 si porta a 1,904 m,
    l'altezza in A-pose del corpo Meshy che sostituisce, cosi' presa dell'arco
    e faretra tarate sul vecchio hanno una chance di reggere. I corpi Meshy
    arrivano gia' in metri: `None`.

    La sorgente la trova `sorgente(nome)`: lo STANDARD e' l'FBX di Tripo in
    `sorgenti/`, che conserva la topologia quad esattamente come esce da P2
    (Mago: 12.227 quad + 4.008 triangoli voluti da Tripo, 16.235 facce).

    `quad=True` e' solo per i vecchi sorgenti GLB di Tripo: il GLB triangola (sul
    Mago 16.235 facce diventavano 28.462 triangoli) e `tris_convert_to_quads` ne
    ricompone solo una parte (11.893 quad + 4.672 triangoli, topologia diversa
    da quella di Tripo). Sull'FBX NON va usato: fonderebbe anche i triangoli
    che Tripo lascia apposta.
    """
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)

    if importa_rig_donatore:
        bpy.ops.import_scene.gltf(filepath=RIG_DONATORE)

    pre = set(o.name for o in bpy.data.objects)
    pre_img = set(i.name for i in bpy.data.images)
    src = sorgente(nome)
    print("%s: sorgente %s" % (nome, src))
    importa_file(src)
    me = [o for o in bpy.data.objects if o.name not in pre and o.type == 'MESH'][0]
    me.name = "CorpoSylvorn"

    # ⚠️ Le mesh Sylvorn arrivano CENTRATE SULL'ORIGINE (piedi a -0.95), non
    # appoggiate: vanno alzate prima di qualunque misura.
    co = [me.matrix_world @ v.co for v in me.data.vertices]
    if altezza:
        k = altezza / (max(p.z for p in co) - min(p.z for p in co))
        me.scale *= k
        bpy.context.view_layer.update()
        co = [me.matrix_world @ v.co for v in me.data.vertices]
        print("%s: scalato x%.3f a %.3f m" % (nome, k, max(p.z for p in co) - min(p.z for p in co)))
    me.location.z -= min(p.z for p in co)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Le immagini di Tripo si chiamano `tripo_image_<uuid>_0_0`: Godot le
    # estrae accanto al GLB con quel nome. Si rinomina come il corpo Meshy,
    # cosi' i PNG estratti e i loro .import restano gli stessi.
    for img in bpy.data.images:
        if img.name not in pre_img and img.name.startswith("tripo_image"):
            battezza_texture(img)
            print("%s: immagine rinominata Baked_BaseColor (%dx%d)" % (nome, img.size[0], img.size[1]))

    prima, dopo = pulisci(me)
    if quad:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.tris_convert_to_quads(face_threshold=0.698, shape_threshold=0.698, uvs=True, seam=True)
        bpy.ops.object.mode_set(mode='OBJECT')
        q = sum(1 for f in me.data.polygons if len(f.vertices) == 4)
        print("%s: quad ricomposti, %d quad su %d facce" % (nome, q, len(me.data.polygons)))
    print("%s: %d -> %d vertici (%.0f%% erano cuciture), %d triangoli"
          % (nome, prima, dopo, 100 * (1 - dopo / prima), len(me.data.polygons)))
    return me


# ═══════════════════════════════════════════════════════════════════════════
# 2. La catena ARP
# ═══════════════════════════════════════════════════════════════════════════

def rigga(mesh_nome="CorpoSylvorn"):
    """Catena Smart completa. I parametri vanno messi PRIMA del passo 1.

    ⚠️ `arp_smart_spine_count` CONTA ANCHE LA RADICE: **4**, non 3. Con 3 escono
    `root.x` + `spine_01` + `spine_02`, cioe' una spina in meno del Nephilite, e
    a `Spine_03` non arriva nessun peso — busto che sotto-ruota su ogni
    caricamento, difetto invisibile ai numeri del bind. Vedi docs/05 §4.
    """
    scn = bpy.context.scene
    me = bpy.data.objects[mesh_nome]

    scn.arp_smart_spine_count = 4
    scn.arp_smart_neck_count = 1
    scn.arp_fingers_to_detect = 5
    scn.arp_smart_depth = True          # senza, le dita AI non partono
    scn.arp_smart_type = 'BODY'

    ctx = _ctx()
    with bpy.context.temp_override(**ctx):
        for o in bpy.data.objects:
            o.hide_set(False)
        bpy.ops.object.select_all(action='DESELECT')
        me.select_set(True)
        bpy.context.view_layer.objects.active = me
        _zitto(bpy.ops.id.get_selected_objects)
    print("passo 1 ok | AI installato:", scn.arp_smart_AI_is_installed,
          "| motore dita:", getattr(scn, 'arp_smart_fingers_engine', '?'))
    if not scn.arp_smart_AI_is_installed:
        raise RuntimeError(
            "AI Tools di ARP non installati in Documents\\AutoRigPro\\AI. "
            "FERMARSI e chiederli: senza, guess_markers non parte.")

    # ⚠️ La PRIMA inferenza e' lentissima (minuti): carica cinque modelli da
    # 57 MB via eseguibili separati. Dalla seconda in poi sono secondi.
    t0 = time.time()
    with bpy.context.temp_override(**ctx):
        _zitto(bpy.ops.arp.guess_markers)
        _zitto(bpy.ops.arp.guess_fingers)
    mk = [o for o in bpy.data.objects if o.name.endswith("_loc")]
    print("marker: %d in %.0fs" % (len(mk), time.time() - t0))

    with bpy.context.temp_override(**ctx):
        _zitto(bpy.ops.id.go_detect)
        # ⚠️⚠️ match_to_rig NON e' opzionale e NON e' implicito in go_detect.
        # Senza, le ossa di riferimento sono giuste ma il rig deformante resta
        # nella posa del template: il bind "riesce" lo stesso, 0 vertici senza
        # peso, e la punta della mano finisce pesata su `foot.l`.
        _zitto(bpy.ops.arp.match_to_rig)

    rig = bpy.data.objects["rig"]
    with bpy.context.temp_override(**ctx):
        if bpy.context.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')

    # ⚠️ I corpi di TRIPO sono DECINE di gusci separati (piastre, cinghie,
    # cappuccio: 88 sul Soldato Scelto del 2026-09-14), non un guscio unico
    # come quelli Meshy. ARP con `arp_bind_split` li separa da solo, ma dal
    # ponte — con `selected_objects` fissato nel temp_override — lega solo il
    # primo pezzo e lascia gli altri 87 senza un gruppo, e il collaudo lo
    # legge come "piedi fuori dalla mesh". Si separano PRIMA, si legano tutti
    # insieme con la selezione esplicita, e si riuniscono dopo: i gruppi si
    # sommano per nome. Su un guscio solo la separazione non fa niente.
    pezzi = _separa_gusci(me)
    scn.arp_bind_split = False
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in pezzi:
        o.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    with bpy.context.temp_override(active_object=rig, selected_objects=pezzi + [rig],
                                   selected_editable_objects=pezzi + [rig], **ctx):
        _zitto(bpy.ops.arp.bind_to_rig)
    legati = sum(1 for o in pezzi if o.vertex_groups)
    print("bind su %d gusci, %d legati" % (len(pezzi), legati))
    me = _riunisci(pezzi, mesh_nome)
    print("bind ok | gruppi:", len(me.vertex_groups),
          "| orfani:", sum(1 for v in me.data.vertices if not v.groups))
    return collauda(me, rig)


def _separa_gusci(me):
    """La mesh in un oggetto per guscio (separate LOOSE), dal piu' grosso."""
    bpy.ops.object.select_all(action='DESELECT')
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='LOOSE')
    bpy.ops.object.mode_set(mode='OBJECT')
    pezzi = [o for o in bpy.context.selected_objects if o.type == 'MESH']
    pezzi.sort(key=lambda o: -len(o.data.vertices))
    print("gusci separati: %d (vertici: %s)" % (len(pezzi), [len(o.data.vertices) for o in pezzi[:5]]))
    return pezzi


def _riunisci(pezzi, nome):
    """I gusci di nuovo in un oggetto solo, col nome di prima. Il modificatore
    armatura resta quello del primo (gli altri sono uguali)."""
    bpy.ops.object.select_all(action='DESELECT')
    for o in pezzi:
        o.select_set(True)
    bpy.context.view_layer.objects.active = pezzi[0]
    bpy.ops.object.join()
    me = bpy.context.view_layer.objects.active
    me.name = nome
    me.data.name = nome
    return me


# ═══════════════════════════════════════════════════════════════════════════
# 3. I due collaudi — nessuno e' facoltativo
# ═══════════════════════════════════════════════════════════════════════════

def collauda(me, rig):
    """docs/05_RIG_CANONICO.md, "I due collaudi".

    Il secondo conta piu' del primo: il binding RIESCE COMUNQUE e non da'
    nessun segnale d'allarme — 0 vertici senza peso, nessun errore — anche
    quando i pesi sono completamente sbagliati.
    """
    esito = {}
    vmax = max(me.data.vertices, key=lambda v: v.co.x)
    top = sorted(vmax.groups, key=lambda x: -x.weight)[:2]
    esito["vertice_braccio"] = [(me.vertex_groups[x.group].name, round(x.weight, 3))
                                for x in top]
    fuori = []
    deform = [b for b in rig.data.bones if b.use_deform]
    for b in deform:
        p = rig.matrix_world @ b.head_local
        ok, loc, nor, _ = me.closest_point_on_mesh(me.matrix_world.inverted() @ p)
        if ok and -(me.matrix_world.inverted() @ p - loc).dot(nor) <= 0:
            fuori.append(b.name)
    esito["ossa_deformanti"] = len(deform)
    esito["ossa_fuori"] = fuori

    print("COLLAUDO 2 (vertice noto):", esito["vertice_braccio"],
          "  <- deve essere un DITO, non foot.l")
    print("COLLAUDO 1 (ossa dentro): %d deformanti, %d fuori %s"
          % (len(deform), len(fuori), fuori[:5]))
    # Riferimento misurato sul Fante il 2026-08-17: 68 deformanti, 0 fuori.
    return esito




# ═══════════════════════════════════════════════════════════════════════════
# 4. Il travaso ARP → Nephilite
# ═══════════════════════════════════════════════════════════════════════════
#
# Il nodo: ARP rigga il corpo nella sua A-POSE con la sua convenzione di ossa,
# mentre le clip di `anims/sword` vivono sulla convenzione Nephilite e sul rest
# della STANCE DI COMBATTIMENTO. Il rest non si tocca, quindi va posata la MESH.
#
# ⚠️⚠️ IL CANCELLO CHE AUTORIZZA TUTTO IL RESTO, misurato il 2026-08-20 sulle
# dieci clip `sword`: le tracce di POSIZIONE stanno solo su `Root` e `Hips`.
# Da `rig-e-skinning.md` §2 discende che:
#   - le ROTAZIONI di rest sono INTOCCABILI (cambiarne una sposta ogni clip);
#   - le POSIZIONI di rest sono LIBERE, cioe' le proporzioni del Fante
#     (gamba +14.9%, avambraccio +36%) si possono tenere senza toccare le clip.
# Se un giorno una clip nuova portasse tracce di posizione su altre ossa, questa
# costruzione non vale piu': ri-misurare PRIMA di rilanciare.
#
# Ne esce `FanteRig`: nomi e gerarchia Nephilite (79 ossa), rotazioni di rest
# IDENTICHE al Nephilite, lunghezze del Fante. E' esattamente cio' che
# `docs/05_RIG_CANONICO.md` chiama «una sola convenzione di ossa; le proporzioni
# seguono il corpo».

# I pesi: ogni osso Nephilite raccoglie uno o piu' gruppi ARP (docs/05 §4-bis).
# ⚠️ I twist/stretch NON si buttano: si SOMMANO al genitore, o l'avambraccio
# perde meta' della sua pelle.
def _mappa_pesi():
    m = {"Hips": ["root.x"], "Spine_01": ["spine_01.x"], "Spine_02": ["spine_02.x"],
         "Spine_03": ["spine_03.x"], "Neck": ["neck.x"], "Head": ["head.x"]}
    for a, N in (("l", "L"), ("r", "R")):
        m["Clavicle_%s" % N] = ["shoulder.%s" % a]
        m["Shoulder_%s" % N] = ["arm_stretch.%s" % a, "c_arm_twist_offset.%s" % a]
        m["Elbow_%s" % N] = ["forearm_stretch.%s" % a, "forearm_twist.%s" % a]
        # ⚠️ I `c_*1_base` di ARP (i METACARPI, le ossa del palmo) NON stanno
        # qui: li divide `_dividi_metacarpi` fra la mano e il dito, lungo l'osso.
        m["Hand_%s" % N] = ["hand.%s" % a]
        m["Thumb_01_%s" % N] = ["thumb1.%s" % a]
        m["Thumb_02_%s" % N] = ["c_thumb2.%s" % a]
        m["Thumb_03_%s" % N] = ["c_thumb3.%s" % a]
        m["IndexFinger_01_%s" % N] = ["index1.%s" % a]
        m["IndexFinger_02_%s" % N] = ["c_index2.%s" % a]
        m["IndexFinger_03_%s" % N] = ["c_index3.%s" % a]
        # ⚠️ Il Nephilite ha la mano a MITTEN: medio, anulare e mignolo di ARP
        # collassano in una sola catena `Finger_*`. Perdita accettabile, le armi
        # si attaccano a `Prop_Attachment_R` e non alle dita.
        m["Finger_01_%s" % N] = ["middle1.%s" % a, "ring1.%s" % a, "pinky1.%s" % a]
        m["Finger_02_%s" % N] = ["c_middle2.%s" % a, "c_ring2.%s" % a, "c_pinky2.%s" % a]
        m["Finger_03_%s" % N] = ["c_middle3.%s" % a, "c_ring3.%s" % a, "c_pinky3.%s" % a]
        m["UpperLeg_%s" % N] = ["thigh_stretch.%s" % a, "thigh_twist.%s" % a]
        m["LowerLeg_%s" % N] = ["leg_stretch.%s" % a, "leg_twist.%s" % a]
        m["Ankle_%s" % N] = ["foot.%s" % a]
        m["Ball_%s" % N] = ["toes_01.%s" % a]
    return m


# I GIUNTI: quale osso ARP ha la TESTA sul giunto di quell'osso Nephilite.
# ⚠️ Non e' l'osso omonimo della mappa dei pesi. ARP spezza omero e femore in
# DUE ossa deformanti (`c_arm_twist_offset` prossimale + `arm_stretch` distale):
# la spalla e' la testa del twist, il gomito la testa di `forearm_stretch`.
# Verificato: c_arm_twist_offset.head -> arm_stretch.head = 0.1402 = meta' omero.
def _mappa_giunti():
    g = {"Hips": "root.x", "Spine_01": "spine_01.x", "Spine_02": "spine_02.x",
         "Spine_03": "spine_03.x", "Neck": "neck.x", "Head": "head.x"}
    for a, N in (("l", "L"), ("r", "R")):
        g["Clavicle_%s" % N] = "shoulder.%s" % a
        g["Shoulder_%s" % N] = "c_arm_twist_offset.%s" % a   # <- la spalla vera
        g["Elbow_%s" % N] = "forearm_stretch.%s" % a         # <- il gomito vero
        g["Hand_%s" % N] = "hand.%s" % a
        g["Thumb_01_%s" % N] = "thumb1.%s" % a
        g["Thumb_02_%s" % N] = "c_thumb2.%s" % a
        g["Thumb_03_%s" % N] = "c_thumb3.%s" % a
        g["IndexFinger_01_%s" % N] = "index1.%s" % a
        g["IndexFinger_02_%s" % N] = "c_index2.%s" % a
        g["IndexFinger_03_%s" % N] = "c_index3.%s" % a
        # La muffola (medio + anulare + mignolo) ruota attorno al CENTRO delle tre
        # nocche, non a quella del medio: attorno al medio il mignolo, lontano
        # dall'asse, sporgeva dal bordo della mano nell'idle (2026-09-30).
        g["Finger_01_%s" % N] = ("middle1.%s" % a, "ring1.%s" % a, "pinky1.%s" % a)
        g["Finger_02_%s" % N] = ("c_middle2.%s" % a, "c_ring2.%s" % a, "c_pinky2.%s" % a)
        g["Finger_03_%s" % N] = ("c_middle3.%s" % a, "c_ring3.%s" % a, "c_pinky3.%s" % a)
        g["UpperLeg_%s" % N] = "thigh_twist.%s" % a          # <- l'anca vera
        g["LowerLeg_%s" % N] = "leg_stretch.%s" % a          # <- il ginocchio vero
        g["Ankle_%s" % N] = "foot.%s" % a
        g["Ball_%s" % N] = "toes_01.%s" % a
    return g


def _ordine_topologico(arm):
    fuori = []
    def scendi(b):
        fuori.append(b)
        for c in b.children:
            scendi(c)
    for b in arm.data.bones:
        if b.parent is None:
            scendi(b)
    return fuori


## I METACARPI di ARP, e a quale dito passano verso la nocca.
METACARPI = {"index": "IndexFinger_01", "middle": "Finger_01", "ring": "Finger_01", "pinky": "Finger_01"}
## Da che frazione dell'osso (0 = polso, 1 = nocca) il peso comincia a passare
## al dito, PER DITO. Sotto resta tutto alla mano.
## ⚠️ Anulare e mignolo passano solo a ridosso della nocca. La muffola ruota
## attorno al centro delle tre nocche, e la nocca del mignolo sta piu' indietro
## e piu' in basso di quel centro: un metacarpo che segue la muffola gira
## attorno a un perno sbagliato, e chiudendo le dita il bordo del palmo
## sporgeva verso l'esterno (visto dall'utente nell'idle il 2026-09-30, con
## 0,4 per tutti).
METACARPO_DA = {"index": 0.4, "middle": 0.4, "ring": 0.7, "pinky": 0.85}


def _dividi_metacarpi(me, arp):
    """I metacarpi di ARP fra MANO e DITO, secondo dove sta il vertice lungo l'osso.

    Il Nephilite non ha ossa del palmo. Due soluzioni sbagliate, entrambe viste:
      * metacarpo tutto alla prima falange (fino al 2026-09-30): il palmo
        ruotava con le dita, e nell'idle — mano chiusa sull'impugnatura — il
        dorso si GONFIAVA e pollice e indice si staccavano dal resto (Mago,
        Fante, Soldato Scelto: visto dall'utente in Cascadeur);
      * metacarpo tutto alla mano: anulare e mignolo ruotano attorno alla nocca
        del MEDIO (la mano a muffola), e la loro base si STIRAVA come un filo.
    In mezzo: vicino al polso mano, verso la nocca sfuma al dito.
    Restituisce {nome_nephilite: {vidx: peso}} da sommare agli altri.
    """
    mw = me.matrix_world
    out = {}
    for a, N in (("l", "L"), ("r", "R")):
        for dito, neph in METACARPI.items():
            nome = "c_%s1_base.%s" % (dito, a)
            g = me.vertex_groups.get(nome)
            b = arp.data.bones.get(nome) if arp is not None else None
            if g is None or b is None:
                continue
            h = arp.matrix_world @ b.head_local
            t = arp.matrix_world @ b.tail_local
            asse = t - h
            L2 = max(asse.length_squared, 1e-9)
            mano = out.setdefault("Hand_%s" % N, {})
            fin = out.setdefault("%s_%s" % (neph, N), {})
            for v in me.data.vertices:
                for el in v.groups:
                    if el.group != g.index or el.weight <= 0.0:
                        continue
                    k = max(0.0, min(1.0, ((mw @ v.co) - h).dot(asse) / L2))
                    da = METACARPO_DA[dito]
                    f = max(0.0, min(1.0, (k - da) / (1.0 - da)))
                    f = f * f * (3.0 - 2.0 * f)
                    mano[v.index] = mano.get(v.index, 0.0) + el.weight * (1.0 - f)
                    fin[v.index] = fin.get(v.index, 0.0) + el.weight * f
    return out


def rinomina_pesi(me):
    """Da 73 gruppi ARP ai 79 nomi Nephilite, SOMMANDO i twist nel genitore.

    Il totale per vertice non cambia (i gruppi sommati sono disgiunti), quindi
    non serve rinormalizzare: si sposta solo l'etichetta.
    """
    M = _mappa_pesi()
    pesi = {}                                  # nome_neph -> {vidx: peso}
    for neph, sorgenti in M.items():
        acc = {}
        for s in sorgenti:
            g = me.vertex_groups.get(s)
            if g is None:
                continue
            gi = g.index
            for v in me.data.vertices:
                for el in v.groups:
                    if el.group == gi and el.weight > 0.0:
                        acc[v.index] = acc.get(v.index, 0.0) + el.weight
        if acc:
            pesi[neph] = acc
    for neph, acc in _dividi_metacarpi(me, bpy.data.objects.get("rig")).items():
        dst = pesi.setdefault(neph, {})
        for vi, w in acc.items():
            dst[vi] = dst.get(vi, 0.0) + w
    for g in list(me.vertex_groups):
        me.vertex_groups.remove(g)
    for neph, acc in pesi.items():
        g = me.vertex_groups.new(name=neph)
        for vi, w in acc.items():
            g.add([vi], min(w, 1.0), 'REPLACE')
    orfani = sum(1 for v in me.data.vertices if not v.groups)
    print("pesi rinominati: %d gruppi Nephilite, %d vertici orfani" % (len(pesi), orfani))
    return pesi


def chiudi_orfani(me):
    """Ogni vertice senza peso prende i pesi del vicino pesato piu' prossimo.

    ⚠️ VA FATTO PRIMA DEL BAKE, e non e' un dettaglio estetico. Un vertice
    senza peso non si muove: l'esportatore glTF lo appende a un `neutral_bone`
    piantato nell'origine, e mentre il corpo affonda quel vertice resta dov'e'
    e si stira in un'ASTA sottile lunga tutto il personaggio. Misurato sul
    Fante: 84 orfani su 20.588 -- 54 sugli stinchi, 21 sulla testa, 9 alle
    caviglie -- e in gioco si vedeva una lancia spuntare dall'elmo.
    Invisibile a riposo, ovvio appena parte una clip (skill §3).

    ⚠️ ORFANO NON VUOL DIRE SOLO "SENZA GRUPPI". Un vertice col gruppo ma a peso
    quasi nullo (ARP ne ha lasciati due sul mento del Mago, 6,6e-05 su `Head`) e'
    orfano uguale: al bake nella stance resta nell'A-pose, 20 cm piu' in alto
    del resto del mento, e diventa una SPINA che sale davanti alla bocca — gia'
    a riposo (visto dall'utente il 2026-09-30: «il mento tira verso l'alto»).
    Qui conta la SOMMA dei pesi, sotto `PESO_MINIMO` il vertice si richiude.
    """
    from mathutils.kdtree import KDTree
    PESO_MINIMO = 0.01

    def peso(v):
        return sum(el.weight for el in v.groups)

    orf = [v for v in me.data.vertices if peso(v) < PESO_MINIMO]
    if not orf:
        print("orfani: nessuno")
        return 0
    pesati = [v for v in me.data.vertices if peso(v) >= PESO_MINIMO]
    kd = KDTree(len(pesati))
    for i, v in enumerate(pesati):
        kd.insert(v.co, i)
    kd.balance()
    for v in orf:
        for el in list(v.groups):
            me.vertex_groups[el.group].remove([v.index])
        _p, i, _d = kd.find(v.co)
        for el in pesati[i].groups:
            me.vertex_groups[el.group].add([v.index], el.weight, 'REPLACE')
    resta = sum(1 for v in me.data.vertices if peso(v) < PESO_MINIMO)
    print("orfani chiusi: %d -> %d" % (len(orf), resta))
    return len(orf)


def _giunti_fante(arp):
    """I giunti del Fante in A-pose, in spazio MONDO, dal rig ARP."""
    G = _mappa_giunti()
    J = {}
    for neph, n_arp in G.items():
        nomi = n_arp if isinstance(n_arp, tuple) else (n_arp,)
        teste = [arp.matrix_world @ arp.data.bones[n].head_local for n in nomi if n in arp.data.bones]
        if teste:
            J[neph] = sum(teste, teste[0] * 0.0) / len(teste)
    return J


def _kabsch(da, a):
    """La rotazione che porta un fascio di direzioni su un altro (minimi quadrati).

    Serve dove un giunto ha piu' figli — bacino, mano — perche' li' la TORSIONE
    e' determinata e una rotazione ad arco minimo la butterebbe via.
    """
    import numpy as np
    from mathutils import Matrix
    A = np.array([[v.x, v.y, v.z] for v in da])
    B = np.array([[v.x, v.y, v.z] for v in a])
    U, _S, Vt = np.linalg.svd(A.T @ B)
    D = np.diag([1.0, 1.0, float(np.sign(np.linalg.det(Vt.T @ U.T)))])
    return Matrix((Vt.T @ D @ U.T).tolist()).to_quaternion()


def _direzioni(arm, J, nome_osso):
    """Le direzioni TESTA→TESTA DEL FIGLIO di un osso, sui soli figli mappati.

    ⚠️⚠️ NON si usa il vettore dell'osso (testa→coda). `NephiliteRig` arriva da
    glTF, che non ha lunghezze d'osso: Blender le inventa, e le code non puntano
    ai figli. Misurato: `Shoulder_L.tail` dista 0.4178 m dalla testa di
    `Elbow_L`, e `LowerLeg_L` e' lungo 4.5 cm. Chi si fida della coda ottiene
    zero catene e un rig identico al donatore — e' costato questa riscrittura
    (skill §6, «per mirare un arto usa testa dell'osso → testa del figlio»).
    """
    b = arm.data.bones[nome_osso]
    fuori = []
    for c in b.children:
        if c.name not in J:
            continue
        v = c.head_local - b.head_local
        if v.length > 1e-6:
            fuori.append((c.name, v))
    return fuori


def _scale_per_osso(nep, J, ordine):
    """Quanto e' cresciuto il Fante attorno a ogni giunto, dai segmenti misurati.

    Serve agli ossi NON mappati (attacchi, mantello, falde): non hanno un giunto
    ARP da cui prendere la misura, quindi seguono la crescita del loro giunto.
    """
    s = {}
    for b in ordine:
        rap = []
        if b.name in J:
            for nome_c, v in _direzioni(nep, J, b.name):
                rap.append((J[nome_c] - J[b.name]).length / v.length)
        if rap:
            s[b.name] = sum(rap) / len(rap)
        else:
            s[b.name] = s.get(b.parent.name, 1.0) if b.parent else 1.0
    return s


def costruisci_fante_rig(nome_arp="rig", nome_nep="NephiliteRig", nome_out="FanteRig"):
    """`FanteRig`: gerarchia e ROTAZIONI di rest del Nephilite, GIUNTI del Fante.

    Le rotazioni locali di rest restano identiche bit per bit — sono l'unica
    cosa che le clip vedono. Cambiano solo le distanze fra i giunti, che le
    clip non guardano perche' le loro tracce di posizione stanno solo su `Root`
    e `Hips`.

    ⚠️ La LUNGHEZZA degli ossi resta quella del Nephilite ed e' voluto: su un
    rig glTF non significa niente (glTF non ha lunghezze), non entra nel rest
    esportato, e cambiarla cambierebbe la rotazione locale, che e' intoccabile.
    Cio' che porta le proporzioni sono le TESTE.
    """
    from mathutils import Vector
    arp = bpy.data.objects[nome_arp]
    nep = bpy.data.objects[nome_nep]
    J = _giunti_fante(arp)
    ordine = _ordine_topologico(nep)
    s = _scale_per_osso(nep, J, ordine)

    testa = {}
    for b in ordine:
        p = b.parent
        if p is None:
            testa[b.name] = (nep.matrix_world @ b.head_local).copy()
            continue
        base = (nep.matrix_world @ b.head_local) - (nep.matrix_world @ p.head_local)
        if base.length <= 1e-9:
            testa[b.name] = testa[p.name].copy()
            continue
        if b.name in J and p.name in J:
            L = (J[b.name] - J[p.name]).length      # misurato sul Fante
        else:
            L = base.length * s[p.name]             # segue la crescita del giunto
        testa[b.name] = testa[p.name] + base.normalized() * L

    # ⚠️ I piedi vanno rimessi a terra: con la gamba +14.9% il Fante costruito
    # dall'anca del Nephilite sprofonda di quella differenza. Si alza tutto
    # TRANNE `Root`, che e' l'osso di root motion e deve restare a terra.
    piedi = ("Ball_L", "Ball_R", "Toes_L", "Toes_R", "Ankle_L", "Ankle_R")
    dz = (min((nep.matrix_world @ nep.data.bones[n].head_local).z for n in piedi)
          - min(testa[n].z for n in piedi))
    for n in testa:
        if n != "Root":
            testa[n] += Vector((0, 0, dz))
    print("piedi rimessi a terra: dz = %+.4f m" % dz)

    dati = bpy.data.armatures.new(nome_out)
    ob = bpy.data.objects.new(nome_out, dati)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = nep.matrix_world.copy()
    inv = ob.matrix_world.inverted()
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    for b in ordine:
        eb = dati.edit_bones.new(b.name)
        vec = nep.matrix_world.to_3x3() @ (b.tail_local - b.head_local)
        eb.head = inv @ testa[b.name]
        eb.tail = inv @ (testa[b.name] + vec)       # stesso vettore = stessa rotazione
        eb.roll = 0.0
    for b in ordine:
        eb = dati.edit_bones[b.name]
        if b.parent is not None:
            eb.parent = dati.edit_bones[b.parent.name]
            eb.use_connect = False                  # le teste non stanno sulle code
        eb.align_roll(nep.matrix_world.to_3x3() @ b.matrix_local.to_3x3() @ Vector((0, 0, 1)))
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in ordine:
        ob.data.bones[b.name].use_deform = nep.data.bones[b.name].use_deform
    return ob


## Le falangi che nel puppet si piegano SOLO attorno alla riga delle nocche.
DITA_A_CARDINE = ("IndexFinger_01", "IndexFinger_02", "IndexFinger_03",
                  "Finger_01", "Finger_02", "Finger_03")


## Il POLLICE non si riorienta affatto: resta com'e' modellato rispetto al
## palmo. Portato sulla direzione del pollice del Nephilite (rotazione piu'
## corta, 29° di torsione) si piegava verso l'interno (visto dall'utente il
## 2026-09-30); con le teste allineate da `allinea_mano` non serve.
DITA_COME_MODELLATE = ("Thumb_01", "Thumb_02", "Thumb_03")


def _cardine(k, u, a):
    """La rotazione attorno all'asse `k` che porta `u` il piu' vicino possibile ad `a`.

    ⚠️ Perche' non la rotazione piu' corta (`rotation_difference`): quella
    sceglie da se' la torsione attorno al dito, e sul Mago (2026-09-30) la
    cottura A-pose → stance girava la muffola di 57° con 14° di TORSIONE, e
    l'indice di 34° con 14°. Il cardine delle clip non cadeva piu' sulla riga
    delle nocche: gia' nell'idle (che per le dita E' il rest del Nephilite) il
    mignolo si alzava e sporgeva, e l'indice si allontanava dal medio (visto
    dall'utente in Cascadeur). Un dito vero si piega attorno alle nocche: la
    cottura fa lo stesso.

    Il dito piegato cosi' resta di lato rispetto all'osso del Nephilite, che ha
    l'indice divaricato dalla muffola di 28° dove il Mago ne ha 12: se le ossa
    restassero dove le mette il Nephilite, ogni falange non combacerebbe con
    la successiva e ogni articolazione farebbe un NODO (dita a salsicciotto,
    visto il 2026-09-30). Per questo `allinea_mano` porta le teste delle ossa
    della mano sulle nostre articolazioni. E chiudere il residuo con la
    rotazione piu' corta non serve: ridava 22° di torsione e il difetto di
    partenza.
    """
    from mathutils import Quaternion
    import math
    pu = (u - k * u.dot(k))
    pa = (a - k * a.dot(k))
    if pu.length < 1e-6 or pa.length < 1e-6:
        return u.rotation_difference(a)
    pu.normalize()
    pa.normalize()
    return Quaternion(k, math.atan2(k.dot(pu.cross(pa)), pu.dot(pa)))


def allinea_mano(fante, puppet):
    """Le TESTE delle ossa della mano del FanteRig sulle nostre articolazioni.

    Dopo la cottura ogni articolazione della mesh finisce in
    `testa del genitore + Q⁻¹ · (giunto - giunto del genitore)`, dove Q e' la
    rotazione che porta l'osso del FanteRig su quello del puppet. Le teste si
    mettono li', cosi' ossa e dita combaciano. Le ROTAZIONI di rest non si
    toccano (le clip vedono solo quelle); le teste delle dita le clip non le
    leggono, perche' le loro tracce di posizione stanno solo su `Root` e
    `Hips`. Gli attacchi (`Prop_Attachment`...) conservano la loro distanza
    dal genitore.
    """
    Rf = lambda b: (fante.matrix_world @ fante.data.bones[b].matrix_local).to_quaternion()
    Rp = lambda b: (puppet.matrix_world @ puppet.data.bones[b].matrix_local).to_quaternion()
    Hp = lambda b: puppet.matrix_world @ puppet.data.bones[b].head_local
    nuove = {}
    for N in ("L", "R"):
        mano = fante.data.bones.get("Hand_%s" % N)
        if mano is None:
            continue
        nuove[mano.name] = fante.matrix_world @ mano.head_local
        coda = list(mano.children)
        while coda:
            b = coda.pop(0)
            p = b.parent.name
            Q = Rp(p) @ Rf(p).inverted()
            nuove[b.name] = nuove[p] + Q.inverted() @ (Hp(b.name) - Hp(p))
            coda.extend(b.children)
    inv = fante.matrix_world.inverted()
    spost = 0.0
    bpy.context.view_layer.objects.active = fante
    bpy.ops.object.mode_set(mode='EDIT')
    for nome, h in nuove.items():
        eb = fante.data.edit_bones[nome]
        d = inv @ h - eb.head
        spost = max(spost, d.length)
        roll = eb.roll
        eb.head += d
        eb.tail += d
        eb.roll = roll
    bpy.ops.object.mode_set(mode='OBJECT')
    print("mani allineate: %d ossa, spostamento massimo %.4f m" % (len(nuove), spost))


def costruisci_puppet(fante, nome_arp="rig", nome_out="Puppet", mani="presa"):
    """Il puppet: stesso rig del Fante, piegato nell'A-POSE della mesh.

    Si costruisce PARTENDO dal FanteRig e ruotandolo: cosi' i roll arrivano dal
    Nephilite attraverso una rotazione, e tornare indietro sara' esatto e senza
    torsione inventata. Dove un giunto ha piu' figli (bacino, mano) la rotazione
    si ricava per minimi quadrati sul fascio di direzioni, non ad arco minimo:
    li' la torsione e' un dato, e buttarla darebbe un polso avvitato.
    """
    from mathutils import Vector, Quaternion
    arp = bpy.data.objects[nome_arp]
    J = _giunti_fante(arp)
    ordine = _ordine_topologico(fante)
    R3 = fante.matrix_world.to_3x3()

    # La riga delle nocche di ogni mano, dall'indice al mignolo: il CARDINE
    # attorno a cui le dita si piegano (vedi `_cardine`).
    nocche = {}
    for a_, N in (("l", "L"), ("r", "R")):
        i, m = arp.data.bones.get("index1.%s" % a_), arp.data.bones.get("pinky1.%s" % a_)
        if i is not None and m is not None:
            nocche[N] = (arp.matrix_world.to_3x3() @ (m.head_local - i.head_local)).normalized()

    Q, testa = {}, {}
    for b in ordine:
        p = b.parent
        Qp = Q[p.name] if p is not None else Quaternion()
        figli = _direzioni(fante, J, b.name)
        k = nocche.get(b.name[-1]) if b.name[:-2] in DITA_A_CARDINE else None
        if b.name[:-2] in DITA_COME_MODELLATE or (mani == "aperte" and b.name[:-2] in DITA_A_CARDINE):
            Q[b.name] = Qp.copy()                 # segue la mano, com'e' modellato
        elif b.name in J and len(figli) == 1 and k is not None:
            u = (Qp @ (R3 @ figli[0][1])).normalized()
            Q[b.name] = _cardine(k, u, (J[figli[0][0]] - J[b.name]).normalized()) @ Qp
        elif b.name in J and figli:
            da = [(Qp @ (R3 @ v)).normalized() for _n, v in figli]
            a = [(J[n] - J[b.name]).normalized() for n, _v in figli]
            R = da[0].rotation_difference(a[0]) if len(da) == 1 else _kabsch(da, a)
            Q[b.name] = R @ Qp
        else:
            Q[b.name] = Qp.copy()                 # nessun giunto: segue il genitore
        if b.name in J:
            testa[b.name] = J[b.name].copy()      # esatto sui giunti misurati
        elif p is None:
            testa[b.name] = (fante.matrix_world @ b.head_local).copy()
        else:
            off = R3 @ (b.head_local - p.head_local)
            testa[b.name] = testa[p.name] + (Q[p.name] @ off)

    dati = bpy.data.armatures.new(nome_out)
    ob = bpy.data.objects.new(nome_out, dati)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = fante.matrix_world.copy()
    inv = ob.matrix_world.inverted()
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    for b in ordine:
        eb = dati.edit_bones.new(b.name)
        vec = R3 @ (b.tail_local - b.head_local)
        eb.head = inv @ testa[b.name]
        eb.tail = inv @ (testa[b.name] + (Q[b.name] @ vec))
        eb.roll = 0.0
    for b in ordine:
        eb = dati.edit_bones[b.name]
        if b.parent is not None:
            eb.parent = dati.edit_bones[b.parent.name]
            eb.use_connect = False
        eb.align_roll(Q[b.name] @ (R3 @ b.matrix_local.to_3x3() @ Vector((0, 0, 1))))
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in ordine:
        ob.data.bones[b.name].use_deform = fante.data.bones[b.name].use_deform

    err = max((ob.matrix_world @ ob.data.bones[n].head_local - J[n]).length for n in J)
    print("puppet: scarto massimo dai giunti ARP = %.6f m" % err)
    return ob


def cuoci_nella_stance(me, puppet, fante):
    """Posa il puppet ESATTAMENTE sul rest del FanteRig e applica il modificatore.

    ⚠️ Non si assegna `pose_bone.matrix` (spazio mondo): con rest e target
    divergenti degenera in compensazioni assurde sulla traslazione. Si ricava il
    `matrix_basis` a mano, che e' esatto e non ha bisogno di aggiornamenti del
    view layer fra un osso e l'altro (skill §6).
    """
    for pb in puppet.pose.bones:
        b = pb.bone
        T = fante.data.bones[b.name].matrix_local
        if b.parent is None:
            pb.matrix_basis = b.matrix_local.inverted() @ T
        else:
            Tp = fante.data.bones[b.parent.name].matrix_local
            pb.matrix_basis = (Tp @ b.parent.matrix_local.inverted()
                               @ b.matrix_local).inverted() @ T
    bpy.context.view_layer.update()
    # CANCELLO: il puppet posato deve coincidere col rest del FanteRig.
    err = max((puppet.pose.bones[b.name].matrix.translation
               - fante.data.bones[b.name].matrix_local.translation).length
              for b in fante.data.bones)
    print("puppet posato: scarto massimo dal rest del FanteRig = %.6f m" % err)

    for m in list(me.modifiers):
        me.modifiers.remove(m)
    mod = me.modifiers.new("CuociStance", 'ARMATURE')
    mod.object = puppet
    bpy.ops.object.select_all(action='DESELECT')
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    bpy.ops.object.modifier_apply(modifier=mod.name)

    me.parent = fante
    me.matrix_parent_inverse = fante.matrix_world.inverted()
    m2 = me.modifiers.new("Armature", 'ARMATURE')
    m2.object = fante
    return me


def collauda_travaso(me, fante):
    """I due collaudi di docs/05, rifatti sul rig di destinazione.

    ⚠️ Il BVH si ricostruisce da zero: `closest_point_on_mesh` restituisce
    risultati STANTII dopo un re-bind, e ha gia' dichiarato 21 ossa fuori che
    erano dentro. Il segnale che era la sonda e non l'asset fu l'asimmetria.
    """
    import bmesh
    from mathutils.bvhtree import BVHTree
    esito = {}
    bm = bmesh.new()
    bm.from_mesh(me.data)
    bm.transform(me.matrix_world)
    bvh = BVHTree.FromBMesh(bm)
    deform = [b for b in fante.data.bones if b.use_deform]
    fuori = []
    for b in deform:
        p = fante.matrix_world @ b.head_local
        loc, nor, _i, _d = bvh.find_nearest(p)
        if loc is None or (p - loc).dot(nor) > 0:
            fuori.append(b.name)
    esito["deformanti"], esito["fuori"] = len(deform), fuori
    print("COLLAUDO 1 (ossa dentro): %d deformanti, %d fuori %s"
          % (len(deform), len(fuori), fuori[:8]))

    for etichetta, scegli in (("x-max", max), ("x-min", min)):
        v = scegli(me.data.vertices, key=lambda v: (me.matrix_world @ v.co).x)
        top = sorted(v.groups, key=lambda x: -x.weight)[:2]
        nomi = [(me.vertex_groups[x.group].name, round(x.weight, 3)) for x in top]
        esito["vertice_" + etichetta] = nomi
        print("COLLAUDO 2 (%s): %s   <- deve essere un DITO" % (etichetta, nomi))

    # Terzo, specifico di questi corpi: la pelle deve stare tutta pesata.
    orfani = sum(1 for v in me.data.vertices if not v.groups)
    esito["orfani"] = orfani
    print("vertici senza peso: %d" % orfani)
    return esito


def stacca_falde(me, fan, fascia=0.03):
    """Le falde devono pendere dal BACINO, non dal petto.

    ⚠️ Il difetto vero, e non era quello che sembrava. ARP pesa la corazza in un
    pezzo solo: `Spine_02` (il `Chest` dopo la rinomina) si prende TUTTA la
    piastra dal petto fino alle falde, che cosi' oscillano col busto invece che
    col bacino. Sul Fante erano 3.247 vertici, 2.306 dei quali sotto la vita.

    ⚠️⚠️ E per due volte l'ho attribuito alla COSCIA, sbagliando. La colpa era
    della sonda: misurando lo scarto baricentro-osso contro il VETTORE
    dell'osso, `UpperLeg` dava 12-14 %H. Ma sul rig Nephilite, che viene da
    glTF, il vettore dell'osso non segue l'arto. Rimisurato sull'asse vero
    (testa dell'osso -> testa del figlio) `UpperLeg` scende a **1.8-2.0 %H** e
    resta in piedi solo `Spine_02` a 10.1 %H. E' la terza volta in questo file
    che le code delle ossa glTF mentono: se misuri qualcosa contro un osso,
    usa testa->testa del figlio.

    Dove tagliare si CERCA, non si cabla: la vita e' la sezione piu' stretta
    della regione, la strozzatura fra pettorale e falde. Sul Fante viene
    z=1.06, cioe' 9.5 cm sopra l'anca; sugli altri cinque corpi verra' altrove.
    Attorno a quella quota si lascia una fascia sfumata, o la piastra si
    incerniera di netto proprio dove si vede.

    Le falde NON vanno sui `Loincloth_*`: verificato, nessuna clip li anima, e
    sono figli di `Hips`. Pesarli li' o su `Hips` da' lo stesso risultato con
    un'indirezione in piu'.
    """
    from mathutils import Vector
    BUSTO = ("Spine_01", "Spine_02", "Spine_03")
    idx = {g.name: g.index for g in me.vertex_groups}
    if "Hips" not in idx:
        me.vertex_groups.new(name="Hips")
        idx = {g.name: g.index for g in me.vertex_groups}
    nomi = {g.index: g.name for g in me.vertex_groups}
    reg = [(v, me.matrix_world @ v.co) for v in me.data.vertices
           if v.groups and nomi[max(v.groups, key=lambda x: x.weight).group] in BUSTO]
    if not reg:
        print("falde: nessuna regione di busto trovata")
        return 0.0

    # --- la strozzatura, cercata fra l'anca e 25 cm piu' su
    anca = (fan.matrix_world @ fan.data.bones["UpperLeg_L"].head_local).z
    passo, migliore = 0.02, None
    z = anca
    while z < anca + 0.25:
        fetta = [p for _v, p in reg if z <= p.z < z + passo]
        if len(fetta) > 8:
            largh = max(p.x for p in fetta) - min(p.x for p in fetta)
            if migliore is None or largh < migliore[0]:
                migliore = (largh, z + passo / 2)
        z += passo
    if migliore is None:
        print("falde: nessuna strozzatura trovata, non tocco niente")
        return 0.0
    vita = migliore[1]
    print("falde: vita alla sezione piu' stretta z=%.3f (largh %.3f), anca a %.3f"
          % (vita, migliore[0], anca))

    gh = me.vertex_groups[idx["Hips"]]
    spostati = 0
    for v, p in reg:
        q = (vita + fascia - p.z) / (2 * fascia)      # 0 sopra la fascia, 1 sotto
        q = max(0.0, min(1.0, q))
        if q <= 0.0:
            continue
        tot = 0.0
        for el in list(v.groups):
            n = nomi[el.group]
            if n in BUSTO:
                giu = el.weight * q
                tot += giu
                me.vertex_groups[el.group].add([v.index], el.weight - giu, 'REPLACE')
        if tot > 0.0:
            avuto = next((el.weight for el in v.groups if el.group == gh.index), 0.0)
            gh.add([v.index], avuto + tot, 'REPLACE')
            spostati += 1
    print("falde: %d vertici passati dal busto al bacino" % spostati)
    return vita


def affila_pesi(me, esponente=6.0):
    """L'acciaio non si piega: si ELEVANO i pesi a potenza e si rinormalizza.

    Ricetta da `game-animation-craft` §7bis. Nel mezzo di una piastra un osso
    domina gia', e l'esponente lo porta a ~1.0: quella zona diventa rigida. Sul
    giunto due ossa se lo contendono quasi alla pari, e li' la sfumatura
    sopravvive -- una fascia stretta che flette e TIENE INSIEME le piastre.
    Nessun taglio, nessun buco, una manopola sola.

    ⚠️ Va fatta DOPO il bake nella stance. La cottura A-pose -> stance e' una
    deformazione grossa e vuole pesi MORBIDI, o le piastre si creano pieghe
    mentre ci passano attraverso. A riposo pesi affilati e pesi morbidi danno
    la stessa identica posa, quindi affilarli dopo non introduce nessuna
    incoerenza fra mesh cotta e rest.

    ⚠️ E NON risolve le falde: quelle seguono la coscia perche' ci sono PESATE
    sopra, e affilare le incolla alla coscia piu' saldamente. Per staccarle
    servono i `Loincloth_*` e `Hips_Attachment`, che nel rig ci sono e che ARP
    non sa riempire.
    """
    dati = []
    for v in me.data.vertices:
        if not v.groups:
            continue
        w = [(el.group, el.weight ** esponente) for el in v.groups if el.weight > 0.0]
        s = sum(x[1] for x in w)
        if s <= 0.0:
            continue
        dati.append((v.index, [(g, x / s) for g, x in w]))
    for vi, w in dati:
        for g, x in w:
            me.vertex_groups[g].add([vi], x, 'REPLACE')
    dom = []
    for v in me.data.vertices:
        if v.groups:
            dom.append(max(el.weight for el in v.groups))
    dom.sort()
    rigidi = sum(1 for d in dom if d > 0.999)
    print("pesi affilati (esponente %.1f): dominanza mediana %.3f, %.0f%% dei vertici rigidi"
          % (esponente, dom[len(dom) // 2], 100.0 * rigidi / len(dom)))
    return dom


def mento_alla_testa(me, mento=(-0.20, 1.525), sotto_orecchio=(-0.08, 1.585), sfuma=0.02):
    """Il viso SOTTO l'osso `Head` va alla testa, non al collo.

    Trovato sul Mago rifatto con Tripo il 2026-09-28: l'osso `Head` parte
    all'altezza della nuca (z 1,60) e mento e mandibola stanno più in basso e
    più avanti, così i pesi li davano al `Neck` (fino al 100%). Girando la testa
    il mento restava col collo e il viso si strappava dalla guancia al mento.

    La regola è la LINEA DELLA MANDIBOLA nel profilo (y, z): una retta dal sotto
    del mento a sotto l'orecchio. Sopra va alla testa, sfumando in `sfuma`
    metri; sotto (la gola) resta al collo. Le quote sono quelle di un corpo alto
    ~1,9 m nella stance del FanteRig: rimisurarle se il corpo è diverso.
    """
    mw = me.matrix_world
    head = me.vertex_groups["Head"]
    pend = (sotto_orecchio[1] - mento[1]) / (sotto_orecchio[0] - mento[0])

    def liscio(t):
        t = max(0.0, min(1.0, t))
        return t * t * (3.0 - 2.0 * t)

    cambiati = 0
    for v in me.data.vertices:
        p = mw @ v.co
        if abs(p.x) > 0.085 or p.y > -0.06 or not (1.49 < p.z < 1.625):
            continue
        w = liscio((p.z - (mento[1] + (p.y - mento[0]) * pend)) / sfuma)
        if w <= 0.0:
            continue
        pesi = {me.vertex_groups[g.group].name: g.weight for g in v.groups}
        h = pesi.get("Head", 0.0)
        if h >= 0.999:
            continue
        for g in v.groups:
            if me.vertex_groups[g.group].name == "Head":
                g.weight = h + (1.0 - h) * w
            else:
                g.weight *= (1.0 - w)
        if "Head" not in pesi:
            head.add([v.index], w, 'REPLACE')
        cambiati += 1
    print("mento alla testa: %d vertici" % cambiati)
    return cambiati


def pesi_dalla_gabbia(me, arm, voxel=0.012, passaggi=3, fattore=0.5,
                      mani=("Hand_L", "Hand_R"), testa="Head"):
    """Gli STRATI di stoffa si muovono insieme: pesi presi da un involucro unico.

    I corpi di Tripo sono fatti di STRATI separati (il Mago: 35 gusci —
    manica, camicia, tunica, mantello, cintura) e ARP pesa ogni guscio per
    conto suo: due strati sovrapposti ricevono pesi un po' diversi, e nelle clip
    quello sotto BUCA quello sopra (camicia bianca che affiora dalla manica
    verde, mantello e cintura strappati nell'affondo: visto dall'utente il
    2026-09-28). Ne' la media dei pesi entro 3 cm ne' lo smooth locale bastano.

    La cura: un INVOLUCRO chiuso di tutto il corpo (voxel remesh, che fonde gli
    strati in una pelle), i pesi copiati sull'involucro e ammorbiditi lungo la
    SUA superficie, poi riportati su ogni vertice dal punto piu' vicino. Testa e
    mani restano fuori: i pesi li' sono gia' giusti e il voxel fonderebbe le dita.

    ⚠️ `voxel` e `passaggi` non vanno alzati a caso: con 2 cm e 10 passaggi
    l'involucro fondeva la manica pendente col fianco e la manica prendeva quote
    di busto — nell'affondo si tendeva a PUNTA fra braccio e fianco.
    """
    from mathutils.bvhtree import BVHTree
    from mathutils.interpolate import poly_3d_calc

    gab = me.copy()
    gab.data = me.data.copy()
    gab.name = "GabbiaPesi"
    bpy.context.scene.collection.objects.link(gab)
    for m in list(gab.modifiers):
        gab.modifiers.remove(m)
    for g in list(gab.vertex_groups):
        gab.vertex_groups.remove(g)
    gab.data.remesh_voxel_size = voxel
    gab.data.use_remesh_preserve_volume = False
    ctx = _ctx()
    for o in bpy.context.view_layer.objects:
        o.select_set(o == gab)
    bpy.context.view_layer.objects.active = gab
    fuori = dict(active_object=gab, object=gab, selected_objects=[gab], **ctx)
    with bpy.context.temp_override(**fuori):
        bpy.ops.object.voxel_remesh()
    for g in me.vertex_groups:
        gab.vertex_groups.new(name=g.name)
    dt = gab.modifiers.new("dt", 'DATA_TRANSFER')
    dt.object = me
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    dt.layers_vgroup_select_src = 'ALL'
    dt.layers_vgroup_select_dst = 'NAME'
    with bpy.context.temp_override(**fuori):
        bpy.ops.object.modifier_apply(modifier="dt")
        bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
        if passaggi > 0:
            bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=fattore, repeat=passaggi, expand=0.0)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
        bpy.ops.object.mode_set(mode='OBJECT')

    gm = gab.data
    gw = gab.matrix_world
    mw = me.matrix_world
    bvh = BVHTree.FromPolygons([gw @ v.co for v in gm.vertices], [p.vertices[:] for p in gm.polygons])
    nomi = {g.index: g.name for g in gab.vertex_groups}
    gpesi = [{nomi[x.group]: x.weight for x in v.groups} for v in gm.vertices]
    mani = [arm.matrix_world @ arm.data.bones[b].head_local for b in mani]
    testa = arm.matrix_world @ arm.data.bones[testa].head_local
    cambiati = 0
    for v in me.data.vertices:
        p = mw @ v.co
        if any((p - m).length <= 0.13 for m in mani):
            continue
        if (p - testa).length < 0.16 and p.z > testa.z - 0.08:
            continue
        loc, _n, fi, _d = bvh.find_nearest(p)
        if fi is None:
            continue
        poly = gm.polygons[fi]
        bw = poly_3d_calc([gw @ gm.vertices[i].co for i in poly.vertices], loc)
        acc = {}
        for wi, vi in zip(bw, poly.vertices):
            for nome, x in gpesi[vi].items():
                acc[nome] = acc.get(nome, 0.0) + x * wi
        tot = sum(x for x in acc.values() if x > 0.01)
        if tot <= 0.0:
            continue
        for g in list(v.groups):
            me.vertex_groups[g.group].remove([v.index])
        for nome, x in acc.items():
            if x > 0.01:
                me.vertex_groups[nome].add([v.index], x / tot, 'REPLACE')
        cambiati += 1
    bpy.data.objects.remove(gab, do_unlink=True)
    print("pesi dalla gabbia (voxel %.3f, %d passaggi): %d vertici" % (voxel, passaggi, cambiati))
    return cambiati


def normalizza_pesi(me):
    """Ogni vertice a somma 1 sulle sue ossa.

    ⚠️ Un vertice coi pesi quasi a zero (6,6e-05 su `Head`, la punta del naso
    del Mago il 2026-09-30) passa tutti i collaudi — non e' "senza peso" — ma
    l'esportatore glTF lo scarta, lo appende a un `neutral_bone` e in gioco
    resta fermo mentre la testa si muove. Si vede solo contando le ossa dello
    skin (80 invece di 79). Rinormalizzare alla fine lo riporta sull'osso giusto.
    """
    tocchi = 0
    for v in me.data.vertices:
        tot = sum(g.weight for g in v.groups)
        if tot <= 0.0 or abs(tot - 1.0) < 1e-4:
            continue
        for g in v.groups:
            g.weight = g.weight / tot
        tocchi += 1
    print("pesi normalizzati: %d vertici" % tocchi)
    return tocchi


def spigoli_stirati(prima, dopo, soglia=3.0, minimo=0.005):
    """COLLAUDO del bake: uno spigolo che si allunga di `soglia` volte e' un
    vertice rimasto indietro.

    Il passaggio A-pose -> stance piega il corpo, non lo stira: gli spigoli
    restano quasi della loro lunghezza. Un vertice a peso ~0 invece resta
    nell'A-pose mentre i vicini si muovono, e i suoi spigoli diventano lunghi
    come una SPINA (il mento del Mago, 2026-09-30: da 1 cm a 20 cm). Stessa
    topologia sui due oggetti: `dopo` e' una copia di `prima`.
    """
    mw0, mw1 = prima.matrix_world, dopo.matrix_world
    v0, v1 = prima.data.vertices, dopo.data.vertices
    brutti = []
    for e in dopo.data.edges:
        a, b = e.vertices
        l0 = (mw0 @ v0[a].co - mw0 @ v0[b].co).length
        l1 = (mw1 @ v1[a].co - mw1 @ v1[b].co).length
        if l1 > minimo and l1 > soglia * max(l0, 1e-6):
            brutti.append((l1 / max(l0, 1e-6), a, b, l0, l1))
    brutti.sort(reverse=True)
    if brutti:
        r, a, b, l0, l1 = brutti[0]
        print("COLLAUDO BAKE: %d spigoli stirati oltre x%.0f — il peggiore v%d-v%d da %.3f a %.3f m"
              % (len(brutti), soglia, a, b, l0, l1))
    else:
        print("COLLAUDO BAKE: nessuno spigolo stirato (soglia x%.0f)" % soglia)
    return brutti


def ripara_stirati(src, me, puppet, fante, giri=3, passaggi=3):
    """Se il bake stira degli spigoli, si ammorbidiscono i pesi LI' e si ricuoce.

    Uno spigolo stirato ha i due capi su ossa troppo diverse (sul Mago: un pezzo
    di cintura pesato sulla coscia accanto a uno sulla schiena, 3 mm -> 10 cm).
    Si prendono i vertici stirati piu' un anello di vicini, si rimette la
    geometria in A-pose (e' una copia di `src`, stessa topologia), si media ogni
    peso con quelli dei vicini LUNGO LA MESH — non nello spazio: la gabbia
    spaziale fonde gli strati — e si rifa' il bake. Fino a `giri` volte.
    """
    import bmesh
    brutti = spigoli_stirati(src, me)
    for giro in range(giri):
        if not brutti:
            return 0
        bm = bmesh.new()
        bm.from_mesh(src.data)
        bm.verts.ensure_lookup_table()
        zona = set()
        for _r, a, b, _l0, _l1 in brutti:
            for i in (a, b):
                zona.add(i)
                zona.update(e.other_vert(bm.verts[i]).index for e in bm.verts[i].link_edges)
        vicini = {i: [e.other_vert(bm.verts[i]).index for e in bm.verts[i].link_edges] for i in zona}
        bm.free()
        nomi = {g.index: g.name for g in me.vertex_groups}
        pesi = {v.index: {nomi[el.group]: el.weight for el in v.groups} for v in me.data.vertices}
        for _p in range(passaggi):
            nuovi = {}
            for i in zona:
                acc = dict(pesi[i])
                for j in vicini[i]:
                    for n, w in pesi[j].items():
                        acc[n] = acc.get(n, 0.0) + w
                tot = sum(acc.values())
                nuovi[i] = {n: w / tot for n, w in acc.items() if w / tot > 0.005}
            pesi.update(nuovi)
        for i in zona:
            v = me.data.vertices[i]
            for el in list(v.groups):
                me.vertex_groups[el.group].remove([i])
            for n, w in pesi[i].items():
                me.vertex_groups[n].add([i], w, 'REPLACE')
        # geometria di nuovo in A-pose, e si ricuoce
        for m in list(me.modifiers):
            me.modifiers.remove(m)
        me.parent = None
        me.matrix_world = src.matrix_world.copy()
        for v, v0 in zip(me.data.vertices, src.data.vertices):
            v.co = v0.co
        cuoci_nella_stance(me, puppet, fante)
        prima = len(brutti)
        brutti = spigoli_stirati(src, me)
        print("riparazione %d: %d vertici ammorbiditi, spigoli stirati %d -> %d"
              % (giro + 1, len(zona), prima, len(brutti)))
    return len(brutti)


def gusci_rigidi(me, massimo=300):
    """Ogni guscio piccolo (fibbie, rivetti, placche) si muove RIGIDO.

    Un pezzo d'armatura piccolo a cavallo di un'articolazione prende pesi
    diversi da una parte e dall'altra, e nel cambio di posa si STIRA: sul
    Comandante (2026-10-02) le fibbie delle falde, a cavallo dell'anca, si
    allungavano fino a 3 cm (35 spigoli stirati che nessuna riparazione
    toglieva, uguali in tre giri di ARP). Qui ogni guscio con al massimo
    `massimo` vertici prende per tutti i vertici la MEDIA dei pesi del guscio.
    """
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me.data)
    bm.verts.ensure_lookup_table()
    seen, gusci = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        st, c = [v], []
        seen.add(v.index)
        while st:
            x = st.pop()
            c.append(x.index)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o.index not in seen:
                    seen.add(o.index)
                    st.append(o)
        gusci.append(c)
    bm.free()
    fatti = 0
    for c in gusci:
        if len(c) > massimo:
            continue
        somma = {}
        for vi in c:
            for el in me.data.vertices[vi].groups:
                somma[el.group] = somma.get(el.group, 0.0) + el.weight
        tot = sum(somma.values())
        if tot <= 0.0:
            continue
        for vi in c:
            for el in list(me.data.vertices[vi].groups):
                me.vertex_groups[el.group].remove([vi])
            for gi, w in somma.items():
                if w / tot > 0.001:
                    me.vertex_groups[gi].add([vi], w / tot, 'REPLACE')
        fatti += 1
    print("gusci rigidi: %d gusci fino a %d vertici" % (fatti, massimo))


def travasa(nome_mesh="CorpoSylvorn", affila=True, falde=True, gabbia=False, mani="presa",
            gusci_rigidi_fino=0):
    """Il §4 completo. NON tocca la mesh riggata da ARP: lavora su una copia.

    `affila=False` per i corpi SENZA armatura (tunica, pelle: il Mago Tripo del
    2026-09-28). `affila_pesi` e' fatto per le piastre d'acciaio dei corpi Meshy:
    su un corpo di stoffa in quad rendeva rigidi il 71% dei vertici, e il collo
    e il mento si strappavano nelle clip (visto dall'utente in gioco).

    `falde=False` per le vesti LUNGHE: `stacca_falde` taglia i pesi a meta' vita
    perche' i gonnellini d'armatura del Fante pendano dal bacino, ma sul Mago
    cintura e tunica cadono proprio sul taglio e nell'affondo si strappavano.

    `gabbia=True` per i corpi a STRATI (Tripo): vedi `pesi_dalla_gabbia`.

    `gusci_rigidi_fino=N`: i gusci con al massimo N vertici si muovono rigidi
    (`gusci_rigidi`), per le armature con fibbie e placche piccole.

    `mani="aperte"` per chi NON impugna niente (il Mago usa le mani): le dita
    restano come sono modellate. Con `"presa"` (default, i mob armati) si
    piegano fino al rest del Nephilite, che ha la destra CHIUSA
    sull'impugnatura; e nell'idle le dita stanno proprio nel rest, quindi il
    Mago teneva un'arma che non ha (visto dall'utente il 2026-09-30).
    """
    src = bpy.data.objects[nome_mesh]
    me = src.copy()
    me.data = src.data.copy()
    me.name = "FanteSylvorn"
    me.data.name = "FanteSylvorn"
    bpy.context.scene.collection.objects.link(me)
    for m in list(me.modifiers):
        me.modifiers.remove(m)
    me.parent = None
    me.matrix_world = src.matrix_world.copy()

    rinomina_pesi(me)
    chiudi_orfani(me)          # ⚠️ prima del bake, o restano indietro
    if gusci_rigidi_fino > 0:
        gusci_rigidi(me, gusci_rigidi_fino)
    fante = costruisci_fante_rig()
    puppet = costruisci_puppet(fante, mani=mani)
    allinea_mano(fante, puppet)
    cuoci_nella_stance(me, puppet, fante)
    ripara_stirati(src, me, puppet, fante)
    if falde:
        stacca_falde(me, fante)  # le falde pendono dal bacino, non dal petto
    if affila:
        affila_pesi(me)        # dopo il bake: l'acciaio non si piega
    if gusci_rigidi_fino > 0:
        gusci_rigidi(me, gusci_rigidi_fino)   # falde e affilatura ripesano per vertice
    mento_alla_testa(me)       # il viso sotto l'osso Head segue la testa
    if gabbia:
        # ⚠️ DOPO il bake. Provata prima (in A-pose, 2026-09-30): con le braccia
        # aperte la manica larga pende vicino all'avambraccio, la gabbia li
        # fondeva e abbassando le braccia la manica si squarciava (251 spigoli
        # stirati invece di 44).
        pesi_dalla_gabbia(me, fante)
    normalizza_pesi(me)
    return collauda_travaso(me, fante)


# ═══════════════════════════════════════════════════════════════════════════
# 4-bis. Le STOFFE simulate (docs/05 §4-quater, standard dal 2026-09-30)
# ═══════════════════════════════════════════════════════════════════════════

PREFISSO_STOFFA = "Stoffa"
ATTRIBUTO_MASCHERA = "cloth_weight"


## Le catene delle braccia e quanto lontano dall'osso un vertice puo' ancora
## seguirlo: (inizio della sfumatura, fine) in metri.
BRACCIA_PORTATA = {
    ("Clavicle", "Shoulder", "Elbow", "Hand"): (0.15, 0.25),
    ("Finger", "Thumb"): (0.06, 0.10),
}


def separa_maniche(ob, rig="FanteRig", nome="Stoffa3", busto=0.20, profondo=0.13, sotto=1.36,
                   attaccata=0.05, libera=0.08):
    """Le MANICHE LARGHE in una stoffa a se', appesa al braccio solo
    all'attaccatura.

    Sul Mago (Richiamo, 2026-10-28) maniche e mantello sono un pezzo solo di
    Tripo. Pesate sul fianco si stendevano dal polso all'anca a braccia alzate;
    pesate sul braccio sporgevano rigide di lato; e la maschera del mantello le
    teneva comunque ferme (`maschera_stoffa` blocca cio' che pesa sulle
    braccia). Qui si staccano: le facce del pezzo che stanno FUORI dal busto
    (oltre `busto` metri dall'asse), sotto le spalle e entro `profondo` dalla
    linea del braccio in profondita' (il mantello largo dietro la schiena no).

    Ogni vertice pesa tutto sull'osso del braccio piu' vicino (spalla, gomito,
    mano); la maschera `cloth_weight` lo tiene fermo entro `attaccata` metri
    dall'asse del braccio (il tubo della manica) e lo lascia libero oltre
    `libera` (la falda che pende): a braccia alzate la falda ricade da se'.
    Con 9-17 cm era ancorata meta' manica (541 punti su 1.066): a braccia
    alzate restava rigida in fuori, ali di gabbiano bianche (la fodera)."""
    import bmesh
    from mathutils.geometry import intersect_point_line
    ar = bpy.data.objects[rig]
    mw = ar.matrix_world
    mwo = ob.matrix_world
    ossa = {}
    for lato in "LR":
        catena = [mw @ ar.data.bones[n + "_" + lato].head_local for n in ("Shoulder", "Elbow", "Hand")]
        punta = "Finger_01_" + lato
        dita = mw @ ar.data.bones[punta].head_local if punta in ar.data.bones else catena[2]
        ossa[lato] = [("Shoulder_" + lato, catena[0], catena[1]), ("Elbow_" + lato, catena[1], catena[2]),
                      ("Hand_" + lato, catena[2], dita)]

    def vicino(p):
        meglio = None
        for segmenti in ossa.values():
            for n, a, b in segmenti:
                _q, t = intersect_point_line(p, a, b)
                t = min(max(t, 0.0), 1.0)
                q = a + (b - a) * t
                d = (p - q).length
                if meglio is None or d < meglio[1]:
                    meglio = (n, d, q)
        return meglio

    def e_manica(p):
        lato = "L" if p.x > 0 else "R"
        if abs(p.x) <= busto or p.z >= sotto:
            return False
        n, _d, q = vicino(p)
        return n.endswith("_" + lato) and abs(p.y - q.y) <= profondo

    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    scelte = [f for f in bm.faces if all(e_manica(mwo @ v.co) for v in f.verts)]
    ## Via le isole minuscole: frange del mantello prese per sbaglio.
    scelte_set = set(scelte)
    viste, tenute = set(), set()
    for f0 in scelte:
        if f0 in viste:
            continue
        pila, isola = [f0], []
        viste.add(f0)
        while pila:
            f = pila.pop()
            isola.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g in scelte_set and g not in viste:
                        viste.add(g)
                        pila.append(g)
        if len(isola) >= 60:
            tenute.update(i.index for i in isola)
    bm.free()
    me = ob.data
    for v in me.vertices:
        v.select = False
    for e in me.edges:
        e.select = False
    for p in me.polygons:
        p.select = p.index in tenute
        if p.select:
            for vi in p.vertices:
                me.vertices[vi].select = True
    for e in me.edges:
        e.select = all(me.vertices[vi].select for vi in e.vertices)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    prima = set(bpy.data.objects)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    nuovo = [o for o in bpy.data.objects if o not in prima][0]
    nuovo.name = nuovo.data.name = nome
    ## Pesi tutti sull'osso del braccio piu' vicino, maschera dalla distanza.
    for g in list(nuovo.vertex_groups):
        nuovo.vertex_groups.remove(g)
    gruppi = {}
    if ATTRIBUTO_MASCHERA in nuovo.data.color_attributes:
        nuovo.data.color_attributes.remove(nuovo.data.color_attributes[ATTRIBUTO_MASCHERA])
    attr = nuovo.data.color_attributes.new(ATTRIBUTO_MASCHERA, 'FLOAT_COLOR', 'POINT')
    nuovo.data.color_attributes.active_color = attr
    mwn = nuovo.matrix_world
    liberi = 0
    for v in nuovo.data.vertices:
        n, d, _q = vicino(mwn @ v.co)
        if n not in gruppi:
            gruppi[n] = nuovo.vertex_groups.new(name=n)
        gruppi[n].add([v.index], 1.0, 'REPLACE')
        t = min(max((d - attaccata) / (libera - attaccata), 0.0), 1.0)
        w = t * t * (3.0 - 2.0 * t)
        attr.data[v.index].color = (w, 0.0, 0.0, 1.0)
        liberi += w > 0.5
    print("separa_maniche: %s %d vertici (%d facce), %d liberi; %s resta di %d vertici" % (
          nome, len(nuovo.data.vertices), len(tenute), liberi, ob.name, len(ob.data.vertices)))
    return nuovo


def pesi_lontani(oggetti, rig="FanteRig", vicini=8, portate=None):
    """Toglie i pesi di BRACCIA, MANI e DITA dai vertici lontani da quell'osso.

    Sul Mago (2026-10-28, prova_movimento.gd a stoffa spenta) migliaia di
    vertici del manto e della veste pesavano su clavicole, spalle, dita e
    pollici fino a 1,3 m dall'osso: la gabbia e il travaso li avevano presi
    dalle mani appese accanto alla veste in A-pose. Quando il Mago alzava le
    braccia per un incantesimo se li portava dietro: lunghe schegge di stoffa
    dalle spalle, e la veste bianca che bucava il manto verde.

    Ogni peso su un osso delle braccia si sfuma via fra le due distanze di
    BRACCIA_PORTATA (dal segmento testa dell'osso -> testa del figlio). Chi
    resta senza pesi prende la media dei `vicini` vertici puliti piu' vicini
    dello stesso oggetto. Le distanze si misurano a riposo. `portate`
    sostituisce BRACCIA_PORTATA: (0, 0.02) toglie le braccia del tutto, come
    sulla veste del Mago, le cui falde accanto alle mani salivano con le
    braccia alzate (Richiamo, 2026-10-28)."""
    from mathutils.geometry import intersect_point_line
    from mathutils.kdtree import KDTree
    ar = bpy.data.objects[rig]
    mw = ar.matrix_world

    def segmento(nome):
        b = ar.data.bones.get(nome)
        if b is None:
            return None
        figli = [c for c in b.children if "Attachment" not in c.name]
        coda = figli[0].head_local if figli else b.tail_local
        return mw @ b.head_local, mw @ coda

    tabella = portate if portate is not None else BRACCIA_PORTATA

    def portata(nome):
        for chiavi, p in tabella.items():
            if any(nome.startswith(k) for k in chiavi):
                return p
        return None

    for ob in oggetti:
        nomi = {g.index: g.name for g in ob.vertex_groups}
        segmenti = {n: segmento(n) for n in nomi.values() if portata(n)}
        mwo = ob.matrix_world
        pos = [mwo @ v.co for v in ob.data.vertices]
        pesi = []
        toccati, vuoti = 0, []
        for v in ob.data.vertices:
            w = {nomi[g.group]: g.weight for g in v.groups if g.weight > 0}
            prima = dict(w)
            for n in list(w):
                if n not in segmenti or segmenti[n] is None:
                    continue
                a, b = segmenti[n]
                _q, t = intersect_point_line(pos[v.index], a, b)
                t = min(max(t, 0.0), 1.0)
                d = (pos[v.index] - (a + (b - a) * t)).length
                p0, p1 = portata(n)
                if d > p0:
                    k = min((d - p0) / (p1 - p0), 1.0)
                    w[n] *= 1.0 - k * k * (3.0 - 2.0 * k)
            w = {n: x for n, x in w.items() if x > 1e-4}
            if w != prima:
                toccati += 1
            if sum(w.values()) < 0.05:
                vuoti.append(v.index)
            pesi.append(w)
        puliti = [i for i in range(len(pesi)) if i not in set(vuoti)]
        kd = KDTree(len(puliti))
        for i in puliti:
            kd.insert(pos[i], i)
        kd.balance()
        for i in vuoti:
            media, somma = {}, 0.0
            for _co, j, d in kd.find_n(pos[i], vicini):
                f = 1.0 / max(d, 1e-4)
                somma += f
                for n, x in pesi[j].items():
                    media[n] = media.get(n, 0.0) + f * x / (sum(pesi[j].values()) or 1.0)
            pesi[i] = {n: x / somma for n, x in media.items()}
        for v, w in zip(ob.data.vertices, pesi):
            tot = sum(w.values()) or 1.0
            for g in list(v.groups):
                ob.vertex_groups[nomi[g.group]].remove([v.index])
            for n, x in w.items():
                if x / tot > 1e-4:
                    ob.vertex_groups[n].add([v.index], x / tot, 'REPLACE')
        print("pesi_lontani %s: %d vertici ripuliti dalle braccia, %d ripresi dai vicini" % (ob.name, toccati, len(vuoti)))


def separa_stoffe(me, minimo=500, presso=None):
    """Il tessuto del corpo in mesh a sé, uno STRATO per mesh, dopo il travaso.

    Tripo salda tutto il tessuto in UN guscio (Mago: 5.195 vertici fra
    cappuccio, pettorale, maniche, mantello, falde e veste). Gli strati si
    innestano l'uno sull'altro con giunzioni a T: spigoli NON-MANIFOLD, con
    tre o piu' facce. Tagliando li' il guscio si divide negli strati veri (sul
    Mago: sopra, 3.185 vertici; sotto, 2.256) piu' qualche scheggia, che resta
    col corpo. Ogni pezzo con almeno `minimo` vertici diventa un oggetto
    `Stoffa<N>` (1 = il piu' alto), con pesi, UV e materiale.

    ⚠️ NON si divide per colore della texture: Tripo dipinge un colore anche
    sul guscio dell'altro, e la divisione esce a coriandoli (visto sul Mago).
    """
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me.data)
    # L'etichetta sta in un attributo di FACCIA: sopravvive al taglio e alla
    # separazione, mentre gli indici delle facce cambiano a ogni passo.
    # ⚠️ Il livello si crea PRIMA di raccogliere le facce: aggiungerlo dopo
    # invalida ogni BMFace gia' letto ("BMesh data ... has been removed").
    lay = bm.faces.layers.int.new("strato")
    bm.verts.ensure_lookup_table()

    def componenti(facce):
        """Pezzi di facce collegate anche solo per un VERTICE, come le parti
        sciolte di Blender: collegarle solo per spigoli spezzettava sia il
        guscio sia gli strati."""
        seen, out = set(), []
        for f0 in facce:
            if f0 in seen:
                continue
            st, comp = [f0], []
            seen.add(f0)
            while st:
                x = st.pop()
                comp.append(x)
                for v in x.verts:
                    for g in v.link_faces:
                        if g not in seen and g in facce:
                            seen.add(g)
                            st.append(g)
            out.append(comp)
        return out

    tutte = set(bm.faces)
    gusci = componenti(tutte)
    # Il tessuto e' il guscio piu' INGOMBRANTE (diagonale del suo ingombro),
    # non quello con piu' facce: la testa del Mago, fitta di triangoli, ne ha
    # piu' della veste, e la prima prova ha separato le orecchie (2026-09-30).
    def ingombro(s):
        co = [v.co for f in s for v in f.verts]
        return (Vector((max(p.x for p in co), max(p.y for p in co), max(p.z for p in co)))
                - Vector((min(p.x for p in co), min(p.y for p in co), min(p.z for p in co)))).length
    from mathutils import Vector
    if presso is not None:
        ## Il guscio di tessuto indicato con un punto (mondo): quello del
        ## vertice piu' vicino. Serve dove il tessuto NON e' il guscio piu'
        ## ingombrante: sul Comandante il mantello e' un guscio a se' e il piu'
        ## ingombrante e' l'armatura (2026-10-02).
        q = me.matrix_world.inverted() @ Vector(presso)
        tessuto = set(min(gusci, key=lambda s: min((v.co - q).length for f in s for v in f.verts)))
    else:
        tessuto = set(max(gusci, key=ingombro))
    # dentro il guscio del tessuto, gli strati: si TAGLIANO le giunzioni a T e
    # si cercano i pezzi collegati anche solo per un vertice. ⚠️ Collegarli
    # solo per spigoli spezzettava gli strati in frammenti (una stoffa sola
    # da 1.783 vertici invece di due da 3.185 e 2.256).
    nm = [e for e in bm.edges if len(e.link_faces) > 2 and all(f in tessuto for f in e.link_faces)]
    bmesh.ops.split_edges(bm, edges=nm)
    strati = componenti(tessuto)
    grandi = [s for s in strati if len({v for f in s for v in f.verts}) >= minimo]
    alto = lambda s: max((me.matrix_world @ v.co).z for f in s for v in f.verts)
    grandi.sort(key=alto, reverse=True)
    for f in bm.faces:
        f[lay] = 0
    for i, s in enumerate(grandi):
        for f in s:
            f[lay] = i + 1
    # ⚠️ I FRAMMENTI del tessuto (decine di pezzetti da 4-16 vertici) vanno con
    # lo strato piu' vicino: lasciati al corpo restavano fermi dentro la stoffa
    # che si muove, chiazze visibili gia' nella maschera (2026-09-30).
    from mathutils.kdtree import KDTree
    punti = [(v.co, i + 1) for i, s in enumerate(grandi) for v in {v for f in s for v in f.verts}]
    kd = KDTree(len(punti))
    for j, (co, _n) in enumerate(punti):
        kd.insert(co, j)
    kd.balance()
    for s in strati:
        if s in grandi:
            continue
        c = sum((v.co for f in s for v in f.verts), Vector()) / sum(len(f.verts) for f in s)
        n = punti[kd.find(c)[1]][1]
        for f in s:
            f[lay] = n
    # si tagliano le giunzioni fra uno strato e il resto, poi si separa
    tagli = [e for e in bm.edges if len({f[lay] for f in e.link_faces}) > 1]
    bmesh.ops.split_edges(bm, edges=tagli)
    bm.to_mesh(me.data)
    bm.free()

    fuori = []
    for i in range(1, len(grandi) + 1):
        att = me.data.attributes["strato"].data
        for v in me.data.vertices:
            v.select = False
        for e in me.data.edges:
            e.select = False
        for p in me.data.polygons:
            p.select = att[p.index].value == i
            if p.select:
                for vi in p.vertices:
                    me.data.vertices[vi].select = True
        for e in me.data.edges:
            e.select = all(me.data.vertices[vi].select for vi in e.vertices)
        bpy.ops.object.select_all(action='DESELECT')
        me.select_set(True)
        bpy.context.view_layer.objects.active = me
        prima = set(bpy.data.objects)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.separate(type='SELECTED')
        bpy.ops.object.mode_set(mode='OBJECT')
        nuovo = [o for o in bpy.data.objects if o not in prima][0]
        nuovo.name = nuovo.data.name = "%s%d" % (PREFISSO_STOFFA, i)
        fuori.append(nuovo)
    for o in fuori + [me]:
        if "strato" in o.data.attributes:
            o.data.attributes.remove(o.data.attributes["strato"])
    for o in fuori:
        co = [o.matrix_world @ v.co for v in o.data.vertices]
        print("%s: %d vertici, z %.2f..%.2f" % (o.name, len(co), min(p.z for p in co), max(p.z for p in co)))
    print("corpo: %d vertici" % len(me.data.vertices))
    return fuori


def _coperti(ob, coperture, distanza, giri=3):
    """Quanto e' COPERTO ogni vertice (0..1): un raggio orizzontale dall'asse
    del corpo verso l'esterno incontra un'altra stoffa entro `distanza`?

    Serve dove due strati sono saldati nello stesso pezzo (sul Mago le falde
    verdi e la veste bianca, unite agli orli e senza giunzioni da tagliare):
    liberi tutti e due si attraversano. Lo strato COPERTO non si vede, e si
    tiene sulle ossa. La copertura si ammorbidisce lungo la mesh per `giri`.
    """
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    alberi = []
    for o in coperture:
        bm = __import__("bmesh").new()
        bm.from_mesh(o.data)
        bm.transform(o.matrix_world)
        alberi.append(BVHTree.FromBMesh(bm))
        bm.free()
    mw = ob.matrix_world
    co = [mw @ v.co for v in ob.data.vertices]
    cx = sum(p.x for p in co) / len(co)
    cy = sum(p.y for p in co) / len(co)
    cop = []
    for p in co:
        d = Vector((p.x - cx, p.y - cy, 0.0))
        if d.length < 1e-6:
            cop.append(0.0)
            continue
        d.normalize()
        preso = any(t.ray_cast(p + d * 0.004, d, distanza)[0] is not None for t in alberi)
        cop.append(1.0 if preso else 0.0)
    vicini = [[] for _ in co]
    for e in ob.data.edges:
        a, b = e.vertices
        vicini[a].append(b)
        vicini[b].append(a)
    for _ in range(giri):
        cop = [(c + sum(cop[j] for j in vicini[i])) / (1 + len(vicini[i])) for i, c in enumerate(cop)]
    return cop


def maschera_stoffa(ob, alto, basso, ossa_ferme=("Shoulder", "Elbow", "Hand", "Clavicle"), dietro=None,
                    coperture=(), distanza=0.08):
    """La maschera della stoffa nel colore dei vertici `cloth_weight` (canale R).

    0 = segue le ossa, 1 = stoffa libera. Per ALTEZZA: sopra `alto` ferma, sotto
    `basso` libera, in mezzo sfuma (smoothstep). I vertici che pesano per lo
    piu' su `ossa_ferme` (le maniche, che senza collisioni sulle braccia
    passerebbero dentro l'avambraccio) restano fermi. Con `dietro` (metri, Y
    di Blender: il dorso e' +Y) e' libero solo cio' che sta piu' indietro:
    il mantello si', il pettorale che scende sulla cintura no. Con
    `coperture` (le stoffe, compresa questa) cio' che sta SOTTO un altro
    strato entro `distanza` resta sulle ossa (`_coperti`).
    """
    import bmesh
    me = ob.data
    cop = _coperti(ob, coperture, distanza) if coperture else None
    if ATTRIBUTO_MASCHERA in me.color_attributes:
        me.color_attributes.remove(me.color_attributes[ATTRIBUTO_MASCHERA])
    attr = me.color_attributes.new(ATTRIBUTO_MASCHERA, 'FLOAT_COLOR', 'POINT')
    me.color_attributes.active_color = attr
    nomi = {g.index: g.name for g in ob.vertex_groups}
    liberi = 0
    for v in me.vertices:
        z = (ob.matrix_world @ v.co).z
        t = max(0.0, min(1.0, (alto - z) / (alto - basso)))
        w = t * t * (3.0 - 2.0 * t)
        fermo = sum(el.weight for el in v.groups if nomi[el.group].rsplit("_", 1)[0] in ossa_ferme)
        tot = sum(el.weight for el in v.groups) or 1.0
        if fermo / tot > 0.5:
            w = 0.0
        if dietro is not None:
            y = (ob.matrix_world @ v.co).y
            t = max(0.0, min(1.0, (y - dietro) / 0.05))
            w *= t * t * (3.0 - 2.0 * t)
        if cop is not None:
            w *= max(0.0, 1.0 - 2.0 * cop[v.index])
        attr.data[v.index].color = (w, 0.0, 0.0, 1.0)
        liberi += w > 0.5
    print("%s: maschera %.2f -> %.2f m, %d vertici liberi su %d" % (ob.name, alto, basso, liberi, len(me.vertices)))


# ═══════════════════════════════════════════════════════════════════════════
# 5. L'export, e le tre cose che la scena si aspetta di trovarci dentro
# ═══════════════════════════════════════════════════════════════════════════

def esporta_glb(percorso=None, mesh="FanteSylvorn", rig="FanteRig", posa=None):
    """⚠️ Tre requisiti, letti dalla scena e dal GLB del Consumato, non dedotti:

    1. L'armatura deve chiamarsi **`NephiliteRig`**: le due scene puntano a
       `Model/NephiliteRig/Skeleton3D`, e il `BoneAttachment3D` dell'arma con
       lei.
    2. Dentro deve esserci **almeno una clip**, anche inerte. Godot crea il nodo
       `AnimationPlayer` solo se il glTF porta un'animazione, e le scene hanno
       `anim_player = NodePath("Model/AnimationPlayer")`: senza clip il nemico
       nasce senza player e non si muove. (skill §5)
    3. I nomi delle ossa restano quelli **Nephilite**: e' la bone map
       `nephilite_humanoid.tres` a rinominarli sul profilo Humanoid all'import.

    ⚠️ E non si esporta la scena intera: il blend contiene ancora il rig ARP, il
    donatore e i suoi custom shape. Si esporta la SOLA selezione.
    """
    if percorso is None:
        percorso = DIR_SYLVORN + "sylvorn_fante_rigged.glb"
    me = bpy.data.objects[mesh]
    ar = bpy.data.objects[rig]
    # Le STOFFE (`separa_stoffe`) escono insieme al corpo, sullo stesso rig.
    stoffe = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(PREFISSO_STOFFA)]
    tutte = [me] + stoffe

    for o in list(bpy.data.objects):
        if o not in tutte and o is not ar:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.armatures):
        if a is not ar.data:
            bpy.data.armatures.remove(a)
    ar.name = ar.data.name = "NephiliteRig"

    # ⚠️ Prima si buttano le azioni che la sessione ha accumulato: il rig
    # donatore ne porta una a ogni `prepara()`, e l'esportatore (modo ACTIONS)
    # le scriverebbe TUTTE nel GLB — il 2026-09-14 ne uscivano quattro, tre
    # di rumore, e in gioco diventano clip nell'AnimationPlayer.
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    if posa is None:
        # la clip inerte del requisito 2: due chiavi sul `Root`, a riposo
        act = bpy.data.actions.new("Animation")
        ar.animation_data_create().action = act
        pb = ar.pose.bones["Root"]
        pb.rotation_mode = 'QUATERNION'
        for f in (1, 2):
            pb.keyframe_insert("rotation_quaternion", frame=f)
        act.use_fake_user = True
    else:
        # I campioni (2026-10-21): la clip e' la POSA DEL MENU (`posa`, ossa ->
        # matrix_basis, da `posa_menu` di monta_campione.py), con un respiro:
        # a meta' giro petto e clavicole salgono di un grado e mezzo.
        import math
        from mathutils import Matrix
        act = bpy.data.actions.new("Posa")
        ar.animation_data_create().action = act
        respiro = {"Spine_02": 0.8, "Spine_03": 1.2, "Clavicle_L": -1.0, "Clavicle_R": -1.0}
        for f, k in ((1, 0.0), (46, 1.0), (91, 0.0)):
            for nome, base in posa.items():
                pb = ar.pose.bones.get(nome)
                if pb is None:
                    continue
                pb.rotation_mode = 'QUATERNION'
                m = base
                if nome in respiro:
                    m = base @ Matrix.Rotation(math.radians(respiro[nome] * k), 4, 'X')
                pb.matrix_basis = m
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
        act.use_fake_user = True
        for pb in ar.pose.bones:
            pb.matrix_basis = Matrix()

    # La TRIANGOLAZIONE la decidiamo noi. La GPU disegna solo triangoli e ogni
    # formato (GLB, FBX, OBJ) viene triangolato comunque all'import di Godot: i
    # quad servono in lavorazione (rig, pesi, ritocchi), non in gioco. Qui si
    # sceglie la diagonale di ogni quad col metodo BEAUTY (la piu' corta, che
    # evita pieghe d'ombra sui quad non piani) invece di lasciarla
    # all'esportatore. I gruppi di vertici e le UV restano.
    import bmesh
    for o in tutte:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        quad = sum(1 for f in bm.faces if len(f.verts) == 4)
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='BEAUTY')
        bm.to_mesh(o.data)
        bm.free()
        # Tripo lascia qualche faccia non valida (doppie o a area zero): sul
        # Mago 15 su 28.462 triangoli. L'esportatore glTF le toglierebbe da se'
        # con un avviso "Mesh ... is not valid"; qui si tolgono prima, e si contano.
        prima = len(o.data.polygons)
        o.data.validate(clean_customdata=False)
        print("%s: triangolati %d quad (BEAUTY): %d triangoli, %d non validi tolti"
              % (o.name, quad, len(o.data.polygons), prima - len(o.data.polygons)))

    # ⚠️ Un oggetto NASCOSTO non si seleziona, e l'export e' della sola
    # selezione: col rig nascosto (per inquadrare una mano) usciva un GLB con
    # la mesh e senza scheletro, "ossa nello skin: 0" (2026-09-30).
    ar.hide_set(False)
    bpy.ops.object.select_all(action='DESELECT')
    for o in tutte:
        o.hide_set(False)
        o.select_set(True)
    ar.select_set(True)
    bpy.context.view_layer.objects.active = ar
    # Il colore dei vertici esce SOLO se si chiama `cloth_weight` (la maschera
    # delle stoffe): con il default 'MATERIAL' l'esportatore lo scarta, perche'
    # nessun materiale lo usa.
    bpy.ops.export_scene.gltf(filepath=percorso, export_format='GLB',
                              use_selection=True, export_animations=True,
                              export_skins=True, export_apply=False,
                              export_vertex_color='NAME',
                              export_vertex_color_name=ATTRIBUTO_MASCHERA)
    return percorso


def verifica_glb(percorso):
    """⚠️ Un export puo' RIUSCIRE producendo un file vuoto: nessun errore, file
    scritto, zero skin e zero animazioni dentro (skill §3). Si guarda dentro."""
    import json
    import struct
    with open(percorso, "rb") as f:
        dati = f.read()
    assert dati[:4] == b"glTF", "non e' un GLB"
    lung = struct.unpack("<I", dati[12:16])[0]
    j = json.loads(dati[20:20 + lung].decode("utf-8"))
    tri = 0
    for m in j.get("meshes", []):
        for p in m["primitives"]:
            tri += j["accessors"][p["indices"]]["count"] // 3
    print("%s: %.1f MB | nodi %d | skin %d | anim %d | mesh %d | triangoli %d | texture %d"
          % (os.path.basename(percorso), len(dati) / 1e6, len(j.get("nodes", [])),
             len(j.get("skins", [])), len(j.get("animations", [])), len(j.get("meshes", [])),
             tri, len(j.get("images", []))))
    radici = [j["nodes"][i]["name"] for i in j["scenes"][j.get("scene", 0)]["nodes"]]
    print("  radici:", radici)
    print("  ossa nello skin:", len(j["skins"][0]["joints"]) if j.get("skins") else 0)
    return j
