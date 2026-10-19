# Vaelthar Tournament — Piano a fasi

> Stato: **v0.1, 2026-10-19**. Il design sta in `docs/16_GDD.md`.
> Si lavora per **rischio**: prima ciò che può affossare il progetto (il mobile), poi ciò che lo rende divertente (arene e ciclo), infine il contenuto.
> Ogni fase si chiude con un **cancello**: una verifica in `arcanium/tools/` più un render o una build **guardati**. Superare i test non basta.

## Regole che valgono in ogni fase

- Commit piccoli appena un pezzo sta in piedi, poi push su `main`. Mai `git add -A`: solo path espliciti.
- Ogni meccanica ha la sua verifica in `tools/`, e si guarda il render.
- **Tripo** si usa dalla web app nel Chrome dell'autore. Prompt e immagine si mostrano **prima** di spendere, e si scarica solo col suo permesso.
- Per ogni passo irreversibile (cancellare, riscrivere la storia, force push) si chiede prima.
- Ogni Godot lanciato da uno strumento ha un `APPDATA` isolato. Dopo un lancio headless si ripristina `project.godot`. Su un clone fresco l'import si fa dall'editor.
- Il contenuto nuovo nasce come **dati** (`.tres` in un catalogo), mai come casi speciali nel codice (GDD §12).

## Fase 0 — Nucleo estratto ✅ (2026-10-19)

Pulizia di Arcanium e primo commit del repo pubblico. Restano due cose da fare a mano:

- [ ] riavviare la sessione di Claude, così il server MCP del playtest punta alla copia;
- [ ] aprire il progetto nell'editor per l'import, e guardare il `battle_playground`.

## Fase 1 — Il telefono regge? *(rischio massimo)*

Lo scopo è capire **prima di costruire** se il combattimento di Arcanium gira su un telefono.

1. Preset di export Android e iOS. Pipeline **GitHub Actions** con runner macOS, che dà la build iOS su **TestFlight**. Serve l'account Apple Developer.
2. Build di `arena_branco` (giocatore e branco) su un telefono vero, in tre misure: fps, tempo di frame, temperatura dopo 10 minuti.
3. Misura della **stoffa simulata in GPU** e dei protagonisti da 120k triangoli: costo con e senza, con i LOD di Godot.
4. Opzione 30/60 fps nel menu, e preset di qualità.
5. Prima versione del **pad touch** a tasti graduati: lo stick, i tasti grandi per attacco, schivata, pesante e incantesimo, i minori più piccoli. Deve funzionare anche col gamepad collegato al telefono.
6. Riscrivere `docs/02_PLATFORM_STRATEGY.md` per mobile e Steam.

**Cancello:** 30 fps stabili sul dispositivo minimo (iPhone 11 o un Android medio del 2021) per 10 minuti, nell'arena col branco. Più un video del pad touch giocato dall'autore. Se non regge, si decide **qui** cosa tagliare (stoffa, ombre, polycount), non dopo.

## Fase 2 — Arene verticali, spinta, caduta

1. **Decisione APERTA da prendere all'inizio:** come si generano le arene, cioè moduli montati a caso oppure stanze intere con varianti. La proposta si fa con un prototipo per ciascun metodo, da guardare.
2. Dislivelli, rampe, piattaforme, almeno un'arena multilivello. Camera isometrica e lock-on devono reggere i piani diversi.
3. **Baratri:**
   - il giocatore che cade perde il match;
   - il nemico che cade muore;
   - verifiche in stile `verifica_danno_caduta.gd`.
4. **Spinta per peso:** il `peso` del nemico entra nella spinta di `arcanium_enemy.gd`, che oggi ha un decadimento fisso. Spingono gli attacchi pesanti, mazze, scudo e alcuni incantesimi.
5. **Porte e trappole** come pezzi riusabili (per esempio piastre, lame, spine e radici per Kalvorn).
6. Le arene diventano dati: un catalogo per territorio.

**Cancello:** cinque arene di Kalvorn guardate in render. Più due scenari di playtest: «spingo un lupo nel baratro» e «cado e perdo il match».

## Fase 3 — Il ciclo della run

1. `RunState` (autoload): seme, campione, territori pescati, tappa, sconfitte (al massimo 3), Arcanium e mucchio perso, potenziamenti. Si salva **tra un match e l'altro**, con suspend e resume per mobile e per la certificazione delle console.
2. **Generatore dell'albero** di un territorio: 5 piani, 2–3 corsie, tipi di nodo come dati. Più la UI della mappa, a tocchi e a gamepad.
3. Il flusso del match:
   - entra nell'arena;
   - se vinci: taglia, poi banco, poi mappa;
   - se perdi: perdita dell'Arcanium, scelta del perk, rivincita.
