---
name: godot-mcp-pro
description: "Godot MCP Pro: 177 tool che pilotano l'editor Godot 4 vivo via WebSocket — scene, nodi, script, AnimationTree, fisica, particelle, shader, theme, audio, navigation, tilemap, simulazione input, ispezione del gioco in esecuzione, testing, profiling, export, refactoring in blocco. Usare quando serve creare o modificare scene e risorse dentro l'editor invece che a mano sui file, provare il gioco con input simulati, ispezionare nodi a runtime, o cercare riferimenti e segnali in tutto il progetto. Keywords: godot mcp, MCP Godot, editor tools, add_node, update_property, get_scene_tree, simulate_action, execute_game_script, animation tree state machine, connect_signal, run_headless_scene, UndoRedo."
---

# Godot MCP Pro — pilotare l'editor invece dei file

Addon d'editor (`addons/godot_mcp`, v1.16.0) che espone **177 tool in 26 categorie**.
L'elenco qui sotto e' stato estratto dai `get_commands()` dei sorgenti installati,
non dalla pagina del prodotto: se l'addon viene aggiornato, ricontarlo da li'.

## Prima di provarci: serve il ponte

L'addon **non e' il server MCP**. `websocket_server.gd` si collega *verso* istanze
Node.js sulle porte **6505-6514** (una per sessione di Claude Code; 6510-6514 sono
per i tool da riga di comando). Perche' i tool funzionino servono tre cose insieme:

1. l'addon abilitato in `project.godot` → `[editor_plugins]` ✔ fatto
2. il server Node compilato e dichiarato in `.mcp.json` ✔ fatto
3. **l'editor Godot APERTO sul progetto** — non e' un sistema headless: quasi tutti
   i tool agiscono sull'editor vivo

Se i tool non rispondono, il primo sospetto e' sempre **l'editor chiuso**.

### Com'e' installato qui (2026-08-04)

- addon: `addons/godot_mcp/` — **gitignorato**, vedi la nota sulla licenza sotto
- server: `C:\godot-mcp-pro-v1.16.0\server\build\index.js`, dichiarato in `.mcp.json`
- ricompilare dopo un aggiornamento: `node build/setup.js install` dalla cartella
  `server`, poi `node build/setup.js doctor` per la verifica

Il server viene avviato **dal client**, non a mano: e' `.mcp.json` a farlo partire.
Gli MCP si caricano all'**avvio** di Claude Code: dopo un cambio di configurazione
serve riavviare, non basta ricaricare.

### L'altro MCP in `.mcp.json`: blender-mcp

Accanto a Godot MCP Pro c'e' **blender-mcp** (v1.8.0, di Siddharth Ahuja), lanciato
via `uvx` con percorso assoluto — i client MCP non ereditano il PATH della shell.
Lato Blender l'addon sta in
`%APPDATA%\Blender Foundation\Blender\5.2\scripts\addons\blender_mcp_addon.py`
e va **abilitato a mano** in *Edit → Preferences → Add-ons → "Blender MCP"*, poi
avviato dal pannello nella barra laterale della viewport (tasto N).

Stessa logica di Godot: senza Blender aperto e con l'addon attivo, i tool non
rispondono.

### Quando "Godot editor is not connected"

Quasi sempre e' un `node.exe` rimasto appeso da una sessione precedente che tiene
la porta. Chiuderlo da Task Manager e riavviare il client.
**Non impostare `GODOT_MCP_PORT` fisso**: il server scansiona da solo 6505-6509 e
Godot si collega a tutte: una porta fissa fa fallire in silenzio se c'e' un residuo.

### Licenza — non versionare il sorgente

`LICENSE` del pacchetto e' proprietaria e vieta esplicitamente di *"redistribute,
sublicense, sell, or share the Software or any portion of its source code"*.
Per questo `addons/godot_mcp/` sta nel `.gitignore`: su un repo pubblico sarebbe
una violazione. Uso commerciale e installazione su piu' macchine proprie sono invece
concessi.

## Il vantaggio che giustifica l'addon: UndoRedo

Ogni modifica passa dall'`UndoRedo` di Godot, quindi **Ctrl+Z annulla tutto** quello
che viene fatto da qui. E' la differenza sostanziale con gli MCP gratuiti, che
scrivono sulle scene senza rete di sicurezza. Vale la pena preferire questi tool
alla modifica diretta dei `.tscn` proprio per questo.

