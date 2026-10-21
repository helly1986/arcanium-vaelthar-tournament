extends CanvasLayer
## Announcer: replica in Godot dell'Announcer.js di Arcanium-Lite.
## Autoload globale (registrato come "Announcer") che mostra annunci soulslike
## a schermo intero ("LEGEND DEFEATED", "BACK TO ARCANIUM FLOW") e il popup
## "oggetto ottenuto" stile Elden Ring. Non deve mai intercettare l'input:
## tutta la gerarchia usa MOUSE_FILTER_IGNORE.

# Colori tema, coerenti con l'estetica soulslike (oro caldo / rosso spento).
const COLOR_GOLD := Color("#e8c86a")
const COLOR_RED := Color("#c85a4a")
const VEIL_ALPHA := 0.55

# Nodi costruiti a runtime e riusati tra le chiamate, per evitare di
# ricreare l'albero UI ogni volta (e per poter interrompere i tween in corso).
var _root : Control
var _veil : ColorRect
var _banner_label : Label

var _item_popup : PanelContainer
var _item_icon_label : Label
var _item_name_label : Label

var _veil_tween : Tween
var _banner_tween : Tween
var _item_tween : Tween


func _ready() -> void:
	# Layer 30: sopra HUD (layer di default) e menu (layer 10).
	layer = 30

	_root = Control.new()
	_root.name = "AnnouncerRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_veil()
	_build_banner()
	# Il popup item viene creato al volo alla prima item_acquired(): non serve
	# occupare un nodo fisso quando non c'è nulla da mostrare.

	## Gli autoload si preparano in ordine non garantito: agganciamo dopo che
	## sono tutti in piedi.
	call_deferred("_wire_sources")


## Le notifiche si agganciano alla SORGENTE (inventario, quest), non ai singoli
## chiamanti. Prima l'unico popup del gioco era una chiamata a mano nel director
## del prologo per la spada: qualunque altro oggetto — l'armatura dell'Alpha, la
## lancia del Consumato — entrava nell'inventario in silenzio. Passando dal
## segnale, ogni oggetto che arriva si annuncia da sé, incluso quello che
## aggiungerai domani senza ricordarti di notificarlo.
func _wire_sources() -> void:
	var inv := get_node_or_null("/root/ArcaniumInventory")
	if inv and inv.has_signal("item_added") \
			and not inv.item_added.is_connected(_on_item_added):
		inv.item_added.connect(_on_item_added)

	var quests := get_node_or_null("/root/QuestManager")
	if quests == null:
		return
	if quests.has_signal("quest_started") \
			and not quests.quest_started.is_connected(_on_quest_started):
		quests.quest_started.connect(_on_quest_started)
	if quests.has_signal("quest_completed") \
			and not quests.quest_completed.is_connected(_on_quest_completed):
		quests.quest_completed.connect(_on_quest_completed)
	if quests.has_signal("quest_updated") \
			and not quests.quest_updated.is_connected(_on_quest_updated):
		quests.quest_updated.connect(_on_quest_updated)


func _on_item_added(def : Resource, _count : int) -> void:
	if def == null:
		return
	var nome := str(def.get("item_name"))
	if nome.strip_edges() == "":
		nome = str(def.get("id"))
	notify("Obtained", nome, str(def.get("icon")))

func _on_quest_started(id : String) -> void:
	notify("New quest", _titolo(id), "✦")

func _on_quest_completed(id : String) -> void:
	notify("Quest complete", _titolo(id), "✦")

## La tappa, non il titolo: "Missione aggiornata — Il Lupo Alpha è caduto" dice
## al giocatore cosa è appena cambiato. Il titolo lo sa già.
func _on_quest_updated(_id : String, entry : String) -> void:
	notify("Quest updated", entry, "✦")

## Le quest viaggiano come id: a schermo va il titolo, che il QuestManager sa.
func _titolo(id : String) -> String:
	var quests := get_node_or_null("/root/QuestManager")
	if quests and quests.has_method("title_of"):
		return str(quests.title_of(id))
	return id


# --- costruzione UI statica -------------------------------------------------

func _build_veil() -> void:
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = Color(0, 0, 0, VEIL_ALPHA)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.modulate.a = 0.0
	_root.add_child(_veil)


func _build_banner() -> void:
	_banner_label = Label.new()
	_banner_label.name = "BannerLabel"
	_banner_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_banner_label.add_theme_font_size_override("font_size", 64)
	_banner_label.add_theme_constant_override("shadow_offset_x", 2)
	_banner_label.add_theme_constant_override("shadow_offset_y", 2)
	_banner_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_banner_label.modulate.a = 0.0
	_root.add_child(_banner_label)


# --- API pubblica ------------------------------------------------------------

func legend_defeated() -> void:
	# Lettere spaziate: Godot non ha letter-spacing su Label di default,
	# lo simuliamo inserendo spazi extra tra i caratteri del testo.
	_banner_label.text = _spaced("LEGEND DEFEATED")
	_banner_label.add_theme_color_override("font_color", COLOR_GOLD)

	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_label, "modulate:a", 1.0, 0.8)


