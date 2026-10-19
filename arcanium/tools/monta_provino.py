# -*- coding: utf-8 -*-
"""Monta dei PNG in un PROVINO A CONTATTO, con l'etichetta scritta su ogni
riquadro. Senza il numero sopra, un provino non e' operativo: non si puo' dire
"il contatto e' al 63".

Uso:  python monta.py <uscita.png> <colonne> <file1> <etichetta1> ...
"""
import shutil, subprocess, sys, os

## ffmpeg ha gia' cambiato posto una volta: il percorso non si scrive piu' in
## un punto solo. Si prova l'installazione nota, poi il PATH; se non c'e',
## `_con_pillow` fa lo stesso lavoro senza dipendenze.
CANDIDATI_FFMPEG = [
    "C:/Software Utili/ffmpeg/ffmpeg-master-latest-win64-gpl/bin/ffmpeg.exe",
    # storico, prima del 2026-08-20
    "C:/Software Utili/ffmpeg-master-latest-win64-gpl-shared/"
    "ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe",
]


def _trova_ffmpeg():
    for p in CANDIDATI_FFMPEG:
        if os.path.exists(p):
            return p
    return shutil.which("ffmpeg") or ""


FFMPEG = _trova_ffmpeg()
FONT = "C\\:/Windows/Fonts/arialbd.ttf"

uscita, colonne = sys.argv[1], int(sys.argv[2])
coppie = list(zip(sys.argv[3::2], sys.argv[4::2]))


def _con_pillow(uscita, colonne, coppie, larghezza=520):
    """Ripiego quando ffmpeg non c'e'. Fa la stessa cosa, senza dipendenze
    esterne: sul PC nuovo `C:\\Software Utili` non esiste piu' e il provino
    e' proprio lo strumento che non deve mancare quando serve guardare."""
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 34)
    except OSError:
        font = ImageFont.load_default()

    riquadri = []
    for percorso, etichetta in coppie:
        im = Image.open(percorso).convert("RGB")
        if im.width != larghezza:
            im = im.resize((larghezza, round(im.height * larghezza / im.width)))
        d = ImageDraw.Draw(im)
        x0, y0, x1, y1 = d.textbbox((12, 10), etichetta, font=font)
        d.rectangle((x0 - 8, y0 - 8, x1 + 8, y1 + 8), fill=(0, 0, 0))
        d.text((12, 10), etichetta, font=font, fill=(255, 255, 255))
        riquadri.append(im)

    w = max(i.width for i in riquadri)
    h = max(i.height for i in riquadri)
    righe = (len(riquadri) + colonne - 1) // colonne
    foglio = Image.new("RGB", (w * min(colonne, len(riquadri)), h * righe), (20, 20, 24))
    for i, im in enumerate(riquadri):
        foglio.paste(im, ((i % colonne) * w, (i // colonne) * h))
    foglio.save(uscita)


if not os.path.exists(FFMPEG):
    _con_pillow(uscita, colonne, coppie)
    print("montato (Pillow):", uscita, os.path.getsize(uscita), "byte")
    raise SystemExit(0)

## drawtext interpreta ':' come separatore di opzioni: un'etichetta che lo
## contiene fa fallire ffmpeg con un errore illeggibile.
coppie = [(f, e.replace(":", "\\:")) for f, e in coppie]

cmd = [FFMPEG, "-y"]
for f, _ in coppie:
    cmd += ["-i", f]

filtri = []
for i, (_, etichetta) in enumerate(coppie):
    filtri.append(
        "[%d:v]scale=520:-1,drawtext=fontfile='%s':text='%s':x=12:y=10:"
        "fontsize=34:fontcolor=white:box=1:boxcolor=black@0.65:boxborderw=8[v%d]"
        % (i, FONT, etichetta, i))

righe = []
n = len(coppie)
r = 0
while r * colonne < n:
    fetta = list(range(r * colonne, min(n, (r + 1) * colonne)))
    ## ⚠️ `vstack` pretende righe della STESSA larghezza: se l'ultima riga e'
    ## corta (13 riquadri su 7 colonne) ffmpeg esce con un errore illeggibile.
    ## Si tappa la riga corta fino alla larghezza piena.
    coda = (",pad=%d:ih:0:0:color=0x141418" % (colonne * 520)) \
        if len(fetta) < colonne else ""
    ingressi = "".join("[v%d]" % i for i in fetta)
    if len(fetta) == 1:
        filtri.append("%snull%s[r%d]" % (ingressi, coda, r))
    else:
        filtri.append("%shstack=inputs=%d%s[r%d]" % (
            ingressi, len(fetta), coda, r))
    righe.append(r)
    r += 1
if len(righe) == 1:
    filtri.append("[r0]null[out]")
else:
    filtri.append("%svstack=inputs=%d[out]" % (
        "".join("[r%d]" % i for i in righe), len(righe)))

cmd += ["-filter_complex", ";".join(filtri), "-map", "[out]", "-frames:v", "1", uscita]
try:
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
except OSError as e:
    ## ffmpeg c'e' ma Windows non lo lascia partire (criterio di controllo
    ## delle applicazioni, WinError 4551, 2026-09-14): esiste sul disco e
    ## `os.path.exists` dice si', quindi il ripiego di sopra non scatta.
    print("ffmpeg bloccato (%s): ripiego su Pillow" % e)
    _con_pillow(uscita, colonne, [(f, e.replace("\:", ":")) for f, e in coppie])
    print("montato (Pillow):", uscita, os.path.getsize(uscita), "byte")
print("montato:", uscita, os.path.getsize(uscita), "byte")
