# -*- coding: utf-8 -*-
"""Bozza schematica della mappa di Vaelthar da dare in input a nano-banana-pro
(image-to-image). Non deve essere bella: deve essere INEQUIVOCABILE su dove
stanno le cose e come si chiamano. Lo stile lo mette il modello.

    python bozza_mappa.py it
    python bozza_mappa.py en

La mappa e' un asset LOCALIZZATO: i nomi propri (regioni, citta') restano
uguali in tutte le lingue, cambiano solo le diciture descrittive e i mari.
"""
import sys
from PIL import Image, ImageDraw, ImageFont

LANG = sys.argv[1] if len(sys.argv) > 1 else "it"

T = {
 "it": {"arc": "L'ARCIPELAGO SILENTE", "mare": "Mare degli Echi",
        "kal": "la foresta che ricorda  \u00b7  SYLVORN",
        "pyr": "la fabbrica che non dorme  \u00b7  VORRKAI",
        "dav": "AETHON", "ver": "le pianure grigie  \u00b7  necromanti",
        "val": "la capitale  \u00b7  KAELVAR", "hal": "il passo alto  \u00b7  DAWNKEEP",
        "kd": "AMARETH", "est": "LE TERRE ESTERNE", "senza": "IL MARE SENZA NOME",
        "tit": "IL REGNO DI VAELTHAR", "sub": "tracciato negli anni della Quarta Era"},
 "en": {"arc": "THE SILENT ARCHIPELAGO", "mare": "Sea of Echoes",
        "kal": "the forest that remembers  \u00b7  SYLVORN",
        "pyr": "the factory that never sleeps  \u00b7  VORRKAI",
        "dav": "AETHON", "ver": "the grey plains  \u00b7  necromancers",
        "val": "the capital  \u00b7  KAELVAR", "hal": "the high pass  \u00b7  DAWNKEEP",
        "kd": "AMARETH", "est": "THE OUTER LANDS", "senza": "THE NAMELESS SEA",
        "tit": "THE REALM OF VAELTHAR", "sub": "charted in the years of the Fourth Era"},
}[LANG]

W, H = 1024, 1365
BG = (232, 214, 178)      # pergamena
INK = (74, 52, 32)
SEA = (150, 176, 186)
GREEN = (90, 124, 74)
RED = (150, 70, 45)
GREY = (140, 138, 132)
SNOW = (232, 238, 242)
SAND = (206, 180, 122)


def font(sz, bold=False):
    for p in ("C:/Windows/Fonts/georgiab.ttf" if bold else "C:/Windows/Fonts/georgia.ttf",
              "C:/Windows/Fonts/timesbd.ttf" if bold else "C:/Windows/Fonts/times.ttf",
              "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"):
        try:
            return ImageFont.truetype(p, sz)
        except Exception:
            pass
    return ImageFont.load_default()


img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)
d.rectangle([0, 0, W, 300], fill=SEA)
d.rounded_rectangle([60, 250, 964, 1210], radius=70, fill=BG, outline=INK, width=6)


def testo(xy, s, sz=34, col=INK, bold=True):
    d.text(xy, s, font=font(sz, bold), fill=col, anchor="mm")


def albero(x, y, s=16):
    d.ellipse([x - s, y - s, x + s, y + s], fill=GREEN)
    d.rectangle([x - 3, y, x + 3, y + s + 8], fill=(90, 62, 38))


def vulcano(x, y, s=42):
    d.polygon([(x - s, y + s * 0.7), (x, y - s * 0.8), (x + s, y + s * 0.7)], fill=(120, 55, 40))
    d.polygon([(x - 11, y - s * 0.75), (x, y - s * 1.15), (x + 11, y - s * 0.75)], fill=(220, 110, 40))


def picco(x, y, s=42):
    d.polygon([(x - s, y + s * 0.7), (x, y - s * 0.9), (x + s, y + s * 0.7)], fill=(96, 106, 120))
    d.polygon([(x - 14, y - s * 0.35), (x, y - s * 0.9), (x + 14, y - s * 0.35)], fill=SNOW)


def citta(x, y, nome, dy=26):
    d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=(120, 40, 35))
    testo((x, y + dy), nome, 26, INK, False)


