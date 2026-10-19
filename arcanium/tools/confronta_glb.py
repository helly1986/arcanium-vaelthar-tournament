# -*- coding: utf-8 -*-
"""Confronto strutturale fra due GLB: la diagnosi da dieci secondi che coglie
le unita' sbagliate (un fattore 100 sulle traslazioni di rest, o una rotazione
sulla radice che l'altro non ha) e le clip perse o raddoppiate.

Uso: python confronta_glb.py <vecchio.glb> <nuovo.glb>
"""
import json, struct, sys


def apri(p):
    d = open(p, "rb").read()
    n = struct.unpack_from("<I", d, 12)[0]
    return json.loads(d[20:20 + n]), len(d)


a, sa = apri(sys.argv[1])
b, sb = apri(sys.argv[2])
print("%-28s %12s %12s" % ("", "VECCHIO", "NUOVO"))
print("%-28s %12d %12d" % ("byte", sa, sb))
for k in ("meshes", "skins", "animations", "images", "materials", "textures", "nodes"):
    print("%-28s %12d %12d" % (k, len(a.get(k, [])), len(b.get(k, []))))
print("%-28s %12d %12d" % ("joints", len(a["skins"][0]["joints"]), len(b["skins"][0]["joints"])))

na = [x.get("name") for x in a["animations"]]
nb = [x.get("name") for x in b["animations"]]
print("\nanimazioni vecchie:", na)
print("animazioni nuove:  ", nb)
print("MANCANTI:", [x for x in na if x not in nb], " IN PIU':", [x for x in nb if x not in na])
if len(nb) != len(set(nb)):
    print("!!! CLIP DOPPIE")

ja = [a["nodes"][i].get("name") for i in a["skins"][0]["joints"]]
jb = [b["nodes"][i].get("name") for i in b["skins"][0]["joints"]]
print("\nossa in piu':", [x for x in jb if x not in ja],
      " perse:", [x for x in ja if x not in jb])

# --- rest: traslazione di ogni osso, confrontata nome per nome ---
def rest(g, nomi):
    fuori = {}
    for i, n in zip(g["skins"][0]["joints"], nomi):
        nd = g["nodes"][i]
        fuori[n] = (nd.get("translation", [0, 0, 0]), nd.get("rotation"), nd.get("scale"))
    return fuori


ra, rb = rest(a, ja), rest(b, jb)
peggio, dove = 0.0, ""
for n in ja:
    if n not in rb:
        continue
    ta, tb = ra[n][0], rb[n][0]
    d = max(abs(x - y) for x, y in zip(ta, tb))
    if d > peggio:
        peggio, dove = d, n
print("\nscarto MASSIMO sulle traslazioni di rest: %.6f (osso %s)" % (peggio, dove))
print("  un fattore 100 qui = unita' sbagliate")
for n in (jb[0], "head"):
    print("  %-8s vecchio %s" % (n, [round(v, 5) for v in ra.get(n, ([],))[0]]))
    print("  %-8s nuovo   %s" % (n, [round(v, 5) for v in rb.get(n, ([],))[0]]))
for n in [x for x in jb if x not in ja]:
    print("  %-8s NUOVO   %s" % (n, [round(v, 5) for v in rb[n][0]]))

# --- radice della scena ---
for g, nome in ((a, "vecchio"), (b, "nuovo")):
    r = g["nodes"][g["scenes"][0]["nodes"][0]]
    print("\nradice %s: %s  rot=%s scala=%s" % (
        nome, r.get("name"), r.get("rotation"), r.get("scale")))
