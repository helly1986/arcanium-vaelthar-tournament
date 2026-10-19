"""Quanto avanzano i nemici mentre CARICANO una mossa (dal suo inizio alla fine del telegraph).

    python arcanium/tools/playtest/misura_carica.py <cartella partita o scenario> [--telegraph 0.75]

Dalla telemetria: per ogni nemico, l'istante in cui `mossa` passa da "" a una
mossa, e la posizione fino a quel tempo + telegraph (in tick di gioco, 60/s).
Lo spostamento si proietta sulla direzione verso il player: positivo = verso
di lui. L'utente (2026-10-15): un lupo che carica il balzo deve stare fermo o
arretrare, non avanzare camminando.
"""
import argparse
import json
import math
from collections import defaultdict
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cartella")
    ap.add_argument("--telegraph", type=float, default=0.75)
    a = ap.parse_args()
    cart = Path(a.cartella)
    f = next(cart / n for n in ("telemetria.jsonl", "telemetria_replay.jsonl") if (cart / n).exists())
    righe = []
    for r in f.read_text(encoding="utf-8").splitlines():
        try:
            righe.append(json.loads(r))
        except json.JSONDecodeError:
            pass
    durata = int(a.telegraph * 60)
    inizio = {}          # id -> (tick, pos, mossa, pos_player)
    prec = {}
    esiti = defaultdict(list)
    for t in righe:
        pp = t["player"]["pos"]
        for n in t["nemici"]:
            k, m = n["id"], n.get("mossa", "")
            if m and not prec.get(k):
                inizio[k] = (t["tick"], n["pos"], m, pp, n["nome"])
            if k in inizio and m == inizio[k][2] and t["tick"] - inizio[k][0] <= durata:
                t0, p0, mossa, pp0, nome = inizio[k]
                verso = [pp0[0] - p0[0], pp0[2] - p0[2]]
                lv = math.hypot(*verso) or 1.0
                d = ((n["pos"][0] - p0[0]) * verso[0] + (n["pos"][2] - p0[2]) * verso[1]) / lv
                esiti[(nome.split("@")[0] or "rinforzo", mossa, t0)] = (d, t["tick"] - t0)
            prec[k] = m
    per_mossa = defaultdict(list)
    for (nome, mossa, t0), (d, dt) in sorted(esiti.items(), key=lambda x: x[0][2]):
        per_mossa[(nome, mossa)].append(d)
    for (nome, mossa), v in sorted(per_mossa.items()):
        print("%-14s %-5s cariche %2d | verso il player: max %+.2f m, media %+.2f m" % (
            nome, mossa, len(v), max(v), sum(v) / len(v)))


if __name__ == "__main__":
    main()
