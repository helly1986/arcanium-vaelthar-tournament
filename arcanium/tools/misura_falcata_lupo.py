# -*- coding: utf-8 -*-
"""Quanto avanza il lupo in `walk` e in `run`, misurato dalle zampe.

Le clip sono animate SUL POSTO: il corpo non si sposta, e' il terreno che
dovrebbe scorrere sotto. La velocita' vera si legge dalle zampe PIANTATE — una
zampa a contatto col suolo scivola all'indietro rispetto al bacino esattamente
alla velocita' con cui l'animale avanza. Quello e' il numero da mettere nel root
motion, e non va inventato: un valore a occhio produce il pattinaggio, cioe' le
zampe che strisciano perche' l'avanzamento non corrisponde alla falcata.

    blender --background --factory-startup --python arcanium/tools/misura_falcata_lupo.py
"""
import bpy, os
from statistics import median

RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")).replace("\\", "/")
GLB = RADICE + "/assets/characters/enemies/wolf_animated.glb"
CLIP = ("walk", "run")
FPS = 30.0

## Quota sotto cui una zampa si considera a terra, in frazione della sua
## escursione verticale. 0.25 = il quarto piu' basso della sua corsa.
##
## ⚠️ Si prova con PIU' soglie, e la misura vale solo se il numero non cambia.
## Una velocita' che dipende dalla soglia scelta e' un numero inventato con piu'
## passaggi in mezzo. In `run` le zampe stanno in aria quasi sempre e con la
## soglia stretta restava 1 solo campione per zampa, con anteriori e posteriori
## in disaccordo del 60%.
SOGLIE = (0.20, 0.25, 0.30, 0.40, 0.50)

## `leap` NON si misura cosi': non e' locomozione ciclica, il corpo e' in aria e
## le quattro zampe danno risultati di SEGNO OPPOSTO (+0,49 contro -0,73). Il suo
## spostamento va preso dalla traiettoria del bacino, non dallo scivolamento.

bpy.ops.wm.read_factory_settings(use_empty=True)

# ⚠️⚠️ L'fps va messo PRIMA dell'import. Il glTF tiene i tempi in SECONDI e
# l'importatore li converte in frame con l'fps della scena, che di default e'
# 24. Qui c'era `sc.render.fps = 30` DOPO l'import: i frame erano spaziati di
# 1/24 di secondo e venivano contati come 1/30, e ogni velocita' usciva
# sovrastimata del 25% (0,460 m/s invece di 0,368). E' lo stesso errore che ha
# accorciato la clip di evocazione — cambia solo il verso.
#
# La FALCATA per ciclo, invece, non dipende dall'fps: e' spazio, non velocita'.
# Per questo e' lei, e non la velocita', il numero che si porta nell'export.
bpy.context.scene.render.fps = int(FPS)
bpy.context.scene.render.fps_base = 1.0

bpy.ops.import_scene.gltf(filepath=GLB)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

# Le zampe sono le FOGLIE delle catene delle gambe: si ricavano dalla
# gerarchia invece di indovinarle dai nomi.
def e_foglia(b):
    return len(b.children) == 0


zampe = [b.name for b in rig.data.bones
         if e_foglia(b) and ("leg" in b.name.lower())]
print("zampe (foglie delle catene):", zampe)
assert len(zampe) == 4, "attese 4 zampe, trovate %d" % len(zampe)

sc = bpy.context.scene
sc.render.fps = int(FPS)

print()
for nome in CLIP:
    az = bpy.data.actions.get(nome)
    if az is None:
        print("%-6s MANCA" % nome)
        continue
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = az
    if az.slots:
        rig.animation_data.action_slot = az.slots[0]

    f0, f1 = (int(round(v)) for v in az.frame_range)
    quadri = list(range(f0, f1 + 1))
    pos = {z: [] for z in zampe}
    bacino = []
    for f in quadri:
        sc.frame_set(f)
        bpy.context.view_layer.update()
        for z in zampe:
            pos[z].append(rig.matrix_world @ rig.pose.bones[z].head.copy())
        bacino.append(rig.matrix_world @ rig.pose.bones["Hips"].head.copy())

    # ⚠️ Lo scivolamento va misurato RISPETTO AL BACINO, non in coordinate
    # assolute: se il bacino oscilla avanti e indietro (e oscilla), la zampa
    # ferma a terra sembra muoversi e il numero esce gonfiato.
    rel = {z: [pos[z][i] - bacino[i] for i in range(len(quadri))] for z in zampe}

    durata = (f1 - f0) / FPS
    print("%-6s  %4.2f s (%d frame)  escursione verticale zampe %.4f m"
          % (nome, durata, len(quadri),
             max(max(p.z for p in pos[z]) - min(p.z for p in pos[z]) for z in zampe)))

    ## ⚠️ Due riferimenti a confronto, e vince quello su cui le quattro zampe
    ## si mettono d'accordo. Rapportare al BACINO toglie l'oscillazione
    ## dell'anca ma presume un tronco RIGIDO — falso in un galoppo, dove la
    ## schiena flette e anteriori e posteriori escono diversi del 48%.
    ## In ASSOLUTO il conto e' quello fisico: in una clip animata sul posto, la
    ## zampa a terra scorre all'indietro esattamente alla velocita' con cui il
    ## corpo dovrebbe avanzare.
    for etichetta, tracce in (("assoluto", pos), ("dal bacino", rel)):
        righe = []
        for soglia in SOGLIE:
            per_zampa = []
            campioni = 0
            for z in zampe:
                zs = [p.z for p in pos[z]]
                lo, hi = min(zs), max(zs)
                limite = lo + soglia * (hi - lo)
                appoggi = {i for i, v in enumerate(zs) if v <= limite}
                passi = [abs((tracce[z][i + 1] - tracce[z][i]).y)
                         for i in sorted(appoggi)
                         if i + 1 < len(quadri) and (i + 1) in appoggi]
                if passi:
                    per_zampa.append(median(passi) * FPS)
                    campioni += len(passi)
            if not per_zampa:
                continue
            v = median(per_zampa)
            disp = (max(per_zampa) - min(per_zampa)) / v * 100.0
            righe.append((soglia, v, disp, per_zampa, campioni))
        if not righe:
            continue
        vs = [r[1] for r in righe]
        print("   [%s]  stabilita' fra soglie: %.3f - %.3f m/s (%.0f%%)"
              % (etichetta, min(vs), max(vs), (max(vs) - min(vs)) / median(vs) * 100))
        for soglia, v, disp, per_zampa, campioni in righe:
            print("      soglia %.2f -> %.3f m/s  falcata %.3f m  zampe [%s]"
                  "  scarto %.0f%%  (%d camp.)"
                  % (soglia, v, v * durata,
                     " ".join("%.3f" % x for x in per_zampa), disp, campioni))
