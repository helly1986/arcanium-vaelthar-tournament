# -*- coding: utf-8 -*-
"""Sostituisce l'animazione di un GLB con una clip che TIENE una posa.

    python arcanium/tools/glb_clip_da_posa.py <base.glb> <posa.json|riposo> <uscita.glb>
                                              [--frame 40] [--fps 30] [--nome Testuggine]

Con `riposo` al posto del JSON la clip tiene la posa di RIPOSO del GLB stesso.

Serve a preparare una scena di lavorazione: il personaggio parte gia' nella
posa giusta al primo fotogramma e ci torna all'ultimo, e l'animatore lavora in
mezzo.

═══════════════════════════════════════════════════════════════════════════
PERCHE' GLI ESTREMI VANNO A RIPOSO, E NON NELLA POSA DEL GESTO
═══════════════════════════════════════════════════════════════════════════

La prima versione di questa scena metteva la GUARDIA al primo e all'ultimo
fotogramma: la mossa nasce e muore in guardia, quindi sembrava ovvio. E'
sbagliato, e il motivo e' che **in gioco quella posa non esiste come posa**.

La guardia e' un `AnimationNodeBlend2` FILTRATO dalla spina in su: il busto
arriva dal fotogramma congelato, le gambe dalla locomozione, e il peso non e'
nemmeno pieno mentre lo scudo sale. Cio' che il giocatore vede e' un miscuglio
che cambia da un frame all'altro — autorare "dalla guardia" vuol dire partire
da una posa che a schermo non compare in nessun istante.

Il RIPOSO invece e' l'unica posa che il motore conosce con certezza: e' il
riferimento rispetto a cui ogni strato si somma. Una clip che parte e finisce
li' si puo' mescolare sopra qualunque cosa il corpo stia facendo — che e'
esattamente cio' che serve a un gesto di UN SOLO ARTO.

⚠️ Conseguenza sul lato motore, da non dimenticare quando la clip torna: il suo
strato va FILTRATO sulla sola catena animata. Se la clip tiene il riposo su
tutto il resto del corpo e non la si filtra, quel riposo cancella la guardia e
la camminata.

⚠️ IL RIPOSO SI SCRIVE QUI, NON IN CASCADEUR. Provato: con il rig gia' cotto,
scrivere `Local Rotation` sui giunti non tiene — i controller del rig ricalcolano
e il valore riletto sbaglia di 92 gradi. Su un personaggio riggato si posa dai
controller, non dai giunti. Quindi la posa degli estremi entra dal GLB, PRIMA
dell'import.

⚠️ E il riposo di Cascadeur sta nei canali `Model Pose Local Rotation` /
`Model Pose Local Position`, che sono dato STATICO: si leggono senza
fotogramma. Chiedendoli con il frame si prende `animation data with id ... does
not exist`, che sembra un id sbagliato ed e' invece il canale giusto interrogato
nel modo sbagliato.

⚠️ Il riposo dei NODI del GLB non si tocca. La clip autorata deve rientrare in
Godot dalla stessa porta delle altre — l'importatore glTF con la sua
`retarget/bone_map` e il suo rest fixer — e un riposo diverso cambia in silenzio
cio' che il rest fixer corregge. E' la classe di guasto che su questo progetto
ha gia' prodotto un Fante coricato con meta' delle tracce nel vuoto.

⚠️ Le traslazioni si scrivono solo dove la posa le porta davvero diverse dal
riposo. In una clip glTF ogni osso ha il suo canale di traslazione, ma per
quasi tutti e' l'offset costante della gerarchia: riscriverlo non aggiunge
niente e moltiplica i dati per tre.
"""

import argparse
import json
import struct


def _leggi(percorso):
    with open(percorso, "rb") as f:
        magic, _ver, _tot = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise SystemExit("%s non e' un GLB" % percorso)
        testa, binario = None, b""
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
    return testa, binario


def _scrivi(percorso, testa, binario):
    j = json.dumps(testa, separators=(",", ":")).encode("utf-8")
    j += b" " * ((4 - len(j) % 4) % 4)
    b = binario + b"\x00" * ((4 - len(binario) % 4) % 4)
    totale = 12 + 8 + len(j) + 8 + len(b)
    with open(percorso, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, totale))
        f.write(struct.pack("<II", len(j), 0x4E4F534A))
        f.write(j)
        f.write(struct.pack("<II", len(b), 0x004E4942))
        f.write(b)


