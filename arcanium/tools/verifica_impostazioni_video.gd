extends SceneTree

## Prova le due righe nuove della scheda Video: modalita' finestra e
## risoluzione, con il ripristino automatico se non arriva conferma.
##
## La parte che conta e' il RIPRISTINO: un pannello che applica e si dimentica
## di tornare indietro lascia il giocatore con una modalita' in cui magari non
## riesce nemmeno a leggere il pulsante per rimediare.
##
## Headless DisplayServer non tocca nessuna finestra vera (applica() esce
## subito), quindi qui si verifica il cablaggio: valori salvati, ripristinati,
## e tendine riallineate.
##
## Uso: godot --headless --script arcanium/tools/verifica_impostazioni_video.gd

const PannelloScene := "res://arcanium/ui/settings_menu/settings_menu.tscn"


func _init() -> void:
	await process_frame
	var esito := 0

	var prefs := root.get_node_or_null("/root/GameSettings")
	var display := root.get_node_or_null("/root/DisplayManager")
	if prefs == null or display == null:
		push_error("GameSettings o DisplayManager non registrati come autoload")
		quit(1)
		return

	print("risoluzioni disponibili: %s" % [display.risoluzioni_disponibili()])

	var pannello: Control = load(PannelloScene).instantiate()
	root.add_child(pannello)
	await process_frame

	## la scheda Video non e' quella d'apertura: va scelta, come farebbe il dito
	pannello._select_tab("Video")
	await process_frame

	var modo_scelta: OptionButton = pannello._scelta_modo
	var ris_scelta: OptionButton = pannello._scelta_risoluzione
	if modo_scelta == null or ris_scelta == null:
		push_error("le tendine video non sono state costruite")
		quit(1)
		return

	print("voci modalita': %d - voci risoluzione: %d" % [modo_scelta.item_count, ris_scelta.item_count])
	esito = _controlla("Risoluzione' non deve piu' essere un placeholder",
			not "Risoluzione" in pannello.PLACEHOLDER_ROWS["Video"], esito)

	var modo_prima: int = prefs.modo_finestra
	var ris_prima: Vector2i = prefs.risoluzione

	## cambio -> deve applicarsi SUBITO, senza aspettare la conferma
	var altro: int = (modo_prima + 1) % display.ModoFinestra.size()
	pannello._cambia_video(altro, ris_prima)
	await process_frame
	esito = _controlla("il cambio si applica subito",
			prefs.modo_finestra == altro, esito)
	esito = _controlla("la conferma e' in corso", pannello._conferma_in_corso, esito)

	## scaduto il tempo (qui simulato annullando) si torna com'era
	pannello._rileggi_scelte()
	var dlg := _trova_dialogo(pannello)
	if dlg == null:
		push_error("nessun dialogo di conferma comparso")
		quit(1)
		return
	dlg.canceled.emit()
	await process_frame

	esito = _controlla("il ripristino rimette la modalita' di prima",
			prefs.modo_finestra == modo_prima, esito)
	esito = _controlla("il ripristino rimette la risoluzione di prima",
			prefs.risoluzione == ris_prima, esito)
	esito = _controlla("la tendina torna allineata al valore vero",
			modo_scelta.get_selected_id() == modo_prima, esito)
	esito = _controlla("finita la conferma se ne puo' fare un'altra",
			not pannello._conferma_in_corso, esito)

	quit(esito)


func _trova_dialogo(nodo: Node) -> ConfirmationDialog:
	for f: Node in nodo.get_children():
		if f is ConfirmationDialog:
			return f
	return null


func _controlla(cosa: String, passato: bool, esito_finora: int) -> int:
	print("%s  %s" % ["[ok]  " if passato else "[NO]  ", cosa])
	return esito_finora if passato else 1
