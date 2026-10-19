"""Il ciclo del playtest (fase 3): gioca -> referto -> giudizio -> regressione.

    python arcanium/tools/playtest/ciclo.py gioca [--finto] [--nome N] [--max-secondi S]
    python arcanium/tools/playtest/ciclo.py rigioca <cartella partita>
    python arcanium/tools/playtest/ciclo.py scenario <nome>
    python arcanium/tools/playtest/ciclo.py referto <cartella> [--senza-visivo]
    python arcanium/tools/playtest/ciclo.py giudica <cartella> <caso> conferma|scarta
                                            [--causa evidenza|modello|codice|servizio]
                                            [--nota "..."] [--regressione NOME]
    python arcanium/tools/playtest/ciclo.py baseline <scenario>
    python arcanium/tools/playtest/ciclo.py suite [--solo scenari|regressioni]

Il REFERTO (referto.md + referto.json nella cartella della partita) tiene solo i
casi da guardare: le segnalazioni dei sorveglianti raggruppate (lo stesso
difetto sullo stesso soggetto a pochi secondi di distanza e' UN caso), i Noul
alti di Jev, gli errori del log contati per testo. Per ogni caso: tick e
secondi esatti del replay, i fotogrammi, e — se il difetto e' visivo — il
parere del canale visivo locale (Qwen3-VL sulla NPU), che vale come INDIZIO:
calibrato in fase 2, prende il magenta e manca l'affondato.

Il GIUDIZIO lo da' Claude (o l'utente) guardando i fotogrammi: `conferma` o
`scarta`. Uno scarto dice di chi e' la colpa — `evidenza` (allo stato mancava
l'informazione), `modello` (Jev o il VLM hanno sbagliato), `codice` (il
sorvegliante ha sbagliato), `servizio` (guasto di TypeSafe, NPU, Godot).
Una conferma con `--regressione NOME` copia nel repo, in
arcanium/tools/playtest/regressioni/NOME/, le azioni della partita (o il nome
dello scenario) e la condizione: QUEL difetto non deve ricomparire. La suite
la rigioca e fallisce finche' il difetto c'e'.

La BASELINE di uno scenario e' la sua telemetria "d'oro" piu' i fotogrammi
delle catture, fuori dal repo (pesano): la suite confronta la sostanza della
telemetria e le immagini con l'SSIM, e dice solo cio' che e' cambiato. Il VLM
non serve a questo: un pixel cambiato si vede con un numero, non con un parere.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gioca as G  # noqa: E402
import calibra_visivo as CV  # noqa: E402

REPO = G.REPO
RADICE = G.RADICE
QUI = Path(__file__).resolve().parent
REGRESSIONI = QUI / "regressioni"
## Errori del log gia' giudicati: non tornano nei referti (si contano soltanto).
## Sta nel repo, accanto alle regressioni: e' memoria del progetto.
NOTI = QUI / "noti.json"
BASELINE = RADICE / "baseline"
SUITE = RADICE / "suite"

## Segnalazioni dello stesso tipo sullo stesso soggetto a meno di questi tick
## l'una dall'altra sono lo stesso caso (10 s a 60 tick/s).
FINESTRA_CASO = 600
## Quale domanda stretta fare al canale visivo per ogni tipo di segnalazione.
## Solo i difetti che si VEDONO: "obiettivo scaduto" non ha una faccia.
DOMANDA_VISIVA = {
    "corpo_su_corpo": "in_groppa",
    "sotto_il_suolo": "affondato",
    "clip_vuota": "t_pose",
}
## Sotto questo SSIM (0..1) un fotogramma della baseline e' "cambiato".
SOGLIA_SSIM = 0.90
CAUSE = ("evidenza", "modello", "codice", "servizio")


# ═══════════════════════════════════════════════════════════════════════════
# Esecuzione: si passa da gioca.py, che resta l'unico che sa lanciare Godot
# ═══════════════════════════════════════════════════════════════════════════

def _gioca_py(args: list[str]) -> int:
    return subprocess.call([sys.executable, str(QUI / "gioca.py"), *args], cwd=REPO)


def _ultima(dove: Path, prefisso: str = "") -> Path:
    cart = [d for d in dove.iterdir() if d.is_dir() and d.name.startswith(prefisso)]
    return max(cart, key=lambda d: d.stat().st_mtime)


def _righe_json(f: Path) -> list[dict]:
    """Le righe di un .jsonl, saltando quelle rotte: una partita interrotta a
    meta' lascia l'ultima riga troncata."""
    out = []
    for r in f.read_text(encoding="utf-8").splitlines():
        try:
            out.append(json.loads(r))
        except json.JSONDecodeError:
            pass
    return out


def _ripulisci_project_godot():
    """Regola del progetto: dopo ogni Godot da riga di comando."""
    subprocess.call(["git", "checkout", "project.godot"], cwd=REPO,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _parametri(cartella: Path, scena: str, seme: int) -> SimpleNamespace:
    """Gli argomenti che `gioca.Partita` si aspetta, per un replay lanciato da qui."""
    return SimpleNamespace(cartella=str(cartella), scena=scena, seme=seme, decidi_ogni=12, max_secondi=900,
                           max_morti=5, temperatura=0.0, sessione=datetime.now().strftime("%Y-%m-%d"),
                           tetto=2.0, finto=True, verboso=False, video=False, scenario_res=None)


# ═══════════════════════════════════════════════════════════════════════════
# Il referto
# ═══════════════════════════════════════════════════════════════════════════

def _visivo_acceso() -> bool:
    try:
        urllib.request.urlopen(CV.URL.replace("/chat/completions", "/models"), timeout=3)
        return True
    except Exception:  # noqa: BLE001
        return False


def _norma_log(riga: str) -> str:
    """Il testo di un errore senza i numeri che cambiano (id, indirizzi, tick)."""
    return re.sub(r"\d+", "#", riga)[:220]


def _casi(cart: Path, con_noti: bool = False) -> list[dict]:
    casi: list[dict] = []
    # 1. Segnalazioni dei sorveglianti (le catture degli scenari non sono allarmi).
    grezze = []
    if (cart / "segnalazioni").exists():
        for d in sorted((cart / "segnalazioni").iterdir()):
            if not d.is_dir() or d.name.startswith("scen_") or not (d / "telemetria.json").exists():
                continue
            t = json.loads((d / "telemetria.json").read_text(encoding="utf-8"))
            grezze.append({"tipo": t.get("tipo", d.name.split("_", 1)[-1]), "tick": int(t.get("tick", 0)),
                           "soggetto": str(t.get("soggetto", "")), "testo": t.get("testo", ""),
                           "cartella": d})
    for s in sorted(grezze, key=lambda s: s["tick"]):
        uguale = next((c for c in casi if c["fonte"] == "sorvegliante" and c["tipo"] == s["tipo"]
                       and c["soggetto"] == s["soggetto"] and s["tick"] - c["ultimo_tick"] <= FINESTRA_CASO), None)
        if uguale:
            uguale["volte"] += 1
            uguale["ultimo_tick"] = s["tick"]
            continue
        casi.append({"fonte": "sorvegliante", "tipo": s["tipo"], "soggetto": s["soggetto"], "testo": s["testo"],
                     "tick": s["tick"], "ultimo_tick": s["tick"], "volte": 1,
                     "fotogrammi": [str(p) for p in sorted(s["cartella"].glob("*.png"))]})
    # 2. I Noul alti di Jev (una domanda per nemico: "l'animazione contraddice lo stato?").
    if (cart / "jev.jsonl").exists():
        for riga in (cart / "jev.jsonl").read_text(encoding="utf-8").splitlines():
            r = json.loads(riga)
            for dom, p in (r.get("nouls_alti") or {}).items():
                uguale = next((c for c in casi if c["fonte"] == "jev" and c["tipo"] == dom
                               and r["tick"] - c["ultimo_tick"] <= FINESTRA_CASO), None)
                if uguale:
                    uguale["volte"] += 1
                    uguale["ultimo_tick"] = r["tick"]
                    uguale["p_max"] = max(uguale["p_max"], p)
                    continue
                casi.append({"fonte": "jev", "tipo": dom, "soggetto": dom, "testo": f"Noul {p:.2f}",
                             "tick": r["tick"], "ultimo_tick": r["tick"], "volte": 1, "p_max": p, "fotogrammi": []})
    # 3. Gli errori del log, contati per testo: non hanno fotogrammi ma restano lavoro.
    lp = cart / "log_problemi.json"
    noti = _noti()
    if lp.exists():
        per_testo: dict[str, dict] = {}
        for e in json.loads(lp.read_text(encoding="utf-8")):
            k = _norma_log(e["riga"])
            if k not in per_testo:
                per_testo[k] = {"fonte": "log", "tipo": e["riga"].split(":", 1)[0], "soggetto": k,
                                "testo": e["riga"], "tick": e["tick"], "ultimo_tick": e["tick"], "volte": 0,
                                "fotogrammi": []}
            per_testo[k]["volte"] += 1
        casi.extend(per_testo.values())
    ## ⚠️ I numeri si danno su TUTTI i casi, noti compresi, e solo dopo si
    ## nascondono i noti: altrimenti ogni giudizio su un errore del log faceva
    ## scorrere la numerazione, e il giudizio successivo cadeva sul caso
    ## sbagliato (successo al primo collaudo, 2026-10-15).
    for i, c in enumerate(sorted(casi, key=lambda c: (c["tick"], c["fonte"], c["soggetto"]))):
        c["id"] = f"C{i + 1:02d}"
    return sorted((c for c in casi if con_noti or not (c["fonte"] == "log" and c["soggetto"] in noti)),
                  key=lambda c: c["id"])


def _noti() -> dict:
    return json.loads(NOTI.read_text(encoding="utf-8")) if NOTI.exists() else {}


def _noti_nascosti(cart: Path) -> int:
    lp = cart / "log_problemi.json"
    if not lp.exists():
        return 0
    noti = _noti()
    return sum(1 for e in json.loads(lp.read_text(encoding="utf-8")) if _norma_log(e["riga"]) in noti)


def referto(cart: Path, visivo: bool = True) -> dict:
    cart = Path(cart)
    casi = _casi(cart)
    verdetti = json.loads((cart / "verdetti.json").read_text(encoding="utf-8")) if (cart / "verdetti.json").exists() else {}
    acceso = visivo and _visivo_acceso()
    secondi_visivo = 0.0
    for c in casi:
        dom = DOMANDA_VISIVA.get(c["tipo"])
        gioco = next((p for p in c["fotogrammi"] if p.endswith("gioco.png")), None)
        if dom and gioco and acceso:
            risposta, sec, _ = CV.chiedi(CV.jpeg_b64(Path(gioco)), CV.DOMANDE[dom])
            secondi_visivo += sec
            c["visivo"] = {"domanda": dom, "risposta": risposta, "secondi": round(sec, 1)}
        elif dom and gioco:
            c["visivo"] = {"domanda": dom, "risposta": "visivo spento"}
        c["verdetto"] = verdetti.get(c["id"], {}).get("verdetto", "da giudicare")
    rg_path = next((cart / n for n in ("riepilogo_godot.json", "riepilogo_replay.json") if (cart / n).exists()),
                   cart / "riepilogo_godot.json")
    rg = json.loads(rg_path.read_text(encoding="utf-8")) if rg_path.exists() else {}
    rp = cart / "riepilogo.json"
    rj = json.loads(rp.read_text(encoding="utf-8")) if rp.exists() else {}
    r = {"cartella": str(cart), "scena": rg.get("scena"), "seme": rg.get("seme"), "esito": rg.get("esito"),
         "secondi_di_gioco": rg.get("secondi_di_gioco"), "morti": rg.get("morti"),
         "jev": rj.get("jev"), "visivo_acceso": acceso, "log_noti_nascosti": _noti_nascosti(cart), "secondi_visivo": round(secondi_visivo, 1),
         "casi": casi}
    (cart / "referto.json").write_text(json.dumps(r, indent=2, ensure_ascii=False), encoding="utf-8")
    (cart / "referto.md").write_text(_markdown(r, cart), encoding="utf-8")
    return r


def _markdown(r: dict, cart: Path) -> str:
    j = r.get("jev") or {}
    righe = [f"# Referto — {cart.name}", "",
             f"- scena `{r['scena']}`, seme {r['seme']}, esito **{r['esito']}**, "
             f"{r['secondi_di_gioco']} s di gioco, {r['morti']} morti",
             f"- Jev: {j.get('chiamate', 0)} chiamate, {j.get('costo_usd', 0)} $" if j else "- Jev: nessuna chiamata",
             f"- canale visivo: {'acceso' if r['visivo_acceso'] else 'spento'}"
             + (f", {r['secondi_visivo']} s" if r["visivo_acceso"] else ""),
             f"- righe di log gia' note e nascoste: {r['log_noti_nascosti']} (vedi arcanium/tools/playtest/noti.json)",
             f"- replay: `python arcanium/tools/playtest/gioca.py --rigioca \"{cart}\"`", "",
             f"## Casi da guardare: {len(r['casi'])}", ""]
    if not r["casi"]:
        righe.append("Nessuno.")
    for c in r["casi"]:
        sec = c["tick"] / 60.0
        righe.append(f"### {c['id']} · {c['tipo']} · {c['fonte']} · **{c['verdetto']}**")
        righe.append(f"- tick **{c['tick']}** ({sec:.1f} s)" + (f", ripetuto {c['volte']} volte fino al tick {c['ultimo_tick']}" if c["volte"] > 1 else ""))
        righe.append(f"- {c['testo']}")
        if c.get("visivo"):
            v = c["visivo"]
            righe.append(f"- visivo ({v['domanda']}): **{v['risposta']}** — indizio, non prova")
        for p in c["fotogrammi"]:
            righe.append(f"- [{Path(p).name}]({Path(p).as_uri()})")
        righe.append("")
    righe += ["## Come si giudica", "",
              "`python arcanium/tools/playtest/ciclo.py giudica <cartella> <caso> conferma --regressione NOME`",
              "`python arcanium/tools/playtest/ciclo.py giudica <cartella> <caso> scarta --causa evidenza|modello|codice|servizio`", ""]
    return "\n".join(righe)


# ═══════════════════════════════════════════════════════════════════════════
# Giudizio e regressioni
# ═══════════════════════════════════════════════════════════════════════════

def giudica(cart: Path, caso: str, verdetto: str, causa: str | None, nota: str, regressione: str | None) -> dict:
    cart = Path(cart)
    c = next((c for c in _casi(cart, con_noti=True) if c["id"] == caso), None)
    if c is None:
        raise SystemExit(f"caso {caso} assente nel referto di {cart.name}")
    if verdetto == "scarta" and causa not in CAUSE:
        raise SystemExit(f"uno scarto vuole la causa: {', '.join(CAUSE)}")
    vp = cart / "verdetti.json"
    v = json.loads(vp.read_text(encoding="utf-8")) if vp.exists() else {}
    v[caso] = {"verdetto": "confermato" if verdetto == "conferma" else "scartato", "causa": causa, "nota": nota,
               "tipo": c["tipo"], "tick": c["tick"], "testo": c["testo"][:300],
               "ts": datetime.now().isoformat(timespec="seconds")}
    if c["fonte"] == "log":
        ## un errore del log giudicato non torna nei referti successivi
        noti = _noti()
        noti[c["soggetto"]] = {"verdetto": v[caso]["verdetto"], "causa": causa, "nota": nota,
                               "esempio": c["testo"][:300], "ts": v[caso]["ts"]}
        NOTI.write_text(json.dumps(noti, indent=2, ensure_ascii=False), encoding="utf-8")
    if verdetto == "conferma" and regressione:
        v[caso]["regressione"] = crea_regressione(cart, c, regressione, nota)
    vp.write_text(json.dumps(v, indent=2, ensure_ascii=False), encoding="utf-8")
    referto(cart, visivo=False)
    return v[caso]


def crea_regressione(cart: Path, caso: dict, nome: str, nota: str) -> str:
    """Nel repo: le azioni (o lo scenario) e la condizione «questo difetto non torna»."""
    dest = REGRESSIONI / nome
    dest.mkdir(parents=True, exist_ok=True)
    ## Un replay vive DENTRO la cartella della partita: azioni e riepilogo
    ## originale stanno un livello sopra (nel replay c'e' riepilogo_replay.json).
    orig = cart if (cart / "riepilogo_godot.json").exists() else cart.parent
    rg = json.loads((orig / "riepilogo_godot.json").read_text(encoding="utf-8"))
    scen = rg.get("scenario") or ""
    reg = {"nome": nome, "creata": datetime.now().isoformat(timespec="seconds"), "origine": str(cart),
           "scena": rg["scena"], "seme": rg["seme"], "nota": nota,
           "tipo": caso["tipo"], "soggetto": caso["soggetto"], "tick": caso["tick"], "finestra": FINESTRA_CASO}
    if scen:
        reg["scenario"] = Path(scen).stem
    else:
        shutil.copy2(orig / "azioni.jsonl", dest / "azioni.jsonl")
        shutil.copy2(orig / "riepilogo_godot.json", dest / "riepilogo_godot.json")
        ## I PUNTI DI CONTROLLO: la sostanza della telemetria fino al difetto.
        ## Un replay di azioni, col gioco cambiato, puo' prendere un'altra strada
        ## e non arrivare mai dove stava il difetto: senza controlli la
        ## regressione "passava" senza aver provato niente (morso_sul_cadavere,
        ## 2026-10-15: obiettivo scaduto al tick 3602, il difetto era al 7493).
        tele = next((cart / n for n in ("telemetria.jsonl", "telemetria_replay.jsonl") if (cart / n).exists()), None)
        if tele:
            righe = _righe_json(tele)
            prima = [r for r in righe if r.get("tick", 0) <= caso["tick"]]
            passo = max(1, len(prima) // 12)
            scelti = prima[::passo] + prima[-1:]
            reg["controlli"] = [G.sostanza(r) for r in scelti]
    (dest / "regressione.json").write_text(json.dumps(reg, indent=2, ensure_ascii=False), encoding="utf-8")
    return str(dest.relative_to(REPO))


def esegui_regressione(dest: Path) -> dict:
    """Rigioca la regressione e cerca il difetto: PASSA se non ricompare."""
    reg = json.loads((dest / "regressione.json").read_text(encoding="utf-8"))
    t0 = time.time()
    if reg.get("scenario"):
        _gioca_py(["--scenario", reg["scenario"]])
        corsa = _ultima(RADICE / "scenari" / reg["scenario"])
    else:
        corsa = RADICE / "regressioni" / reg["nome"] / datetime.now().strftime("%Y%m%d-%H%M%S")
        p = G.Partita(_parametri(corsa, reg["scena"], reg["seme"]))
        p.lancia_godot(None, dest / "azioni.jsonl").wait()
        p.f_log.close()
    _ripulisci_project_godot()
    if reg.get("controlli"):
        tele = corsa / "telemetria_replay.jsonl"
        per_tick = {}
        if tele.exists():
            for t in _righe_json(tele):
                per_tick[t.get("tick")] = G.sostanza(t)
        for c in reg["controlli"]:
            if per_tick.get(c["tick"]) != c:
                return {"nome": reg["nome"], "passa": None, "secondi_muro": round(time.time() - t0, 1),
                        "corsa": str(corsa), "ritrovati": [],
                        "non_valida": f"il replay ha preso un'altra strada al tick {c['tick']}, prima del difetto "
                                      f"(tick {reg['tick']}): rifarla come scenario"}
    casi = _casi(corsa)
    ## Lo stesso tipo vicino al tick di allora; se la partita ha divergito dopo
    ## il fix, il difetto puo' cadere altrove ma non deve sparire per sbaglio:
    ## conta anche lo stesso tipo sullo stesso soggetto in qualunque tick.
    ritrovati = [c for c in casi if c["tipo"] == reg["tipo"]
                 and (abs(c["tick"] - reg["tick"]) <= reg["finestra"] or c["soggetto"] == reg["soggetto"])]
    return {"nome": reg["nome"], "passa": not ritrovati, "secondi_muro": round(time.time() - t0, 1),
            "corsa": str(corsa), "ritrovati": [{k: c[k] for k in ("id", "tipo", "tick", "testo")} for c in ritrovati]}


# ═══════════════════════════════════════════════════════════════════════════
# Baseline e suite
# ═══════════════════════════════════════════════════════════════════════════

def ssim(a: Path, b: Path, lato: int = 192) -> float:
    """SSIM medio a blocchi 8x8 sui grigi rimpiccioliti: solo PIL, niente numpy
    (non c'e' su questo Python). Basta a dire "e' cambiato" con una soglia."""
    ia = Image.open(a).convert("L")
    ib = Image.open(b).convert("L")
    alto = max(8, round(lato * ia.height / ia.width / 8) * 8)
    ia, ib = ia.resize((lato, alto)), ib.resize((lato, alto))
    pa, pb = list(ia.getdata()), list(ib.getdata())
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    tot, n = 0.0, 0
    for by in range(0, alto, 8):
        for bx in range(0, lato, 8):
            xa = [pa[(by + y) * lato + bx + x] for y in range(8) for x in range(8)]
            xb = [pb[(by + y) * lato + bx + x] for y in range(8) for x in range(8)]
            ma, mb = sum(xa) / 64.0, sum(xb) / 64.0
            va = sum((v - ma) ** 2 for v in xa) / 63.0
            vb = sum((v - mb) ** 2 for v in xb) / 63.0
            cov = sum((u - ma) * (v - mb) for u, v in zip(xa, xb)) / 63.0
            tot += ((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2))
            n += 1
    return tot / n


def _scenari() -> list[str]:
    return sorted(p.stem for p in (REPO / "arcanium" / "tools" / "scenari").glob("*.gd") if p.stem != "scenario")


def baseline(nome: str) -> dict:
    _gioca_py(["--scenario", nome])
    _ripulisci_project_godot()
    corsa = _ultima(RADICE / "scenari" / nome)
    dest = BASELINE / nome
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(corsa, dest, ignore=shutil.ignore_patterns("appdata"))
    rg = json.loads((dest / "riepilogo_godot.json").read_text(encoding="utf-8"))
    return {"scenario": nome, "baseline": str(dest), "impronta": rg.get("impronta_telemetria"),
            "catture": len([d for d in (dest / "segnalazioni").iterdir() if d.name.startswith("scen_")])}


def confronta_con_baseline(nome: str, corsa: Path) -> dict:
    base = BASELINE / nome
    out = {"scenario": nome, "corsa": str(corsa), "cambiato": False}
    if not base.exists():
        out["nota"] = "nessuna baseline: `ciclo.py baseline %s`" % nome
        return out
    div = G.prima_divergenza(base / "telemetria.jsonl", corsa / "telemetria.jsonl")
    if div:
        out["telemetria"] = div
        out["cambiato"] = True
    immagini = []
    for d in sorted((base / "segnalazioni").iterdir()):
        if not d.name.startswith("scen_"):
            continue
        for png in sorted(d.glob("*.png")):
            nuova = corsa / "segnalazioni" / d.name / png.name
            if not nuova.exists():
                immagini.append({"cattura": d.name, "vista": png.stem, "ssim": None, "nota": "manca nella corsa"})
                continue
            s = ssim(png, nuova)
            if s < SOGLIA_SSIM:
                immagini.append({"cattura": d.name, "vista": png.stem, "ssim": round(s, 3)})
    if immagini:
        out["immagini"] = immagini
        out["cambiato"] = True
    tb = {d.name for d in (base / "segnalazioni").iterdir()}
    tc = {d.name for d in (corsa / "segnalazioni").iterdir()} if (corsa / "segnalazioni").exists() else set()
    if tb != tc:
        out["segnalazioni"] = {"sparite": sorted(tb - tc), "nuove": sorted(tc - tb)}
        out["cambiato"] = True
    return out


def suite(solo: str | None) -> dict:
    t0 = time.time()
    esito = {"quando": datetime.now().isoformat(timespec="seconds"), "scenari": [], "regressioni": []}
    if solo in (None, "scenari"):
        for nome in _scenari():
            _gioca_py(["--scenario", nome])
            _ripulisci_project_godot()
            esito["scenari"].append(confronta_con_baseline(nome, _ultima(RADICE / "scenari" / nome)))
    if solo in (None, "regressioni") and REGRESSIONI.exists():
        for dest in sorted(d for d in REGRESSIONI.iterdir() if (d / "regressione.json").exists()):
            esito["regressioni"].append(esegui_regressione(dest))
    esito["secondi_muro"] = round(time.time() - t0, 1)
    SUITE.mkdir(parents=True, exist_ok=True)
    (SUITE / f"suite_{datetime.now():%Y%m%d-%H%M%S}.json").write_text(json.dumps(esito, indent=2, ensure_ascii=False), encoding="utf-8")
    return esito


def stampa_suite(e: dict):
    """Solo cio' che cambia."""
    cambiati = [s for s in e["scenari"] if s["cambiato"] or s.get("nota")]
    rotte = [r for r in e["regressioni"] if r["passa"] is False]
    invalide = [r for r in e["regressioni"] if r["passa"] is None]
    print(f"suite: {len(e['scenari'])} scenari, {len(e['regressioni'])} regressioni, {e['secondi_muro']} s")
    for s in cambiati:
        print(f"  CAMBIATO {s['scenario']}: " + (s.get("nota") or ""))
        if s.get("telemetria"):
            print(f"    telemetria diversa dal tick {s['telemetria'].get('tick')}")
        for im in s.get("immagini", []):
            print(f"    {im['cattura']}/{im['vista']}: SSIM {im['ssim']} {im.get('nota', '')}")
        if s.get("segnalazioni"):
            print(f"    segnalazioni sparite {s['segnalazioni']['sparite']} nuove {s['segnalazioni']['nuove']}")
    for r in rotte:
        print(f"  ROTTA {r['nome']}: il difetto e' ancora li' — " + "; ".join(f"tick {c['tick']} {c['testo']}" for c in r["ritrovati"]))
    for r in invalide:
        print(f"  NON VALIDA {r['nome']}: {r['non_valida']}")
    if not cambiati and not rotte and not invalide:
        print("  niente di cambiato, tutte le regressioni passano")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gioca")
    g.add_argument("--finto", action="store_true")
    g.add_argument("--nome", default="ciclo")
    g.add_argument("--max-secondi", default="600")
    g.add_argument("--scena")
    g.add_argument("--senza-visivo", action="store_true")
    rg = sub.add_parser("rigioca")
    rg.add_argument("cartella")
    rg.add_argument("--senza-visivo", action="store_true")
    sc = sub.add_parser("scenario")
    sc.add_argument("nome")
    sc.add_argument("--senza-visivo", action="store_true")
    rf = sub.add_parser("referto")
    rf.add_argument("cartella")
    rf.add_argument("--senza-visivo", action="store_true")
    gd = sub.add_parser("giudica")
    gd.add_argument("cartella")
    gd.add_argument("caso")
    gd.add_argument("verdetto", choices=("conferma", "scarta"))
    gd.add_argument("--causa", choices=CAUSE)
    gd.add_argument("--nota", default="")
    gd.add_argument("--regressione")
    bl = sub.add_parser("baseline")
    bl.add_argument("scenario", nargs="?", help="senza nome: tutti")
    su = sub.add_parser("suite")
    su.add_argument("--solo", choices=("scenari", "regressioni"))
    a = ap.parse_args()

    if a.cmd in ("gioca", "rigioca", "scenario"):
        if a.cmd == "gioca":
            args = ["--nome", a.nome, "--max-secondi", a.max_secondi] + (["--finto"] if a.finto else [])
            if a.scena:
                args += ["--scena", a.scena]
            _gioca_py(args)
            cart = _ultima(RADICE / "partite")
        elif a.cmd == "rigioca":
            _gioca_py(["--rigioca", a.cartella])
            cart = _ultima(Path(a.cartella), "replay_")
        else:
            _gioca_py(["--scenario", a.nome])
            cart = _ultima(RADICE / "scenari" / a.nome)
        _ripulisci_project_godot()
        r = referto(cart, visivo=not a.senza_visivo)
        print(f"referto: {cart / 'referto.md'}  ({len(r['casi'])} casi)")
    elif a.cmd == "referto":
        r = referto(Path(a.cartella), visivo=not a.senza_visivo)
        print(f"referto: {Path(a.cartella) / 'referto.md'}  ({len(r['casi'])} casi)")
        for c in r["casi"]:
            print(f"  {c['id']} {c['fonte']:<12} {c['tipo']:<24} tick {c['tick']:>6}  x{c['volte']}  {c['verdetto']}"
                  + (f"  visivo: {c['visivo']['risposta']}" if c.get("visivo") else ""))
    elif a.cmd == "giudica":
        print(json.dumps(giudica(Path(a.cartella), a.caso, a.verdetto, a.causa, a.nota, a.regressione), indent=2, ensure_ascii=False))
    elif a.cmd == "baseline":
        for nome in ([a.scenario] if a.scenario else _scenari()):
            print(json.dumps(baseline(nome), ensure_ascii=False))
    elif a.cmd == "suite":
        stampa_suite(suite(a.solo))


if __name__ == "__main__":
    main()
