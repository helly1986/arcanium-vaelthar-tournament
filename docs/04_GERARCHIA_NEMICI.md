# Gerarchia dei nemici di Arcanium

> Rifattorizzazione del 2026-07-26. Sostituisce l'assetto precedente, in cui il
> Consumato (nemico comune) girava su `arcanium_boss.gd` tarato al ribasso e il
> lupo su un controller copiato-e-modificato dal boss.

## L'albero

```
ArcaniumEnemy                       arcanium/systems/enemies/arcanium_enemy.gd
│   ciclo di vita, bersaglio, locomozione, facing, scelta ed esecuzione
│   delle mosse, morte e despawn. Un `_physics_process` a template method.
│
├── ArcaniumQuadrupedEnemy          arcanium_quadruped_enemy.gd
│       lupo comune e Alpha: branco, fuga, ululato, balzo.
│
└── ArcaniumHumanoidEnemy           arcanium_humanoid_enemy.gd
    │   Consumato: libreria Nephilite, root motion, poise-break, finisher
    │   subiti, hitbox d'arma fisiche.
    │
    └── ArcaniumBoss                arcanium_boss.gd
            Senza Nome: fase 2, proiettili, scariche radiali, muri, boss bar.
```

Fuori dall'albero: `arcanium/systems/template_dummy_enemy.gd` (ex
`arcanium_enemy.gd`) è il manichino del livello di prova, guidato dalla pipeline
del template. Non è un nemico del gioco.

**L'Alpha e il Senza Nome sono entrambi "boss" ma stanno su rami diversi**, ed è
voluto: l'Alpha è un quadrupede, il Senza Nome un umanoide. "Boss" non è una
classe, è un insieme di TRATTI (barra, banner, fase, bounty) che si innestano
dove servono — sull'Alpha col flag `is_alpha`, sul Senza Nome con una
sottoclasse dedicata perché i tratti sono molti e pesanti.

## Cosa è stato trovato durante l'analisi

### 1. L'animazione di morte sovrascritta da quella di dolore (BUG, risolto)

```gdscript
damage_taken.emit(_by_what)        # → HealthSystem → died → _on_died() → play(morte)
if not _busy and _state != VICTIM: # ⚠️ non controllava DEAD
    _play(hurt_anim, false)        # ← la clip di dolore copre quella di morte
```

`ArcaniumHealthSystem._on_damage_signal` emette `died` **in modo sincrono**
dentro `damage_taken`: al ritorno lo stato è già `DEAD` e la morte è già partita.
Il controllo mancante spiega l'asimmetria osservata in playtest:

| | quando muore | `_busy` | esito |
|---|---|---|---|
| Consumato (25 HP) | quasi sempre da fermo o in inseguimento | falso | morte **mai** visibile |
| Boss | quasi sempre a metà attacco | vero | ramo saltato, morte visibile |

Ora `ArcaniumEnemy.hit()` ricontrolla `DEAD` dopo l'emit. Un test headless
verifica che dopo un colpo letale la clip in riproduzione sia quella di morte,
su tutti e quattro i nemici.

### 2. L'istante del colpo scollegato dall'animazione (BUG, risolto)

Il Consumato non ha una lama fisica, quindi cadeva nel ramo di fallback del
controller boss, che consegna il danno a `telegraph / anim_speed_scale`:

```
A1: 1.4 / 0.7 = 2.00 s      clip a velocità 0.7: 1.30 / 0.7 = 1.86 s
```

**Il danno arrivava dopo la fine dell'animazione.** Misurando le clip del pack
(campionamento dello scheletro a 120 Hz, picco di velocità dell'osso
`Prop_Attachment_R`):

| clip | durata | contatto vero |
|---|---|---|
| `sword_light_attack_01` | 1.30 s | **0.45 s** |
| `sword_light_attack_02` | 1.53 s | **0.50 s** |
| `sword_charged_attack_01` | 3.70 s | 2.53 s |
| `sword_th_charged_attack_01` | 2.77 s | 1.54 s |
| `sword_run_attack_01` | 1.37 s | 0.46 s |

Gli istanti di contatto ora sono un DATO (`EnemyMove.contact_times`, secondi
sulla clip a velocità 1.0), non una stima nel codice: una sola verità condivisa
da animazione e gameplay. Le costanti `MULTI_HIT` che vivevano nel controller
del lupo sono migrate nei suoi move set.

### 2bis. I tempi di colpo, per tutte le mosse di tutti i nemici

Il colpo del Consumato era il caso più vistoso, ma il problema era di sistema.
Rifatta la revisione su **tutte** le mosse dei tre nemici, con due cambi di
fondo.

**a) I contatti si misurano dalle clip, non si stimano.**
`arcanium/tools/measure_attack_contacts.gd` campiona la posa dello scheletro a
240 Hz e segue l'osso che colpisce (mano armata / punta del muso). Il criterio:
si isolano le regioni in cui l'osso viaggia veloce — una per colpo — e dentro
ciascuna si prende l'istante di massimo AVANZAMENTO. Vale sia per i fendenti
(dove la lama attraversa l'asse frontale) sia per morsi e affondi (dove il colpo
arriva a fine estensione, cioè dopo il picco di velocità). L'esito finisce in
`arcanium/resources/attack_timing.tres`.

