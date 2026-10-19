# -*- coding: utf-8 -*-
"""Meshy da riga di comando: prima l'illustrazione, poi il modello.

Due fasi, nell'ordine in cui vanno fatte (vedi docs/05_RIG_CANONICO.md):

    # 1. l'IMMAGINE di riferimento, con nano-banana-pro
    python arcanium/tools/meshy.py illustrazione "prompt..." assets/ui/equipment/corazza.png

    # 2. il MODELLO, dall'immagine
    python arcanium/tools/meshy.py modello assets/ui/equipment/corazza.png assets/characters/armor/corazza.glb

⚠️ LA CHIAVE NON STA NEL REPO e non deve entrarci. Si legge da
`../MESHY_API_KEY.md` (fuori dalla radice del progetto) o dalla variabile
d'ambiente `MESHY_API_KEY`, e non viene mai stampata.

⚠️ E' un servizio A PAGAMENTO. Lo strumento stampa il saldo prima e dopo, cosi'
il costo si vede subito invece di scoprirlo a fine mese. Riferimento misurato:
un image-to-3d a 30.000 poligoni costa 30 crediti.

⚠️ Il taglio dell'immagine decide la qualita' del modello. Oggetto SINGOLO e
ISOLATO su fondo neutro, luce morbida uniforme, oggetto tutto dentro
l'inquadratura. Un'armatura indossata da un manichino si porta dentro il
manichino, e poi va ritagliata a mano.
"""
import sys, os, json, re, time, base64, shutil, argparse, urllib.request, urllib.error

## ⚠️ La console Windows parte in cp1252 e i simboli di avviso nella docstring
## bastano a far crollare perfino `--help`.
for flusso in (sys.stdout, sys.stderr):
    if hasattr(flusso, "reconfigure"):
        flusso.reconfigure(encoding="utf-8", errors="replace")

RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
API = "https://api.meshy.ai/openapi/v1"

## ⚠️ Quello che si genera via API NON resta nello spazio di lavoro Meshy: se il
## file locale si perde, e' perso. Quindi ogni cosa scaricata si archivia ANCHE
## qui, fuori dal repo, con lo stesso nome.
## ⚠️ Il percorso era scritto a mano su `C:\Users\Adriano`, che su questa
## macchina non esiste (l'utente e' `adriano.pace`): ogni archiviazione falliva
## con "Access is denied" e la rete di sicurezza non c'era pur sembrando esserci.
## Ora si parte dalla home vera.
_ARCHIVIO_BASE = os.path.join(os.path.expanduser("~"), "LOCAL", "Meshy")
ARCHIVIO = {
    "illustrazione": os.path.join(_ARCHIVIO_BASE, "Illustrazioni"),
    "modello": os.path.join(_ARCHIVIO_BASE, "Modelli3d"),
}

## Modelli accettati da `text-to-image`, chiesti all'API il 2026-08-09 mandando
## un nome sbagliato apposta: l'errore li elenca.
MODELLI_IMMAGINE = ("nano-banana", "nano-banana-pro", "nano-banana-2",
                    "nano-banana-2-lite", "gpt-image-2")


def chiave():
    k = os.environ.get("MESHY_API_KEY")
    if k:
        return k.strip()
    fuori = os.path.join(os.path.dirname(RADICE), "MESHY_API_KEY.md")
    if os.path.exists(fuori):
        with open(fuori, encoding="utf-8") as f:
            return f.read().strip()
    raise SystemExit("chiave Meshy non trovata: ne' MESHY_API_KEY ne' %s" % fuori)


