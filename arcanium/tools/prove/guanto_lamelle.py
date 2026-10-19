# -*- coding: utf-8 -*-
"""Il guanto a piastre, COSTRUITO SULLE OSSA.

Ricavare il guanto ritagliando la mano dal corpo non funziona: le pieghe fra le
dita fanno compenetrare i gusci, e ogni cura peggiora (vedi docs/13). Qui il
problema non si pone, perche' le dita sono **volumi separati**: una lamella per
falange, come in un guanto d'arme vero.

Lunghezza di ogni lamella = lunghezza dell'osso. Spessore = quello del DITO,
misurato sul corpo. Nessuno dei due si scrive: si leggono. Quindi lo stesso
codice fa il guanto giusto per il corpo femminile, per i nemici, per qualunque
mano con questa convenzione di ossa.

## ⚠️ Come si misura la grossezza di un dito, e come NON si misura

La prima versione sparava un ventaglio di sonde perpendicolari all'osso e
chiedeva al KD-tree del corpo il punto di pelle piu' vicino. Dava **24 mm** per
una falange media, che ne fa circa 9: a 5 cm dall'asse di un dito il punto di
pelle piu' vicino non e' quel dito, e' **quello accanto** — o il palmo. Una
sonda che puo' rispondere con la carne sbagliata non misura niente.

Qui invece la carne si sceglie PRIMA di misurarla:

1. per ogni vertice del corpo si guarda quale osso lo DOMINA (peso massimo);
2. si tengono solo i vertici dominati dalle ossa **di quel dito**;
3. di quelli si tiene la fetta che cade nella finestra assiale del segmento;
4. si prendono DUE semiassi, non un raggio: quanto e' larga la carne di lato e
   quanto e' spessa verso il dorso, ciascuno come quantile alto.

⚠️ I due semiassi non sono un vezzo: sulla MANO la distanza dall'asse osseo vale
33 mm di larghezza contro 14 di spessore, e una piastra costruita sul numero
unico resta sospesa sopra il dorso invece di appoggiarcisi. Misurato: falange
media 10,1 x 7,9 mm di semiasse, mano 33,5 x 14,1. Sono due cose diverse e vanno
misurate come tali.

Cosi' il dito accanto non e' proprio fra i candidati, e non serve nessuna soglia
magica sulla distanza. E funziona su qualunque corpo pesato con questa
convenzione di ossa, che e' il motivo per cui il guanto si costruisce cosi'.

## ⚠️ E il ROLLIO non e' vincolato da niente

Seconda trappola, e si vede solo a render: `rotation_difference` allinea l'asse
Z locale all'osso e **lascia libero il rollio attorno a quell'asse**. La lamella
e' mezzo cilindro: se il rollio e' arbitrario, la meta' che tieni guarda da una
parte a caso, e a schermo escono lamine **di taglio** invece che appoggiate sul
dorso. Non e' un difetto di misura: la misura era giusta e il pezzo era storto.

Serve una direzione DORSALE, e va letta. Qui si sceglie con `MODO_DORSO` fra tre
riferimenti, e si guarda quale appoggia le piastre sul dorso:

  `osso_x` / `osso_z`  l'asse locale dell'osso, cioe' il rollio che il rig gia'
                       porta con se'. Segue lo splay di ogni dito gratis.
  `carne`              la normale del piano della mano, ricavata dalla CARNE
                       dominata dalla mano (varianza minima), col segno preso
                       dal baricentro: il palmo ha le eminenze, quindi la carne
                       e' spostata verso il palmo rispetto all'asse osseo.
                       Piu' la regola del POLLICE, che ha un dorso suo.
  `pelle`              ⚠️ PROVATA E SCARTATA. L'idea e' buona in teoria — il
                       dorso e' il lato dove la pelle e' piu' vicina all'osso,
                       perche' dall'altra parte c'e' il polpastrello — ma su
                       questa mesh il segnale e' troppo rumoroso: sulle falangi
                       dello stesso dito le stime oscillano fra 0 e 112 gradi, e
                       sette segmenti su diciassette non hanno ampiezza
                       sufficiente e ripiegano. Lamelle dello stesso dito
                       ruotate una diversa dall'altra sono peggio di una
                       normale unica leggermente sbagliata. Il codice resta:
                       su una mesh piu' fitta puo' tornare buono.

Misurato su protagonista_v4: l'asse X delle falangi e' (+1,0,0) su tutte, la
normale del piano della mano e' (+0.91, +0.01, +0.42). Concordano nel verso ma
non nella direzione — 35 gradi — quindi si guarda, non si sceglie a tavolino.

    blender --background --factory-startup --python arcanium/tools/prove/guanto_lamelle.py
"""
import bpy, bmesh, os, math
from mathutils import Vector, Matrix

RADICE = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/"
CORPO = RADICE + "assets/characters/base_body/protagonista_v4.glb"
## i render di lavoro vanno in `bisezione/`, che git ignora: sono decine di
## PNG da un megabyte. In git ci vanno solo i fotogrammi che reggono
## un'affermazione, copiati a mano come esito_*.png.
FUORI = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/") + "/bisezione/"
os.makedirs(FUORI, exist_ok=True)

