extends SceneTree

## La PROVA DI MOVIMENTO: un personaggio in gioco fotografato mentre si muove,
## da davanti e da dietro, per trovare i PESI sbagliati — cio' che a riposo e
## in una posa ferma non si vede: pantaloni che bucano la veste, pannelli
## tirati in mezzo alle gambe, schegge che restano indietro col bacino.
## Richiesta dell'utente del 2026-10-28, dopo la tunica di Zarine: «ci fa
## capire brillantemente se ci sono problemi di pesi».
##
## Nel dungeon di prova, con due luci sul soggetto (davanti e dietro: il retro
## di una veste e' dove si vedono i buchi) e due camere che lo seguono:
##   - un CAMPIONE (una casata, es. aethon): fermo in guardia, quattro passi,
##     la fermata, due colpi, una schivata. I nemici del dungeon si tolgono.
##   - un NEMICO (una scena di arcanium/characters, es. sylvorn_mago): messo a
##     quattro metri dal giocatore, si muove con la sua IA — si avvicina,
##     attacca, gira: sono le sue clip vere, con il suo AnimationTree.
##
## Esce un foglio per soggetto, <nome>_movimento.png: due righe per istante,
## sopra la camera davanti e sotto quella dietro, in ordine di tempo.
##
## Con `spenta` fra gli argomenti la stoffa simulata resta spenta (solo
## skinning): se un difetto c'e' anche cosi', sono i PESI, non la simulazione.
##
## Con `clip=<libreria/nome>` il nemico non usa la sua IA: suona quella clip
## dall'inizio alla fine, fotografata a passi regolari (per guardare una clip
## nuova, che l'IA sceglie a caso).
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --fixed-fps 60 --script res://arcanium/tools/prova_movimento.gd -- <cartella> [soggetti...]
## Senza soggetti: i sei campioni e i nemici Tripo (NEMICI_TRIPO).

const CAMPIONI := ["dawnkeep", "sylvorn", "aethon", "verath", "amareth", "vorrkai"]
const NEMICI_TRIPO := ["sylvorn_mago", "sylvorn_comandante", "sylvorn_soldato_scelto"]
const DUNGEON := "res://arcanium/levels/dungeon/dungeon_prova.tscn"
const ARENA := "res://arcanium/levels/arena_senza_fuoco.tscn"
## Un riquadro del foglio, e quanti per riga.
const LATO := 300
const COLONNE := 8

var _dir := ""
var _spenta := false
var _clip := ""
var _scatti : Array[Image] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else OS.get_user_data_dir()
	_spenta = "spenta" in args
	for a in args:
		if String(a).begins_with("clip="):
			_clip = String(a).trim_prefix("clip=")
	var soggetti : Array = Array(args.slice(1)).filter(func(x): return x != "spenta" and not String(x).begins_with("clip="))
	if soggetti.is_empty():
		soggetti = CAMPIONI + NEMICI_TRIPO
	await process_frame
	for s in soggetti:
		if ResourceLoader.exists("res://arcanium/resources/campioni/%s.tres" % s):
			await _campione(String(s))
		elif ResourceLoader.exists("res://arcanium/characters/%s.tscn" % s):
			await _nemico(String(s))
		else:
			push_error("prova_movimento: '%s' non e' ne' una casata ne' una scena di nemico" % s)
	quit()


func _dungeon(casa : String) -> Node:
	var salva : Node = root.get_node("SaveManager")
	salva._house = casa
	root.get_node("EquipmentLoadout").clear_all()
	salva._tecniche_del_campione()
	var scena : Node = load(DUNGEON).instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 40:
		await process_frame
	for e in get_nodes_in_group("nemico_dungeon"):
		e.queue_free()
	return scena


func _campione(casa : String) -> void:
	var scena : Node = await _dungeon(casa)
	var pl : Node3D = scena.get_node("Player")
	var camere := _attrezza(pl)
	## La nebbia di guerra vela il giocatore per qualche secondo all'ingresso.
	await _attesa(6.0)
	_spegni_stoffa(pl)
	_scatti.clear()
	await _scatto(pl, camere)
	Input.action_press("move_up")
	for k in 4:
		await _attesa(0.3)
		await _scatto(pl, camere)
	Input.action_release("move_up")
	await _attesa(1.2)
	await _scatto(pl, camere)
	for colpo in 2:
		pl.attack()
		for k in 3:
			await _attesa(0.2)
			await _scatto(pl, camere)
	await _attesa(0.8)
	pl.dodge()
	for k in 3:
		await _attesa(0.15)
		await _scatto(pl, camere)
	_foglio(casa)
	await _via(scena)