def chiama(percorso, dati=None):
    ## `percorso` puo' essere anche un URL intero: serve per gli endpoint che
    ## stanno su /v2 (text-to-3d) invece che sul /v1 di `API`.
    corpo = json.dumps(dati).encode() if dati is not None else None
    url = percorso if percorso.startswith("http") else API + percorso
    req = urllib.request.Request(url, data=corpo,
                                 method="POST" if dati else "GET")
    req.add_header("Authorization", "Bearer " + chiave())
    if dati is not None:
        req.add_header("Content-Type", "application/json")
    ## ⚠️ Riprova sui guasti di RETE, non su quelli dell'API.
    ##
    ## Su questa macchina il TLS cade a intermittenza con
    ## CERTIFICATE_VERIFY_FAILED (un proxy che si mette in mezzo): in una tornata
    ## di sei modelli e' successo dal secondo in poi, e cinque generazioni sono
    ## morte prima ancora di partire. Un HTTPError invece e' una risposta vera —
    ## riprovarlo significherebbe rimandare la stessa richiesta sbagliata, o
    ## peggio pagarla due volte.
    ultimo = None
    for tentativo in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            raise SystemExit("Meshy %d: %s" % (e.code, e.read().decode()[:600]))
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            ultimo = e
            attesa = 5 * (tentativo + 1)
            print("  rete: %s — riprovo fra %ds (%d/4)" % (e, attesa, tentativo + 1),
                  flush=True)
            time.sleep(attesa)
    raise SystemExit("rete non raggiungibile dopo 4 tentativi: %s" % ultimo)


def saldo():
    return chiama("/balance").get("balance")


## Ogni quanto stampare comunque, anche se lo stato non e' cambiato.
## ⚠️ Senza questo il polling SEMBRA piantato: su un image-to-3d la percentuale
## e' rimasta a 49% per 23 minuti filati, e chi guardava il log ha creduto che
## lo strumento non interrogasse piu' niente. Interrogava eccome, ogni 8s: era
## muto perche' stampava solo sui cambiamenti.
BATTITO = 60


def attendi(percorso, tid, massimo):
    inizio = time.time()
    ultimo = None
    ultima_stampa = 0.0
    while True:
        stato = chiama("%s/%s" % (percorso, tid))
        s, avanz = stato.get("status"), stato.get("progress", 0)
        passato = time.time() - inizio
        if (s, avanz) != ultimo or passato - ultima_stampa >= BATTITO:
            print("  %6.0fs  %-12s %3d%%" % (passato, s, avanz), flush=True)
            ultimo, ultima_stampa = (s, avanz), passato
        if s == "SUCCEEDED":
            return stato
        if s in ("FAILED", "CANCELED"):
            raise SystemExit("Meshy ha fallito: %s"
                             % json.dumps(stato.get("task_error", {}))[:600])
        if passato > massimo:
            ## ⚠️ Scadere NON vuol dire fallire: il task continua sul server e il
            ## risultato resta scaricabile. Si stampa il comando pronto per
            ## riprenderlo, invece di lasciare un id da riscoprire a mano.
            raise SystemExit(
                "attesa scaduta dopo %ds — il task e' VIVO e va ripreso:\n"
                "    python arcanium/tools/meshy.py recupera %s %s <destinazione>"
                % (massimo, percorso.strip("/"), tid))
        time.sleep(8)


def assoluto(p):
    return p if os.path.isabs(p) else os.path.join(RADICE, p)


def scarica(url, dest, tipo=None):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    urllib.request.urlretrieve(url, dest)
    print("SCRITTO:", os.path.relpath(dest, RADICE), os.path.getsize(dest), "byte")
    archivia(dest, tipo)


def archivia(percorso, tipo):
    """Copia in `LOCAL\\Meshy`, fuori dal repo.

    ⚠️ Non e' un doppione inutile: quello che nasce dall'API non compare nello
    spazio di lavoro Meshy, quindi il file locale e' l'UNICA copia. Sovrascrivere
    un percorso di destinazione — come e' gia' successo alla corazza senza
    stemma — vuol dire perderlo.
    """
    if tipo is None:
        tipo = "modello" if percorso.lower().endswith(".glb") else "illustrazione"
    cartella = ARCHIVIO.get(tipo)
    if not cartella:
        return
    try:
        os.makedirs(cartella, exist_ok=True)
        meta = os.path.join(cartella, os.path.basename(percorso))
        shutil.copy2(percorso, meta)
        print("  archiviato in:", meta)
    except OSError as e:
        ## L'archivio e' una rete di sicurezza: se non si riesce a scrivere si
        ## avvisa e si va avanti, invece di buttare via un lavoro gia' pagato.
        print("  ⚠️ archiviazione fallita (%s): il file resta solo in %s"
              % (e, percorso))


