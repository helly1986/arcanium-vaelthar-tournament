#!/usr/bin/env python3
"""Cornici della UI nuova (design-ui-nuova) con Flux Pro 1.1 su fal.ai, poi
scontornate con BiRefNet.

    python arcanium/tools/cornici_fal.py <cartella> [pezzo ...]

Per ogni pezzo quattro varianti (semi fissi, quindi ripetibili). In
<cartella> escono, per ognuna, il grezzo su nero (`<pezzo>_<seme>.png`) e lo
scontornato con l'alfa (`<pezzo>_<seme>_alfa.png`). La cartella sta FUORI dal
repo: si sceglie, e solo i pezzi scelti, tagliati in 9-slice, entrano in
assets/ui/.

Prezzo verificato il 2026-10-21 sulla pagina di fal: Flux Pro 1.1 costa
0,04 $ al megapixel, arrotondato per eccesso. Per questo il formato quadrato
e' 1024x960 (0,98 MP, un megapixel) e non 1024x1024 (1,05 MP, due).

I prompt li ha approvati l'utente il 2026-10-21: non si cambiano senza
chiedere. Il medaglione e' alla seconda versione, approvata lo stesso giorno:
con "engraved runes" Flux incideva lettere latine finte. La chiave FAL_KEY e' una variabile di SISTEMA: vedi
patina_pavimenti.py.
"""
import json
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from patina_pavimenti import chiave, chiama  # noqa: E402

FLUX = "https://queue.fal.run/fal-ai/flux-pro/v1.1"
BIREFNET = "https://queue.fal.run/fal-ai/birefnet/v2"
SEMI = [11, 23, 37, 41]

PEZZI = {
    "barra": ((1024, 256),
        "Game UI asset: a long thin horizontal frame for a health bar, burnished dark iron "
        "with worn bronze edges, small engraved runes only at the two rounded end caps, the "
        "long top and bottom edges plain and straight so they can be stretched, empty hollow "
        "center, symmetric, front orthographic view, soft even lighting, dark fantasy, "
        "hand-painted texture, isolated on a flat pure black background, no text, no gems, "
        "no scenery"),
    "medaglione": ((1024, 960),
        "Game UI asset: a round medallion frame, burnished dark iron ring with aged gold "
        "filigree and a band of abstract geometric engravings, no letters, no runes, no "
        "inscriptions, no writing, four small studs at the cardinal points, "
        "empty hollow center for an emblem, symmetric, front orthographic view, soft even "
        "lighting, dark fantasy, hand-painted texture, isolated on a flat pure black "
        "background, no text, no emblem inside"),
    "pannello": ((1024, 960),
        "Game UI asset: a rectangular panel border, thin burnished dark iron frame with "
        "ornate engraved corner pieces in aged gold, plain straight edges between the "
        "corners so they can be stretched, empty center, symmetric, front orthographic view, "
        "soft even lighting, dark fantasy, hand-painted texture, isolated on a flat pure "
        "black background, no text"),
    "pulsante": ((1024, 256),
        "Game UI asset: a horizontal button frame, dark iron plate with a thin aged gold rim "
        "and small runic notches at both ends, plain straight middle so it can be stretched, "
        "slightly recessed dark center, symmetric, front orthographic view, soft even "
        "lighting, dark fantasy, hand-painted texture, isolated on a flat pure black "
        "background, no text"),
}


def in_coda(endpoint, corpo, k, nome):
    d = chiama(endpoint, k, corpo)
    for _ in range(200):
        time.sleep(2)
        s = chiama(d["status_url"], k)
        if s.get("status") == "COMPLETED":
            return chiama(d["response_url"], k)
        if s.get("status") in ("FAILED", "CANCELLED"):
            raise RuntimeError("%s: %s" % (nome, s))
    raise RuntimeError("%s: tempo scaduto" % nome)


def genera(pezzo, seme, dest, k):
    (w, h), prompt = PEZZI[pezzo]
    nome = "%s_%d" % (pezzo, seme)
    out = in_coda(FLUX, {
        "prompt": prompt,
        "image_size": {"width": w, "height": h},
        "seed": seme,
        "num_images": 1,
        "output_format": "png",
        "safety_tolerance": "2",
    }, k, nome)
    url = out["images"][0]["url"]
    urllib.request.urlretrieve(url, dest / (nome + ".png"))
    alfa = in_coda(BIREFNET, {
        "image_url": url,
        "model": "General Use (Heavy)",
        "operating_resolution": "2048x2048",
        "output_format": "png",
        "refine_foreground": True,
    }, k, nome + " alfa")
    urllib.request.urlretrieve(alfa["image"]["url"], dest / (nome + "_alfa.png"))
    print("CORNICI: %s ok" % nome, flush=True)


def main():
    try:
        import truststore
        truststore.inject_into_ssl()
    except ImportError:
        pass
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    dest = Path(sys.argv[1])
    dest.mkdir(parents=True, exist_ok=True)
    k = chiave()
    pezzi = sys.argv[2:] or list(PEZZI)
    for p in pezzi:
        for s in SEMI:
            genera(p, s, dest, k)


if __name__ == "__main__":
    main()
