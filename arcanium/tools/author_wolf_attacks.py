# -*- coding: utf-8 -*-
"""Autora le clip d'attacco del lupo con un ANTICIPO leggibile.

Il problema misurato sulle clip originali: in tutta la carica del morso la testa
arretrava di 2.8 cm e saliva di 2.1 (su una testa che sta 31 cm sopra l'anca) e
il corpo non si accovacciava affatto (accovacciamento piatto: -0.200 -> -0.202).
Con lo zoom isometrico del gioco non si vedeva nulla, quindi il morso arrivava
senza preavviso. Nella combo, poi, fra i due contatti (0.75 s e 1.38 s) la testa
rientrava per soli 0.25 s e meno della carica iniziale: i due colpi si leggevano
attaccati.

Qui l'anticipo diventa un GESTO: l'animale si accovaccia (anca giù, zampe
piegate), arretra e ALZA il muso, orecchie indietro — poi scatta. E nella combo
fra un morso e l'altro c'è una seconda carica visibile, non un rimbalzo.

Uso:
  blender --background --python tools/author_wolf_attacks.py
Esporta GLB di sola armatura in assets/characters/enemies/anims/.
"""
import bpy, math, os, tempfile
from mathutils import Vector, Matrix, Euler

## ⚠️ Ricavata dalla posizione dello script (`<radice>/arcanium/tools/`), non
## scritta a mano: era fissata al percorso del PC vecchio e su qualunque altra
## macchina lo script non partiva.
RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")).replace("\\", "/")
GLB = RADICE + "/assets/characters/enemies/wolf_animated.glb"
DEST = RADICE + "/assets/characters/enemies/anims/wolf/"
OUT = os.path.join(tempfile.gettempdir(), "arcanium_provini") + os.sep
os.makedirs(OUT, exist_ok=True)

FPS = 24
## Il modello in gioco è scalato 2.6: le misure di anticipo si stampano in unità
## di gioco, così sono confrontabili con la sonda Godot.
SCALA_GIOCO = 2.6

## ═══════════════════════════════════════════════════════════════════════════
## IL MORSO E' LA CHIUSURA DELLA BOCCA, non l'avanzamento della testa
## ═══════════════════════════════════════════════════════════════════════════
## Prima il rilascio era una TRASLAZIONE di tutta la testa (carica in alto,
## scatta avanti e in basso) e la bocca non faceva niente: il collo faceva
## tutto, e il colpo si leggeva come una testata. Ora la mandibola e' un osso
## (`jaw`, figlio di `head`) e il gesto e':
##
##   carica accentuata + bocca che si SPALANCA (e' il tell)
##   → 2 frame di STASI a bocca aperta
##   → chiusura in 3 frame = IL COLPO
##
## ⚠️ I frame di CONTATTO sono quelli della chiusura, non quelli
## dell'avanzamento: `contact_times` nel move set va misurato li'.
##
## `jaw`: 0 = bocca chiusa (e' la posa di bind), POSITIVO = si apre. Oltre i 45
## gradi l'angolo della bocca si strappa; 40 e' lo spalancamento massimo sano.
APERTA = 40
SOCCHIUSA = 20

