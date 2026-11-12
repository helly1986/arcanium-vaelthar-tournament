"""OGNI OSSO SOLO SULLA SUA PARTE DEL CORPO: il collaudo (e la cura) dei pesi dopo il
bind di ARP.

L'utente, 2026-11-12, sulle punte all'inguine di Edran nelle pose a gambe larghe: «dopo
ogni creazione su Tripo dobbiamo fare una passata di verifica [...] Poi assicurarci che
una volta riggato con ARP e fatto il weight painting ogni osso copra solo la parte di
corpo che deve effettivamente coprire».

Cosa si era trovato (misurato su una posa del colpo di scudo, gambe larghe):
- vertici di coscia e veste pesati sul POLLICE (`thumb3.l` fino a 0,09): nella A-pose le
  mani pendono accanto alle cosce, e il bind automatico ha passato le dita alle cosce
  vicine. Edran (veste), Aurin, Ilwen;
- i pannelli della veste fra le gambe pesati sulle DUE cosce insieme: allargando le gambe
  si stirano fino a 7,5 volte (la "linguetta" scura all'inguine). Edran, Ilwen.

Tre regole, sull'osso DOMINANTE di ogni vertice (le ossa di torsione contano come il loro
osso di stiramento, `thigh_twist.l` come `thigh_stretch.l`):
1. GERARCHIA: un altro osso puo' pesare sul vertice solo se sta a non piu' di `SALTI`
   passi dal dominante nell'albero delle ossa che deformano. Il pollice e' a dieci passi
   dalla coscia, il bacino a uno. Tre passi lasciano le sfumature vere: la colonna
   nell'ascella (braccio, spalla, spine_03, spine_02), la clavicola sul fianco del petto;
2. ESCLUSIVE: le DITA pesano solo sulla mano del loro lato (mano, dita, metacarpi), la TESTA
   solo su testa, collo e spine_03 (i capelli lunghi sulla schiena). Su Edran la testa pesava fino al 24% sullo spallaccio e le ossa
   del braccio sui lati della testa: girando la testa si muoveva la spalla;
3. LATO: un vertice che sta chiaramente da un lato (oltre `CENTRO` dal piano di mezzo, dal
   lato del suo dominante) non pesa sugli ARTI dell'altro lato. Le clavicole no: al centro
   del petto e della schiena sfumano fra loro, ed e' giusto.
Le ossa centrali (`.x`) sono sempre di nessun lato.

    violazioni(ob, rig)            -> il conto, per coppia (dominante, intruso)
    pulisci_pesi(ob, rig)          -> toglie gli intrusi e rinormalizza; ritorna il conto

Si usa dentro monta_arp.py (prima dell'export, su corpo e stoffe) e, a GLB fatto, con
arcanium/tools/collaudo_campione.py.
"""
import bpy
from collections import Counter, deque

SALTI = 3
CENTRO = 0.03  # m dal piano di mezzo
SOGLIA = 0.01  # sotto questo peso un osso non conta
DITA = ("thumb", "index", "middle", "ring", "pinky")
ARTI = ("thigh", "leg", "foot", "toes", "arm", "forearm", "hand") + DITA
TORSIONI = {"thigh_twist": "thigh_stretch", "leg_twist": "leg_stretch", "arm_twist": "arm_stretch",
            "forearm_twist": "forearm_stretch"}


def _canonico(nome):
    ## I gruppi del rig SORGENTE di ARP hanno i nomi dei controlli (`c_thumb3.l`,
    ## `c_arm_twist_offset.l`); l'export li porta sulle ossa senza `c_`.
    if nome.startswith("c_"):
        nome = nome[2:]
    nome = nome.replace("arm_twist_offset.", "arm_twist.")
    for t, s in TORSIONI.items():
        if nome.startswith(t + "."):
            return s + nome[len(t):]
    return nome


def _esclusivo(nome):
    ## I metacarpi (`*1_base`) partono dal polso e sfumano sull'avambraccio: non sono dita.
    return (nome.startswith(DITA) and "_base" not in nome) or nome == "head.x"


def _vicino_esclusivo(c, dom):
    """Le dita solo sulla mano del loro lato (mano e dita, metacarpi compresi: nel palmo
    sfumano fra loro), la testa solo su testa e collo."""
    if c == "head.x":
        ## Fino a due passi (collo, spine_03): i capelli lunghi sulla schiena seguono la
        ## testa (Aurin, 2026-11-12: tolta, la coda si stirava in strisce). Lo spallaccio
        ## (shoulder, tre passi) no.
        return dom in ("head.x", "neck.x", "spine_03.x")
    return _lato(dom) == _lato(c) and (dom.startswith(DITA) or dom.startswith("hand."))


