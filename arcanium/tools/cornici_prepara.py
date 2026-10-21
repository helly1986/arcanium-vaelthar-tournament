#!/usr/bin/env python3
"""Dalla variante scelta (cornici_fal.py) al pezzo della UI.

    python arcanium/tools/cornici_prepara.py <alfa.png> <nome> <larghezza>

Rifila i bordi trasparenti, riduce alla larghezza voluta (la UI a 1080p non
vuole un 1024 per una barra larga 300: pesa e sgrana in riduzione al volo),
toglie l'alone scuro rimasto dallo sfondo nero (pixel quasi trasparenti) e
salva in assets/ui/cornici/<nome>.png. Stampa la misura, che serve per i
margini del 9-slice.
"""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets" / "ui" / "cornici"


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    src, nome, larghezza = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
    im = Image.open(src).convert("RGBA")
    ## L'alone: BiRefNet lascia pixel con alfa bassa e colore quasi nero dove
    ## c'era lo sfondo. Sotto 24 su 255 si azzerano.
    a = im.getchannel("A").point(lambda v: 0 if v < 24 else v)
    im.putalpha(a)
    box = a.getbbox()
    if box is None:
        sys.exit("immagine vuota")
    im = im.crop(box)
    h = round(im.height * larghezza / im.width)
    im = im.resize((larghezza, h), Image.LANCZOS)
    DEST.mkdir(parents=True, exist_ok=True)
    out = DEST / (nome + ".png")
    im.save(out, optimize=True)
    print("CORNICE: %s %dx%d (%d KB)" % (out.relative_to(ROOT), im.width, im.height, out.stat().st_size // 1024))


if __name__ == "__main__":
    main()