LATO = "Left"
DITA = {
    "Thumb":  ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"],
    "Index":  ["IndexProximal", "IndexIntermediate", "IndexDistal"],
    "Middle": ["MiddleProximal", "MiddleIntermediate", "MiddleDistal"],
    "Ring":   ["RingProximal", "RingIntermediate", "RingDistal"],
    "Little": ["LittleProximal", "LittleIntermediate", "LittleDistal"],
}

## ⚠️ Le quote si incastrano, e l'ordine e' quello di un guanto vero:
##   pelle → imbottitura → stoffa → un filo d'aria → acciaio
## Quindi il GIOCO della lamella non si scrive: si RICAVA dal gambeson. Scritto
## a mano valeva 1,6 mm mentre il gambeson ne occupa 3,9, e il risultato era che
## l'imbottitura spuntava ATTRAVERSO l'acciaio — a schermo il guanto sembrava
## sbriciolato. C'e' un cancello piu' sotto che lo ricontrolla a ogni giro.
IMBOTTITURA = 0.0026  # quanto il gambeson sta sopra la pelle
SPESSORE_GB = 0.0013  # la stoffa del gambeson
ARIA = 0.0008         # il filo d'aria fra stoffa e acciaio
GIOCO = IMBOTTITURA + SPESSORE_GB + ARIA
SPESSORE = 0.0022     # spessore della lamina d'acciaio
ACCAVALLA = 1.14      # ogni lamella sborda sulla precedente: cosi' non si aprono
SMUSSO = 0.0009
QUANTILE = 0.75       # un dito non e' un cilindro: la mediana lo fa troppo magro
SALDATURA = 0.0001
## "osso_x" | "osso_z" | "carne" — vedi il capitolo sul rollio nella docstring
## ⚠️ `carne` di default: guardati i tre render, `osso_x` sbaglia il POLLICE.
## Il rollio delle falangi e' uniforme (X = +X mondo su tutte e quindici) ma il
## metacarpo del pollice ha un rollio suo, e la lamella gli esce di taglio.
MODO_DORSO = os.environ.get("MODO_DORSO", "carne")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=CORPO)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
corpo = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o is not corpo:
        bpy.data.objects.remove(o, do_unlink=True)
## saldato: da glTF arriva spezzato su ogni cucitura UV, e le isole di una mano
## non si contano su una mesh gia' a pezzi per conto suo
bpy.ops.object.select_all(action='DESELECT')
corpo.select_set(True)
bpy.context.view_layer.objects.active = corpo
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=SALDATURA)
bpy.ops.object.mode_set(mode='OBJECT')
print("corpo saldato: %d vertici" % len(corpo.data.vertices))


def testa_coda(nome):
    b = rig.data.bones[nome]
    return (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local)


# --- chi domina cosa --------------------------------------------------------
_nomi_gruppi = [g.name for g in corpo.vertex_groups]
DOMINATI = {}
for _v in corpo.data.vertices:
    _best, _bw = None, 0.0
    for _g in _v.groups:
        if _g.weight > _bw:
            _bw, _best = _g.weight, _nomi_gruppi[_g.group]
    if _best is not None:
        DOMINATI.setdefault(_best, []).append(_v.index)


def carne_di(ossa):
    """Gli indici dei vertici dominati da una qualunque di quelle ossa."""
    fuori = []
    for n in ossa:
        fuori.extend(DOMINATI.get(n, ()))
    return fuori


def vicini_di(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    fuori = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    bm.free()
    return fuori


def liscia_campo(valori, vicini, giri=4, forza=0.55):
    v = list(valori)
    for _ in range(giri):
        nuovo = []
        for i, x in enumerate(v):
            vv = vicini[i]
            nuovo.append(x if not vv else
                         x * (1.0 - forza) + (sum(v[j] for j in vv) / len(vv)) * forza)
        v = nuovo
    return v


def taglia_su_campo(ob, campo, soglia=0.5):
    """Taglia ESATTAMENTE sulla curva di livello, tenendo il sotto-soglia.

    Cancellare vertici interi darebbe un bordo a scaletta: qui gli spigoli che
    attraversano la soglia si spezzano nel punto esatto.
    """
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    val = {v: campo[v.index] for v in bm.verts}
    incroci = []
    for e in list(bm.edges):
        a_, b_ = e.verts
        if (val[a_] - soglia) * (val[b_] - soglia) < 0.0:
            incroci.append((e, (soglia - val[a_]) / (val[b_] - val[a_])))
    for e, tt in incroci:
        try:
            _, nv = bmesh.utils.edge_split(e, e.verts[0], tt)
            val[nv] = soglia
        except (ValueError, RuntimeError):
            pass
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if val.get(v, 0.0) > soglia + 1e-9],
                     context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


