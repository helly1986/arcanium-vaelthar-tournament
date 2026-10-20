extends SceneTree

## Scrive i TEMI delle stanze del mini-dungeon (tema_stanza.gd) in
## arcanium/levels/dungeon/temi/ e li aggancia al profilo delle rovine, col
## pavimento dei corridoi. I temi sono dati: si ritoccano nell'inspector, o
## qui e si rilancia.
##
## Uso: godot --headless --path . --script res://arcanium/tools/genera_temi_dungeon.gd

const Tema := preload("res://arcanium/levels/dungeon/tema_stanza.gd")
const Pezzo := preload("res://arcanium/levels/dungeon/pezzo_tema.gd")
const ARREDO := "res://assets/environment/dungeon/arredo/"
const PAVIMENTI := "res://assets/environment/dungeon/pavimenti/"
const DEST := "res://arcanium/levels/dungeon/temi/"
const PROFILO := "res://arcanium/levels/dungeon/profilo_rovine.tres"

const MURO := 0
const CENTRO := 1
const ANGOLO := 2
const SPARSO := 3
const FILE := 4

const INGRESSO := 0
const COMBATTIMENTO := 1
const CHIUSA := 2
const TESORO := 3


## [scena, posto, min, max, larghezza, altezza, solido, fuoco, celle_per_pezzo]
func _p(scena : String, posto : int, mn : int, mx : int, largo : float, alto : float,
		solido := true, fuoco := false, per_celle := 0.0, verso_camera := false) -> Resource:
	var p : Resource = Pezzo.new()
	p.scena = load(ARREDO + scena + ".glb")
	p.posto = posto
	p.quanti_min = mn
	p.quanti_max = mx
	p.larghezza = largo
	p.altezza = alto
	p.solido = solido
	p.fuoco = fuoco
	p.celle_per_pezzo = per_celle
	p.verso_camera = verso_camera
	return p


