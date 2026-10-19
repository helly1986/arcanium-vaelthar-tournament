# Playtest autonomo — Jev gioca, Claude sistema

> Avviato il **2026-10-07**. Le regole operative di ogni lancio (APPDATA isolato,
> renderer, tempo deterministico, budget) stanno nella skill
> `.claude/skills/arcanium-playtest/SKILL.md`. Questo documento dice **cosa
> fa la pipeline, cosa e' stato misurato e a che punto e'**.

## ⚠️ Prima di tutto: i salvataggi dei test manuali

Il gioco salva da solo (a ogni Cono, a ogni flag di quest) in
`%APPDATA%\Godot\app_userdata\Arcanium\arcanium_save.cfg`, che e' anche dove
l'utente tiene i suoi test manuali. Una partita automatica lanciata come il
gioco normale **lo sovrascrive senza avvisare**.

Regola: **ogni Godot lanciato da uno strumento parte con `APPDATA` puntato a
una cartella sua**, sotto `C:\Users\Adriano\LOCAL\vaelthar_playtest\` (fuori
dal repo). Godot non ha un flag per la cartella utente ma legge `APPDATA`:
verificato il 2026-10-07, con `APPDATA` altrove il salvataggio vero non si vede.
Il ponte, in piu', si rifiuta di partire se trova la cartella utente vera.
Comandi pronti per bash, PowerShell e Python nella skill.

## L'idea

| Chi | Fa | Non fa |
|---|---|---|
| **Jev** (TypeSafe, `jev-1.13.0`) | sceglie l'azione (Choice) e risponde ai sorveglianti (Noul, Score) leggendo lo stato in parole | non vede immagini, non scrive referti, non ha l'ultima parola |
| **Sorveglianti** (GDScript, nel gioco) | controlli deterministici a ogni tick: bloccato, sotto il suolo, corpo su corpo, danno senza sorgente, nemico inerte, softlock, errori nel log | — |
| **Canale visivo** (locale) | guarda solo i momenti segnalati: domande strette, una per difetto | "trova i difetti" generico: non funziona (misurato) |
| **Claude** | conferma guardando fotogrammi e telemetria, corregge, trasforma la partita in regressione | — |

## Cosa e' stato misurato (fase 0)

- **Jev**: mediana **370 ms** a richiesta da qui (325–469, 10 chiamate), 1.275
  token per uno stato di combattimento con 1 Choice + 6 Noul + 1 Score =
  **0,000054 $**. Gioca a Doom solo con navigazione, piano e riflessi scritti
  in codice: il codice porta, Jev sceglie la tattica.
- **Godot fuori headless**: Forward Mobile sulla 890M, Traccia caricata in 2,2 s,
  59 fps con `--fixed-fps 60`, catture piene a 1920×1080.
- **NPU** (FastFlowLM 1.0.7, Qwen3-VL-4B): ~10 s per fotogramma 720p. Con la
  domanda aperta "trova difetti di rendering" ha mancato una roccia tutta
  magenta 4 volte su 4, con "confidenza 1.0"; con "c'e' un oggetto magenta?"
  la trova. Quindi: domande strette, e il magenta si conta in codice.
- **Orologio**: cooldown e stordimenti usavano `Time.get_ticks_msec()`, che
  corre anche col mondo fermo. Ora contano i tick (`orologio_gioco.gd`).

## Il primo percorso

La Traccia Perduta, dall'ingresso all'Alpha: una linea quasi dritta lungo −Z
(da z=16 a z=−208), 9 trigger di tratto, 2 Coni, 8 nemici, Maestro a z=−160,
Alpha a z=−190, barriera a z=−208.

⚠️ Il "lupo in groppa" e' **ancora vivo sulla Traccia**: `_on_alpha_howl` del
director fa `add_child` e poi `global_position`. Il fix c'e' solo in
`richiamo_branco.gd` (Kalvorn). Lasciato apposta come prima cattura vera
della pipeline, da correggere dopo.

## Fase 1 — cosa e' stato misurato (2026-10-07)

**Il ponte.** `arcanium/tools/playtest/`: autoload `PontePlaytest` (spento
senza `-- --playtest`), `gioca.py` lo lancia e parla con Jev. Replay
**identico**: stessa impronta MD5 su 10.234 tick di telemetria, rigiocando
le azioni registrate senza nessun giocatore.

**La prima partita di Jev** (`jev_traccia_1`, seme 1): Traccia attraversata
fino all'arena in **45,75 s di gioco** (il giocatore finto a regola fissa
ci aveva messo 108 s), poi **5 morti contro l'Alpha**, mai abbattuto.
1.320 chiamate, ~2.000 token l'una, **0,11 $**, latenza mediana 277 ms
(p95 396 ms), nessun errore del servizio. **629 s di muro per 189 s di
gioco.** Gioca troppo in difesa: 757 fra schivate e passi indietro, 91
attacchi; la confidenza mediana della Choice e' 0,57.

**I Noul su condizioni letterali non funzionano.** Misurati contro la verita'
ricavabile dallo stato stesso, su 1.320 risposte: "nemico vicino che non
attacca" ≥0,8 vero nello 0% dei casi (38), "colpo senza aggressore" ≥0,8
vero nel 3% (61). Jev tratta "close" come "very close", mescola le
condizioni di nemici diversi della lista, ignora "just now" contro "a
moment ago". Sono condizioni che il CODICE calcola esattamente: restano ai
sorveglianti, e a Jev si chiedono solo giudizi di significato.

**Difetti veri trovati:**
1. i lupi mordevano il CADAVERE e ogni morso rimandava `death_started`
   (tre "morti" in 2,7 s) — corretto in `player_charbody3D.gd`, `hit()`;
   regressione: rigiocata la partita, identica fino al tick 7501, poi gli HP
   restano fermi e il sorvegliante "morte ripetuta" tace;
2. il SALTO dell'Alpha (`LEAP`, `move_range = 12.64`) colpisce da dove e'
   partito, non da dove atterra: 28 HP tolti col lupo a 6,8 m, confermato sul
   fotogramma. `_apply_hit` usa la portata della mossa anche come portata
   del colpo. Da correggere;
3. un colpo arriva nel tick esatto della RINASCITA (5 rinascite su 5, Alpha
   e lupi comuni), senza danno netto. Da chiarire con la nuova telemetria.

## Fase 2 — cosa e' stato misurato (2026-10-07)

**Scenari** (`arcanium/tools/scenari/`, girano dentro il ponte, con etichette
di verita'): `ululato_traccia`, `ululato_corpo_in_origine`, `colpi_lupi`,
`difetti_visivi`. Server MCP `arcanium-playtest` (`server_mcp.py`, registrato
in `.mcp.json`): gioca, rigioca, scenari, giudizi di stato e di fotogramma.

**Seconda partita di Jev** (stato con le tre fasi del colpo, verso del player,
obiettivo "combatti"): attacchi dal 7% al **23%** delle scelte, Alpha portato a
meta' salute (prima mai sotto "high"), ancora 5 morti; 1.352 chiamate,
0,117 $, mediana 275 ms. Colpi del player: angolo mediano 20°, 1 su 55 oltre
90° (a 1,5 m).

**Calibrazione dei canali.**
- Jev, Choice: rovesciando l'ordine delle opzioni la scelta resta la stessa
  nell'86% dei casi; cambia solo dove Jev era gia' indeciso.
- Jev, Noul di coerenza animazione PER NEMICO (60 positivi costruiti + 60
  negativi certi): soglia 0,5 → 60/60, zero falsi allarmi. Probabilita'
  prudenti (fascia 0,6–0,8 vera al 100%). Contraddizioni nette: quelle sottili
  restano da misurare.
- Canale visivo, Qwen3-VL-4B sulla NPU, una domanda stretta per difetto, 39
  immagini × 6 domande: magenta 3/3 (ma 2 falsi allarmi sui lupi viola del
  Branco Guasto), T-pose 2/3, in groppa 1/3, z-fighting 1/3, affondato 0/3,
  dentro una roccia 0/3. 5,3 s a domanda. Utile come indizio, non come
  sorvegliante.
- Clef-Flash non si carica su Ollama 0.40.0 ("pooling_type"): da riprovare.
- Sorveglianti sul set visivo: "affondato" preso; "in groppa" mancato coi
  corpi congelati, da cui il controllo geometrico.

**Difetti nuovi:**
4. i MORSI dell'Alpha (W1/W2, portata 4,33/4,69 m) entrano fino a 3,3 m col
   muso a un metro dal player, confermato sui fotogrammi: dati, non animazioni.
   Proposta, non applicata (difficolta' del boss; .tres che l'editor riscrive);
5. `_find_critical_target` sceglie il bersaglio del critico solo per distanza,
   senza guardare il verso del player.

Il "danno nel tick della rinascita" della fase 1 era un falso allarme del
sorvegliante (confrontava l'autore col player gia' teletrasportato): corretto.
Il "lupo in groppa" sulla Traccia e' latente e non si riproduce.

I difetti 4 e 5 sono corretti il 2026-10-15: `portata_colpo` nelle mosse (il
morso dell'Alpha prende quando arriva il muso, 1,31 m davanti al centro: nello
scenario i morsi oltre 2,5 m passano da 5 a 0) e il cono davanti al player per
critico e backstab (`verifica_finisher_verso.gd`).

## Fase 3 — cosa e' stato misurato (2026-10-15)

Un comando, `arcanium/tools/playtest/ciclo.py` (uso nella skill
arcanium-playtest): gioca/rigioca/scenario → referto → giudica → regressione;
baseline e suite.

- **Referto**: solo i casi da guardare. La prima partita di Jev (fase 1) da' 20
  casi invece di centinaia di righe (il Noul "colpito senza attaccante" 31 + 20
  volte = 2 casi); la seconda da' 0 casi dopo aver giudicato i 5 errori d'avvio,
  ora in `noti.json` (4 noti, 1 rumore del ponte; i bind `head_end`/`headfront`
  dello skin del lupo restano un difetto vero).
- **Regressioni**: la prima, nata dalla partita che aveva trovato il morso sul
  cadavere, **passava anche col difetto reintrodotto**: il replay di azioni del
  7 ottobre, sul gioco di oggi, diverge al tick 625 e non arriva mai nell'arena
  (il difetto era al 7493). Da qui i punti di controllo (13 per regressione):
  se il replay diverge prima del difetto l'esito e' NON VALIDA. La regressione
  vera e' lo scenario `cadavere_morso`: con la correzione nessuna segnalazione,
  senza "morte ripetuta" al tick 273. **Una regressione si prova col difetto
  reintrodotto prima di fidarsene.**
- **Baseline e suite**: 5 scenari + 1 regressione in **155 s**. Sullo stesso
  codice 99 immagini confrontate, SSIM minimo 0,991 (soglia 0,90): niente
  cambiato. Col morso del lupo rifatto la suite ha segnalato solo cio' che
  doveva: telemetrie dal primo W1, le tre viste della cattura del W1 (SSIM
  0,52–0,70), il secondo W1 un tick prima; `difetti_visivi` identico.
- Costo TypeSafe della fase: 0 $ (tutto su partite e scenari esistenti).

## Stato

- [x] Fase 0 — ricognizione
- [x] Fase 1 — ponte Jev ↔ Godot, modalita' discreta, replay, sorveglianti
- [x] Fase 2 — scenari mirati, Noul tarati, canale visivo, server MCP
- [ ] Fase 3 — ciclo e regressione fatti; manca la dimostrazione del lupo in
      groppa (alla cieca: lo reintroduce l'utente nel richiamo dell'Alpha
      della Traccia, Jev ci gioca sopra)
- [ ] Fase 4 — tempo reale (solo con l'ok dell'utente)
