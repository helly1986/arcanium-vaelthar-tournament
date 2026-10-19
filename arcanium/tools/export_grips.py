# -*- coding: utf-8 -*-
"""Porta in gioco le prese tarate a mano nell'equip playground.

Legge i transform dei nodi `Grip_*` di `arcanium/levels/equip_playground.tscn`
e li scrive dove il gioco li cerca davvero — che non e' lo stesso posto per
tutti i pezzi:

    arma non di serie   -> `held_transform` nel .tres dell'arma (lo legge
                           HeldWeapon quando la equipaggi dal menu)
    arma del kit        -> il nodo gia' montato in player_dawnkeep.tscn
    scudo               -> ShieldMesh dentro shield.tscn
    sigillo             -> il nodo gia' montato in player_dawnkeep.tscn

Rifiuta di esportare una presa tarata sul mount sbagliato: vedi il commento su
DESTINAZIONI. Un transform preso dal genitore sbagliato e' il modo piu'
silenzioso di buttare via mezz'ora di trascinamenti.

Lavora sul TESTO delle scene, senza aprire Godot: cosi' si puo' lanciare
mentre l'editor e' aperto, invece di litigare con l'istanza dell'utente per
la GPU. Va poi ricaricata la scena toccata nell'editor.

Uso:
    python arcanium/tools/export_grips.py            # scrive
    python arcanium/tools/export_grips.py --prova    # mostra e basta
"""
import os
import re
import sys

RADICE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PLAYGROUND = "arcanium/levels/equip_playground.tscn"

IDENTITA = "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)"

# Ogni presa, il mount su cui DEVE pendere nel playground, e dove finisce in
# gioco. `tipo` dice COME si scrive:
#   "tres"  -> proprieta' `held_transform` nella sezione [resource]
#   "nodo"  -> riga `transform` sotto un nodo di una scena
#
# Il controllo sul mount non e' pignoleria: un transform e' un numero RELATIVO a
# un genitore, e preso dal genitore sbagliato descrive una posa che a riposo
# sembra giusta e sbaglia a ogni frame in cui i due ossi si muovono in modo
# diverso. E' gia' successo col sigillo, tarato appeso all'osso Chest.
DESTINAZIONI = [
    {
        "grip": "Grip_spada_senza_nome",
        "mount": "ManoDestra/HandPivot",
        "tipo": "tres",
        "file": "arcanium/resources/weapons/spada_senza_nome.tres",
        "aabb": ((-0.032045, -0.688346, -0.135193), (0.064150, 1.387292, 0.261581)),
    },
    {
        "grip": "Grip_lancia_del_consumato",
        "mount": "ManoDestra/HandPivot",
        "tipo": "tres",
        "file": "arcanium/resources/weapons/lancia_del_consumato.tres",
        "aabb": ((-11.879877, 0.0, -0.382149), (23.749310, 1.500000, 0.741506)),
    },
    {
        "grip": "Grip_scudo_prima_veglia",
        "mount": "ManoSinistra/HandPivot",
        "tipo": "nodo",
        "file": "player/equipment_system/equipment/shield.tscn",
        "nodo": "ShieldMesh",
        # Il volume che para deve stare dove sta il disco: se si sposta solo la
        # mesh, lo scudo si vede spostato e continua a parare dov'era.
        "segui_collider": "CollisionShape3D",
    },
    {
        "grip": "Grip_lama_prima_veglia",
        "mount": "ManoDestra/HandPivot",
        "tipo": "nodo",
        "file": "characters/player_dawnkeep.tscn",
        "nodo": "Sword",
    },
    {
        "grip": "Grip_sigillo_prima_veglia",
        "mount": "ManoSinistra/HandPivot",
        "tipo": "nodo",
        "file": "characters/player_dawnkeep.tscn",
        "nodo": "Sigillo_Gadget",
        # Il sigillo e' un oggetto di MANO SECONDARIA: si impugna al posto dello
        # scudo (e' il focus arcano, senza il quale non si lancia). In scena
        # parte dal mount dell'anca solo perche' e' li' che il GadgetSystem
        # parcheggia il pezzo NON impugnato, e da quando il parcheggio e'
        # invisibile (HideStoredGadget) questo transform vale una cosa sola:
        # come sta IN MANO. Quindi si esporta, ma va tarato sotto ManoSinistra.
    },
]


