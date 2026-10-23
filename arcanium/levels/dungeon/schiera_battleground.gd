extends Control

## Lo SCHIERAMENTO del battleground (design-mappa-run del 2026-10-22: «schiera
## ridotta»). Prima dello scontro, a gioco fermo, ognuna delle tre truppe base
## della casata va su uno dei punti proposti (la sala d'ingresso e le stanze
## piu' vicine); «Deploy» le mette in campo e lo scontro parte. Due truppe
## sullo stesso punto vanno bene: si scelgono la massa o la copertura.

const Ornati := preload("res://arcanium/ui/theme/ornati.gd")
const MenuStyle := preload("res://arcanium/ui/game_menu/er_style.gd")

signal schierato(scelte : Array)

## Le truppe: [{"nome": String, "scena": PackedScene}].
var truppe : Array = []
## I punti: [{"nome": String, "pos": Vector3}].
var punti : Array = []
## Il punto scelto per ogni truppa (indice in `punti`).
var scelte : Array = []
var _etichette : Array = []


func _ready() -> void:
	## Sotto un CanvasLayer servono anche gli offset, o resta nell'angolo.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	scelte.clear()
	for k in truppe.size():
		scelte.append(mini(k, punti.size() - 1))
	var velo := ColorRect.new()
	velo.color = Color(0, 0, 0, 0.5)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(velo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centro)
	var box := Ornati.pannello(Vector2(760, 0))
	centro.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	Ornati.contenuto(box).add_child(col)
	col.add_child(Ornati.titolo(MenuStyle.spaziato(tr("Deploy your troops")), 24))
	var t := Label.new()
	t.text = tr("Your house troops fight beside you. Choose where each one waits; the enemy force is larger than usual.")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(600, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	for k in truppe.size():
		var riga := HBoxContainer.new()
		riga.alignment = BoxContainer.ALIGNMENT_CENTER
		riga.add_theme_constant_override("separation", 14)
		var nome := Label.new()
		nome.text = tr(String(truppe[k]["nome"]))
		nome.custom_minimum_size = Vector2(190, 0)
		nome.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
		riga.add_child(nome)
		var meno := Ornati.bottone("‹", Vector2(70, 44))
		meno.pressed.connect(_cambia.bind(k, -1))
		riga.add_child(meno)
		var dove := Label.new()
		dove.custom_minimum_size = Vector2(220, 0)
		dove.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		riga.add_child(dove)
		_etichette.append(dove)
		var piu := Ornati.bottone("›", Vector2(70, 44))
		piu.pressed.connect(_cambia.bind(k, 1))
		riga.add_child(piu)
		col.add_child(riga)
	var vai := Ornati.bottone("Deploy", Vector2(220, 50))
	vai.name = "Schiera"
	vai.pressed.connect(conferma)
	var c := CenterContainer.new()
	c.add_child(vai)
	col.add_child(c)
	_aggiorna()
	vai.grab_focus()


func _cambia(k : int, d : int) -> void:
	scelte[k] = (int(scelte[k]) + d + punti.size()) % punti.size()
	_aggiorna()


func _aggiorna() -> void:
	for k in _etichette.size():
		(_etichette[k] as Label).text = tr(String(punti[int(scelte[k])]["nome"]))


func conferma() -> void:
	schierato.emit(scelte.duplicate())
	queue_free()
