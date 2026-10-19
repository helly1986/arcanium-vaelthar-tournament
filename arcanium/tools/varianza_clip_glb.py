# -*- coding: utf-8 -*-
"""Misura quanto si MUOVE davvero ogni osso, dentro ogni clip di un GLB.

⚠️ La ragione per cui questo file esiste. Controllare che i canali di
animazione esistano NON dice niente: un canale con cento chiavi tutte uguali e'
una posa statica, e passa qualunque verifica strutturale. Sono state consegnate
nove clip "verificate" che erano pose ferme. Da qui in avanti il collaudo di una
clip animata e' la VARIANZA dei valori, osso per osso.

Non serve ne' Blender ne' Godot: legge il GLB da solo.

    python arcanium/tools/varianza_clip_glb.py <file.glb>
    python arcanium/tools/varianza_clip_glb.py <file.glb> --clip walk --dettaglio
    python arcanium/tools/varianza_clip_glb.py <file.glb> --soglia 0.02

Uscita: per ogni clip, quante ossa si muovono davvero e quali. Codice di uscita
1 se una clip risulta STATICA, cosi' si puo' mettere in mezzo a una pipeline.

## Come si legge il numero

Per rotazioni e traslazioni si riporta l'AMPIEZZA (max - min) del canale, presa
sulla componente che si muove di piu':
  - rotazione: in gradi, come angolo massimo fra due quaternioni della sequenza;
  - traslazione e scala: nelle unita' del file (metri per la traslazione).

Un osso conta come "mosso" se supera `--soglia` (default: 1 grado di rotazione,
oppure 1 mm di traslazione). Sotto quella soglia e' rumore di campionamento.
"""
import sys, json, struct, math, argparse

# ⚠️ La console Windows parte in cp1252 e i gradi (°) bastano a far crollare lo
# script sull'ULTIMA riga, dopo aver stampato tutto il resto: il risultato
# sembra completo ed e' un errore.
for flusso in (sys.stdout, sys.stderr):
    if hasattr(flusso, "reconfigure"):
        flusso.reconfigure(encoding="utf-8", errors="replace")

# glTF: componentType -> (formato struct, byte)
COMPONENTI = {
    5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
    5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4),
}
CONTEGGIO = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4,
             "MAT2": 4, "MAT3": 9, "MAT4": 16}


def leggi_glb(percorso):
    """Restituisce (json, bytes del chunk binario)."""
    with open(percorso, "rb") as f:
        dati = f.read()
    magia, versione, _lunghezza = struct.unpack_from("<III", dati, 0)
    if magia != 0x46546C67:
        raise ValueError("non e' un GLB (magic sbagliato): %s" % percorso)
    off = 12
    js, binario = None, b""
    while off < len(dati):
        clen, ctipo = struct.unpack_from("<II", dati, off)
        corpo = dati[off + 8: off + 8 + clen]
        if ctipo == 0x4E4F534A:      # JSON
            js = json.loads(corpo.decode("utf-8"))
        elif ctipo == 0x004E4942:    # BIN
            binario = corpo
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    if js is None:
        raise ValueError("GLB senza chunk JSON: %s" % percorso)
    return js, binario