def leggi(rel):
    with open(os.path.join(RADICE, rel), encoding="utf-8") as f:
        return f.read()


def scrivi(rel, testo):
    # newline="" per non convertire i fine riga, encoding esplicito per non
    # inserire un BOM: i .tscn/.tres sono UTF-8 senza BOM e Godot ci tiene.
    with open(os.path.join(RADICE, rel), "w", encoding="utf-8", newline="") as f:
        f.write(testo)


def blocchi_nodo(testo):
    """{nome nodo: (parent, corpo)} per ogni [node name="..."] della scena."""
    fuori = {}
    intestazioni = list(re.finditer(r'^\[node name="([^"]+)"([^\]]*)\]$', testo, re.M))
    for i, m in enumerate(intestazioni):
        fine = intestazioni[i + 1].start() if i + 1 < len(intestazioni) else len(testo)
        p = re.search(r'parent="([^"]*)"', m.group(2))
        fuori[m.group(1)] = (p.group(1) if p else "", testo[m.end():fine])
    return fuori


def transform_di(corpo):
    m = re.search(r"^transform = (Transform3D\([^)]*\))$", corpo, re.M)
    return m.group(1) if m else IDENTITA


def origine_di(t):
    numeri = numeri_di(t)
    return numeri[9:12] if len(numeri) >= 12 else [0.0, 0.0, 0.0]


## Larghezza minima della scatola che colpisce. La lama vera e' sottile pochi
## centimetri: una hitbox aderente manca quasi tutto, e il template infatti usa
## 0.4 su una spada spessa 4 cm. La generosita' e' voluta, non un errore.
SPESSORE_MINIMO = 0.35


def numeri_di(t):
    return [float(x) for x in re.findall(r"-?[\d.eE+-]+", t[len("Transform3D("):-1])]


def hitbox_da(aabb, t):
    """Scatola che copre il modello DOPO la presa tarata.

    La hitbox non e' un numero indipendente: e' una conseguenza di dove hai
    messo l'arma. Spostando la presa della lancia avanti di 42 cm la punta era
    finita fuori dalla scatola, e una lancia che non colpisce con la punta ha
    perso l'unica cosa che sa fare. Ricavarla qui vuol dire che non puo' piu'
    scadere di nascosto al trascinamento successivo.
    """
    n = numeri_di(t)
    # Costruttore piatto di Transform3D = righe della base; le COLONNE sono gli
    # assi. Leggerlo per colonne (cioe' trasposto) e' l'errore classico.
    righe = [n[0:3], n[3:6], n[6:9]]
    origine = n[9:12]
    pos, dim = aabb
    basso = [1e9] * 3
    alto = [-1e9] * 3
    for i in range(8):
        p = [pos[k] + (dim[k] if (i >> k) & 1 else 0.0) for k in range(3)]
        for r in range(3):
            v = sum(righe[r][c] * p[c] for c in range(3)) + origine[r]
            basso[r] = min(basso[r], v)
            alto[r] = max(alto[r], v)
    dimensione = [max(alto[r] - basso[r], SPESSORE_MINIMO) for r in range(3)]
    centro = [(alto[r] + basso[r]) * 0.5 for r in range(3)]
    return dimensione, centro


def scrivi_proprieta(testo, nome, valore):
    riga = "%s = %s" % (nome, valore)
    schema = r"^%s = [A-Za-z0-9_]+\([^)]*\)$" % re.escape(nome)
    if re.search(schema, testo, re.M):
        return re.sub(schema, riga, testo, count=1, flags=re.M)
    # Senza held_model la riga non servirebbe a niente: la si appende in fondo
    # alla sezione [resource], che e' l'ultima del file.
    return testo.rstrip("\n") + "\n" + riga + "\n"


def scrivi_tres(rel, valore, prova, aabb=None):
    testo = leggi(rel)
    nuovo = scrivi_proprieta(testo, "held_transform", valore)
    if aabb is not None:
        dim, centro = hitbox_da(aabb, valore)
        nuovo = scrivi_proprieta(nuovo, "hitbox_size",
                                 "Vector3(%s)" % ", ".join("%g" % v for v in dim))
        nuovo = scrivi_proprieta(nuovo, "hitbox_offset",
                                 "Vector3(%s)" % ", ".join("%g" % v for v in centro))
        print("   hitbox: %s attorno a %s" % (
            ["%.2f" % v for v in dim], ["%.2f" % v for v in centro]))
    if nuovo == testo:
        return False
    if not prova:
        scrivi(rel, nuovo)
    return True


