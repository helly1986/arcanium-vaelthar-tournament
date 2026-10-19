# -*- coding: utf-8 -*-
"""Tripo P1 su fal.ai: dal testo a una mesh GIA' leggera.

    python arcanium/tools/tripo.py genera "un ciuffo d'erba..." dest.glb --facce 400
    python arcanium/tools/tripo.py lotto tools/gen/lotto8_sottobosco.json --facce 400
    python arcanium/tools/tripo.py recupera <request_id> dest.glb

⚠️ PERCHE' ESISTE, visto che c'e' gia' meshy.py.
Meshy fa mesh dense e le si alleggerisce dopo, e "dopo" e' il problema: sul
sottobosco di Kalvorn la decimazione ha strappato le UV (il muschio risaliva
sulle facce) e ha disintegrato i grappoli — sassolini e funghi diventavano
coriandoli, perche' il collapse non ha spigoli condivisi su cui lavorare.
Le card ritagliate dal render erano leggere ma restavano cartone.

Tripo P1 prende `face_limit` (48-20.000) come VINCOLO DI GENERAZIONE: la mesh
nasce leggera e pulita invece di essere ridotta a forza. E' la differenza fra
chiedere un pezzo da 400 facce e ricavarlo distruggendone uno da 3.500.

⚠️ `face_limit` conta FACCE, non triangoli: se il modello torna in quad, i
triangoli sono il doppio. Lo strumento misura il GLB scaricato e stampa il
conto vero, cosi' il numero non si crede sulla parola.

⚠️ LA CHIAVE NON STA NEL REPO. Si legge da `FAL_KEY` o da `../FAL_KEY.md`
(fuori dalla radice del progetto), e non viene mai stampata.

⚠️ E' un servizio A PAGAMENTO. Ogni generazione stampa quanto e' costata
secondo le metriche di fal. Prima di un lotto si prova UN pezzo.
"""
import sys, os, json, time, argparse, urllib.request, urllib.error

## ⚠️ La console Windows parte in cp1252 e i simboli di avviso bastano a far
## crollare perfino `--help`. Stessa medicina di meshy.py.
for flusso in (sys.stdout, sys.stderr):
    if hasattr(flusso, "reconfigure"):
        flusso.reconfigure(encoding="utf-8", errors="replace")

RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CODA = "https://queue.fal.run"
MODELLO = "tripo3d/p1/text-to-3d"

## ⚠️ Come per Meshy: quello che si genera non resta sul servizio per sempre.
## Ogni GLB scaricato si archivia ANCHE fuori dal repo, con lo stesso nome.
ARCHIVIO = os.path.join(os.path.expanduser("~"), "LOCAL", "Tripo", "Modelli3d")


def chiave():
    k = os.environ.get("FAL_KEY")
    if k:
        return k.strip()
    fuori = os.path.join(os.path.dirname(RADICE), "FAL_KEY.md")
    if os.path.exists(fuori):
        with open(fuori, encoding="utf-8") as f:
            return f.read().strip()
    raise SystemExit("chiave fal non trovata: ne' FAL_KEY ne' %s" % fuori)


def assoluto(p):
    return p if os.path.isabs(p) else os.path.join(RADICE, p)


def chiama(url, dati=None, metodo=None):
    corpo = json.dumps(dati).encode() if dati is not None else None
    req = urllib.request.Request(
        url, data=corpo, method=metodo or ("POST" if dati is not None else "GET"))
    req.add_header("Authorization", "Key " + chiave())
    if corpo is not None:
        req.add_header("Content-Type", "application/json")
    ## ⚠️ Si riprova sui guasti di RETE, mai su una risposta dell'API: un
    ## HTTPError e' una risposta vera, e rimandarla significherebbe ripetere la
    ## stessa richiesta sbagliata — o pagarla due volte.
    ultimo = None
    for tentativo in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            raise SystemExit("fal %d: %s" % (e.code, e.read().decode()[:800]))
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            ultimo = e
            attesa = 5 * (tentativo + 1)
            print("  rete: %s — riprovo fra %ds (%d/4)" % (e, attesa, tentativo + 1),
                  flush=True)
            time.sleep(attesa)
    raise SystemExit("rete non raggiungibile dopo 4 tentativi: %s" % ultimo)


