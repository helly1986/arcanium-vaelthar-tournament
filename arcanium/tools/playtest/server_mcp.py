"""Il playtest di Arcanium come server MCP (stdio).

    python arcanium/tools/playtest/server_mcp.py

Strumenti: gioca_partita, rigioca_partita, esegui_scenario, giudica_stato,
giudica_fotogramma, elenca_partite. Il contratto e' su FILE JSON: ogni
strumento lascia il suo risultato nella cartella della partita o dello scenario
(sotto C:/Users/Adriano/LOCAL/vaelthar_playtest/, fuori dal repo) e restituisce
il percorso piu' una sintesi. Niente protocolli fra agenti: chi chiama legge i
file.

Tutto quello che lancia Godot passa da gioca.py, quindi con APPDATA isolato
(skill arcanium-playtest) e col tetto di spesa di TypeSafe.
"""

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mcp.server.mcpserver import MCPServer  # noqa: E402

import calibra_jev as CJ  # noqa: E402
import calibra_visivo as CV  # noqa: E402
import domande_jev as DJ  # noqa: E402
from gioca import RADICE, REPO  # noqa: E402

GIOCA = Path(__file__).resolve().parent / "gioca.py"

server = MCPServer(
    name="arcanium-playtest",
    instructions="Playtest autonomo di Arcanium: Jev (TypeSafe) gioca, i sorveglianti segnalano, il canale "
                 "visivo locale giudica i fotogrammi. I risultati sono file JSON sotto "
                 "C:/Users/Adriano/LOCAL/vaelthar_playtest/. Nessun System 1 ha l'ultima parola: le "
                 "segnalazioni vanno confermate guardando fotogrammi e telemetria.",
)


