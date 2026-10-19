# -*- coding: utf-8 -*-
"""Veste un personaggio con pezzi d'armatura generati — la pipeline.

    blender --background --factory-startup --python arcanium/tools/vesti_protagonista.py

Di vestizioni ne servono a centinaia (sette casate x quattro pezzi, piu' i
nemici), quindi qui non si tara un'armatura: si tara una TABELLA. Il codice sotto
non cambia, cambia solo `VESTIZIONE`.

## Le quattro fasi

1. **Taglia e posto.** I pezzi escono da Meshy NORMALIZZATI — centrati
   sull'origine e inscritti in un cubo di lato 1.9, senza nessun rapporto col
   corpo. Si portano alla misura voluta e si mettono dove vanno.
2. **Gonfiatura.** Un'armatura deve stare SOPRA il corpo, con un margine. Senza,
   si vede la pelle sbucare da tutte le parti — e per costruzione, visto che la
   piastra ha lo spessore di zero.
3. **Legatura.** I pesi si trasferiscono dal corpo NUDO: e' esattamente la
   superficie che la piastra ricopre, quindi non e' la trappola del donatore
   vestito che il progetto ha gia' pagato due volte.
4. **Irrigidimento.** Vedi sotto: senza, l'acciaio si piega come stoffa.

## ⚠️⚠️ L'ACCIAIO NON SI PIEGA — e due cure sbagliate prima di quella buona

1. **Pesi trasferiti e basta.** La piastra si deforma come la carne che copre.
   Guardato in un affondo profondo: la corazza si torceva col busto, le
   ginocchiere si accartocciavano, i guanti si sfaldavano sulle dita.
2. **Tagliare in pezzi rigidi separati**, uno per osso. L'acciaio diventa
   acciaio, ma un guscio UNICO tagliato in segmenti si APRE: fra una piastra e
   l'altra non c'e' materiale di sovrapposizione, perche' la mesh generata e' un
   pezzo solo e non un insieme di lamine. Si vedeva la gamba nei varchi.

**Quella che funziona: AFFILARE i pesi** (`AFFILATURA`, esponente 6). Si tengono
i pesi trasferiti, si elevano a potenza e si rinormalizza. Nel mezzo di una
piastra un osso domina gia' e l'esponente lo porta a ~1.0: quella zona diventa
rigida. Sul giunto due ossa se lo contendono quasi alla pari, e li' la sfumatura
resta — una fascia stretta che flette e TIENE INSIEME le piastre. Nessun taglio,
nessun buco, una manopola sola. Misurato: dominanza mediana 0,998, 62% dei
vertici gia' completamente rigidi.

⚠️ **L'eccezione**: un guscio grande e continuo — un pettorale — va tutto su UN
osso solo, e si dichiara mettendo una sola voce in `ossa`. Affilare non basta,
perche' i pesi lo dividerebbero fra le vertebre e lo si vedrebbe incernierarsi
in tre tronconi. Un pettorale vero e' appeso alle spalle ed e' rigido.

## ⚠️ I pezzi degli ARTI vanno ruotati, il busto no

Meshy li genera verticali, appesi. Le braccia in A-pose stanno a 47 gradi sotto
l'orizzontale, quindi un bracciale incollato dritto entra nel fianco. Si divide
il pezzo in destro/sinistro e si ruota ciascuno sull'asse osso→osso, che si
LEGGE dallo scheletro invece di stimarlo. Le gambe no: sono a 4.3 gradi dalla
verticale e la differenza non si vede.

## ⚠️⚠️ IL .glb ESPORTATO VUOLE LO STESSO IMPORT DEL CORPO

Questo script pesa le piastre sulle 61 ossa del corpo, ma il rest su cui le pesa
e' quello di **Blender**. Godot pero' importa il corpo con `retarget/bone_map` e
`rest_fixer/fix_silhouette`, che gli RISCRIVONO il rest. Se il .glb dell'armatura
non ha le stesse impostazioni d'import, le piastre restano pesate su un rest e
vengono guidate da un altro.

Non e' un dettaglio: misurato fra i due scheletri, bacino e torace coincidevano
ma la MANO era fuori di 56 cm e le ossa degli arti ruotate fino a 172 gradi. In
gioco la corazza sembrava a posto e le ginocchiere stavano a meta' coscia.

Quindi: **ogni nuovo set d'armatura copia il blocco `_subresources` di
`protagonista_v4.glb.import` nel proprio `.import`**, con lo stesso percorso di
nodo (`PATH:BaseArmature/Skeleton3D`). Vedi `prima_veglia_set.glb.import`.

## ⚠️ Saldare PRIMA di dividere

Le mesh Meshy arrivano coi vertici spezzati sulle cuciture UV. `separate LOOSE`
su un pezzo non saldato non vede due bracciali: ne vede DUEMILADUECENTOSESSANTASEI,
e i due piu' grossi hanno 141 vertici.
"""
import bpy, os, sys, math, bmesh
from mathutils import Vector
from mathutils.kdtree import KDTree

RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")).replace("\\", "/")
CORPO = RADICE + "/assets/characters/base_body/protagonista_v4.glb"
ARMOR = RADICE + "/assets/characters/armor/"
## ⚠️ Un SET per file. La tabella non e' piu' una sola: i pezzi di casate
## diverse non vanno nello stesso `.glb`, o il manto del Branco Guasto finirebbe
## dentro `prima_veglia_set.glb` e ce lo si porterebbe dietro per sempre.
##
##     blender --background --factory-startup --python vesti_protagonista.py -- <set>
##
## Senza argomento si costruiscono TUTTI i set.