def scarica(url, dest, etichetta="modello"):
    dest = assoluto(dest)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
        f.write(r.read())
    print("  salvato: %s (%.1f KB)" % (dest, os.path.getsize(dest) / 1024.0))
    try:
        os.makedirs(ARCHIVIO, exist_ok=True)
        import shutil
        shutil.copy2(dest, os.path.join(ARCHIVIO, os.path.basename(dest)))
    except Exception as e:
        print("  (archiviazione saltata: %s)" % e)
    return dest


def conta_triangoli(glb):
    """Legge il GLB e somma i triangoli, senza Blender.

    ⚠️ Serve perche' `face_limit` e' una RICHIESTA, non una garanzia, e conta
    facce: un ritorno in quad raddoppia i triangoli. Il numero che conta e'
    quello del file, non quello chiesto.
    """
    try:
        with open(glb, "rb") as f:
            dati = f.read()
        if dati[:4] != b"glTF":
            return None
        lung_json = int.from_bytes(dati[12:16], "little")
        testa = json.loads(dati[20:20 + lung_json].decode("utf-8"))
        acc = testa.get("accessors", [])
        tot = 0
        for m in testa.get("meshes", []):
            for p in m.get("primitives", []):
                modo = p.get("mode", 4)
                if modo != 4:            # 4 = TRIANGLES
                    continue
                i = p.get("indices")
                if i is not None and i < len(acc):
                    tot += acc[i].get("count", 0) // 3
                else:
                    pos = (p.get("attributes") or {}).get("POSITION")
                    if pos is not None and pos < len(acc):
                        tot += acc[pos].get("count", 0) // 3
        return tot
    except Exception:
        return None


## ⚠️ Gli URL di stato NON si ricostruiscono a mano. La coda di fal li espone
## sotto l'APPLICAZIONE (`tripo3d/p1`), non sotto il singolo endpoint
## (`tripo3d/p1/text-to-3d`): incollare il path completo da' 405, e il task nel
## frattempo e' gia' partito. La risposta di invio porta `status_url` e
## `response_url` proprio per questo — si usano quelli.
def base_richieste(request_id):
    app = MODELLO.rsplit("/", 1)[0]
    return "%s/%s/requests/%s" % (CODA, app, request_id)


def attendi(request_id, secondi, status_url=None, response_url=None):
    base = base_richieste(request_id)
    url_stato = status_url or (base + "/status")
    url_esito = response_url or base
    inizio = time.time()
    ultimo_stato = None
    while time.time() - inizio < secondi:
        s = chiama(url_stato)
        st = s.get("status")
        if st != ultimo_stato:
            print("  stato: %s (coda %s)" % (st, s.get("queue_position")), flush=True)
            ultimo_stato = st
        if st == "COMPLETED":
            return chiama(url_esito), s
        if st in ("FAILED", "CANCELLED"):
            raise SystemExit("task %s: %s" % (st, json.dumps(s)[:600]))
        time.sleep(3)
    raise SystemExit("scaduto dopo %ds. Il task continua sul server: "
                     "riprendilo con `recupera %s`" % (secondi, request_id))


def _url_glb(esito):
    mu = esito.get("model_urls") or {}
    for chiave_ in ("glb", "pbr_model", "base_model"):
        v = mu.get(chiave_)
        if isinstance(v, dict) and v.get("url"):
            return v["url"]
        if isinstance(v, str) and v:
            return v
    mm = esito.get("model_mesh")
    if isinstance(mm, dict) and mm.get("url"):
        return mm["url"]
    if isinstance(mm, str) and mm:
        return mm
    return None


