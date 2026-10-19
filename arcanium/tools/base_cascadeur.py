# -*- coding: utf-8 -*-
"""La BASE per Cascadeur: un corpo riggato con una clip di partenza, senza texture.

    blender --background --factory-startup --python arcanium/tools/base_cascadeur.py -- \
        <corpo_rigged.glb> <clip.glb|-> <uscita.glb> [NomeClip] [tieni=N] [root_fermo]

`tieni=N` prepara una clip NUOVA da autorare: la posa del PRIMO fotogramma
della clip (di solito l'idle, cosi' la clip nuova si attacca all'idle senza
scatti) tenuta ferma per N frame, a 30 fps, campionata frame per frame. In
Cascadeur `casc_estremi_clip.py` ne lascia solo la prima e l'ultima chiave.
Cosi' e' nata la scena del richiamo del Mago (2026-09-26/30, N=91 = 3 s).
⚠️ Si prepara QUI e non in Cascadeur: riscrivere canale per canale la posa del
frame 0 sull'ultimo frame, dentro Cascadeur, spostava le mani di 50 cm (i
controlli del rig dipendono l'uno dall'altro).

Cascadeur vuole un GLB con scheletro, mesh e una clip da cui partire: qui si
prende il corpo riggato del gioco (es. `sylvorn_soldato_scelto_rigged.glb`),
gli si mette addosso la clip dei nemici indicata (es. `sword_idle_01.glb`:
stesso rig Nephilite, stessi nomi d'osso, quindi l'azione si trasferisce
tale e quale) e si buttano le texture — in Cascadeur servono le forme, non i
pixel, e 34 MB di immagini rallentano ogni scena di lavorazione.

Con `-` al posto della clip si esporta il corpo con la sola clip inerte che
gia' porta (due chiavi sul Root): si parte dalla stance di riposo.

Le armi NON stanno qui: le aggancia `casc_arma_su_osso.py` dentro Cascadeur,
dalla trasformazione del `.tscn` (vedi il suo cappello sul perche').
"""
import bpy, sys, os

argv = sys.argv[sys.argv.index("--") + 1:]
CORPO, CLIP, DST = argv[0], argv[1], argv[2]
NOME_CLIP = argv[3] if len(argv) > 3 and not argv[3].startswith("tieni=") else "Base"
TIENI = 0
ROOT_FERMO = "root_fermo" in argv[3:]
for a in argv[3:]:
    if a.startswith("tieni="):
        TIENI = int(a.split("=", 1)[1])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30          # ⚠️ PRIMA dell'import: il glTF conta in secondi
bpy.ops.import_scene.gltf(filepath=CORPO)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
## Il corpo e' la mesh PESATA sull'armatura (quella con piu' vertici): il GLB
## riggato porta anche l'icosfera che ARP usa come forma dei controlli.
mesh = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.vertices))
print("OGGETTI", [(o.name, o.type, len(o.data.vertices) if o.type == "MESH" else "-") for o in bpy.data.objects])
print("CORPO", arm.name, "ossa", len(arm.data.bones), "| mesh", mesh.name, "verts", len(mesh.data.vertices))

if CLIP != "-":
    prima = set(bpy.data.objects)
    prima_az = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=CLIP)
    nuovi = [o for o in bpy.data.objects if o not in prima]
    azioni = [a for a in bpy.data.actions if a not in prima_az]
    if not azioni:
        raise SystemExit("la clip %s non porta azioni" % CLIP)
    az = azioni[0]
    nomi_corpo = {b.name for b in arm.data.bones}
    canali = set()
    for layer in az.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    dp = fc.data_path
                    if dp.startswith('pose.bones["'):
                        canali.add(dp.split('"')[1])
    fuori = sorted(canali - nomi_corpo)
    print("CLIP", az.name, "ossa animate", len(canali), "| assenti nel corpo:", fuori[:8])
    if not arm.animation_data:
        arm.animation_data_create()
    arm.animation_data.action = az
    ## Blender 5: l'azione ha degli SLOT, e uno scheletro nuovo va legato al
    ## suo, altrimenti l'azione risulta assegnata e non muove niente.
    if az.slots:
        arm.animation_data.action_slot = az.slots[0]
    az.name = NOME_CLIP
    az.use_fake_user = True
    for o in nuovi:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a is not az:
            bpy.data.actions.remove(a)
    print("azione trasferita:", az.name, "frame", az.frame_range[:])

## `root_fermo`: la clip arriva in Cascadeur SUL POSTO, con la traslazione del
## `Root` azzerata. Serve sui rig in cui il nodo dell'armatura e' ruotato (il
## lupo: WolfRig +90 gradi su X, Root -90): Godot consuma la traslazione del
## Root nello spazio dello scheletro come root motion e il lupo avanza;
## Cascadeur la legge come vuole il glTF, ruotata col nodo padre, e il lupo
## SPROFONDA (misurato il 2026-10-09: 38,5 cm in avanti diventati 100 cm verso
## il basso alla scala 2,6). L'avanzamento si rifa' in Cascadeur col corpo, e al
## ritorno lo si riestrae sul Root (bake_root_motion.py).
if ROOT_FERMO and arm.animation_data and arm.animation_data.action:
    azzerate = 0
    for layer in arm.animation_data.action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in list(cb.fcurves):
                    if fc.data_path == 'pose.bones["Root"].location':
                        cb.fcurves.remove(fc)
                        azzerate += 1
    arm.pose.bones["Root"].location = (0.0, 0.0, 0.0)
    print("Root fermo: tolte %d curve di traslazione" % azzerate)

if TIENI and arm.animation_data and arm.animation_data.action:
    ## La posa del primo fotogramma tenuta per TIENI frame, da 0 a TIENI-1.
    az = arm.animation_data.action
    primo = az.frame_range[0]
    curve = 0
    for layer in az.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    v = fc.evaluate(primo)
                    fc.keyframe_points.clear()
                    for f in (0.0, float(TIENI - 1)):
                        fc.keyframe_points.insert(f, v).interpolation = "LINEAR"
                    curve += 1
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = TIENI - 1
    print("posa del frame %d tenuta per %d frame (%d curve)" % (primo, TIENI, curve))

## Si esportano TUTTE le mesh pesate su questo scheletro: dal 2026-09-30 i
## corpi con tessuto hanno anche le mesh `Stoffa*` (docs/05 §4-quater), e
## prendendo solo la piu' grande il Mago arrivava in Cascadeur senza veste.
pesate = [o for o in bpy.data.objects if o.type == "MESH"
          and any(md.type == "ARMATURE" and md.object == arm for md in o.modifiers)]
print("MESH PESATE", [o.name for o in pesate])

## Niente texture: un materiale piatto al posto di quello con le immagini.
for m in {m for o in pesate for m in o.data.materials}:
    if m and m.use_nodes:
        for n in list(m.node_tree.nodes):
            if n.type == "TEX_IMAGE":
                m.node_tree.nodes.remove(n)
for img in list(bpy.data.images):
    bpy.data.images.remove(img)

bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
for o in pesate:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", use_selection=True,
                          export_animations=True, export_skins=True, export_apply=False,
                          export_yup=True, export_image_format="NONE",
                          **({"export_force_sampling": True, "export_frame_range": True,
                              "export_optimize_animation_size": False,
                              "export_optimize_animation_keep_anim_armature": True} if TIENI else {}))
print("EXPORT", DST, os.path.getsize(DST), "byte")