# --- ⛔ CANCELLO: quante dita ha la mano di QUESTO corpo? --------------------
## `conta_dita.py` affetta dal basso e su un corpo intero conterebbe le gambe.
## Qui la stessa idea, ristretta alla carne della mano: quante isole topologiche
## fanno i vertici dominati dalle ossa delle dita? Se non sono cinque, il guanto
## costruito su cinque catene non combacia con la carne, e va saputo PRIMA.
def conta_dita_del_corpo():
    ossa_dita = [LATO + n for d in DITA.values() for n in d]
    voluti = set(carne_di(ossa_dita))
    bm = bmesh.new()
    bm.from_mesh(corpo.data)
    bm.verts.ensure_lookup_table()
    visti, isole = set(), []
    for i in voluti:
        if i in visti:
            continue
        pila, gruppo = [i], []
        visti.add(i)
        while pila:
            j = pila.pop()
            gruppo.append(j)
            for e in bm.verts[j].link_edges:
                k = e.other_vert(bm.verts[j]).index
                if k in voluti and k not in visti:
                    visti.add(k)
                    pila.append(k)
        isole.append(gruppo)
    grosse = [g for g in isole if len(g) >= 25]
    bm.free()
    return grosse


_isole = conta_dita_del_corpo()
print("CANCELLO dita: %d isole di carne dominata dalle falangi (vertici: %s)"
      % (len(_isole), sorted((len(g) for g in _isole), reverse=True)[:8]))
if len(_isole) != len(DITA):
    print("  ⚠️ non sono %d isole separate: le dita possono essere unite dalla"
          " carne del palmo, il che va bene, oppure essere un numero diverso."
          " Guardare il render prima di fidarsi." % len(DITA))


# --- il verso DORSALE ------------------------------------------------------
R3 = rig.matrix_world.to_3x3()
## le NOCCHE sono le teste delle falangi prossimali. Servono in due posti: per
## far arrivare la piastra del dorso fin li', e per orientare il POLLICE.
NOCCA = sum((testa_coda(LATO + DITA[d][0])[0]
             for d in ("Index", "Middle", "Ring", "Little")), Vector()) / 4.0


def normale_piatta(punti):
    """La direzione di varianza MINIMA di una nuvola: la normale di cio' che e'
    piatto. Iterazione di potenza sullo spettro traslato, che porta il minimo a
    essere il dominante in modulo — non serve un solutore di autovalori."""
    centro = sum(punti, Vector()) / len(punti)
    M = [[0.0] * 3 for _ in range(3)]
    for p in punti:
        q = p - centro
        for i in range(3):
            for j in range(3):
                M[i][j] += q[i] * q[j]
    A = Matrix(M).to_3x3()
    B = A - Matrix.Scale(A[0][0] + A[1][1] + A[2][2] + 1e-12, 3)
    v = Vector((0.31, 0.57, 0.76))
    for _ in range(300):
        v = B @ v
        if v.length < 1e-20:
            break
        v.normalize()
    return v, centro


_h_testa, _h_coda = testa_coda(LATO + "Hand")
_u_mano = (_h_coda - _h_testa).normalized()
_carne_mano = [corpo.matrix_world @ corpo.data.vertices[i].co
               for i in DOMINATI.get(LATO + "Hand", [])]
_n_piano, _ = normale_piatta(_carne_mano)
## ⚠️ Il segno non lo da' la PCA. Lo da' l'anatomia: il palmo ha le eminenze
## tenar e ipotenar, il dorso e' piatto, quindi il BARICENTRO della carne della
## mano sta spostato verso il PALMO rispetto all'asse dell'osso.
_bar = sum(_carne_mano, Vector()) / len(_carne_mano)
_t = (_bar - _h_testa).dot(_u_mano)
_scarto = _bar - (_h_testa + _u_mano * _t)
DORSALE_CARNE = (-1.0 if _scarto.dot(_n_piano) > 0 else 1.0) * _n_piano
print("dorsale dalla carne: (%+.3f,%+.3f,%+.3f) | scarto del baricentro %+.4f m"
      % (DORSALE_CARNE.x, DORSALE_CARNE.y, DORSALE_CARNE.z, _scarto.dot(_n_piano)))


