"""Misure su Jev con stati VERI di una partita giocata (principio 2: misurare
prima di fidarsi). Ogni chiamata passa dal registro di spesa e dal tetto.

    python arcanium/tools/playtest/calibra_jev.py ordine <cartella partita> [--n 100]
    python arcanium/tools/playtest/calibra_jev.py noul <set etichettato .jsonl>

ordine — la documentazione avverte che Jev 1.13 tende a preferire la PRIMA
  opzione di una Choice ("Jev 1.13 jaggedness", #8). Qui si fa la stessa
  domanda due volte sullo stesso stato, con le opzioni in ordine diritto e
  rovesciato, e si conta: quante volte la scelta resta la stessa, e quanto
  pesa la posizione in testa.

noul — precisione, richiamo e calibrazione di un Noul su un set etichettato
  (righe {"stato":..., "domanda":..., "vero": bool}); le risposte grezze si
  salvano accanto, cosi' cambiare soglia non richiede di rifare l'inferenza.
"""

import argparse
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import domande_jev as DJ  # noqa: E402
from gioca import MODELLO, PREZZO_TOKEN, REGISTRO_SPESA, chiave_api, spesa_sessione  # noqa: E402

ESECUTORE = Path(__file__).resolve().parent / "esecutore_azioni.gd"


def criteri_gd() -> dict:
    """Le descrizioni delle azioni, lette dalla fonte unica (esecutore_azioni.gd)."""
    t = ESECUTORE.read_text(encoding="utf-8")
    blocco = t[t.index("const CRITERI := {"):t.index("}", t.index("const CRITERI := {"))]
    return dict(re.findall(r'"([a-z_]+)": "((?:[^"\\]|\\.)*)"', blocco))


class Cliente:
    def __init__(self, sessione: str, tetto: float, etichetta: str):
        from typesafe_sdk import TypeSafeClient
        self.c = TypeSafeClient(api_key=chiave_api(), model=MODELLO, timeout=15.0)
        self.sessione, self.tetto, self.etichetta = sessione, tetto, etichetta
        self.speso = 0.0

    def chiedi(self, stato, domande) -> dict:
        if spesa_sessione(self.sessione) >= self.tetto:
            raise SystemExit(f"tetto di spesa della sessione raggiunto ({self.tetto} $)")
        r = self.c.system_one(state=stato, questions=domande).model_dump()
        tok = int(r["usage"]["input_tokens"])
        costo = tok * PREZZO_TOKEN
        self.speso += costo
        with open(REGISTRO_SPESA, "a", encoding="utf-8") as f:
            f.write(json.dumps({"ts": datetime.now().isoformat(timespec="seconds"), "sessione": self.sessione,
                                "partita": self.etichetta, "tick": -1, "input_tokens": tok, "costo": costo}) + "\n")
        return r


