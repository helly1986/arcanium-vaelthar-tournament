# -*- coding: utf-8 -*-
"""Rimette al protagonista la densita' piena, senza toccargli le ossa.

Il corpo in gioco era stato decimato da 119.752 a 43.000 triangoli — il 64% in
meno — prendendo come riferimento il protagonista VECCHIO (`protagonist_fist`,
31.161 tri, 24 ossa), che pero' non era l'hero. A vista si pagava in cuciture
sulle ginocchia, cosce sfaccettate e dita sfrangiate. Misurato: lo scarto di
POSIZIONE fra le due mesh e' di 0,04 mm mediani (massimo 0,20), quindi la
decimazione non ha spostato la superficie — ha tolto risoluzione alla NORMALE,
che e' esattamente cio' che si vede.

    blender --background --factory-startup --python arcanium/tools/riporta_densita_corpo.py

## Perche' NON si passa dal blend ARP

Il rig del giocatore vive due volte: 344 ossa nel blend di lavoro (rig ARP con
i controllori) e 61 nel GLB esportato per Godot. Rifare l'export dal blend
significherebbe ripercorrere il rinomina-per-Godot e sperare che ne esca la
stessa armatura. Qui invece l'armatura si prende GIA' FATTA dal GLB che il
gioco usa, e si sostituisce solo la mesh:

  - le 61 ossa restano bit-per-bit quelle di prima, quindi la posa di riposo
    non cambia di un millesimo e OGNI clip esistente continua a cadere giusta —
    comprese quelle nuove animate in Cascadeur sul corpo vecchio;
  - `protagonista_v4.glb.import` resta valido cosi' com'e': e' agganciato al
    percorso `BaseArmature/Skeleton3D` con la mappa identita' e il `rest_fixer`
    acceso, e nessuno di quei nomi si muove.

## Perche' i pesi si possono trasferire

Il donatore e' il corpo NUDO decimato, cioe' lo stesso identico personaggio a
meno di 0,2 mm — non una figura vestita. Il trasferimento per vicinanza da un
donatore incappucciato e' la trappola gia' pagata due volte (spalle pesate sul
mantello, testa sul cappuccio): qui non si applica, ed e' il motivo per cui
questa scorciatoia e' lecita mentre quella non lo era.

⚠️ Le UV del corpo denso sono state confrontate con quelle del decimato prima
di scrivere questo: scarto mediano 0,00008 in unita' UV, cioe' 0,001 passi
della mappa di ID a 1/8. La maschera che cancella la pelle sotto l'armatura
legge in UV, e un taglio UV diverso l'avrebbe rotta in silenzio.
"""
import bpy, os, random
from mathutils import Vector
from mathutils.bvhtree import BVHTree

RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")).replace("\\", "/")
GIOCO = RADICE + "/assets/characters/base_body/protagonista_v4.glb"
DENSO = RADICE + "/assets/characters/base_body/protagonista_v4_meshy6.glb"
DEST = GIOCO

SALDATURA = 0.0001      # come da pipeline: le mesh Meshy arrivano spezzate sulle UV
PESI_PER_VERTICE = 4    # il limite che glTF applica comunque: meglio deciderlo qui

# ─── 1. Il corpo che il gioco usa oggi ───────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GIOCO)

basso = bpy.data.objects["Protagonista"]
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
print("armatura:", rig.name, "| ossa:", len(rig.data.bones))
print("mesh vecchia:", len(basso.data.vertices), "vert,",
      sum(len(p.vertices) - 2 for p in basso.data.polygons), "tri,",
      len(basso.vertex_groups), "gruppi")
materiali = list(basso.data.materials)
modificatori = [(m.type, m.name) for m in basso.modifiers]

# ─── 2. Il corpo denso ───────────────────────────────────────────────────────
prima = set(bpy.data.objects.keys())
bpy.ops.import_scene.gltf(filepath=DENSO)
alto = next(bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - prima
            if bpy.data.objects[n].type == 'MESH')
print("mesh densa:", len(alto.data.vertices), "vert,",
      sum(len(p.vertices) - 2 for p in alto.data.polygons), "tri")


def bbox(ob):
    co = [ob.matrix_world @ v.co for v in ob.data.vertices]
    return (Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co))),
            Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co))))


# ⚠️ Il corpo di Meshy e' centrato sull'ORIGINE, quello in gioco poggia a terra:
# 0,95 di scarto in Z. Senza rimetterli in registro i pesi si trasferirebbero
# dal punto sbagliato — e la misura direbbe che sono corpi diversi.
bmn, _bmx = bbox(basso)
amn, _amx = bbox(alto)
scarto = bmn - amn
alto.location = alto.location + scarto
bpy.context.view_layer.update()
print("allineamento applicato:", [round(v, 5) for v in scarto])
amn, amx = bbox(alto)
assert (amn - bmn).length < 1e-4, "allineamento fallito"

