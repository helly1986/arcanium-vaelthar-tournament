extends SceneTree

## Le BARRE VIVE (barra_viva.gd) fotografate sopra il dungeon vero, prima di
## metterle nell'HUD: si guardano e si approvano.
##   1. in alto a sinistra, a grandezza vera: vita 82%, Arcanium 40%, vigore
##      pieno, col medaglione e un sigillo provvisorio;
##   2. al centro, ingrandite 2,4 volte: vita al 24% appena dopo un colpo (la
##      scia chiara e il battito), Arcanium 65%, vigore 30%.
## Tre scatti a mezzo secondo l'uno dall'altro, per vedere che il liquido si
## muove; piu' un ritaglio dell'ingrandimento.
##
## Uso (renderer vero, niente --headless; APPDATA isolato):
##   godot --path . --script res://arcanium/tools/anteprima_barre.gd -- <cartella>

const BarraViva := preload("res://arcanium/ui/hud/barra_viva.gd")

var _dove := ""
var _grandi : Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dove = args[0] if not args.is_empty() else OS.get_user_data_dir()
	await process_frame
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 20:
		await process_frame
	## L'HUD di oggi si nasconde: si guardano le barre nuove da sole.
	for h in root.find_children("*", "", true, false):
		if h.get_script() != null and String(h.get_script().resource_path).ends_with("arcanium_hud.gd"):
			(h as CanvasItem).visible = false

	var strato := CanvasLayer.new()
	strato.layer = 80
	root.add_child(strato)
	strato.add_child(_gruppo(Vector2(24, 22), 1.0, [0.82, 0.40, 1.0], ["82", "40", "100"]))
	var grande := _gruppo(Vector2(380, 300), 2.4, [0.60, 0.65, 0.30], ["60", "65", "30"])
	strato.add_child(grande)
	for k in 30:
		await process_frame
	## Il colpo: la vita scende di colpo, la scia resta indietro.
	_grandi[0].set_value(0.24, "24")
	await _foto("barre_1", 0.15)
	await _foto("barre_2", 0.5)
	await _foto("barre_3", 0.5)
	var img := Image.load_from_file(_dove.path_join("barre_1.png"))
	var k := float(img.get_width()) / root.get_visible_rect().size.x
	img.get_region(Rect2i(Vector2i(360 * k, 280 * k), Vector2i(1080 * k, 240 * k))).save_png(_dove.path_join("barre_zoom.png"))
	img.get_region(Rect2i(Vector2i(0, 0), Vector2i(460 * k, 120 * k))).save_png(_dove.path_join("barre_vere.png"))
	quit()


## Medaglione + tre barre, a una scala.
func _gruppo(dove : Vector2, scala : float, valori : Array, testi : Array) -> Control:
	var g := Control.new()
	g.position = dove
	g.scale = Vector2(scala, scala)
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 10)
	g.add_child(riga)
	riga.add_child(_medaglione())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	riga.add_child(col)
	var tipi := [BarraViva.Tipo.SANGUE, BarraViva.Tipo.ARCANIUM, BarraViva.Tipo.VIGORE]
	for i in 3:
		var b : Control = BarraViva.new()
		b.tipo = tipi[i]
		col.add_child(b)
		b.set_value(valori[i], testi[i])
		if scala > 1.0:
			_grandi.append(b)
	return g


## Il medaglione (assets/ui/cornici/medaglione.png, Flux seme 23) col sigillo
## provvisorio della casata dentro: i sigilli veri arrivano coi campioni.
func _medaglione() -> Control:
	var m := TextureRect.new()
	m.texture = load("res://assets/ui/cornici/medaglione.png")
	m.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	m.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	m.custom_minimum_size = Vector2(78, 78)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	## Il centro della cornice e' vuoto: un disco scuro dentro l'anello d'oro.
	var disco := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.03, 0.04, 0.95)
	sb.set_corner_radius_all(40)
	disco.add_theme_stylebox_override("panel", sb)
	disco.set_anchors_preset(Control.PRESET_FULL_RECT)
	disco.offset_left = 13
	disco.offset_top = 13
	disco.offset_right = -13
	disco.offset_bottom = -13
	disco.show_behind_parent = true
	m.add_child(disco)
	var l := Label.new()
	l.text = "◈"
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color("#8fbfe0"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(l)
	return m


func _foto(nome : String, attesa : float) -> void:
	await create_timer(attesa, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dove.path_join(nome + ".png"))
	print("ANTEPRIMA: ", nome)