# ─── fase 1: l'illustrazione ─────────────────────────────────────────────────
def illustrazione(args):
    dest = assoluto(args.destinazione)
    prima = saldo()
    print("saldo prima:", prima, "| modello:", args.modello)
    invio = chiama("/text-to-image", {
        "ai_model": args.modello,
        "prompt": args.prompt,
        "aspect_ratio": args.formato,
    })
    tid = invio.get("result") or invio.get("id")
    print("task:", tid)
    stato = attendi("/text-to-image", tid, args.attendi)
    url = None
    for chiave_url in ("image_url", "image_urls", "result_url"):
        v = stato.get(chiave_url)
        if isinstance(v, str):
            url = v
            break
        if isinstance(v, list) and v:
            url = v[0]
            break
    if not url:
        raise SystemExit("nessuna immagine nella risposta: %s" % json.dumps(stato)[:600])
    scarica(url, dest, "illustrazione")
    dopo = saldo()
    print("saldo dopo: %s  (costo %s)" % (dopo, prima - dopo))


# ─── fase 1-bis: l'illustrazione, PARTENDO da immagini ───────────────────────
## ⚠️ `/text-to-image` IGNORA le immagini di riferimento: passargliele non da'
## errore e non cambia niente. Verificato mandando un URL inesistente in quattro
## campi diversi (`image_urls`, `reference_images`, `image_url`, `init_image`):
## tutti e quattro i task sono RIUSCITI, cioe' nessuno ha provato a scaricarlo.
## Per lavorare su riferimenti esiste un endpoint separato, `/image-to-image`,
## e il campo si chiama `reference_image_urls`.
def rilettura(args):
    dest = assoluto(args.destinazione)
    riferimenti = []
    for p in args.riferimenti:
        f = assoluto(p)
        with open(f, "rb") as fh:
            riferimenti.append("data:image/png;base64,"
                               + base64.b64encode(fh.read()).decode())
        print("riferimento:", os.path.relpath(f, RADICE),
              "(%.0f KB)" % (os.path.getsize(f) / 1024))
    prima = saldo()
    print("saldo prima:", prima, "| modello:", args.modello)
    invio = chiama("/image-to-image", {
        "ai_model": args.modello,
        "prompt": args.prompt,
        "reference_image_urls": riferimenti,
    })
    tid = invio.get("result") or invio.get("id")
    print("task:", tid)
    stato = attendi("/image-to-image", tid, args.attendi)
    url = None
    for k in ("image_url", "image_urls", "result_url"):
        v = stato.get(k)
        if isinstance(v, str):
            url = v
            break
        if isinstance(v, list) and v:
            url = v[0]
            break
    if not url:
        raise SystemExit("nessuna immagine nella risposta: %s" % json.dumps(stato)[:600])
    scarica(url, dest, "illustrazione")
    dopo = saldo()
    print("saldo dopo: %s  (costo %s)" % (dopo, prima - dopo))


# ─── fase 2: il modello ──────────────────────────────────────────────────────
def modello(args):
    img, dest = assoluto(args.immagine), assoluto(args.destinazione)
    prima = saldo()
    print("saldo prima:", prima)
    with open(img, "rb") as f:
        uri = "data:image/png;base64," + base64.b64encode(f.read()).decode()
    ## ⚠️ `ai_model` va detto: il default e' il modello VECCHIO, e su questi
    ## oggetti si vede. `should_remesh` con topologia quad e' cio' che Meshy
    ## chiama smart topology — geometria pulita senza decimare a mano.
    corpo = {
        "image_url": uri,
        "ai_model": args.ai_model,
        "topology": args.topologia,
        "target_polycount": args.poligoni,
        "should_remesh": True,
        "should_texture": True,
        "enable_pbr": True,
        "symmetry_mode": args.simmetria,
    }
    ## ⚠️ I modelli **T** vogliono `model_type: smart-topology`, e senza quello
    ## l'API rifiuta seccamente ("ai_model meshy-t2 requires model_type"). E'
    ## la modalita' che fa la mesh LEGGERA e pulita: `should_remesh` da solo
    ## non basta a ottenerla, perche' descrive il rifacimento della topologia,
    ## non il regime in cui gira il modello.
    if args.ai_model in ("meshy-t1", "meshy-t2"):
        corpo["model_type"] = "smart-topology"

    ## ⚠️ `ultra_mode` e' accettato SOLO da meshy-7 (o "latest"): chiederlo su
    ## meshy-6 non alza la qualita', la richiesta viene rifiutata. Per questo lo
    ## si manda solo quando il modello lo regge, invece di spedirlo sempre.
    if args.ultra:
        if args.ai_model not in ("meshy-7", "latest"):
            raise SystemExit("--ultra richiede --ai-model meshy-7 (o latest)")
        corpo["ultra_mode"] = True
    invio = chiama("/image-to-3d", corpo)
    tid = invio.get("result") or invio.get("id")
    print("task:", tid)
    stato = attendi("/image-to-3d", tid, args.attendi)
    url = (stato.get("model_urls") or {}).get("glb")
    if not url:
        raise SystemExit("nessun GLB nella risposta: %s" % json.dumps(stato)[:600])
    scarica(url, dest, "modello")
    dopo = saldo()
    print("saldo dopo: %s  (costo %s)" % (dopo, prima - dopo))


