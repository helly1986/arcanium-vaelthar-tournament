extends CanvasLayer

## Contatore delle prestazioni, per misurare sul telefono (Fase 1 del piano).
##
## A schermo, in alto a sinistra: fps, tempo di frame medio e peggiore
## dell'ultimo secondo, draw call, primitive, memoria video. Ogni secondo la
## stessa riga va anche nel log con il prefisso "PRESTAZIONI:", che si legge dal
## PC senza guardare il telefono:
##     adb logcat -s godot | grep PRESTAZIONI
## Ogni minuto stampa anche il riassunto del minuto (fps minimo, medio e i frame
## oltre i 33 ms), che e' il numero del cancello: 30 fps stabili per 10 minuti.
##
## Si aggiunge a qualunque scena come nodo figlio; non tocca il gioco.

var _etichetta : Label
var _tempi : Array[float] = []          ## tempi di frame dell'ultimo secondo, in ms
var _da_ultimo := 0.0
var _secondi := 0
var _fps_minuto : Array[float] = []
var _lenti_minuto := 0                  ## frame oltre 33.3 ms nel minuto


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_etichetta = Label.new()
	_etichetta.position = Vector2(12, 8)
	_etichetta.add_theme_font_size_override("font_size", 22)
	_etichetta.add_theme_color_override("font_outline_color", Color.BLACK)
	_etichetta.add_theme_constant_override("outline_size", 6)
	add_child(_etichetta)


func _process(delta : float) -> void:
	var ms := delta * 1000.0
	_tempi.append(ms)
	if ms > 33.4:
		_lenti_minuto += 1
	_da_ultimo += delta
	if _da_ultimo < 1.0:
		return
	_da_ultimo = 0.0
	_secondi += 1
	var somma := 0.0
	var peggiore := 0.0
	for t in _tempi:
		somma += t
		peggiore = maxf(peggiore, t)
	var medio := somma / maxf(1.0, _tempi.size())
	var fps := Engine.get_frames_per_second()
	_tempi.clear()
	var draw := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var prim := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var vmem := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var riga := "%d fps  %.1f ms (peggiore %.1f)  draw %d  prim %dk  vmem %d MB" % [
		fps, medio, peggiore, draw, int(prim / 1000.0), int(vmem)]
	_etichetta.text = riga
	print("PRESTAZIONI: t=%ds %s" % [_secondi, riga])
	_fps_minuto.append(fps)
	if _secondi % 60 == 0:
		var minimo := 1000.0
		var tot := 0.0
		for f in _fps_minuto:
			minimo = minf(minimo, f)
			tot += f
		print("PRESTAZIONI: minuto %d — fps minimo %d, medio %.1f, frame oltre 33 ms %d" % [
			_secondi / 60, int(minimo), tot / _fps_minuto.size(), _lenti_minuto])
		_fps_minuto.clear()
		_lenti_minuto = 0