## `rollio`: la testa si INCLINA per arrivare piu' orizzontale sul corpo del
## bersaglio — un lupo non morde di piatto. Non sostituisce il pitch: il muso
## resta in linea, solo cantato.
# (frame, (roll, pitch, drop) anca, chest, head, zampe_ant, zampe_post, coda, orecchie, jaw, rollio)
#  pitch NEGATIVO = muso in su (coil);  head NEGATIVO = testa alzata.
## ⚠️ «Carica più accentuata» NON vuol dire alzare tutti i numeri. Con anca a
## −16 di pitch e zampe anteriori a 32 il lupo si IMPENNA: le anteriori si
## staccano da terra e l'animale sta ritto come un cavallo. Il pitch dell'anca
## ruota tutto il corpo attorno al bacino e solleva il davanti; le anteriori
## piegate lo assecondano. Una carica più profonda si ottiene ABBASSANDO il
## bacino (drop) e arrotolando collo e petto, tenendo il pitch dov'era e le
## zampe piantate. Si vede solo di profilo con un pavimento in campo: nei
## numeri il picco sembrava semplicemente "più carico".
CARICA = [
    (0,  (0,   0,  0.000),   0,   0,    0,   0,   0,   0,   0,   0),
    (7,  (0,  -4, -0.016),  -9, -20,    9,  16,  -7,  22,  SOCCHIUSA,  -4),
    (16, (0,  -8, -0.040), -22, -40,   18,  32, -14,  40,  APERTA,     -8),  # picco
    (18, (0,  -8, -0.040), -22, -40,   18,  32, -14,  40,  APERTA,     -8),  # STASI
]
## ⚠️ Lo scatto va tenuto MOLTO più contenuto della carica. Primo tentativo:
## anca +14 di pitch sommata a petto +20 e testa +40, con le zampe anteriori
## ripiegate all'indietro — il lupo si piantava il muso SOTTO il pavimento con
## le zampe divaricate, una faccia a terra invece di un morso. Il pitch dell'anca
## fa ruotare TUTTO il corpo attorno al bacino, quindi si somma a valle: qui
## resta piccolo e l'affondo lo danno petto e collo, mentre le zampe restano
## vicine al neutro perché devono reggere l'animale.
##
## ⚠️ E il morso NON va verso terra, né torna in linea: il muso resta ALZATO
## come in carica e il lupo morde verso l'ALTO, per strappare il petto. Finché
## la bocca non si apriva, mandare la testa in basso era l'unico modo di far
## leggere un impatto; ora che il colpo è la CHIUSURA, la testa non deve fare il
## lavoro. Quindi nel rilascio `head` resta NEGATIVO (muso in su): quello che
## cambia è il corpo che si distende in avanti, e la bocca che scatta.
## Al contatto il collo si ALLUNGA in avanti (`chest` positivo = si protende)
## mentre il muso resta ALTO (`head` negativo) e girato: e' la posa da strappo.
## Le due rotazioni si sommano a valle, quindi la direzione vera del muso e'
## chest+head — che deve restare negativa, cioe' in su.
SCATTO = [
    (22, (0,  -2, -0.014),  10, -32,    6,  20,  -4,   6,  APERTA,     26),  # arriva APERTA
    (25, (0,   2, -0.010),  18, -34,   -6,  14,   4,   0,   0,        40),  # CONTATTO: strappo
    (30, (0,   0, -0.004),   6, -18,    2,   6,   2,   0,   6,        14),
]
RITORNO = [(38, (0, 0, 0.000), 0, 0, 0, 0, 0, 0, 0, 0)]

# combo: dopo il primo contatto si RICARICA in modo visibile, poi secondo morso
RICARICA = [
    (31, (0,  -8, -0.018), -12, -24,   18,  20,  -8,  28,  SOCCHIUSA,   0),
    (38, (0, -11, -0.032), -18, -34,   25,  31, -13,  38,  APERTA,     -6),  # 2° segnale
    (40, (0, -11, -0.032), -18, -34,   25,  31, -13,  38,  APERTA,     -6),  # STASI
]
SCATTO2 = [
    (43, (0,  -2, -0.014),  10, -30,    6,  20,  -4,   6,  APERTA,    -26),
    (46, (0,   2, -0.010),  18, -32,   -6,  14,   4,   0,   0,       -40),  # CONTATTO 2
    (51, (0,   0, -0.004),   6, -18,    2,   6,   2,   0,   6,       -14),
]
RITORNO2 = [(58, (0, 0, 0.000), 0, 0, 0, 0, 0, 0, 0, 0)]

## Istanti di CONTATTO (chiusura della bocca) in secondi, per il move set.
CONTATTI = {"wolf_bite_01": [25 / 24.0], "wolf_bite_combo_01": [25 / 24.0, 46 / 24.0]}