---

## I 177 tool per categoria

### Progetto e file
`get_project_info` · `get_filesystem_tree` · `search_files` · `search_in_files`
`get_project_settings` · `set_project_setting` · `uid_to_project_path`
`project_path_to_uid` · `add_autoload` · `remove_autoload`

### Scene
`get_scene_tree` · `get_scene_file_content` · `create_scene` · `open_scene`
`delete_scene` · `add_scene_instance` · `play_scene` · `stop_scene` · `save_scene`
`get_scene_exports`

### Nodi
`add_node` · `delete_node` · `duplicate_node` · `move_node` · `update_property`
`get_node_properties` · `add_resource` · `set_anchor_preset` · `rename_node`
`connect_signal` · `disconnect_signal` · `get_node_groups` · `set_node_groups`
`find_nodes_in_group` · `get_editor_selection` · `select_nodes` · `clear_editor_selection`

### Script
`list_scripts` · `read_script` · `create_script` · `edit_script` · `attach_script`
`get_open_scripts` · `validate_script`

### Editor e diagnostica
`get_editor_errors` · `get_output_log` · `get_editor_screenshot` · `get_game_screenshot`
`execute_editor_script` · `clear_output` · `reload_plugin` · `reload_project`
`get_signals` · `compare_screenshots` · `set_auto_dismiss` · `get_editor_camera`
`set_editor_camera`

### Runtime — il gioco in esecuzione
`get_game_scene_tree` · `get_game_node_properties` · `set_game_node_property`
`capture_frames` · `monitor_properties` · `execute_game_script` · `start_recording`
`stop_recording` · `replay_recording` · `find_nodes_by_script` · `get_autoload`
`batch_get_properties` · `find_ui_elements` · `click_button_by_text` · `wait_for_node`
`find_nearby_nodes` · `navigate_to` · `move_to` · `watch_signals`

### Input simulato
`simulate_key` · `simulate_mouse_click` · `simulate_mouse_move` · `simulate_action`
`simulate_sequence` — e `get_input_actions` · `set_input_action` per l'InputMap

### Animazione
`list_animations` · `create_animation` · `add_animation_track` · `set_animation_keyframe`
`get_animation_info` · `remove_animation`

### AnimationTree
`create_animation_tree` · `get_animation_tree_structure` · `add_state_machine_state`
`remove_state_machine_state` · `add_state_machine_transition`
`remove_state_machine_transition` · `set_blend_tree_node` · `set_tree_parameter`

### 3D
`add_mesh_instance` · `setup_lighting` · `set_material_3d` · `setup_environment`
`setup_camera_3d` · `add_gridmap`

### Fisica
`setup_collision` · `set_physics_layers` · `get_physics_layers` · `add_raycast`
`setup_physics_body` · `get_collision_info`

### Navigation
`setup_navigation_region` · `bake_navigation_mesh` · `setup_navigation_agent`
`set_navigation_layers` · `get_navigation_info`

### Particelle
`create_particles` · `set_particle_material` · `set_particle_color_gradient`
`apply_particle_preset` · `get_particle_info`

### Shader
`create_shader` · `read_shader` · `edit_shader` · `assign_shader_material`
`set_shader_param` · `get_shader_params`

### Theme e UI
`create_theme` · `set_theme_color` · `set_theme_constant` · `set_theme_font_size`
`set_theme_stylebox` · `setup_control` · `get_theme_info`

### Audio
`get_audio_bus_layout` · `add_audio_bus` · `set_audio_bus` · `add_audio_bus_effect`
`add_audio_player` · `get_audio_info`

### TileMap
`tilemap_set_cell` · `tilemap_fill_rect` · `tilemap_get_cell` · `tilemap_clear`
`tilemap_get_info` · `tilemap_get_used_cells`

### Risorse
`read_resource` · `edit_resource` · `create_resource` · `get_resource_preview`

### Refactoring in blocco
`find_nodes_by_type` · `find_signal_connections` · `batch_set_property` · `batch_add_nodes`
`find_node_references` · `get_scene_dependencies` · `cross_scene_set_property`

### Analisi del progetto
`find_unused_resources` · `analyze_signal_flow` · `analyze_scene_complexity`
`find_script_references` · `detect_circular_dependencies` · `get_project_statistics`