## Banner del MINI-BOSS: l'Alpha del Branco Guasto è una classe inferiore a una
## Leggenda → "FIEND DEFEATED" in viola (tema Guasto), non l'oro delle Leggende.
## Auto-dissolvenza dopo qualche secondo (nessun clear() esterno richiesto).
func fiend_defeated() -> void:
	_banner_label.text = _spaced("FIEND DEFEATED")
	_banner_label.add_theme_color_override("font_color", Color(0.72, 0.45, 1.0))

	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_label, "modulate:a", 1.0, 0.8)
	_banner_tween.tween_interval(2.6)
	_banner_tween.tween_property(_banner_label, "modulate:a", 0.0, 1.0)


func back_to_arcanium() -> void:
	_banner_label.text = _spaced("BACK TO ARCANIUM FLOW")
	_banner_label.add_theme_color_override("font_color", COLOR_RED)

	if _veil_tween:
		_veil_tween.kill()
	_veil_tween = create_tween()
	_veil_tween.tween_property(_veil, "modulate:a", 1.0, 0.6)

	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_label, "modulate:a", 1.0, 0.8)


func item_acquired(item_name : String, icon : String = "") -> void:
	notify("Obtained", item_name, icon)

## Stesso popup dell'oggetto ottenuto, con la didascalia scelta da chi chiama:
## "Obtained", "Quest updated", "Nemico abbattuto"... Un solo canale per
## tutte le notifiche brevi, così hanno tutte lo stesso posto e lo stesso ritmo
## e non ne nascono tre stili diversi.
func notify(caption_text : String, text : String, icon : String = "") -> void:
	# Popup semplice "usa e getta": ogni chiamata ricrea il pannello, così
	# più chiamate consecutive sostituiscono la precedente senza gestire code.
	if _item_popup and is_instance_valid(_item_popup):
		if _item_tween:
			_item_tween.kill()
		_item_popup.queue_free()

	_item_popup = _create_item_popup(text, icon, caption_text)
	_root.add_child(_item_popup)

	_item_tween = create_tween()
	_item_tween.tween_property(_item_popup, "modulate:a", 1.0, 0.4)
	_item_tween.tween_interval(4.0)
	_item_tween.tween_property(_item_popup, "modulate:a", 0.0, 0.6)
	_item_tween.tween_callback(_item_popup.queue_free)


func clear() -> void:
	# Nasconde velo e banner (legend_defeated / back_to_arcanium).
	# Il popup item NON viene toccato: si gestisce da solo col proprio tween.
	if _veil_tween:
		_veil_tween.kill()
	_veil_tween = create_tween()
	_veil_tween.tween_property(_veil, "modulate:a", 0.0, 0.4)

	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_label, "modulate:a", 0.0, 0.4)


# --- helper --------------------------------------------------------------

func _spaced(text : String) -> String:
	# Inserisce spazi tra i caratteri per simulare letter-spacing largo,
	# tipico dei banner soulslike (es. "LEGEND DEFEATED" -> "L E G E N D...").
	var out := ""
	for i in text.length():
		out += text[i]
		if i < text.length() - 1:
			out += " "
	return out


func _create_item_popup(item_name : String, icon : String, caption_text : String = "Obtained") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ItemPopup"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0

	## ⚠️ LA PILA IN BASSO ALLO SCHERMO, dal fondo verso l'alto:
	##   0 –  100 px   barra azioni (spell_bar.gd, attaccata al fondo)
	## 138 –  178 px   fascia della BossBar (arena_senza_fuoco.tscn)
	## 178 px in su    QUESTA notifica
	##
	## Stava a 80 px, cioè addosso alla barra azioni: la notifica ci passava
	## sopra e non si leggeva bene né lei né gli oggetti. Sale al filo superiore
	## della fascia BossBar, così le tre cose sono impilate e non si toccano mai
	## — nemmeno quando c'è un boss in campo.
	const ALTEZZA_FASCIA_BOSS := 178.0
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position.y = -ALTEZZA_FASCIA_BOSS

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.75)
	style.border_color = Color(0.85, 0.8, 0.65, 0.6)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 18
	style.content_margin_right = 22
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	_item_icon_label = Label.new()
	_item_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_icon_label.text = icon
	_item_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_item_icon_label.add_theme_font_size_override("font_size", 28)
	_item_icon_label.add_theme_color_override("font_color", COLOR_GOLD)
	row.add_child(_item_icon_label)

	var text_col := VBoxContainer.new()
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_theme_constant_override("separation", 0)
	row.add_child(text_col)

	var caption := Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.text = caption_text
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	text_col.add_child(caption)

	_item_name_label = Label.new()
	_item_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_name_label.text = item_name
	_item_name_label.add_theme_font_size_override("font_size", 18)
	_item_name_label.add_theme_color_override("font_color", Color.WHITE)
	text_col.add_child(_item_name_label)

	return panel
