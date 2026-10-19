"""L'orchestratore del playtest: Jev gioca ad Arcanium in modalita' discreta.

    python arcanium/tools/playtest/gioca.py --nome traccia_1 --seme 1
    python arcanium/tools/playtest/gioca.py --rigioca <cartella della partita>

Cosa fa:
  1. crea la cartella della partita sotto C:/Users/Adriano/LOCAL/vaelthar_playtest/
     (FUORI dal repo), con un APPDATA suo: il gioco salva da solo in user://, e
     lanciato con l'APPDATA normale sovrascriverebbe i salvataggi dei test
     manuali (skill arcanium-playtest);
  2. apre un socket, lancia Godot (renderer vero, --fixed-fps 60) col ponte acceso;
  3. a ogni stato che il ponte manda, fa UNA richiesta a Jev con la Choice
     dell'azione, i Noul dei sorveglianti e lo Score di gravita', tutte insieme;
  4. registra ogni richiesta e risposta (probabilita' comprese), token, costo e
     latenza; si ferma prima di superare il tetto di spesa della sessione;
  5. legge lo stdout di Godot e annota errori e avvisi col tick;
  6. scrive riepilogo.json.

Con --rigioca non chiama Jev: Godot rigioca azioni.jsonl da solo, e alla fine
si confronta l'impronta della telemetria con quella della partita originale.
"""

import argparse
import json
import os
import random
import re
import socket
import statistics
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import domande_jev as DJ  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
GODOT = r"C:\Godot\Godot_v4.7.1-stable_win64_console.exe"
RADICE = Path(r"C:\Users\Adriano\LOCAL\vaelthar_playtest")
REGISTRO_SPESA = RADICE / "spesa_typesafe.jsonl"
MODELLO = "jev-1.13.0"
PREZZO_TOKEN = 0.042 / 1e6   # $ per token in input (docs.typesafe.ai/models); l'output e' gratis
RE_LOG = re.compile(r"^(SCRIPT ERROR|ERROR|WARNING|USER ERROR|USER WARNING)\b")


def chiave_api() -> str:
    """La chiave sta nelle variabili UTENTE di Windows: un processo aperto prima
    che venisse registrata non la vede nell'ambiente. Mai stamparla."""
    k = os.environ.get("TYPESAFE_API_KEY")
    if k:
        return k
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as h:
        return winreg.QueryValueEx(h, "TYPESAFE_API_KEY")[0]


def spesa_sessione(sessione: str) -> float:
    if not REGISTRO_SPESA.exists():
        return 0.0
    tot = 0.0
    for riga in REGISTRO_SPESA.read_text(encoding="utf-8").splitlines():
        r = json.loads(riga)
        if r.get("sessione") == sessione:
            tot += float(r["costo"])
    return tot


