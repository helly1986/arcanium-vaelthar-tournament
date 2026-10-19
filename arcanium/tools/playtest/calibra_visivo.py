"""Calibrazione del canale visivo sul set etichettato di uno scenario.

    python arcanium/tools/playtest/calibra_visivo.py <cartella scenario> [--viste gioco,lato,alto]

Per ogni immagine e ogni tipo di difetto fa UNA domanda stretta sì/no a un VLM
locale (Qwen3-VL-4B sulla NPU, FastFlowLM, localhost:52625), con l'immagine in
testa al messaggio. La lezione della fase 0: con "trova i difetti di rendering"
lo stesso modello aveva mancato un lupo tutto magenta 4 volte su 4 dicendo
"confidenza 1.0"; con "c'e' un oggetto magenta?" lo trovava. Quindi: domande
strette, e il numero di confidenza auto-dichiarato non si usa come probabilita'.

Le risposte grezze finiscono in visivo_giudizi.jsonl accanto allo scenario: cambiare
il modo di contare non richiede di rifare l'inferenza.

Clef-Flash (Ollama, stessa API di Jev, con immagini) era il candidato con le
probabilita' vere, ma sulla versione 0.40.0 di Ollama non si carica affatto
("pooling_type is [-1], but [0] was specified", 2026-10-07): resta da riprovare.
"""

import argparse
import base64
import io
import json
import re
import time
import urllib.request
from pathlib import Path

from PIL import Image

URL = "http://localhost:52625/v1/chat/completions"
MODELLO = "qwen3vl-it:4b"

# Una domanda per difetto. Il tipo del caso nell'etichetta dello scenario e'
# la chiave: "pulito" vuol dire NO a tutte.
DOMANDE = {
    "magenta": "Is any object in this image rendered in a flat, solid magenta or bright pink color, "
               "the color a game engine shows when a texture is missing?",
    "affondato": "Is any animal or character sunk into the ground, with its legs or lower body hidden below "
                 "the ground surface?",
    "in_groppa": "Is one animal standing on top of another animal's back?",
    "dentro_roccia": "Is any animal or character intersecting a rock, with part of its body inside the rock?",
    "z_fighting": "Is there a flat floating square or panel made of interleaved stripes or patches of two different "
                  "colors, as when two surfaces overlap in exactly the same place?",
    "t_pose": "Is a humanoid character standing in a T-pose, with both arms held straight out to the sides?",
}
PROMPT = "{domanda}\nAnswer with exactly one word: yes or no."


def jpeg_b64(p: Path, lato: int = 1280) -> str:
    im = Image.open(p).convert("RGB")
    im.thumbnail((lato, lato))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=92)
    return base64.b64encode(buf.getvalue()).decode()


def chiedi(img_b64: str, domanda: str) -> tuple[str, float, dict]:
    body = {"model": MODELLO, "temperature": 0, "max_tokens": 3,
            "messages": [{"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + img_b64}},
                {"type": "text", "text": PROMPT.format(domanda=domanda)}]}]}
    t0 = time.perf_counter()
    out = json.load(urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=600))
    return out["choices"][0]["message"]["content"].strip().lower(), time.perf_counter() - t0, out.get("usage", {})


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cartella")
    ap.add_argument("--viste", default="gioco,lato,alto")
    a = ap.parse_args()
    cart = Path(a.cartella)
    righe = []
    f_out = open(cart / "visivo_giudizi.jsonl", "w", encoding="utf-8")
    casi = sorted(d for d in (cart / "segnalazioni").iterdir() if d.name.startswith("scen_"))
    for d in casi:
        tipo_vero = re.sub(r"^scen_\d+_\d+_", "", d.name)
        for vista in a.viste.split(","):
            img = d / f"{vista}.png"
            if not img.exists():
                continue
            b = jpeg_b64(img)
            for tipo, domanda in DOMANDE.items():
                risposta, sec, uso = chiedi(b, domanda)
                r = {"caso": d.name, "vista": vista, "domanda": tipo, "vero": tipo == tipo_vero,
                     "risposta": risposta, "si": risposta.startswith("yes"), "secondi": round(sec, 2),
                     "token_cache": (uso.get("prompt_tokens_details") or {}).get("cached_tokens")}
                righe.append(r)
                f_out.write(json.dumps(r) + "\n")
                f_out.flush()
            print(f"{d.name:32s} {vista:5s} " + " ".join(
                f"{x['domanda'][:6]}={'S' if x['si'] else '-'}{'!' if x['si'] != x['vero'] else ' '}"
                for x in righe[-len(DOMANDE):]))
    riassunto(righe, cart)


def riassunto(righe, cart):
    out = {}
    for tipo in DOMANDE:
        xs = [r for r in righe if r["domanda"] == tipo]
        tp = sum(r["si"] and r["vero"] for r in xs)
        fp = sum(r["si"] and not r["vero"] for r in xs)
        fn = sum(not r["si"] and r["vero"] for r in xs)
        tn = sum(not r["si"] and not r["vero"] for r in xs)
        out[tipo] = {"TP": tp, "FP": fp, "FN": fn, "TN": tn,
                     "precisione": round(tp / max(1, tp + fp), 2), "richiamo": round(tp / max(1, tp + fn), 2)}
    tot = {k: sum(v[k] for v in out.values()) for k in ("TP", "FP", "FN", "TN")}
    secs = [r["secondi"] for r in righe]
    print(json.dumps(out, indent=1))
    print("totale:", tot, "| secondi per domanda: mediana %.1f, max %.1f" % (sorted(secs)[len(secs) // 2], max(secs)))
    (cart / "visivo_riassunto.json").write_text(json.dumps({"per_tipo": out, "totale": tot}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