def dorsale_dalla_pelle(ossa_dito, testa, coda, riferimento, settori=24,
                        ampiezza_minima=0.04):
    """Il dorso e' il lato dove la PELLE E' PIU' VICINA ALL'OSSO.

    ⚠️ E' anatomia, non un trucco: sul dorso ci sono l'unghia e un velo di
    tessuto, sul lato palmare c'e' il polpastrello. Quindi la distanza della
    pelle dall'asse osseo, girando attorno all'osso, ha un minimo sul dorso e
    un massimo sul palmo. Misurarla la' risolve anche il POLLICE, che ha un
    rollio tutto suo e che una normale unica per la mano sbaglia.

    Si adatta la prima armonica r(θ) ≈ r0 + A·cos(θ − θ_palmo) invece di
    prendere l'argmin: su una mesh da gioco i settori sono pochi e rumorosi, e
    l'argmin salterebbe da un settore all'altro fra una falange e l'altra.
    Se l'ampiezza e' troppo piccola il segnale non c'e': si torna al
    riferimento invece di inventare.
    """
    u = (coda - testa)
    lung = u.length
    if lung < 1e-6:
        return riferimento.copy(), 0.0
    u = u.normalized()
    a = riferimento - u * riferimento.dot(u)
    if a.length < 1e-6:
        a = Vector((0.0, 0.0, 1.0)).cross(u)
    a.normalize()
    b = u.cross(a).normalized()
    settore = [[] for _ in range(settori)]
    for i in carne_di(ossa_dito):
        p = corpo.matrix_world @ corpo.data.vertices[i].co
        t = (p - testa).dot(u)
        ## lontano dai giunti: li' la carne appartiene a due segmenti
        if not (0.10 * lung <= t <= 0.90 * lung):
            continue
        q = p - (testa + u * t)
        if q.length < 1e-6:
            continue
        ang = math.atan2(q.dot(b), q.dot(a)) % (2.0 * math.pi)
        settore[int(ang / (2.0 * math.pi) * settori) % settori].append(q.length)
    cx = cy = tot = n_pieni = 0.0
    for k, s_ in enumerate(settore):
        if len(s_) < 2:
            continue
        s_.sort()
        r = s_[len(s_) // 2]
        ang = 2.0 * math.pi * (k + 0.5) / settori
        cx += r * math.cos(ang)
        cy += r * math.sin(ang)
        tot += r
        n_pieni += 1
    if n_pieni < settori * 0.5 or tot <= 0.0:
        return riferimento.copy(), 0.0
    ampiezza = math.hypot(cx, cy) / tot * 2.0      # A/r0, all'incirca
    if ampiezza < ampiezza_minima:
        return riferimento.copy(), ampiezza
    ang_palmo = math.atan2(cy, cx)
    palmo = (a * math.cos(ang_palmo) + b * math.sin(ang_palmo)).normalized()
    return -palmo, ampiezza


def dorsale_di(nome_osso, ossa_dito=None, testa=None, coda=None):
    """Il verso dorsale per QUESTO osso, secondo `MODO_DORSO`."""
    b = rig.data.bones[nome_osso]
    if MODO_DORSO == "osso_x":
        return (R3 @ b.x_axis).normalized()
    if MODO_DORSO == "osso_z":
        return (R3 @ b.z_axis).normalized()
    if MODO_DORSO == "carne" and "Thumb" in nome_osso and testa is not None:
        ## ⚠️ Il POLLICE non ha lo stesso dorso delle altre dita: la sua unghia
        ## guarda di lato, quasi novanta gradi via. Una normale unica per la mano
        ## gli mette la lamella di taglio — si vede in
        ## `esito_guanto_rollio_osso_x.png`. La regola che lo prende: **il dorso
        ## del pollice guarda VIA dalle altre dita**, quindi si punta all'opposto
        ## delle nocche, perpendicolarmente all'osso.
        verso_dita = NOCCA - (testa + coda) * 0.5
        u = (coda - testa).normalized()
        d = -(verso_dita - u * verso_dita.dot(u))
        if d.length > 1e-6:
            return d.normalized()
    if MODO_DORSO == "pelle" and ossa_dito is not None:
        d, amp = dorsale_dalla_pelle(ossa_dito, testa, coda, DORSALE_CARNE)
        gradi = math.degrees(d.angle(DORSALE_CARNE))
        print("     dorsale dalla pelle: %+.0f gradi dalla normale della mano,"
              " ampiezza %.3f%s" % (gradi, amp, "  (troppo debole: ripiego)"
                                    if amp < 0.04 else ""))
        return d
    return DORSALE_CARNE.copy()


# --- le misure della carne, prese dove devono ------------------------------
def misure_carne(ossa_dito, testa, coda, dorsale, quantile=QUANTILE):
    """I DUE semiassi della carne lungo questo segmento: laterale e dorsale.

    ⚠️ Un solo "raggio" non basta, e sulla mano l'errore e' grosso: la mano e'
    piatta, quindi la distanza dall'asse osseo e' dominata dalla LARGHEZZA (38 mm)
    e non dice niente sullo SPESSORE (~15). Una piastra costruita su quel numero
    resta sospesa sopra il dorso. Le due misure sono due cose diverse e si
    prendono separatamente.

    ⚠️ E i candidati sono solo i vertici dominati dalle ossa **di questo dito**:
    e' questo che impedisce di misurare il dito accanto. La prima versione
    sparava sonde nel vuoto e chiedeva il punto di pelle piu' vicino — a 5 cm
    dall'asse di un dito quel punto e' quello accanto, o il palmo.
    """
    asse = coda - testa
    lung = asse.length
    if lung < 1e-6:
        return None
    u = asse.normalized()
    d = dorsale - u * dorsale.dot(u)
    if d.length < 1e-6:
        return None
    d.normalize()
    lat = d.cross(u).normalized()
    laterali, dorsali = [], []
    for i in carne_di(ossa_dito):
        p = corpo.matrix_world @ corpo.data.vertices[i].co
        t = (p - testa).dot(u)
        if -0.15 * lung <= t <= 1.15 * lung:
            q = p - (testa + u * t)
            laterali.append(abs(q.dot(lat)))
            if q.dot(d) > 0.0:
                dorsali.append(q.dot(d))
    if len(laterali) < 8 or len(dorsali) < 4:
        return None
    laterali.sort()
    dorsali.sort()
    return (laterali[min(len(laterali) - 1, int(len(laterali) * quantile))],
            dorsali[min(len(dorsali) - 1, int(len(dorsali) * quantile))],
            len(laterali))


def lamella(nome, testa, coda, semi_lat, semi_dor, dorsale):
    """Una lamina che copre il DORSO del segmento: mezzo ellissoide schiacciato.

    ⚠️ La base si costruisce PER INTERO — asse dell'osso e verso dorsale — invece
    di usare `rotation_difference`, che fissa solo l'asse e lascia il ROLLIO a
    caso. Col rollio libero la meta' che tieni guarda da una parte qualunque, e a
    schermo escono lamine **di taglio** invece che appoggiate sul dorso: la
    misura era giusta e il pezzo era storto. Nel locale: +Z lungo l'osso, +Y
    dorsale, ed e' per questo che la meta' che si tiene e' quella con y grande.

    Nessuna "larghezza" scritta a mano: la sezione e' l'ellisse misurata sulla
    carne.
    """
    lung = (coda - testa).length
    if lung < 1e-5:
        return None
    u = (coda - testa).normalized()
    d = dorsale - u * dorsale.dot(u)
    if d.length < 1e-6:
        return None
    d.normalize()
    lat = d.cross(u).normalized()

    me = bpy.data.meshes.new(nome)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=14,
                          radius1=semi_dor + GIOCO,
                          radius2=(semi_dor + GIOCO) * 0.94,
                          depth=lung * ACCAVALLA)
    ## da cerchio a ellisse: il semiasse laterale e' misurato, non stimato
    k = (semi_lat + GIOCO) / (semi_dor + GIOCO)
    for v in bm.verts:
        v.co.x *= k
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -semi_dor * 0.30],
                     context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()

    ob = bpy.data.objects.new(nome, me)
    bpy.context.collection.objects.link(ob)
    base = Matrix(((lat.x, d.x, u.x), (lat.y, d.y, u.y), (lat.z, d.z, u.z))).to_4x4()
    ob.matrix_world = Matrix.Translation((testa + coda) * 0.5) @ base
    return ob


