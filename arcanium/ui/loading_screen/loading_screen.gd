extends CanvasLayer
class_name LoadingScreen

## Schermata di caricamento fullscreen riusabile. Uso tipico: instanziata al
## volo da un trigger di uscita (es. crocevia_exit_trigger.gd), aggiunta
## direttamente a `get_tree().root` (NON alla scena corrente) così sopravvive
## al `change_scene_to_packed` che lei stessa esegue, poi si autodistrugge.
##
## start(target_scene_path, illustration_path, title_text):
##  - se `illustration_path` esiste ed è caricabile → TextureRect fullscreen;
##  - altrimenti fallback ColorRect scuro + Label col titolo (nessun asset
##    richiesto per testare il flusso).

@export var min_display_time : float = 1.2
@export var fade_time : float = 0.4

const FALLBACK_BG := Color(0.06, 0.05, 0.05)

var _root : Control
var _bg_color : ColorRect
var _bg_image : TextureRect
var _title_label : Label
var _hint_label : Label


func _ready() -> void:
	layer = 60
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_bg_color = ColorRect.new()
	_bg_color.color = FALLBACK_BG
	_bg_color.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg_color)

	_bg_image = TextureRect.new()
	_bg_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_image.stretch_mode = TextureRect.STRETCH_SCALE
	_bg_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_image.visible = false
	_root.add_child(_bg_image)

	_title_label = Label.new()
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.offset_left = -400.0
	_title_label.offset_right = 400.0
	_title_label.offset_top = -40.0
	_title_label.offset_bottom = 40.0
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 42)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.offset_top = -70.0
	_hint_label.offset_bottom = -30.0
	_hint_label.offset_left = -200.0
	_hint_label.offset_right = 200.0
	_hint_label.text = "Caricamento..."
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	_root.add_child(_hint_label)

	_root.modulate.a = 0.0


## Avvia la transizione: fade-in del velo, caricamento threaded della scena
## target (con tempo minimo di permanenza per non far "lampeggiare" lo
## schermo se la scena è già in cache), cambio scena, fade-out, queue_free.
func start(target_scene_path : String, illustration_path : String = "", title_text : String = "") -> void:
	_title_label.text = title_text

	if illustration_path != "" and ResourceLoader.exists(illustration_path):
		var tex : Texture2D = load(illustration_path)
		if tex:
			_bg_image.texture = tex
			_bg_image.visible = true
			_bg_color.visible = false

	var fade_in := create_tween()
	fade_in.tween_property(_root, "modulate:a", 1.0, fade_time)
	await fade_in.finished

	var started_at := Time.get_ticks_msec()

	var err := ResourceLoader.load_threaded_request(target_scene_path)
	if err != OK:
		push_warning("LoadingScreen: impossibile avviare il caricamento di " + target_scene_path)
	else:
		while true:
			var status := ResourceLoader.load_threaded_get_status(target_scene_path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				break
			if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("LoadingScreen: caricamento fallito per " + target_scene_path)
				break
			await get_tree().process_frame

	var elapsed_ms := Time.get_ticks_msec() - started_at
	var remaining_sec : float = maxf(0.0, min_display_time - elapsed_ms / 1000.0)
	if remaining_sec > 0.0:
		await get_tree().create_timer(remaining_sec).timeout

	var packed : PackedScene = ResourceLoader.load_threaded_get(target_scene_path)
	if packed == null:
		packed = load(target_scene_path)
	if packed:
		get_tree().change_scene_to_packed(packed)
	else:
		## ⚠️ NON restare in silenzio. Prima qui non c'era nulla: se il
		## caricamento falliva, il velo faceva fade-in, aspettava, faceva
		## fade-out e il giocatore si ritrovava **esattamente dov'era** senza
		## un messaggio, un errore, niente. È successo davvero sul passaggio a
		## Kalvorn, ed è costato una sessione di caccia a un bug che il gioco
		## sapeva benissimo di avere ma non diceva.
		##
		## Un fallimento silenzioso è peggio di un errore: sembra un problema di
		## design ("il portale non funziona?") invece che un problema tecnico.
		push_error("LoadingScreen: '%s' non si è caricata — il giocatore resta dov'era."
			% target_scene_path)
		_hint_label.text = "Impossibile caricare la destinazione."
		_title_label.text = ""
		await get_tree().create_timer(2.0).timeout

	var fade_out := create_tween()
	fade_out.tween_property(_root, "modulate:a", 0.0, fade_time)
	await fade_out.finished

	queue_free()