def _aggiungi(testa, binario, valori, tipo, minimo=None, massimo=None):
    """Accoda un accessor + bufferView e ne restituisce l'indice."""
    piatto = [x for v in valori for x in v]
    dati = struct.pack("<" + "f" * len(piatto), *piatto)
    off = len(binario)
    binario += dati
    binario += b"\x00" * ((4 - len(binario) % 4) % 4)
    testa.setdefault("bufferViews", []).append(
        {"buffer": 0, "byteOffset": off, "byteLength": len(dati)})
    a = {"bufferView": len(testa["bufferViews"]) - 1, "componentType": 5126,
         "count": len(valori), "type": tipo}
    if minimo is not None:
        a["min"], a["max"] = minimo, massimo
    testa.setdefault("accessors", []).append(a)
    return len(testa["accessors"]) - 1, binario


def costruisci(base, posa_json, uscita, frame, fps, nome):
    testa, binario = _leggi(base)
    nodi = testa.get("nodes", [])
    per_nome = {}
    for i, n in enumerate(nodi):
        if "name" in n:
            per_nome[n["name"]] = i

    if posa_json == "riposo":
        ## ⚠️ Il riposo si prende dai nodi dello SKIN, non da tutti i nodi: la
        ## radice della scena e il nodo della mesh non sono ossa, e animarli
        ## sposterebbe il personaggio invece di posarlo.
        ossa_skin = set()
        for sk in testa.get("skins", []):
            for j in sk.get("joints", []):
                ossa_skin.add(j)
        posa = {}
        for i in sorted(ossa_skin):
            n = nodi[i]
            posa[n.get("name", "nodo_%d" % i)] = {
                "rotation": list(n.get("rotation", [0.0, 0.0, 0.0, 1.0])),
                "translation": list(n.get("translation", [0.0, 0.0, 0.0])),
            }
    else:
        posa = json.load(open(posa_json, encoding="utf-8"))["ossa"]

    # ⚠️ Il riposo si legge PRIMA di toccare qualunque cosa: serve a decidere
    # quali traslazioni valga la pena scrivere.
    durata = (frame - 1) / float(fps)
    tempi = [[0.0], [durata]]
    id_tempo, binario = _aggiungi(testa, binario, tempi, "SCALAR",
                                  [0.0], [durata])

    canali, campionatori = [], []
    scritte_rot, scritte_tra = 0, 0
    for osso, dati in sorted(posa.items()):
        idx = per_nome.get(osso)
        if idx is None:
            continue
        rot = dati.get("rotation")
        if rot:
            aid, binario = _aggiungi(testa, binario, [rot, rot], "VEC4")
            campionatori.append({"input": id_tempo, "output": aid,
                                 "interpolation": "LINEAR"})
            canali.append({"sampler": len(campionatori) - 1,
                           "target": {"node": idx, "path": "rotation"}})
            scritte_rot += 1
        tra = dati.get("translation")
        if tra is not None:
            riposo = nodi[idx].get("translation", [0.0, 0.0, 0.0])
            if max(abs(a - b) for a, b in zip(tra, riposo)) > 1e-5:
                aid, binario = _aggiungi(testa, binario, [tra, tra], "VEC3")
                campionatori.append({"input": id_tempo, "output": aid,
                                     "interpolation": "LINEAR"})
                canali.append({"sampler": len(campionatori) - 1,
                               "target": {"node": idx, "path": "translation"}})
                scritte_tra += 1

    testa["animations"] = [{"name": nome, "channels": canali,
                            "samplers": campionatori}]
    testa["buffers"][0]["byteLength"] = len(binario) + (
        (4 - len(binario) % 4) % 4)
    _scrivi(uscita, testa, binario)

    mancanti = [o for o in posa if o not in per_nome]
    print("clip '%s': %d fotogrammi a %d fps (%.3f s)"
          % (nome, frame, fps, durata))
    print("  %d rotazioni, %d traslazioni scritte su %d ossa della posa"
          % (scritte_rot, scritte_tra, len(posa)))
    if mancanti:
        print("  ⚠ %d ossa della posa non esistono nel GLB base: %s"
              % (len(mancanti), mancanti[:8]))
    print("  -> %s" % uscita)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("base")
    p.add_argument("posa", help="JSON di posa_da_clip.py, oppure 'riposo'")
    p.add_argument("uscita")
    p.add_argument("--frame", type=int, default=40)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--nome", default="Testuggine")
    a = p.parse_args()
    costruisci(a.base, a.posa, a.uscita, a.frame, a.fps, a.nome)
