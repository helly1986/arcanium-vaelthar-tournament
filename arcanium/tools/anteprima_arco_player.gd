extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## ANTEPRIMA DELL'ARCO SUL PLAYER — come si vede il tiro
## ═══════════════════════════════════════════════════════════════════════════
##
##   Godot.exe --path . res://arcanium/tools/anteprima_arco_player.tscn -- \
##       <cartella_screenshot> [frazioni es. 0.0,0.4,0.66,0.9]
##   Godot.exe --path . res://arcanium/tools/anteprima_arco_player.tscn -- \
##       <cartella_screenshot> corsa:0.3,0.6,0.9,1.2
##
## Con `corsa:` non si tira: si tiene premuto avanti per il tempo chiesto e
## si fotografa la CORSA con l'arco agli istanti dati (secondi dalla partenza),
## con la camera che segue il corpo. Stampa anche quanto il player e' avanzato
## davvero fra il primo e l'ultimo scatto: e' il root motion della clip in
## gioco, da confrontare con `misura_locomozione.py`.
##
## ⚠️ NON `--headless`: in headless lo scheletro non si muove.
##
## Istanzia il player da solo su un pavimento, gli mette l'Arco di Spirito
## in mano dall'armadio (come farebbe il menu), chiede un colpo leggero e
## fotografa il TIRO alle frazioni chieste. Alla fine rimette l'arma di prima e
## toglie l'arco dal possesso; il salvataggio dell'utente viene messo da parte
## e rimesso, perche' l'armadio salva a ogni cambio.
##
## Serve a giudicare la presa dell'arco (`held_transform` nel .tres) e il gesto
## segnaposto: la presa si tara nell'equip playground, questo la mostra in
## movimento.

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"
const ARCO := "res://arcanium/resources/weapons/arco_di_spirito_sylvorn.tres"
const SALVATAGGIO := "user://arcanium_save.cfg"
const COPIA := "user://arcanium_save.cfg.anteprima_arco"

var _cartella : String = ""
var _frazioni : PackedFloat32Array = [0.0, 0.4, 0.66, 0.9]
var _cam : Camera3D
## `corsa:` — gli istanti (secondi) a cui fotografare la corsa; vuoto = si tira.
var _corsa : PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_cartella = args[0]
	if args.size() >= 2:
		var lista := str(args[1])
		if lista.begins_with("corsa:"):
			for s in lista.trim_prefix("corsa:").split(","):
				_corsa.append(float(s))
		else:
			_frazioni = PackedFloat32Array()
			for s in lista.split(","):
				_frazioni.append(float(s))
	_costruisci_mondo()

	var loadout := get_node_or_null("/root/EquipmentLoadout")
	var salva := get_node_or_null("/root/SaveManager")
	if loadout == null:
		push_error("anteprima_arco_player: manca EquipmentLoadout.")
		get_tree().quit(1)
		return
	var c_era := _copia(SALVATAGGIO, COPIA)
	var arco : Resource = load(ARCO)
	var prima : Resource = loadout.equipped_in("arma_primaria")

	var p : Node3D = (load(PLAYER) as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector3(0, 0.05, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam.make_current()
	for _i in 600:
		if p.current_state == p.state.FREE:
			break
		await get_tree().physics_frame
	var arcieria : Node = p.get_node("ArcieriaPlayer")

	loadout.acquire(arco)
	## L'arco e' chiuso finche' non si sa l'Arcieria (EquipmentLoadout): qui si
	## guarda il tiro, non il lucchetto, e la tecnica si segna come appresa. Il
	## salvataggio e' gia' al riparo.
	var lucchetto : Resource = loadout.tecnica_richiesta(arco) if loadout.has_method("tecnica_richiesta") else null
	if lucchetto != null:
		var flags := get_node_or_null("/root/PlayerFlags")
		if flags != null:
			flags.set_flag(str(lucchetto.get("unlock_flag")))
	if not loadout.equip("arma_primaria", arco):
		push_error("anteprima_arco_player: l'arco non si e' messo (lucchetto?)")
	await get_tree().process_frame
	await get_tree().process_frame
	print("anteprima_arco_player: in mano '%s', tipo %s" % [str(arco.name), str(p.weapon_type)])
	## Un attimo di locomozione d'arco, cosi' la prima foto e' la posa a riposo.
	await get_tree().create_timer(0.6).timeout
	var scattate := {}
	if not _corsa.is_empty():
		await _corri(p)
		_fine(loadout, arco, prima, salva, c_era)
		return
	if 0.0 in _frazioni:
		await _scatta(0.0, 0.0)
		scattate[0.0] = true

	p.queue_attack(false)
	for _i in 600:
		await get_tree().physics_frame
		if not arcieria.in_tiro():
			if scattate.size() >= _frazioni.size():
				break
			continue
		var t : float = float(arcieria.get("_t"))
		var d : float = float(arcieria.get("_durata"))
		for fr in _frazioni:
			if not scattate.has(fr) and t >= fr * d - 0.001:
				scattate[fr] = true
				await _scatta(fr, t)
				break
		if scattate.size() >= _frazioni.size():
			break

	_fine(loadout, arco, prima, salva, c_era)


## Rimettere tutto com'era.
func _fine(loadout : Node, arco : Resource, prima : Resource, salva : Node, c_era : bool) -> void:
	if prima != null:
		loadout.equip("arma_primaria", prima)
	loadout.release(arco)
	if c_era:
		if salva != null:
			salva.set("_resume_scene", "")
		_copia(COPIA, SALVATAGGIO)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COPIA))
	elif FileAccess.file_exists(SALVATAGGIO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SALVATAGGIO))
	get_tree().quit(0)