## Un pezzo appeso al muro: la base a `quota` metri da terra.
func _appeso(p : Resource, quota : float) -> Resource:
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
	## Il riempimento e' un terzo di quello disegnato prima: dark fantasy, a
	## illuminare sono i fuochi (2026-10-20).
	t.luce_energia = energia * 0.3
	t.torce = opzioni.get("torce", true)
	t.bracieri = opzioni.get("bracieri", false)
	t.colonne = opzioni.get("colonne", false)
	t.rovine_min = opzioni.get("rovine_min", 0)
	t.rovine_max = opzioni.get("rovine_max", 0)
	t.muri_minimi = opzioni.get("muri_minimi", 0)
	var a : Array[Resource] = []
	a.assign(arredo)
	t.arredo = a
	return t


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	var temi := {
		## L'ingresso: la sala d'onore della casata, statue e vessilli.
		"atrio": _tema("Atrio", [INGRESSO], 1.0, "lastricato", Color(1.0, 0.8, 0.55), 0.6, [
			_p("statua", MURO, 2, 6, 0.0, 2.8, true, false, 30.0),
			## Lo stendardo e' un drappo da muro: alto 1,8 m e appeso a 1,1 m da terra,
			## con la cima sotto il bordo del muro (3,2 m).
			_appeso(_p("vessillo_dawnkeep", MURO, 2, 6, 0.0, 1.8, false, false, 25.0), 1.1),
			_p("candelabro", ANGOLO, 2, 2, 0.0, 2.0, true, true),
		], {"bracieri": true, "colonne": true}),
		"cripta": _tema("Cripta", [COMBATTIMENTO, CHIUSA], 1.0, "mattoni_spina", Color(0.6, 0.7, 1.0), 0.4, [
			_p("sarcofago", FILE, 2, 12, 2.4, 0.0, true, false, 12.0),
			_p("candelabro", ANGOLO, 2, 4, 0.0, 2.0, true, true),
			_p("ossa", SPARSO, 1, 6, 1.3, 0.0, false, false, 25.0),
			_p("anfora", SPARSO, 0, 4, 0.0, 0.9, true, false, 35.0),
		]),
		"armeria": _tema("Armeria", [COMBATTIMENTO], 1.0, "legno_assi", Color(1.0, 0.75, 0.5), 0.5, [
			_p("rastrelliera", MURO, 2, 8, 2.2, 0.0, true, false, 14.0),
			_p("rastrelliera", FILE, 0, 4, 2.2, 0.0, true, false, 25.0, true),
			_p("manichino", SPARSO, 1, 5, 0.0, 1.9, true, false, 25.0),
			_p("tavolo", SPARSO, 0, 2, 2.4, 0.0, true, false, 60.0),
			_p("barile", SPARSO, 1, 6, 0.7, 0.0, true, false, 25.0),
			_p("cassa", SPARSO, 0, 4, 0.9, 0.0, true, false, 35.0),
		], {"bracieri": true, "muri_minimi": 8}),
		"biblioteca": _tema("Biblioteca", [COMBATTIMENTO, CHIUSA], 1.0, "legno_assi", Color(1.0, 0.7, 0.45), 0.45, [
			_p("scaffale", MURO, 3, 14, 0.0, 2.6, true, false, 8.0),
			## Le corsie: scaffali in file in mezzo alla sala. Servono anche quando i
			## muri utili sono pochi (stanze circondate da corridoi e porte).
			_p("scaffale", FILE, 2, 8, 0.0, 2.6, true, false, 14.0, true),
			_p("leggio", SPARSO, 1, 3, 0.0, 1.3, true, false, 50.0),
			_p("libri", SPARSO, 2, 8, 1.0, 0.0, false, false, 15.0),
			_p("candelabro", ANGOLO, 2, 2, 0.0, 2.0, true, true),
			_p("tavolo", SPARSO, 0, 2, 2.4, 0.0, true, false, 50.0),
		], {"muri_minimi": 14}),
		"magazzino": _tema("Magazzino", [COMBATTIMENTO], 0.8, "", Color(1.0, 0.72, 0.45), 0.5, [
			_p("pila_casse", MURO, 2, 8, 1.6, 0.0, true, false, 15.0),
			_p("barile", SPARSO, 2, 10, 0.7, 0.0, true, false, 12.0),
			_p("sacco", SPARSO, 2, 8, 0.8, 0.0, true, false, 15.0),
			_p("cesta", SPARSO, 1, 4, 0.7, 0.0, true, false, 30.0),
			_p("cassa", SPARSO, 1, 8, 0.9, 0.0, true, false, 15.0),
		], {"bracieri": true}),
		"rituale": _tema("Sala rituale", [COMBATTIMENTO, CHIUSA], 1.0, "basalto_rune", Color(0.75, 0.5, 1.0), 0.6, [
			_p("altare", CENTRO, 1, 1, 2.4, 0.0),
			_p("candelabro", ANGOLO, 2, 4, 0.0, 2.0, true, true),
			_p("statua", MURO, 0, 4, 0.0, 2.8, true, false, 40.0),
			_p("ossa", SPARSO, 0, 4, 1.3, 0.0, false, false, 35.0),
		]),
		"prigione": _tema("Prigione", [CHIUSA, COMBATTIMENTO], 0.8, "terra_paglia", Color(0.7, 0.8, 0.6), 0.3, [
			_p("gabbia", SPARSO, 2, 8, 0.0, 2.0, true, false, 18.0),
			_p("ossa", SPARSO, 1, 6, 1.3, 0.0, false, false, 20.0),
			_p("sacco", SPARSO, 0, 4, 0.8, 0.0, true, false, 35.0),
			_p("barile", SPARSO, 0, 3, 0.7, 0.0, true, false, 45.0),
		]),
		"tesoro": _tema("Camera del tesoro", [TESORO], 1.0, "marmo_oro", Color(1.0, 0.8, 0.4), 0.9, [
			_p("oro", SPARSO, 2, 10, 1.6, 0.0, false, false, 18.0),
			_p("statua", ANGOLO, 2, 4, 0.0, 2.8, true, false, 50.0),
			_p("anfora", SPARSO, 1, 6, 0.0, 0.9, true, false, 30.0),
			_p("candelabro", ANGOLO, 0, 2, 0.0, 2.0, true, true),
		]),
		## Le rovine di prima: niente arredo di tema, colonne e macerie.
		"rovine": _tema("Rovine", [COMBATTIMENTO], 1.0, "", Color(1.0, 0.72, 0.45), 0.5, [],
			{"bracieri": true, "colonne": true, "rovine_min": 1, "rovine_max": 3}),
	}
	var lista : Array[Resource] = []
	for nome in temi:
		var t : Resource = temi[nome]
		var percorso : String = DEST + nome + ".tres"
		var err := ResourceSaver.save(t, percorso)
		print("TEMI: %s %s" % [percorso, "ok" if err == OK else "ERRORE %d" % err])
		lista.append(load(percorso))
	var profilo : Resource = load(PROFILO)
	profilo.temi = lista
	profilo.materiale_corridoio = load(PAVIMENTI + "ciottoli_scuri.tres")
	const DECAL := "res://assets/environment/dungeon/decal/"
	var crepe : Array[Texture2D] = [load(DECAL + "crepa_1.png"), load(DECAL + "crepa_2.png"), load(DECAL + "crepa_3.png")]
	var sporco : Array[Texture2D] = [load(DECAL + "sporco_1.png"), load(DECAL + "sporco_2.png")]
	var muschio : Array[Texture2D] = [load(DECAL + "muschio_1.png")]
	profilo.decal_crepe = crepe
	profilo.decal_sporco = sporco
	profilo.decal_muschio = muschio
	profilo.uscita = load(ARREDO + "uscita_scala.glb")
	profilo.piastra = load(ARREDO + "piastra.glb")
	profilo.bocca_trappola = load(ARREDO + "bocca_trappola.glb")
	profilo.fontana = load(ARREDO + "fontana.glb")
	profilo.ponticello = load(ARREDO + "ponticello.glb")
	var grossi : Array[PackedScene] = [load(ARREDO + "testa_colosso.glb"), load(ARREDO + "lampadario.glb")]
	profilo.pezzi_grossi = grossi
	print("TEMI: profilo %s" % ("ok" if ResourceSaver.save(profilo, PROFILO) == OK else "ERRORE"))
	quit()
