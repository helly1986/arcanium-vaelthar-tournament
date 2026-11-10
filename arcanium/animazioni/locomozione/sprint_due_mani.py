# -*- coding: utf-8 -*-
"""Le POSE CHIAVE dello sprint A DUE MANI (root-Sprint) sullo scheletro ARP.

    python arcanium/animazioni/locomozione/sprint_due_mani.py <campione> <uscita.json>

La corsa a due mani (corsa_due_mani.py) spinta: stesse chiavi (un contatto a ogni passo, dalla
generazione si tiene il ciclo di mezzo), l'arma sempre in spalla con due mani. Cambia la
misura: la velocita' e' quella dello sprint di Zarine in gioco oggi, 7,44 m/s; il busto pende
di piu', il bacino sta piu' basso, il piede dietro sale di piu' e il passo si allunga.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corsa_due_mani as corsa  # noqa: E402


class Corpo(corsa.Corpo):
    def __init__(self, nome):
        super(Corpo, self).__init__(nome)
        k = self.c["scala"]
        self.avanza = 744.0 / 30.0
        self.bacino_giu = 13.0 * k
        self.bacino_avanti = 5.0 * k
        self.bacino_pende = 13.0
        self.contatto = 26.0 * k
        self.dietro_z = -62.0 * k
        self.dietro_y = 50.0 * k
        self.dietro_punte = 68.0
        self.pende_basso = 9.0
        self.pende_alto = 7.0
        self.testa = -20.0


def spec(nome):
    C = Corpo(nome)
    return {
        "_nota": "Generato da arcanium/animazioni/locomozione/sprint_due_mani.py (%s): non si modifica a mano." % nome,
        "frames": corsa.FRAMES,
        "base": corsa.FRAMES,
        "chiavi": corsa.CHIAVI,
        "pose": {str(f): corsa.posa(C, f) for f in corsa.CHIAVI},
    }


if __name__ == "__main__":
    with open(sys.argv[2], "w", encoding="utf-8") as uscita:
        json.dump(spec(sys.argv[1]), uscita, indent=1)
    print("scritto", sys.argv[2], sys.argv[1], len(corsa.CHIAVI), "pose")
