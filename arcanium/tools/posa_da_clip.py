# -*- coding: utf-8 -*-
"""Estrae UNA posa da un istante di una clip GLB, e la scrive in JSON.

    python arcanium/tools/posa_da_clip.py <clip.glb> <secondi> <uscita.json>

═══════════════════════════════════════════════════════════════════════════
PERCHE' SI LEGGE IL GLB E NON SI CHIEDE A GODOT
═══════════════════════════════════════════════════════════════════════════

Perche' i nomi delle ossa sono DIVERSI dalle due parti. In gioco lo scheletro
usa la convenzione Nephilite-Godot (`Spine`, `Chest`, `LeftUpperArm`), che
nasce dalla `retarget/bone_map` applicata durante l'importazione; il GLB della
clip — e ogni cosa che passa da Cascadeur — usa quella del pack (`Spine_01`,
`Spine_03`, `Shoulder_L`).

Leggere la clip alla sorgente salta il problema invece di risolverlo: la posa
esce gia' scritta nella lingua di Cascadeur, e non c'e' nessuna tabella di
traduzione da tenere aggiornata.

⚠️ Si estraggono le ROTAZIONI LOCALI, piu' la traslazione delle sole ossa che
ce l'hanno animata. Interpolare o trasportare posizioni globali di una gerarchia
stira le ossa: la posa di uno scheletro sono le rotazioni locali, punto.

⚠️ L'interpolazione dichiarata dal sampler viene rispettata. `STEP` tiene il
valore della chiave precedente, `LINEAR` interpola (slerp per le rotazioni),
`CUBICSPLINE` valuta la spline di Hermite — che e' come il glTF esporta quando
le curve hanno le tangenti, cioe' quasi sempre. Campionare "alla chiave piu'
vicina" darebbe una posa che nel gioco non si vede in nessun fotogramma.
"""

import json
import struct
import sys


def _leggi_glb(percorso):
    with open(percorso, "rb") as f:
        magic, _ver, _tot = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise SystemExit("%s non e' un GLB" % percorso)
        testa = None
        binario = b""
        while True:
            intestazione = f.read(8)
            if len(intestazione) < 8:
                break
            lung, tipo = struct.unpack("<II", intestazione)
            dati = f.read(lung)
            if tipo == 0x4E4F534A:
                testa = json.loads(dati.decode("utf-8"))
            elif tipo == 0x004E4942:
                binario = dati
    if testa is None:
        raise SystemExit("nessun blocco JSON in %s" % percorso)
    return testa, binario


_TIPI = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
         5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
_QUANTI = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _accessor(g, bin_, indice):
    a = g["accessors"][indice]
    fmt, dim = _TIPI[a["componentType"]]
    n = _QUANTI[a["type"]]
    bv = g["bufferViews"][a["bufferView"]]
    inizio = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    passo = bv.get("byteStride") or dim * n
    fuori = []
    for i in range(a["count"]):
        off = inizio + i * passo
        v = struct.unpack_from("<" + fmt * n, bin_, off)
        fuori.append(list(v))
    return fuori


def _slerp(a, b, t):
    d = sum(x * y for x, y in zip(a, b))
    if d < 0.0:
        b = [-x for x in b]
        d = -d
    if d > 0.9995:
        v = [x + (y - x) * t for x, y in zip(a, b)]
    else:
        import math
        th0 = math.acos(max(-1.0, min(1.0, d)))
        th = th0 * t
        s0 = math.sin(th0)
        v = [(math.sin(th0 - th) / s0) * x + (math.sin(th) / s0) * y
             for x, y in zip(a, b)]
    n = sum(x * x for x in v) ** 0.5
    return [x / n for x in v] if n > 0 else [0.0, 0.0, 0.0, 1.0]


def _hermite(p0, m0, p1, m1, t):
    t2 = t * t
    t3 = t2 * t
    return [(2 * t3 - 3 * t2 + 1) * a + (t3 - 2 * t2 + t) * b
            + (-2 * t3 + 3 * t2) * c + (t3 - t2) * d
            for a, b, c, d in zip(p0, m0, p1, m1)]


def campiona(g, bin_, sampler, istante, rotazione):
    tempi = [x[0] for x in _accessor(g, bin_, sampler["input"])]
    valori = _accessor(g, bin_, sampler["output"])
    interp = sampler.get("interpolation", "LINEAR")
    if not tempi:
        return None
    istante = max(tempi[0], min(tempi[-1], istante))
    i = 0
    while i + 1 < len(tempi) and tempi[i + 1] < istante:
        i += 1
    j = min(i + 1, len(tempi) - 1)
    dt = tempi[j] - tempi[i]
    u = 0.0 if dt <= 0.0 else (istante - tempi[i]) / dt

    if interp == "CUBICSPLINE":
        # terne (tangente entrante, valore, tangente uscente)
        p0, m0 = valori[3 * i + 1], [x * dt for x in valori[3 * i + 2]]
        p1, m1 = valori[3 * j + 1], [x * dt for x in valori[3 * j]]
        v = _hermite(p0, m0, p1, m1, u)
        if rotazione:
            n = sum(x * x for x in v) ** 0.5
            v = [x / n for x in v] if n > 0 else [0.0, 0.0, 0.0, 1.0]
        return v
    if interp == "STEP":
        return valori[i]
    if rotazione:
        return _slerp(valori[i], valori[j], u)
    return [a + (b - a) * u for a, b in zip(valori[i], valori[j])]


def estrai(percorso, istante):
    g, bin_ = _leggi_glb(percorso)
    nodi = g.get("nodes", [])
    anims = g.get("animations", [])
    if not anims:
        raise SystemExit("%s non contiene animazioni" % percorso)
    a = anims[0]
    posa = {}
    for ch in a["channels"]:
        b = ch["target"]
        nodo = b.get("node")
        via = b.get("path")
        if nodo is None or via not in ("rotation", "translation"):
            continue
        v = campiona(g, bin_, a["samplers"][ch["sampler"]], istante,
                     via == "rotation")
        if v is None:
            continue
        posa.setdefault(nodi[nodo].get("name", "nodo_%d" % nodo), {})[via] = v
    durata = 0.0
    for s in a["samplers"]:
        t = [x[0] for x in _accessor(g, bin_, s["input"])]
        if t:
            durata = max(durata, t[-1])
    return {"clip": percorso, "istante": istante, "durata": durata,
            "ossa": posa}


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    esito = estrai(sys.argv[1], float(sys.argv[2]))
    with open(sys.argv[3], "w", encoding="utf-8") as f:
        json.dump(esito, f, indent=1)
    rot = sum(1 for v in esito["ossa"].values() if "rotation" in v)
    tra = sum(1 for v in esito["ossa"].values() if "translation" in v)
    print("clip lunga %.3f s, posa a %.3f s" % (esito["durata"], esito["istante"]))
    print("%d ossa: %d rotazioni, %d traslazioni -> %s"
          % (len(esito["ossa"]), rot, tra, sys.argv[3]))
