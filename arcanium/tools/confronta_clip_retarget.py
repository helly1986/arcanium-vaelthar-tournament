# -*- coding: utf-8 -*-
"""Confronta una clip prima e dopo il retarget, misurando il GESTO.

Non basta che il file esista e abbia le tracce giuste: il retarget puo' riuscire
formalmente e perdere il movimento. Questo script misura, frame per frame e su
entrambe le clip, quantita' che descrivono l'azione invece della meccanica:

- altezza del bacino e della testa (il corpo scende? di quanto?)
- distanza mano-gola, normalizzata sull'altezza del personaggio (le mani vanno
  davvero al collo?)
- apertura del ginocchio (le gambe si piegano?)

Le distanze si normalizzano perche' i due corpi hanno proporzioni diverse
(femore +19%, tibia -2%): confrontare centimetri direbbe "diverso" anche su un
retarget perfetto.

Uso:

    blender.exe --background --python arcanium/tools/confronta_clip_retarget.py -- \
        sorgente.glb OSSO_MANO,OSSO_COLLO,... destinazione.glb OSSO_MANO,...
"""
import sys
import bpy


def _carica(percorso):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=percorso)
    arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if not arms:
        raise SystemExit("nessuna armatura in %s" % percorso)
    return arms[0]


def _pos(arm, nome):
    return arm.matrix_world @ arm.pose.bones[nome].head


def misura(percorso, ossa, campioni=13):
    """ossa = dict con chiavi bacino, testa, mano_sx, mano_dx, collo,
    anca, ginocchio, caviglia."""
    arm = _carica(percorso)
    az = arm.animation_data.action
    f0, f1 = (int(round(v)) for v in az.frame_range)
    sc = bpy.context.scene

    # altezza di riferimento: bacino a riposo, per normalizzare le distanze
    sc.frame_set(f0)
    h_rif = _pos(arm, ossa["bacino"]).z
    righe = []
    for i in range(campioni):
        f = f0 + round((f1 - f0) * i / (campioni - 1))
        sc.frame_set(f)
        bacino = _pos(arm, ossa["bacino"])
        testa = _pos(arm, ossa["testa"])
        collo = _pos(arm, ossa["collo"])
        msx = _pos(arm, ossa["mano_sx"])
        mdx = _pos(arm, ossa["mano_dx"])
        anca = _pos(arm, ossa["anca"])
        gin = _pos(arm, ossa["ginocchio"])
        cav = _pos(arm, ossa["caviglia"])
        # angolo del ginocchio: 180 = gamba dritta
        import mathutils, math
        v1 = (anca - gin); v2 = (cav - gin)
        ang = math.degrees(v1.angle(v2)) if v1.length > 1e-6 and v2.length > 1e-6 else 0.0
        righe.append(dict(
            f=f,
            pct=(f - f0) / max(1, (f1 - f0)),
            bacino=bacino.z / h_rif,
            testa=testa.z / h_rif,
            mano_collo=min((msx - collo).length, (mdx - collo).length) / h_rif,
            ginocchio=ang,
        ))
    return righe, f0, f1, h_rif


OSSA_MIXAMO = dict(bacino="Hips", testa="Head", collo="neck", mano_sx="LeftHand",
                   mano_dx="RightHand", anca="LeftUpLeg", ginocchio="LeftLeg",
                   caviglia="LeftFoot")
OSSA_CANONICHE = dict(bacino="Hips", testa="Head", collo="Neck", mano_sx="LeftHand",
                      mano_dx="RightHand", anca="LeftUpperLeg",
                      ginocchio="LeftLowerLeg", caviglia="LeftFoot")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    sorgente, destinazione = argv[0], argv[1]
    a, af0, af1, ah = misura(sorgente, OSSA_MIXAMO)
    b, bf0, bf1, bh = misura(destinazione, OSSA_CANONICHE)
    print()
    print("SORGENTE     %s  (%d frame, bacino a riposo %.3f m)" % (sorgente.split("/")[-1], af1 - af0 + 1, ah))
    print("RETARGETTATA %s  (%d frame, bacino a riposo %.3f m)" % (destinazione.split("/")[-1], bf1 - bf0 + 1, bh))
    print()
    print("           |------------- SORGENTE -------------|----------- RETARGETTATA -----------|")
    print("  %%clip  |  bacino  testa  mano-collo  ginocch |  bacino  testa  mano-collo  ginocch")
    for ra, rb in zip(a, b):
        print("  %5.0f%%  |  %6.3f %6.3f  %9.3f  %7.1f |  %6.3f %6.3f  %9.3f  %7.1f"
              % (ra["pct"] * 100,
                 ra["bacino"], ra["testa"], ra["mano_collo"], ra["ginocchio"],
                 rb["bacino"], rb["testa"], rb["mano_collo"], rb["ginocchio"]))
    print()
    # scarti massimi: se il retarget e' fedele devono essere piccoli
    for chiave, etichetta in [("bacino", "altezza bacino"), ("testa", "altezza testa"),
                              ("mano_collo", "distanza mano-collo")]:
        peggio = max(abs(ra[chiave] - rb[chiave]) for ra, rb in zip(a, b))
        print("  scarto massimo %-22s %.4f (in altezze di bacino)" % (etichetta, peggio))
    peggio = max(abs(ra["ginocchio"] - rb["ginocchio"]) for ra, rb in zip(a, b))
    print("  scarto massimo %-22s %.2f gradi" % ("angolo ginocchio", peggio))
