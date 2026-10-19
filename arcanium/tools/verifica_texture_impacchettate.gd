extends SceneTree
## CANCELLO: le texture che IMPACCHETTANO due mappe in una hanno ancora tutti i
## canali dopo l'import?
##
##   godot --headless --path . --script res://arcanium/tools/verifica_texture_impacchettate.gd
##
## Qui l'headless va bene: si guardano le texture, non una scena col Terrain3D.
## Per gli array del terreno serve l'altro cancello, `verifica_terreno_canali`,
## che deve aprire il livello.
##
## ⚠️ Perche' esiste. Una texture `_nrm_rgh` tiene la NORMALE in RGB e la
## RUVIDEZZA in alpha; una `_alb_ht` tiene l'albedo in RGB e l'ALTEZZA in alpha.
## Basta `compress/normal_map=1` (Enabled) nel `.import` perche' Godot la tratti
## come sorgente-normale e scelga **RGTC_RG (BC5)**, che ha due soli canali:
##
##   - l'alpha non c'e' PROPRIO -> la ruvidezza sparisce;
##   - e il BLU vale zero -> uno shader che legge `texture(...).rgb * 2.0 - 1.0`
##     ottiene una normale che punta DENTRO la superficie.
##
## Nessuna delle due cose da' un errore. Il file si importa, il gioco parte.
##
## Il confronto si fa fra il PNG sorgente e l'immagine che il motore ha davvero
## in memoria dopo l'import: il `.import` dichiara le intenzioni, non l'esito.

const Canali := preload("res://arcanium/tools/confronto_canali.gd")

## Le texture a canali impacchettati che NON passano da Terrain3D, cioe' quelle
## che un materiale o uno shader legge direttamente.
## Vaelthar Tournament: quelle che c'erano erano tutte di Kalvorn (guado e tronchi
## giganti), andate con lui. Le nuove si aggiungono qui come {"file", "chi"}.
var IMPACCHETTATE : Array = []

## Suffissi che DICHIARANO un impacchettamento: se il nome promette una seconda
## mappa nell'alpha, il formato importato deve avere l'alpha.
const SUFFISSI_IMPACCHETTATI := ["_rgh", "_ht", "_orm", "_arm", "_mask", "_pack"]
## Dove cercare. Non tutto il progetto: le normali PURE (`*_normal.png`) stanno
## benissimo a `normal_map=1`, ed e' anzi la scelta giusta — RGTC tiene X e Y
## meglio di BPTC nello stesso spazio. Il guasto e' solo di chi impacchetta.
const CARTELLE := ["res://assets", "res://arcanium", "res://characters", "res://player"]

var _problemi := 0
var _degradati := 0


func _init() -> void:
	print("═══ texture a canali impacchettati ═══")

	## L'autoprova vuole un alpha che porti informazione: si usa la prima
	## impacchettata se c'e', altrimenti un rumore sintetico (stesso criterio).
	var prima: Image = null
	if not IMPACCHETTATE.is_empty():
		prima = Image.load_from_file(IMPACCHETTATE[0]["file"])
		if prima == null:
			_fallisci("autoprova: %s illeggibile" % IMPACCHETTATE[0]["file"])
			_esito()
			return
	else:
		prima = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for y in 64:
			for x in 64:
				prima.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var prova := Canali.autoprova(prima)
	print("  autoprova (alpha appiattito): r=%.3f  err %.1f  ->  %s" % [
		prova["r"], prova["err"], "BOCCIATO" if prova["rotto"] else "PASSATO"])
	if not prova["rotto"]:
		_fallisci("autoprova: il criterio NON boccia un canale appiattito — cancello inservibile")
		_esito()
		return

	for voce in IMPACCHETTATE:
		_controlla(voce["file"], voce["chi"])

	print("  --- scansione: nomi che promettono un canale impacchettato ---")
	var trovati := 0
	for cartella in CARTELLE:
		trovati += _scandaglia(cartella)
	print("      %d .import controllati per suffisso" % trovati)
	_esito()