# ARCIPELAGO SILENTE (nord, in mare)
for cx, cy, r in [(300, 150, 42), (520, 120, 30), (700, 165, 48), (860, 135, 26)]:
    d.ellipse([cx - r, cy - r * 0.7, cx + r, cy + r * 0.7], fill=SAND, outline=INK, width=3)
testo((512, 60), T["arc"], 32, (60, 70, 78))
testo((512, 225), T["mare"], 30, (70, 86, 96), bold=False)

# KALVORN — nord-ovest, foresta
d.rounded_rectangle([120, 330, 470, 560], radius=40, fill=(196, 206, 168), outline=INK, width=3)
for x in range(160, 450, 62):
    for y in (390, 470):
        albero(x, y)
testo((295, 320), "KALVORN", 46, GREEN)
testo((295, 578), T["kal"], 24, INK, False)
citta(230, 500, "Varanthos")

# PYRRATH — nord-est, vulcanico
for x, y in [(620, 470), (700, 430), (790, 465), (860, 425)]:
    vulcano(x, y)
testo((740, 320), "PYRRATH", 46, RED)
testo((740, 578), T["pyr"], 24, INK, False)
citta(700, 520, "Mekhavar")

# DAVRATH — ovest
testo((240, 700), "DAVRATH", 40, (110, 90, 140))
testo((240, 742), T["dav"], 24, INK, False)
citta(240, 790, "Tahphir")

# VERATH — est, pianure grigie
d.rounded_rectangle([640, 640, 930, 800], radius=30, fill=(196, 194, 188), outline=INK, width=3)
testo((785, 690), "VERATH", 40, GREY)
testo((785, 732), T["ver"], 22, INK, False)
citta(860, 770, "Ashveil")

# VALDRIS — centro, capitale
d.ellipse([470, 660, 570, 760], fill=(40, 40, 52), outline=(190, 150, 60), width=6)
d.ellipse([500, 695, 540, 725], fill=(220, 190, 90))
testo((515, 625), "VALDRIS", 44, INK)
testo((515, 790), T["val"], 24, INK, False)

# HALRATH — sud-ovest, montagne innevate
for x, y in [(180, 990), (270, 950), (360, 985), (440, 945)]:
    picco(x, y)
testo((300, 870), "HALRATH", 46, (70, 90, 120))
testo((300, 1060), T["hal"], 24, INK, False)
citta(270, 1020, "Ironveil")

# KALATH-DUN — sud-est
d.ellipse([640, 900, 850, 1010], fill=(150, 172, 186), outline=INK, width=3)
testo((745, 870), "KALATH-DUN", 40, (170, 140, 60))
testo((745, 1040), T["kd"], 24, INK, False)

# KETH-SORATH — estremo sud-est
d.polygon([(880, 1150), (855, 1075), (905, 1075)], fill=(24, 24, 30))
d.ellipse([872, 1055, 890, 1073], fill=(226, 196, 96))
testo((880, 1178), "Keth-Sorath", 26, INK, False)

# strade dalla capitale
for x, y in [(295, 450), (740, 450), (240, 720), (785, 700), (300, 960), (745, 950)]:
    d.line([515, 710, x, y], fill=(150, 90, 70), width=3)

# margini. NB: l'etichetta del mare orientale sta DENTRO il campo, non sul bordo:
# nella prima passata usciva dall'immagine.
testo((110, 660), T["est"], 22, (120, 108, 90), bold=False)
testo((855, 300), T["senza"], 22, (120, 108, 90), bold=False)
testo((512, 1265), T["tit"], 52, (130, 50, 40))
testo((512, 1315), T["sub"], 26, INK, False)

# rosa dei venti, spostata in alto rispetto al cartiglio: prima la "N" ci finiva sopra.
d.ellipse([64, 1130, 154, 1220], outline=INK, width=4)
d.polygon([(109, 1135), (101, 1175), (117, 1175)], fill=(150, 60, 45))
testo((109, 1108), "N", 28)

img.save("bozza_vaelthar_%s.png" % LANG)
print("scritta bozza_vaelthar_%s.png" % LANG, img.size)
