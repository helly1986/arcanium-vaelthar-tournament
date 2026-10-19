"""Ritocca le orecchie del Mago Sylvorn rifatto con Tripo P2 (2026-09-28).

    blender --background --factory-startup --python arcanium/tools/ritocca_orecchie_mago.py -- <ingresso.fbx> <uscita.fbx>

Lo STANDARD (2026-09-30) e' FBX dentro e fuori: l'FBX di Tripo conserva la
topologia quad, e l'uscita va in `consumati_sylvorn/sorgenti/` con la texture
INCORPORATA, pronta per `monta_consumato_sylvorn.prepara`. Accetta anche GLB
(la prima versione del 2026-09-28 era fatta cosi').

Tripo ha dato orecchie da ELFO (punta a z 0,951 su una testa alta 1 m); la
lore voleva orecchie UMANE, danneggiate, con l'apparecchio d'ascolto
dell'Arcanium — che Tripo ha preso dal concept sull'orecchio +x. Si ritocca la
forma senza perdere la modellazione:

  * tutte e due: la punta si riconduce verso un contorno TONDO attorno al
    centro della conca (vedi `R_LIBERO`); lobo e conca restano;
  * l'orecchio SENZA apparecchio (-x) ha il raggio più corto e una TACCA a V
    nel bordo alto. È il «danneggiato».

I vertici si spostano per POSIZIONE, non per indice: il GLB di Tripo duplica i
vertici sulle cuciture UV (30k vertici per 28k triangoli), e due copie dello
stesso punto spostate in modo diverso aprirebbero la mesh.

Le misure sono in metri sul GLB come esce da Tripo (alto 1 m). Il montaggio
(`monta_consumato_sylvorn.prepara(..., altezza=...)`) lo scala dopo.
"""
import bpy, sys, math

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]

## ARROTONDARE, non schiacciare. Nel piano laterale (x, z) ogni punto
## dell'orecchio si avvicina al CENTRO dell'orecchio solo oltre il raggio
## `R_LIBERO`: conca e lobo restano come sono, la punta viene ricondotta verso
## un contorno tondo, con una coda morbida (`CODA`) invece di un taglio netto.
##
## ⚠️ Due tentativi falliti prima di questo (2026-09-28, visti a render):
##   1. peso per SPORGENZA di ogni vertice: fronte e retro della lamina si
##      spostavano diversi e l'orecchio si strappava in schegge;
##   2. compressione VERTICALE uguale a ogni quota: la punta, che è obliqua,
##      schiacciata si girava in fuori come un corno.
CENTRO = (0.051, 0.926)      # (|x|, z) al centro della conca
R_LIBERO = 0.013
CODA = 0.3                   # quanto resta dell'eccesso oltre il raggio
## L'orecchio danneggiato (-x): raggio più corto (è stato tagliato) e una
## tacca a V nel bordo alto.
R_DANNEGGIATO = 0.011
TACCA_Y = -0.066
TACCA_LARGA = 0.006
TACCA_FONDA = 0.003
## Da cranio a orecchio, su una fascia larga (il cranio non si tocca).
CRANIO = 0.045
SFUMA = 0.008
Y_ORECCHIO = (-0.10, -0.035)
Z_MIN = 0.900


def liscio(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


bpy.ops.wm.read_factory_settings(use_empty=True)
if SRC.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=SRC, use_image_search=True)
else:
    bpy.ops.import_scene.gltf(filepath=SRC)
me = [o for o in bpy.data.objects if o.type == "MESH"][0]
mw = me.matrix_world
inv = mw.inverted()
spostati = {1: 0, -1: 0}
for v in me.data.vertices:
    p = mw @ v.co
    lato = 1 if p.x > 0 else -1
    ax = abs(p.x)
    if not (Y_ORECCHIO[0] < p.y < Y_ORECCHIO[1]) or p.z <= Z_MIN or ax <= CRANIO:
        continue
    w = liscio((ax - CRANIO) / SFUMA)
    dx, dz = ax - CENTRO[0], p.z - CENTRO[1]
    r = math.hypot(dx, dz)
    rl = R_LIBERO if lato == 1 else R_DANNEGGIATO
    if r > rl:
        r2 = rl + (r - rl) * CODA
        k = 1.0 + (r2 / r - 1.0) * w
        dx *= k
        dz *= k
    z = CENTRO[1] + dz
    if lato == -1:
        t = 1.0 - min(1.0, abs(p.y - TACCA_Y) / TACCA_LARGA)
        alto = liscio((z - CENTRO[1]) / rl)
        z -= TACCA_FONDA * t * alto * w
    p.x = (CENTRO[0] + dx) * lato
    p.z = z
    v.co = inv @ p
    spostati[lato] += 1
print("spostati: +x %d, -x %d" % (spostati[1], spostati[-1]))

bpy.ops.object.select_all(action="SELECT")
if DST.lower().endswith(".fbx"):
    ## Texture DENTRO l'FBX: la sorgente e' un file solo, niente cartella .fbm.
    bpy.ops.export_scene.fbx(filepath=DST, use_selection=True, path_mode="COPY",
                             embed_textures=True, mesh_smooth_type="FACE")
else:
    bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_image_format="AUTO")
print("EXPORT", DST)