def spessore_e_smusso(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    m = ob.modifiers.new("Spessore", 'SOLIDIFY')
    m.thickness = SPESSORE
    m.offset = 1.0
    bpy.ops.object.modifier_apply(modifier=m.name)
    b = ob.modifiers.new("Smusso", 'BEVEL')
    b.width = SMUSSO
    b.segments = 2
    b.limit_method = 'ANGLE'
    b.angle_limit = math.radians(35)
    bpy.ops.object.modifier_apply(modifier=b.name)


pezzi = []

# --- le falangi -------------------------------------------------------------
print()
print("%-24s %8s %8s %8s %7s  %s"
      % ("osso", "lung", "semi_lat", "semi_dor", "vert", "nota"))


def costruisci(nome_pezzo, pieno, testa, coda, ossa_candidate, eredita=None):
    """Misura la carne, tira su la lamella, e racconta cosa ha misurato."""
    dors = dorsale_di(pieno, ossa_candidate, testa, coda)
    m = misure_carne(ossa_candidate, testa, coda, dors)
    nota = ""
    if m is None:
        ## una falange distale puo' dominare pochissima carne: si eredita dal
        ## segmento precedente, assottigliato. Meglio di una costante a mano.
        if eredita is None:
            print("  %-22s NON MISURABILE e niente da ereditare: saltata" % pieno)
            return None, None
        semi_lat, semi_dor, n = eredita[0] * 0.86, eredita[1] * 0.86, 0
        nota = "ereditato: troppa poca carne dominata"
    else:
        semi_lat, semi_dor, n = m
    ob = lamella(nome_pezzo, testa, coda, semi_lat, semi_dor, dors)
    if ob is not None:
        spessore_e_smusso(ob)
        pezzi.append(ob)
    print("  %-22s %7.4f %8.4f %8.4f %7d  %s"
          % (pieno, (coda - testa).length, semi_lat, semi_dor, n, nota))
    return ob, (semi_lat, semi_dor)


for dito, ossa in DITA.items():
    piene = [LATO + n for n in ossa if LATO + n in rig.data.bones]
    ultimo = None
    for i, nome_osso in enumerate(ossa):
        pieno = LATO + nome_osso
        if pieno not in rig.data.bones:
            print("  osso mancante:", pieno)
            continue
        testa, coda = testa_coda(pieno)
        _, ultimo = costruisci("Lam_%s_%d" % (dito, i), pieno, testa, coda,
                               piene, ultimo)

# --- il dorso della mano ----------------------------------------------------
h_testa, h_coda = testa_coda(LATO + "Hand")
## ⚠️ Il dorso copre i METACARPI: dal polso alle NOCCHE. E la nocca non e' la
## coda dell'osso `Hand` — quella e' dove il rig ha deciso di finire il segmento,
## e sul protagonista arriva a meta' del metacarpo. Le nocche sono le TESTE
## delle falangi prossimali, e si leggono. Prima la piastra si fermava a meta'
## e restava una fascia di pelle nuda prima delle dita.
_nocche = [testa_coda(LATO + DITA[d][0])[0]
           for d in ("Index", "Middle", "Ring", "Little")]
nocca = sum(_nocche, Vector()) / len(_nocche)
print("  dorso: coda dell'osso Hand a %.4f m dal polso, nocche a %.4f m"
      % ((h_coda - h_testa).length, (nocca - h_testa).length))
costruisci("Lam_Dorso", LATO + "Hand", h_testa, nocca, [LATO + "Hand"])

# --- il polsino -------------------------------------------------------------
l_testa, l_coda = testa_coda(LATO + "LowerArm")
verso_mano = (h_testa - l_testa).normalized()
polso_a = h_testa - verso_mano * 0.030
polso_b = h_testa + verso_mano * 0.004
mis = misure_carne([LATO + "LowerArm", LATO + "Hand"], polso_a, polso_b,
                   dorsale_di(LATO + "Hand"))
r_polso = max(mis[0], mis[1]) if mis else 0.030
me = bpy.data.meshes.new("Lam_Polsino")
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=20,
                      radius1=r_polso + GIOCO * 2, radius2=r_polso + GIOCO * 2,
                      depth=(polso_b - polso_a).length)