## `alto`/`basso`  dove arriva sul corpo, in metri di mondo (pezzi del BUSTO)
## `arto`          coppia di ossa che da' asse e lunghezza (pezzi degli ARTI)
## `gonfia`        quanto sta LARGO sopra il corpo. 1.0 = aderente = si vede la pelle
## `ancora`        cosa resta fermo mentre gonfia: "basso", "centro", "polsino"
## `regione`       la carne CONTRO CUI conformare. Vuoto = tutto il corpo.
##
##                 ⚠️ NON e' `ossa`: quello dice da quale osso il pezzo e' MOSSO,
##                 questo quale carne COPRE. Sulla corazza differiscono molto —
##                 e' rigida su UpperChest ma copre petto, schiena, spalle e
##                 fianchi. Prendendo `ossa` come regione, il pettorale si
##                 conformava contro un francobollo di 1.016 vertici e il 76%
##                 dei suoi vertici risultava "dentro la carne".
##
##                 Serve dichiararla sugli ARTI PARI: conformare una gamba contro
##                 tutto il corpo la spinge fuori rispetto all'ALTRA gamba, e i
##                 due gambali si incrociano. Visto in gioco.
## `taglia_su`     ossa su cui il pezzo NON deve arrivare: tutto cio' che sta
##                 sopra la loro carne viene TAGLIATO VIA. Serve quando la mesh
##                 generata comprende una parte che non si vuole (o che e'
##                 sbagliata). Il taglio non e' a occhio ne' a quota fissa: per
##                 ogni vertice si guarda su quale osso pesa il punto del corpo
##                 piu' vicino.
## `taglio`        quale regola usa `taglia_su`: "osso" (default) o "vicinanza".
##                 Sono due strumenti diversi e si scelgono per pezzo — vedi
##                 `campo_di_taglio`. Un pezzo tarato non cambia perche' ne
##                 arriva uno nuovo.
## `cinghia`       CIRCONFERENZA, separata dalla lunghezza. 1.0 = quella che
##                 viene dalla scala uniforme.
##
##                 ⚠️ Senza, la scala e' UNIFORME: allungare un pezzo per fargli
##                 coprire piu' arto lo fa grasso nella stessa misura. Portare i
##                 bracciali dal gomito alla SPALLA e' un allungamento di 1,66x
##                 (0,442 m -> 0,732 m misurati sul rest), e uniforme darebbe un
##                 barile invece di una brachiale. Con `cinghia` la lunghezza la
##                 detta la catena delle ossa e la circonferenza si tara a parte.
## `conforma`      `(stacco, fascia)`: lo stacco della piastra dalla pelle e la
##                 larghezza della sfumatura del peso di aderenza. Vedi
##                 `conforma_al_corpo` — e' li' che sta la trappola del `wrap_mode`.
## `affondo`       quanto in giu' arriva la fascia di aderenza, sotto la pelle.
##                 Opzionale: senza, vale `AFFONDO` (35 mm). Un vertice piu'
##                 sepolto di cosi' NON si tira fuori: e' una parte del pezzo che
##                 sta dentro il corpo, non la parete interna che si appoggia, e
##                 tirarla fuori la spezza. Sepolta e' invisibile, catapultata e'
##                 una scheggia.
## `ossa`          i segmenti che il pezzo attraversa. UNA voce = guscio rigido
PRIMA_VEGLIA = {
    "corazza": {
        "file": "corazza_prima_veglia.glb",
        ## ⚠️ ALZATA di 5 cm il 2026-08-21 (era 1.60/0.91). Lo scollo e' una scodella
        ## larga e bassa: sulla mediana il bordo stava a z=1.550 contro il collo a
        ## 1.592, e su un uomo leggeva come una scollatura. Ora il bordo arriva a
        ## 1.600, appena sopra la base del collo, e le clavicole sono coperte.
        ##
        ## ⚠️ Cinque, non quindici: provati tutti e due e guardati. A +15 il
        ## colletto arriva al mento e la testa ci finisce dentro
        ## (`esito_corazza_su15_troppo.png`).
        ##
        ## ⚠️ E si alza solo `alto`, non tutti e due. Spostando il pezzo intero
        ## lo scollo chiudeva ma la FALDA saliva con lui e scopriva l'inguine:
        ## chiusa una scollatura, aperta l'altra. Tenendo fermo `basso` il pezzo
        ## si allunga verso l'alto e l'orlo resta dov'era — al prezzo di
        ## `cinghia`, che rimette a posto la circonferenza.
        "alto": 1.65, "basso": 0.91, "centro_y": 0.02,
        "arto": None, "gonfia": 1.10, "ancora": "centro",
        ## ⚠️ `cinghia` compensa l'allungamento. Alzando solo `alto` il pezzo si
        ## allunga di 5 cm, e siccome la scala e' UNIFORME diventa anche il 7%
        ## piu' largo: una corazza gonfia. 0.93 = 0.69/0.74, cioe' esattamente
        ## il rapporto fra l'altezza di prima e quella di adesso, quindi la
        ## circonferenza resta quella tarata.
        "cinghia": 0.93,
        ## Un pettorale e' un guscio unico appeso alle spalle: un osso solo.
        "ossa": ["UpperChest"],
        ## Sta in RILIEVO, quindi la conformazione qui non deve appiattire niente:
        ## col vertex group tocca solo cio' che il corpo attraversa — collo,
        ## ascelle, il bordo della falda. Fascia stretta apposta.
        "conforma": (0.012, 0.016),
    },
    "gambali": {
        "file": "gambali_prima_veglia.glb",
        "alto": 1.06, "basso": -0.01, "centro_y": 0.00,
        "arto": None, "gonfia": 1.12, "ancora": "basso",
        ## Circonferenza oltre la scala uniforme: a 1.0 restavano strisce di pelle
        ## nude sull'interno coscia e su tutti e due i lati dei polpacci, e a 1.10
        ## si stringono in modo visibile — confrontate due foto nella stessa
        ## inquadratura sul banco.
        ##
        ## ⚠️ 1.20 sfonda: le ginocchiere delle DUE gambe si compenetrano al
        ## centro e spuntano schegge ai lati. Il limite non e' la gamba, e' l'altra
        ## gamba.
        "cinghia": 1.02,
        ## ⚠ Due gusci, uno per gamba: vanno DIVISI prima di gonfiare.
        ## Gonfiando il pezzo intero attorno al suo centro — che sta in mezzo
        ## alle due gambe — le piastre si allontanano l'una dall'altra e la
        ## pelle resta scoperta nel mezzo. Provato e guardato.
        "dividi_lati": True, "centra_su": "UpperLeg",
        ## Sei pezzi rigidi: coscia, stinco e calzare per lato.
        "ossa_lato": ["UpperLeg", "LowerLeg", "Foot"],
        ## ⚠️ La regione include le ANCHE anche se il pezzo non ci pesa: il gambale
        ## arriva a 1.06, sopra l'articolazione, e se il bersaglio finisce li' le
        ## query di punto-piu'-vicino cadono sul BORDO della mesh ritagliata e
        ## danno normali impazzite. Risultato guardato: la coscia si sbriciolava in
        ## schegge, e quelle si accavallavano fra le due gambe. Il bersaglio deve
        ## continuare oltre il pezzo, non finire sotto di lui.
        "regione": ["UpperLeg", "LowerLeg", "Foot", "Hips"],
        ## AVVOLGENTE: e' il pezzo che ci guadagna di piu', le strisce di pelle
        ## nuda stavano sull'interno coscia e sui lati dei polpacci.
        "conforma": (0.010, 0.024),
    },
    "bracciali": {
        "file": "bracciali_prima_veglia.glb",
        ## ⚠️ DAL GOMITO, e non e' pigrizia: portarlo alla SPALLA e' stato provato
        ## e guardato, due volte. Non e' un problema di circonferenza — con
        ## `cinghia` 0.60 il tubo era troppo stretto e il braccio ne usciva di
        ## sopra, con 0.88 era grasso e restava lo stesso sotto il braccio, e in
        ## tutti e due i casi **la spalla restava nuda**.
        ##
        ## La ragione e' geometrica: il pezzo viene posato lungo la CORDA fra i
        ## due ossi, e la catena spalla→gomito→dita NON e' dritta. Un tubo
        ## rettilineo su un arto che piega passa sotto il gomito, comunque lo si
        ## dimensioni. Gomito→dita invece e' quasi rettilineo, ed e' per questo
        ## che il disegno sta cosi'.
        ##
        ## Il braccio scoperto fra spalliera e bracciale si copre con un altro
        ## pezzo o col gambeson, non allungando questo.
        ## Dichiarato sul BRACCIO INTERO: e' la dichiarazione che porta la
        ## copertura, e la conformazione fa il resto. La scala uniforme lo rende
        ## grasso, e va bene: lo shrinkwrap lo tira sull'anatomia.
        "arto": ("UpperArm", "MiddleDistal"), "margine": 1.0,
        "gonfia": 1.10, "ancora": "polsino",
        ## ⚠️⚠️ IL GUANTO SI TAGLIA VIA, e il motivo e' grave: Meshy l'ha generato
        ## con SEI DITA. Cinque in fila piu' il pollice — contate col cancello
        ## `arcanium/tools/conta_dita.py`, x da +0,272 a +0,483 equispaziate.
        ## Nessuna tecnica di vestizione mappa sei dita su cinque.
        ##
        ## Rifare il guanto ricavandolo dal corpo e' stato provato e NON funziona:
        ## una mano non e' un arto (cinque tubi sottili con pieghe profonde), e
        ## tutte e cinque le strade falliscono — vedi docs/13. Il guanto vero si
        ## modellera' una volta sola, come asset a se': una mano e' una mano, e
        ## quello stesso guanto varra' per ogni armatura di ogni casata.
        ##
        ## Intanto questo set ha i bracciali SENZA guanto, che e' un look
        ## legittimo e non blocca niente.
        "taglia_su": ["Hand", "ThumbMetacarpal", "ThumbProximal", "ThumbDistal",
                      "IndexProximal", "IndexIntermediate", "IndexDistal",
                      "MiddleProximal", "MiddleIntermediate", "MiddleDistal",
                      "RingProximal", "RingIntermediate", "RingDistal",
                      "LittleProximal", "LittleIntermediate", "LittleDistal"],
        ## Due segmenti: omero e avambraccio. La manica finisce al polso.
        "ossa": ["UpperArm", "LowerArm"],
        ## AVVOLGENTE.
        "conforma": (0.009, 0.022),
    },
}

