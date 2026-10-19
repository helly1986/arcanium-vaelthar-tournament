# -*- coding: utf-8 -*-
"""Taglia una clip di locomozione in Cascadeur su UN passo e chiude il loop.

Da eseguire DENTRO Cascadeur, tramite il ponte, sulla scena corrente:

    python tools/cascadeur_mcp.py arcanium/tools/casc_taglia_loop.py

`A` e `B` (in cima) sono i frame della finestra da tenere: i frame A..B
diventano 0..L (L = B - A), le chiavi oltre L si tolgono e la timeline si
accorcia a L+1 frame. La finestra si sceglie PRIMA, con
`misura_locomozione.py` sul GLB esportato: stampa le coppie di frame che si
somigliano di piu'. Ma la media delle rotazioni non basta — vedi sotto.

═══════════════════════════════════════════════════════════════════════════
IL TAGLIO DA SOLO NON CHIUDE: la differenza si SPALMA
═══════════════════════════════════════════════════════════════════════════

Due frame a un passo di distanza non sono mai uguali (sulla corsa dell'arciere,
2026-09-14: 12-14 gradi di media, 30 sul peggiore). Tagliare e basta lascia uno
scatto a ogni giro. Qui la differenza fra A e B si distribuisce lungo la
finestra: al frame k il valore e' quello di A+k piu' (A - B) * k/L — posizioni
come vettori, rotazioni con uno slerp dal quaternione identita' a quello della
differenza. Il frame L viene identico allo 0, e nessun frame si sposta piu' di
un L-esimo dello scarto.

═══════════════════════════════════════════════════════════════════════════
SI SCRIVONO I CONTROLLI, NON I GIUNTI
═══════════════════════════════════════════════════════════════════════════

In una scena riggata `set_data_value` su `Local Rotation` di un giunto riesce
(`ok=True`) e dopo l'aggiornamento il valore e' tornato quello di prima: il rig
risolve i giunti dai punti, dai corpi rigidi, dal centro di massa. Quindi si
riscrivono TUTTI i canali animati di TUTTI gli oggetti — i giunti liberi
(attachment, dita, toes, Spine_02/03, Root) restano come scritti, quelli
riggati li rifa' il rig dai controlli, che sono stati spalmati allo stesso
modo. E' la strada di `pycsc` `Timeline.move_frames`. I canali costanti
(`Model Pose`, colori, flag) sollevano `RuntimeError` alla lettura per frame:
si saltano. Matrici, float e bool si copiano tali e quali (li ricalcola o li
tiene il rig).

⚠️ `csc.math.Quaternion(w, x, y, z)`: il costruttore vuole PRIMA la w. Con
l'ordine (x, y, z, w) le componenti ruotano di un posto e ogni giunto libero
esce girato di ~120 gradi — la faretra sopra la testa. Lo script fa l'andata e
ritorno su un quaternione noto prima di scrivere qualunque cosa.

═══════════════════════════════════════════════════════════════════════════
LA FINESTRA GIUSTA: ESTREMI IN APPOGGIO
═══════════════════════════════════════════════════════════════════════════

La spalmatura sposta anche i piedi. Con gli estremi presi a meta' del volo
di un piede (f09->f23: la migliore per media di rotazioni), la differenza in
ALTEZZA del piede — 23 cm fra un estremo e l'altro — finiva spalmata ANCHE sui
frame in cui quel piede doveva stare a terra: nel loop restava sollevato di
15-20 cm durante l'appoggio. Con gli estremi entrambi in appoggio dello stesso
piede (f06->f22) la differenza e' orizzontale, e il piede a terra resta a
terra: al piu' scivola di qualche centimetro di lato, che su una corsa sul
posto non si nota. `misura_locomozione.py` stampa i frame di appoggio.

Si torna indietro con `Scene.Undo` (una sessione = un passo).
"""
import csc, math, numpy as np

## La finestra da tenere (frame della scena corrente).
A, B = 6, 22
## True: legge e stampa soltanto, non scrive.
PROVA = False

L = B - A
app = csc.app.get_application()
sc = app.current_scene()
ds = sc.domain_scene()
mv = ds.model_viewer(); dv = mv.data_viewer(); lv = ds.layers_viewer()
n_frame = dv.get_animation_size()
assert n_frame > B, "la scena ha %d frame, la finestra arriva a %d" % (n_frame, B)


def qmul(a, b):
    return (a[3]*b[0] + a[0]*b[3] + a[1]*b[2] - a[2]*b[1],
            a[3]*b[1] - a[0]*b[2] + a[1]*b[3] + a[2]*b[0],
            a[3]*b[2] + a[0]*b[1] - a[1]*b[0] + a[2]*b[3],
            a[3]*b[3] - a[0]*b[0] - a[1]*b[1] - a[2]*b[2])


def qinv(a):
    return (-a[0], -a[1], -a[2], a[3])


def qnorm(a):
    n = math.sqrt(sum(c*c for c in a)) or 1.0
    return tuple(c / n for c in a)


def slerp_id(d, w):
    """Slerp fra l'identita' e `d`, di frazione w."""
    d = qnorm(d)
    if d[3] < 0:
        d = tuple(-c for c in d)
    ang = 2.0 * math.acos(max(-1.0, min(1.0, d[3])))
    if ang < 1e-6:
        return (0.0, 0.0, 0.0, 1.0)
    s = math.sin(ang / 2.0)
    asse = (d[0] / s, d[1] / s, d[2] / s)
    h = ang * w / 2.0
    return (asse[0]*math.sin(h), asse[1]*math.sin(h), asse[2]*math.sin(h), math.cos(h))


