---
name: arcanium-playtest
description: "Come si lancia Arcanium da riga di comando senza rovinare i salvataggi dei test manuali, e come gira il playtest autonomo (Jev gioca, i sorveglianti segnalano, Claude conferma e corregge). Usare ogni volta che si avvia Godot fuori dall'editor su questo progetto — playtest, scenari, replay, cancelli verifica_*, catture, benchmark — o si tocca arcanium/tools/playtest/. Keywords: playtest, Jev, TypeSafe, APPDATA, user://, arcanium_save.cfg, salvataggio sovrascritto, ponte_playtest, replay, sorveglianti, scenari."
---

# Playtest di Arcanium

Il piano completo e lo stato dei lavori stanno in `docs/15_PLAYTEST_JEV.md`.
Qui restano le regole che si applicano a OGNI lancio.

## 1. Ogni Godot lanciato da uno strumento usa un APPDATA suo

`user://` su Windows e' `%APPDATA%\Godot\app_userdata\Arcanium`. Li' vivono il
salvataggio (`arcanium_save.cfg`) e le impostazioni (`arcanium_settings.cfg`)
dei **test manuali dell'utente**. Il gioco salva DA SOLO (autosave souls-like a
ogni Cono, a ogni flag di quest), quindi una partita automatica che attraversa
un Cono **sovrascrive il salvataggio dell'utente senza dirlo**, e
`begin_new_run()` lo cancella proprio.

Godot non ha un flag per la cartella utente, ma legge `APPDATA` dall'ambiente.
Verificato il 2026-10-07: con `APPDATA` puntato altrove `OS.get_user_data_dir()`
diventa `<APPDATA>/Godot/app_userdata/Arcanium` e il salvataggio vero non si vede.

```bash
# bash: la variabile vale solo per questo comando
APPDATA="C:\\Users\\Adriano\\LOCAL\\vaelthar_playtest\\appdata\\<nome>" \
  "/c/Godot/Godot_v4.7.1-stable_win64_console.exe" --path . ...
```

```powershell
# PowerShell: $env: resta nella sessione — si salva e si rimette
$vecchio = $env:APPDATA; $env:APPDATA = "C:\Users\Adriano\LOCAL\vaelthar_playtest\appdata\<nome>"
& "C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --path . ...
$env:APPDATA = $vecchio
```

```python
# Python (gioca.py fa cosi'): copia dell'ambiente, mai os.environ modificato
env = dict(os.environ, APPDATA=str(cartella_partita / "appdata"))
subprocess.Popen([godot, "--path", repo, ...], env=env)
```

- La cartella `arcanium_playtest/` sta FUORI dal repo (`C:\Users\Adriano\LOCAL\`).
- Un APPDATA per partita: ogni partita parte da un profilo vuoto, quindi da
  impostazioni di default e senza salvataggio — e' anche cio' che la rende
  ripetibile.
- **Seconda sicura nel codice:** `ponte_playtest.gd` controlla
  `OS.get_user_data_dir()` e, se e' quella vera di Roaming, si rifiuta di
  partire. Non toglierla.
- I cancelli `verifica_*` storici che toccano il salvataggio (`verifica_nuova_partita`,
  `verifica_baule`, `verifica_tomo`, `verifica_coni`) si fanno una copia e la
  rimettono: funziona, ma un crash a meta' lascia il salvataggio sbagliato.
  Lanciati da uno strumento, vanno comunque con un APPDATA isolato.

## 2. Le altre regole dei lanci

- Dopo ogni esecuzione: `git checkout project.godot` (Godot lo riscrive).
- Per catturare immagini serve il renderer vero: **niente `--headless`** (in
  headless il renderer e' fittizio e le catture escono vuote). Il banner deve
  dire `Vulkan ... Forward Mobile ... Radeon 890M`; non passare
  `--rendering-driver vulkan`, che fa ricadere su Forward+.
- Tempo deterministico: `--fixed-fps 60`. Cooldown e stordimenti contano i tick
  di fisica (`arcanium/systems/orologio_gioco.gd`), non il muro: niente
  `Time.get_ticks_msec()` nel codice di gioco nuovo.
- La chiave di TypeSafe sta nelle variabili UTENTE di Windows
  (`TYPESAFE_API_KEY`): un processo aperto prima che fosse registrata non la
  vede, e va letta con `[Environment]::GetEnvironmentVariable('TYPESAFE_API_KEY','User')`.
  Mai stamparla, mai committarla.
- Budget TypeSafe: 25 $ in tutto, stop e domanda prima di superare 2 $ in una
  sessione di lavoro; niente tempo reale senza ok esplicito dell'utente.

## 3. Il ciclo (fase 3): `ciclo.py`

```bash
python arcanium/tools/playtest/ciclo.py gioca [--finto] [--nome N]   # o: rigioca <cartella>, scenario <nome>
python arcanium/tools/playtest/ciclo.py referto <cartella>          # referto.md + referto.json
python arcanium/tools/playtest/ciclo.py giudica <cartella> C03 conferma --regressione NOME --nota "..."
python arcanium/tools/playtest/ciclo.py giudica <cartella> C04 scarta --causa evidenza|modello|codice|servizio
python arcanium/tools/playtest/ciclo.py baseline [scenario]         # telemetria d'oro + catture, fuori dal repo
python arcanium/tools/playtest/ciclo.py suite                       # stampa SOLO cio' che cambia
```

- Il referto raggruppa: stesso tipo + stesso soggetto entro 600 tick = un caso.
  Il canale visivo (FastFlowLM sulla NPU) risponde solo ai tipi che si vedono
  (`corpo_su_corpo`, `sotto_il_suolo`, `clip_vuota`) ed e' un INDIZIO.
- **Prima di giudicare, rileggere l'elenco dei casi.** I numeri sono stabili
  (contano anche i noti nascosti), ma il 2026-10-15 due giri di giudizi "a
  memoria" sono caduti sui casi sbagliati: il verdetto ora riporta il testo.
- Gli errori del log giudicati vanno in `arcanium/tools/playtest/noti.json` e
  spariscono dai referti successivi (si contano).
- Una regressione da PARTITA salva le azioni e 13 punti di controllo della
  telemetria fino al difetto. Se il replay diverge prima, l'esito e' **NON
  VALIDA**, non "passa": col gioco cambiato un replay di azioni prende
  un'altra strada (morso_sul_cadavere, 2026-10-15: divergeva al tick 625 e
  "passava" anche col difetto reintrodotto). Rimedio: rifarla come SCENARIO
  (`arcanium/tools/scenari/`), che monta la situazione e non dipende dalla
  strada. Prima di fidarsi di una regressione, provarla col difetto
  reintrodotto: deve fallire.
