extends Node

## Gestione display globale. Autoload "DisplayManager": applica modalità finestra
## e risoluzione, e intercetta F11 per alternare rapidamente schermo intero e
## finestra durante lo sviluppo.
##
## Qui sta il COME si applica; il COSA (valore scelto, salvato su disco) sta in
## `GameSettings`. Separati perché la modalità va applicata anche prima che le
## preferenze siano state lette, e perché il pannello Impostazioni ha bisogno di
## provare una risoluzione SENZA salvarla, finché il giocatore non conferma.
##
## Registrato come autoload in project.godot così vale in ogni scena.

## L'enum vive qui e non in `GameSettings` perché è roba di display: le
## preferenze lo salvano e basta. `GameSettings` lo raggiunge con un preload
## dello script, che funziona anche prima che gli autoload esistano.
enum ModoFinestra {
	FINESTRA,        ## finestra normale, ridimensionabile, con bordi
	SCHERMO_INTERO,  ## fullscreen: la risoluzione la decide lo schermo
	SENZA_BORDI,     ## finestra grande quanto lo schermo, senza cornice
}

const NOME_MODO := {
	ModoFinestra.FINESTRA: "Finestra",
	ModoFinestra.SCHERMO_INTERO: "Schermo intero",
	ModoFinestra.SENZA_BORDI: "Senza bordi",
}

## Risoluzioni offerte in finestra. Vengono filtrate su quelle che ci stanno
## davvero nello schermo: proporre 4K su un pannello 1080p produce una finestra
## più grande del monitor, con i pulsanti fuori portata — esattamente il guaio
## da cui nasce questa schermata.
const RISOLUZIONI : Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

## Sotto questa larghezza il menu principale non ci sta: la colonna centrale è
## alta 399 px e va tenuta centrata con un margine ragionevole.
const RISOLUZIONE_MINIMA := Vector2i(1280, 720)


func _unhandled_key_input(event : InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


## F11 passa dalle preferenze quando ci sono, così il pannello Impostazioni non
## si ritrova a mostrare "Finestra" mentre il gioco è a schermo intero.
func toggle_fullscreen() -> void:
	var nuovo := ModoFinestra.FINESTRA if _e_a_schermo_intero() else ModoFinestra.SCHERMO_INTERO
	var prefs := get_node_or_null("/root/GameSettings")
	if prefs != null:
		prefs.modo_finestra = nuovo
	else:
		applica(nuovo, RISOLUZIONE_MINIMA)


func _e_a_schermo_intero() -> bool:
	var modo := DisplayServer.window_get_mode()
	return modo == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or modo == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Applica modalità e risoluzione. La risoluzione conta solo in `FINESTRA`:
## negli altri due modi la detta lo schermo, ed è per questo che il pannello
## Impostazioni disabilita la tendina quando non sei in finestra.
func applica(modo : int, risoluzione : Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return

	var schermo := DisplayServer.window_get_current_screen()
	match modo:
		ModoFinestra.SCHERMO_INTERO:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		ModoFinestra.SENZA_BORDI:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(schermo))
			DisplayServer.window_set_size(DisplayServer.screen_get_size(schermo))
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(risoluzione)
			_centra(risoluzione, schermo)


## Rimette la finestra al centro dello schermo: dopo un ridimensionamento resta
## ancorata all'angolo in alto a sinistra e può finire mezza fuori.
func _centra(risoluzione : Vector2i, schermo : int) -> void:
	var area := DisplayServer.screen_get_usable_rect(schermo)
	DisplayServer.window_set_position(area.position + (area.size - risoluzione) / 2)


## Le risoluzioni proponibili sullo schermo corrente. Sempre almeno una: se il
## monitor fosse più piccolo di 1280x720 restituiamo comunque il minimo, perché
## una tendina vuota è peggio di una scelta imperfetta.
func risoluzioni_disponibili() -> Array[Vector2i]:
	if DisplayServer.get_name() == "headless":
		return RISOLUZIONI.duplicate()

	var schermo := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var buone : Array[Vector2i] = []
	for r : Vector2i in RISOLUZIONI:
		if r.x <= schermo.x and r.y <= schermo.y:
			buone.append(r)
	if buone.is_empty():
		buone.append(RISOLUZIONE_MINIMA)
	return buone
