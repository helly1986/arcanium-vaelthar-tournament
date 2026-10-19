extends SceneTree

## Prova che la preferenza "Camera in lock-on" esista davvero: le quattro voci
## nel menu, il valore che cambia, e soprattutto che SOPRAVVIVA a un riavvio
## (e' l'unico motivo per cui sta in un file separato dal salvataggio di partita).
##
## Uso: godot --headless --script arcanium/tools/verifica_opzioni_camera.gd

const MENU := "res://arcanium/ui/settings_menu/settings_menu.tscn"


func _init() -> void:
	await process_frame
	var esito := 0
	var prefs := root.get_node_or_null("/root/GameSettings")
	if prefs == null:
		print("GameSettings NON e' un autoload: la preferenza non esiste")
		quit(1)
		return

	print("stili disponibili:")
	for i in prefs.LockCamera.size():
		print("   %d = %-24s scarto %+.0f gradi%s" % [
			i, prefs.NOME_STILE.get(i, "?"),
			prefs.ANGOLO_STILE.get(i, 0.0),
			"   (non insegue)" if i == prefs.LockCamera.LIBERA else ""])

	# il menu deve mostrarle tutte, nell'ordine dell'enum
	var pannello : Control = load(MENU).instantiate()
	root.add_child(pannello)
	await process_frame
	var scelta : OptionButton = _trova_option(pannello)
	if scelta == null:
		print("NEL MENU non c'e' nessun OptionButton: la voce non e' stata costruita")
		esito = 1
	else:
		print("nel menu: %d voci, selezionata %d" % [scelta.item_count, scelta.selected])
		if scelta.item_count != prefs.LockCamera.size():
			print("   NUMERO DI VOCI DIVERSO dall'enum")
			esito = 1
	pannello.queue_free()
	await process_frame

	# cambio + persistenza
	var prima : int = prefs.lock_camera
	prefs.lock_camera = prefs.LockCamera.DI_LATO
	var cfg := ConfigFile.new()
	var letto := -1
	if cfg.load(prefs.PATH) == OK:
		letto = int(cfg.get_value(prefs.SEZIONE, "lock_camera", -1))
	print("scritto su disco: %d (atteso %d)" % [letto, prefs.LockCamera.DI_LATO])
	if letto != prefs.LockCamera.DI_LATO:
		print("   LA PREFERENZA NON E' STATA SALVATA")
		esito = 1

	# valore fuori scala: deve essere riportato dentro, non piantato
	prefs.lock_camera = 99
	print("dopo aver assegnato 99: %d (deve restare dentro 0..%d)" % [
		prefs.lock_camera, prefs.LockCamera.size() - 1])
	if prefs.lock_camera >= prefs.LockCamera.size():
		esito = 1

	prefs.lock_camera = prima
	print("esito: ", "OPZIONE SANA" if esito == 0 else "PROBLEMI")
	quit(esito)


func _trova_option(n : Node) -> OptionButton:
	if n is OptionButton:
		return n as OptionButton
	for f in n.get_children():
		var t := _trova_option(f)
		if t:
			return t
	return null
