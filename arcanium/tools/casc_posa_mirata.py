# -*- coding: utf-8 -*-
"""Costruisce una posa in Cascadeur dicendo DOVE PUNTA ogni osso nel mondo.

Da eseguire DENTRO Cascadeur, tramite il ponte:

    python tools/cascadeur_mcp.py arcanium/tools/casc_posa_mirata.py

La posa si scrive in `lavorazione/cascadeur/posa.json`, non qui dentro: cosi' si
itera guardando i provini senza toccare il codice.

═══════════════════════════════════════════════════════════════════════════
PERCHE' NON SI SCRIVONO I QUATERNIONI LOCALI A MANO
═══════════════════════════════════════════════════════════════════════════

Un quaternione locale non dice niente a nessuno: dipende dagli assi di riposo di
QUELL'osso in QUEL rig, che nel pack dei nemici non sono ne' allineati al mondo
ne' uguali fra un osso e l'altro. Scrivere «l'avambraccio sinistro attraversa il
petto» come quaternione vuol dire indovinare e rendere, indovinare e rendere.

Qui si dichiara invece una cosa che si puo' DISEGNARE su un foglio: la direzione
nel mondo verso cui l'osso deve puntare il proprio figlio. Il personaggio guarda
+Z, ha l'alto in +Y, e la sua sinistra e' +X (misurato: `Hand_L` sta a x=+44,6 e
`Hand_R` a x=-45,8). Quindi «avambraccio che attraversa il petto in avanti» e'
`[-0.55, 0.35, 0.75]`, e si legge.

⚠️ La MIRA non sa fare la TORSIONE. Puntare il figlio da qualche parte lascia
libera la rotazione attorno all'osso stesso: per il busto che si mette di taglio,
o per il polso che gira lo scudo, serve `delta`, che moltiplica una rotazione
esplicita attorno a un asse del mondo.

═══════════════════════════════════════════════════════════════════════════
LA CATENA DI CONVERSIONE, E PERCHE' NON SERVE SAPERE CHI E' IL PADRE
═══════════════════════════════════════════════════════════════════════════

Si scrive `Local Rotation`, ma si ragiona in globale. Il passaggio ha bisogno
della rotazione globale del PADRE, che non si va a cercare nella gerarchia — si
ricava dai due canali che l'osso ha gia' addosso:

    R_padre = R_globale @ R_locale⁻¹

Cosi' il tool non ha una tabella di parentele da tenere aggiornata, e funziona
identico sul rig del protagonista e su quello del pack.

⚠️ UN OSSO PER SESSIONE, e in ordine dal bacino alle estremita'. Muovere una
spalla sposta anche mano e dita: se si calcolassero tutte le mire sulla stessa
lettura, ogni osso a valle mirerebbe da un posto in cui non si trova piu'.
`modify_update_with_session` ricalcola la scena fra un osso e l'altro — ed e'
`_update_` che ricalcola: `modify_with_session` scrive e basta.

═══════════════════════════════════════════════════════════════════════════
⚠️⚠️ PERCHE' C'E' UNA POSA DI PARTENZA SALVATA SU FILE
═══════════════════════════════════════════════════════════════════════════

Autorare vuol dire ripetere: applica, rendi, guarda, correggi di cinque gradi,
riapplica. Ma una `mira` e una `delta` non si comportano allo stesso modo se
rilanciate sulla scena gia' posata — la mira e' assoluta e ridarebbe lo stesso
risultato, la **delta MOLTIPLICA**, e un secondo giro raddoppia l'angolo.

E il secondo giro non e' un'ipotesi: il ponte cade con `RemoteDisconnected`
mentre Cascadeur sta ancora lavorando, quindi capita di rilanciare uno script
che aveva gia' scritto. E' successo al primo tentativo di questa posa.

Percio' la prima esecuzione registra la `Local Rotation` INTATTA di ogni osso
toccato in `posa_base.json`, e ogni esecuzione successiva riparte da li'. Il
tool diventa idempotente: lanciarlo dieci volte da' la stessa posa di lanciarlo
una volta.

⚠️ Il file di partenza vale per QUELLA clip in QUELLA scena. Quando si cambia
clip di base va cancellato, o si posa un gesto sui riferimenti di un altro.
"""

