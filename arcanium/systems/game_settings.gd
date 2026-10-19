extends Node

## PREFERENZE DEL GIOCATORE — separate dal salvataggio della partita.
##
## `SaveManager` tiene lo stato di UNA RUN (casata, checkpoint, esito): comincia
## una partita nuova e riparte da zero, ed è giusto così. Le preferenze no —
## devono sopravvivere a una run nuova e a una morte — quindi vivono in un file
## loro. Tenerle insieme significherebbe che il giocatore si ritrova la camera
## rimessa a default ogni volta che ricomincia.

const PATH := "user://arcanium_settings.cfg"
const SEZIONE := "camera"
const SEZIONE_VIDEO := "video"

## Lo script, non l'autoload: serve per l'enum e il valore di default, che
## vengono valutati prima che gli autoload esistano.
const Display := preload("res://arcanium/systems/display_manager.gd")

## Come si comporta la camera quando sei AGGANCIATO a un nemico. Cambia il
## "combat feeling" più di quanto sembri, per questo è una scelta e non una
## costante: sono quattro giochi diversi.
enum LockCamera {
	DRITTA,    ## in linea dietro il player, il nemico davanti — soulslike
	OBLIQUA,   ## tre quarti, alla Diablo
	DI_LATO,   ## perpendicolare: i due contendenti di fianco, sapore 2.5D
	LIBERA,    ## non insegue: resta dove l'hai messa tu
}

## Scarto di azimut applicato all'allineamento, per stile. `LIBERA` non ha un
## angolo: spegne proprio l'inseguimento (vedi `iso_cam._align_to_lock`).
const ANGOLO_STILE := {
	LockCamera.DRITTA: 0.0,
	LockCamera.OBLIQUA: 45.0,
	LockCamera.DI_LATO: 90.0,
}

const NOME_STILE := {
	LockCamera.DRITTA: "Dritta (soulslike)",
	LockCamera.OBLIQUA: "Obliqua (alla Diablo)",
	LockCamera.DI_LATO: "Di lato (2.5D)",
	LockCamera.LIBERA: "Non inseguire",
}

## Come si comporta lo ZOOM. Non e' una preferenza di comodo: cambia cosa il
## gioco ti fa GUARDARE.
##
## `CLASSICO` scala l'offset e basta, quindi l'angolo di vista resta lo stesso a
## ogni distanza — avvicinandoti vedi le stesse cose piu' grandi.
##
## `CINEMATICO` fa SCENDERE l'elevazione mentre ti avvicini: la camera guarda
## piu' in orizzontale e scopre cio' che sta in alto — chiome, ballatoi, la
## volta di Kalvorn. E' pensato per ambientazioni verticali, dove il dettaglio
## che vale non e' per terra.
##
## ⚠️ Un angolo piu' basso vede piu' PARETI, e nei livelli chiusi puo' infilare
## geometria fra camera e player. La IsoCam dissolve gli occlusori, ma si ferma
## a sei: e' la ragione per cui questa e' una SCELTA e non il comportamento
## unico.
enum ZoomCamera {
	CLASSICO,     ## angolo fisso: ci si avvicina e basta
	CINEMATICO,   ## avvicinandosi la camera si abbassa e mostra il cielo
}

const NOME_ZOOM := {
	ZoomCamera.CLASSICO: "Classico (angolo fisso)",
	ZoomCamera.CINEMATICO: "Cinematico (scopre l'alto)",
}

signal lock_camera_changed(stile : int)
signal zoom_camera_changed(modo : int)
signal video_changed
signal acqua_changed


## Modalità finestra e risoluzione. Applicano SUBITO oltre a salvare: sono le
## uniche preferenze che si vedono a occhio, e una che si salva senza applicarsi
## sembrerebbe semplicemente ignorata.
##
## Il default è schermo intero, come `window/size/mode=3` in project.godot: alla
## prima accensione, senza file di preferenze, il gioco deve comportarsi come si
## è sempre comportato.
var modo_finestra : int = Display.ModoFinestra.SCHERMO_INTERO:
	set(v):
		var nuovo : int = clampi(v, 0, Display.ModoFinestra.size() - 1)
		if nuovo == modo_finestra:
			return
		modo_finestra = nuovo
		_salva()
		_applica_video()
		video_changed.emit()

