"""Monta un CAMPIONE (docs/campioni_concept.md) con la ricetta dei corpi Tripo
vestiti di `monta_consumato_sylvorn.py` (docs/05_RIG_CANONICO.md §4-ter): stessa
pipeline di Arcanium, cambiano solo le cartelle.

Si esegue DENTRO Blender, dal ponte (arcanium/tools/ponte_blender.py), un passo
per chiamata: il ponte ricrea il namespace ogni volta, la scena invece resta.

    exec(open(".../monta_campione.py").read())
    m = carica("edran")                    # la ricetta, puntata sul campione
    m["prepara"]("edran", altezza=1.86)    # sorgenti/edran.fbx, coi piedi a terra
    m["rigga"]()                           # ARP, guscio per guscio
    m["travasa"](affila=False, falde=False, gabbia=True)
    m["esporta_glb"](m["DIR_SYLVORN"] + "edran_rigged.glb")

Il campione sta in assets/characters/campioni/<nome>/, la sorgente FBX di
Tripo in <nome>/sorgenti/ (con .gdignore: versionata, Godot non la importa).
"""
import os

P = "C:/Users/Adriano/LOCAL/arcanium---vaelthar-tournament/arcanium/tools/monta_consumato_sylvorn.py"


def carica(nome):
    ns = {"__name__": "monta_campione", "P": P}
    exec(compile(open(P, encoding="utf-8").read(), P, "exec"), ns)
    cartella = ns["RADICE"] + "assets/characters/campioni/%s/" % nome
    ## Le funzioni della ricetta leggono queste globali del loro namespace.
    ns["DIR_SYLVORN"] = cartella
    ns["DIR_SORGENTI"] = cartella + "sorgenti/"
    os.makedirs(ns["DIR_SORGENTI"], exist_ok=True)
    return ns