# ─── recupero di un task gia' finito ─────────────────────────────────────────
## ⚠️ Serve piu' spesso di quanto sembri: un task che ha superato l'attesa
## continua sul server e il suo risultato resta scaricabile per un pezzo. Averlo
## come comando evita di riscriverlo a mano ogni volta — ed evita soprattutto di
## RIGENERARE, che costa di nuovo.
def recupera(args):
    stato = chiama("/%s/%s" % (args.tipo, args.task))
    print("stato:", stato.get("status"), "| avanzamento:", stato.get("progress"))
    if stato.get("status") != "SUCCEEDED":
        raise SystemExit("non ancora pronto: %s" % str(stato.get("task_error"))[:300])
    url = (stato.get("model_urls") or {}).get("glb")
    if not url:
        for k in ("image_url", "image_urls", "result_url"):
            v = stato.get(k)
            if isinstance(v, str):
                url = v
                break
            if isinstance(v, list) and v:
                url = v[0]
                break
    if not url:
        raise SystemExit("nessun file nella risposta: %s" % json.dumps(stato)[:600])
    scarica(url, assoluto(args.destinazione))


## Gli endpoint che sanno ELENCARE, con la loro versione. Provati uno per uno:
## gli altri (text-to-texture, assets, tasks) rispondono 404.
ELENCABILI = {
    "text-to-image": "v1", "image-to-image": "v1", "text-to-3d": "v2",
    "image-to-3d": "v1", "multi-image-to-3d": "v1", "remesh": "v1",
}


def _tutte(tipo):
    """Tutte le pagine di un endpoint, senza ripetizioni."""
    fuori, visti, pag = [], set(), 1
    while pag <= 40:
        d = chiama("https://api.meshy.ai/openapi/%s/%s?page_num=%d&page_size=50"
                   "&sort_by=-created_at" % (ELENCABILI[tipo], tipo, pag))
        if not isinstance(d, list) or not d:
            break
        nuovi = [x for x in d if x.get("id") not in visti]
        if not nuovi:
            break
        visti.update(x.get("id") for x in nuovi)
        fuori.extend(nuovi)
        pag += 1
    return fuori


def _file_di(voce):
    """(etichetta, url) di tutto cio' che una generazione porta con se'."""
    fuori = []
    for i, u in enumerate(voce.get("image_urls") or []):
        fuori.append(("img%d" % i, u))
    for i, t in enumerate(voce.get("texture_urls") or []):
        if isinstance(t, dict):
            for k, u in t.items():
                if isinstance(u, str) and u.startswith("http"):
                    fuori.append(("tex%d_%s" % (i, k), u))
    for k, u in (voce.get("model_urls") or {}).items():
        if isinstance(u, str) and u.startswith("http"):
            fuori.append(("modello_%s" % k, u))
    for k in ("thumbnail_url", "video_url"):
        u = voce.get(k)
        if isinstance(u, str) and u.startswith("http"):
            fuori.append((k.replace("_url", ""), u))
    return fuori


