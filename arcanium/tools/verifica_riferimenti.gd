extends SceneTree

## ⛔ CANCELLO: il progetto regge? Ogni scena, risorsa e script rimasto si carica,
## e nessun riferimento punta nel vuoto.
##
## Nato per la pulizia del roguelike (via Kalvorn, Traccia, Crocevia, hub e
## quest): si cancella un'area, si lancia questo, e si committa solo se passa.
## Guarda:
##   1. autoload, plugin abilitati e `run/main_scene` in project.godot;
##   2. ogni .tscn/.tres/.res: le dipendenze dichiarate esistono, e si carica;
##   3. ogni .gd: si compila;
##   4. i percorsi `res://` scritti a mano negli script e negli .import (bone
##      map, librerie di clip): il caricamento non li vede finche' quel ramo di
##      codice non gira, e sono proprio quelli che una cancellazione spezza.
##      Nei commenti sono solo AVVISI: documentazione invecchiata, non rotture.
## Le cartelle con `.gdignore` (lavorazione/, prove/) non sono del progetto.
##
##     APPDATA=<cartella isolata> godot_console.exe --headless --path . \
##         --script res://arcanium/tools/verifica_riferimenti.gd [-- --avvisi]
##
## ⚠️ Poi `git checkout project.godot`. Il log va letto anche per le righe
## `ERROR:` che il motore stampa caricando: lo script non le intercetta.

const SALTA := ["res://.godot", "res://addons/godot_mcp"]
const SEGNAPOSTO := ["%", "{", "<", "*", "`"]

var _fatto := false
var _errori : PackedStringArray = []
var _avvisi : PackedStringArray = []


func _process(_dt : float) -> bool:
	if _fatto:
		return true
	_fatto = true
	var mostra_avvisi := OS.get_cmdline_user_args().has("--avvisi")

	var tutti : PackedStringArray = []
	_raccogli("res://", tutti)
	print("file nel progetto: %d" % tutti.size())

	_controlla_progetto()
	var n_ris := 0
	var n_gd := 0
	for p in tutti:
		var est := p.get_extension().to_lower()
		if est in ["tscn", "tres", "res"]:
			n_ris += 1
			_controlla_risorsa(p)
		elif est == "gd":
			n_gd += 1
			_controlla_script(p)
			_controlla_stringhe(p, true)
		elif est == "import":
			_controlla_stringhe(p, false)
	print("risorse caricate: %d, script compilati: %d" % [n_ris, n_gd])

	if mostra_avvisi:
		for a in _avvisi:
			print("AVVISO  ", a)
	print("avvisi (riferimenti nei commenti): %d%s" % [_avvisi.size(),
			"" if mostra_avvisi else "  (--avvisi per vederli)"])
	for e in _errori:
		print("ROTTO   ", e)
	print("ESITO: %s (%d rotture)" % ["OK" if _errori.is_empty() else "FALLITO", _errori.size()])
	quit(0 if _errori.is_empty() else 1)
	return true


func _raccogli(dir : String, out : PackedStringArray) -> void:
	## Le cartelle nascoste (.claude con gli esempi delle skill, .godot) non sono
	## del progetto: Godot stesso non le scansiona.
	if dir in SALTA or dir.get_file().begins_with(".") \
			or FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		out.append(dir.path_join(f))
	for s in d.get_directories():
		_raccogli(dir.path_join(s), out)


func _esiste(p : String) -> bool:
	if p.begins_with("uid://"):
		return ResourceUID.has_id(ResourceUID.text_to_id(p))
	return FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p) \
			or ResourceLoader.exists(p)


func _controlla_progetto() -> void:
	for prop in ProjectSettings.get_property_list():
		var nome : String = prop.name
		if nome.begins_with("autoload/"):
			var p := str(ProjectSettings.get_setting(nome)).trim_prefix("*")
			if not _esiste(p):
				_errori.append("autoload %s -> %s" % [nome.trim_prefix("autoload/"), p])
	for cfg in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()):
		if not FileAccess.file_exists(cfg) and not cfg.begins_with("res://addons/godot_mcp"):
			_errori.append("plugin abilitato mancante: %s" % cfg)
	var main := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main != "" and not _esiste(main):
		_errori.append("main_scene mancante: %s" % main)


func _controlla_risorsa(p : String) -> void:
	for dep in ResourceLoader.get_dependencies(p):
		## "uid://...::Tipo::res://percorso" oppure "res://percorso::Tipo"
		var pezzi := dep.split("::")
		var bersaglio := pezzi[pezzi.size() - 1] if pezzi[pezzi.size() - 1].begins_with("res://") else pezzi[0]
		var uid := pezzi[0] if pezzi[0].begins_with("uid://") else ""
		if not (_esiste(bersaglio) or (uid != "" and _esiste(uid))):
			_errori.append("%s -> dipendenza mancante %s" % [p, bersaglio])
	if ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE) == null:
		_errori.append("%s -> non si carica" % p)


func _controlla_script(p : String) -> void:
	var s := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE) as GDScript
	if s == null:
		_errori.append("%s -> non si carica" % p)
	elif not s.can_instantiate() and not s.is_abstract():
		_errori.append("%s -> non compila" % p)


func _controlla_stringhe(p : String, e_script : bool) -> void:
	var testo := FileAccess.get_file_as_string(p)
	## Con la ruvidezza disattivata (mode=1) `roughness/src_normal` non si legge:
	## i template ne hanno di vecchi che puntano nel vuoto senza danno.
	var src_normal_inerte := not e_script and testo.contains("roughness/mode=1")
	var re := RegEx.create_from_string("(?:\"|')(res://[^\"'\\n]+)(?:\"|')|(res://[^\\s\"'\\)\\]\\},;`]+)")
	var n := 0
	for riga in testo.split("\n"):
		n += 1
		var r := riga.strip_edges()
		if not e_script and (r.begins_with("source_file") or r.begins_with("dest_files") \
				or r.begins_with("path") \
				or (src_normal_inerte and r.begins_with("roughness/src_normal"))):
			continue
		## Un percorso dove si SCRIVE (render di uno strumento) puo' non esistere ancora.
		if r.contains("save_png") or r.contains("save_jpg") or r.contains("RegEx.create_from_string"):
			continue
		var commento := e_script and (r.begins_with("#") or r.begins_with("##"))
		for m in re.search_all(riga):
			var s := m.get_string(1) if m.get_string(1) != "" else m.get_string(2)
			s = s.split("::")[0].trim_suffix(".").trim_suffix("/")
			if SEGNAPOSTO.any(func(c): return c in s):
				continue
			if not commento and not e_script and riga.find("#") >= 0 and riga.find("#") < riga.find(s):
				commento = true
			if not _esiste(s):
				var voce := "%s:%d -> %s" % [p, n, s]
				if commento or (e_script and riga.find("#") >= 0 and riga.find("#") < riga.find(s)):
					_avvisi.append(voce)
				else:
					_errori.append(voce)
