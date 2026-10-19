# -*- coding: utf-8 -*-
"""Porta una clip da uno scheletro estraneo al rig canonico di Arcanium.

Serve per le clip che arrivano da fuori (Mixamo, mocap, generatori) e che hanno
nomi d'osso diversi, catena diversa e posa di riposo diversa da quella del
progetto. Rinominare le tracce NON basta: due rig di provenienza diversa hanno
riposi diversi, e la clip trasferita esce storta anche se ogni traccia risolve.

Il conto e' lo stesso di `arcanium/tools/rig_retarget.gd`, ma cotto in un GLB
invece che applicato a runtime. Per ogni osso, a ogni frame:

  1. orientamento della sorgente in spazio armatura        G_s(b,t)
  2. scarto rispetto al SUO riposo                          D = G_s(b,t) . GRs(b)^-1
  3. lo stesso scarto sul riposo del destinatario           R_d = D . GRd(b)
  4. rientro in locale, discendendo la gerarchia            basis = ...

Le POSIZIONI restano quelle di riposo del destinatario: le ossa hanno lunghezze
diverse e copiare le traslazioni disarticolerebbe lo scheletro. L'unica
eccezione e' l'`Hips`, la cui traslazione e' movimento vero (accasciarsi,
saltare): il suo scarto viene scalato per il rapporto fra le due altezze di
bacino.

Uso (headless, non tocca la sessione Blender aperta):

    blender.exe --background --python arcanium/tools/retarget_su_canonico.py -- \
        clip_sorgente.glb corpo_canonico.glb uscita.glb

Il corpo canonico serve solo come portatore del riposo di destinazione: la mesh
viene scartata e in uscita c'e' solo l'armatura con la clip.
"""
import sys
import bpy
from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# La mappa. ATTENZIONE: la spina si mappa PER POSIZIONE IN CATENA, non per nome.
# In player_poison_death la catena e' Hips -> Spine02 -> Spine01 -> Spine, cioe'
# `Spine02` e' l'osso piu' BASSO e `Spine` il piu' ALTO: l'opposto di quello che
# i nomi suggeriscono. Misurato: mappando per nome lo scarto di riposo era
# 175,65 gradi (praticamente invertito); per posizione scende a 4-5.
# ---------------------------------------------------------------------------
MAPPA = {
    "Hips": "Hips",
    "Spine02": "Spine",
    "Spine01": "Chest",
    "Spine": "UpperChest",
    "neck": "Neck",
    "Head": "Head",
    "LeftShoulder": "LeftShoulder",
    "LeftArm": "LeftUpperArm",
    "LeftForeArm": "LeftLowerArm",
    "LeftHand": "LeftHand",
    "RightShoulder": "RightShoulder",
    "RightArm": "RightUpperArm",
    "RightForeArm": "RightLowerArm",
    "RightHand": "RightHand",
    "LeftUpLeg": "LeftUpperLeg",
    "LeftLeg": "LeftLowerLeg",
    "LeftFoot": "LeftFoot",
    "LeftToeBase": "LeftToes",
    "RightUpLeg": "RightUpperLeg",
    "RightLeg": "RightLowerLeg",
    "RightFoot": "RightFoot",
    "RightToeBase": "RightToes",
}
# `headfront` e `head_end` non hanno corrispondente nel canonico: si scartano.

OSSO_BACINO = "Hips"


def _log(*a):
    print("[retarget]", *a)


def _armature_importata(percorso):
    prima = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=percorso)
    nuovi = [o for o in bpy.context.scene.objects if o not in prima]
    arms = [o for o in nuovi if o.type == "ARMATURE"]
    if not arms:
        raise SystemExit("nessuna armatura in %s" % percorso)
    return arms[0], nuovi


def _ordine_gerarchico(arm):
    """Ossa dal padre al figlio: il conto va fatto discendendo."""
    fuori = []

    def vai(osso):
        fuori.append(osso)
        for f in osso.children:
            vai(f)

    for b in arm.data.bones:
        if b.parent is None:
            vai(b)
    return fuori