var risoluzione : Vector2i = Display.RISOLUZIONE_MINIMA:
	set(v):
		var nuova := _risoluzione_valida(v)
		if nuova == risoluzione:
			return
		risoluzione = nuova
		_salva()
		_applica_video()
		video_changed.emit()

## ACQUA RICCA — rifrazione e riflesso sul guado.
##
## ⚠️ Non e' un interruttore dentro uno shader: SCAMBIA lo shader dell'acqua,
## perche' `hint_screen_texture` e' una dichiarazione di compilazione e Godot
## alloca e copia il back-buffer per il solo fatto che un materiale in scena la
## contenga — anche dove l'acqua non si vede. Misurato col banco: +28 MB di VRAM
## su tutto il livello; il tempo (11,91 contro 11,97 ms) sta sotto il rumore. Su
## una integrata che condivide la RAM col gioco la memoria e' una scelta vera, e
## per questo il default e' SPENTO.
var acqua_ricca : bool = false:
	set(v):
		if v == acqua_ricca:
			return
		acqua_ricca = v
		_salva()
		acqua_changed.emit()

var lock_camera : int = LockCamera.DRITTA:
	set(v):
		var nuovo : int = clampi(v, 0, LockCamera.size() - 1)
		if nuovo == lock_camera:
			return
		lock_camera = nuovo
		_salva()
		lock_camera_changed.emit(lock_camera)


var zoom_camera : int = ZoomCamera.CLASSICO:
	set(v):
		var nuovo : int = clampi(v, 0, ZoomCamera.size() - 1)
		if nuovo == zoom_camera:
			return
		zoom_camera = nuovo
		_salva()
		zoom_camera_changed.emit(zoom_camera)


func _ready() -> void:
	_carica()
	_applica_video()


## Angolo di scarto per lo stile corrente. `LIBERA` non arriva mai qui: chi
## chiama controlla prima `insegue()`.
func angolo_lock() -> float:
	return float(ANGOLO_STILE.get(lock_camera, 0.0))


func insegue() -> bool:
	return lock_camera != LockCamera.LIBERA


func zoom_cinematico() -> bool:
	return zoom_camera == ZoomCamera.CINEMATICO


func _carica() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	## assegnato al campo, non alla variabile interna: passa dal setter e quindi
	## dal clamp, così un file rovinato non pianta un valore impossibile
	lock_camera = int(cfg.get_value(SEZIONE, "lock_camera", LockCamera.DRITTA))
	zoom_camera = int(cfg.get_value(SEZIONE, "zoom_camera", ZoomCamera.CLASSICO))
	modo_finestra = int(cfg.get_value(SEZIONE_VIDEO, "modo_finestra", modo_finestra))
	risoluzione = cfg.get_value(SEZIONE_VIDEO, "risoluzione", risoluzione)
	acqua_ricca = bool(cfg.get_value(SEZIONE_VIDEO, "acqua_ricca", acqua_ricca))


func _salva() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  ## conserva le altre sezioni che verranno
	cfg.set_value(SEZIONE, "lock_camera", lock_camera)
	cfg.set_value(SEZIONE, "zoom_camera", zoom_camera)
	cfg.set_value(SEZIONE_VIDEO, "modo_finestra", modo_finestra)
	cfg.set_value(SEZIONE_VIDEO, "risoluzione", risoluzione)
	cfg.set_value(SEZIONE_VIDEO, "acqua_ricca", acqua_ricca)
	cfg.save(PATH)


func _applica_video() -> void:
	var display := get_node_or_null("/root/DisplayManager")
	if display != null:
		display.applica(modo_finestra, risoluzione)


## Una risoluzione che non ci sta nello schermo va rifiutata, non salvata: e' il
## modo piu' facile di restare chiusi fuori dal proprio gioco. Se il file di
## preferenze ne contiene una impossibile (monitor cambiato, config copiata da
## un'altra macchina) si ripiega sulla piu' grande che ci sta.
func _risoluzione_valida(v : Vector2i) -> Vector2i:
	var display := get_node_or_null("/root/DisplayManager")
	if display == null:
		return v
	var buone : Array[Vector2i] = display.risoluzioni_disponibili()
	if v in buone:
		return v
	return buone[buone.size() - 1]
