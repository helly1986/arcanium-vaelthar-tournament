#!/usr/bin/env python3
"""Manda codice Python al Blender aperto, sul ponte dell'addon BlenderMCP
(porta 9876), senza bisogno del server MCP.

    python arcanium/tools/ponte_blender.py file.py          # esegue un file
    python arcanium/tools/ponte_blender.py -c "print(1)"    # esegue una riga

Stampa cio' che il codice stampa (il campo `result` della risposta). Le due
trappole del ponte valgono anche qui (memoria mcp-assenti-pc-nuovo): nessun
oggetto attivo, e il namespace rinasce a ogni chiamata. Le catene lunghe si
lanciano da bpy.app.timers e l'esito si legge da bpy.app.driver_namespace.
"""
import json
import socket
import sys


def manda(codice, porta=9876, attesa=900.0):
    s = socket.create_connection(("127.0.0.1", porta), timeout=attesa)
    s.sendall(json.dumps({"type": "execute_code", "params": {"code": codice}}).encode("utf-8"))
    buf = b""
    while True:
        pezzo = s.recv(65536)
        if not pezzo:
            break
        buf += pezzo
        try:
            return json.loads(buf.decode("utf-8"))
        except ValueError:
            continue
    return json.loads(buf.decode("utf-8"))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    codice = sys.argv[2] if sys.argv[1] == "-c" else open(sys.argv[1], encoding="utf-8").read()
    r = manda(codice)
    if r.get("status") != "success":
        print("ERRORE:", r.get("message", r))
        sys.exit(1)
    res = r.get("result", {})
    print(res.get("result", res) if isinstance(res, dict) else res)


if __name__ == "__main__":
    main()
