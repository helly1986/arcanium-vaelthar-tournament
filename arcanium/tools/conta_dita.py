# -*- coding: utf-8 -*-
"""CANCELLO: quante dita ha davvero questa mesh generata?

    blender --background --factory-startup --python arcanium/tools/conta_dita.py -- <file.glb>

## Perche' esiste

⚠️⚠️ **Meshy sbaglia il numero delle dita, e lo sbaglia spesso: ne genera SEI
invece di cinque.** Non e' un caso isolato di un pezzo, e' un difetto noto del
generatore. Sul bracciale della Prima Veglia e' successo, e non ce ne siamo
accorti per settimane — perche' un guanto a sei dita, in mezzo a una mesh
d'acciaio piena di piastre, non salta all'occhio finche' non lo si cerca.

Il costo di non accorgersene e' alto: tutto il lavoro di fitting, pesatura e
conformazione fatto su un pezzo sbagliato **e' da rifare**. E nessuna tecnica di
vestizione lo rimedia — non si mappano sei dita su cinque, per quanto bene si
sappia conformare.

Quindi: **questo cancello si passa PRIMA di investire un minuto in un pezzo
generato che tocca mani o piedi.** Prima della pesatura, prima della
conformazione, prima di metterlo in una tabella.

## Come conta

Non guardando: **contando le isole topologiche**. La prospettiva puo' ingannare
l'occhio su una mano vista di tre quarti — la topologia no.

Si taglia la mesh a varie quote vicino alla punta e si contano le componenti
connesse. Dove il numero e' **stabile su piu' quote**, quello e' il numero di
dita separate. Troppo in basso arrivano solo le piu' lunghe, troppo in alto si
fondono tutte nel palmo: e' la fascia stabile in mezzo che conta.

⚠️ Il POLLICE e' piu' corto e arretrato: alle quote delle punte spesso si e' gia'
fuso col palmo e non compare fra le isole. Guardare anche la sua posizione — un
pollice sta di lato e indietro, un dito sta in fila — o si conta uno di meno.
"""
import bpy, bmesh, sys, os
from mathutils import Vector

SOGLIA_ISOLA = 25      # sotto questo numero di vertici e' rumore, non un dito
QUOTE = [0.04, 0.06, 0.08, 0.10, 0.12, 0.14, 0.16, 0.18, 0.20]


def _argomento():
    if "--" in sys.argv:
        resto = sys.argv[sys.argv.index("--") + 1:]
        if resto:
            return resto[0]
    raise SystemExit("uso: ... --python conta_dita.py -- <file.glb>")


def _tronconi(percorso):
    """Importa, salda le cuciture e restituisce i gusci separati, dal piu' grosso."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=percorso)
    m = max((o for o in bpy.data.objects if o.type == 'MESH'),
            key=lambda o: len(o.data.vertices))
    for o in list(bpy.data.objects):
        if o is not m:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    m.select_set(True)
    bpy.context.view_layer.objects.active = m
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ## ⚠️ Senza saldare, `separate LOOSE` non vede i gusci: vede le migliaia di
    ## isole delle cuciture UV. E' la stessa trappola della vestizione.
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.mesh.separate(type='LOOSE')
    bpy.ops.object.mode_set(mode='OBJECT')
    return sorted([o for o in bpy.context.selected_objects if o.type == 'MESH'],
                  key=lambda o: len(o.data.vertices), reverse=True)


def _isole(ob, taglio):
    """Componenti connesse di cio' che resta sotto `taglio`."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > taglio], context='VERTS')
    visti, fuori = set(), []
    for v in bm.verts:
        if v.index in visti or not v.link_edges:
            continue
        pila, gruppo = [v], []
        visti.add(v.index)
        while pila:
            c = pila.pop()
            gruppo.append(c)
            for e in c.link_edges:
                a = e.other_vert(c)
                if a.index not in visti:
                    visti.add(a.index)
                    pila.append(a)
        if len(gruppo) >= SOGLIA_ISOLA:
            centro = sum((g.co for g in gruppo), Vector()) / len(gruppo)
            fuori.append((centro, min(g.co.z for g in gruppo), len(gruppo)))
    bm.free()
    return fuori


def conta(percorso):
    tronconi = _tronconi(percorso)
    print("%s: %d gusci (vertici: %s)"
          % (os.path.basename(percorso), len(tronconi),
             [len(t.data.vertices) for t in tronconi[:4]]))
    ob = tronconi[0]
    zs = [v.co.z for v in ob.data.vertices]
    zmin, alt = min(zs), max(zs) - min(zs)

    conteggi = []
    for f in QUOTE:
        isole = _isole(ob, zmin + alt * f)
        conteggi.append(len(isole))
        righe = ""
        if isole:
            isole.sort(key=lambda t: t[0].x)
            righe = "  x: " + " ".join("%+.3f" % c.x for c, _, _ in isole)
        print("  %2d%% dell'altezza: %d isole%s" % (f * 100, len(isole), righe))

    ## la fascia stabile: il valore che si ripete di piu' fra quote consecutive
    stabile, run, migliore, lung = None, 1, None, 0
    for i in range(1, len(conteggi)):
        if conteggi[i] == conteggi[i - 1]:
            run += 1
            if run > lung:
                lung, migliore = run, conteggi[i]
        else:
            run = 1
    stabile = migliore
    print("")
    print("  isole stabili alle punte: %s" % str(stabile))
    print("  ⚠️ il POLLICE spesso si e' gia' fuso col palmo a queste quote:")
    print("     se le isole stanno tutte IN FILA, il pollice e' in piu' -> dita = isole + 1")
    if stabile is not None and stabile + 1 > 5:
        print("")
        print("  ⛔ SOSPETTO: %d dita col pollice. Una mano ne ha CINQUE." % (stabile + 1))
        print("     Meshy ne genera sei spesso. NON investire fitting su questo pezzo:")
        print("     si rigenera, oppure il guanto si deriva dal corpo (che le dita")
        print("     giuste ce le ha per costruzione).")
    return stabile


if __name__ == "__main__":
    conta(_argomento())