CLIP = {
    "wolf_bite_01": CARICA + SCATTO + RITORNO,
    "wolf_bite_combo_01": CARICA + SCATTO + RICARICA + SCATTO2 + RITORNO2,
}

## ═══════════════════════════════════════════════════════════════════════════
## IL ROOT MOTION — dove il lupo VA, separato da come si muove
## ═══════════════════════════════════════════════════════════════════════════
## Sta in una tabella a parte e non dentro le pose di sopra, perché è un'altra
## cosa: quelle dicono come si piega l'animale, questa dice dove finisce. Si
## rileggono e si ritoccano senza intralciarsi.
##
## Va su un osso `Root` a terra (creato all'import, vedi `aggiungi_root`), che è
## la convenzione del progetto: `root_motion_track = "%GeneralSkeleton:Root"`,
## come in `characters/player_dawnkeep.tscn` e in `arcanium_humanoid_enemy.gd`.
## Mettere invece la traslazione sull'anca costerebbe il beccheggio del bacino,
## che Godot consumerebbe come spostamento invece di mostrarlo.
##
## ⚠️ I numeri sono in METRI DI GIOCO e vengono divisi per SCALA_GIOCO: il
## modello è scalato 2.6 in `arcanium/characters/lupo.tscn`, quindi un metro di
## affondo è 0.385 unità nell'animazione. Scriverli in unità d'animazione
## renderebbe impossibile capire a colpo d'occhio se un balzo è lungo.
##
## ⚠️ Il commit `fa7a64c` aveva TOLTO la traslazione dall'anca («rimosso lo
## sprofondamento»). Quello resta giusto: qui non si rimette il movimento sul
## bacino, si mette su un osso dedicato che Godot sa consumare.
#            (frame, avanti_m, su_m)
MOTO = {
    ## Morso singolo = attacco IN SALTO. Sta fermo per tutta la carica — è
    ## l'anticipo, e un anticipo che scivola non si legge — poi stacca, e il
    ## contatto arriva mentre è ancora per aria. NESSUN rientro: atterra e resta
    ## dov'è, che è quello che rende l'attacco pericoloso da schivare.
    "wolf_bite_01": [
        (0,  0.00, 0.00),
        (16, 0.00, 0.00),   # picco della carica: ancora piantato
        (18, 0.00, 0.00),   # stasi a bocca aperta
        (21, 0.15, 0.18),   # stacco
        (25, 0.70, 0.10),   # CONTATTO: morde ancora in aria
        (30, 1.00, 0.00),   # atterraggio
        (38, 1.00, 0.00),   # resta lì
    ],
    ## Doppio morso = attacco AVANZANTE. Nessun balzo: avanza di continuo, e i
    ## due contatti cadono su due passi. La ricarica fra i due morsi guadagna
    ## comunque terreno, così il secondo non sembra un rimbalzo sul posto.
    "wolf_bite_combo_01": [
        (0,  0.00, 0.0),
        (16, 0.05, 0.0),    # striscia avanti mentre si accovaccia
        (25, 0.35, 0.0),    # CONTATTO 1
        (38, 0.55, 0.0),    # ricarica: guadagna terreno
        (46, 0.85, 0.0),    # CONTATTO 2
        (58, 1.00, 0.0),
    ],
}

FRONT = ["frontleg", "R_frontleg"]
FRONT2 = ["frontleg0", "R_frontleg0"]
BACK = ["backleg", "R_backleg"]
BACK2 = ["backleg0", "R_backleg0"]
TAIL = ["tailstart", "tail1", "tail2", "tail3"]
EARS = ["earend", "R_earend"]


def fcurve_di(act):
    """Le fcurve di un'action in Blender 5.x: non piu' `act.fcurves`, ma dentro
    layer → strip → channelbag (le action ora hanno gli SLOT)."""
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    yield fc


def pulisci():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)