def _quando(ms):
    return time.strftime("%Y-%m-%d_%H%M", time.localtime((ms or 0) / 1000.0))


def elenca(args):
    """Cosa esiste sul conto di QUESTA chiave.

    ⚠️⚠️ Due cose che sembrano ovvie e non lo sono:

    1. **La libreria e' legata alla CHIAVE, non all'account.** Da una chiave si
       vedono solo i task creati con quella chiave: non quello che si e' fatto
       nella web app, e nemmeno quello fatto da un'altra macchina con un'altra
       chiave. Cercare qui un'immagine fatta nel sito e' tempo perso.
    2. **Gli URL sono FIRMATI E A SCADENZA** (`expires_at`, circa tre giorni).
       La generazione resta elencata per sempre, ma il file dietro il link
       diventa 403. Misurato: nove generazioni di luglio, tutte irrecuperabili.
       Quindi `ritira` va lanciato SUBITO, non "quando serve".
    """
    adesso = time.time() * 1000.0
    tot = morti = 0
    for tipo in (ELENCABILI if args.tipo == "tutti" else [args.tipo]):
        voci = _tutte(tipo)
        print()
        print("=== %s: %d" % (tipo, len(voci)))
        for v in voci:
            tot += 1
            scaduto = (v.get("expires_at") or 0) < adesso
            morti += 1 if scaduto else 0
            print("  %s  %-9s %-15s %-40s%s"
                  % (_quando(v.get("created_at")), v.get("status", "?"),
                     v.get("ai_model") or "-",
                     (v.get("prompt") or v.get("name") or "")[:40],
                     "  LINK SCADUTO" if scaduto else ""))
    print()
    print("totale %d, col link gia' scaduto %d" % (tot, morti))