## La corsa: avanti premuto, camera che segue, uno scatto a ogni istante
## chiesto. Il player guarda +Z e la camera resta al suo tre quarti.
func _corri(p : Node3D) -> void:
	var offset : Vector3 = _cam.position - Vector3(0.0, 0.0, 0.0)
	var mira_rel := Vector3(0.0, 1.0, 0.1)
	Input.action_press("move_up")
	var t := 0.0
	var scattate := {}
	var posizioni := {}
	while scattate.size() < _corsa.size() and t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_cam.look_at_from_position(p.global_position + offset, p.global_position + mira_rel, Vector3.UP)
		for istante in _corsa:
			if not scattate.has(istante) and t >= istante - 0.001:
				scattate[istante] = true
				posizioni[istante] = p.global_position
				await _scatta_corsa(istante, t, p)
				break
	Input.action_release("move_up")
	var istanti := _corsa.duplicate()
	istanti.sort()
	if istanti.size() >= 2:
		var a : float = istanti[0]
		var b : float = istanti[istanti.size() - 1]
		var d : float = (posizioni[b] - posizioni[a]).length()
		print("corsa: da %.2f a %.2f s il player ha percorso %.2f m = %.2f m/s" % [a, b, d, d / maxf(b - a, 0.001)])


func _scatta_corsa(istante : float, t : float, p : Node3D) -> void:
	if _cartella == "":
		return
	Engine.time_scale = 0.0
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var nome := "%s/arco_player_corsa_%03d.png" % [_cartella, int(round(istante * 100.0))]
	var err := img.save_png(nome)
	var albero : AnimationTree = find_child("AnimStateTree", true, false)
	var ms = albero.get("parameters/MovementStates/playback") if albero else null
	print("  %.2f s  (t %.3f)  pos %s  locomozione=%s blend=%s  %s" % [istante, t, str(p.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
		str(ms.get_current_node()) if ms else "-",
		str(albero.get("parameters/MovementStates/BOW_tree/MoveStrafe/blend_position")) if albero else "-",
		nome if err == OK else "SCREENSHOT FALLITO"])
	await get_tree().process_frame
	Engine.time_scale = 1.0


## ⚠️ Salvare un PNG a 1080p blocca il processo per un decimo abbondante, e
## il tiro intanto correrebbe: le foto dopo la prima uscivano tutte in
## ritardo, con l'etichetta di una frazione e la posa di quella dopo (una
## freccia "gia' in volo" all'84% con il rilascio all'86%, 2026-09-14). Il
## tempo si ferma (`Engine.time_scale = 0`) per tutto il salvataggio E per il
## frame dopo, che e' quello in cui il motore conta il tempo perso.
func _scatta(fraz : float, t : float) -> void:
	if _cartella == "":
		return
	Engine.time_scale = 0.0
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var nome := "%s/arco_player_%03d.png" % [_cartella, int(round(fraz * 100.0))]
	var err := img.save_png(nome)
	print("  %3.0f%%  t %.3f s  %s" % [fraz * 100.0, t, nome if err == OK else "SCREENSHOT FALLITO"])
	await get_tree().process_frame
	Engine.time_scale = 1.0
	## Le rotazioni di due ossa: dicono se la clip sta davvero girando o se il
	## corpo e' fermo al riposo (una T-pose che sembra un fotogramma).
	var sk : Skeleton3D = find_child("GeneralSkeleton", true, false)
	if sk != null:
		var albero : AnimationTree = find_child("AnimStateTree", true, false)
		print("        LeftUpperArm %s  RightUpperArm %s  Attack=%s ATTACK=%s" % [
			str(sk.get_bone_pose_rotation(sk.find_bone("LeftUpperArm")).get_euler() * 57.3).substr(0, 40),
			str(sk.get_bone_pose_rotation(sk.find_bone("RightUpperArm")).get_euler() * 57.3).substr(0, 40),
			str(albero.get("parameters/Attack/active")) if albero else "-",
			str(albero.get("parameters/ATTACK_tree/playback").get_current_node()) if albero else "-"])
		## E l'arco: dove puntano i flettenti (Y del modello in mano) e in che
		## ramo di locomozione sta l'albero. Confrontabile con misura_presa_arco.
		var modello : Node3D = find_child("ModelloEquipaggiato", true, false)
		if modello != null and albero != null:
			var ms = albero.get("parameters/MovementStates/playback")
			print("        flettenti %s  locomozione=%s  blend=%s" % [
				str(modello.global_transform.basis.y.snapped(Vector3(0.01, 0.01, 0.01))),
				str(ms.get_current_node()) if ms else "-",
				str(albero.get("parameters/MovementStates/BOW_tree/MoveStrafe/blend_position"))])


func _copia(da : String, a : String) -> bool:
	if not FileAccess.file_exists(da):
		return false
	var sorgente := FileAccess.open(da, FileAccess.READ)
	var dest := FileAccess.open(a, FileAccess.WRITE)
	if sorgente == null or dest == null:
		return false
	dest.store_buffer(sorgente.get_buffer(sorgente.get_length()))
	return true


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
	## Tre quarti frontale dal lato dell'arco (la destra del player, che guarda +Z).
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.position = Vector3(-1.9, 1.35, 1.9)
	_cam.look_at_from_position(_cam.position, Vector3(0.0, 1.0, 0.1), Vector3.UP)
	add_child(_cam)