def _una(prompt, dest, facce, texture, seme, attesa):
    corpo = {"prompt": prompt, "texture": bool(texture)}
    if facce:
        corpo["face_limit"] = int(facce)
    if seme is not None:
        corpo["model_seed"] = int(seme)
    invio = chiama("%s/%s" % (CODA, MODELLO), corpo)
    rid = invio.get("request_id")
    print("  request:", rid, flush=True)
    esito, stato = attendi(rid, attesa, invio.get("status_url"),
                           invio.get("response_url"))
    url = _url_glb(esito)
    if not url:
        raise SystemExit("nessun GLB nella risposta: %s" % json.dumps(esito)[:600])
    p = scarica(url, dest)
    tri = conta_triangoli(p)
    print("  triangoli nel file: %s (chiesti %s facce)" % (
        tri if tri is not None else "?", facce))
    m = stato.get("metrics") or esito.get("metrics")
    if m:
        print("  metriche fal:", json.dumps(m)[:200])
    return p, tri


def genera(args):
    print("genero:", os.path.basename(args.destinazione), flush=True)
    _una(args.prompt, args.destinazione, args.facce, not args.senza_texture,
         args.seme, args.attendi)


def lotto(args):
    voci = json.load(open(assoluto(args.lista), encoding="utf-8"))
    if args.solo:
        volute = set(args.solo)
        voci = [v for v in voci if v.get("id") in volute]
    if not voci:
        raise SystemExit("nessuna voce da fare")
    print("da fare: %d pezzi -> %s" % (len(voci), args.cartella))
    esiti = []
    for i, v in enumerate(voci, 1):
        vid = v["id"]
        dest = os.path.join(args.cartella, vid + ".glb")
        if os.path.exists(assoluto(dest)) and not args.rifai:
            print("[%d/%d] %s: c'e' gia', salto" % (i, len(voci), vid))
            continue
        print("[%d/%d] %s" % (i, len(voci), vid), flush=True)
        facce = v.get("facce", args.facce)
        try:
            _, tri = _una(v["prompt"], dest, facce, not args.senza_texture,
                          v.get("seme"), args.attendi)
            esiti.append((vid, tri))
        except SystemExit as e:
            print("  !! saltato: %s" % e)
            esiti.append((vid, None))
    print("\n=== fatto ===")
    for vid, tri in esiti:
        print("  %-28s %s" % (vid, tri if tri is not None else "FALLITO"))


def recupera(args):
    esito = chiama(base_richieste(args.request_id))
    url = _url_glb(esito)
    if not url:
        raise SystemExit("niente GLB: %s" % json.dumps(esito)[:600])
    p = scarica(url, args.destinazione)
    print("  triangoli:", conta_triangoli(p))


def main():
    ap = argparse.ArgumentParser(description="Tripo P1 (fal.ai): testo -> mesh leggera")
    sub = ap.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("genera", help="un pezzo solo")
    g.add_argument("prompt")
    g.add_argument("destinazione")
    ## Il tetto e' 20.000, ma per il sottobosco il punto e' stare in basso:
    ## un ciuffo d'erba a 400 facce e' gia' piu' di quanto la camera mostri.
    g.add_argument("--facce", type=int, default=400)
    g.add_argument("--seme", type=int, default=None)
    g.add_argument("--senza-texture", action="store_true")
    g.add_argument("--attendi", type=int, default=900)
    g.set_defaults(func=genera)

    l = sub.add_parser("lotto", help="una lista JSON di {id, prompt}")
    l.add_argument("lista")
    l.add_argument("cartella")
    l.add_argument("--facce", type=int, default=400)
    l.add_argument("--solo", nargs="+", help="solo questi id")
    l.add_argument("--rifai", action="store_true", help="rigenera anche se il file c'e'")
    l.add_argument("--senza-texture", action="store_true")
    l.add_argument("--attendi", type=int, default=900)
    l.set_defaults(func=lotto)

    r = sub.add_parser("recupera", help="scarica un request_id gia' finito")
    r.add_argument("request_id")
    r.add_argument("destinazione")
    r.set_defaults(func=recupera)

    a = ap.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
