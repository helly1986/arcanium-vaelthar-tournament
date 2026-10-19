extends Node3D

## CANCELLO DI VERIFICA dello schianto a terra: screenshot dalla camera VERA di
## gioco (stessi parametri della IsoCam), sul pavimento VERO dell'arena di prova
## (la Traccia Perduta, dove nacque, non c'e' piu').
##
## ⚠️ Perché non basta guardare l'effetto in una scenetta vuota: le zolle si
## leggono per contrasto contro il suolo e per dimensione contro il personaggio.
## Su un piano grigio a camera libera sembrano sempre giuste. È lo stesso motivo
## per cui le miniature dei modelli mentono.
##
## Lancio (NIENTE --headless: serve la finestra o non renderizza, e per giunta
## la GDExtension di Terrain3D non regge il renderer dummy):
##   Godot_v4.7-stable_win64.exe --path . res://arcanium/tools/verifica_schianto.tscn --resolution 1600x900

## ⚠️ `preload` e non il nome globale `SchiantoATerra`: i class_name entrano in
## `.godot/global_script_class_cache.cfg` solo quando l'EDITOR riscansiona il
## progetto, e questo strumento gira col solo runtime. Uno script nuovo di zecca
## darebbe "Identifier not declared" prima ancora di poter essere verificato.
const Schianto := preload("res://arcanium/systems/vfx/schianto_a_terra.gd")

const LIVELLO := "res://arcanium/levels/arena_prova.tscn"
## Dove finiscono gli scatti: primo argomento utente, o la cartella utente.
var FUORI : String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()

## Parametri copiati dalla IsoCam (cameras/iso_cam/iso_cam.gd): offset base,
## fov, zoom di default. Cambiarli qui vuol dire non verificare più niente.
const ISO_OFFSET := Vector3(0, 25.18, 25.18)
const ISO_FOV := 50.0
const ISO_ZOOM := 0.82

var _cam : Camera3D


func _ready() -> void:
	var scena : Node3D = load(LIVELLO).instantiate()
	add_child(scena)

	_cam = Camera3D.new()
	_cam.fov = ISO_FOV
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	add_child(_cam)
	_cam.make_current()

	await get_tree().process_frame
	await get_tree().process_frame

	## Il player della scena fa da riferimento di SCALA: senza un corpo umano
	## accanto non si può dire se una zolla è grossa o piccola.
	var player : Node3D = null
	var p := get_tree().get_nodes_in_group("player")
	if not p.is_empty():
		player = p[0]
	var centro : Vector3 = player.global_position if player else Vector3(0, 0, 16)

	## Si aspetta che la collisione dinamica di Terrain3D si generi attorno al
	## player, o il raggio verso il basso non trova niente e non nasce nulla.
	for _i in 20:
		await get_tree().physics_frame

	await _scatta("schianto_00_prima.png", centro, null)

	var fx = Schianto.al_punto(self, centro + Vector3(2.2, 0.0, 0.0),
			Vector3.UP, 1.4, Schianto.TERRA_TRACCIA)
	if fx == null:
		push_error("Schianto non creato.")
		get_tree().quit(1)
		return

	## Tre istanti: il fungo, le zolle in volo, il riposo. Sono le tre cose
	## diverse che l'effetto deve saper fare, e vanno guardate separatamente.
	## ⚠️ NON si aspetta col cronometro. Salvare un PNG da 1600x900 costa
	## parecchi decimi, e sommandoli gli scatti arrivavano molto più tardi di
	## quanto dicesse l'etichetta: ho fotografato un impatto già finito e ne ho
	## dedotto che "le zolle non si vedono", che era falso. Si aspetta invece
	## che l'EFFETTO STESSO raggiunga l'età voluta (`_eta`), e la si stampa
	## accanto al nome del file — così l'etichetta non può più mentire.
	for quando in [0.12, 0.40, 0.85, 1.60, 3.10]:
		await _eta_di(fx, quando)
		await _scatta("schianto_%.2f.png" % quando, centro, fx)

	get_tree().quit()


func _dopo(s : float) -> void:
	await get_tree().create_timer(s).timeout


## Aspetta che l'effetto abbia l'età voluta. Se nel frattempo si è liberato da
## solo, esce subito invece di restare appeso.
func _eta_di(fx : Node, quando : float) -> void:
	while is_instance_valid(fx) and fx._eta < quando:
		await get_tree().process_frame


func _scatta(nome : String, centro : Vector3, fx : Node) -> void:
	_cam.global_position = centro + ISO_OFFSET * ISO_ZOOM
	_cam.look_at(centro, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(FUORI + "/" + nome)
	if not is_instance_valid(fx):
		print("[schianto] %s   (nessun effetto vivo)" % nome)
		return
	## ⚠️ Non basta contare le zolle vive: "vive" vuol dire solo che il loro
	## ciclo non è finito, NON che si vedano. Qui si stampa dove stanno davvero
	## rispetto al suolo che hanno trovato — è l'unico modo di distinguere
	## "sprofondate sotto il terreno" da "ci sono ma non si leggono".
	var ferme := 0
	var sotto := 0
	var alta := -999.0
	for i in fx._pos.size():
		if fx._scala[i] <= 0.0:
			continue
		if fx._ferma_da[i] >= 0.0:
			ferme += 1
		var sopra_suolo : float = fx._pos[i].y - fx._suolo[i]
		if sopra_suolo < -0.05:
			sotto += 1
		alta = maxf(alta, sopra_suolo)
	print("[schianto] %s  età %.2fs | vive %d | ferme %d | SOTTO IL SUOLO %d | la più alta %.2f m"
			% [nome, fx._eta, fx._vive, ferme, sotto, alta])
