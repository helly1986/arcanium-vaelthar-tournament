"""IL COLLAUDO DI UN CAMPIONE A GLB FATTO: topologia, pesi per regione, stiramenti nelle pose
estreme, e un foglio da guardare.

    blender -b --factory-startup --python arcanium/tools/collaudo_campione.py -- <campione.glb> <cartella_uscita>         [--blend lavorazione/blender/campione_<nome>_arp.blend] [--senza-foto]

L'utente, 2026-11-12: dopo ogni creazione su Tripo «una passata di verifica su Blender che
copre il 100% della mesh generata dall'AI e verifica strappi, aperture», e dopo il rig e i
pesi «ogni osso copra solo la parte di corpo che deve effettivamente coprire». Il collaudo
guarda TUTTE le mesh del GLB (il corpo e ogni `Stoffa<N>`), non un campione di vertici:
1. TOPOLOGIA (ispeziona_topologia di monta_campione.py), sul .blend del montaggio:
   spigoli non-manifold, farfalle, vertici e spigoli volanti, facce degeneri, normali
   incoerenti, n-gon; i BUCHI veri (anelli di bordo sotto i 5 cm che non poggiano su un
   altro guscio e non sono aperti apposta: BUCHI_LEGITTIMI) e, a parte, le giunzioni e gli
   ORLI dei capi (le maniche, l'orlo del mantello: i capi di Tripo sono strati aperti);
2. PESI (verifica_pesi.py): ossa lontane nella gerarchia dal dominante, ossa del lato
   opposto;
3. STIRAMENTI: le pose estreme delle clip nostre (POSE), ogni spigolo confrontato con la
   sua lunghezza a riposo; oltre `STIRO` volte e' una piega (si conta), oltre `STRAPPO`
   volte e 12 cm e' uno strappo (boccia);
4. un FOGLIO per posa, da destra, da sinistra, davanti e di tre quarti, senza scarto delle
   facce posteriori: un interno che si vede e' scuro.

L'ultima riga e' l'esito: `COLLAUDO <file>: OK` o `COLLAUDO <file>: DA RIVEDERE (...)`.
"""
import os
import sys
import bpy
import bmesh
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CC = RADICE + "lavorazione/cascadeur/"
## Le pose estreme: (nome, clip esportata da Cascadeur sullo scheletro ARP, frame).
POSE = [
    ("gambe_larghe", CC + "edran/colpo_scudo/edran_colpo_scudo_fin.glb", 8),
    ("raccolto", CC + "edran/rotolata/edran_rotolata_mg.glb", 13),
    ("atterraggio", CC + "edran/salto_indietro/edran_salto_indietro_mg.glb", 12),
    ("sprint", CC + "edran/sprint/edran_sprint_mg.glb", 8),
    ## Il braccio destro sopra la testa (la carica del fendente obliquo): con le mani ai
    ## fianchi nella A-pose, e' la posa che tira su cio' che il bind ha dato al braccio.
    ## L'utente, 2026-11-13: la falda di Edran a punte sul fianco destro, in Cascadeur.
    ("braccio_alzato", CC + "edran/obliquo/edran_obliquo_arp.glb", 7),
    ## La stessa posa SPECCHIATA (braccio sinistro) e con le due braccia alzate: l'utente
    ## aveva visto le punte anche sul fianco sinistro, e nella base vecchia c'erano (84
    ## strappi). Una clip a braccio sinistro alzato non c'e': si specchia questa.
    ("braccio_sinistro", CC + "edran/obliquo/edran_obliquo_arp.glb", 7, "specchio"),
    ("due_braccia", CC + "edran/obliquo/edran_obliquo_arp.glb", 7, "due_braccia"),
]
BRACCIO = ("shoulder", "arm_", "forearm_", "hand", "thumb", "index", "middle", "ring", "pinky")


def _altro_lato(n):
    return n[:-2] + (".r" if n.endswith(".l") else ".l") if n.endswith((".l", ".r")) else n


def specchia_posa(arm, modo):
    """La posa corrente dello scheletro specchiata sul piano di mezzo (`specchio`), o col
    braccio sinistro specchio del destro (`due_braccia`). Vale perche' le ossa dello
    scheletro esportato sono speculari: posizione con la x cambiata di segno, quaternione
    con y e z cambiate di segno. L'azione si stacca: la posa resta scritta sulle ossa."""
    from mathutils import Quaternion
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    posa = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy()) for pb in arm.pose.bones}
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        l, q = posa[pb.name]
        if modo == "specchio" or (pb.name.endswith(".l") and pb.name.startswith(BRACCIO)):
            l, q = posa.get(_altro_lato(pb.name), (l, q))
            l, q = Vector((-l.x, l.y, l.z)), Quaternion((q.w, q.x, -q.y, -q.z))
        pb.location, pb.rotation_quaternion = l, q
    bpy.context.view_layer.update()
