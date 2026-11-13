extends SceneTree

## Scrive il profilo della DIMORA FORTIFICATA (arcanium/levels/dungeon/
## profilo_dimora.tres) e i suoi temi in arcanium/levels/dungeon/temi_dimora/.
##
## Lo stile, chiesto dall'autore il 2026-11-13 su un riferimento di taverna
## isometrica: tetto che non si vede, muri alti, lampadari sospesi nel nulla
## che illuminano davvero, stanze piene di arredo con varieta' di legni,
## pietre e stoffe; colorato, ma su tinte scure da dark fantasy (non i rossi e
## gli ori saturi del riferimento). Accanto alle rovine buie, non al loro posto.
##
## Parte dal profilo delle rovine (pianta, nemici, trappole, pezzi comuni) e
## cambia solo cio' che fa la dimora. Si ritocca qui e si rilancia.
##
## Uso: godot --headless --path . --script res://arcanium/tools/genera_profilo_dimora.gd

const Tema := preload("res://arcanium/levels/dungeon/tema_stanza.gd")
const Pezzo := preload("res://arcanium/levels/dungeon/pezzo_tema.gd")
const Misura := preload("res://arcanium/levels/dungeon/misura_pezzo.gd")
const ARREDO := "res://assets/environment/dungeon/arredo/"
const PAVIMENTI := "res://assets/environment/dungeon/pavimenti/"
const TEMI_ROVINE := "res://arcanium/levels/dungeon/temi/"
const DEST := "res://arcanium/levels/dungeon/temi_dimora/"
const ROVINE := "res://arcanium/levels/dungeon/profilo_rovine.tres"
const PROFILO := "res://arcanium/levels/dungeon/profilo_dimora.tres"

const MURO := 0
const CENTRO := 1
const ANGOLO := 2
const SPARSO := 3
const FILE := 4

const INGRESSO := 0
const COMBATTIMENTO := 1
const CHIUSA := 2
const TESORO := 3


func _p(scena : String, posto : int, mn : int, mx : int, largo : float, alto : float,
		solido := true, fuoco := false, per_celle := 0.0, verso_camera := false, quota := 0.0) -> Resource:
	var p : Resource = Pezzo.new()
	p.scena = load(ARREDO + scena + (".tscn" if ResourceLoader.exists(ARREDO + scena + ".tscn") else ".glb"))
	p.posto = posto
	p.quanti_min = mn
	p.quanti_max = mx
	p.larghezza = largo
	p.altezza = alto
	p.solido = solido
	p.fuoco = fuoco
	p.celle_per_pezzo = per_celle
	p.verso_camera = verso_camera
	p.quota = quota
	return p


func _tema(nome : String, ruoli : Array, peso : float, pavimento : String, colore : Color,
		energia : float, arredo : Array, opzioni := {}) -> Resource:
	var t : Resource = Tema.new()
	t.nome = nome
	t.ruoli = PackedInt32Array(ruoli)
	t.peso = peso
	t.pavimento = load(PAVIMENTI + pavimento + ".tres") if pavimento != "" else null
	t.luce_colore = colore
	t.luce_energia = energia
	t.torce = opzioni.get("torce", true)
	t.bracieri = false
	t.colonne = opzioni.get("colonne", false)
	t.rovine_min = 0
	t.rovine_max = 0
	t.muri_minimi = opzioni.get("muri_minimi", 0)
	var a : Array[Resource] = []
	a.assign(arredo)
	t.arredo = a
	return t


func _ambiente() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.018, 0.022)
	## Una luce d'ambiente vera, tiepida e spenta: si legge tutta la stanza, e
	## i lampadari e le candele fanno le pozze calde sopra.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.46, 0.4, 0.38)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.15
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.1
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.045, 0.05)
	e.fog_density = 0.008
	## Dark fantasy: i colori ci sono, ma spenti.
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.8
	e.adjustment_contrast = 1.08
	e.adjustment_brightness = 1.0
	return e


