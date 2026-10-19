"""Ricampiona i sampler CUBICSPLINE di un GLB in chiavi per-frame LINEAR.

Perche' serve: l'importer GLB di Cascadeur non sa leggere CUBICSPLINE e si ferma
con "unexpected times & values count: N vs 3N". Blender esporta CUBICSPLINE ogni
volta che le curve hanno le tangenti (cioe' quasi sempre, se non si spunta
"Always Sample Animations").

Non appiattisce la curva: valuta la spline di Hermite a ogni frame, cosi' il
movimento che arriva in Cascadeur e' quello autorato, non una spezzata fra le
chiavi.

    python tools/glb_cubicspline_to_linear.py ingresso.glb uscita.glb [--fps 30]
"""
import json
import struct
import sys

TIPI = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FLOAT = 5126


def _leggi_glb(percorso):
    with open(percorso, "rb") as f:
        dati = f.read()
    if dati[:4] != b"glTF":
        raise SystemExit(f"{percorso}: non e' un GLB")
    off, js, binario = 12, None, b""
    while off < len(dati):
        lung, tipo = struct.unpack_from("<II", dati, off)
        off += 8
        pezzo = dati[off:off + lung]
        if tipo == 0x4E4F534A:
            js = json.loads(pezzo.decode("utf-8"))
        elif tipo == 0x004E4942:
            binario = pezzo
        off += lung
    return js, bytearray(binario)


def _accessor(js, binario, idx):
    acc = js["accessors"][idx]
    if acc.get("componentType") != FLOAT:
        raise SystemExit(f"accessor {idx}: atteso float, trovato {acc.get('componentType')}")
    n = TIPI[acc["type"]]
    bv = js["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    passo = bv.get("byteStride") or n * 4
    fuori = []
    for i in range(acc["count"]):
        p = base + i * passo
        fuori.append(list(struct.unpack_from("<" + "f" * n, binario, p)))
    return fuori, n


def _aggiungi_accessor(js, binario, valori, n, minmax=False):
    while len(binario) % 4:
        binario.append(0)
    off = len(binario)
    for v in valori:
        binario += struct.pack("<" + "f" * n, *v)
    js["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(binario) - off})
    acc = {
        "bufferView": len(js["bufferViews"]) - 1,
        "componentType": FLOAT,
        "count": len(valori),
        "type": [k for k, v in TIPI.items() if v == n][0],
    }
    if minmax:
        acc["min"] = [min(v[i] for v in valori) for i in range(n)]
        acc["max"] = [max(v[i] for v in valori) for i in range(n)]
    js["accessors"].append(acc)
    return len(js["accessors"]) - 1


def _hermite(v0, b0, v1, a1, delta, t):
    t2, t3 = t * t, t * t * t
    h00 = 2 * t3 - 3 * t2 + 1
    h10 = t3 - 2 * t2 + t
    h01 = -2 * t3 + 3 * t2
    h11 = t3 - t2
    return [h00 * v0[i] + h10 * delta * b0[i] + h01 * v1[i] + h11 * delta * a1[i]
            for i in range(len(v0))]


def _normalizza(q):
    n = sum(c * c for c in q) ** 0.5
    return [c / n for c in q] if n else q


def converti(ingresso, uscita, fps=30.0):
    js, binario = _leggi_glb(ingresso)
    if len(js.get("buffers", [])) != 1:
        raise SystemExit("atteso un solo buffer (GLB standard)")
    convertiti = 0
    for anim in js.get("animations", []):
        rotazioni = {c["sampler"] for c in anim["channels"]
                     if c["target"]["path"] == "rotation"}
        for si, s in enumerate(anim["samplers"]):
            if s.get("interpolation") != "CUBICSPLINE":
                continue
            tempi, _ = _accessor(js, binario, s["input"])
            triple, n = _accessor(js, binario, s["output"])
            tempi = [t[0] for t in tempi]
            if len(triple) != 3 * len(tempi):
                raise SystemExit(f"sampler {si}: {len(tempi)} tempi, {len(triple)} valori")
            chiavi = [(triple[3 * i], triple[3 * i + 1], triple[3 * i + 2])
                      for i in range(len(tempi))]

            passo = 1.0 / fps
            nuovi_t, nuovi_v = [], []
            k = 0
            t = tempi[0]
            # un campione per frame, piu' l'ultimo tempo esatto
            while t < tempi[-1] - 1e-9:
                while k + 1 < len(tempi) and tempi[k + 1] <= t:
                    k += 1
                delta = tempi[k + 1] - tempi[k]
                u = (t - tempi[k]) / delta if delta else 0.0
                v = _hermite(chiavi[k][1], chiavi[k][2], chiavi[k + 1][1], chiavi[k + 1][0], delta, u)
                nuovi_t.append([t])
                nuovi_v.append(_normalizza(v) if si in rotazioni else v)
                t += passo
            nuovi_t.append([tempi[-1]])
            ultimo = list(chiavi[-1][1])
            nuovi_v.append(_normalizza(ultimo) if si in rotazioni else ultimo)

            s["input"] = _aggiungi_accessor(js, binario, nuovi_t, 1, minmax=True)
            s["output"] = _aggiungi_accessor(js, binario, nuovi_v, n)
            s["interpolation"] = "LINEAR"
            convertiti += 1

    js["buffers"][0]["byteLength"] = len(binario)
    testo = json.dumps(js, separators=(",", ":")).encode("utf-8")
    testo += b" " * ((4 - len(testo) % 4) % 4)
    while len(binario) % 4:
        binario.append(0)
    totale = 12 + 8 + len(testo) + 8 + len(binario)
    with open(uscita, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, totale))
        f.write(struct.pack("<II", len(testo), 0x4E4F534A) + testo)
        f.write(struct.pack("<II", len(binario), 0x004E4942) + bytes(binario))
    print(f"{convertiti} sampler convertiti -> {uscita}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    fps = 30.0
    if "--fps" in sys.argv:
        fps = float(sys.argv[sys.argv.index("--fps") + 1])
    if len(args) != 2:
        raise SystemExit(__doc__)
    converti(args[0], args[1], fps)