## ⚠️ Il MANTO non e' acciaio: e' una giacca di cuoio e pelliccia, e va trattata
## da stoffa. Due differenze che contano.
##
## 1. `morbido`: i pesi del corpo si tengono COSI' COME SONO. L'affilatura
##    serve a far comportare da acciaio una piastra che altrimenti si piega
##    come carne — su una giacca farebbe il contrario del vero, un cuoio che
##    non si piega alle spalle.
## 2. Copre busto E braccia, fino a meta' avambraccio. E' l'unico pezzo finora
##    che attraversa la spalla, cioe' il giunto peggiore.
##
## ⚠️ Misurato sul corpo: collo z=1.592, anca z=1.014, spalla x=0.199, polso
## x=0.475. Scalando la giacca sull'altezza del busto le maniche arrivano a
## x~0.33 contro i 0.41 dell'avambraccio: restano CORTE. `cinghia` allarga
## anche il busto, quindi non e' la manopola giusta — se ne riparla guardando.
BRANCO_GUASTO = {
    "manto": {
        "file": "assets/equipment/PlayerEquipment/manto_branco_guasto.glb",
        "alto": 1.64, "basso": 0.93, "centro_y": 0.02,
        "arto": None, "gonfia": 1.06, "ancora": "centro",
        "cinghia": 1.10,
        "ossa": ["UpperChest", "Spine", "LeftShoulder", "RightShoulder"],
        ## ⚠️ VIA LE MANICHE. Il pezzo e' disegnato con le maniche perche' nasce
        ## da prima che i bracciali fossero un pezzo a se': ora quel tratto di
        ## braccio appartiene a loro, e due capi sullo stesso avambraccio si
        ## compenetrano. Il taglio e' sull'appartenenza ossea, quindi la
        ## pelliccia che drappeggia sulla SPALLA resta — se ne va solo cio' che
        ## sta sopra la carne del braccio.
        "taglia_su": ["LeftUpperArm", "LeftLowerArm", "LeftHand",
                      "RightUpperArm", "RightLowerArm", "RightHand"],
        ## ⚠️ "vicinanza" e non "osso": i polsini stanno staccati dal braccio, e
        ## la regola per osso li terrebbe (la loro carne piu' vicina e' l'anca).
        "taglio": "vicinanza",
        "morbido": True,
        ## la carne che copre: busto e braccia, non le gambe
        "regione": ["UpperChest", "Chest", "Spine", "Hips", "Neck",
                    "LeftShoulder", "LeftUpperArm", "LeftLowerArm",
                    "RightShoulder", "RightUpperArm", "RightLowerArm"],
        "conforma": (0.008, 0.020),
    },
}

SET = {
    "prima_veglia": (ARMOR + "prima_veglia_set.glb", PRIMA_VEGLIA),
    "branco_guasto": (ARMOR + "branco_guasto_set.glb", BRANCO_GUASTO),
}

## ⚠️ UN SET PER ESECUZIONE, non tutti in un giro. Lo script e' lineare e
## distruttivo — a fine corsa cancella il corpo per esportare solo le piastre —
## quindi un secondo giro nella stessa sessione lavorerebbe su una scena mezza
## smontata. Costruirli tutti significa invocarlo una volta per set.
_scelti = [a for a in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
           if not a.startswith("-")]
NOME_SET = _scelti[0] if _scelti else "prima_veglia"
if NOME_SET not in SET:
    raise SystemExit("set sconosciuto: %s (ne conosco %s)" % (NOME_SET, list(SET)))
DEST, VESTIZIONE = SET[NOME_SET]
print("=== set: %s -> %s" % (NOME_SET, os.path.basename(DEST)))