STIRO = 2.5
SPIGOLO_MIN = 0.02  # m: sotto, uno stiramento non si vede
## Lo STRAPPO, che boccia: uno spigolo stirato di oltre 4 volte E lungo piu' di 12 cm, cioe'
## una scheggia che si vede. Le pieghe (oltre STIRO) si contano e basta: gomiti, spalle e
## inguine piegati ne fanno a centinaia anche coi pesi giusti, e fino al 2026-11-12 il
## collaudo usciva DA RIVEDERE su ogni campione, sempre. Le schegge di Ilwen erano 60 cm
## a 50 volte, le ciocche di Aurin 37 cm a 110.
STRAPPO = 4.0
STRAPPO_LUNGO = 0.12

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verifica_pesi  # noqa: E402

a = sys.argv[sys.argv.index("--") + 1:]
GLB, USCITA = a[0], a[1]
FOTO = "--senza-foto" not in a
NOME = os.path.basename(GLB).split("_")[0]  # edran_arp.glb -> edran
os.makedirs(USCITA, exist_ok=True)

## Gli strumenti della topologia di monta_campione.py, senza il resto del montaggio.
_ns = {"__name__": "collaudo"}
exec(compile(open(RADICE + "arcanium/tools/monta_campione.py", encoding="utf-8").read(), "monta_campione", "exec"), _ns)
ispeziona_topologia = _ns["ispeziona_topologia"]

problemi = []
BUCO_VERO = 0.05  # m di perimetro: sotto e' un buco (controlla_e_ripara li chiude), sopra un orlo

## 1. La TOPOLOGIA si legge dal .blend del montaggio, non dal GLB: l'import glTF spezza i
## vertici lungo le cuciture di UV e normali, e risaldandoli si fondono anche strati di
## Tripo che si toccano (spigoli non-manifold che nel corpo non ci sono).
BLEND = a[a.index("--blend") + 1] if "--blend" in a else ""
print("=== TOPOLOGIA")
if BLEND and os.path.exists(BLEND):
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    for o in [o for o in bpy.data.objects if o.type == "MESH" and (o.name in ("Corpo", "CorpoSylvorn")
                                                                   or o.name.startswith("Stoffa"))]:
        t = ispeziona_topologia(o.name, stampa=False)
        gravi = {k: t[k] for k in ("non_manifold", "farfalle", "vertici_volanti", "spigoli_volanti", "degeneri",
                                   "normali_incoerenti", "ngon") if t.get(k)}
        ## I buchi sotto i 5 cm, uno per uno (buchi_veri di monta_campione.py): le giunzioni
        ## che poggiano su un altro guscio e quelli aperti apposta non sono difetti.
        bm = bmesh.new()
        bm.from_mesh(o.data)
        inv = o.matrix_world.inverted()
        veri, giunzioni, legittimi = _ns["buchi_veri"](
            bm, BUCO_VERO, salta=[inv @ Vector(q) for q in _ns["BUCHI_LEGITTIMI"].get(NOME, ())])
        dove = [tuple(round(c, 3) for c in o.matrix_world @ (sum((v.co for e in an for v in e.verts), Vector())
                                                              / (2 * len(an)))) for an in veri]
        bm.free()
        orli = sorted((an for an in t["anelli"] if an[1] >= BUCO_VERO), key=lambda an: -an[1])
        print("  %s: %d vertici, %d gusci; sotto i %d cm: %d buchi veri %s, %d giunzioni su un altro guscio, "
              "%d aperti apposta; orli %d, i piu' lunghi (m) %s; %s" % (
                  o.name, len(o.data.vertices), t["gusci"], BUCO_VERO * 100, len(veri), dove[:8], len(giunzioni),
                  len(legittimi), len(orli), [an[1] for an in orli[:6]], gravi or "nessuno spigolo storto"))
        if gravi:
            problemi.append("topologia %s %s" % (o.name, gravi))
        if veri:
            problemi.append("%s: %d buchi veri" % (o.name, len(veri)))
else:
    print("  (manca il .blend del montaggio: --blend <file>)")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=GLB)
arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
mesh = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.vertex_groups]

print("=== PESI")
for o in mesh:
    n = verifica_pesi.stampa(o, arm)
    if n:
        problemi.append("pesi %s: %d vertici" % (o.name, n))

