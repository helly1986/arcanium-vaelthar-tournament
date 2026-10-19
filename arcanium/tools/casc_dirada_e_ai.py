# -*- coding: utf-8 -*-
"""Dirada le chiavi di un tratto e mette l'interpolazione AI in mezzo.

E' il mestiere di Cascadeur ridotto all'osso: **pochi keyframe e tanta
interpolazione AI**. Una clip importata da GLB e' bakeata, cioe' ha una chiave a
ogni frame: cosi' l'AI non ha niente da inventare e ogni bruttura autorata
resta dov'e'. Togliendo le chiavi in mezzo e lasciando solo le pose che
contano, la rete riempie il resto con un movimento che rispetta il corpo.

Da eseguire DENTRO Cascadeur, tramite il ponte:

    python tools/cascadeur_mcp.py arcanium/tools/casc_dirada_e_ai.py

⚠️⚠️ **L'interpolazione AI gira solo se il personaggio ha il rig di Cascadeur.**
Misurato: sullo scheletro nudo importato da GLB, mettere `Interpolation.AI` non
cambia un valore; con il rig costruito, fra LINEAR e AI ci sono **27,3 cm** di
differenza sulla mano a meta' intervallo. Il rig si costruisce con
`arcanium/tools/casc_rigga_personaggio.py`.

⚠️ Le chiavi stanno sui LAYER, non sugli oggetti, e il rig ne crea uno per parte
del corpo (11 sul nostro biped). Diradare vuol dire farlo su tutti.
"""
import traceback

import csc

AI = None  # riempito a runtime: csc.layers.layer.Interpolation.AI


def _log(*a):
    print("[dirada]", *a)


def dirada(ds, da, a, chiavi_da_tenere, interpolazione=None):
    """Toglie le chiavi in [da, a] tranne quelle elencate, e mette AI."""
    global AI
    I = csc.layers.layer.Interpolation
    AI = I.AI
    tipo = interpolazione if interpolazione is not None else AI

    lv = ds.layers_viewer()
    layer_ids = list(lv.all_layer_ids())
    tenere = sorted(set(chiavi_da_tenere))
    _log("layer: %d | tratto %d..%d | chiavi tenute: %s" % (len(layer_ids), da, a, tenere))

    def modifica(me, update, scene, session):
        le = me.layers_editor()
        for lid in layer_ids:
            lay = ds.layers_viewer().layer(lid)
            for f in range(da, a + 1):
                if f in tenere:
                    continue
                if lay.is_key(f):
                    le.unset_section(f, lid)

    if not ds.modify_update_with_session("dirada chiavi", modifica):
        raise SystemExit("il diradamento e' fallito: guarda il log eventi")

    # rilettura: quante chiavi sono rimaste davvero
    rimaste = set()
    for lid in layer_ids:
        rimaste |= {k for k in ds.layers_viewer().layer(lid).key_frame_indices()
                    if da <= k <= a}
    _log("chiavi rimaste nel tratto:", sorted(rimaste))
    if rimaste != set(tenere):
        _log("⚠️ attese %s" % tenere)

    # l'interpolazione va messa sulla chiave che APRE ogni intervallo
    def metti(me, update, scene, session):
        le = me.layers_editor()
        for lid in layer_ids:
            lay = ds.layers_viewer().layer(lid)
            for f in tenere[:-1]:
                if not lay.is_key(f):
                    continue
                sec = csc.layers.layer.Section()
                sec.key = lay.key(f)
                iv = csc.layers.layer.Interval()
                iv.interpolation = tipo
                sec.interval = iv
                le.set_section(sec, f, lid)

    if not ds.modify_update_with_session("interpolazione AI", metti):
        raise SystemExit("l'interpolazione non e' stata applicata")

    lay0 = ds.layers_viewer().layer(layer_ids[0])
    _log("interpolazione sul primo layer:",
         [(f, str(lay0.section(f).interval.interpolation)) for f in tenere[:-1] if lay0.is_key(f)])


# ── le pose che si tengono ────────────────────────────────────────────────
# 1   in piedi, prima che il veleno morda
# 18  le mani scattano alla gola
# 48  la stretta piu' chiusa (misurato: mano a 8,4 cm dal collo)
# 78  primo cedimento
# 105 l'ultima posa prima che parta lo stramazzo
# 112 da qui in poi la caduta resta com'e': e' gia' stata messa a terra
TENERE = [1, 18, 48, 78, 105, 112]

try:
    _app = csc.app.get_application()
    _ds = _app.current_scene().domain_scene()
    dirada(_ds, 1, 112, TENERE)
except Exception:
    print("ECCEZIONE:\n" + traceback.format_exc())