def ordine(a):
    cart = Path(a.cartella)
    righe = [json.loads(l) for l in open(cart / "jev.jsonl", encoding="utf-8") if l.strip()]
    stati = [r["stato"] for r in righe if "stato" in r and r["stato"]["observed"]["enemies"]]
    passo = max(1, len(stati) // a.n)
    stati = stati[::passo][:a.n]
    crit = criteri_gd()
    cl = Cliente(a.sessione, a.tetto, f"calibra_ordine_{cart.name}")
    uguali, primo_dritto, primo_rovescio, fuori = 0, 0, 0, []
    out = open(cart / "calibra_ordine.jsonl", "w", encoding="utf-8")
    for s in stati:
        azioni = s["available_actions"]
        dritto = {k: crit.get(k, k) for k in azioni}
        rovescio = {k: crit.get(k, k) for k in reversed(azioni)}
        r1 = cl.chiedi(s, {"action": DJ.domanda_azione(dritto)})["answers"]["action"]
        r2 = cl.chiedi(s, {"action": DJ.domanda_azione(rovescio)})["answers"]["action"]
        uguali += r1["choice"] == r2["choice"]
        primo_dritto += r1["choice"] == azioni[0]
        primo_rovescio += r2["choice"] == azioni[-1]
        out.write(json.dumps({"stato": s, "dritto": r1, "rovescio": r2}) + "\n")
        if r1["choice"] != r2["choice"]:
            fuori.append((r1["choice"], round(r1["probabilities"][r1["choice"]], 2),
                          r2["choice"], round(r2["probabilities"][r2["choice"]], 2)))
    n = len(stati)
    print(f"stati: {n}  costo: {cl.speso:.4f} $")
    print(f"stessa scelta nei due ordini: {uguali}/{n} = {uguali / n:.0%}")
    print(f"scelta = prima opzione: dritto {primo_dritto}/{n}, rovesciato {primo_rovescio}/{n}")
    print("esempi di scelta cambiata (dritto, p, rovescio, p):", fuori[:8])


# Coppie stato -> clip COERENTI per regola (negativi certi) e la clip che le
# contraddice (positivi certi, costruiti scambiando solo quel campo).
def _coerente(e: dict) -> bool:
    a, s, att = e["animation"], e["state"], e["attack"]
    if s == "chasing you":
        return a in ("run", "walk")
    if s == "fighting":
        return ("bite" in a or "leap" in a) if att.startswith(("winding", "striking", "recovering")) else a in ("idle", "walk", "run")
    if s == "idle":
        return a == "idle"
    return False


def _contraddizione(e: dict) -> str | None:
    s, att = e["state"], e["attack"]
    if s == "chasing you":
        return "death"
    if s == "fighting" and att.startswith(("winding", "striking")):
        return "idle"
    if s == "idle":
        return "death"
    return None


def noul_anim(a):
    import random
    cart = Path(a.cartella)
    righe = [json.loads(l) for l in open(cart / "jev.jsonl", encoding="utf-8") if l.strip()]
    rng = random.Random(7)
    casi = []
    for r in righe:
        s = r.get("stato")
        if not s:
            continue
        for i, e in enumerate(s["observed"]["enemies"]):
            if _coerente(e):
                casi.append((s, i, False, e["animation"]))
                c = _contraddizione(e)
                if c:
                    s2 = json.loads(json.dumps(s))
                    s2["observed"]["enemies"][i]["animation"] = c
                    casi.append((s2, i, True, c))
    rng.shuffle(casi)
    pos = [c for c in casi if c[2]][:a.n // 2]
    neg = [c for c in casi if not c[2]][:a.n // 2]
    cl = Cliente(a.sessione, a.tetto, f"calibra_anim_{cart.name}")
    out = open(cart / "calibra_anim.jsonl", "w", encoding="utf-8")
    xs = []
    for s, i, vero, clip in pos + neg:
        r = cl.chiedi(s, {"q": DJ.domanda_animazione(i)})["answers"]["q"]["noul"]
        xs.append((r, vero))
        e = s["observed"]["enemies"][i]
        out.write(json.dumps({"vero": vero, "noul": r, "clip": clip, "state": e["state"], "attack": e["attack"]}) + "\n")
    print(f"casi: {len(xs)} (veri {sum(v for _, v in xs)})  costo: {cl.speso:.4f} $")
    for s in (0.5, 0.8):
        tp = sum(p >= s and v for p, v in xs); fp = sum(p >= s and not v for p, v in xs); fn = sum(p < s and v for p, v in xs)
        print(f"  soglia {s}: TP {tp} FP {fp} FN {fn}  precisione {tp / max(1, tp + fp):.2f}  richiamo {tp / max(1, tp + fn):.2f}")
    print("  calibrazione (fascia: n, frazione vera):", end=" ")
    for lo, hi in [(0, .2), (.2, .4), (.4, .6), (.6, .8), (.8, 1.01)]:
        b = [v for p, v in xs if lo <= p < hi]
        if b:
            print(f"[{lo:.1f}-{hi:.1f}) {len(b)} {sum(b) / len(b):.2f};", end=" ")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    o = sub.add_parser("ordine")
    o.add_argument("cartella")
    o.add_argument("--n", type=int, default=100)
    nn = sub.add_parser("anim")
    nn.add_argument("cartella")
    nn.add_argument("--n", type=int, default=120)
    for p in (o, nn):
        p.add_argument("--sessione", default=datetime.now().strftime("%Y-%m-%d"))
        p.add_argument("--tetto", type=float, default=2.0)
    a = ap.parse_args()
    {"ordine": ordine, "anim": noul_anim}[a.cmd](a)


if __name__ == "__main__":
    main()