bm.to_mesh(me)
bm.free()
polsino = bpy.data.objects.new("Lam_Polsino", me)
bpy.context.collection.objects.link(polsino)
asse = (polso_b - polso_a).normalized()
polsino.matrix_world = (Matrix.Translation((polso_a + polso_b) * 0.5)
                        @ Vector((0, 0, 1)).rotation_difference(asse).to_matrix().to_4x4())
spessore_e_smusso(polsino)
pezzi.append(polsino)
print("  %-22s %7.4f %8.4f %8.4f %7d  polsino (anello: il raggio grande)"
      % ("polso", (polso_b - polso_a).length, mis[0] if mis else 0,
         mis[1] if mis else 0, mis[2] if mis else 0))
print()
print("lamelle costruite: %d" % len(pezzi))

# --- il GAMBESON: l'imbottitura che sta SOTTO le piastre --------------------
## Un guanto d'arme non e' acciaio sulla pelle: sotto c'e' sempre un guanto
## imbottito, e sulla mano — che e' la zona piu' delicata e la piu' scoperta fra
## una lamella e l'altra — e' quello che chiude i buchi.
##
## Non si genera: si RICAVA DAL CORPO. Ritagliare la superficie della mano,
## staccarla di due millimetri lungo la normale e ingrossarla da' un capo che
## copre esattamente cio' che si dichiara e aderisce PER COSTRUZIONE, perche'
## *e'* la mano. E in piu' eredita i pesi del corpo: si muove giusto senza che
## nessuno lo pesi.
##
## ⚠️ `docs/13` dice che il guscio derivato NON funziona su una mano, ed e' vero
## per un GUSCIO RIGIDO: cinque tubi sottili con pieghe profonde, e un solidify
## spesso fa compenetrare i gusci di dita vicine. Qui non e' un guscio rigido: e'
## una calzamaglia di due millimetri, e lo scostamento si SMORZA nelle pieghe —
## dove la superficie e' concava, spingere lungo la normale fa scontrare i due
## lati della piega, quindi li' non si spinge.
##
## Materiale a se': e' il pezzo che si ritinge per casata.
POLSO_SU = 0.055          # quanto risale sull'avambraccio, sotto il polsino


