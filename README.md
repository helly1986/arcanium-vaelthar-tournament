# Arcanium: Vaelthar Tournament

Roguelike soulslike piccolo, ambientato nel mondo di **Arcanium**: il Grande Torneo
delle sei casate nell'Arena Arcana di Valdris. Mappa di run ad albero di incontri
(fight, elite, boss, battleground), piccole arene generate, potenziamenti che si
accumulano vincendo, eserciti evocati che combattono da soli nei battleground.
Piattaforme: iPhone e Android (touch e gamepad), poi PC e console.

**Stato:** nucleo estratto da Arcanium (ottobre 2026). Il design e' in
`docs/16_GDD.md`, il piano di lavoro in `docs/17_PIANO_FASI.md`: si parte dalla
Fase 1, cioe' dal capire se il combattimento regge su un telefono.

## Cosa c'e'

| Area | Dove |
|---|---|
| Giocatore: movimento, combattimento, AnimationTree, lock-on | `player/`, `characters/player_dawnkeep_v4.tscn`, `docs/02_ANIMTREE_MAP.md` |
| Camera isometrica | `cameras/iso_cam/` |
| Nemici: base, umanoidi, quadrupedi, boss, distanza, mago, eco, ordine del Comandante, richiamo del branco | `arcanium/systems/enemies/`, `arcanium/characters/`, move set in `arcanium/resources/enemies/` |
| Mob pronti | lupi (comune, capobranco, Alpha), Consumato, Fante, Fante con spadone, Soldato Scelto, Mago, Comandante, Eco Radicata Guasta, Senza Nome (boss) |
| Stati, salute, Arcanium, cristalli, Marche | `arcanium/systems/status/`, `arcanium_health_system.gd`, `crystal_*.gd`, `marche_progression.gd` |
| Incantesimi ed evocazioni | `arcanium/systems/spells/`, `arcanium/systems/summons/` |
| Equipaggiamento e casate | `equipment_loadout.gd`, `house_catalog.gd` |
| HUD e barra del boss | `arcanium/ui/hud/` |
| Clip e librerie d'animazione | `assets/characters/anims*` (bone map nei `.import`) |
| Arene | `arcanium/levels/arena_builder.gd` (arena 40x40 a runtime) |

## Dove si prova

- `arcanium/levels/battle_playground.tscn` — il boss a comando (F1..F9), evocazioni sbloccate.
- `arcanium/levels/arena_branco.tscn` — l'Alpha e due lupi: ci girano gli scenari del playtest.
- `arcanium/levels/arena_prova.tscn` — l'arena col solo giocatore: i cancelli dei mob ci fanno nascere chi serve.
- `arcanium/levels/equip_playground.tscn`, `stoffa_playground.tscn` — taratura delle prese e della stoffa.

## Verifiche

Ogni meccanica ha il suo cancello in `arcanium/tools/verifica_*.gd`.
`verifica_riferimenti.gd` controlla che ogni scena, risorsa e script si carichi e
che nessun riferimento punti nel vuoto: si lancia dopo ogni modifica strutturale.
Il playtest autonomo e gli scenari sono in `docs/15_PLAYTEST_JEV.md`
(`arcanium/tools/scenari/giro_nucleo.gd` guarda il nucleo in un minuto).

⚠️ Ogni Godot lanciato da uno strumento va con un `APPDATA` isolato, e dopo un
lancio da riga di comando si ripristina `project.godot` (Godot lo riscrive).
Su un clone fresco l'import va fatto aprendo il progetto nell'editor.

## Requisiti

Godot **4.7.1**, renderer Mobile. Il plugin `addons/godot_mcp` non e' nel repo
(prodotto a pagamento): chi clona lo installa da se'.

## Fuori dal repo

`lavorazione/` (sorgenti: `.blend`, grezzi Tripo, FBX, render delle prove, pack
di SFX) e `LORE/` restano sul disco di chi lavora e non si versionano.

## Crediti

Basato sul *Godot 4 Souls-like Template* v2 di Cat Prisbrey (pubblico dominio, vedi `licenses/`).

## Licenza

Tutti i diritti riservati, salvo i componenti di terze parti: vedi `LICENSE`.
