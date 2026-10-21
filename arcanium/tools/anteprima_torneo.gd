extends SceneTree

## Le schermate del TORNEO fotografate sul dungeon vero, per guardarle:
##   1_sconfitta.png  la prima sconfitta, con l'Arcanium in palio;
##   2_perk.png       le carte del perk (la riga dell'Arcanium resta);
##   3_rivincita.png  la rivincita, con «in palio» nell'indicatore;
##   4_vittoria.png   la rivincita vinta, «recuperato»;
##   5_varco.png      una sconfitta con la Pietra del Varco in tasca;
##   6_eliminato.png  la terza sconfitta.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_torneo.gd -- <cartella>

var du : Node
var _dove := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	var banca : Node = root.get_node("CrystalBank")
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	du = scena.get_node("Dungeon")
	du.seme = 0
	du.obiettivo = 0
	root.add_child(scena)
	for k in 30:
		await process_frame

	banca.add(340)
	du.caduto.emit()
	var s : Node = await _schermo()
	await _foto("1_sconfitta")
	s._scegli("riprova")
	await _foto("2_perk")
	s._pulsanti[0].pressed.emit()
	for k in 30:
		await process_frame
	await _foto("3_rivincita")

	banca.add(45)
	du.ripulito.emit()
	s = await _schermo()
	await _foto("4_vittoria")
	s._scegli("prossimo")
	for k in 10:
		await process_frame

	du.forziere_aperto.emit(true)
	du.caduto.emit()
	s = await _schermo()
	await _foto("5_varco")
	s._scegli("riprova")
	await process_frame
	s._pulsanti[0].pressed.emit()
	for k in 10:
		await process_frame

	banca.add(60)
	du.caduto.emit()
	s = await _schermo()
	await _foto("6_eliminato")
	quit()


func _schermo() -> Node:
	for k in 1200:
		var s : Node = du.find_child("FineScontro", false, false)
		if s != null:
			return s
		await process_frame
	return null


## Aspetta la dissolvenza della schermata (0,8 s) e fotografa.
func _foto(nome : String) -> void:
	await create_timer(1.2, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