bpy.ops.object.select_all(action='DESELECT')
alto.select_set(True)
bpy.context.view_layer.objects.active = alto
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ─── 3. Saldatura ────────────────────────────────────────────────────────────
# ⚠️ Non e' facoltativa: le mesh Meshy arrivano coi vertici spezzati sulle
# cuciture UV. Senza saldare, ogni vertice doppio riceve i pesi due volte e la
# mesh si apre sulle cuciture appena l'osso ruota.
v_prima = len(alto.data.vertices)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=SALDATURA)
bpy.ops.object.mode_set(mode='OBJECT')
print("saldatura: %d -> %d vertici (%d facce)"
      % (v_prima, len(alto.data.vertices), len(alto.data.polygons)))

# ⚠️⚠️ Le NORMALI CUSTOM vanno buttate DOPO la saldatura, non prima e non mai.
# Il GLB di Meshy arriva con normali split per loop; fondendo i vertici delle
# cuciture, i loop sopravvissuti si portano dietro normali incoerenti fra loro e
# la pelle si copre di un brulichio fine su tutto il corpo. Non e' un difetto
# della mesh densa: la stessa geometria, con le normali ricalcolate, e' liscia e
# piu' nitida del corpo decimato. Verificato affiancando quattro versioni —
# grezza, saldata-con-normali, saldata-e-ripulita — e guardandole.
if alto.data.has_custom_normals:
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
for p in alto.data.polygons:
    p.use_smooth = True
print("normali custom dopo la pulizia:", alto.data.has_custom_normals)

# ─── 4. Materiale: lo STESSO datablock, non una copia ────────────────────────
# Cosi' texture e immagini sono esattamente quelle che il gioco gia' importa.
alto.data.materials.clear()
for m in materiali:
    alto.data.materials.append(m)
print("materiali:", [m.name for m in alto.data.materials])

# ─── 5. I pesi, dal corpo decimato a quello denso ────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
alto.select_set(True)
basso.select_set(True)
bpy.context.view_layer.objects.active = basso   # ATTIVO = sorgente
bpy.ops.object.data_transfer(
    data_type='VGROUP_WEIGHTS',
    use_create=True,
    vert_mapping='POLYINTERP_NEAREST',
    layers_select_src='ALL',
    layers_select_dst='NAME',
    mix_mode='REPLACE')
print("gruppi trasferiti:", len(alto.vertex_groups))
assert len(alto.vertex_groups) == len(basso.vertex_groups), "gruppi persi nel trasferimento"

bpy.ops.object.select_all(action='DESELECT')
alto.select_set(True)
bpy.context.view_layer.objects.active = alto
# ⚠️ glTF tiene 4 influenze per vertice e taglia le altre SENZA rinormalizzare:
# meglio tagliare qui e normalizzare dopo, o il peso totale scende sotto 1 e le
# ossa "tirano" meno del dovuto proprio dove le influenze erano tante (ascelle).
bpy.ops.object.vertex_group_limit_total(limit=PESI_PER_VERTICE)
bpy.ops.object.vertex_group_normalize_all(lock_active=False)

# ─── 6. Prende il posto del vecchio ──────────────────────────────────────────
nome = basso.name
matrice = basso.matrix_world.copy()
# ⚠️ Il datablock della mesh vecchia va cancellato PRIMA di riusarne il nome, o
# Blender battezza la nuova `Protagonista.001` e il GLB esce con quel nome.
# Non e' cosmetica: `player_dawnkeep_v4.tscn` sovrascrive il nodo
# `protagonist/BaseArmature/GeneralSkeleton/Protagonista` per applicargli
# `material_override = corpo_mask`, cioe' la maschera che cancella la pelle
# sotto l'armatura. Con un nome diverso quell'override si perde e la maschera
# smette di funzionare senza che niente lo dica.
mesh_vecchia = basso.data
bpy.data.objects.remove(basso, do_unlink=True)
bpy.data.meshes.remove(mesh_vecchia)
alto.name = nome
alto.data.name = nome
assert alto.name == nome and alto.data.name == nome, \
    "il nome non e' quello atteso: %s / %s" % (alto.name, alto.data.name)
alto.matrix_world = matrice
alto.parent = rig
alto.matrix_parent_inverse = rig.matrix_world.inverted()

for m in list(alto.modifiers):
    alto.modifiers.remove(m)