def ritira(args):
    """Scarica tutto cio' che e' ancora scaricabile, in `LOCAL/Meshy/api/`."""
    base = os.path.join(_ARCHIVIO_BASE, "api")
    presi = falliti = 0
    for tipo in (ELENCABILI if args.tipo == "tutti" else [args.tipo]):
        voci = [v for v in _tutte(tipo) if v.get("status") == "SUCCEEDED"]
        if not voci:
            continue
        cartella = os.path.join(base, tipo)
        os.makedirs(cartella, exist_ok=True)
        print()
        print("=== %s: %d da ritirare" % (tipo, len(voci)))
        for v in voci:
            nome = re.sub(r"[^0-9A-Za-z]+", "_",
                          (v.get("prompt") or v.get("name") or "senza_nome"))[:60].strip("_")
            for etichetta, u in _file_di(v):
                est = os.path.splitext(u.split("?")[0])[1] or ".bin"
                dove = os.path.join(cartella, "%s_%s__%s%s"
                                    % (_quando(v.get("created_at")), nome.lower(),
                                       etichetta, est))
                if os.path.exists(dove) and os.path.getsize(dove) > 0:
                    continue
                ## ⚠️ Si prova SEMPRE, anche su cio' che `expires_at` da' per
                ## morto: quella e' una previsione, la verita' e' la risposta.
                try:
                    urllib.request.urlretrieve(u, dove)
                    presi += 1
                    print("  %-18s %s" % (etichetta, os.path.basename(dove)))
                except Exception as e:
                    falliti += 1
                    if os.path.exists(dove):
                        os.remove(dove)
                    print("  %-18s FALLITO: %s" % (etichetta, e))
    print()
    print("ritirati %d file, falliti %d (i falliti sono link scaduti)"
          % (presi, falliti))


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="fase", required=True)

    a = sub.add_parser("illustrazione", help="testo -> immagine (nano-banana)")
    a.add_argument("prompt")
    a.add_argument("destinazione")
    a.add_argument("--modello", default="nano-banana-pro", choices=MODELLI_IMMAGINE)
    a.add_argument("--formato", default="1:1")
    a.add_argument("--attendi", type=int, default=600)
    a.set_defaults(func=illustrazione)

    r = sub.add_parser("rilettura", help="immagini di riferimento -> immagine")
    r.add_argument("prompt")
    r.add_argument("destinazione")
    r.add_argument("riferimenti", nargs="+")
    r.add_argument("--modello", default="nano-banana-pro", choices=MODELLI_IMMAGINE)
    r.add_argument("--attendi", type=int, default=600)
    r.set_defaults(func=rilettura)

    b = sub.add_parser("modello", help="immagine -> GLB (meshy-6)")
    b.add_argument("immagine")
    b.add_argument("destinazione")
    ## Il tetto della smart topology e' 15.000, e bastano: i LOD li genera Godot.
    b.add_argument("--poligoni", type=int, default=15000)
    ## ⚠️⚠️ TRIANGOLI per i PROP, quad per cio' che si DEFORMA.
    ##
    ## Sui personaggi animati i quad riducono le punte quando la mesh si piega,
    ## e li' vanno tenuti. Su un oggetto rigido invece sono peggio, e di molto:
    ## il remesh in quad deve far cadere ogni bordo su una griglia di
    ## quadrilateri, e dove il bordo e' obliquo la griglia non lo segue e si
    ## STRAPPA. Sulla corazza il fauld usciva sbrecciato e lo stemma aveva una
    ## cucitura netta lungo l'asse di simmetria.
    ##
    ## Misurato sullo stesso riferimento, stesso target di 15.000:
    ##    quad      34.172 tri  fauld strappato, cucitura sullo stemma
    ##    triangle  15.343 tri  fauld intero, bordi puliti, stemma nitido
    ## La versione in triangoli e' migliore su ogni voce E pesa meno della meta'.
    ##
    ## Alzare i poligoni non e' la cura: a 300.000 la forma viene giusta ma ogni
    ## bordo si riempie di punte, perche' a quella densita' il rumore della
    ## ricostruzione diventa geometria.
    b.add_argument("--topologia", default="triangle", choices=["quad", "triangle"])
    b.add_argument("--simmetria", default="auto", choices=["off", "auto", "on"])
    ## Il default resta meshy-6: e' con quello che sono stati fatti gli asset
    ## gia' in gioco, e cambiarlo di nascosto renderebbe irripetibile tutto
    ## quello che e' stato generato finora.
    ## ⚠️ meshy-7 --ultra e' HI-POLY: alza la fedelta' della geometria, non
    ## produce un pezzo leggero. Per il LOW POLY con smart topology servono i
    ## modelli **T**, e T2 esiste solo qui, in image-to-3d: non c'e' in
    ## text-to-3d, quindi un pezzo leggero vuole per forza un'immagine di
    ## riferimento.
    ##
    ## L'elenco completo l'ha detto l'API il 2026-08-22, interrogata mandando un
    ## nome di modello inesistente — il corpo viene rifiutato PRIMA di mettere
    ## in coda un task, quindi la domanda non costa crediti (saldo 1376 prima e
    ## 1376 dopo). ⚠️ Non chiederlo mai con un corpo valido: quello genera.
    ##    meshy-4  meshy-5  meshy-6  meshy-7  latest  meshy-t1  meshy-t2
    b.add_argument("--ai-model", dest="ai_model", default="meshy-6",
                   choices=["meshy-4", "meshy-5", "meshy-6", "meshy-7",
                            "latest", "meshy-t1", "meshy-t2"])
    b.add_argument("--ultra", action="store_true",
                   help="geometria ad alta fedelta' (solo meshy-7/latest)")
    b.add_argument("--attendi", type=int, default=3600)
    b.set_defaults(func=modello)

    c = sub.add_parser("recupera", help="scarica un task già finito, per id")
    c.add_argument("tipo", choices=["text-to-image", "image-to-image", "image-to-3d"])
    c.add_argument("task")
    c.add_argument("destinazione")
    c.set_defaults(func=recupera)

    scelte = ["tutti"] + list(ELENCABILI)
    e = sub.add_parser("elenca", help="cosa esiste sul conto di QUESTA chiave")
    e.add_argument("tipo", nargs="?", default="tutti", choices=scelte)
    e.set_defaults(func=elenca)

    t = sub.add_parser("ritira", help="scarica tutto finche' i link valgono")
    t.add_argument("tipo", nargs="?", default="tutti", choices=scelte)
    t.set_defaults(func=ritira)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