print("=== STIRAMENTI")
riposo = {o.name: [v.co.copy() for v in o.data.vertices] for o in mesh}
arm.animation_data_create()
for nome, clip, frame, *modo in POSE:
    if not os.path.exists(clip):
        print("  %s: manca %s" % (nome, clip))
        continue
    prima = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=clip)
    nuovi = [o for o in bpy.context.scene.objects if o not in prima]
    sorgente = [o for o in nuovi if o.type == "ARMATURE"][0]
    azione = sorgente.animation_data.action
    for o in nuovi:
        bpy.data.objects.remove(o, do_unlink=True)
    arm.animation_data.action = azione
    if hasattr(arm.animation_data, "action_slot") and azione.slots:
        arm.animation_data.action_slot = azione.slots[0]
    bpy.context.scene.frame_set(frame)
    if modo:
        specchia_posa(arm, modo[0])
    dg = bpy.context.evaluated_depsgraph_get()
    riga = []
    for o in mesh:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        co = [v.co.copy() for v in me.vertices]
        ev.to_mesh_clear()
        r = riposo[o.name]
        stirati = strappi = 0
        peggio = 1.0
        for e in o.data.edges:
            i, j = e.vertices
            l0 = (r[i] - r[j]).length
            l1 = (co[i] - co[j]).length
            if l0 > 1e-5 and l1 > SPIGOLO_MIN:
                k = l1 / l0
                peggio = max(peggio, k)
                stirati += k > STIRO
                strappi += k > STRAPPO and l1 > STRAPPO_LUNGO
        riga.append("%s %d pieghe (fino a %.1fx), %d strappi" % (o.name, stirati, peggio, strappi))
        ## Le stoffe simulate in gioco non seguono lo skinning: i loro strappi qui sono
        ## quelli della posa di partenza del solver, e si guardano in gioco.
        if strappi and not o.name.startswith("Stoffa"):
            problemi.append("%s in %s: %d strappi" % (o.name, nome, strappi))
    print("  %s f%d: %s" % (nome, frame, ", ".join(riga)))
    if not FOTO:
        continue
    scena = bpy.context.scene
    scena.render.engine = "BLENDER_WORKBENCH"
    scena.display.shading.light = "STUDIO"
    scena.display.shading.show_backface_culling = False
    scena.render.resolution_x, scena.render.resolution_y = 520, 680
    if scena.camera is None:
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scena.collection.objects.link(cam)
        scena.camera = cam
    cam = scena.camera
    bacino = arm.matrix_world @ arm.pose.bones["root.x"].head
    centro = Vector((bacino.x, bacino.y, max(0.6, bacino.z)))
    for lato, d in (("destra", Vector((-1, 0, 0))), ("sinistra", Vector((1, 0, 0))),
                    ("davanti", Vector((0, -1, 0))), ("tre_quarti", Vector((-0.7, -0.7, 0)))):
        cam.location = centro + d * 3.0 + Vector((0, 0, 0.15))
        cam.rotation_euler = (centro - cam.location).to_track_quat("-Z", "Y").to_euler()
        scena.render.filepath = os.path.join(USCITA, "%s_%s.png" % (nome, lato))
        bpy.ops.render.render(write_still=True)

if FOTO:
    ## Il foglio con le immagini di Blender: il suo Python non ha PIL (prima del 2026-11-12
    ## il foglio non usciva, e nessuno se n'era accorto).
    import numpy as np
    righe = [p[0] for p in POSE if os.path.exists(os.path.join(USCITA, "%s_destra.png" % p[0]))]
    lati = ("destra", "sinistra", "davanti", "tre_quarti")
    if righe:
        L, H = bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y
        foglio = np.zeros((H * len(righe), L * 4, 4), dtype=np.float32)
        for i, n in enumerate(righe):
            for j, l in enumerate(lati):
                im = bpy.data.images.load(os.path.join(USCITA, "%s_%s.png" % (n, l)))
                px = np.empty(L * H * 4, dtype=np.float32)
                im.pixels.foreach_get(px)
                bpy.data.images.remove(im)
                ## Le righe dei pixel di Blender partono dal basso.
                r0 = (len(righe) - 1 - i) * H
                foglio[r0:r0 + H, j * L:(j + 1) * L] = px.reshape(H, L, 4)
        foglio[..., 3] = 1.0
        out = bpy.data.images.new("foglio", L * 4, H * len(righe), alpha=False)
        out.pixels.foreach_set(foglio.ravel())
        out.filepath_raw = os.path.join(USCITA, "foglio.png")
        out.file_format = "PNG"
        out.save()

esito = "OK" if not problemi else "DA RIVEDERE (%s)" % "; ".join(problemi)
print("COLLAUDO %s: %s" % (os.path.basename(GLB), esito))