## Cerca i `.import` il cui NOME dichiara un impacchettamento ma che sono
## importati come sorgente-normale: `compress/normal_map=1` porta a un formato a
## due canali, e la mappa promessa dal nome non arriverebbe mai alla GPU.
func _scandaglia(cartella: String) -> int:
	var n := 0
	var d := DirAccess.open(cartella)
	if d == null:
		return 0
	d.list_dir_begin()
	var voce := d.get_next()
	while voce != "":
		var percorso := "%s/%s" % [cartella, voce]
		if d.current_is_dir():
			if not voce.begins_with("."):
				n += _scandaglia(percorso)
		elif voce.ends_with(".import"):
			n += 1
			var nome := voce.trim_suffix(".import").get_basename()
			var promette := false
			for suff in SUFFISSI_IMPACCHETTATI:
				if nome.ends_with(suff):
					promette = true
			if promette:
				var testo := FileAccess.get_file_as_string(percorso)
				if testo.contains("compress/normal_map=1"):
					_fallisci("%s: il nome promette un canale impacchettato ma sta a compress/normal_map=1 (formato a due canali)"
						% percorso.trim_prefix("res://"))
		voce = d.get_next()
	d.list_dir_end()
	return n


func _controlla(percorso: String, chi: String) -> void:
	var etichetta := percorso.get_file().get_basename()
	var tex: Texture2D = ResourceLoader.load(percorso)
	if tex == null:
		_fallisci("%s: non caricabile" % etichetta)
		return
	var importata: Image = tex.get_image()
	if importata == null:
		_fallisci("%s: immagine importata non leggibile" % etichetta)
		return

	var formato := importata.get_format()
	print("  %s" % etichetta)
	print("      formato importato: %s   %dx%d   mipmap=%s" % [
		Canali.nome_formato(formato), importata.get_width(), importata.get_height(),
		importata.has_mipmaps()])
	print("      lo legge: %s" % chi)

	# Il primo controllo non ha nemmeno bisogno di confrontare i pixel: certi
	# formati il canale alpha non ce l'hanno per costruzione.
	if not Canali.ha_alpha(formato):
		_fallisci("%s: %s NON HA il canale alpha — la mappa impacchettata li' dentro e' persa"
			% [etichetta, Canali.nome_formato(formato)])
		return

	var sorgente := Image.load_from_file(percorso)
	if sorgente == null:
		_fallisci("%s: PNG sorgente illeggibile" % etichetta)
		return
	sorgente.convert(Image.FORMAT_RGBA8)
	var vista := Canali.in_chiaro(importata)
	if vista == null:
		_fallisci("%s: immagine importata non decomprimibile" % etichetta)
		return
	if vista.get_size() != sorgente.get_size():
		_fallisci("%s: importata %s, sorgente %s" % [
			etichetta, vista.get_size(), sorgente.get_size()])
		return

	var misure := Canali.metrica(sorgente, vista)
	var rotto := false
	var degradati: Array[String] = []
	for c in 4:
		if misure[c]["rotto"]:
			rotto = true
		if misure[c]["degradato"]:
			degradati.append(Canali.NOMI[c])
	if rotto:
		_fallisci("%s  %s" % [etichetta, Canali.riga(misure)])
	elif not degradati.is_empty():
		_degradati += 1
		print("      [~]  %s   <- rumore su %s, canale intero" % [
			Canali.riga(misure), "+".join(degradati)])
	else:
		print("      [ok] %s" % Canali.riga(misure))


func _esito() -> void:
	if _problemi == 0:
		if _degradati > 0:
			print("ESITO: I CANALI REGGONO (%d texture con rumore di compressione, nessun canale perso)" % _degradati)
		else:
			print("ESITO: I CANALI REGGONO")
		quit()
	else:
		print("ESITO: %d TEXTURE CON UN CANALE PERSO" % _problemi)
		quit(1)


func _fallisci(messaggio: String) -> void:
	_problemi += 1
	print("      [NO] %s" % messaggio)