def aggiungi_root(rig):
    """Crea l'osso `Root` a terra e ci appende `Hips`.

    Il GLB base non ce l'ha (la radice è `Hips`), ma Godot legge il root motion
    da un osso chiamato così. Lo si crea qui e non nel .blend perché la sorgente
    dei morsi è QUESTO script: il blend del lupo ha le azioni piatte, e chi
    cercasse lì il movimento non lo troverebbe.

    Restituisce (avanti, su) come versori in spazio ARMATURA, MISURATI dal rig:
    l'orientamento del lupo importato non si deduce, si guarda dove ha il muso.
    """
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    if "Root" in eb:
        eb.remove(eb["Root"])
    root = eb.new("Root")
    root.head = (0.0, 0.0, 0.0)
    ## punta lungo +Y locale, che qui è l'ALTO: lo stesso asse su cui
    ## `basis_anca` applica il `drop`. Così la matrice locale è l'identità e
    ## `location` si legge senza conversioni.
    root.tail = (0.0, 0.10, 0.0)
    root.roll = 0.0
    root.use_deform = False
    h = eb["Hips"]
    h.parent = root
    h.use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')

    su = Vector((0.0, 1.0, 0.0))
    muso = rig.data.bones["headend"].head_local - rig.data.bones["Hips"].head_local
    muso.y = 0.0                      # solo la componente orizzontale
    avanti = muso.normalized()
    print("  Root creato | avanti locale = (%.2f, %.2f, %.2f)" % (avanti.x, avanti.y, avanti.z))
    return avanti, su


def applica_moto(rig, nome, avanti, su):
    """Scrive il root motion sull'osso `Root`, dai metri di gioco di `MOTO`."""
    passi = MOTO.get(nome)
    if not passi:
        return
    pb = rig.pose.bones["Root"]
    ## ⚠️ L'esportatore glTF converte le coordinate in Y-up: (x, y, z) → (x, z, −y).
    ## Scrivere la traslazione già "come la vogliamo nel GLB" la manda sull'asse
    ## sbagliato — misurato: il metro d'affondo finiva in verticale e il lupo
    ## saltava sul posto. Serve la conversione INVERSA: per ottenere il vettore
    ## glTF `g` si scrive `(g.x, −g.z, g.y)`.
    def in_blender(g):
        return Vector((g.x, -g.z, g.y))

    for f, avanti_m, su_m in passi:
        g = (avanti * (avanti_m / SCALA_GIOCO)) + (su * (su_m / SCALA_GIOCO))
        pb.location = in_blender(g)
        pb.keyframe_insert("location", frame=f)
    print("  moto: %d chiavi, avanza %.2f m, alza %.2f m"
          % (len(passi), max(p[1] for p in passi), max(p[2] for p in passi)))