Due controprove indipendenti che il metodo è tarato bene: il morso del lupo
misura **0.69 s** contro lo 0.70 authorato a mano in Blender, e `sword_cast_01`
misura il rilascio a **1.97 s** contro il "~f60 = 2.0 s" annotato nel codice.

| clip | durata | contatto | finestra arma |
|---|---|---|---|
| `sword_light_attack_01` | 1.30 s | 0.47 | 0.34–0.57 |
| `sword_light_attack_02` | 1.53 s | 0.46 | 0.34–0.57 |
| `sword_run_attack_01` | 1.37 s | 0.51 | 0.40–0.60 |
| `sword_charged_attack_01` | 3.70 s | 2.53 | 2.40–2.53 |
| `sword_charged_attack_02` | 3.70 s | 2.54 | 2.40–2.70 |
| `sword_jump_attack_01` | 2.50 s | 1.21 | 1.14–1.23 |
| `sword_th_charged_attack_01` | 2.77 s | 1.60 | 1.47–1.63 |
| `sword_cast_01` | 3.00 s | 1.97 | 1.77–2.00 |
| `sword_burst_01` | 2.10 s | 1.30 | 1.27–1.43 |
| `bite` | 1.33 s | 0.69 | 0.54–0.70 |
| `bite_combo` | 2.00 s | 0.68 / 1.23 | 0.54–1.30 |
| `leap` | 1.20 s | 0.70 | 0.64–0.90 |

**b) Il colpo lo consegna il PLAYHEAD, non un timer.**
Un timer corre *parallelo* all'animazione: basta un cambio di velocità, una
clip interrotta o un blend e il danno arriva quando a schermo non succede nulla.
`AnimationPlayer.current_animation_position` è già in tempo-clip — a velocità
0.7, dopo un secondo reale vale 0.7 — quindi si confronta DIRETTAMENTE con gli
istanti misurati e non si divide per `anim_speed_scale` da nessuna parte. Lo
stesso vale per la finestra della hitbox fisica, che ora si apre e chiude
seguendo il playhead: sono spariti i token e le coroutine appese che servivano a
invalidare le finestre delle mosse abortite (una finestra che non viene più
aggiornata semplicemente non si apre).

**Perché è cruciale**: parata e schivata all'ultimo istante sono le due abilità
su cui si regge il combattimento, e il giocatore le temporizza su ciò che VEDE.
Il parry del player è una finestra di 0.3 s dalla pressione, la schivata dà
i-frame per il 70% della clip: entrambe funzionano solo se il danno arriva
quando l'arma arriva.

La finestra della lama era il secondo colpevole: a frazioni fisse (15%–90% della
clip) restava viva anche durante il **wind-up** e il **recovery**. Su
`sword_charged_attack_01` faceva **2.78 secondi di lama accesa su 3.70**: il boss
ti feriva mentre *alzava* la spada, e non esisteva istante in cui schivare fosse
la risposta giusta. Ora la finestra è l'arco vero dello swing, dal 4% al 24%
della clip a seconda della mossa.

**Trappola dell'engine emersa qui, da ricordare**: un `PackedFloat32Array`
estratto da un `Dictionary` CONDIVIDE il buffer con quello dentro il dizionario.
Il controller si tiene i contatti in coda e li toglie mano a mano che li
consegna, quindi senza `duplicate()` il primo nemico che attacca **svuota la
tabella per tutti**: in gioco il primo Consumato colpiva a tempo e gli altri tre
ricadevano sul `telegraph`. Vale per qualunque Packed array preso da un
Dictionary o da una Resource condivisa.

**Banco di regressione**: `arcanium/tools/check_hit_timing.gd` lancia ogni mossa
di ogni nemico e confronta l'istante atteso con quello osservato (più il
controllo della clip di morte). Tolleranza 0.05 s; oggi lo scarto reale è
+0.013…+0.034 s, cioè 1-2 frame di fisica, e **mai in anticipo** — un colpo che
arriva presto è quello che si percepisce come sleale.

```bash
godot --headless --path . res://arcanium/tools/check_hit_timing.tscn
```

**Unica eccezione rimasta**: `B2 "Balzo Reciso"` dichiara a mano
`blade_open_frac 0.4 / blade_close_frac 0.68`, che vincono sulla misura e danno
una finestra di 0.70 s (28% della clip) invece dei 0.17 s misurati. È
un'intenzione authorata — durante la discesa la lama spazza e chi sta sotto va
colpito — quindi è stata lasciata. Per allinearla alla misura basta togliere
quelle due righe da `senza_nome_moveset.tres`.

### 3. Bersaglio scelto male con i minion in campo (risolto)

