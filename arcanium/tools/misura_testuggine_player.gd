extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## MISURA DELLA TESTUGGINE SUL PLAYER — portata vera, e come si vede
## ═══════════════════════════════════════════════════════════════════════════
##
##   Godot.exe --path . res://arcanium/tools/misura_testuggine_player.tscn -- \
##       [cartella_screenshot] [frazioni es. 0.30,0.72,1.0]
##
## ⚠️ NON `--headless`: in headless l'AnimationTree avanza ma lo SCHELETRO no
## (vedi la memoria «in headless le pose non avanzano»), e la misura tornerebbe
## la posa di riposo con un numero rassicurante e falso.
##
## Cosa fa: istanzia il player da solo su un pavimento, gli alza la guardia
## come fa il gioco (`guarding = true`, l'albero sfuma la posa da se'), lancia
## la Legione Testuggine e, a ogni frame di fisica, registra quanto la MANO
## DESTRA e la PUNTA della lama si spingono avanti rispetto all'origine del
## player. Alla fine stampa la portata massima e a che punto del gesto cade.
##
## E' il numero che va in `legione_testuggine.tres` al posto di quello del
## Fante (avambraccio al 131%): finche' non e' stato scritto li', la portata
## nel .tres e' un ripiego.

const TECNICA := "res://arcanium/resources/tecniche_guerra/legione_testuggine.tres"
const PLAYER := "res://characters/player_dawnkeep_v4.tscn"

var _cartella : String = ""
var _frazioni : PackedFloat32Array = [0.30, 0.72, 1.0]
var _scattate : Dictionary = {}
var _player : Node3D
var _caster : Node
var _sk : Skeleton3D
var _lama : Node3D
var _campioni : Array = []   # [t, frazione, avanti_mano, avanti_punta, alto_punta]
var _durata : float = 0.0
var _cam : Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_cartella = args[0]
	if args.size() >= 2:
		_frazioni = PackedFloat32Array()
		for s in str(args[1]).split(","):
			_frazioni.append(float(s))

	_costruisci_mondo()
	var flags := get_node_or_null("/root/PlayerFlags")
	var tecnica : Resource = load(TECNICA)
	var flag : String = str(tecnica.get("unlock_flag"))
	var era : bool = flags != null and flags.has(flag)
	if flags != null:
		flags.set_flag(flag)

	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.05, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	## ⚠️ La scena del player porta la SUA camera (l'isometrica del gioco), che
	## diventa `current` entrando nell'albero dopo la nostra: senza questa riga
	## lo screenshot e' il player visto da venti metri, con la HUD sotto.
	_cam.make_current()
	_caster = _player.get_node_or_null("TecnicaGuerraCaster")
	_sk = _player.find_child("GeneralSkeleton", true, false)
	_lama = _player.find_child("Sword", true, false)
	if _caster == null or _sk == null:
		push_error("misura_testuggine: manca il caster o lo scheletro.")
		get_tree().quit(1)
		return

	## Guardia su come in gioco: l'albero la sfuma (`set_guarding`). Si aspetta
	## che sia arrivata prima di lanciare, altrimenti si misura un braccio che
	## parte da una posa a meta'.
	_player.guarding = true
	await get_tree().create_timer(0.8).timeout
	var blend : float = float(_player.animation_tree.get("parameters/Guarding/blend_amount"))
	print("misura_testuggine: guardia al %.0f%%" % (blend * 100.0))

	if not _caster.lancia(tecnica):
		push_error("misura_testuggine: lancia() rifiutato.")
		get_tree().quit(1)
		return
	_durata = float(_caster.get("_durata"))
	print("misura_testuggine: affondo partito, durata %.2f s" % _durata)

	## Un giro di fisica dopo l'altro finche' il gesto e' in corso.
	while _caster.in_corso() != null:
		await get_tree().physics_frame
		_campiona()
	## e qualche frame di rientro, per vedere il braccio tornare in guardia
	for _i in 20:
		await get_tree().physics_frame
		_campiona()
	_riassunto()
	if flags != null and not era:
		flags.clear(flag)
	get_tree().quit(0)