def q_da(rot):
    q = rot.to_quaternion()
    return (q.x(), q.y(), q.z(), q.w())


def rot_da(q):
    ## ⚠️ (w, x, y, z): vedi il cappello.
    return csc.math.Rotation.from_quaternion(csc.math.Quaternion(q[3], q[0], q[1], q[2]))


## Andata e ritorno del quaternione: se non torna uguale, non si scrive niente.
_q = qnorm((0.1, 0.2, 0.3, 0.9))
_r = q_da(rot_da(_q))
assert all(abs(_r[i] - _q[i]) < 1e-3 for i in range(4)), "quaternione: andata e ritorno rotti %s -> %s" % (_q, _r)

## 1. lettura di tutti i canali animati
canali = []   # (did, nome_oggetto, nome_canale, tipo, valori{f: v})
n_obj = 0
for o in mv.get_objects():
    n_obj += 1
    nome_o = mv.get_object_name(o)
    for did in dv.get_all_data_id(o):
        try:
            v0 = dv.get_data_value(did, 0)
        except RuntimeError:
            continue   # costante
        vals = {f: dv.get_data_value(did, f) for f in range(A, B + 1)}
        canali.append((did, nome_o, dv.get_data_name(did), type(v0).__name__, vals))
print("oggetti %d, canali animati %d, finestra %d..%d (%d frame)" % (n_obj, len(canali), A, B, L))

## 2. i valori nuovi
scritture = []   # (did, k, valore)
stat = {"rot": 0, "pos": 0, "copia": 0}
peggio_rot = (0.0, ""); peggio_pos = (0.0, "")
for did, nome_o, nome_c, tipo, vals in canali:
    va, vb = vals[A], vals[B]
    if tipo == "Rotation":
        qa, qb = q_da(va), q_da(vb)
        d = qnorm(qmul(qa, qinv(qb)))
        ang = math.degrees(2.0 * math.acos(max(-1.0, min(1.0, abs(d[3])))))
        if ang > peggio_rot[0]:
            peggio_rot = (ang, nome_o + "/" + nome_c)
        for k in range(L + 1):
            q = q_da(vals[A + k])
            scritture.append((did, k, rot_da(qnorm(qmul(slerp_id(d, k / float(L)), q)))))
        stat["rot"] += 1
    elif tipo == "ndarray" and getattr(va, "shape", None) == (3,):
        delta = np.asarray(va, dtype=float) - np.asarray(vb, dtype=float)
        if np.linalg.norm(delta) > peggio_pos[0]:
            peggio_pos = (float(np.linalg.norm(delta)), nome_o + "/" + nome_c)
        for k in range(L + 1):
            scritture.append((did, k, np.asarray(vals[A + k], dtype=float) + delta * (k / float(L))))
        stat["pos"] += 1
    else:
        for k in range(L + 1):
            scritture.append((did, k, vals[A + k]))
        stat["copia"] += 1
print("canali: rotazioni %d, posizioni %d, copiati %d; scritture %d" % (stat["rot"], stat["pos"], stat["copia"], len(scritture)))
print("differenza fra A e B da spalmare: rotazione %.1f gradi (%s), posizione %.1f cm (%s)"
      % (peggio_rot[0], peggio_rot[1], peggio_pos[0], peggio_pos[1]))

## ⚠️ Niente SystemExit dentro il ponte: e' una BaseException, il server MCP
## non la cattura e muore.
if PROVA:
    print("prova: niente scritto")
else:
    layer_ids = [l for l in lv.all_layer_ids() if not l.is_null()]

    def taglia(me, update, scene, session):
        de = me.data_editor(); le = me.layers_editor()
        for did, k, v in scritture:
            de.set_data_value(did, k, v)
        for lid in layer_ids:
            for f in list(lv.layer(lid).key_frame_indices()):
                if f > L:
                    le.unset_section(f, lid)
            le.set_fixed_interpolation_or_key_if_need(lid, L, True)
        me.fit_animation_size_by_layers()

    ok = ds.modify_update_with_session("taglio del loop %d..%d" % (A, B), taglia)
    print("sessione ok=%s; frame ora %d (attesi %d)" % (ok, dv.get_animation_size(), L + 1))

    ## 3. collaudo: frame 0 e frame L identici su ogni canale
    diff = 0.0; nome_d = ""
    for did, nome_o, nome_c, tipo, vals in canali:
        v0 = dv.get_data_value(did, 0); vL = dv.get_data_value(did, L)
        if tipo == "Rotation":
            d = qnorm(qmul(q_da(v0), qinv(q_da(vL))))
            ang = math.degrees(2.0 * math.acos(max(-1.0, min(1.0, abs(d[3])))))
            if ang > diff:
                diff, nome_d = ang, nome_o + "/" + nome_c + " (gradi)"
        elif tipo == "ndarray" and getattr(v0, "shape", None) == (3,):
            dd = float(np.linalg.norm(np.asarray(v0, dtype=float) - np.asarray(vL, dtype=float)))
            if dd > diff:
                diff, nome_d = dd, nome_o + "/" + nome_c + " (cm)"
    print("collaudo: differenza massima fra frame 0 e frame %d = %.3f %s" % (L, diff, nome_d))