def leggi_accessor(js, binario, indice):
    """Un accessor glTF come lista di tuple. Gestisce anche il byteStride."""
    acc = js["accessors"][indice]
    n = acc["count"]
    larghezza = CONTEGGIO[acc["type"]]
    fmt, dim = COMPONENTI[acc["componentType"]]

    if "bufferView" not in acc:
        return [tuple([0.0] * larghezza)] * n     # accessor tutto a zero

    bv = js["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    passo = bv.get("byteStride") or (dim * larghezza)

    fuori = []
    for i in range(n):
        o = base + i * passo
        fuori.append(struct.unpack_from("<" + fmt * larghezza, binario, o))
    return fuori


def angolo_fra_quaternioni(a, b):
    """Angolo in gradi fra due rotazioni (x, y, z, w). Segno-insensibile: q e
    -q sono la STESSA rotazione, e senza il valore assoluto un cambio di segno
    a meta' curva verrebbe letto come una rotazione di 360 gradi."""
    p = sum(x * y for x, y in zip(a, b))
    p = min(1.0, max(-1.0, abs(p)))
    return math.degrees(2.0 * math.acos(p))


def ampiezza_rotazione(valori):
    """Angolo massimo fra la prima rotazione e ognuna delle altre."""
    if len(valori) < 2:
        return 0.0
    return max(angolo_fra_quaternioni(valori[0], v) for v in valori[1:])


def ampiezza_vettore(valori):
    """max - min sulla componente piu' mobile."""
    if len(valori) < 2:
        return 0.0
    larghezza = len(valori[0])
    return max(max(v[c] for v in valori) - min(v[c] for v in valori)
               for c in range(larghezza))


def analizza(percorso, soglia_gradi=1.0, soglia_metri=0.001):
    js, binario = leggi_glb(percorso)
    nodi = js.get("nodes", [])
    nomi = [n.get("name", "nodo_%d" % i) for i, n in enumerate(nodi)]
    clip = []

    for anim in js.get("animations", []):
        campionatori = anim.get("samplers", [])
        per_osso = {}     # nome -> {percorso: (ampiezza, unita, n_chiavi)}
        durata = 0.0

        for canale in anim.get("channels", []):
            bersaglio = canale["target"]
            if "node" not in bersaglio:
                continue
            nome = nomi[bersaglio["node"]]
            tipo = bersaglio["path"]
            camp = campionatori[canale["sampler"]]

            tempi = [t[0] for t in leggi_accessor(js, binario, camp["input"])]
            valori = leggi_accessor(js, binario, camp["output"])
            if tempi:
                durata = max(durata, tempi[-1])

            # STEP/LINEAR danno una chiave per tempo; CUBICSPLINE ne da' TRE
            # (tangente entrante, valore, tangente uscente): senza sfoltirle si
            # misurerebbe l'ampiezza delle tangenti insieme a quella dei valori.
            if camp.get("interpolation") == "CUBICSPLINE":
                valori = valori[1::3]

            if tipo == "rotation":
                amp, unita = ampiezza_rotazione(valori), "gradi"
            else:
                amp, unita = ampiezza_vettore(valori), "unita"
            per_osso.setdefault(nome, {})[tipo] = (amp, unita, len(tempi))

        clip.append({
            "nome": anim.get("name", "(senza nome)"),
            "durata": durata,
            "ossa": per_osso,
            "canali": len(anim.get("channels", [])),
        })

    return clip


def osso_mosso(canali, soglia_gradi, soglia_metri):
    for tipo, (amp, unita, _n) in canali.items():
        if tipo == "rotation" and amp >= soglia_gradi:
            return True
        if tipo != "rotation" and amp >= soglia_metri:
            return True
    return False


def descrivi(canali):
    pezzi = []
    for tipo in ("rotation", "translation", "scale"):
        if tipo in canali:
            amp, unita, n = canali[tipo]
            simbolo = "°" if unita == "gradi" else ""
            pezzi.append("%s %.3f%s (%d ch)" % (tipo[:3], amp, simbolo, n))
    return "  ".join(pezzi)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("glb")
    p.add_argument("--clip", help="analizza solo la clip con questo nome")
    p.add_argument("--soglia", type=float, default=1.0,
                   help="gradi sotto cui una rotazione e' rumore (default 1.0)")
    p.add_argument("--soglia-metri", type=float, default=0.001,
                   help="unita' sotto cui una traslazione e' rumore (default 0.001)")
    p.add_argument("--dettaglio", action="store_true",
                   help="elenca OGNI osso, non solo quelli mossi")
    p.add_argument("--attese", type=int, default=None,
                   help="numero minimo di ossa mosse perche' la clip passi")
    args = p.parse_args()

    clip = analizza(args.glb, args.soglia, args.soglia_metri)
    if not clip:
        print("NESSUNA ANIMAZIONE nel file:", args.glb)
        return 1

    print("== %s ==" % args.glb)
    print("   soglie: %.3f gradi / %.4f unita'\n" % (args.soglia, args.soglia_metri))

    statiche = []
    for c in clip:
        if args.clip and c["nome"] != args.clip:
            continue
        mosse = {n: ch for n, ch in c["ossa"].items()
                 if osso_mosso(ch, args.soglia, args.soglia_metri)}
        stato = "STATICA" if not mosse else "ok"
        if not mosse:
            statiche.append(c["nome"])
        print("%-22s %7.2fs  ossa con canali: %3d  MOSSE: %3d   [%s]"
              % (c["nome"], c["durata"], len(c["ossa"]), len(mosse), stato))

        da_stampare = c["ossa"] if args.dettaglio else mosse
        for nome in sorted(da_stampare,
                           key=lambda n: -max(a for a, _u, _k in da_stampare[n].values())):
            segno = " " if nome in mosse else "-"
            print("     %s %-28s %s" % (segno, nome, descrivi(da_stampare[nome])))
        if args.attese is not None and len(mosse) < args.attese:
            print("     ⚠️ attese almeno %d ossa mosse, trovate %d"
                  % (args.attese, len(mosse)))
            statiche.append(c["nome"])
        print()

    if statiche:
        print("⚠️ CLIP CHE NON PASSANO:", ", ".join(sorted(set(statiche))))
        return 1
    print("Tutte le clip si muovono.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