def costruisci(nome, chiavi):
    pulisci()
    bpy.ops.import_scene.gltf(filepath=GLB)
    rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
    avanti, su = aggiungi_root(rig)

    bpy.context.view_layer.objects.active = rig
    rig.animation_data_clear()
    # via le action importate, o la nostra diventa "<nome>.001"
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    act = bpy.data.actions.new(nome)
    rig.animation_data_create()
    rig.animation_data.action = act
    try:
        rig.animation_data.action_slot = act.slots.new(id_type='OBJECT', name="WolfRig")
    except Exception as e:
        print("slot:", e)

    bpy.ops.object.mode_set(mode='POSE')
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)

    anca = rig.data.bones["Hips"]
    pivot = anca.head_local.copy()

    def basis_anca(roll, pitch, drop):
        R = (Matrix.Rotation(math.radians(roll), 4, 'Z')
             @ Matrix.Rotation(math.radians(pitch), 4, 'X'))
        attorno = Matrix.Translation(pivot) @ R @ Matrix.Translation(-pivot)
        target = Matrix.Translation(Vector((0, drop, 0))) @ attorno @ anca.matrix_local
        return anca.matrix_local.inverted() @ target

    def ruota(osso, gradi, f):
        pb = rig.pose.bones.get(osso)
        if pb is None:
            return
        pb.rotation_euler = Euler([math.radians(g) for g in gradi], 'XYZ')
        pb.keyframe_insert("rotation_euler", frame=f)

    for (f, hips, chest, head, front, back, tail, ear, jaw, rollio) in chiavi:
        hp = rig.pose.bones["Hips"]
        hp.matrix_basis = basis_anca(hips[0], hips[1], hips[2])
        hp.keyframe_insert("rotation_euler", frame=f)
        hp.keyframe_insert("location", frame=f)
        ruota("chest", (chest, 0, 0), f)
        ## il rollio va sull'asse dell'osso (Y = lunghezza), non su X
        ruota("head", (head, rollio, 0), f)
        for n in FRONT:
            ruota(n, (front, 0, 0), f)
        for n in FRONT2:
            ruota(n, (-front * 0.75, 0, 0), f)
        for n in BACK:
            ruota(n, (-back, 0, 0), f)
        for n in BACK2:
            ruota(n, (back * 0.85, 0, 0), f)
        for i, n in enumerate(TAIL):
            ruota(n, (tail * (0.6 + 0.2 * i), 0, tail * 0.25), f)
        for n in EARS:
            ruota(n, (ear, 0, 0), f)
        ## la mandibola: se l'osso non c'e', la clip esce muta invece di
        ## fallire — e il morso tornerebbe una testata senza che nessuno lo dica
        assert "jaw" in rig.pose.bones, "manca l'osso `jaw`: GLB base vecchio?"
        ruota("jaw", (jaw, 0, 0), f)

    applica_moto(rig, nome, avanti, su)

    bpy.ops.object.mode_set(mode='OBJECT')
    ## ⚠️ La mandibola va in LINEARE. Con l'interpolazione bezier di default la
    ## chiusura in 3 frame si ammorbidisce in entrata e in uscita: misurata, a
    ## due terzi del tragitto la bocca era ancora quasi spalancata, e un morso
    ## che si chiude "dolcemente" non e' uno scatto. Il resto del corpo la
    ## bezier ce l'ha giustamente.
    for fc in fcurve_di(act):
        if '"jaw"' in fc.data_path:
            for k in fc.keyframe_points:
                k.interpolation = 'LINEAR'
    act.use_fake_user = True
    return rig, mesh, act


def misura(rig, chiavi, nome):
    """Anticipo in unità di GIOCO, confrontabile con la sonda Godot."""
    scn = bpy.context.scene
    testa = rig.pose.bones["head"]
    anca = rig.pose.bones["Hips"]
    zampa = rig.pose.bones["frontleg2"]
    mand = rig.pose.bones["jaw"]
    print("\n--- %s --- (unita' di gioco, x%.1f)" % (nome, SCALA_GIOCO))
    print("   f      t     testa_avanti  testa_su   accovacciamento   bocca(cm)")
    ultimo = chiavi[-1][0]
    for f in range(0, ultimo + 1, 2):
        scn.frame_set(f)
        bpy.context.view_layer.update()
        h = testa.matrix.translation
        p = anca.matrix.translation
        z = zampa.matrix.translation
        ## Apertura MISURATA sulla punta della mandibola, non l'angolo che ho
        ## scritto io nelle chiavi: se l'osso non ruotasse, l'angolo direbbe
        ## comunque 40 e la bocca resterebbe chiusa.
        ## ⚠️ Va misurata nello spazio della TESTA: in spazio armatura ci
        ## finisce dentro anche la rotazione del collo, e durante la carica —
        ## che alza il muso di 38 gradi — la misura dice che la bocca si CHIUDE
        ## mentre si sta spalancando.
        in_testa = testa.matrix.inverted()
        cerniera = in_testa @ mand.matrix.translation
        punta = in_testa @ (mand.matrix @ Vector((0, mand.length, 0)))
        print("  %3d   %.2f    %+7.3f      %+7.3f    %+7.3f        %6.2f" % (
            f, f / float(FPS),
            (h.z - p.z) * SCALA_GIOCO, (h.y - p.y) * SCALA_GIOCO,
            (p.y - z.y) * SCALA_GIOCO,
            (cerniera.y - punta.y) * SCALA_GIOCO * 100.0))