import json
import traceback

import numpy as np

import csc

POSA = r"C:\Users\Adriano\LOCAL\arcanium---vaelthar-tournament\lavorazione\cascadeur\posa.json"
BASE = r"C:\Users\Adriano\LOCAL\arcanium---vaelthar-tournament\lavorazione\cascadeur\posa_base.json"


class Fermata(Exception):
    """Errore da riportare al chiamante SENZA far cadere il ponte.

    ⚠️ `raise SystemExit(...)` dentro uno script del ponte MCP NON arriva a chi
    ha chiamato: il server prova a costruire la risposta, va in `KeyError: 'ok'`
    e CHIUDE la connessione. Chi guarda da fuori vede `RemoteDisconnected` e
    conclude che Cascadeur e' morto — e Cascadeur sta benissimo, il messaggio
    utile e' finito solo nel `cascadeur_log.log`. Costato due diagnosi sbagliate.
    """


def _log(*a):
    print("[posa]", *a)


def _mat(rot):
    return np.array(rot.to_rotation_matrix(), dtype=float).reshape(3, 3)


def _rot(m):
    return csc.math.Rotation.from_rotation_matrix(m.tolist())


def _da_asse_angolo(asse, gradi):
    a = np.array(asse, dtype=float)
    a = a / np.linalg.norm(a)
    t = np.radians(float(gradi))
    x, y, z = a
    c, s, u = np.cos(t), np.sin(t), 1.0 - np.cos(t)
    return np.array([
        [c + x * x * u,     x * y * u - z * s, x * z * u + y * s],
        [y * x * u + z * s, c + y * y * u,     y * z * u - x * s],
        [z * x * u - y * s, z * y * u + x * s, c + z * z * u],
    ])


def _fra_versori(d, t):
    """Rotazione minima che porta la direzione d sulla direzione t."""
    d = d / np.linalg.norm(d)
    t = t / np.linalg.norm(t)
    asse = np.cross(d, t)
    sin = float(np.linalg.norm(asse))
    cos = float(np.dot(d, t))
    if sin < 1e-9:
        if cos > 0.0:
            return np.eye(3)
        perp = np.array([0.0, 1.0, 0.0]) if abs(d[0]) > 0.9 else np.array([1.0, 0.0, 0.0])
        return _da_asse_angolo(np.cross(d, perp), 180.0)
    return _da_asse_angolo(asse, np.degrees(np.arctan2(sin, cos)))


class Scena(object):
    def __init__(self):
        app = csc.app.get_application()
        self.ds = app.current_scene().domain_scene()
        self.mv = self.ds.model_viewer()
        self.dv = self.mv.data_viewer()
        self.giunti = {self.mv.get_object_name(o): o for o in self.mv.get_objects()
                       if self.mv.get_object_type_name(o) == "Joint"}
        self.lv = self.ds.layers_viewer()
        self._canali = {}

    def canale(self, osso, nome):
        chiave = (osso, nome)
        if chiave not in self._canali:
            o = self.giunti[osso]
            self._canali[chiave] = {self.dv.get_data_name(i): i
                                    for i in self.dv.get_all_data_id(o)}[nome]
        return self._canali[chiave]

    def posizione(self, osso, f):
        return np.array(self.dv.get_data_value(self.canale(osso, "Position"), f),
                        dtype=float)

    def globale(self, osso, f):
        return _mat(self.dv.get_data_value(self.canale(osso, "Rotation"), f))

    def locale(self, osso, f):
        return _mat(self.dv.get_data_value(self.canale(osso, "Local Rotation"), f))

    def scrivi_locale(self, osso, frames, matrici):
        """Una sessione, un osso. Ritorna False se la sessione e' esplosa."""
        did = self.canale(osso, "Local Rotation")
        lid = self.lv.layer_id_by_obj_id(self.giunti[osso])
        valori = dict(zip(frames, [_rot(m) for m in matrici]))

        def scrivi(me, update, scene, session):
            le = me.layers_editor()
            de = me.data_editor()
            for f in frames:
                le.set_fixed_interpolation_or_key_if_need(lid, f, True)
                de.set_data_value(did, f, valori[f])

        return self.ds.modify_update_with_session("posa " + osso, scrivi)