SALDATURA = 0.0001
ANGOLO_SPIGOLO = math.radians(35)


def bbox(o):
    co = [o.matrix_world @ v.co for v in o.data.vertices]
    return (Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co))),
            Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co))))


def importa(percorso):
    prima = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=percorso)
    return [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - prima]


def attivo(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def salda_e_liscia(o):
    """Salda le cuciture UV e rifa' le normali ad ANGOLO.

    ⚠️ Le normali custom sopravvivono alla saldatura ma restano incoerenti sui
    vertici fusi, e la piastra si copre di brulichio. Si buttano. E si rifa' lo
    shading ad angolo, non liscio dappertutto: liscio sulle curve, NETTO sugli
    spigoli — uno shade smooth totale arrotonda i bordi delle lame.
    """
    attivo(o)
    prima = len(o.data.vertices)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=SALDATURA)
    bpy.ops.object.mode_set(mode='OBJECT')
    if o.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    try:
        bpy.ops.object.shade_auto_smooth(angle=ANGOLO_SPIGOLO)
    except AttributeError:
        for p in o.data.polygons:
            p.use_smooth = True
    return prima, len(o.data.vertices)


def gonfia(o, fattore, ancora, riferimento=None):
    """Ingrandisce il pezzo tenendo fermo cio' che deve restare fermo."""
    if abs(fattore - 1.0) < 1e-6:
        return
    mn, mx = bbox(o)
    if ancora == "basso":
        fermo = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    elif ancora == "polsino":
        fermo = riferimento
    else:
        fermo = (mn + mx) / 2
    o.scale = o.scale * fattore
    bpy.context.view_layer.update()
    mn2, mx2 = bbox(o)
    if ancora == "basso":
        nuovo = Vector(((mn2.x + mx2.x) / 2, (mn2.y + mx2.y) / 2, mn2.z))
    elif ancora == "polsino":
        ## il polsino non e' un estremo del bbox: si ricalcola dal centro
        nuovo = riferimento
    else:
        nuovo = (mn2 + mx2) / 2
    o.location += fermo - nuovo
    bpy.context.view_layer.update()