def _arto(nome):
    return nome.startswith(ARTI) and _lato(nome) != ""


def _lato(nome):
    if nome.endswith(".l"):
        return "l"
    if nome.endswith(".r"):
        return "r"
    return ""


def _distanze(rig=None):
    """Passi fra ogni coppia di ossa che deformano (canoniche), nell'albero dello scheletro
    ESPORTATO (arp_genitori.json, uguale per tutti i campioni: l'export UNIVERSAL di ARP).
    Non dal rig sorgente: li' le ossa che deformano pendono da ossa di controllo, e la
    gerarchia ricavata metteva il collo lontano dalla testa e lo stinco dalla coscia
    (2026-11-12, la prima prova tolse 17.784 pesi buoni da Edran)."""
    import json
    import os
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "arp_genitori.json"), encoding="utf-8") as f:
        genitori = json.load(f)
    vicini = {}
    for figlio, padre in genitori.items():
        a, pa = _canonico(figlio), _canonico(padre)
        vicini.setdefault(a, set())
        vicini.setdefault(pa, set())
        if pa != a:
            vicini[a].add(pa)
            vicini[pa].add(a)
    dist = {}
    for s in vicini:
        d = {s: 0}
        coda = deque([s])
        while coda:
            x = coda.popleft()
            for y in vicini[x]:
                if y not in d:
                    d[y] = d[x] + 1
                    coda.append(y)
        dist[s] = d
    return dist


def _scorri(ob, rig, correggi):
    dist = _distanze(rig)
    nomi = {g.index: g.name for g in ob.vertex_groups}
    mw = ob.matrix_world
    ## Il piano di mezzo e il lato di ogni osso, dal rig a riposo (x del mondo).
    lato_x = {}
    for b in rig.data.bones:
        x = (rig.matrix_world @ b.head_local).x
        lato_x.setdefault(_canonico(b.name), x)
    ## Il lato del mondo di ogni suffisso, da un osso sicuro (la coscia).
    for s in "lr":
        lato_x.setdefault("_" + s, lato_x.get("thigh_stretch." + s, 1.0 if s == "l" else -1.0))
    conto = Counter()
    vertici_toccati = 0
    via = []  # (gruppo, vertice)
    for v in ob.data.vertices:
        pesi = [(g.weight, nomi.get(g.group, ""), g.group) for g in v.groups if g.weight > SOGLIA]
        if len(pesi) < 2:
            continue
        ## Il dominante per osso canonico (torsione + stiramento insieme).
        somma = Counter()
        for w, n, _ in pesi:
            somma[_canonico(n)] += w
        dom = somma.most_common(1)[0][0]
        lato_dom = _lato(dom)
        x = (mw @ v.co).x
        da_un_lato = lato_dom and abs(x) > CENTRO and (x > 0) == (lato_x["_" + lato_dom] > 0)
        toccato = False
        for w, n, gi in pesi:
            c = _canonico(n)
            if c == dom:
                continue
            passi = dist.get(dom, {}).get(c, 99)
            lontano = passi > SALTI or (_esclusivo(c) and not _vicino_esclusivo(c, dom))
            altro_lato = da_un_lato and _arto(c) and _lato(c) != lato_dom
            if lontano or altro_lato:
                conto[(dom, c, "lontano" if lontano else "altro lato")] += 1
                via.append((gi, v.index))
                toccato = True
        vertici_toccati += toccato
    if correggi and via:
        for gi, vi in via:
            ob.vertex_groups[gi].remove([vi])
        _normalizza(ob)
    return conto, vertici_toccati


def _normalizza(ob):
    for v in ob.data.vertices:
        s = sum(g.weight for g in v.groups)
        if s > 0.0:
            for g in v.groups:
                g.weight /= s


def violazioni(ob, rig):
    return _scorri(ob, rig, False)


def pulisci_pesi(ob, rig):
    conto, toccati = _scorri(ob, rig, True)
    print("pesi per regione su %s: %d vertici ripuliti, %d pesi tolti" % (ob.name, toccati, sum(conto.values())))
    for (dom, c, perche), n in conto.most_common(8):
        print("   %5d  %s su vertici di %s (%s)" % (n, c, dom, perche))
    return conto


def stampa(ob, rig):
    conto, toccati = violazioni(ob, rig)
    print("PESI %s: %d vertici con ossa fuori posto, %d pesi" % (ob.name, toccati, sum(conto.values())))
    for (dom, c, perche), n in conto.most_common(10):
        print("   %5d  %s su vertici di %s (%s)" % (n, c, dom, perche))
    return toccati