### Test e profiling
`run_test_scenario` · `assert_node_state` · `assert_screen_text` · `run_stress_test`
`get_test_report` · `get_performance_monitors` · `get_editor_performance`

### Headless ed export
`run_headless_scene` · `run_headless_script` · `get_godot_executable`
`list_export_presets` · `export_project` · `get_export_info`
`list_android_devices` · `get_android_preset_info` · `deploy_to_android`

---

## Insidie (dal produttore, verificate nei sorgenti)

**Non modificare `project.godot` a mano mentre l'editor e' aperto.** Godot lo
riscrive di continuo e la modifica si perde. Usare `set_project_setting`,
`add_autoload`, `remove_autoload`. ⚠️ Su Arcanium questa regola vale **solo a
editor aperto**: il lavoro headless (autoload, `[editor_plugins]`, impostazioni
video) modifica il file direttamente ed e' corretto cosi', ma le due strade non
vanno mischiate nella stessa sessione.

**Preferire le proprieta' dell'inspector al codice.** Per colori, dimensioni,
override di theme e trasformazioni usare `update_property` sul nodo: il valore
resta visibile e ritoccabile a mano. Scrivere GDScript solo quando la proprieta'
non esiste nell'inspector o deve essere dinamica.

**Formato dei valori** (vengono interpretati da stringa):
`"Vector2(100, 200)"` · `"Vector3(1, 2, 3)"` · `"Color(1, 0, 0, 1)"` o `"#ff0000"`
· `"true"`/`"false"` · `"42"` · enum come intero.

**Dopo `create_script` o modifiche sostanziali, chiamare `reload_project`**,
altrimenti Godot continua a usare la versione vecchia.

**`execute_game_script` non accetta funzioni annidate** (`func` dentro `func`:
errore di compilazione) e vuole `.get("proprieta")` invece dell'accesso diretto.

**`simulate_key`: durate corte, 0.3-0.5 s.** Oltre il secondo il personaggio
supera il bersaglio. Con InputMap definita preferire `simulate_action`.

**`simulate_mouse_click`**: lasciare `auto_release: true` — i pulsanti UI reagiscono
al rilascio, servono entrambi gli eventi.

**Salvare spesso** con `save_scene`: un reload dell'editor si porta via il non salvato.

**Cicli `for` su array non tipizzati**: annotare esplicitamente il tipo, altrimenti
l'inferenza fallisce. Su Arcanium e' gia' la convenzione (vedi `godot-gdscript-mastery`).

---

## Dove serve davvero su Arcanium

**AnimationTree — il muro delle armi.** `object_type` sull'arma pilota
`MovementStates/<TIPO>_tree` e `ATTACK_tree/<TIPO>`, e oggi esistono solo `SLASH` e
`THRUST`: spadone, mazza e arco non hanno il ramo. `get_animation_tree_structure`,
`add_state_machine_state` e `add_state_machine_transition` sono la via per aggiungerli
senza scrivere `.tscn` a mano.

**Segnali.** L'architettura e' "signal up, call down" e ci sono gia' stati segnali
appesi nel vuoto (`summon_tutorial_requested`, `EventBus.shop_requested`).
`analyze_signal_flow`, `get_signals` e `find_signal_connections` trovano gli
scollegamenti; `connect_signal` li chiude.

**Provare il combattimento.** `simulate_action` + `get_game_scene_tree` +
`monitor_properties` fanno quello che oggi si fa a mano nel `battle_playground`.
`start_recording`/`replay_recording` rendono ripetibile una sequenza di prova.

**Non sostituiscono i `verifica_*.gd`.** Gli script in `arcanium/tools/` girano in
headless, escono con codice 0/1 e non richiedono l'editor aperto: restano la rete
di sicurezza per le regressioni. I tool MCP servono a *costruire* e a *ispezionare*,
i `verifica_*` a *dimostrare*. `run_headless_script` e' il ponte fra i due.

**Level building.** `add_mesh_instance`, `add_gridmap`, `setup_lighting` e
`setup_environment` convivono con i builder `@tool` esistenti
(`traccia_perduta_builder.gd`, `crocevia_builder.gd`): usare i tool per il
piazzamento a mano e i builder per cio' che e' generato, mai i due sulla stessa
porzione di scena.
