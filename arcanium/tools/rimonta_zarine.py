"""Rimonta ZARINE TAHVI (Aethon) dal suo FBX di Tripo con la catena dei campioni,
con le MANI APERTE nel travaso (2026-11-01).

Con `mani="presa"` (il default di `travasa`) le dita si cuociono nel riposo
del Nephilite, che ha la destra chiusa sull'impugnatura: la mano di Zarine
restava mezza chiusa, pollice e indice ad anello, e la catena `Finger_*`
(medio, anulare e mignolo insieme) saltava da un dito all'altro. Chiusa poi da
presa_mano.gd sull'asta, pollice e dita bucavano il palmo («la mano e'
esplosa», sul banco della guardia a due mani). Con le mani aperte le dita
restano come le ha modellate Tripo, le guida `guess_fingers` di ARP, e il
pugno lo fa presa_mano.

I passi sono quelli del montaggio del 2026-10-21 (b_tutto2 nello scratchpad di
quella sessione): veste a piombo, pesi_gonna a strati con `segue_gamba` 0,6
(i pannelli fino alle caviglie). Dopo, `riesporta("zarine")` di
monta_campione.py rifa' la tunica simulata (STOFFE), le gambe senza bacino e la
Posa a piombo.

Dentro Blender CON INTERFACCIA (ARP fa uno screenshot OpenGL), dal ponte:
    python arcanium/tools/ponte_blender.py arcanium/tools/rimonta_zarine.py
"""
exec(open("C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/arcanium/tools/monta_campione.py", encoding="utf-8").read())
import bpy
NOME = "zarine"
OPZ = dict(strati=True, raggio=0.12, sfuma=0.08, segue_gamba=0.6)
m = carica(NOME)
m["prepara"](NOME, altezza=1.70)
gonna_prima_della_cottura(m, **OPZ)
veste_a_piombo(m)
m["rigga"]()
m["travasa"](affila=False, falde=False, gabbia=True, mani="aperte")
pesi_gonna(**OPZ)
bpy.ops.wm.save_as_mainfile(filepath="C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/lavorazione/blender/campione_%s.blend" % NOME)
print("FATTO", riesporta(NOME))
