"""IL COLLAUDO DI UN CAMPIONE A GLB FATTO: topologia, pesi per regione, stiramenti nelle pose
estreme, e un foglio da guardare.

    blender -b --factory-startup --python arcanium/tools/collaudo_campione.py -- <campione.glb> <cartella_uscita>         [--blend lavorazione/blender/campione_<nome>_arp.blend] [--senza-foto]

L'utente, 2026-11-12: dopo ogni creazione su Tripo «una passata di verifica su Blender che
copre il 100% della mesh generata dall'AI e verifica strappi, aperture», e dopo il rig e i
pesi «ogni osso copra solo la parte di corpo che deve effettivamente coprire». Il collaudo
guarda TUTTE le mesh del GLB (il corpo e ogni `Stoffa<N>`), non un campione di vertici:
1. TOPOLOGIA (ispeziona_topologia di monta_campione.py), sul .blend del montaggio:
   spigoli non-manifold, farfalle, vertici e spigoli volanti, facce degeneri, normali
   incoerenti, n-gon; i BUCHI veri (anelli di bordo sotto i 5 cm) e, a parte, gli ORLI
   dei capi (le maniche, l'orlo del mantello: i capi di Tripo sono strati aperti);
2. PESI (verifica_pesi.py): ossa lontane nella gerarchia dal dominante, ossa del lato
   opposto;
3. STIRAMENTI: le pose estreme delle clip nostre (POSE), ogni spigolo confrontato con la
   sua lunghezza a riposo; oltre `STIRO` volte e' uno strappo;
4. un FOGLIO per posa, da destra, da sinistra, davanti e di tre quarti, senza scarto delle
   facce posteriori: un interno che si vede e' scuro.

L'ultima riga e' l'esito: `COLLAUDO <file>: OK` o `COLLAUDO <file>: DA RIVEDERE (...)`.
"""
import os
import sys
import bpy
from mathutils import Vector

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CC = RADICE + "lavorazione/cascadeur/"
## Le pose estreme: (nome, clip esportata da Cascadeur sullo scheletro ARP, frame).
POSE = [
    ("gambe_larghe", CC + "edran/colpo_scudo/edran_colpo_scudo_fin.glb", 8),
    ("raccolto", CC + "edran/rotolata/edran_rotolata_mg.glb", 13),
    ("atterraggio", CC + "edran/salto_indietro/edran_salto_indietro_mg.glb", 12),
    ("sprint", CC + "edran/sprint/edran_sprint_mg.glb", 8),
]
STIRO = 2.5
SPIGOLO_MIN = 0.02  # m: sotto, uno stiramento non si vede

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verifica_pesi  # noqa: E402

a = sys.argv[sys.argv.index("--") + 1:]
GLB, USCITA = a[0], a[1]
FOTO = "--senza-foto" not in a
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
        buchi = [an for an in t["anelli"] if an[1] < BUCO_VERO]
        orli = sorted((an for an in t["anelli"] if an[1] >= BUCO_VERO), key=lambda an: -an[1])
        print("  %s: %d vertici, %d gusci; buchi veri (< %d cm) %d; orli %d, i piu' lunghi (m) %s; %s" % (
            o.name, len(o.data.vertices), t["gusci"], BUCO_VERO * 100, len(buchi), len(orli),
            [an[1] for an in orli[:6]], gravi or "nessuno spigolo storto"))
        if gravi:
            problemi.append("topologia %s %s" % (o.name, gravi))
        if buchi:
            problemi.append("%s: %d buchi veri" % (o.name, len(buchi)))
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
for nome, clip, frame in POSE:
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
    dg = bpy.context.evaluated_depsgraph_get()
    riga = []
    for o in mesh:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        co = [v.co.copy() for v in me.vertices]
        ev.to_mesh_clear()
        r = riposo[o.name]
        stirati = 0
        peggio = 1.0
        for e in o.data.edges:
            i, j = e.vertices
            l0 = (r[i] - r[j]).length
            l1 = (co[i] - co[j]).length
            if l0 > 1e-5 and l1 > SPIGOLO_MIN:
                k = l1 / l0
                peggio = max(peggio, k)
                stirati += k > STIRO
        riga.append("%s %d (fino a %.1fx)" % (o.name, stirati, peggio))
        if stirati:
            problemi.append("%s in %s: %d spigoli stirati" % (o.name, nome, stirati))
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
    try:
        from PIL import Image
    except ImportError:
        Image = None
    if Image is not None:
        righe = [n for n, _, _ in POSE if os.path.exists(os.path.join(USCITA, "%s_destra.png" % n))]
        lati = ("destra", "sinistra", "davanti", "tre_quarti")
        foglio = Image.new("RGB", (260 * 4, 340 * len(righe)))
        for i, n in enumerate(righe):
            for j, l in enumerate(lati):
                foglio.paste(Image.open(os.path.join(USCITA, "%s_%s.png" % (n, l))).convert("RGB").resize((260, 340)),
                             (j * 260, i * 340))
        foglio.save(os.path.join(USCITA, "foglio.png"))

esito = "OK" if not problemi else "DA RIVEDERE (%s)" % "; ".join(problemi)
print("COLLAUDO %s: %s" % (os.path.basename(GLB), esito))
