# Analisi del framework — Cat's Godot 4 Souls-like Template v2.0.0

> Base del progetto **Arcanium** (Godot 4.7, renderer `gl_compatibility`/mobile).
> Documento di studio: descrive COME funziona il template, per sapere DOVE innestare i nostri sistemi.
> ⚠️ Il template annuncia una v3.0 con codebase completamente diversa: **restiamo sulla v2 e non aggiorniamo mai in-place**. Ogni miglioria la portiamo noi a mano.

## 1. Filosofia architetturale

Il template è **signal-driven e loosely coupled**: quasi nessun sistema chiama direttamente un altro. Il player emette segnali (`attack_started`, `dodge_started`, `hurt_started`…); AnimationTree, EquipmentSystem, HealthSystem e UI si agganciano ai segnali per nome (spesso configurato via `@export var ..._signal : String`). Conseguenze pratiche:

- Si può sostituire un sistema intero senza toccare gli altri, purché si emettano/ascoltino gli stessi segnali.
- I nomi dei segnali sono **contratti**: rinominarli rompe silenziosamente le connessioni fatte via stringa (`has_signal(...)` + `connect(...)` → se il nome non esiste, semplicemente non si connette, senza errore).
- Il movimento è **root-motion driven**: la velocità del CharacterBody3D deriva da `animation_tree.get_root_motion_position() / delta` (vedi `set_root_move()` in `player/player_charbody3D.gd:507`). Le animazioni COMANDANO il gameplay: cambiare una clip di attacco cambia distanze e timing dei colpi.

## 2. Mappa dei sistemi

### 2.1 Player — `player/player_charbody3D.gd` (+ scena `player_charbody3d.tscn`)
- `CharacterBody3D` con enum di stato minimale: `FREE / STATIC / CLIMB` + sub-stati booleani (`busy`, `guarding`, `sprinting`, `dodging`, `slowed`).
- Input gestito in `_input()`: attacco leggero/forte, dodge/sprint (stesso tasto, timer 0.3s per distinguere tap/hold), parata+parry (finestra `parry_window` = 0.3s), interazioni, cambio arma/gadget/item, salto, scalata.
- **Pattern chiave `trigger_event(signal_name)`** (riga 489): setta `busy=true`, emette il segnale, aspetta che l'AnimationTree "misuri" la durata della clip (`animation_measured`), aspetta quel tempo, poi `busy=false`. Tutto il gating delle azioni si basa su questo. È QUI che si innesterà qualsiasi costo in stamina/risorse.
- `hit(_who, _by_what)` è il punto d'ingresso del danno: gestisce parry → block → hurt in cascata. `_by_what` è una `EquipmentResource` (vedi 2.4).
- Morte: `death()` ricarica la scena dopo 3s (`get_tree().reload_current_scene()`) — placeholder da sostituire col nostro flusso morte/respawn.

### 2.2 AnimationTree — `player/player_anim_tree.gd` (`AnimationTreeSoulsBase`)
- Il vero "cervello" dei timing. Struttura: state machine radice `MovementStates` con un **sotto-albero per tipo d'arma** (`SLASH_tree`, `HEAVY_tree`, `LADDER_tree`, `SPRINT_tree`…), ciascuno con blendspace `MoveStrafe` 2D (strafe via cross/dot product calcolati dal player).
- Le azioni one-shot (Attack, Dodge, Hurt, Parry, Block, Jump, UseItem, Gadget…) sono nodi **OneShot** richiesti via `request_oneshot(nome)`.
- Combo: `attack_count` (1..`max_attack_count`, default 2) incrementato ad ogni attacco entro `anim_length + 0.2s`; il routing della combo sta nelle *advanced expressions* dentro l'ATTACK_tree. Per combo più lunghe: aumentare `max_attack_count` e aggiungere rami nell'albero.
- **Contratto centrale `animation_measured(anim_length)`**: emesso da `_on_animation_started` leggendo la durata della clip. Player, EquipmentSystem e combat timing dipendono da questo. Se un'animazione non parte, chi fa `await animation_measured` resta appeso: attenzione quando sostituiremo le clip.
- Tipi d'arma riconosciuti: se non esiste `<TIPO>_tree` fa fallback su `SLASH_tree` (riga 159). Quindi si possono aggiungere armi nuove gradualmente.

### 2.3 Animazioni & modelli
- Le animazioni vivono in **AnimationLibrary** agganciate a rig standard (Godot Humanoid/Mixamo-like). Il retarget è il meccanismo ufficiale per usare modelli custom: "swap in your own compatible models" è il selling point del template.
- 110+ animazioni CC0 incluse (`MannyAnimations.zip` in root = sorgenti).
- Modelli inclusi: mannequin low-poly M/F in `assets/characters/`.

### 2.4 Equipaggiamento — `player/equipment_system/`
- `EquipmentSystem` (Node3D, riusato sia per arma primaria che per gadget off-hand): due mount point (`held_mount_point` / `stored_mount_point`, tipicamente BoneAttachment3D mano/schiena), swap dei figli al segnale di cambio; attiva/disattiva il monitoring dell'Area3D dell'arma durante la finestra d'attacco (30%→80% della durata clip — hitbox timing "a percentuale", non per frame).
- `EquipmentObject` (Area3D) = arma fisica con `equipment_info : EquipmentResource`.
- `EquipmentResource` (Resource): `name, object_type (SLASH/HEAVY/SHIELD/OTHER), power, weight, value`. **È qui che innesteremo le Sette Marche e lo scaling di Arcanium** — estendendo la Resource, non riscrivendola.
- Colpo a segno: `_on_body_entered` → se il corpo è nel gruppo `targets` e ha metodo `hit()`, chiama `hit(player_node, equipment_info)`. Il danno è "push": chi colpisce passa i propri dati, chi è colpito decide cosa farne.