def renderizza(rig, mesh, nome, frames, testa_sola=False):
    """Provino A CONTATTO: un riquadro per frame, di PROFILO ortografico.

    Il ritmo non si vede in nessun frame singolo — e con la mandibola serve
    anche il primo piano, perche' su tutto il corpo la bocca e' quaranta pixel.
    """
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.render.resolution_x = 640
    scn.render.resolution_y = 480
    pts = []
    for b in rig.data.bones:
        pts.append(rig.matrix_world @ b.head_local)
        pts.append(rig.matrix_world @ b.tail_local)
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centro = (lo + hi) * 0.5
    dim = max((hi - lo).x, (hi - lo).y, (hi - lo).z)
    larg = dim * 0.75 if testa_sola else dim * 1.5
    cd = bpy.data.cameras.new("QA")
    cd.type = 'ORTHO'
    cd.ortho_scale = larg
    cam = bpy.data.objects.new("QA", cd)
    scn.collection.objects.link(cam)
    # PROFILO: un morso va avanti e la bocca si apre in verticale, e di tre
    # quarti l'apertura si accorcia. 'Y' = asse locale della camera tenuto in
    # alto, giusto in un mondo Z-up.
    ## di profilo per il RITMO e la linea del morso; di tre quarti da davanti per
    ## il ROLLIO, che di profilo e' invisibile (ruota attorno all'asse di vista)
    occhio_rel = (Vector((1.4, -1.0, 0.15)) if testa_sola == '34'
                  else Vector((-1.0, 0.0, 0.0)))
    cam.rotation_euler = (-occhio_rel).to_track_quat('-Z', 'Y').to_euler()
    scn.camera = cam
    if not testa_sola:
        bpy.ops.mesh.primitive_plane_add(size=dim * 3, location=(centro.x, centro.y, 0.0))
    fatti = []
    for f in frames:
        scn.frame_set(f)
        bpy.context.view_layer.update()
        ## ⚠️ Il primo piano deve SEGUIRE la testa: inquadrando il punto dove la
        ## testa sta al frame 0, i frame del colpo — che sono quelli che contano
        ## — escono fuori campo e il provino non mostra proprio la chiusura.
        if testa_sola:
            ## centrata fra la nuca e la punta del mento, non sull'origine
            ## dell'osso `head` — che sta in fondo al cranio e lascia il muso
            ## sul bordo, mezzo tagliato
            pb = rig.pose.bones["jaw"]
            mento = pb.matrix @ Vector((0, pb.length, 0))
            nuca = rig.pose.bones["head"].matrix.translation
            centro = rig.matrix_world @ ((mento + nuca) * 0.5)
        cam.location = centro + occhio_rel.normalized() * dim * 2.0
        scn.render.filepath = OUT + "%s_f%02d.png" % (nome, f)
        bpy.ops.render.render(write_still=True)
        fatti.append(scn.render.filepath)
    bpy.data.objects.remove(cam, do_unlink=True)
    return fatti


def esporta(rig, nome):
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    dest = DEST + nome + ".glb"
    bpy.ops.export_scene.gltf(
        filepath=dest, export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='ACTIONS', export_yup=True)
    print("ESPORTATO:", dest, os.path.getsize(dest), "byte")


for nome, chiavi in CLIP.items():
    rig, mesh, act = costruisci(nome, chiavi)
    misura(rig, chiavi, nome)
    ultimo = chiavi[-1][0]
    passo = 2
    frames = list(range(0, ultimo + 1, passo))
    renderizza(rig, mesh, nome, frames)
    ## il muso frame per frame: la chiusura dura 3 frame, a passo 2 se ne
    ## vedrebbe uno solo e non si potrebbe giudicare lo scatto
    renderizza(rig, mesh, nome + "_muso", list(range(0, ultimo + 1)), testa_sola=True)
    renderizza(rig, mesh, nome + "_34", list(range(14, min(ultimo, 34) + 1)), testa_sola='34')
    print("CONTATTI (s):", CONTATTI[nome])
    esporta(rig, nome)
print("\nFATTO")
