extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## ANTEPRIMA DI UNA CLIP SUL NEMICO VERO — con l'arma in mano e le sue tinte
## ═══════════════════════════════════════════════════════════════════════════
##
##   Godot.exe --path . res://arcanium/tools/anteprima_clip_nemico.tscn -- \
##       res://arcanium/characters/sylvorn_fante_spadone.tscn \
##       sword/sword_th_combo_01  <cartella_screenshot>  [frazioni: 0.1,0.3,...] \
##       [camera: x,y,z] [mira: x,y,z]
##
## Camera e mira sono opzionali: senza, il tre quarti frontale a due metri e
## mezzo che inquadra un gran colpo. Con, si va a guardare una MANO — e' nato
## per montare l'arco dell'arciere, dove il tre quarti mostra un puntino.
##
## Al posto della clip si puo' dare una MOSSA, `mossa:<id>` (es. `mossa:R1`):
## allora non si suona la clip nuda ma si chiama `_begin_move` del nemico, con
## tutto cio' che la mossa porta — finestra d'arma, strato, corda dell'arco
## che si tende. E' la differenza fra vedere il gesto e vedere il tiro.
##
## Istanzia la scena del nemico da sola su un pavimento, gli spegne l'AI
## (fisica off: senza bersaglio rimetterebbe l'idle a ogni frame) e gli fa
## suonare la clip con il SUO `_play`, cioe' con l'albero o l'AnimationPlayer
## che usa in gioco. Fotografa agli istanti chiesti e si chiude.
##
## ⚠️ La clip la manda avanti QUESTO tool, un sessantesimo per frame, con il
## mixer in modalita' manuale — non l'orologio. Salvare un PNG a 1080p blocca
## il processo per un decimo abbondante, e con l'orologio la clip intanto
## correva: con fotogrammi fitti (ogni 2%) l'etichetta diceva 78% e la posa
## era quella del 95%, e ci ho letto sopra un rilascio che non c'era
## (2026-09-14). Ogni scatto stampa comunque il playhead VERO.
##
## Con una MOSSA si armano anche i contatti, e ogni passo si chiama
## `_advance_attack_timeline` come farebbe la fisica: il rilascio arriva
## all'istante misurato, la freccia parte davvero verso il bersaglio finto e
## la corda si tende e scatta come in gioco.
##
## Diverso dal provino di Blender (`provino_clip.py`): quello rende il corpo
## nudo, questo rende quello che si vedra' in gioco — arma montata, scudo,
## varianti, tinte. Il provino serve a giudicare l'animazione; questo a
## giudicare la MOSSA.
##
## ⚠️ NON `--headless`: in headless lo scheletro non si muove.

var _scena : String = ""
var _clip : String = ""
var _cartella : String = ""
var _frazioni : PackedFloat32Array = [0.0, 0.25, 0.5, 0.75, 1.0]
var _cam : Camera3D
var _cam_pos : Vector3 = Vector3(-2.6, 1.7, 3.0)
var _cam_mira : Vector3 = Vector3(0.0, 1.1, 0.0)

## Un passo di clip per frame di processo, come a 60 Hz.
const PASSO := 1.0 / 60.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("uso: -- <scena.tscn> <Libreria/Clip> <cartella> [frazioni]")
		get_tree().quit(2)
		return
	_scena = args[0]
	_clip = args[1]
	_cartella = args[2]
	if args.size() >= 4:
		_frazioni = PackedFloat32Array()
		for s in str(args[3]).split(","):
			_frazioni.append(float(s))
	if args.size() >= 5:
		_cam_pos = _vettore(args[4])
	if args.size() >= 6:
		_cam_mira = _vettore(args[5])

	_costruisci_mondo()
	var f : Node3D = (load(_scena) as PackedScene).instantiate()
	add_child(f)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam.make_current()
	f.set_physics_process(false)
	for n in f.find_children("*", "SkeletonModifier3D", true, false):
		n.set("active", false)
	var mossa = null
	if _clip.begins_with("mossa:"):
		for m in f.move_set.moves:
			if m.id == _clip.trim_prefix("mossa:"):
				mossa = m
		if mossa == null:
			push_error("anteprima_clip_nemico: '%s' non ha la mossa '%s'" % [_scena.get_file(), _clip])
			get_tree().quit(1)
			return
		_clip = mossa.anim
	if not f.anim_player.has_animation(_clip):
		push_error("anteprima_clip_nemico: '%s' non ha la clip '%s'" % [_scena.get_file(), _clip])
		get_tree().quit(1)
		return
	var durata : float = f.anim_player.get_animation(_clip).length
	if mossa != null:
		## Un bersaglio finto davanti, cosi' mira e rilascio hanno qualcosa su
		## cui lavorare; la fisica resta spenta, e' la mossa che si guarda.
		var bersaglio := Node3D.new()
		bersaglio.position = f.global_transform.basis.z * 8.0 + Vector3(0, 1.0, 0)
		add_child(bersaglio)
		f.target = bersaglio
		f._begin_move(mossa)
		## I contatti si armano come in `_execute_move`, senza la sua attesa a
		## orologio (che con i PNG da salvare finirebbe prima della clip).
		f.set("_pending_contacts", f._contact_times(mossa).duplicate())
		f.set("_released_this_move", false)
	else:
		f._play(_clip, false)
	print("anteprima_clip_nemico: '%s' su %s, %.2f s" % [_clip, _scena.get_file(), durata])

	## Il mixer che suona: l'albero se il nemico ce l'ha, se no l'AnimationPlayer.
	var mixer : AnimationMixer = f.get("_albero") as AnimationMixer
	if mixer == null:
		mixer = f.anim_player
	mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	## Il tempo lo tiene il tool, non lo si rilegge dal nemico: all'ultimo
	## passo la clip finisce, l'AnimationPlayer la scarica e il playhead letto
	## torna a zero — e il ciclo non usciva piu' (il caricato, 4,00 s = 240
	## passi esatti). Lo si stampa a fianco per controllo.
	var t := 0.0
	var scattate := {}
	while t < durata + 0.05 and scattate.size() < _frazioni.size():
		mixer.advance(PASSO)
		t += PASSO
		if mossa != null:
			f._advance_attack_timeline()
		await get_tree().process_frame
		for fr in _frazioni:
			if not scattate.has(fr) and t >= fr * durata - 0.001:
				scattate[fr] = true
				await _scatta(fr, minf(t, durata), _playhead(f, durata))
	if mossa != null:
		f._clear_move_state()
	get_tree().quit(0)


func _vettore(s : String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## Il playhead della clip, letto come lo legge il nemico.
func _playhead(f : Node, durata : float) -> float:
	if f.has_method("_clip_pos"):
		return clampf(float(f._clip_pos()), 0.0, durata)
	return 0.0


func _scatta(fraz : float, t : float, letto : float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var nome := "%s/clip_%03d.png" % [_cartella, int(round(fraz * 100.0))]
	var err := img.save_png(nome)
	print("  %3.0f%%  t %.3f s (playhead letto %.3f)  %s" % [fraz * 100.0, t, letto, nome if err == OK else "SCREENSHOT FALLITO"])


func _costruisci_mondo() -> void:
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.38)
	env.ambient_light_energy = 0.7
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
	## Tre quarti frontale, un po' distante: un gran colpo dall'alto va alto.
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.position = _cam_pos
	_cam.look_at_from_position(_cam.position, _cam_mira, Vector3.UP)
	add_child(_cam)
