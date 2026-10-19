# Mappa dell'AnimationTree del player — verificata sui file

> Estratta da `player/player_charbody3d.tscn` (l'intero AnimationTree è **inline** come sub_resource nella scena, non un `.tres` separato) e da `player/player_anim_tree.gd` (`AnimationTreeSoulsBase`).
> Sorgente animazioni: `AnimationLibrary` **`MeleeLib`** (`player/animation_libraries/MeleeLib.res`), player prefisso `MeleeLib/…`.
> Serve alla Fase 2+: quando retargettiamo il protagonista Meshy, questi sono i nomi di clip e i parametri che `set("parameters/…")` deve poter risolvere. Rinominare un nodo qui rompe le chiamate stringa in `player_anim_tree.gd`.
> ⚠️ Da riverificare con **screenshot** a editor aperto una volta che il MCP Godot è riconnesso (task residuo).

## 0. Root — `AnimationNodeBlendTree` (`tree_root`)

Nodi di primo livello (ognuno un `nodes/<Nome>/node`). I **OneShot** sono richiesti da `request_oneshot(nome)` → `set("parameters/<nome>/request", true)`:

| Nodo (parametro) | Tipo | Attivato da (segnale player → handler) |
|---|---|---|
| `MovementStates` | StateMachine | sempre attivo (base locomotion) — `parameters/MovementStates/playback` |
| `ATTACK_tree` | StateMachine | dentro il OneShot `Attack` |
| `Attack` | **OneShot** | `attack_started` → `_on_attack_started` |
| `Block` / `BlockAnim` | **OneShot** + Anim `GuardBlocked` | `block_started` → `_on_block_started` |
| `Parry` / `ParryAnim` | **OneShot** + Anim | `parry_started` → `_on_parry_started` |
| `Hurt` | **OneShot** | `hurt_started` → `_on_hurt_started` (sceglie Hurt1/Hurt2) |
| `Dodge` / `DODGE_tree` | **OneShot** + StateMachine | `dodge_started` → `_on_dodge_started` |
| `Jump` / `JumpAnim` | **OneShot** + Anim | `jump_started` → `_on_jump_started` |
| `Landed` / `LANDED_tree` | **OneShot** + StateMachine | `landed_fall` → `_on_landed_fall` |
| `Gadget` / `GADGET_tree` | **OneShot** + StateMachine | `gadget_started` → `_on_gadget_started` |
| `Summon` | **OneShot** — ⚠️ **DA CREARE** | `summon_started` → `_on_summon_started` |
| `GadgetChange` / `GadgetChangeAnim` | **OneShot** + Anim | `gadget_change_started` |
| `WeaponChange` / `WeaponChangeAnim` | **OneShot** + Anim | `weapon_change_started` |
| `UseItem` | **OneShot** | `use_item_started` → `_on_use_item_started` |
| `ItemChange` / `ItemChangeAnim` | **OneShot** + Anim | `item_change_started` |
| `ITEM_tree` | StateMachine | routing consumabile (dentro UseItem) |
| `Interacts` / `INTERACT_Tree` | **OneShot** + StateMachine | `interact_started` → `_on_interact_started` |
| `Guarding` / `GuardingAnim` | Blend2 + Anim `Guarding` | continuo, `parameters/Guarding/blend_amount` in `set_guarding()` |
| `StateMachine` | StateMachine | (nodo generico ausiliario) |

> Lista OneShot completa (i nomi esatti da usare in `request_oneshot`): **Attack, Block, Parry, Hurt, Dodge, Jump, Landed, Gadget, GadgetChange, WeaponChange, UseItem, ItemChange, Interacts**.

### ⚠️ `GADGET_tree` è una SPADATA, non un gesto generico

I suoi unici due stati sono `SlashL1` e `ShieldBash`. Chiamarlo per qualcosa che
non è un colpo si vede: l'evocazione partiva con `gadget_started` e il
protagonista menava un fendente a vuoto mentre la creatura compariva a lato.
Per questo l'evocazione ha il suo `summon_started` → OneShot `Summon`.

Il nodo `Summon` **non esiste ancora** nell'albero: la clip dedicata è in
lavorazione (sorgente da animare in `assets/characters/anims/_sorgenti/protagonista_posa_riposo.glb`).
Finché manca, `_summon_at` non chiede nessun gesto e la creatura compare subito.

### ⚠️ Chiedere un OneShot che non esiste blocca il player

`request_oneshot("Fantasma")` fa `set("parameters/Fantasma/request", true)` su un
parametro inesistente: Godot lo ignora **in silenzio**, nessuna clip parte,
`animation_measured` non scatta mai — e `trigger_event()` resta appeso a
`await` con `busy = true` per sempre. Il player smette di rispondere ai comandi
e non c'è nessun errore a dirlo.

Prima di instradare un segnale nuovo, chiedere
`AnimationTreeSoulsBase.has_oneshot(nome)`.

Il segnale-contratto `animation_measured(length)` è emesso da `_on_animation_started` (misura `anim_length` dalla clip che parte). Tutto il gating in `player_charbody3D.gd` fa `await animation_measured`.

## 1. `MovementStates` — StateMachine base (`playback` = `parameters/MovementStates/playback`)

Stati:
- `Spawn` (Anim di ingresso)
- `SLASH_tree` — locomotion arma taglio (default/fallback)
- `HEAVY_tree` — locomotion arma pesante
- `SPRINT_tree` — travel via `_on_sprint_started` → `base_state_machine.travel("SPRINT_tree")`
- `LADDER_tree` — travel via `_on_climb_start`
- `Death` — travel via `_on_death_started`

Selezione albero arma in `_on_weapon_change_ended`: se esiste `<TIPO>_tree` sotto `MovementStates` usa quello, altrimenti fallback **`SLASH`**. `current_weapon_tree = parameters/MovementStates/<TIPO>_tree/playback`.

### `SLASH_tree` (StateMachine)
- `MoveStrafe` — `AnimationNodeBlendSpace2D` (blend locomotion). Pilotato da `set_strafe()`/`set_free_move()` via `parameters/MovementStates/SLASH_tree/MoveStrafe/blend_position` (Vector2 = strafe_cross_product, move_dot_product).
- `Falling` — Anim.

`HEAVY_tree` e `SPRINT_tree` hanno la stessa forma (ognuno con proprio `MoveStrafe`/`Falling`; SPRINT ha `Sprint`). `LADDER_tree` è un BlendTree (`Climbing` → `LadderTime` TimeScale, pilotato da `set_ladder()` con `parameters/MovementStates/LADDER_tree/LadderTime/scale`).

## 2. `ATTACK_tree` (dentro OneShot `Attack`) — routing combo

`ATTACK_tree` è una StateMachine con due sotto-stati per tipo d'arma, scelti per `advance_expression`:
- `Start → SLASH` se `weapon_type == "SLASH"`
- `Start → HEAVY` se `weapon_type == "HEAVY"`

### `SLASH` (StateMachine) — combo taglio
Stati e clip:
| Stato | Clip (`MeleeLib/…`) | Transizione da `Start` (advance_expression) |
|---|---|---|
| `Slash1` | `root-Slash1` | `attack_count == 1` |
| `Slash2` | `root-Slash2` | `attack_count == 2` |
| `Slash3` | `root-Slash3` | `player_node.secondary_action` (attacco forte) |
| `LightJumpAttack` | `LightJumpAttack` | `!player_node.is_on_floor()` |
| `SprintAttack` | `root-Stab1` | `player_node.sprinting` |

`attack_count` va 1→`max_attack_count` (default **2**), incrementato in `_on_attack_started` entro `anim_length + 0.2s` (reset da `attack_timer`). Per combo più lunghe: alzare `max_attack_count` **e** aggiungere stati `Slash4…` con expression `attack_count == 3…`.

### `HEAVY` (StateMachine) — combo pesante
Stati: `Heavy1`, `Heavy2`, `HeavyUppercut`, `HeavyJumpAttack`, `SprintAttack`. Stesso schema di routing da `Start`.

## 3. Altri sotto-alberi

- **`DODGE_tree`**: `Roll` (clip `root-Roll`) se `player_node.input_dir`; `JumpBack` (`root-Roll` in play_mode reverse) se `!input_dir`.
- **`GADGET_tree`**: `SlashL1` (`SlashL1`) default; `ShieldBash` (`ShieldBash`) se `gadget_type == "SHIELD"`.
- **`ITEM_tree`**: `NoItem`, `ThrowL`, `UsePotion` (`UsePotion`).
- **`INTERACT_Tree`**: `OpenChest`, `OpenDoor`, `OpenGate`, `OpenLeverFloor`, `OpenOther` (clip omonime).
- **`LANDED_tree`**: `LandHard`, `LandSoft` (scelto da `landing_type`).
- **Hurt** (dentro OneShot `Hurt`): `Hurt1`, `Hurt2` (random), `LadderHurt1` in stato CLIMB.

## 4. Note per la migrazione (Fase 2+)

1. **Filtri per-osso**: `Block`, `GadgetChange`, `Guarding` usano `filters = ["%GeneralSkeleton:Chest", …]` (braccio sx + dita) per fondere solo la parte alta. Il retarget deve mantenere gli stessi **nomi osso Humanoid** (`%GeneralSkeleton:LeftUpperArm` ecc.), altrimenti i filtri smettono di applicarsi silenziosamente.
2. **`root-` prefix** = clip con root motion (Slash/Roll/Stab). Coerente con la nota del piano: le clip comandano le distanze del combat.
3. `weapon_type`/`gadget_type` sono stringhe (`"SLASH"`/`"HEAVY"`/`"SHIELD"`): guidano sia la scelta del `_tree` di locomotion sia il routing combo. Le armi Arcanium mappano su questi tipi (spada arcana → `SLASH`).
4. Tutte le transizioni combat usano `advance_mode = 2` (Auto) — nessun timer manuale nella SM, il gating è nei OneShot + `busy`/`animation_measured`.

---
_TODO editor-aperto (post riconnessione MCP): screenshot dei tre grafi (root BlendTree, MovementStates, ATTACK_tree/SLASH) da allegare qui; confermare i tempi di xfade delle transizioni combo (0.2/0.3s dal file)._