## Il nemico nell'ARENA aperta del prologo, senza il boss e la sua regia: nel
## dungeon il Mago, che tiene le distanze, usciva dalla stanza e le camere
## restavano dietro un muro (2026-10-28).
func _nemico(nome : String) -> void:
	var salva : Node = root.get_node("SaveManager")
	salva._house = "dawnkeep"
	root.get_node("EquipmentLoadout").clear_all()
	salva._tecniche_del_campione()
	var scena : Node = load(ARENA).instantiate()
	for via in ["SenzaNome", "PrologueDirector", "BossBarLayer"]:
		var n := scena.get_node_or_null(via)
		if n != null:
			scena.remove_child(n)
			n.free()
	root.add_child(scena)
	for k in 40:
		await process_frame
	var pl : Node3D = scena.get_node("Player")
	## Tutti e due al centro dell'arena: al punto di partenza del giocatore la
	## camera dietro il nemico finiva nelle macerie del bordo.
	pl.global_position = Vector3(0, pl.global_position.y, -2.0)
	var e : Node3D = (load("res://arcanium/characters/%s.tscn" % nome) as PackedScene).instantiate()
	scena.add_child(e)
	e.global_position = Vector3(0, pl.global_position.y + 0.1, 2.0)
	e.look_at(pl.global_position, Vector3.UP, true)
	var camere := _attrezza(e)
	## Con una clip sola l'IA resta spenta da subito: altrimenti nei sei
	## secondi d'attesa il Mago evocava le sue Eco, che coprivano le camere.
	if _clip != "":
		e.set_physics_process(false)
		e.set_process(false)
	await _attesa(6.0)
	_spegni_stoffa(e)
	_scatti.clear()
	var ap : AnimationPlayer = e.get("anim_player")
	if _clip != "" and ap != null and ap.has_animation(_clip):
		e.set_physics_process(false)
		e.set_process(false)
		## Suona di seguito, senza salti: con `seek` a ogni scatto la stoffa
		## simulata vedeva il corpo teletrasportarsi e non cadeva mai.
		var lungo := ap.get_animation(_clip).length
		ap.play(_clip)
		for k in 16:
			await _scatto(e, camere)
			await _attesa(lungo / 16.0)
		_foglio(nome + "_" + _clip.get_file())
		await _via(scena)
		return
	for k in 16:
		await _scatto(e, camere)
		## Quale clip suona a ogni istante: per sapere quale rifare.
		if ap != null:
			print("ISTANTE %d: %s a %.2f s" % [k, ap.current_animation, ap.current_animation_position])
		await _attesa(0.35)
	_foglio(nome)
	await _via(scena)


## Due luci e due camere figlie del soggetto: lo seguono ovunque vada.
func _attrezza(soggetto : Node3D) -> Array[Camera3D]:
	for z in [2.0, -2.0]:
		var l := OmniLight3D.new()
		soggetto.add_child(l)
		l.position = Vector3(0, 1.7, z)
		l.omni_range = 7.0
		l.light_energy = 2.5
	var camere : Array[Camera3D] = []
	for pos in [Vector3(1.5, 1.2, 2.8), Vector3(1.5, 1.2, -2.8)]:
		var c := Camera3D.new()
		soggetto.add_child(c)
		c.position = pos
		c.fov = 40.0
		camere.append(c)
	return camere


func _spegni_stoffa(soggetto : Node) -> void:
	if not _spenta:
		return
	for st in soggetto.find_children("StoffaSimulata", "", true, false):
		for so in st._solver:
			st._accendi(so, false)
		st.set_process(false)


func _scatto(soggetto : Node3D, camere : Array[Camera3D]) -> void:
	for c in camere:
		c.current = true
		c.look_at(soggetto.global_position + Vector3(0, 0.95, 0))
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var h := img.get_height()
		img = img.get_region(Rect2i(img.get_width() / 2 - h * 2 / 5, h / 20, h * 4 / 5, h * 9 / 10))
		img.resize(LATO, LATO * 9 / 8)
		_scatti.append(img)


## Il foglio: per ogni istante la camera davanti sopra e quella dietro sotto.
func _foglio(nome : String) -> void:
	var istanti := _scatti.size() / 2
	var righe := (istanti + COLONNE - 1) / COLONNE
	var alto := LATO * 9 / 8
	var foglio := Image.create(LATO * mini(istanti, COLONNE), alto * 2 * righe, false, Image.FORMAT_RGB8)
	for i in istanti:
		var x := (i % COLONNE) * LATO
		var y := (i / COLONNE) * alto * 2
		for k in 2:
			var s := _scatti[i * 2 + k]
			s.convert(Image.FORMAT_RGB8)
			foglio.blit_rect(s, Rect2i(0, 0, LATO, alto), Vector2i(x, y + k * alto))
	var p := _dir.path_join("%s_movimento%s.png" % [nome, "_spenta" if _spenta else ""])
	foglio.save_png(p)
	print("MOVIMENTO: %s, %d istanti -> %s" % [nome, istanti, p])


func _attesa(secondi : float) -> void:
	await create_timer(secondi, true, false, true).timeout


func _via(scena : Node) -> void:
	Input.action_release("move_up")
	root.remove_child(scena)
	scena.queue_free()
	for k in 3:
		await process_frame