def retarget(sorgente, corpo, uscita, fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # ⚠️ Va messo PRIMA dell'import: il caricatore glTF converte i tempi in
    # secondi in numeri di frame usando gli fps della scena. Col default di
    # Blender (24) una clip di 6,37 s entra in 152 frame invece di 191, e la
    # clip finisce ricampionata a una cadenza che non e' quella del progetto.
    bpy.context.scene.render.fps = int(fps)
    bpy.context.scene.render.fps_base = 1.0

    dst, _ = _armature_importata(corpo)
    dst.name = "CANONICO"
    src, nuovi_src = _armature_importata(sorgente)
    src.name = "SORGENTE"

    azione = src.animation_data.action if src.animation_data else None
    if azione is None:
        raise SystemExit("la sorgente non ha animazione")
    f0, f1 = (int(round(v)) for v in azione.frame_range)
    _log("clip '%s': frame %d -> %d" % (azione.name, f0, f1))

    # --- controllo della mappa, prima di calcolare qualsiasi cosa -----------
    mancanti_src = [k for k in MAPPA if k not in src.pose.bones]
    mancanti_dst = [v for v in MAPPA.values() if v not in dst.pose.bones]
    if mancanti_src or mancanti_dst:
        raise SystemExit("mappa non applicabile. Assenti nella sorgente: %s; "
                         "nel canonico: %s" % (mancanti_src, mancanti_dst))
    _log("mappa verificata: %d ossa" % len(MAPPA))

    # --- riposi, in spazio armatura ----------------------------------------
    riposo_src = {n: src.data.bones[n].matrix_local.copy() for n in MAPPA}
    riposo_dst = {b.name: b.matrix_local.copy() for b in dst.data.bones}

    # rapporto d'altezza dei bacini, per la sola traslazione del bacino
    p_src_riposo = riposo_src[OSSO_BACINO].translation.copy()
    p_dst_riposo = riposo_dst[MAPPA[OSSO_BACINO]].translation.copy()
    k = (p_dst_riposo.z / p_src_riposo.z) if abs(p_src_riposo.z) > 1e-9 else 1.0
    _log("bacino a riposo: sorgente %.4f, canonico %.4f -> fattore %.4f"
         % (p_src_riposo.z, p_dst_riposo.z, k))

    inversa = {n: riposo_src[n].inverted() for n in MAPPA}

    for pb in dst.pose.bones:
        pb.rotation_mode = "QUATERNION"

    nome_clip = azione.name
    dst.animation_data_create()
    nuova = bpy.data.actions.new("__retarget_in_corso")
    dst.animation_data.action = nuova

    ordine = _ordine_gerarchico(dst)
    nome_dst_di_src = MAPPA
    src_di_dst = {v: kk for kk, v in MAPPA.items()}

    scena = bpy.context.scene
    scena.frame_start, scena.frame_end = f0, f1

    for f in range(f0, f1 + 1):
        scena.frame_set(f)

        # scarti in spazio armatura, letti dalla sorgente posata
        scarto = {}
        for ns, nd in nome_dst_di_src.items():
            g = src.pose.bones[ns].matrix          # spazio armatura
            d = g @ inversa[ns]
            scarto[nd] = d.to_quaternion().to_matrix().to_4x4()

        # traslazione del bacino: scarto in spazio armatura, scalato
        p_src = src.pose.bones[OSSO_BACINO].matrix.translation
        delta_bacino = (p_src - p_src_riposo) * k

        A = {}                                     # matrici desiderate, sp. armatura
        for osso in ordine:
            pad = osso.parent
            offset = (pad.matrix_local.inverted() @ osso.matrix_local) if pad \
                else osso.matrix_local.copy()
            Apad = A[pad.name] if pad else Matrix.Identity(4)
            base = Apad @ offset                   # dove starebbe seguendo il riposo

            if osso.name in scarto:
                R = (scarto[osso.name] @ osso.matrix_local).to_3x3()
            else:
                R = base.to_3x3()                  # osso non mappato: resta a riposo

            pos = base.translation.copy()
            if osso.name == MAPPA[OSSO_BACINO]:
                pos = p_dst_riposo + delta_bacino

            A[osso.name] = Matrix.Translation(pos) @ R.to_4x4()
            dst.pose.bones[osso.name].matrix_basis = \
                offset.inverted() @ Apad.inverted() @ A[osso.name]

        for osso in ordine:
            pb = dst.pose.bones[osso.name]
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if osso.name == MAPPA[OSSO_BACINO]:
                pb.keyframe_insert("location", frame=f)

    _log("cotti %d frame su %d ossa" % (f1 - f0 + 1, len(ordine)))

    # --- via tutto tranne l'armatura canonica ------------------------------
    for o in list(bpy.context.scene.objects):
        if o is not dst:
            bpy.data.objects.remove(o, do_unlink=True)

    # ⚠️ L'azione della sorgente si chiama spesso come la clip che vogliamo
    # produrre: se resta in giro l'esportatore le scrive TUTTE E DUE nel GLB, e
    # il gioco che prende `get_animation_list()[0]` pesca quella sbagliata.
    # Verificato: senza questo, in uscita c'erano `PoisonDeath` (la sorgente,
    # inservibile sul rig canonico) e `PoisonDeath.001` (quella buona).
    bpy.data.actions.remove(azione)
    nuova.name = nome_clip
    if nuova.name != nome_clip:
        raise SystemExit("nome azione ancora occupato: %r" % nuova.name)
    if len(bpy.data.actions) != 1:
        raise SystemExit("azioni residue: %s" % [a.name for a in bpy.data.actions])

    bpy.ops.export_scene.gltf(
        filepath=uscita,
        export_format="GLB",
        export_animations=True,
        export_force_sampling=True,
        export_animation_mode="ACTIONS",
        export_frame_range=True,
        export_apply=False,
        export_yup=True,
    )
    _log("scritto", uscita)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) != 3:
        raise SystemExit(__doc__)
    retarget(argv[0], argv[1], argv[2])
