#!/usr/bin/env python3
"""Pavimenti dei mini-dungeon con Patina su fal.ai (`fal-ai/patina/material`).

    python arcanium/tools/patina_pavimenti.py [nome ...]

Patina genera una texture che si ripete davvero sui bordi e ne stima le mappe
PBR. Si tengono colore, normale e ruvidita': le uniche che il materiale del
pavimento usa. Escono in assets/environment/dungeon/pavimenti/<nome>_*.jpg
(la normale in .png).

La chiave e' FAL_KEY. L'utente l'ha registrata come variabile di SISTEMA: un
processo nato prima non la eredita, quindi se manca nell'ambiente si legge dal
registro. Non si stampa mai.
"""

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets" / "environment" / "dungeon" / "pavimenti"
ENDPOINT = "https://queue.fal.run/fal-ai/patina/material"
MAPPE = ["basecolor", "normal", "roughness"]

## Stile comune: interni di un dungeon, visti dall'alto da una camera
## isometrica a una decina di metri. Lastre e assi devono leggersi a quella
## distanza: pochi elementi grandi per texture, non un mosaico fitto.
STILE = ("seamless tileable PBR floor material for a dark fantasy dungeon, top-down, "
         "large readable elements, worn and dusty, ")

MATERIALI = {
    "legno_assi": "old dark oak floor planks, long straight boards, worn and scratched, iron nails, dark gaps",
    "mattoni_spina": "dark reddish-brown clay bricks laid in a herringbone pattern, grey mortar, chipped edges",
    "marmo_oro": "large square polished black marble tiles with gold veins, thin inlaid brass strips between tiles",
    "basalto_rune": "large irregular dark basalt flagstones with faint carved runes, thin deep cracks between slabs",
    "lastricato": "large worn square pale limestone flagstones of an ancient hall, thin dark joints, slight moss in cracks",
    "ciottoli_scuri": "dark grey rounded cobblestones of an underground passage, packed dirt between stones",
    "terra_paglia": "flat packed dark brown earth floor of a dungeon cell, loose golden straw strands scattered evenly, tiny pebbles, uniform, no holes, no round shapes",
}


def chiave():
    k = os.environ.get("FAL_KEY", "")
    if k:
        return k
    try:
        import winreg
        for radice, percorso in [
                (winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"),
                (winreg.HKEY_CURRENT_USER, r"Environment")]:
            try:
                with winreg.OpenKey(radice, percorso) as h:
                    return winreg.QueryValueEx(h, "FAL_KEY")[0]
            except OSError:
                pass
    except ImportError:
        pass
    sys.exit("FAL_KEY non trovata")


def chiama(url, k, corpo=None):
    req = urllib.request.Request(
        url, data=json.dumps(corpo).encode() if corpo is not None else None,
        headers={"Authorization": "Key " + k, "Content-Type": "application/json"},
        method="POST" if corpo is not None else "GET")
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)


def genera(nome, testo, k):
    corpo = {
        "prompt": STILE + testo,
        "image_size": "square_hd",
        "tiling_mode": "both",
        "maps": MAPPE,
        "enable_prompt_expansion": False,
        "output_format": "png",
        "seed": 1009,
    }
    d = chiama(ENDPOINT, k, corpo)
    stato, risposta = d["status_url"], d["response_url"]
    for _ in range(120):
        time.sleep(3)
        s = chiama(stato, k)
        if s.get("status") == "COMPLETED":
            break
        if s.get("status") in ("FAILED", "CANCELLED"):
            raise RuntimeError("%s: %s" % (nome, s))
    out = chiama(risposta, k)
    trovate = {}
    for im in out["images"]:
        tipo = im.get("map_type")
        if tipo in MAPPE:
            dest = DEST / ("%s_%s.png" % (nome, tipo))
            urllib.request.urlretrieve(im["url"], dest)
            ## Colore e ruvidita' in JPEG (2 MB -> 400 KB l'una nel repo); la
            ## normale resta PNG, che il JPEG la sporca.
            if tipo != "normal":
                from PIL import Image
                jpg = dest.with_suffix(".jpg")
                im_ = Image.open(dest)
                (im_.convert("L") if tipo == "roughness" else im_.convert("RGB")).save(jpg, quality=90)
                dest.unlink()
                dest = jpg
            trovate[tipo] = dest
    mancano = [m for m in MAPPE if m not in trovate]
    if mancano:
        raise RuntimeError("%s: mancano %s" % (nome, mancano))
    print("PATINA: %s ok (%s)" % (nome, ", ".join(p.name for p in trovate.values())))


def main():
    ## Il Python di questo PC non trova i certificati da solo
    ## (CERTIFICATE_VERIFY_FAILED): si usano quelli di Windows.
    try:
        import truststore
        truststore.inject_into_ssl()
    except ImportError:
        pass
    DEST.mkdir(parents=True, exist_ok=True)
    k = chiave()
    nomi = sys.argv[1:] or list(MATERIALI)
    for n in nomi:
        genera(n, MATERIALI[n], k)


if __name__ == "__main__":
    main()
