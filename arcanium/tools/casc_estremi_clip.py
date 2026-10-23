# -*- coding: utf-8 -*-
"""Scena Cascadeur pronta da AUTORARE: solo la prima e l'ultima chiave.

Da eseguire DENTRO Cascadeur, tramite il ponte, sulla scena corrente appena
riggata da `casc_rigga_personaggio.py`:

    python tools/cascadeur_mcp.py arcanium/tools/casc_estremi_clip.py

La base viene da `base_cascadeur.py ... tieni=N`: la posa del primo fotogramma
dell'idle tenuta per N frame. Qui si lasciano SOLO le chiavi al primo e
all'ultimo frame, con interpolazione BEZIER, e si salva la scena. L'animatore
parte da due pose identiche a quella dell'idle, cosi' la clip si attacca
all'idle da tutte e due le parti.

⚠️ Le chiavi si TENGONO (quelle cotte dal rig), non si riscrivono: copiare la
posa canale per canale dal frame 0 all'ultimo spostava le mani di 50 cm — i
controlli del rig dipendono l'uno dall'altro (2026-09-26). E si misura: la posa
al primo, a meta' e all'ultimo frame deve coincidere al millimetro.

Dove salvare si scrive in `lavorazione/cascadeur/salva_come.txt` (il ponte
esegue il testo dentro Cascadeur: una variabile d'ambiente non arriva).

Con `lavorazione/cascadeur/chiavi_da_tenere.txt` (una lista json di frame) si
tengono anche le chiavi di MEZZO: e' il ritorno delle pose chiave scritte in
FK su una scena senza rig (`casc_pose_fk.py`), esportate e riggate — il rig le
ha cotte nei controlli, e fra l'una e l'altra interpola Cascadeur.
"""
import csc
import math

SALVA_COME = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/lavorazione/cascadeur/salva_come.txt"
CHIAVI = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/lavorazione/cascadeur/chiavi_da_tenere.txt"

ds = app.current_scene().domain_scene()
lv = ds.layers_viewer()
mv = ds.model_viewer()
dv = mv.data_viewer()
L = csc.layers.layer
FINE = dv.get_animation_size() - 1
META = FINE // 2
try:
    import json
    with open(CHIAVI, encoding="utf-8") as f:
        TENUTE = sorted({int(k) for k in json.load(f)} | {0, FINE})
except OSError:
    TENUTE = [0, FINE]
print("chiavi tenute:", TENUTE)


def sessione(me, up, sc, se):
    le = me.layers_editor()
    for lid in lv.all_layer_ids():
        lay = lv.layer(lid)
        if not all(lay.is_key(f) for f in TENUTE):
            continue
        sez = {}
        for f in TENUTE:
            s = L.Section()
            s.key = lay.key(f)
            iv = L.Interval()
            iv.interpolation = L.Interpolation.BEZIER
            s.interval = iv
            sez[f] = s
        le.set_sections(sez, lid)
    me.fit_animation_size_by_layers()


print("sessione:", ds.modify_update_with_session("chiavi solo agli estremi", sessione))
print("frame:", dv.get_animation_size(), "chiavi:",
      {tuple(lv.layer(l).key_frame_indices()) for l in lv.all_layer_ids()})

peggio = (0.0, "")
for o in mv.get_objects():
    if mv.get_object_type_name(o) != "Joint":
        continue
    ids = {dv.get_data_name(i): i for i in dv.get_all_data_id(o)}
    try:
        ## Con le chiavi di mezzo la meta' non e' piu' la posa ferma: si
        ## confrontano solo i due capi, che devono restare identici (il loop).
        a, b, c = (dv.get_data_value(ids["Position"], f) for f in (0, META if len(TENUTE) == 2 else 0, FINE))
    except Exception:
        continue   # canale costante: non ha chiavi da confrontare
    pa, pb, pc = ([float(x[k]) for k in range(3)] for x in (a, b, c))
    d = max(math.dist(pa, pc), math.dist(pa, pb))
    if d > peggio[0]:
        peggio = (d, mv.get_object_name(o))
print("scarto massimo fra i frame 0/%d/%d: %.3f cm (%s)" % (META, FINE, peggio[0], peggio[1]))

try:
    with open(SALVA_COME, encoding="utf-8") as f:
        dove = f.read().strip()
except OSError:
    dove = ""
## ⚠️ `save` non solleva errori: se lo stesso file e' aperto in un'altra
## scheda (la versione vecchia della scena) scrive "Saving scene failed" nel
## log e basta, e qui si stampava "salvata" lo stesso (2026-09-30). La scheda
## vecchia si chiude, e il salvataggio si verifica dalla data del file.
if dove:
    import os
    sm = app.get_scene_manager()
    nuova = app.current_scene()
    for s in list(sm.scenes()):
        if s is not nuova and s.get_path_name() == dove:
            sm.remove_application_scene(s)
            print("chiusa la scheda vecchia di", dove)
    sm.set_current_scene(nuova)
    prima = os.path.getmtime(dove) if os.path.exists(dove) else 0.0
    nuova.save(dove)
    if os.path.exists(dove) and os.path.getmtime(dove) > prima:
        print("salvata in", dove)
    else:
        print("⚠️ NON salvata:", dove)
else:
    print("non salvata: manca", SALVA_COME)