def _vicini(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    fuori = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    bm.free()
    return fuori


def liscia_campo(valori, vicini, giri=8, forza=0.65):
    """Media un campo scalare coi vicini PRIMA di tagliarlo su una soglia.

    Senza, il bordo segue il rumore dei pesi: frastagliato, e con buchi dove un
    vertice isolato sta appena sotto soglia.
    """
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
    """Taglia la mesh ESATTAMENTE sulla curva di livello, tenendo il sotto-soglia.

    ⚠️ Lisciare il campo non basta: cancellando VERTICI interi il bordo puo' solo
    seguire gli spigoli, e viene a scaletta lo stesso. Qui gli spigoli che
    attraversano la soglia si spezzano nel punto esatto, e il bordo cade dove il
    campo vale davvero `soglia`.
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
    for e, t in incroci:
        try:
            _, nv = bmesh.utils.edge_split(e, e.verts[0], t)
            val[nv] = soglia
        except (ValueError, RuntimeError):
            pass
    via = [v for v in bm.verts if val.get(v, 0.0) > soglia + 1e-9]
    bmesh.ops.delete(bm, geom=via, context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return len(incroci), len(via)



def via_le_isole_piccole(ob, frazione=0.05):
    """Butta i pezzi che il TAGLIO ha staccato dal corpo principale.

    ⚠️ Serve perche' il taglio per appartenenza ossea non li prende. Sul manto
    del Branco Guasto, tolte le maniche, restavano i due POLSINI: appesi vicino
    ai fianchi, la loro carne piu' vicina non era piu' il braccio ma il bacino,
    quindi il campo li dichiarava "da tenere". Erano detriti, e a schermo erano
    due tubi che galleggiavano.

    La regola e' topologica, non geometrica: un pezzo del busto e' UN guscio, e
    cio' che il taglio ha staccato non fa piu' parte del capo.
    """
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    visti, isole = set(), []
    for v in bm.verts:
        if v.index in visti:
            continue
        pila, gruppo = [v.index], []
        visti.add(v.index)
        while pila:
            i = pila.pop()
            gruppo.append(i)
            for e in bm.verts[i].link_edges:
                k = e.other_vert(bm.verts[i]).index
                if k not in visti:
                    visti.add(k)
                    pila.append(k)
        isole.append(gruppo)
    if len(isole) <= 1:
        bm.free()
        return len(isole), 0
    isole.sort(key=len, reverse=True)
    soglia = len(isole[0]) * frazione
    via = [i for g in isole[1:] if len(g) < soglia for i in g]
    if via:
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in via], context='VERTS')
        bm.to_mesh(ob.data)
        ob.data.update()
    bm.free()
    return len(isole), len(via)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=CORPO)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
corpo = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o is not corpo:
        bpy.data.objects.remove(o, do_unlink=True)

## ⚠️ Il corpo va SALDATO come i pezzi, e per lo stesso motivo: da glTF arriva
## spezzato su ogni cucitura UV. Misurato su protagonista_v4: 66.190 vertici e
## **12.312 spigoli di bordo**, cioe' una superficie aperta dappertutto. Il
## bersaglio della conformazione ne ereditava i buchi — nella regione della gamba
## il PIEDE restava un'isola staccata (`esito_bersaglio_bucato.png`) — e su una
## superficie aperta il "dentro" non e' definito: il punto piu' vicino cade sul
## bordo e la normale la' vale quello che vale. Saldato: 59.878 vertici, 0 bordi.
_prima = len(corpo.data.vertices)
attivo(corpo)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=SALDATURA)
bpy.ops.object.mode_set(mode='OBJECT')
print("corpo:", corpo.name, "%d -> %d vert (saldato)" % (_prima, len(corpo.data.vertices)),
      "| rig:", rig.name, len(rig.data.bones), "ossa")


def osso(nome):
    return rig.matrix_world @ rig.data.bones[nome].head_local


## Indice spaziale del corpo: serve a chiedere "il punto piu' vicino del corpo,
## su quale osso pesa?" — cioe' a tagliare un pezzo dove finisce la sua regione.
_kd = KDTree(len(corpo.data.vertices))
for _i, _v in enumerate(corpo.data.vertices):
    _kd.insert(corpo.matrix_world @ _v.co, _i)
_kd.balance()
_gruppi_corpo = {g.name: g.index for g in corpo.vertex_groups}


_kd_regioni = {}


def _kd_delle_ossa(ossa):
    """Un indice spaziale della sola carne DOMINATA da quelle ossa."""
    chiave = tuple(sorted(ossa))
    if chiave in _kd_regioni:
        return _kd_regioni[chiave]
    idx = {_gruppi_corpo[n] for n in ossa if n in _gruppi_corpo}
    punti = []
    for v in corpo.data.vertices:
        migliore, peso = None, 0.0
        for g in v.groups:
            if g.weight > peso:
                peso, migliore = g.weight, g.group
        if migliore in idx:
            punti.append(corpo.matrix_world @ v.co)
    kd = KDTree(max(1, len(punti)))
    for i, p in enumerate(punti):
        kd.insert(p, i)
    kd.balance()
    _kd_regioni[chiave] = (kd, len(punti))
    return _kd_regioni[chiave]


def campo_di_taglio(pezzo, ossa_via, ossa_resta, modo="osso"):
    """1 dove il pezzo va TAGLIATO, 0 dove va tenuto. Due regole, si sceglie.

    ⚠️⚠️ Sono due strumenti diversi, e si DICHIARANO per pezzo (`taglio` nella
    tabella). Non e' un dettaglio di implementazione: cambiare la regola comune
    per far contento un pezzo nuovo rimette in discussione ogni pezzo gia'
    tarato. E' successo — allargando la regola per il manto del Branco Guasto i
    bracciali si sono accorciati di trecento vertici, e nessuno l'aveva chiesto.
    Un pezzo tarato deve restare tarato.

    **"osso"** — l'osso che DOMINA il punto di corpo piu' vicino. Se quel punto
    non appartiene ne' alle ossa da togliere ne' a quelle da tenere, TIENE.
    E' la regola dei pezzi degli arti: sul bracciale il confine cade al polso,
    dove la carne passa dall'avambraccio alla mano, ed e' esattamente dove deve.

    **"vicinanza"** — si confronta la distanza dalle due carni. Serve quando il
    pezzo ha parti STACCATE dal corpo, dove il punto piu' vicino non dice
    niente: sul manto, tolte le maniche, restavano i due polsini appesi ai
    fianchi, perche' la loro carne piu' vicina era l'anca — che non sta in
    nessuna delle due liste, e "nessuno dei due" per la regola "osso" vuol dire
    tieni. Col confronto di distanze il polsino e' piu' vicino al braccio che al
    busto, e se ne va.

    ⚠️ E "vicinanza" NON e' un miglioramento da applicare a tutti: al polso la
    carne della mano e' piu' vicina di quella dell'avambraccio, quindi su un
    bracciale taglierebbe troppo presto.
    """
    if modo not in ("osso", "vicinanza"):
        raise SystemExit("taglio sconosciuto: %s (osso | vicinanza)" % modo)
    mw = pezzo.matrix_world
    grezzo = []
    if modo == "vicinanza":
        kd_via, n_via = _kd_delle_ossa(ossa_via)
        kd_resta, n_resta = _kd_delle_ossa(ossa_resta)
        if n_via == 0 or n_resta == 0:
            raise SystemExit("taglia_su: regione vuota (via %d, resta %d)"
                             % (n_via, n_resta))
        for v in pezzo.data.vertices:
            p = mw @ v.co
            _, _, d_via = kd_via.find(p)
            _, _, d_resta = kd_resta.find(p)
            grezzo.append(1.0 if d_via < d_resta else 0.0)
        return liscia_campo(grezzo, _vicini(pezzo))

    idx_via = {_gruppi_corpo[n] for n in ossa_via if n in _gruppi_corpo}
    idx_resta = {_gruppi_corpo[n] for n in ossa_resta if n in _gruppi_corpo}
    for v in pezzo.data.vertices:
        _, i, _ = _kd.find(mw @ v.co)
        p_via = p_resta = 0.0
        for g in corpo.data.vertices[i].groups:
            if g.group in idx_via:
                p_via += g.weight
            elif g.group in idx_resta:
                p_resta += g.weight
        grezzo.append(1.0 if p_via > p_resta else 0.0)
    return liscia_campo(grezzo, _vicini(pezzo))


indossati = []   # (oggetto, ossa-segmento, configurazione, regione)

for nome, cfg in VESTIZIONE.items():
    ## ⚠️ Un percorso con "/" e' relativo alla RADICE del progetto: non tutti i
    ## pezzi stanno in `assets/characters/armor/` (il manto sta fra
    ## l'equipaggiamento del giocatore).
    _sorgente = (RADICE + "/" + cfg["file"]) if "/" in cfg["file"] else (ARMOR + cfg["file"])
    pezzi = importa(_sorgente)
    m = max((o for o in pezzi if o.type == 'MESH'), key=lambda o: len(o.data.vertices))
    for o in pezzi:
        if o is not m:
            bpy.data.objects.remove(o, do_unlink=True)
    m.name = "PV_" + nome.capitalize()
    attivo(m)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    prima, dopo = salda_e_liscia(m)
    print("  %-10s saldatura %d -> %d vertici" % (nome, prima, dopo))

    if cfg["arto"] is None and not cfg.get("dividi_lati"):
        mn, mx = bbox(m)
        scala = (cfg["alto"] - cfg["basso"]) / (mx.z - mn.z)
        cin = cfg.get("cinghia", 1.0)
        m.scale = (scala * cin, scala * cin, scala)
        bpy.context.view_layer.update()
        mn, mx = bbox(m)
        m.location += Vector((0.0 - (mn.x + mx.x) / 2,
                              cfg["centro_y"] - (mn.y + mx.y) / 2,
                              (cfg["alto"] + cfg["basso"]) / 2 - (mn.z + mx.z) / 2))
        bpy.context.view_layer.update()
        gonfia(m, cfg["gonfia"], cfg["ancora"])
        ## ⚠️ `taglia_su` vale anche sui pezzi del BUSTO, non solo sugli arti.
        ## Serviva sul manto del Branco Guasto: e' una giacca con le maniche,
        ## disegnata quando i bracciali non esistevano ancora. Ora i bracciali
        ## sono un pezzo a se', e le maniche vanno via — tagliate dove finisce
        ## la carne della spalla, non a una quota inventata.
        ##
        ## ⚠️ Qui i nomi delle ossa sono INTERI (`LeftUpperArm`): un pezzo del
        ## busto non ha un lato, quindi non c'e' nessun prefisso da aggiungere.
        if cfg.get("taglia_su"):
            attivo(m)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            n_inc, n_via = taglia_su_campo(
                m, campo_di_taglio(m, cfg["taglia_su"], cfg["ossa"],
                                   cfg.get("taglio", "osso")))
            n_isole, n_detriti = via_le_isole_piccole(m)
            print("  %-10s tagliato: %d spigoli sulla curva, %d vertici via;"
                  " %d isole, %d vertici di detrito buttati"
                  % (nome, n_inc, n_via, n_isole, n_detriti))
        mn, mx = bbox(m)
        print("  %-10s x%.3f gonfiata x%.2f -> z %.3f..%.3f  largh %.3f  prof %.3f"
              % (nome, scala, cfg["gonfia"], mn.z, mx.z, mx.x - mn.x, mx.y - mn.y))
        indossati.append((m, cfg["ossa"], cfg, cfg.get("regione")))
        continue

    if cfg.get("dividi_lati") and cfg["arto"] is None:
        attivo(m)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.separate(type='LOOSE')
        bpy.ops.object.mode_set(mode='OBJECT')
        lati = sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
                      key=lambda o: len(o.data.vertices), reverse=True)
        print("  %-10s %d gusci (vertici: %s)"
              % (nome, len(lati), [len(t.data.vertices) for t in lati[:4]]))
        assert len(lati) >= 2, "attesi due gusci, la saldatura non ha funzionato"
        for o in lati[2:]:
            bpy.data.objects.remove(o, do_unlink=True)
        for t in lati[:2]:
            mn, mx = bbox(t)
            lato = "Left" if (mn.x + mx.x) / 2 > 0 else "Right"
            t.name = "PV_" + nome.capitalize()[:-1] + "_" + lato[0]
            scala = (cfg["alto"] - cfg["basso"]) / (mx.z - mn.z)
            cin = cfg.get("cinghia", 1.0)
            t.scale = (scala * cin, scala * cin, scala)
            bpy.context.view_layer.update()
            mn, mx = bbox(t)
            ## Centrato sulla SUA gamba, non sull'asse del corpo.
            asse = osso(lato + cfg["centra_su"])
            t.location += Vector((asse.x - (mn.x + mx.x) / 2,
                                  cfg["centro_y"] - (mn.y + mx.y) / 2,
                                  (cfg["alto"] + cfg["basso"]) / 2 - (mn.z + mx.z) / 2))
            bpy.context.view_layer.update()
            gonfia(t, cfg["gonfia"], cfg["ancora"])
            mn, mx = bbox(t)
            print("     %-18s x%.3f gonfiato x%.2f  z %.3f..%.3f  largh %.3f"
                  % (t.name, scala, cfg["gonfia"], mn.z, mx.z, mx.x - mn.x))
            indossati.append((t, [lato + n for n in cfg["ossa_lato"]], cfg,
                              [(lato + n) if (lato + n) in _gruppi_corpo else n
                               for n in cfg.get("regione", cfg["ossa_lato"])]))
        continue

    # ─── pezzi degli arti: si dividono, e ognuno si allinea al suo osso ──────
    su, giu = cfg["arto"]
    attivo(m)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='LOOSE')
    bpy.ops.object.mode_set(mode='OBJECT')
    tronconi = sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
                      key=lambda o: len(o.data.vertices), reverse=True)
    print("  %-10s %d tronconi (vertici: %s)"
          % (nome, len(tronconi), [len(t.data.vertices) for t in tronconi[:4]]))
    assert len(tronconi) >= 2, "attesi due pezzi, la saldatura non ha funzionato"
    for o in tronconi[2:]:
        bpy.data.objects.remove(o, do_unlink=True)

    for t in tronconi[:2]:
        mn, mx = bbox(t)
        lato = "Left" if (mn.x + mx.x) / 2 > 0 else "Right"
        t.name = "PV_" + nome.capitalize()[:-1] + "_" + lato[0]
        gomito, punta = osso(lato + su), osso(lato + giu)
        direzione = punta - gomito
        lunghezza = direzione.length * cfg["margine"]
        direzione.normalize()
        scala = lunghezza / (mx.z - mn.z)
        ## Il pezzo scende lungo -Z: il polsino in alto, le dita in basso.
        t.rotation_mode = 'QUATERNION'
        t.rotation_quaternion = Vector((0, 0, -1)).rotation_difference(direzione)
        ## La Z LOCALE e' l'asse dell'arto (il pezzo scende lungo -Z), quindi la
        ## lunghezza sta in Z e la circonferenza in X/Y. La scala e' locale e si
        ## applica prima della rotazione: qui separarle e' legittimo.
        cin = cfg.get("cinghia", 1.0)
        t.scale = (scala * cin, scala * cin, scala)
        bpy.context.view_layer.update()
        mn2, mx2 = bbox(t)
        t.location += gomito - ((mn2 + mx2) / 2 - direzione * (lunghezza / 2))
        bpy.context.view_layer.update()
        gonfia(t, cfg["gonfia"], "polsino", gomito)

        ## Taglio della parte che non si vuole (vedi `taglia_su` nella tabella).
        if cfg.get("taglia_su"):
            attivo(t)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            via = [lato + n for n in cfg["taglia_su"]]
            resta = [lato + n for n in cfg["ossa"]]
            n_inc, n_via = taglia_su_campo(
                t, campo_di_taglio(t, via, resta, cfg.get("taglio", "osso")))
            print("     %-18s tagliato: %d spigoli sulla curva, %d vertici via"
                  % (t.name, n_inc, n_via))
        print("     %-18s x%.3f gonfiato x%.2f  lungh %.3f  dir (%.2f, %.2f, %.2f)"
              % (t.name, scala, cfg["gonfia"], lunghezza,
                 direzione.x, direzione.y, direzione.z))
        indossati.append((t, [lato + n for n in cfg["ossa"]], cfg,
                          [(lato + n) if (lato + n) in _gruppi_corpo else n
                           for n in cfg.get("regione", cfg["ossa"])]))

# ─── Legatura: pesi dal corpo, poi AFFILATI ─────────────────────────────
## ⚠⚠ Due strade sbagliate, provate e guardate, prima di questa.
##
## 1. **Pesi trasferiti e basta.** La piastra si piega come la carne che copre:
##    nell'affondo la corazza si torceva, le ginocchiere si accartocciavano e i
##    guanti si sfaldavano sulle dita. L'acciaio non fa cosi'.
## 2. **Tagliare in pezzi rigidi separati**, uno per osso. L'acciaio diventa
##    acciaio, ma un guscio UNICO tagliato in segmenti si APRE: fra una piastra
##    e l'altra non c'e' materiale di sovrapposizione, perche' la mesh generata
##    e' un pezzo solo e non un insieme di lamine sovrapposte. Sui gambali si
##    vedeva la gamba attraverso i varchi.
##
## La terza e' quella che usano i giochi: si tengono i pesi trasferiti e li si
## AFFILA elevandoli a potenza, poi rinormalizzando. Nel mezzo di una piastra un
## osso domina gia', e l'esponente lo porta a ~1.0: quella zona diventa rigida.
## Sul giunto due ossa si contendono il vertice quasi alla pari, e li' la
## sfumatura resta — una fascia stretta che flette e tiene insieme le piastre.
##
## Nessun taglio, nessun buco, e una manopola sola.
_bersagli = {}


def bersaglio_regione(ossa):
    """Una copia del corpo con SOLO la carne delle ossa date.

    ⚠️⚠️ Conformare contro il corpo INTERO e' sbagliato, e sui gambali si e' visto
    in gioco: per un vertice sul lato interno del cosciale sinistro la superficie
    piu' vicina non e' la coscia sinistra, e' la DESTRA. Lo shrinkwrap lo
    spinge fuori rispetto alla gamba sbagliata, e i due pezzi si accavallano —
    ginocchiere che puntano una verso l'altra e lamine incrociate al centro.
    Un pezzo si conforma solo contro la SUA regione.

    Il ritaglio usa la stessa macchina del taglio: campo lisciato e taglio sulla
    curva di livello, cosi' il bersaglio non ha bordi frastagliati.
    """
    chiave = tuple(sorted(ossa))
    if chiave in _bersagli:
        return _bersagli[chiave]
    ## ⚠️ Un nome puo' essere SENZA lato (Hips): vale per tutti e due i pezzi.
    idx = {_gruppi_corpo[n] for n in ossa if n in _gruppi_corpo}
    grezzo = [1.0 - min(1.0, sum(g.weight for g in v.groups if g.group in idx))
              for v in corpo.data.vertices]
    liscio = liscia_campo(grezzo, _vicini(corpo), giri=5, forza=0.6)

    attivo(corpo)
    bpy.ops.object.duplicate()
    reg = bpy.context.active_object
    reg.name = "Regione_" + "_".join(sorted(ossa))[:40]
    taglia_su_campo(reg, liscio, 0.7)
    reg.hide_render = True
    _bersagli[chiave] = reg
    print("     bersaglio %s: %d vertici" % (reg.name, len(reg.data.vertices)))
    return reg


AFFONDO = 0.035


def conforma_al_corpo(pezzo, stacco, fascia=0.022, bersaglio=None, affondo=AFFONDO):
    """Fa ADERIRE il pezzo al corpo senza spianargli il rilievo.

    Vedi `docs/13_VESTIZIONE_CONFORMAZIONE.md`. In due mosse, e servono tutte e
    due:

    1. un vertex group di ADERENZA calcolato dalla distanza dal corpo: peso 1 in
       una FASCIA attorno alla pelle — da `affondo` sotto a `stacco` sopra — e
       sfumato a zero da tutte e due le parti;
    2. uno Shrinkwrap `OUTSIDE` pesato da quel gruppo.

    ⚠️⚠️ **`OUTSIDE`, non `OUTSIDE_SURFACE`.** Sembrano lo stesso modo e fanno il
    contrario: `OUTSIDE_SURFACE` PROIETTA sulla superficie (a distanza `offset`)
    tutto cio' che ha peso, `OUTSIDE` muove solo cio' che sta DENTRO e lascia
    fuori quello che e' gia' fuori. Con `OUTSIDE_SURFACE` sui gambali si
    muovevano 1.720 vertici su 3.894 invece dei 689 che stavano dentro la carne,
    e **1.075 dei mossi erano la parete ESTERNA** — la faccia che si vede. Il
    guscio si accartocciava: fascia del ginocchio spezzata, calzare in schegge.
    Bisezionato e guardato: `arcanium/tools/prove/esito_wrap_OUTSIDE*.png`.

    ⚠️ **Il fondo `affondo` non e' un dettaglio.** Senza, la regola era "d <
    stacco -> peso 1", e un vertice sepolto 12 cm dentro il bacino valeva 1: lo
    shrinkwrap lo catapultava fuori di 13 cm, e la cima del cosciale usciva a
    schegge. Un pezzo di piastra sepolto nella carne e' INVISIBILE; catapultato
    e' una scheggia che si vede. Misurato coi fondi 60/35/18 mm: il p99 dello
    spostamento scende da 10,9 cm a 4,5 cm con 35 mm, e le schegge spariscono.

    ⚠️ Ed e' il vertex group a conservare lo SPESSORE del guscio: la parete
    interna e' vicina alla pelle (peso 1, si appoggia), le cime delle piastre
    sono lontane (peso 0, non si muovono). Senza, parete interna ed esterna
    finiscono sullo stesso punto e il pezzo si strappa.

    ⚠️ Il peso si CALCOLA, non si dipinge: cosi' vale per qualunque pezzo su
    qualunque corpo. E' questo che rende sostenibili decine di armature.

    Proprio per come e' fatto, e' SICURO anche sui pezzi che stanno in rilievo:
    dove il pezzo e' gia' fuori non fa niente.
    """
    ber = bersaglio if bersaglio is not None else corpo
    g = pezzo.vertex_groups.new(name="aderenza")
    mw = pezzo.matrix_world
    inv = ber.matrix_world.inverted()
    dentro = sepolti = 0
    for v in pezzo.data.vertices:
        p_mondo = mw @ v.co
        ok, loc, nor, _ = ber.closest_point_on_mesh(inv @ p_mondo)
        if not ok:
            g.add([v.index], 0.0, 'REPLACE')
            continue
        lm = ber.matrix_world @ loc
        nm = (ber.matrix_world.to_3x3() @ nor).normalized()
        d = (p_mondo - lm).dot(nm)
        if d < 0.0:
            dentro += 1
        if d > stacco + fascia:
            peso = 0.0
        elif d > stacco:
            peso = 1.0 - (d - stacco) / fascia
        elif d >= -affondo:
            peso = 1.0
        elif d < -(affondo + fascia):
            peso = 0.0
            sepolti += 1
        else:
            peso = 1.0 - (-d - affondo) / fascia
            sepolti += 1
        g.add([v.index], peso, 'REPLACE')

    attivo(pezzo)
    mod = pezzo.modifiers.new("Conforma", 'SHRINKWRAP')
    mod.target = ber
    mod.wrap_method = 'NEAREST_SURFACEPOINT'
    mod.wrap_mode = 'OUTSIDE'
    mod.offset = stacco
    mod.vertex_group = g.name
    bpy.ops.object.modifier_apply(modifier=mod.name)
    ## via il gruppo: ha finito, e non deve finire nell'export
    pezzo.vertex_groups.remove(pezzo.vertex_groups[g.name])
    return dentro, sepolti


AFFILATURA = 6.0


def mappa_ai_dichiarati(rig, ossa):
    """Ogni osso del rig -> l'osso DICHIARATO piu' vicino nella catena.

    ⚠️ Senza questo, `ossa` era un commento: il ramo multi-osso teneva i pesi di
    TUTTE e 61 le ossa del donatore, perche' i pesi arrivano dal corpo nudo che
    e' pesato su tutte. Sul guanto voleva dire che la punta si spartiva fra le
    falangi — e le falangi sono proprio le ossa il cui rest NON coincide fra il
    corpo (che Godot raddrizza con fix_silhouette) e la piastra (importata
    liscia). Risultato guardato in gioco: la punta del guanto si sfaldava in
    schegge sulle dita, mentre avambraccio e dorso stavano bene.

    Piegando ogni falange su `Hand` la punta diventa un guscio rigido che segue
    la mano, che e' quello che un guanto d'acciaio fa davvero.

    La visita e' NON orientata di proposito: le falangi trovano `Hand` salendo,
    ma `UpperArm` — che pesa il bordo alto della manica e non ha nessun
    dichiarato sopra di se' — trova `LowerArm` scendendo. Solo coi genitori
    quei vertici resterebbero senza peso.
    """
    vicini = {}
    for b in rig.data.bones:
        vicini.setdefault(b.name, set())
        if b.parent:
            vicini[b.name].add(b.parent.name)
            vicini.setdefault(b.parent.name, set()).add(b.name)
    fuori = {n: n for n in ossa}
    fronte = list(ossa)
    while fronte:
        prossimo = []
        for n in fronte:
            for v in vicini.get(n, ()):
                if v not in fuori:
                    fuori[v] = fuori[n]
                    prossimo.append(v)
        fronte = prossimo
    return fuori


print("=== legatura ===")
for m, ossa, cfg, regione in indossati:
    ## ⚠️ La conformazione va PRIMA della legatura: i pesi devono trasferirsi
    ## sulla forma DEFINITIVA. Farla dopo significherebbe pesare una mesh che poi
    ## si muove.
    if cfg.get("conforma"):
        stacco, fascia = cfg["conforma"]
        ber = bersaglio_regione(regione) if regione else None
        dentro, sepolti = conforma_al_corpo(m, stacco, fascia, ber,
                                            cfg.get("affondo", AFFONDO))
        print("  %-20s conformato: %d vertici su %d erano dentro la carne"
              " (%d troppo sepolti, lasciati stare)"
              % (m.name, dentro, len(m.data.vertices), sepolti))
    attivo(m)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action='DESELECT')
    m.select_set(True)
    corpo.select_set(True)
    bpy.context.view_layer.objects.active = corpo   # ATTIVO = sorgente
    bpy.ops.object.data_transfer(
        data_type='VGROUP_WEIGHTS', use_create=True,
        vert_mapping='POLYINTERP_NEAREST',
        layers_select_src='ALL', layers_select_dst='NAME', mix_mode='REPLACE')
    attivo(m)

    if cfg.get("morbido"):
        ## ⚠️ STOFFA: i pesi del corpo si tengono COSI' COME SONO — niente
        ## ripiegamento sui dichiarati, niente affilatura. L'affilatura esiste
        ## per far comportare da acciaio una piastra che altrimenti si piega
        ## come carne; su una giacca di cuoio e pelliccia farebbe il contrario
        ## del vero, un capo che non si piega alla spalla. Il donatore e' il
        ## corpo nudo, cioe' esattamente la superficie che la giacca copre:
        ## i suoi pesi sono gia' quelli giusti.
        n_gruppi = len([g for g in m.vertex_groups])
        print("  %-20s MORBIDO: tengo i pesi del corpo (%d gruppi), niente affilatura"
              % (m.name, n_gruppi))
    elif len(ossa) == 1:
        ## Un guscio unico e rigido per costruzione: pettorale appeso alle
        ## spalle. Niente sfumature, niente da affilare.
        for g in list(m.vertex_groups):
            m.vertex_groups.remove(g)
        m.vertex_groups.new(name=ossa[0]).add(range(len(m.data.vertices)), 1.0, 'REPLACE')
        print("  %-20s rigido su %s" % (m.name, ossa[0]))
    else:
        nomi = [g.name for g in m.vertex_groups]
        ## I pesi del donatore si RIPIEGANO sui segmenti dichiarati prima di
        ## affilare: un guanto dichiarato su Hand non deve sapere che esistono
        ## le falangi. Vedi mappa_ai_dichiarati.
        verso = mappa_ai_dichiarati(rig, ossa)
        gruppi = {}
        dominanza = []
        for v in m.data.vertices:
            sommati = {}
            for g in v.groups:
                if g.weight <= 0.0:
                    continue
                n = verso.get(nomi[g.group])
                if n is not None:
                    sommati[n] = sommati.get(n, 0.0) + g.weight
            pesi = list(sommati.items())
            if not pesi:
                raise SystemExit("%s: vertice senza peso" % m.name)
            affilati = [(n, w ** AFFILATURA) for n, w in pesi]
            tot = sum(w for _, w in affilati)
            affilati = [(n, w / tot) for n, w in affilati]
            dominanza.append(max(w for _, w in affilati))
            for n, w in affilati:
                if w > 0.001:
                    gruppi.setdefault(n, []).append((v.index, w))
        for g in list(m.vertex_groups):
            m.vertex_groups.remove(g)
        for n, coppie in gruppi.items():
            g = m.vertex_groups.new(name=n)
            for i, w in coppie:
                g.add([i], w, 'REPLACE')
        dominanza.sort()
        rigidi = sum(1 for d in dominanza if d > 0.99)
        print("  %-20s %2d ossa | dominanza mediana %.3f | vertici gia' rigidi %d%%"
              % (m.name, len(gruppi), dominanza[len(dominanza) // 2],
                 round(100.0 * rigidi / len(dominanza))))

    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    for mod in list(m.modifiers):
        m.modifiers.remove(mod)
    mod = m.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    m.parent = rig
    m.matrix_parent_inverse = rig.matrix_world.inverted()

# ─── Export: armatura e piastre. Il corpo il gioco ce l'ha gia' ──────────────
bpy.data.objects.remove(corpo, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for m, _, _, _ in indossati:
    m.hide_set(False)
    m.hide_viewport = False
    m.hide_render = False
    m.select_set(True)
rig.hide_set(False)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=DEST, export_format='GLB', use_selection=True,
                          export_animations=False, export_yup=True,
                          export_apply=False, export_skins=True)
print("ESPORTATO:", DEST, os.path.getsize(DEST), "byte")
