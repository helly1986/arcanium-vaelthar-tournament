extends Control

## Menu iniziale di Arcanium — key-art, emblema, titolo, tema musicale in loop
## e navigazione (Continua / Impostazioni). Porting di src/ui/MainMenu.js
## (Arcanium-Lite): a differenza del web, qui l'audio non è bloccato da un
## gesto utente, quindi il tema parte subito col fade-in.

@export var arena_scene_path : String = "res://arcanium/levels/arena_senza_fuoco.tscn"
@export var music_target_volume_db : float = -8.0
@export var music_fade_in_seconds : float = 2.5
@export var music_fade_out_seconds : float = 0.7

var _music : AudioStreamPlayer
var _leaving := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_background()
	_build_content()
	_build_music()

func _build_background() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/menu_bg.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vignette := ColorRect.new()
	vignette.color = Color(0.02, 0.01, 0.03, 0.55)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

func _build_content() -> void:
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 18)
	add_child(center)

	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/ui/menu_emblem.png")
	emblem.custom_minimum_size = Vector2(120, 120)
	# Senza IGNORE_SIZE la dimensione minima la detta la texture (1024x1024) e non
	# il custom_minimum_size: la colonna diventa alta 1303 px e sotto i 1440p i
	# pulsanti finiscono fuori schermo.
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(emblem)

	var title := Label.new()
	title.text = "ARCANIUM"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.93, 0.9, 0.98))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Il ciclo continua"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	center.add_child(spacer)

	# "Continua" compare solo se esiste un salvataggio (dopo il Prologo): riparte
	# dal Crocevia, non dallo scontro col Senza Nome.
	var save := get_node_or_null("/root/SaveManager")
	if save and save.has_save():
		var continue_btn := _make_button("Continua")
		continue_btn.pressed.connect(_on_continue_pressed)
		center.add_child(continue_btn)

	var new_game_btn := _make_button("Nuova Partita")
	new_game_btn.pressed.connect(_on_new_game_pressed)
	center.add_child(new_game_btn)

	var settings_btn := _make_button("Impostazioni")
	settings_btn.pressed.connect(_on_settings_pressed)
	center.add_child(settings_btn)

func _make_button(text : String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(240, 44)
	btn.add_theme_font_size_override("font_size", 18)
	return btn

func _build_music() -> void:
	_music = AudioStreamPlayer.new()
	var stream : AudioStream = load("res://assets/audio/arcanium_main_theme.mp3")
	if stream is AudioStreamMP3:
		stream.loop = true
	_music.stream = stream
	_music.bus = "Music"
	_music.volume_db = -80.0
	add_child(_music)
	_music.play()
	_fade_music(-80.0, music_target_volume_db, music_fade_in_seconds)

func _fade_music(from_db : float, to_db : float, seconds : float) -> void:
	_music.volume_db = from_db
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", to_db, seconds)

const SettingsMenuScene := preload("res://arcanium/ui/settings_menu/settings_menu.tscn")

func _on_settings_pressed() -> void:
	var panel := SettingsMenuScene.instantiate()
	panel.closed.connect(panel.queue_free)
	add_child(panel)

const HouseCatalog := preload("res://arcanium/systems/house_catalog.gd")
const CHAR_CREATION_PATH := "res://arcanium/ui/char_creation/char_creation.tscn"

## "Continua": riprende dal salvataggio (Crocevia), non dal boss.
func _on_continue_pressed() -> void:
	var save := get_node_or_null("/root/SaveManager")
	var path := arena_scene_path
	if save and save.has_save():
		path = save.get_resume_scene()
	_fade_out_and_go(path)

## "Nuova Partita": se esiste un salvataggio, avvisa della sovrascrittura, poi
## apre la creazione personaggio. Altrimenti va diretto alla creazione.
func _on_new_game_pressed() -> void:
	var save := get_node_or_null("/root/SaveManager")
	if save and save.has_save():
		_show_overwrite_confirm()
	else:
		_open_char_creation()

func _show_overwrite_confirm() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Nuova Partita"
	dlg.dialog_text = "Esiste già un salvataggio.\nIniziare una nuova partita lo sovrascriverà: i progressi andranno persi.\n\nContinuare?"
	dlg.ok_button_text = "Sovrascrivi"
	dlg.cancel_button_text = "Annulla"
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		dlg.queue_free()
		_open_char_creation()
	)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()

## Apre la schermata di creazione personaggio (overlay, così la musica prosegue).
## Finché la schermata non esiste (in costruzione), fallback: nuova run Dawnkeep
## diretta all'arena, così il flusso resta giocabile.
func _open_char_creation() -> void:
	if not ResourceLoader.exists(CHAR_CREATION_PATH):
		var save := get_node_or_null("/root/SaveManager")
		if save:
			save.begin_new_run(HouseCatalog.DEFAULT_HOUSE, "male")
		_fade_out_and_go(arena_scene_path)
		return
	var scene : PackedScene = load(CHAR_CREATION_PATH)
	var panel := scene.instantiate()
	panel.confirmed.connect(_on_char_confirmed)
	panel.cancelled.connect(panel.queue_free)
	add_child(panel)

## La creazione personaggio ha confermato: avvia la nuova run e parte l'arena.
func _on_char_confirmed(house : String, gender : String) -> void:
	var save := get_node_or_null("/root/SaveManager")
	if save:
		save.begin_new_run(house, gender)
	_fade_out_and_go(arena_scene_path)

func _fade_out_and_go(path : String) -> void:
	if _leaving:
		return
	_leaving = true
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", -80.0, music_fade_out_seconds)
	tween.tween_callback(func() -> void: get_tree().change_scene_to_file(path))