def scrivi_nodo(rel, nodo, valore, prova, origine=None):
    testo = leggi(rel)
    m = re.search(r'^\[node name="%s"[^\]]*\]$' % re.escape(nodo), testo, re.M)
    if m is None:
        print("   ! nodo '%s' non trovato in %s" % (nodo, rel))
        return False
    prossimo = re.search(r"^\[", testo[m.end() + 1:], re.M)
    fine = m.end() + 1 + (prossimo.start() if prossimo else len(testo) - m.end() - 1)
    corpo = testo[m.end():fine]
    riga = "transform = %s" % valore
    if re.search(r"^transform = Transform3D\([^)]*\)$", corpo, re.M):
        nuovo_corpo = re.sub(r"^transform = Transform3D\([^)]*\)$", riga, corpo, count=1, flags=re.M)
    elif valore == IDENTITA:
        nuovo_corpo = corpo   # identita' e riga assente sono la stessa cosa
    else:
        # `corpo` comincia con l'a capo che chiude l'intestazione: la riga si
        # infila SUBITO DOPO e il resto resta com'era. Toglierglielo (lstrip)
        # su un nodo senza corpo saldava la riga all'intestazione del nodo
        # successivo, e il .tscn ne usciva rotto senza che niente protestasse.
        nuovo_corpo = "\n" + riga + corpo
    nuovo = testo[:m.end()] + nuovo_corpo + testo[fine:]
    if nuovo == testo:
        return False
    _verifica_scena(rel, nuovo)
    if not prova:
        scrivi(rel, nuovo)
    return True


## Uno strumento che riscrive scene deve dimostrare di non averle rotte. Il
## controllo costa niente e coglie l'intera famiglia di errori da concatenazione:
## ogni sezione di un .tscn/.tres sta a inizio riga, sempre.
def _verifica_scena(rel, testo):
    for n, riga in enumerate(testo.splitlines(), 1):
        pos = riga.find("[node ")
        if pos <= 0:
            pos = riga.find("[sub_resource ")
        if pos > 0:
            raise SystemExit(
                "ABORT: %s riga %d — sezione a meta' riga, il file sarebbe rotto:\n  %s"
                % (rel, n, riga[:120]))


def main():
    prova = "--prova" in sys.argv
    grip = blocchi_nodo(leggi(PLAYGROUND))
    toccati = set()
    saltati = []
    for d in DESTINAZIONI:
        if d["grip"] not in grip:
            print("%-32s  MANCA nel playground" % d["grip"])
            continue
        genitore, corpo = grip[d["grip"]]
        atteso = d.get("mount")
        if atteso is not None and genitore != atteso:
            print("%-32s  SALTATO: pende da '%s', non da '%s'"
                  % (d["grip"], genitore, atteso))
            print("   trascinalo sul mount giusto (Godot conserva la posa nel mondo)")
            saltati.append(d["grip"])
            continue
        t = transform_di(corpo)
        if d.get("sospeso"):
            print("%-32s  SOSPESO: %s" % (d["grip"], d["sospeso"]))
            print("   (taratura conservata nel playground, non scritta)")
            continue
        print("%-32s -> %s" % (d["grip"], d["file"]))
        print("   %s" % t)
        if d["tipo"] == "tres":
            cambiato = scrivi_tres(d["file"], t, prova, d.get("aabb"))
        else:
            cambiato = scrivi_nodo(d["file"], d["nodo"], t, prova)
            if cambiato and d.get("segui_collider"):
                o = origine_di(t)
                col = "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % tuple(
                    ("%g" % v) for v in o)
                scrivi_nodo(d["file"], d["segui_collider"], col, prova)
                print("   collider allineato: %s" % col)
        print("   %s" % ("scritto" if cambiato and not prova else
                         "da scrivere" if cambiato else "gia' aggiornato"))
        if cambiato:
            toccati.add(d["file"])
    if toccati and not prova:
        print("\nRicarica in editor: " + ", ".join(sorted(toccati)))


if __name__ == "__main__":
    main()
