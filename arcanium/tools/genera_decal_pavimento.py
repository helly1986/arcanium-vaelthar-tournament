#!/usr/bin/env python3
"""Le texture dei decal del pavimento dei mini-dungeon: crepe, sporco, muschio.

    python arcanium/tools/genera_decal_pavimento.py

Procedurali e con seme fisso: si rifanno identiche, e si ritoccano qui senza
pagare nulla. Escono in assets/environment/dungeon/decal/*.png (RGBA): il
colore e' quello della crepa o della macchia, l'alfa quanto copre.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets" / "environment" / "dungeon" / "decal"
LATO = 512


def crepa(seme):
    """Una crepa che si ramifica: polilinee a passo casuale, piu' sottili ai rami."""
    rng = random.Random(seme)
    img = Image.new("RGBA", (LATO, LATO), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def ramo(x, y, ang, lung, spess, livello):
        for _ in range(int(lung)):
            ang += rng.uniform(-0.22, 0.22)
            nx = x + math.cos(ang) * 6
            ny = y + math.sin(ang) * 6
            if not (8 < nx < LATO - 8 and 8 < ny < LATO - 8):
                return
            d.line([(x, y), (nx, ny)], fill=(10, 8, 7, 255), width=max(2, int(spess)))
            ## Il bordo appena piu' chiaro: la pietra scheggiata ai lati.
            d.line([(x + 2, y + 2), (nx + 2, ny + 2)], fill=(170, 160, 145, 90), width=2)
            x, y = nx, ny
            spess *= 0.985
            if livello < 3 and rng.random() < 0.06:
                ramo(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.2), lung * 0.45, spess * 0.6, livello + 1)

    cx, cy = LATO / 2, LATO / 2
    for k in range(rng.randint(2, 3)):
        ramo(cx, cy, rng.uniform(0, math.tau), rng.uniform(30, 45), rng.uniform(9.0, 13.0), 0)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def macchia(seme, colore, forza):
    """Una macchia irregolare: rumore a piu' scale, sfumato verso i bordi."""
    rng = random.Random(seme)
    somma = None
    for scala, peso in [(8, 1.0), (24, 0.5), (64, 0.25)]:
        r = Image.new("L", (scala, scala))
        r.putdata([int(rng.random() * 255) for _ in range(scala * scala)])
        r = r.resize((LATO, LATO), Image.BICUBIC).point(lambda v, p=peso: v * p / 1.75)
        somma = r if somma is None else ImageChops.add(somma, r)
    ## Soglia e contrasto: restano chiazze, non una nebbia uniforme.
    chiazze = somma.point(lambda v: max(0, min(255, int((v / 255 - 0.40) * 3.5 * 255))))
    ## Bordo: il gradiente radiale di PIL e' 0 al centro e 255 fuori.
    bordo = ImageOps.invert(Image.radial_gradient("L").resize((LATO, LATO)))
    ## Al quadrato: si spegne ben prima del bordo del quadrato, che non si vede.
    bordo = ImageChops.multiply(bordo, bordo)
    alfa = ImageChops.multiply(chiazze, bordo).point(lambda v: int(v * forza))
    img = Image.new("RGBA", (LATO, LATO), colore + (0,))
    img.putalpha(alfa)
    return img.filter(ImageFilter.GaussianBlur(1.5))


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for i in range(3):
        crepa(11 + i).save(DEST / ("crepa_%d.png" % (i + 1)))
    for i in range(2):
        macchia(31 + i, (22, 17, 13), 1.0).save(DEST / ("sporco_%d.png" % (i + 1)))
    macchia(51, (38, 58, 22), 0.95).save(DEST / "muschio_1.png")
    print("DECAL:", ", ".join(sorted(p.name for p in DEST.glob("*.png"))))


if __name__ == "__main__":
    main()