4. La **regola souls** in `crystal_bank.gd`, che oggi toglie il 50% alla morte.
5. Fine run: eliminazione dopo 3 sconfitte, oppure vittoria col 4° boss e la scena della gemma (per ora un segnaposto).

**Cancello:** uno scenario di playtest che attraversa un territorio intero con mob segnaposto. Deve contenere due sconfitte, una rivincita vinta e una persa, e verificare il saldo dell'Arcanium a ogni passo.

## Fase 4 — Crescita nella run

1. **Banco di fine match:** 3 offerte, rarità legate al nodo, prezzi per tappa.
2. **Famiglie di danno** con soglie 2/4/6: per la slice **Crio** (l'affinità di Dawnkeep) e **una seconda famiglia**. **APERTO:** quale.
3. **Marche:** nuova curva per un endgame dopo circa 20 scontri, al posto di quella da souls a tre cicli.
4. Gli altri nodi: Mercante (oggetti, rimozione, rilancio), Tesoro, Riposo, Imprevisto (2–3 eventi per la slice).
5. **Perk della rivincita**: 4–6 per la slice.
6. **Bestiario a scoperta**: le schede si riempiono quando un tipo di danno viene provato davvero (il segnale `damage_dealt` esiste già).

**Cancello:** un giocatore finto completa 10 run simulate, e un rapporto mostra che la potenza a metà e a fine territorio sta dentro una forbice decisa prima. Più una run giocata dall'autore.

## Fase 5 — Il battleground

1. Schieramento in N slot, con le truppe come dati.
2. IA delle armate: si parte dalle evocazioni (`arcanium/systems/summons/`) e dall'ordine del Comandante.
3. 2–3 incantesimi dall'alto con ricarica, a tocchi.
4. Esercito nemico nascosto e rivelabile a pagamento. Bonus casata.
5. Le truppe Dawnkeep: Sentinella del Passo (esiste già), **Custode Glaciale** e **Lama del Vento Polare** (da fare con Tripo).
6. Prestazioni: quante unità reggono sul dispositivo minimo. Misura **prima** di fissare la dimensione delle squadre.

**Cancello:** un battleground 3 contro 3 squadre a 30 fps sul dispositivo minimo, guardato. Più una verifica che il bonus casata si attivi solo con le 3 truppe base.

## Fase 6 — Kalvorn e Vyrath

1. Il roster di Kalvorn: i mob pronti, distribuiti fra scontri ed élite, con pesi, resistenze e taglie.
2. **Vyrath:**
   - concept, poi Tripo (mostrato prima di spendere);
   - poi ARP e Cascadeur;
   - le mosse partono dalle radici e dalle Eco già fatte.
3. Bilanciamento della regione e direzione artistica delle arene di Kalvorn.
4. Audio della regione.

**Cancello:** Vyrath battuto dall'autore su telefono, e il bestiario della regione completo.

## Fase 7 — Slice, demo Steam, pagina Steam

1. Rifinitura: menu, tutorial leggero, opzioni, salvataggio robusto.
2. La pagina Steam e la **demo** (Dawnkeep e Kalvorn). Lo Steam Next Fest si sceglie in base alla data.
3. Trailer dalla demo.
4. Playtest esterni: pochi giocatori, osservati.

**Cancello:** la demo pubblicata e le prime wishlist.

## Fase 8 — Produzione fino al lancio

Si ripete per ogni territorio quello che la fase 6 ha insegnato. Per ciascuno: roster, boss, arene, campione, 3 truppe e una famiglia di danno.

- I **3 campioni donna** richiedono un corpo femminile sullo scheletro unico. Va affrontato **presto** in questa fase, perché è un rischio di pipeline.
- **Meta:** Fama, sblocchi del pool, bonus con tetto, estrazione dei campioni, le gemme e il Grande Portale.
- **Finale:** l'Ispettore Primo e lo Sha-Des nella dimensione oscura.
- Gradi di sfida.
- Lancio insieme su **iOS, Android e Steam**, a circa 7 €.

## Dopo il lancio

- Sfide giornaliere, che richiedono un server per le classifiche.
- Patch gratuite con contenuto nuovo.
- DLC corposi, per esempio la modalità skirmish.
- Console tramite porting house.

## Decisioni APERTE

Si prendono quando la fase le incontra, una alla volta, con l'autore.

| Decisione | Fase |
|---|---|
| Metodo di generazione delle arene | 2 |
| Seconda famiglia di danno della slice | 4 |
| Elenco dei perk della rivincita, eventi degli Imprevisti | 4 |
| Numeri della Fama e dei bonus permanenti | 8 |
| Uomini e donne fra i campioni, nomi, abilità di casata | 8 |
| Roster dei territori oltre Kalvorn (circa 30 mob in tutto) | 8 |
| Chi è lo Sha-Des finale; il Grande Portale nel lore | 8 |