Il controller boss usava `get_first_node_in_group("player")`, cioè un nodo
*qualunque* del gruppo in ordine d'albero. Da quando esistono le evocazioni, il
gruppo contiene anche la Scintilla: il boss poteva restare agganciato al minion
dall'altra parte dell'arena mentre il player lo colpiva. La base ora prende
sempre il più vicino (comportamento che il lupo aveva già).

### 4. Diagnostica accumulata, rimossa

- **Log su file**: `arcanium_boss.gd` apriva `res://arcanium/_boss_debug.log` in
  scrittura a ogni `_ready`, con ~100 punti di log. Con quattro Consumati in
  scena scrivevano tutti sullo STESSO file, sovrascrivendosi a vicenda: era già
  inutilizzabile oltre che costoso.
- **`debug_overlay`**: l'export esisteva e le scene lo impostavano, ma il codice
  che creava l'etichetta era finito **dopo un `return`**, dentro `_rm_track()`.
  Non ha mai funzionato. Rimosso insieme a `_debug_label`.
- **`_diag_arp_check()`** e **`_verify_animations()`**: sonde nate per inseguire
  l'A-pose, la cui causa (retarget verso nomi-osso non validi) è sparita col
  skinning nativo sul rig del pack. Rimosse.
- **`_lunge_forward()`**: spostamento tweenato dell'era Meshy, senza chiamanti
  da quando le clip portano root motion authorata. Rimosso.
- Heartbeat nel log, sonda del facing mesh-vs-nodo, `_blade_min_info`,
  `_blade_player_start`, `_busy_since`: tutta strumentazione di indagini chiuse.

Restano nei commenti le **conclusioni** di quelle indagini (perché la track di
root motion sta sul bone `Root`, perché il blend è a 0, perché il watchdog è
per-mossa) — quelle sono conoscenza, non impalcatura.

## Come aggiungere un nemico

### Un comune umanoide

1. Scena `CharacterBody3D` con script `arcanium_humanoid_enemy.gd`, figli
   `Model` (GLB skinnato sul rig Nephilite), `AnimationPlayer`, `HealthSystem`,
   `StatusHost`/`PoiseBreak`, `CrystalBounty`.
2. Un `EnemyMoveSet` con le mosse. Per ciascuna: `anim`, `contact_times`,
   `move_range`, `power`.
3. Nient'altro: locomozione, morte, finisher e poise-break arrivano dalla classe.

### Un quadrupede

Come sopra ma con `arcanium_quadruped_enemy.gd` e le clip in-place della
creatura. ⚠️ Le clip NON devono animare `Hips.location`, o il corpo sprofonda:
l'avanzamento lo mette il controller.

### Una creatura con più arti offensivi

Non serve un controller nuovo. Si aggiungono `Area3D` alla scena (una per
arto/arma), si elencano in `extra_hitboxes`, e ogni mossa dichiara la propria in
`EnemyMove.hitbox` (il nome del nodo). Chi non dichiara nulla usa l'arma
principale (`blade`); chi non ha armi usa gli istanti di contatto.

### Una creatura senza scheletro (softbody, sciame)

Si estende `ArcaniumEnemy` e si sovrascrivono `_play()` e `_anim_len()` con
qualunque cosa faccia da "animazione" (shader, deformazione procedurale,
scaletta di stati). Nessun'altra parte del ciclo guarda lo scheletro.

### Un doppio boss

I due si trovano col gruppo `arcanium_enemy` e reagiscono l'uno alla caduta
dell'altro via `on_ally_died()` (è il canale che il branco usa per la fuga).
Fase, barra e banner si innestano come fa `ArcaniumBoss`.

## Punti d'innesto della classe base

| Metodo | A cosa serve |
|---|---|
| `_setup()` | inizializzazione, dopo segnali e bersaglio |
| `_special_state_step(delta)` | stati che gestiscono da soli il frame (stagger, victim, fuga, transizioni) |
| `_pre_ai_step(delta)` | gira anche durante gli attacchi (root motion, sonde) |
| `_attack_motion(delta)` | movimento durante una mossa |
| `_pre_combat_step()` | salta l'AI del frame (transizione di fase) |
| `_run_move_timeline(move, len)` | quando aggancia e quando colpisce |
| `_execute_special(move, len)` | coreografie proprie (ululato, balzo) |
| `_on_move_started/_released/_finished` | VFX di carica, proiettili, scivolate |
| `_deliver_hit(move)` | come arriva il danno |
| `_move_is_usable` / `_move_weight_multiplier` | filtri e pesi contestuali |
| `_can_react_to_hit()` | stati che non vanno interrotti da un colpo |
| `_on_special_anim_finished(name)` | catene di clip (victim → getup) |

## Cosa NON è cambiato di proposito

Il combattimento del Senza Nome. Finestra della lama, sonda swept, backstop
ravvicinato, catene, fase 2, proiettili e VFX sono stati **spostati**, non
riscritti: stessa logica, stessi numeri, meno rumore attorno. Le uniche
differenze di comportamento volute sono quelle elencate sopra (bersaglio più
vicino, morte che non viene più coperta, collision layer spenti alla morte).