## Un GRUPPO d'arredo come scena unica (una "scenetta": il tavolo con le sue
## panche): ogni parte e' [glb, misure volute in metri (x, y, z) dell'ingombro,
## posizione della base, rotazione y]. Il costruttore la tratta come un pezzo
## solo, scalato sull'ingombro di tutto il gruppo, con una sola collisione.
func _gruppo(nome : String, parti : Array) -> void:
	var radice := Node3D.new()
	radice.name = nome
	for parte in parti:
		var n : Node3D = (load(ARREDO + String(parte[0]) + ".glb") as PackedScene).instantiate()
		var box := Misura.ingombro(n)
		var voluto : Vector3 = parte[1]
		n.scale = Vector3(voluto.x / box.size.x, voluto.y / box.size.y, voluto.z / box.size.z)
		n.rotation.y = parte[3]
		n.position = parte[2]
		radice.add_child(n)
		n.owner = radice
	var scena := PackedScene.new()
	scena.pack(radice)
	var err := ResourceSaver.save(scena, ARREDO + nome + ".tscn")
	print("DIMORA: gruppo %s %s" % [nome, "ok" if err == OK else "ERRORE %d" % err])
	radice.free()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	## La tavolata: il tavolo apparecchiato lungo 3 m (il piano a ~0,85 m) e una
	## panca per lato. I GLB di Tripo hanno il lato lungo su z.
	_gruppo("tavolata", [
		["tavolo_banchetto", Vector3(1.55, 1.6, 3.0), Vector3.ZERO, 0.0],
		["panca", Vector3(0.45, 0.48, 2.6), Vector3(1.2, 0, 0), 0.0],
		["panca", Vector3(0.45, 0.48, 2.6), Vector3(-1.2, 0, 0), PI],
	])
	## Il tavolo da cucina con due sedie e una cesta accanto.
	_gruppo("angolo_cucina", [
		["tavolo_cucina", Vector3(2.0, 1.6, 1.2), Vector3.ZERO, 0.0],
		["sacco", Vector3(0.8, 0.78, 0.58), Vector3(1.45, 0, 0.2), 0.4],
		["cesta", Vector3(0.7, 0.44, 0.7), Vector3(-1.4, 0, 0.3), 0.0],
	])
	var nuovi := {
		## La sala grande: tavolate in file sotto i lampadari, il camino al muro,
		## arazzi, credenze e sedie: la scena del riferimento, a tinte scure.
		"sala_grande": _tema("Sala grande", [COMBATTIMENTO], 1.4, "lastricato", Color(1.0, 0.72, 0.48), 0.35, [
			_p("camino", MURO, 1, 1, 0.0, 3.8),
			_p("tavolata", FILE, 2, 6, 3.0, 0.0, true, false, 10.0),
			_p("arazzo", MURO, 2, 8, 0.0, 2.4, false, false, 10.0, false, 1.3),
			_p("credenza", MURO, 1, 4, 0.0, 2.4, true, false, 20.0),
			_p("sedia", MURO, 1, 6, 0.0, 1.4, true, false, 14.0),
			_p("pilastro_legno", ANGOLO, 2, 4, 0.0, 4.6),
			_p("barile", MURO, 1, 5, 0.7, 0.0, true, false, 16.0),
			_p("anfora", MURO, 1, 5, 0.0, 0.9, true, false, 16.0),
			_p("cesta", MURO, 0, 3, 0.7, 0.0, true, false, 25.0),
		]),
		## La cucina: il tavolo col calderone, le botti, la credenza dei piatti,
		## sacchi e ceste.
		"cucina": _tema("Cucina", [COMBATTIMENTO, CHIUSA], 1.0, "terra_paglia", Color(1.0, 0.65, 0.4), 0.35, [
			_p("angolo_cucina", SPARSO, 1, 3, 3.6, 0.0, true, false, 20.0),
			_p("credenza", MURO, 1, 4, 0.0, 2.4, true, false, 15.0),
			_p("botti_rastrelliera", MURO, 1, 2, 2.0, 0.0, true, false, 45.0),
			_p("barile", MURO, 2, 6, 0.7, 0.0, true, false, 10.0),
			_p("pila_casse", MURO, 0, 2, 1.6, 0.0, true, false, 45.0),
			_p("sacco", MURO, 1, 5, 0.8, 0.0, true, false, 12.0),
			_p("cesta", MURO, 1, 4, 0.7, 0.0, true, false, 14.0),
			_p("anfora", SPARSO, 1, 3, 0.0, 0.9, true, false, 30.0),
		]),
		## La cantina: botti sulle rastrelliere, casse, sacchi.
		"cantina": _tema("Cantina", [COMBATTIMENTO, CHIUSA], 0.8, "mattoni_spina", Color(1.0, 0.62, 0.38), 0.3, [
			_p("botti_rastrelliera", MURO, 2, 6, 2.0, 0.0, true, false, 14.0),
			_p("barile", SPARSO, 2, 6, 0.7, 0.0, true, false, 18.0),
			_p("pila_casse", MURO, 1, 3, 1.6, 0.0, true, false, 30.0),
			_p("cassa", SPARSO, 1, 4, 0.9, 0.0, true, false, 25.0),
			_p("sacco", SPARSO, 1, 4, 0.8, 0.0, true, false, 25.0),
		]),
		## La cappella della casata: l'altare, le panche in file, le statue,
		## gli arazzi.
		"cappella": _tema("Cappella", [COMBATTIMENTO, CHIUSA], 0.9, "mattoni_spina", Color(0.85, 0.7, 0.9), 0.35, [
			_p("altare", CENTRO, 1, 1, 2.6, 0.0),
			_p("panca", FILE, 2, 8, 2.4, 0.0, true, false, 14.0),
			_p("statua", MURO, 2, 4, 0.0, 3.0, true, false, 30.0),
			_p("candelabro", ANGOLO, 2, 4, 0.0, 2.0, true, true),
			_p("arazzo", MURO, 1, 4, 0.0, 2.4, false, false, 30.0, false, 1.3),
			_p("leggio", SPARSO, 1, 2, 0.0, 1.3, true, false, 60.0),
		]),
	}
	var lista : Array[Resource] = []
	for nome in nuovi:
		var percorso : String = DEST + nome + ".tres"
		var err := ResourceSaver.save(nuovi[nome], percorso)
		print("DIMORA: %s %s" % [percorso, "ok" if err == OK else "ERRORE %d" % err])
		lista.append(load(percorso))
	## Dalle rovine si prendono i temi che stanno bene in una dimora.
	for nome in ["atrio", "biblioteca", "armeria", "magazzino", "tesoro"]:
		lista.append(load(TEMI_ROVINE + nome + ".tres"))
	var p : Resource = load(ROVINE).duplicate()
	p.temi = lista
	## Stanze da casa, non da cattedrale: nel riferimento la sala e' larga una
	## dozzina di metri e piena. Con le stanze delle rovine (fino a 40 m) l'arredo
	## si perdeva nel pavimento vuoto. Piu' stanze, piu' piccole.
	p.stanza_lato_min = 5
	p.stanza_lato_max = 11
	p.stanze_min = 7
	p.stanze_max = 11
	p.larghezza = 52
	p.profondita = 52
	p.muro_alto = 4.6
	p.muro_basso = 0.9
	p.pilastro_ogni = 6.0
	## Niente rovine: sassi, macerie e pezzi grossi crollati non c'entrano.
	p.sasso = null
	p.colonna_caduta = null
	p.macerie = null
	p.lastre = null
	p.braciere = null
	var grossi : Array[PackedScene] = []
	p.pezzi_grossi = grossi
	p.decal_muschio = [] as Array[Texture2D]
	p.decal_ogni_celle = 10.0
	p.torce_per_stanza_min = 1
	p.torce_per_stanza_max = 3
	p.luce_stanza_energia = 0.3
	## Le applique a tre candele al posto delle torce: e' una casa, non una
	## grotta.
	p.torcia = load(ARREDO + "applique.glb")
	p.lampadario = load(ARREDO + "lampadario_anello.glb")
	p.lampadario_largo = 2.4
	p.luce_lampadario_energia = 3.4
	p.lampadario_quota = 3.6
	p.ambiente = _ambiente()
	var err := ResourceSaver.save(p, PROFILO)
	print("DIMORA: profilo %s" % ("ok" if err == OK else "ERRORE %d" % err))
	quit()