mod = alto.modifiers.new("Armature", 'ARMATURE')
mod.object = rig
print("modificatori vecchi:", modificatori, "-> nuovi:", [m.type for m in alto.modifiers])

for p in alto.data.polygons:
    p.use_smooth = True

bpy.context.view_layer.update()

# ─── 7. I due collaudi obbligatori, PRIMA dell'export ────────────────────────
print("=== COLLAUDO 1: ogni osso deformante e' dentro la mesh? ===")
# ⚠️ BVH ricostruito da zero: `closest_point_on_mesh` restituisce risultati
# stantii dopo che i pesi sono cambiati, e ha gia' dichiarato fuori 21 ossa che
# erano dentro. Il segnale che era la sonda e non l'asset fu l'ASIMMETRIA.
depsgraph = bpy.context.evaluated_depsgraph_get()
bvh = BVHTree.FromObject(alto, depsgraph)
inv = alto.matrix_world.inverted()
altezza = bbox(alto)[1].z - bbox(alto)[0].z

# ⚠️ Avere un gruppo di vertici non vuol dire deformare: bisogna che ci sia del
# PESO dentro. `Root` ha il suo gruppo ed e' vuoto — sta a terra fra i piedi,
# fuori dalla carne per costruzione, ed e' l'osso del root motion. Metterlo nel
# collaudo lo fa fallire su un asset sano: e' il collaudo a essere sbagliato.
peso_per_gruppo = {}
for v in alto.data.vertices:
    for g in v.groups:
        if g.weight > 0.0:
            peso_per_gruppo[g.group] = peso_per_gruppo.get(g.group, 0.0) + g.weight
deformanti = {alto.vertex_groups[i].name for i in peso_per_gruppo}
vuoti = sorted({g.name for g in alto.vertex_groups} - deformanti)
print("  gruppi VUOTI (esclusi dal collaudo):", vuoti)

fuori = []
margini = []
for b in rig.data.bones:
    if b.name not in deformanti:
        continue          # non porta peso: non deforma nulla
    testa = inv @ (rig.matrix_world @ b.head_local)
    loc, nor, idx, d = bvh.find_nearest(testa)
    if loc is None:
        continue
    dentro = -(testa - loc).dot(nor)
    margini.append((dentro / altezza, b.name))
    if dentro <= 0.0:
        fuori.append(b.name)
margini.sort()
print("  ossa deformanti controllate: %d | FUORI: %d" % (len(margini), len(fuori)))
if fuori:
    print("  fuori:", fuori)
print("  margine minimo: %.4f%% dell'altezza (%s)" % (margini[0][0] * 100, margini[0][1]))

print("=== COLLAUDO 2: il vertice piu' esterno del braccio su che osso pesa? ===")
# Se esce un piede invece della punta del dito, i pesi sono sbagliati: il
# binding "riesce" comunque e non da' nessun segnale d'allarme.
co = [(alto.matrix_world @ v.co, v) for v in alto.data.vertices]
piu_a_sinistra = max(co, key=lambda t: t[0].x)[1]
pesi = sorted(((g.weight, alto.vertex_groups[g.group].name) for g in piu_a_sinistra.groups),
              reverse=True)
print("  vertice x=%.4f -> %s" % ((alto.matrix_world @ piu_a_sinistra.co).x,
                                  [(n, round(w, 4)) for w, n in pesi[:3]]))
osso_atteso = pesi[0][1] if pesi else "?"
print("  osso dominante:", osso_atteso)

somme = [sum(g.weight for g in v.groups) for v in alto.data.vertices]
print("  somma dei pesi: min %.4f  max %.4f  (deve stare a 1)"
      % (min(somme), max(somme)))
senza_peso = sum(1 for s in somme if s < 1e-6)
print("  vertici senza peso:", senza_peso)

assert not fuori, "ci sono ossa fuori dalla mesh: non si esporta"
assert senza_peso == 0, "ci sono vertici senza peso: non si esporta"
assert "Middle" in osso_atteso or "middle" in osso_atteso, \
    "il vertice piu' esterno del braccio non pesa su un dito medio: pesi sbagliati"

# ─── 8. Export ───────────────────────────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    if o.type in ('MESH', 'ARMATURE'):
        o.hide_set(False)
        o.hide_viewport = False
        o.hide_render = False
        o.select_set(True)
bpy.context.view_layer.objects.active = rig

bpy.ops.export_scene.gltf(
    filepath=DEST, export_format='GLB', use_selection=True,
    export_animations=False, export_yup=True, export_apply=False,
    export_skins=True, export_all_influences=False)
print("ESPORTATO:", DEST, os.path.getsize(DEST), "byte")