def _riporta_alla_partenza(sc, spec, frames):
    """Rimette le `Local Rotation` di partenza, registrandole la prima volta.

    E' cio' che rende il tool ripetibile: si posa sempre sopra lo stesso gesto,
    non sopra il risultato del giro precedente.
    """
    ossa = [v["osso"] for v in spec["ossa"]]
    try:
        with open(BASE, encoding="utf-8") as f:
            base = json.load(f)
    except IOError:
        base = {}

    nuovi = [o for o in ossa if o not in base]
    if nuovi:
        for osso in nuovi:
            base[osso] = {str(f): sc.locale(osso, f).tolist() for f in frames}
        with open(BASE, "w", encoding="utf-8") as f:
            json.dump(base, f, indent=1)
        _log("posa di partenza registrata per %d ossa nuove" % len(nuovi))
        return

    for osso in ossa:
        salvate = base[osso]
        if any(str(f) not in salvate for f in frames):
            raise Fermata(
                "%s: la posa di partenza non copre i frame chiesti. Cancella %s "
                "e rilancia su una scena appena importata." % (osso, BASE))
        sc.scrivi_locale(osso, frames,
                         [np.array(salvate[str(f)], dtype=float) for f in frames])
    _log("riportate alla partenza %d ossa" % len(ossa))


def applica(spec):
    sc = Scena()
    frames = list(spec["frames"])
    n_frame = sc.dv.get_animation_size()
    for f in frames:
        if not (0 <= f < n_frame):
            raise Fermata("frame %d fuori dalla clip (0..%d)" % (f, n_frame - 1))

    _riporta_alla_partenza(sc, spec, frames)

    for voce in spec["ossa"]:
        osso = voce["osso"]
        if osso not in sc.giunti:
            raise Fermata("osso assente dalla scena: %s" % osso)
        nuove = []
        for f in frames:
            g = sc.globale(osso, f)
            loc = sc.locale(osso, f)
            padre = g @ loc.T
            if "mira" in voce:
                figlio = voce["mira"]
                d = sc.posizione(figlio, f) - sc.posizione(osso, f)
                if np.linalg.norm(d) < 1e-6:
                    raise Fermata(
                        "%s e %s sono nello stesso punto: e' un osso di lunghezza "
                        "zero e la mira non ha un verso" % (osso, figlio))
                delta = _fra_versori(d, np.array(voce["verso"], dtype=float))
            else:
                delta = _da_asse_angolo(voce["delta"]["asse"], voce["delta"]["gradi"])
            nuove.append(padre.T @ (delta @ g))
        if not sc.scrivi_locale(osso, frames, nuove):
            raise Fermata("la sessione su %s e' fallita (guarda cascadeur_log.log)"
                             % osso)

        # ⚠️ Il ritorno True della sessione NON e' una conferma: si RILEGGE.
        f0 = frames[0]
        if "mira" in voce:
            d = sc.posizione(voce["mira"], f0) - sc.posizione(osso, f0)
            d = d / np.linalg.norm(d)
            t = np.array(voce["verso"], dtype=float)
            t = t / np.linalg.norm(t)
            scarto = np.degrees(np.arccos(np.clip(float(np.dot(d, t)), -1.0, 1.0)))
            _log("%-14s mira %-18s scarto residuo %.2f gradi"
                 % (osso, voce["mira"], scarto))
            if scarto > 1.0:
                raise Fermata("%s non ha mirato dove doveva (%.2f gradi)"
                                 % (osso, scarto))
        else:
            _log("%-14s delta %s gradi attorno a %s"
                 % (osso, voce["delta"]["gradi"], voce["delta"]["asse"]))
    _log("posa applicata: %d ossa su %d frame" % (len(spec["ossa"]), len(frames)))


try:
    with open(POSA, encoding="utf-8") as _f:
        _spec = json.load(_f)
    applica(_spec)
except Exception:
    print("ECCEZIONE:\n" + traceback.format_exc())