func _campiona() -> void:
	var t : float = float(_caster.get("_t")) if _caster.in_corso() != null else _durata
	var fraz : float = t / maxf(_durata, 0.01)
	var origine : Vector3 = _player.global_position
	var avanti : Vector3 = _player.global_transform.basis.z
	avanti.y = 0.0
	avanti = avanti.normalized()
	var mano_idx := _sk.find_bone("RightHand")
	var mano : Vector3 = _sk.global_transform * _sk.get_bone_global_pose(mano_idx).origin
	var punta : Vector3 = _punta_lama()
	var d_mano : float = (mano - origine).dot(avanti)
	var d_punta : float = (punta - origine).dot(avanti)
	_campioni.append([t, fraz, d_mano, d_punta, punta.y - origine.y])
	for f in _frazioni:
		if not _scattate.has(f) and fraz >= f:
			_scattate[f] = true
			_scatta(f, d_punta)


## La punta: l'estremo del box di collisione della lama lungo il suo asse
## lungo, in coordinate mondo. Se l'arma non ha un box, si ripiega sulla mano.
func _punta_lama() -> Vector3:
	if _lama == null:
		return Vector3.ZERO
	var forma : CollisionShape3D = null
	for c in _lama.find_children("*", "CollisionShape3D", true, false):
		forma = c
		break
	if forma == null or not (forma.shape is BoxShape3D):
		return _lama.global_position
	var box := forma.shape as BoxShape3D
	var mezzo : Vector3 = box.size * 0.5
	## L'asse piu' lungo del box e' la lama; si prendono i due estremi e si
	## tiene quello piu' lontano dall'impugnatura (il pivot dell'arma).
	var asse := Vector3.ZERO
	if mezzo.x >= mezzo.y and mezzo.x >= mezzo.z:
		asse = Vector3(mezzo.x, 0, 0)
	elif mezzo.y >= mezzo.z:
		asse = Vector3(0, mezzo.y, 0)
	else:
		asse = Vector3(0, 0, mezzo.z)
	var a : Vector3 = forma.global_transform * asse
	var b : Vector3 = forma.global_transform * (-asse)
	var impugnatura : Vector3 = _lama.global_position
	return a if a.distance_to(impugnatura) >= b.distance_to(impugnatura) else b


func _scatta(fraz : float, d_punta : float) -> void:
	if _cartella == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var nome := "%s/testuggine_player_%02d.png" % [_cartella, int(round(fraz * 100.0))]
	var err := img.save_png(nome)
	print("  screenshot al %.0f%% (punta a %.2f m): %s" % [fraz * 100.0, d_punta, nome if err == OK else "FALLITO"])


func _riassunto() -> void:
	var max_mano := -1.0
	var max_punta := -1.0
	var t_mano := 0.0
	var t_punta := 0.0
	var alto_al_max := 0.0
	for c in _campioni:
		if c[2] > max_mano:
			max_mano = c[2]
			t_mano = c[1]
		if c[3] > max_punta:
			max_punta = c[3]
			t_punta = c[1]
			alto_al_max = c[4]
	print()
	print("═══ PORTATA DELLA TESTUGGINE SUL PLAYER ═══")
	print("  mano destra:   avanti %.2f m   al %.0f%% del gesto" % [max_mano, t_mano * 100.0])
	print("  punta lama:    avanti %.2f m   al %.0f%% del gesto   (a %.2f m da terra)" % [max_punta, t_punta * 100.0, alto_al_max])
	print("  campioni: %d   durata %.2f s" % [_campioni.size(), _durata])
	print("  finestra dichiarata: 40%%..72%%  -> punta a: %s" % _punta_in(0.40, 0.72))
	print("  => `portata` nel .tres = quanto la PUNTA arriva avanti al contatto, arrotondato per difetto.")


func _punta_in(da : float, a : float) -> String:
	var lo := 99.0
	var hi := -99.0
	for c in _campioni:
		if c[1] >= da and c[1] <= a:
			lo = minf(lo, c[3])
			hi = maxf(hi, c[3])
	return "da %.2f a %.2f m" % [lo, hi]


func _costruisci_mondo() -> void:
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.38)
	env.ambient_light_energy = 0.6
	amb.environment = env
	add_child(amb)
	var luce := DirectionalLight3D.new()
	luce.rotation_degrees = Vector3(-40, -60, 0)
	luce.light_energy = 1.3
	luce.shadow_enabled = true
	add_child(luce)
	var suolo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	forma.shape = box
	suolo.add_child(forma)
	suolo.position = Vector3(0, -0.1, 0)
	add_child(suolo)
	var piano := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	piano.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.14, 0.11)
	piano.material_override = m
	add_child(piano)
	## Stessa inquadratura del popup: tre quarti frontale dal lato della spada.
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.position = Vector3(-1.9, 1.35, 1.75)
	_cam.look_at_from_position(_cam.position, Vector3(0.05, 1.0, 0.15), Vector3.UP)
	add_child(_cam)
