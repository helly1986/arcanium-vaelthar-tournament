extends SceneTree

## Cancello: il CAMPIONE NON EVOCA PIU' (decisione dell'autore del 2026-10-21:
## le evocazioni avranno la loro modalita', il battleground).
##
##   1. l'input non ha piu' le modalita' (select_mode_spell/_summon);
##   2. SpellSelection cicla solo gli incantesimi e non annuncia altro;
##   3. il campione (player_dawnkeep_v4.tscn) non ha piu' il ramo, il segnale
##      ne' i nodi dell'evocazione;
##   4. la barra in basso non ha la sezione EVOCAZIONI;
##   5. il grimorio elenca solo gli incantesimi;
##   6. la scheda di un oggetto non mostra il bonus alle evocazioni;
##   7. e il codice delle evocazioni resta per il battleground: ogni risorsa in
##      resources/summons/ si carica e ha la sua creatura.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_senza_evocazioni.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 8
const SUMMON_DIR := "res://arcanium/resources/summons/"
const SPELL_DIR := "res://arcanium/resources/spells/"

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame

	## 1.
	_ok(not InputMap.has_action("select_mode_summon") and not InputMap.has_action("select_mode_spell"),
			"l'input non ha piu' le modalita' incantesimo/evocazione")

	## 2. Anche con tutte le evocazioni sbloccate.
	var flags : Node = root.get_node_or_null("PlayerFlags")
	for f in DirAccess.get_files_at(SUMMON_DIR):
		if f.ends_with(".tres"):
			var r := load(SUMMON_DIR + f)
			if flags != null and r != null and "unlock_flag" in r and str(r.unlock_flag) != "":
				flags.set_flag(r.unlock_flag)
	var sel : Node = load("res://arcanium/systems/spell_selection.gd").new()
	root.add_child(sel)
	var tipi := {}
	sel.selection_changed.connect(func(k, _r): tipi[k] = true)
	var visti := {}
	for k in 6:
		sel.select_next()
		visti[sel.current()] = true
	var n_spell := 0
	for f in DirAccess.get_files_at(SPELL_DIR):
		if f.ends_with(".tres"):
			n_spell += 1
	_ok(not ("known_summons" in sel) and not ("current_summon" in sel) and tipi.keys() == ["spell"]
			and visti.size() == n_spell,
			"SpellSelection cicla solo i %d incantesimi (annunci: %s)" % [n_spell, str(tipi.keys())])
	sel.queue_free()

	## 3.
	var pl : Node = (load("res://characters/player_dawnkeep_v4.tscn") as PackedScene).instantiate()
	var nodi_evoca := pl.find_children("*Evocazione*", "", true, false)
	_ok(not pl.has_signal("summon_started") and not pl.has_method("_cast_summon_selection")
			and not pl.has_method("_summon_at") and not ("summon_release_delay" in pl) and nodi_evoca.is_empty(),
			"il campione non ha piu' ramo, segnale ne' nodi dell'evocazione (%d nodi)" % nodi_evoca.size())
	pl.free()

	## 4.
	var cornice := Control.new()
	cornice.size = Vector2(1280, 720)
	root.add_child(cornice)
	var barra : Control = load("res://arcanium/ui/hud/spell_bar.gd").new()
	cornice.add_child(barra)
	await process_frame
	var etichette : Array = barra.find_children("*", "Label", true, false).map(func(l): return l.text)
	_ok(not barra._slots.has("minion") and barra._slots.has("spell") and barra._slots.has("items")
			and not ("EVOCAZIONI" in etichette),
			"la barra ha incantesimi e oggetti, niente EVOCAZIONI (sezioni %s)" % str(barra._slots.keys()))
	cornice.queue_free()

	## 5.
	var nomi_evoca := {}
	for f in DirAccess.get_files_at(SUMMON_DIR):
		if f.ends_with(".tres"):
			var r := load(SUMMON_DIR + f)
			nomi_evoca[String(r.get("name")) if r != null and "name" in r else f] = true
	var libro : Control = load("res://arcanium/ui/game_menu/grimoire_book.gd").new()
	root.add_child(libro)
	await process_frame
	var voci : Array = libro._carica_voci()
	var intruse := voci.filter(func(v): return nomi_evoca.has(v["name"]))
	_ok(voci.size() == n_spell and intruse.is_empty(),
			"il grimorio ha %d pagine, tutte incantesimi (%s)" % [voci.size(), str(voci.map(func(v): return v["name"]))])
	libro.queue_free()

	## 6.
	var modale : Node = load("res://arcanium/ui/game_menu/equip_modal.gd").new()
	## Il Manto del Branco Guasto ha resistenze e un bonus alle evocazioni.
	var manto : Resource = load("res://arcanium/resources/equipment/manto_branco_guasto.tres")
	var righe : Array = modale._statistiche(manto)
	var testi : Array = righe.map(func(r): return String(r[0]))
	_ok(not (manto.get("summon_damage_bonus") as Dictionary).is_empty()
			and testi.filter(func(t): return t.begins_with("Evocazioni")).is_empty()
			and not testi.filter(func(t): return t.begins_with("Resistenza")).is_empty(),
			"la scheda dell'oggetto mostra le resistenze, non il bonus alle evocazioni (%s)" % str(testi))
	modale.free()

	## 7.
	var buone := 0
	var tutte := 0
	for f in DirAccess.get_files_at(SUMMON_DIR):
		if not f.ends_with(".tres"):
			continue
		tutte += 1
		var r := load(SUMMON_DIR + f)
		if r != null and r.get("minion_scene") is PackedScene:
			buone += 1
	_ok(tutte > 0 and buone == tutte, "le %d evocazioni restano per il battleground, ognuna con la sua creatura" % tutte)
	_ok(ResourceLoader.exists("res://arcanium/systems/summons/summoned_minion.tscn")
			and ResourceLoader.exists("res://arcanium/systems/spells/summon_spell_resource.gd")
			and ResourceLoader.exists("res://arcanium/systems/vfx/miracolo_evocazione.gd"),
			"il minion, la risorsa d'evocazione e il vortice ci sono ancora")

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
