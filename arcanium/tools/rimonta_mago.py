"""Rimonta il MAGO SYLVORN dal suo FBX di Tripo P2 con la catena dei campioni
(monta_campione.py: topologia ispezionata e saldata prima del rig), poi le due
stoffe e la pulizia dei pesi. Richiesta dell'utente del 2026-10-28: il Mago
montato a settembre si strappava in movimento (prova_movimento.gd).

Dentro Blender, dal ponte:
    python arcanium/tools/ponte_blender.py arcanium/tools/rimonta_mago.py

⚠️ Dopo `controlla_e_ripara` le giunzioni a T fra gli strati sono saldate e
`separa_stoffe` trova solo il manto: la veste bianca e' un guscio a se' del
corpo e si prende indicandola con un punto (davanti, a meta' gamba).
"""
exec(open("C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/arcanium/tools/monta_campione.py", encoding="utf-8").read())
import bpy
R = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
GONNA_RAGGIO = 0.10
ns = {"__name__": "monta_mago", "P": P}
exec(compile(open(P, encoding="utf-8").read(), P, "exec"), ns)
ns["DIR_SYLVORN"] = R + "assets/characters/enemies/consumati_sylvorn/"
ns["DIR_SORGENTI"] = R + "lavorazione/sorgenti/consumati_sylvorn/fbx_p2/"
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
me = ns["prepara"]("sylvorn_mago_p2", altezza=1.87)
controlla_e_ripara(me.name)
ns["rigga"]()
ns["travasa"](affila=False, falde=False, gabbia=True)
ns["separa_stoffe"](bpy.data.objects["FanteSylvorn"])
bpy.data.objects["Stoffa1"].name = "MantoTmp"
ns["separa_stoffe"](bpy.data.objects["FanteSylvorn"], presso=(0.0, -0.33, 0.6))
veste = bpy.data.objects["Stoffa1"]
veste.name = veste.data.name = "Stoffa2"
manto = bpy.data.objects["MantoTmp"]
manto.name = manto.data.name = "Stoffa1"
s1, s2 = bpy.data.objects["Stoffa1"], bpy.data.objects["Stoffa2"]
ns["maschera_stoffa"](s1, alto=1.20, basso=0.85, dietro=0.12)
ns["maschera_stoffa"](s2, alto=0.95, basso=0.65, coperture=(s1, s2))
ns["pesi_lontani"]([bpy.data.objects[n] for n in ("FanteSylvorn", "Stoffa1")])
## La VESTE non segue mai le braccia: le falde ai fianchi, accanto alle mani
## a riposo, salivano con le braccia alzate come ali di gabbiano (2026-10-28).
ns["pesi_lontani"]([s2], portate={("Clavicle", "Shoulder", "Elbow", "Hand"): (0.0, 0.02),
                                   ("Finger", "Thumb"): (0.0, 0.02)})
## Le maniche larghe, stoffa a se' appesa al braccio (2026-10-28).
## La veste non si tende fra le ginocchia nell'accovacciata delle Radici:
## la stoffa lontana dall'asse della gamba passa al bacino (2026-10-28).
_g = {"__name__": "gonna"}
exec(compile(open(R + "arcanium/tools/monta_campione.py", encoding="utf-8").read(), "monta_campione.py", "exec"), _g)
_g["pesi_gonna"](nome_mesh="Stoffa2", raggio=GONNA_RAGGIO)
ns["separa_maniche"](s1)
bpy.ops.wm.save_as_mainfile(filepath=R + "lavorazione/mago_rimontato.blend")
p = ns["esporta_glb"](ns["DIR_SYLVORN"] + "sylvorn_mago_rigged.glb")
ns["verifica_glb"](p)
print("FATTO", p)
