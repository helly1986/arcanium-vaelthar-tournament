extends SceneTree

## Misura il menu principale a varie risoluzioni e dice quali pezzi finiscono
## fuori dallo schermo.
##
## Il menu e' costruito da codice in _build_content(): niente si vede
## nell'editor, quindi un errore di ancoraggio si scopre solo giocando. Questo
## script stampa il rettangolo di ogni figlio e lo confronta col viewport.
##
## Uso: godot --headless --script arcanium/tools/verifica_menu_layout.gd

const MenuScene := "res://arcanium/ui/main_menu/main_menu.tscn"

const RISOLUZIONI : Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]


func _init() -> void:
	var esito := 0
	for r: Vector2i in RISOLUZIONI:
		if not await _prova(r):
			esito = 1
	quit(esito)


func _prova(risoluzione: Vector2i) -> bool:
	## Un SubViewport invece della finestra vera: headless la finestra non scende
	## sotto una certa dimensione (a 1280x720 resta 64x64) e la misura verrebbe
	## falsata proprio alla risoluzione piu' stretta, quella che conta di piu'.
	var vp := SubViewport.new()
	vp.size = risoluzione
	root.add_child(vp)

	var scena: PackedScene = load(MenuScene)
	var menu: Control = scena.instantiate()
	vp.add_child(menu)

	## due frame: uno per _ready, uno perche' i Container assestano il layout
	## dopo, ed e' proprio li' che si vede lo sbaglio
	await process_frame
	await process_frame

	print("\n=== %d x %d ===" % [risoluzione.x, risoluzione.y])
	var tutto_dentro := true

	for figlio: Node in menu.get_children():
		if figlio is not Control:
			continue
		var c: Control = figlio
		var r: Rect2 = c.get_global_rect()
		var nome := "%s (%s)" % [c.name, c.get_class()]
		print("  %-34s pos=(%6.1f,%7.1f) dim=(%6.1f,%7.1f)" % [nome, r.position.x, r.position.y, r.size.x, r.size.y])

		if c is VBoxContainer:
			tutto_dentro = _misura_voci(c, risoluzione) and tutto_dentro

	if tutto_dentro:
		print("  -> tutto dentro lo schermo")

	vp.queue_free()
	await process_frame
	return tutto_dentro


## Scende nella colonna centrale: e' li' che stanno titolo e pulsanti.
func _misura_voci(colonna: VBoxContainer, risoluzione: Vector2i) -> bool:
	var tutto_dentro := true
	for voce: Node in colonna.get_children():
		if voce is not Control:
			continue
		var c: Control = voce
		var r: Rect2 = c.get_global_rect()
		var etichetta := c.name
		if c is Button:
			etichetta = "Button '%s'" % (c as Button).text
		elif c is Label:
			etichetta = "Label '%s'" % (c as Label).text

		var fuori := ""
		if r.position.y < 0:
			fuori = "  <<< TAGLIATO IN ALTO"
			tutto_dentro = false
		elif r.end.y > risoluzione.y:
			fuori = "  <<< FUORI SCHERMO IN BASSO (di %.0f px)" % (r.end.y - risoluzione.y)
			tutto_dentro = false

		print("      %-28s y=%7.1f .. %7.1f%s" % [etichetta, r.position.y, r.end.y, fuori])
	return tutto_dentro