class Partita:
    def __init__(self, a):
        self.a = a
        self.cartella = Path(a.cartella)
        self.cartella.mkdir(parents=True, exist_ok=True)
        self.f_jev = open(self.cartella / "jev.jsonl", "a", encoding="utf-8")
        self.f_log = open(self.cartella / "godot.log", "w", encoding="utf-8")
        self.rng = random.Random(a.seme)
        self.tick = 0
        self.latenze, self.token, self.costi = [], [], []
        self.segnalazioni, self.log_problemi, self.incerti = [], [], []
        self.ciao, self.fine = None, None
        self.fermare = ""
        self.spesa_iniziale = spesa_sessione(a.sessione)
        self.client = None

    # ─── Jev ────────────────────────────────────────────────────────────────
    def finto(self, msg: dict) -> dict:
        """Giocatore finto a regola fissa, gratis: serve a collaudare il ponte."""
        c = msg["criteri"]
        nemici = msg["stato"]["observed"]["enemies"]
        vicino = any(e["distance"] in ("very close", "close") for e in nemici)
        if "close_menu" in c:
            az = "close_menu"
        elif "interact" in c and not nemici and "not yet activated" in msg["stato"]["observed"].get("within_reach", ""):
            az = "interact"
        elif vicino and "lock_on" in c:
            az = "lock_on"
        elif vicino and any(e["attack"].startswith("winding") for e in nemici):
            az = "dodge"
        elif vicino:
            az = "attack_light"
        elif nemici and "approach" in c:
            az = "approach"
        else:
            az = "move_on"
        if "low obstacle" in msg["stato"]["observed"].get("path_ahead", "") and not vicino:
            az = "jump"
        return {"tipo": "azione", "tick": msg["tick"], "azione": az, "fonte": "finto"}

    def jev(self, msg: dict) -> dict:
        if self.a.finto:
            return self.finto(msg)
        speso = self.spesa_iniziale + sum(self.costi)
        if speso >= self.a.tetto:
            self.fermare = f"tetto di spesa della sessione raggiunto ({speso:.4f} $ su {self.a.tetto} $)"
            return {"tipo": "azione", "azione": "wait", "fonte": "budget", "stop": True, "perche": self.fermare}
        from typesafe_sdk import TypeSafeClient
        if self.client is None:
            self.client = TypeSafeClient(api_key=chiave_api(), model=MODELLO, timeout=15.0)
        domande = DJ.domande(msg["criteri"], msg["stato"])
        t0 = time.perf_counter()
        try:
            r = self.client.system_one(state=msg["stato"], questions=domande)
        except Exception as e:  # noqa: BLE001 — un guasto del servizio si registra, non si inventa
            self.scrivi_jev({"tick": msg["tick"], "errore": type(e).__name__})
            return {}
        lat = (time.perf_counter() - t0) * 1000
        d = r.model_dump()
        tok = int(d["usage"]["input_tokens"])
        costo = tok * PREZZO_TOKEN
        self.latenze.append(lat)
        self.token.append(tok)
        self.costi.append(costo)
        with open(REGISTRO_SPESA, "a", encoding="utf-8") as f:
            f.write(json.dumps({"ts": datetime.now().isoformat(timespec="seconds"), "sessione": self.a.sessione,
                                "partita": self.cartella.name, "tick": msg["tick"], "input_tokens": tok,
                                "costo": costo}) + "\n")
        risposte = d["answers"]
        prob = risposte["action"]["probabilities"]
        azione = self.scegli(prob)
        nouls = {k: v["noul"] for k, v in risposte.items() if v.get("type") == "noul"}
        alti = {k: p for k, p in nouls.items() if p >= DJ.SOGLIA_CATTURA}
        incerti = {k: p for k, p in nouls.items() if DJ.FASCIA_INCERTA[0] <= p <= DJ.FASCIA_INCERTA[1]}
        if incerti:
            self.incerti.append({"tick": msg["tick"], "nouls": incerti})
        self.scrivi_jev({"tick": msg["tick"], "modello": d["model"], "latenza_ms": round(lat, 1),
                         "input_tokens": tok, "costo": costo, "stato": msg["stato"],
                         "risposte": risposte, "azione": azione, "nouls_alti": alti, "nouls_incerti": incerti})
        return {"tipo": "azione", "tick": msg["tick"], "azione": azione, "fonte": "jev",
                "cattura": bool(alti), "motivo_cattura": ", ".join(f"{k}={p:.2f}" for k, p in alti.items())}

    def scegli(self, prob: dict) -> str:
        """Temperatura 0 = sempre l'opzione piu' probabile. Sopra 0 si campiona
        con un generatore a seme fisso: la partita resta riproducibile anche
        senza replay (che comunque rilegge le azioni scritte)."""
        if self.a.temperatura <= 0.01:
            return max(prob, key=prob.get)
        nomi = list(prob)
        pesi = [max(prob[n], 1e-9) ** (1 / self.a.temperatura) for n in nomi]
        return self.rng.choices(nomi, weights=pesi)[0]

    def scrivi_jev(self, rec: dict):
        self.f_jev.write(json.dumps(rec, ensure_ascii=False) + "\n")
        self.f_jev.flush()

    # ─── Godot ──────────────────────────────────────────────────────────────
    def lancia_godot(self, porta: int | None, replay: Path | None) -> subprocess.Popen:
        env = dict(os.environ, APPDATA=str(self.cartella / "appdata"))
        (self.cartella / "appdata").mkdir(exist_ok=True)
        utente = ["--playtest", f"--seme={self.a.seme}", f"--out={self.cartella.as_posix()}",
                  f"--decidi_ogni={self.a.decidi_ogni}", f"--max_secondi={self.a.max_secondi}",
                  f"--max_morti={self.a.max_morti}"]
        if getattr(self.a, "scenario_res", None):
            utente += [f"--scenario={self.a.scenario_res}"]
        elif replay:
            utente += [f"--azioni={replay.as_posix()}"]
        else:
            utente += [f"--porta={porta}"]
        video = []
        if replay and getattr(self.a, "video", False):
            # MJPEG grezzo di Godot; poi ffmpeg lo porta in mp4 (vedi rigioca).
            video = ["--write-movie", str(self.cartella / "partita.avi")]
        cmd = [GODOT, "--path", str(REPO), "--fixed-fps", "60", *video, self.a.scena, "--", *utente]
        self.f_log.write("CMD " + " ".join(cmd) + "\n")
        p = subprocess.Popen(cmd, cwd=REPO, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace", bufsize=1)
        threading.Thread(target=self.leggi_log, args=(p,), daemon=True).start()
        return p

    def leggi_log(self, p: subprocess.Popen):
        for riga in p.stdout:
            riga = riga.rstrip("\n")
            self.f_log.write(riga + "\n")
            if RE_LOG.match(riga):
                self.log_problemi.append({"tick": self.tick, "riga": riga[:400]})
            if riga.startswith("PLAYTEST:") and self.a.verboso:
                print(riga)
        self.f_log.flush()

    def gioca(self) -> dict:
        srv = socket.socket()
        srv.bind(("127.0.0.1", 0))
        srv.listen(1)
        porta = srv.getsockname()[1]
        srv.settimeout(120)
        t0 = time.time()
        proc = self.lancia_godot(porta, None)
        conn, _ = srv.accept()
        conn.settimeout(None)
        f = conn.makefile("rwb")
        try:
            for raw in f:
                msg = json.loads(raw)
                tipo = msg["tipo"]
                if tipo == "ciao":
                    self.ciao = msg
                    print(f"Godot pronto: {msg['scena']}, {msg['tappe']} tappe, seme {msg['seme']}")
                elif tipo == "stato":
                    self.tick = msg["tick"]
                    risposta = self.jev(msg)
                    f.write((json.dumps(risposta) + "\n").encode())
                    f.flush()
                    n = len(self.costi)
                    if n and n % 25 == 0:
                        print(f"  tick {self.tick}: {n} chiamate, {sum(self.costi):.4f} $, "
                              f"mediana {statistics.median(self.latenze):.0f} ms")
                elif tipo == "segnalazione":
                    self.segnalazioni.append(msg)
                    print(f"  SEGNALAZIONE {msg['id']}: {msg['allarme']['testo']}")
                elif tipo == "fine":
                    self.fine = msg["riepilogo"]
                    break
        except KeyboardInterrupt:
            self.fermare = "interrotto a mano"
        finally:
            conn.close()
            srv.close()
        try:
            proc.wait(timeout=120)
        except subprocess.TimeoutExpired:
            proc.kill()
        return self.riepilogo(time.time() - t0, proc.returncode)

    def riepilogo(self, muro: float, codice: int | None) -> dict:
        r = {
            "partita": self.cartella.name, "modello": MODELLO, "sessione": self.a.sessione,
            "godot": self.fine, "codice_uscita": codice, "fermato": self.fermare,
            "secondi_muro": round(muro, 1),
            "jev": {
                "chiamate": len(self.costi), "token_input": sum(self.token),
                "costo_usd": round(sum(self.costi), 6),
                "latenza_mediana_ms": round(statistics.median(self.latenze), 1) if self.latenze else None,
                "latenza_p95_ms": round(sorted(self.latenze)[int(0.95 * (len(self.latenze) - 1))], 1) if self.latenze else None,
                "token_medi": round(statistics.mean(self.token)) if self.token else None,
            },
            "spesa_sessione_usd": round(self.spesa_iniziale + sum(self.costi), 6),
            "segnalazioni": [{"id": s["id"], "testo": s["allarme"]["testo"]} for s in self.segnalazioni],
            "noul_incerti": len(self.incerti),
            "log_problemi": len(self.log_problemi),
        }
        (self.cartella / "riepilogo.json").write_text(json.dumps(r, indent=2, ensure_ascii=False), encoding="utf-8")
        (self.cartella / "log_problemi.json").write_text(json.dumps(self.log_problemi, indent=1, ensure_ascii=False), encoding="utf-8")
        return r


def rigioca(a) -> dict:
    orig = Path(a.rigioca)
    rg = json.loads((orig / "riepilogo_godot.json").read_text(encoding="utf-8"))
    a.cartella = str(orig / f"replay_{datetime.now():%H%M%S}")
    a.seme = rg["seme"]
    a.scena = rg["scena"]
    p = Partita(a)
    t0 = time.time()
    proc = p.lancia_godot(None, orig / "azioni.jsonl")
    proc.wait()
    nuovo = json.loads((Path(a.cartella) / "riepilogo_replay.json").read_text(encoding="utf-8"))
    # Identica = nessuna differenza nella telemetria sul tratto in comune, e
    # stessa lunghezza. Dopo un fix la partita PUO' divergere: si dice dove.
    div = prima_divergenza(orig / "telemetria.jsonl", Path(a.cartella) / "telemetria_replay.jsonl")
    # L'impronta MD5 vale solo a parita' di formato; la sostanza vale sempre.
    identica = div is None
    esito_impronta = nuovo["impronta_telemetria"] == rg["impronta_telemetria"]
    tipi = {}
    for d in (Path(a.cartella) / "segnalazioni").iterdir():
        tipo = d.name.split("_", 1)[1]
        tipi[tipo] = tipi.get(tipo, 0) + 1
    esito = {"identica": identica, "impronta_uguale": esito_impronta, "originale": rg, "replay": nuovo,
             "secondi_muro": round(time.time() - t0, 1),
             "segnalazioni_per_tipo": tipi}
    if div:
        esito["prima_divergenza"] = div
    (Path(a.cartella) / "confronto.json").write_text(json.dumps(esito, indent=2, ensure_ascii=False), encoding="utf-8")
    avi = Path(a.cartella) / "partita.avi"
    if avi.exists():
        esito["video"] = comprimi_video(avi)
    return esito


FFMPEG = ["C:/Software Utili/ffmpeg/ffmpeg-master-latest-win64-gpl/bin/ffmpeg.exe",
          "C:/Software Utili/ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe", "ffmpeg"]


def comprimi_video(avi: Path) -> str:
    """Il .avi di --write-movie e' MJPEG e pesa gigabyte: si porta in H.264 e si butta."""
    mp4 = avi.with_suffix(".mp4")
    for exe in FFMPEG:
        if exe == "ffmpeg" or Path(exe).exists():
            r = subprocess.run([exe, "-y", "-loglevel", "error", "-i", str(avi), "-c:v", "libx264", "-crf", "23",
                                "-preset", "veryfast", "-pix_fmt", "yuv420p", "-c:a", "aac", str(mp4)])
            if r.returncode == 0 and mp4.exists():
                avi.unlink()
                return str(mp4)
    return str(avi)


def scenario(a) -> dict:
    """Gioca uno scenario di arcanium/tools/scenari/: niente Jev, niente socket.
    La scena la dichiara lo scenario stesso (`var scena := "res://..."`)."""
    sorgente = REPO / "arcanium" / "tools" / "scenari" / f"{a.scenario}.gd"
    m = re.search(r'^var scena := "([^"]+)"', sorgente.read_text(encoding="utf-8"), re.M)
    a.scena = m.group(1) if m else "res://arcanium/levels/arena_branco.tscn"
    a.scenario_res = f"res://arcanium/tools/scenari/{a.scenario}.gd"
    a.cartella = str(RADICE / "scenari" / a.scenario / f"{datetime.now():%Y%m%d-%H%M%S}")
    p = Partita(a)
    t0 = time.time()
    proc = p.lancia_godot(None, None)
    proc.wait()
    cart = Path(a.cartella)
    r = {"scenario": a.scenario, "cartella": a.cartella, "secondi_muro": round(time.time() - t0, 1),
         "codice_uscita": proc.returncode}
    if (cart / "riepilogo_godot.json").exists():
        r["godot"] = json.loads((cart / "riepilogo_godot.json").read_text(encoding="utf-8"))
    if (cart / "etichette.json").exists():
        r["etichette"] = json.loads((cart / "etichette.json").read_text(encoding="utf-8"))
    tipi = {}
    if (cart / "segnalazioni").exists():
        for d in (cart / "segnalazioni").iterdir():
            if d.name.startswith("scen_"):
                tipo = "cattura_scenario"
            else:
                tipo = d.name.split("_", 1)[1]
            tipi[tipo] = tipi.get(tipo, 0) + 1
    r["segnalazioni_per_tipo"] = tipi
    r["log_problemi"] = len(p.log_problemi)
    (cart / "riepilogo.json").write_text(json.dumps(r, indent=2, ensure_ascii=False), encoding="utf-8")
    return r


def sostanza(t: dict) -> dict:
    """Cio' che una regressione deve ritrovare uguale. Non le righe intere:
    la telemetria si arricchisce (campi nuovi) e una partita registrata prima
    deve restare confrontabile con il codice di dopo."""
    p = t["player"]
    return {"tick": t["tick"], "tappa": t["tappa"],
            "player": [p["pos"], p["hp"], p["fa"], p.get("a_terra")],
            "nemici": [[n["nome"], n["pos"], n["stato"], n["hp"], n["clip"]] for n in t["nemici"]]}


def prima_divergenza(f1: Path, f2: Path):
    l1 = [l for l in f1.read_text(encoding="utf-8").splitlines() if l.strip()]
    l2 = [l for l in f2.read_text(encoding="utf-8").splitlines() if l.strip()]
    for r1, r2 in zip(l1, l2):
        a, b = json.loads(r1), json.loads(r2)
        if sostanza(a) != sostanza(b):
            return {"tick": a.get("tick"), "originale": sostanza(a), "replay": sostanza(b)}
    if len(l1) != len(l2):
        return {"tick": None, "nota": f"lunghezze diverse: {len(l1)} contro {len(l2)} decisioni"}
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--nome", default="partita")
    ap.add_argument("--scena", default="res://arcanium/levels/arena_branco.tscn")
    ap.add_argument("--seme", type=int, default=1)
    ap.add_argument("--decidi-ogni", dest="decidi_ogni", type=int, default=12, help="tick fra due decisioni (12 = 0,2 s)")
    ap.add_argument("--max-secondi", dest="max_secondi", type=float, default=900)
    ap.add_argument("--max-morti", dest="max_morti", type=int, default=5)
    ap.add_argument("--temperatura", type=float, default=0.0)
    ap.add_argument("--sessione", default=datetime.now().strftime("%Y-%m-%d"), help="per il tetto di spesa")
    ap.add_argument("--tetto", type=float, default=2.0, help="$ massimi per sessione di lavoro")
    ap.add_argument("--rigioca", help="cartella di una partita da rigiocare senza Jev")
    ap.add_argument("-v", "--verboso", action="store_true")
    ap.add_argument("--finto", action="store_true", help="giocatore a regola fissa, senza Jev (gratis)")
    ap.add_argument("--video", action="store_true", help="col replay: registra la partita in video (fluida)")
    ap.add_argument("--scenario", help="nome di uno scenario in arcanium/tools/scenari/ (senza .gd)")
    a = ap.parse_args()
    RADICE.mkdir(parents=True, exist_ok=True)
    if a.scenario:
        r = scenario(a)
        print(json.dumps({k: r.get(k) for k in ("scenario", "cartella", "secondi_muro", "segnalazioni_per_tipo", "log_problemi")},
                         indent=2, ensure_ascii=False))
        print("etichette:", len(r.get("etichette", [])))
        return
    if a.rigioca:
        e = rigioca(a)
        print(json.dumps({k: e[k] for k in ("identica", "secondi_muro", "segnalazioni_per_tipo")}, indent=2))
        print("morti:", e["originale"]["morti"], "->", e["replay"]["morti"])
        if not e["identica"]:
            print("prima divergenza al tick", (e.get("prima_divergenza") or {}).get("tick"))
        return
    a.cartella = str(RADICE / "partite" / f"{datetime.now():%Y%m%d-%H%M%S}_{a.nome}")
    r = Partita(a).gioca()
    print(json.dumps(r, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
