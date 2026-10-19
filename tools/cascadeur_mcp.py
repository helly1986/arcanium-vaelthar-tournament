"""Ponte verso il server MCP di Cascadeur, usabile da riga di comando.

Cascadeur 2026.2 espone UN SOLO tool MCP, `run_script`: esegue Python dentro
Cascadeur al prossimo evento di idle della scena. Tutto ciò che si vuole fare
passa di lì — non esistono tool specializzati.

Serve finché il server MCP non è agganciato alla sessione: permette comunque di
interrogarlo e pilotarlo.

    python tools/cascadeur_mcp.py script.py     # esegue un file
    python tools/cascadeur_mcp.py -c "codice"   # esegue una stringa
    python tools/cascadeur_mcp.py --info        # server, moduli, risorse

⚠️ Il server va acceso a mano in Cascadeur (Script → MCP → Start MCP) a ogni
avvio del programma, e non dà nessun riscontro a schermo: si verifica che sia su
con `Get-NetTCPConnection -LocalPort 8765`.
"""

import json
import sys
import urllib.request

URL = "http://127.0.0.1:8765/mcp"
_sessione = None


def rpc(metodo, parametri=None, id_=1, notifica=False, timeout=120):
    global _sessione
    d = {"jsonrpc": "2.0", "method": metodo}
    if not notifica:
        d["id"] = id_
    if parametri is not None:
        d["params"] = parametri
    intestazioni = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    if _sessione:
        intestazioni["Mcp-Session-Id"] = _sessione
    richiesta = urllib.request.Request(
        URL, data=json.dumps(d).encode("utf-8"), headers=intestazioni
    )
    with urllib.request.urlopen(richiesta, timeout=timeout) as risposta:
        s = risposta.headers.get("Mcp-Session-Id")
        if s:
            _sessione = s
        grezzo = risposta.read().decode("utf-8", "replace")
    if notifica or not grezzo.strip():
        return None
    # il server può rispondere in SSE oppure in JSON semplice
    for riga in grezzo.splitlines():
        if riga.startswith("data:"):
            return json.loads(riga[5:].strip())
    return json.loads(grezzo)


def connetti():
    r = rpc(
        "initialize",
        {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "arcanium", "version": "1"},
        },
    )
    try:
        rpc("notifications/initialized", None, notifica=True)
    except Exception:
        pass
    return r.get("result", {})


def esegui(codice, timeout=120):
    """Esegue codice Python dentro Cascadeur e restituisce l'output testuale.

    ⚠️ Uno script lungo puo' far cadere la connessione (`RemoteDisconnected`)
    mentre Cascadeur continua a lavorare: NON e' un fallimento, e ripetere la
    chiamata puo' rifare il lavoro una seconda volta. Chi scrive nella scena
    deve poterlo fare due volte senza raddoppiare l'effetto.
    """
    r = rpc("tools/call", {"name": "run_script", "arguments": {"code": codice}}, 3,
            timeout=timeout)
    if "error" in r:
        return "ERRORE MCP: " + json.dumps(r["error"])
    pezzi = []
    for c in r.get("result", {}).get("content", []):
        if c.get("type") == "text":
            pezzi.append(c["text"])
    return "\n".join(pezzi)


def leggi_risorsa(uri):
    r = rpc("resources/read", {"uri": uri}, 4)
    c = r.get("result", {}).get("contents", [])
    return c[0].get("text", "") if c else ""


def main(argv):
    timeout = 120
    resto = []
    for a in argv:
        if a.startswith("--timeout="):
            timeout = float(a.split("=", 1)[1])
        else:
            resto.append(a)
    argv = resto
    info = connetti()
    if not argv or argv[0] == "--info":
        print("server:", json.dumps(info.get("serverInfo", {})))
        print("capacita:", json.dumps(info.get("capabilities", {})))
        t = rpc("tools/list", {}, 2).get("result", {}).get("tools", [])
        print("tool:", [x["name"] for x in t])
        r = rpc("resources/list", {}, 5).get("result", {}).get("resources", [])
        print("risorse:", [x["uri"] for x in r])
        return 0
    if argv[0] == "-c":
        print(esegui(argv[1], timeout))
    elif argv[0] == "--risorsa":
        print(leggi_risorsa(argv[1]))
    else:
        print(esegui(open(argv[0], encoding="utf-8").read(), timeout))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