def fai_gambeson():
    gruppi = {g.name: g.index for g in corpo.vertex_groups}
    ossa = [LATO + "Hand"] + [LATO + n for d in DITA.values() for n in d]
    idx = {gruppi[n] for n in ossa if n in gruppi}
    i_av = gruppi.get(LATO + "LowerArm")
    p_polso, _ = testa_coda(LATO + "Hand")
    gomito, _ = testa_coda(LATO + "LowerArm")
    su = (gomito - p_polso).normalized()

    ## appartenenza: la carne della mano, piu' una rampa che risale il polso
    campo = []
    for v in corpo.data.vertices:
        w = min(1.0, sum(g.weight for g in v.groups if g.group in idx))
        if i_av is not None and w < 1.0:
            if any(g.group == i_av and g.weight > 0.0 for g in v.groups):
                d = ((corpo.matrix_world @ v.co) - p_polso).dot(su)
                if 0.0 <= d <= POLSO_SU:
                    w = max(w, 1.0 - d / POLSO_SU)
        campo.append(1.0 - w)
    campo = liscia_campo(campo, vicini_di(corpo), giri=3, forza=0.5)

    bpy.ops.object.select_all(action='DESELECT')
    corpo.select_set(True)
    bpy.context.view_layer.objects.active = corpo
    bpy.ops.object.duplicate()
    gb = bpy.context.active_object
    gb.name = "Gambeson_Mano"
    taglia_su_campo(gb, campo, 0.6)
    if not gb.data.vertices:
        print("  ⚠️ gambeson vuoto: la soglia ha tagliato tutto")
        return None

    ## ⚠️ Lo scostamento si SMORZA dove la superficie e' concava. Senza, le due
    ## pareti di una piega fra due dita si spingono l'una contro l'altra e si
    ## compenetrano — ed e' esattamente il modo in cui il guscio derivato
    ## falliva sulla mano.
    vic = vicini_di(gb)
    co = [v.co.copy() for v in gb.data.vertices]
    nor = [v.normal.copy() for v in gb.data.vertices]
    smorzati = 0
    for i, v in enumerate(gb.data.vertices):
        f = 1.0
        if vic[i]:
            d = sum((co[j] for j in vic[i]), Vector()) / len(vic[i]) - co[i]
            if d.length > 1e-9:
                k = d.dot(nor[i]) / d.length          # >0 = concavo
                f = 1.0 - max(0.0, min(1.0, k))
                if f < 0.9:
                    smorzati += 1
        v.co = co[i] + nor[i] * (IMBOTTITURA * f)
    gb.data.update()
    _sp = [ (gb.data.vertices[i].co - co[i]).length for i in range(len(co)) ]
    _nl = [ n.length for n in nor ]
    _sp.sort()
    print("  gambeson: normali |n| min %.3f max %.3f | spostamento mediano %.5f"
          " max %.5f m" % (min(_nl), max(_nl), _sp[len(_sp) // 2], _sp[-1]))

    bpy.ops.object.select_all(action='DESELECT')
    gb.select_set(True)
    bpy.context.view_layer.objects.active = gb
    m = gb.modifiers.new("Stoffa", 'SOLIDIFY')
    m.thickness = SPESSORE_GB
    m.offset = -1.0        # cresce verso l'interno: fuori resta dove l'ho messo
    bpy.ops.object.modifier_apply(modifier=m.name)
    print("  gambeson: %d vertici, %d smorzati nelle pieghe, %d gruppi di pesi"
          " ereditati dal corpo"
          % (len(gb.data.vertices), smorzati, len(gb.vertex_groups)))
    return gb


gambeson = fai_gambeson()

## ⚠️ Cancello sul gambeson: DOVE sta rispetto alla pelle, e sta SOTTO le
## piastre? Se sta sopra, spunta attraverso l'acciaio e il guanto si sbriciola a
## schermo. Il gioco della lamella (GIOCO) deve superare imbottitura + stoffa.
if gambeson is not None:
    _dists = []
    for v in gambeson.data.vertices:
        pm = gambeson.matrix_world @ v.co
        ok, loc, nor, _ = corpo.closest_point_on_mesh(corpo.matrix_world.inverted() @ pm)
        if ok:
            lm = corpo.matrix_world @ loc
            nm = (corpo.matrix_world.to_3x3() @ nor).normalized()
            _dists.append((pm - lm).dot(nm))
    _dists.sort()
    print("  gambeson sopra la pelle: mediana %+.4f  p05 %+.4f  p95 %+.4f m"
          % (_dists[len(_dists) // 2], _dists[int(len(_dists) * 0.05)],
             _dists[int(len(_dists) * 0.95)]))
    _tetto = IMBOTTITURA + SPESSORE_GB
    print("  gioco della lamella %.4f  contro  imbottitura+stoffa %.4f  ->  %s"
          % (GIOCO, _tetto,
             "OK, l'acciaio sta sopra" if GIOCO > _tetto
             else "⚠️ IL GAMBESON SPUNTA ATTRAVERSO L'ACCIAIO"))

# --- resa -------------------------------------------------------------------
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.materials.clear()
mp = bpy.data.materials.new("pelle")
mp.diffuse_color = (0.86, 0.66, 0.58, 1)
mp.roughness = 0.85
corpo.data.materials.append(mp)
ma = bpy.data.materials.new("acciaio")
ma.diffuse_color = (0.30, 0.34, 0.42, 1)
ma.metallic = 1.0
ma.roughness = 0.28
for o in pezzi:
    o.data.materials.append(ma)
if gambeson is not None:
    ## materiale a se': e' il pezzo che si ritinge per casata
    mg = bpy.data.materials.new("gambeson")
    ## ⚠️ Ben staccato dal colore della pelle: alla prima resa era un marrone
    ## chiaro e sotto la luce studio l'ho scambiato per la mano nuda — cioe' ho
    ## creduto che il gambeson non ci fosse. Due materiali che si somigliano
    ## fanno perdere tempo esattamente come due materiali diversi in un
    ## confronto.
    mg.diffuse_color = (0.19, 0.16, 0.15, 1)
    mg.roughness = 0.95
    gambeson.data.materials.clear()
    gambeson.data.materials.append(mg)
    print("  gambeson: materiali %s | hide_render %s | %d facce"
          % ([m.name for m in gambeson.data.materials], gambeson.hide_render,
             len(gambeson.data.polygons)))

## `SOLO_GAMBESON=1` per guardarlo senza l'acciaio davanti
if os.environ.get("SOLO_GAMBESON"):
    for o in pezzi:
        o.hide_render = True
if os.environ.get("SENZA_CORPO"):
    corpo.hide_render = True

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.render.resolution_x = 1300
sc.render.resolution_y = 1000
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.10, 0.12, 1)
cd = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
cd.type = 'ORTHO'

## ⚠️ L'inquadratura si prende dal FRAME DELLA MANO, non dagli assi del mondo.
## La mano e' in A-pose: il suo piano non e' allineato a niente, e guardarla da
## -Y la prende di taglio — le lamelle sembrano lame anche quando sono appoggiate.
## Meta' degli sbagli di ieri vengono da camere piazzate a occhio.
punta = testa_coda(LATO + "MiddleDistal")[1]
centro = (polso_a + punta) * 0.5
campo = (punta - polso_a).length * 1.9
_lungo = (punta - polso_a).normalized()
_lat = DORSALE_CARNE.cross(_lungo).normalized()


def scatta(direzione, alto, nome):
    """`direzione` = il verso in cui GUARDA la camera, nel frame della mano."""
    cd.ortho_scale = campo
    d = Vector(direzione).normalized()
    cam.location = centro - d * 0.6
    q = d.to_track_quat('-Z', 'Y')
    cam.rotation_euler = q.to_euler()
    ## raddrizza il rollio: la mano deve stare in verticale nell'inquadratura
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = q
    su = (alto - d * alto.dot(d)).normalized()
    attuale = (q @ Vector((0, 1, 0))).normalized()
    ang = attuale.angle(su)
    if ang > 1e-4:
        from mathutils import Quaternion
        segno = 1.0 if attuale.cross(su).dot(d) > 0 else -1.0
        cam.rotation_quaternion = Quaternion(d, -segno * ang) @ q
    sc.render.filepath = FUORI + nome
    bpy.ops.render.render(write_still=True)
    print("reso:", nome)


scatta(-DORSALE_CARNE, -_lungo, "guanto_dorso_" + MODO_DORSO)
scatta(DORSALE_CARNE, -_lungo, "guanto_palmo_" + MODO_DORSO)
scatta(_lat, -_lungo, "guanto_lato_" + MODO_DORSO)
scatta((-DORSALE_CARNE * 0.7 + _lat * 0.7).normalized(), -_lungo,
       "guanto_tre_quarti_" + MODO_DORSO)
## ─── il RITRATTO per l'image-to-image ──────────────────────────────────────
## ⚠️ Non e' un render di collaudo, e' un RIFERIMENTO da dare a un generatore
## d'immagini: quindi guanto isolato, niente corpo, formato quadrato come il
## pannello di Meshy, e fondo neutro CHIARO — su fondo scuro l'acciaio scuro
## sparisce e il generatore non vede la sagoma. Il gambeson resta: fa parte del
## pezzo, ed e' cio' che va texturizzato per casata.
if os.environ.get("RITRATTO"):
    corpo.hide_render = True
    sc.render.resolution_x = 1024
    sc.render.resolution_y = 1024
    ## ⚠️ In Blender 5.2 il workbench prende il fondo da `world.color`, non dal
    ## nodo Background: settare solo il nodo non cambia niente e il render esce
    ## col fondo di prima. Si settano tutti e due.
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.58, 0.60, 0.63, 1)
    sc.world.color = (0.58, 0.60, 0.63)
    sc.display.shading.show_cavity = False
    ## acciaio piu' chiaro: deve leggersi come metallo, non come sagoma nera
    ma.diffuse_color = (0.62, 0.65, 0.70, 1)
    ma.roughness = 0.22
    mg.diffuse_color = (0.26, 0.22, 0.20, 1)
    tutti = [o.matrix_world @ v.co for o in pezzi + ([gambeson] if gambeson else [])
             for v in o.data.vertices]
    mn = Vector((min(c.x for c in tutti), min(c.y for c in tutti), min(c.z for c in tutti)))
    mx = Vector((max(c.x for c in tutti), max(c.y for c in tutti), max(c.z for c in tutti)))
    centro_r = (mn + mx) * 0.5
    campo_r = max((c - centro_r).length for c in tutti) * 2.15
    for nome_r, dire in (
            ("ritratto_tre_quarti", (-DORSALE_CARNE * 0.78 + _lat * 0.55 - _lungo * 0.30)),
            ("ritratto_dorso", -DORSALE_CARNE),
            ("ritratto_lato", _lat)):
        cd.ortho_scale = campo_r
        d = Vector(dire).normalized()
        cam.location = centro_r - d * 0.8
        q = d.to_track_quat('-Z', 'Y')
        cam.rotation_mode = 'QUATERNION'
        su = (-_lungo - d * (-_lungo).dot(d)).normalized()
        attuale = (q @ Vector((0, 1, 0))).normalized()
        ang = attuale.angle(su)
        if ang > 1e-4:
            from mathutils import Quaternion
            segno = 1.0 if attuale.cross(su).dot(d) > 0 else -1.0
            cam.rotation_quaternion = Quaternion(d, -segno * ang) @ q
        else:
            cam.rotation_quaternion = q
        sc.render.filepath = FUORI + nome_r
        bpy.ops.render.render(write_still=True)
        print("reso:", nome_r)

print("FATTO")