### 2.5 Salute — `enemy/health_system.gd` (`HealthSystem`, usato anche dal player)
- Node generico: si aggancia via nome-segnale a un nodo che riporta danno/cura; legge `_by_what.power` e scala HP. Interi, semplicissimo (player: pochi HP, non 100).
- Gestisce anche health bar flottante on-screen (unproject della posizione).
- **Da estendere per Arcanium**: resistenze/vulnerabilità (ResistanceTable), status effects (Erosione dell'Eco, Frattura), danno non intero. La via pulita: sottoclasse o sostituto che mantiene il contratto `died` + `health_updated`.

### 2.6 Nemici — `enemy/enemy_base_root_motion.gd`
- CharacterBody3D con stati `FREE / CHASE / COMBAT / ATTACK / DEAD`, NavigationAgent3D per il pathfinding, `target_sensor` (Area3D con raycast di conferma) per l'aggro, `default_target` per pattugliamento (PathFollow3D) o ritorno allo spawn.
- Combat loop: entro `combat_range` un `CombatTimer` chiama `combat_randomizer()` → 30% retreat / 70% attack. **Questo è il punto d'innesto per AI più ricche** (pattern per gruppo nemico, telegraph, cooldown per mossa — le logiche che avevamo negli slider di tuning di Lite).
- Morte con **ragdoll fisico** (physical bones) e freeze della posa dopo 3s.
- ⚠️ Hardcoded da generalizzare: `$mannyquin/godot_rig/GeneralSkeleton` (riga 28) — path del rig nel ragdoll; andrà export-ato quando useremo i nostri modelli Meshy.

### 2.7 Targeting / lock-on — `player/player_targeting_system/`
- Tre "occhi" Area3D (centro/destra/sinistra) + raycast `Eyeline` anti-muro. Cambio bersaglio con flick di mouse/stick. Il lock-on attiva lo strafing del player e orienta la follow cam.
- Compatibile concettualmente col nostro schema lock-on di Lite (L / L+tasto); la mappatura input andrà rivista in `project.godot [input]`.

### 2.8 Camera — `cameras/`
- `follow_cam_3d.gd`: third-person follow con supporto lock-on. `area_cam`: camere fisse ad area (stile Demon's Souls) — utile per momenti registici negli atti.

### 2.9 Item/consumabili — `player/item_system/`
- `InventorySystem` + `ItemResource`/`ItemObject`: slot ciclabile, `use_item` con timing su animazione. Fire bomb e potion come esempi. Base sufficiente per i consumabili di Arcanium.

### 2.10 Interagibili, audio, UI
- `interactable objects/`: chest, porte, cancelli, leve, scala, spawn site (checkpoint/falò di fatto: `spawn_site`). Pattern comune: `activate(player)` + animazione `Interacts` sul player.
- `audio/SoundFXSystem.gd` + footfall system (suoni passi per materiale).
- `ui/`: health bar, item slot, death card ("YOU DIED"), control card. Tutto placeholder grafico da ri-skinnare con l'arte di Arcanium.

## 3. Contratti da rispettare (cheat-sheet per chi implementa)

| Contratto | Dove | Regola |
|---|---|---|
| `animation_measured(length)` | AnimationTree → tutti | ogni azione attende la durata reale della clip |
| `hit(who, equipment_resource)` | armi → bersagli | il bersaglio decide gli effetti; serve `has_method("hit")` |
| gruppo `"targets"` | nemici e player | requisito per essere colpibili/lock-onabili |
| segnali `*_started` / `*_ended` | player → sistemi | connessioni per nome-stringa: MAI rinominare senza grep globale |
| layer fisici 1-5 | project.godot | World / Player / Targets / Interactable / Ladder |
| `EquipmentResource.power` | danno | HealthSystem legge `.power` su qualunque cosa colpisca |

## 4. Punti deboli noti del template (da tenere d'occhio)

1. **Timing basati su `create_timer` + percentuali di clip**: fragili se cambiamo velocità delle animazioni; per il combat di qualità AA valuteremo Call Method tracks nelle animazioni per aprire/chiudere le hitbox su frame precisi.
2. **HealthSystem con HP interi e nessun concetto di tipo di danno** — sarà tra le prime cose estese.
3. **AI nemica elementare** (random 30/70): ottima base, ma i nostri nemici hanno pattern e status; serve un layer di "move set" data-driven.
4. **Morte player = reload scena**: da sostituire con flusso checkpoint (spawn_site c'è già).
5. **`ui_cancel` = quit istantaneo** in `_input` del player (riga 191): da rimuovere subito, o Esc chiude il gioco.
6. Renderer: il template era su `gl_compatibility`. **Deciso il passaggio a Mobile** (Vulkan/D3D12) per bilanciare qualità e target deboli (Switch 2/handheld/Series S) — vedi `02_PLATFORM_STRATEGY.md`. Impatta materiali e luci: verificare a editor aperto.