def _esegui(args: list[str], timeout: int) -> str:
    p = subprocess.run([sys.executable, "-u", str(GIOCA), *args], cwd=REPO, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    subprocess.run(["git", "checkout", "project.godot"], cwd=REPO, capture_output=True)
    return (p.stdout or "") + (("\n[stderr]\n" + p.stderr[-2000:]) if p.returncode else "")


def _ultima(cartella: Path) -> Path | None:
    xs = sorted((d for d in cartella.iterdir() if d.is_dir()), key=lambda d: d.stat().st_mtime) if cartella.exists() else []
    return xs[-1] if xs else None


@server.tool()
def gioca_partita(nome: str = "partita", seme: int = 1, max_secondi: float = 600, finto: bool = False,
                  tetto_usd: float = 2.0) -> dict:
    """Fa giocare Jev (o il giocatore finto, gratis) sulla Traccia Perduta in modalita' discreta.
    Restituisce la cartella della partita e riepilogo.json (esito, tappe, morti, costo, latenze,
    segnalazioni). Lento: minuti di muro."""
    args = ["--nome", nome, "--seme", str(seme), "--max-secondi", str(max_secondi), "--tetto", str(tetto_usd)]
    if finto:
        args.append("--finto")
    log = _esegui(args, timeout=4 * 3600)
    cart = _ultima(RADICE / "partite")
    rie = json.loads((cart / "riepilogo.json").read_text(encoding="utf-8")) if cart and (cart / "riepilogo.json").exists() else None
    return {"cartella": str(cart), "riepilogo": rie, "coda_log": log[-1500:]}


@server.tool()
def rigioca_partita(cartella: str, video: bool = False) -> dict:
    """Rigioca una partita registrata SENZA Jev (azioni.jsonl) e la confronta con l'originale:
    identica = stessa sostanza della telemetria. Con video=True registra anche un mp4 fluido."""
    args = ["--rigioca", cartella] + (["--video"] if video else [])
    log = _esegui(args, timeout=4 * 3600)
    r = _ultima(Path(cartella))
    conf = json.loads((r / "confronto.json").read_text(encoding="utf-8")) if r and (r / "confronto.json").exists() else None
    if conf:
        conf = {k: conf.get(k) for k in ("identica", "impronta_uguale", "secondi_muro", "segnalazioni_per_tipo",
                                         "prima_divergenza", "video")}
    return {"cartella_replay": str(r), "confronto": conf, "coda_log": log[-1500:]}


@server.tool()
def esegui_scenario(nome: str) -> dict:
    """Gioca uno scenario di arcanium/tools/scenari/ (es. colpi_lupi, difetti_visivi, ululato_traccia):
    situazione montata, catture a tick precisi, etichette di verita'."""
    log = _esegui(["--scenario", nome], timeout=3600)
    cart = _ultima(RADICE / "scenari" / nome)
    rie = json.loads((cart / "riepilogo.json").read_text(encoding="utf-8")) if cart and (cart / "riepilogo.json").exists() else None
    return {"cartella": str(cart), "riepilogo": rie, "coda_log": log[-1000:]}


@server.tool()
def giudica_stato(stato: dict | None = None, file: str | None = None, tetto_usd: float = 2.0) -> dict:
    """Fa a Jev le domande del playtest su uno stato (lo stato per Jev scritto da osservatore.gd, cioe'
    {observed, inferred, available_actions}): la Choice dell'azione e un Noul di coerenza animazione per
    nemico. Passa dal registro di spesa. Le probabilita' sono giudizi, non verita'."""
    if stato is None:
        stato = json.loads(Path(file).read_text(encoding="utf-8"))
        stato = stato.get("stato", stato)
    crit = CJ.criteri_gd()
    criteri = {k: crit.get(k, k) for k in stato.get("available_actions", list(crit))}
    from datetime import datetime
    cl = CJ.Cliente(datetime.now().strftime("%Y-%m-%d"), tetto_usd, "mcp_giudica_stato")
    r = cl.chiedi(stato, DJ.domande(criteri, stato))
    return {"risposte": r["answers"], "token": r["usage"], "costo_usd": round(cl.speso, 6),
            "soglia_anim": 0.5, "nota": "Noul anim_i >= 0.5: animazione incoerente col nemico i (tarato il 2026-10-07)"}


@server.tool()
def giudica_fotogramma(immagine: str, difetti: list[str] | None = None, domanda_libera: str | None = None) -> dict:
    """Chiede al VLM locale (Qwen3-VL-4B sulla NPU, `flm serve qwen3vl-it:4b` deve essere acceso) una
    domanda STRETTA si'/no per difetto. difetti: chiavi fra magenta, affondato, in_groppa, dentro_roccia,
    z_fighting, t_pose (default: tutte). ~5 s a domanda. Un si' e' un indizio da confermare, non un referto."""
    b = CV.jpeg_b64(Path(immagine))
    domande = {k: CV.DOMANDE[k] for k in (difetti or list(CV.DOMANDE))}
    if domanda_libera:
        domande["libera"] = domanda_libera
    out = {}
    try:
        for k, q in domande.items():
            risposta, sec, _ = CV.chiedi(b, q)
            out[k] = {"si": risposta.startswith("yes"), "risposta": risposta, "secondi": round(sec, 1)}
    except OSError as e:
        return {"errore": f"VLM non raggiungibile ({e}): avviare 'C:/Program Files/flm/flm.exe serve qwen3vl-it:4b'"}
    return {"immagine": immagine, "giudizi": out}


@server.tool()
def elenca_partite(limite: int = 10) -> list[dict]:
    """Le ultime partite e gli ultimi scenari, con esito e segnalazioni."""
    righe = []
    for base in (RADICE / "partite", *(RADICE / "scenari").glob("*")):
        if not base.exists():
            continue
        for d in base.iterdir():
            f = d / "riepilogo.json"
            if f.exists():
                r = json.loads(f.read_text(encoding="utf-8"))
                righe.append({"cartella": str(d), "modificata": d.stat().st_mtime,
                              "esito": (r.get("godot") or {}).get("esito"), "segnalazioni": r.get("segnalazioni")
                              or r.get("segnalazioni_per_tipo"), "costo_usd": (r.get("jev") or {}).get("costo_usd")})
    righe.sort(key=lambda x: -x["modificata"])
    return righe[:limite]


if __name__ == "__main__":
    server.run("stdio")
