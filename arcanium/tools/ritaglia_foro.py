# -*- coding: utf-8 -*-
"""Toglie la materia che entra dentro il FORO di un pezzo ad anello.

    blender --background --python arcanium/tools/ritaglia_foro.py -- <glb> [raggio]

⚠️ PERCHE' SERVE. La piazzola del ballatoio di Kalvorn e' un anello che deve
lasciar passare il tronco. Generata, il foro e' uscito SBILENCO: il bordo
interno andava da 0,19 a 0,34 (raggio esterno 0,483), cioe' su meta'
circonferenza il tavolato sporgeva dentro il buco. In gioco quella lingua
sarebbe finita DENTRO la corteccia.

Scalare il pezzo finche' il punto piu' stretto libera il tronco non e' una
cura: ingrandisce tutto l'anello e il pianerottolo diventa una piazza. Si
taglia, e costa zero.

Il criterio e' geometrico e non a occhio: si stima il centro dai vertici del
BORDO ESTERNO (l'unico cerchio affidabile — quello interno e' proprio quello
sbagliato), poi si cancella ogni faccia il cui centro cade sotto il raggio
voluto. Restano bordi aperti sull'anello interno: da fuori non si vedono, e
li' dentro passa comunque il tronco.

⚠️ Il taglio va SEMPRE rimisurato dopo: lo script stampa il bordo interno per
settore prima e dopo, e i due profili sono la verifica.
"""
import bpy, bmesh, math, os, sys


def raggi_per_settore(polygons, cx, cy, S=24):
    r = [9.0] * S
    for p in polygons:
        c = p.center if hasattr(p, "center") else p.calc_center_median()
        d = math.hypot(c.x - cx, c.y - cy)
        i = int(((math.degrees(math.atan2(c.y - cy, c.x - cx)) + 360.0) % 360.0) / 360.0 * S) % S
        r[i] = min(r[i], d)
    return r


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("uso: ... -- <glb> [raggio_foro]")
    glb = os.path.abspath(args[0])

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=glb)
    o = [x for x in bpy.data.objects if x.type == 'MESH'][0]
    me = o.data

    ## Centro dal bordo ESTERNO: la media di tutti i vertici e' spostata
    ## proprio dall'asimmetria che si vuole correggere.
    cx0 = sum(v.co.x for v in me.vertices) / len(me.vertices)
    cy0 = sum(v.co.y for v in me.vertices) / len(me.vertices)
    r_max = max(math.hypot(v.co.x - cx0, v.co.y - cy0) for v in me.vertices)
    est = [v.co for v in me.vertices
           if math.hypot(v.co.x - cx0, v.co.y - cy0) > r_max * 0.85]
    cx = sum(p.x for p in est) / len(est)
    cy = sum(p.y for p in est) / len(est)
    r_est = sum(math.hypot(p.x - cx, p.y - cy) for p in est) / len(est)

    prima = raggi_per_settore(me.polygons, cx, cy)
    ## Di default si taglia al SETTORE PIU' LARGO gia' presente: cosi' il foro
    ## diventa tondo senza togliere un millimetro di tavolato utile in piu'.
    r_foro = float(args[1]) if len(args) > 1 else min(max(prima), r_est * 0.62)

    print("centro %.4f %.4f | raggio esterno %.3f | taglio a %.3f" % (cx, cy, r_est, r_foro))
    print("bordo interno PRIMA: " + " ".join("%.2f" % v for v in prima))

    bm = bmesh.new()
    bm.from_mesh(me)
    n0 = len(bm.faces)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces
        if math.hypot(f.calc_center_median().x - cx,
                      f.calc_center_median().y - cy) < r_foro], context='FACES')
    bm.to_mesh(me)
    bm.free()
    me.update()

    dopo = raggi_per_settore(me.polygons, cx, cy)
    print("bordo interno DOPO : " + " ".join("%.2f" % v for v in dopo))
    print("facce %d -> %d" % (n0, len(me.polygons)))

    bpy.ops.object.select_all(action='DESELECT')
    for x in bpy.data.objects:
        if x.type in {'MESH', 'EMPTY'}:
            x.select_set(True)
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
                              export_yup=True, export_materials='EXPORT')
    print("scritto %s (%d byte)" % (glb, os.path.getsize(glb)))


main()
