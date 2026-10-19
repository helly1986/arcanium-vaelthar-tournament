extends RefCounted
class_name Suoni

## SUONI DI ARCANIUM — il ponte fra il codice e la libreria in `audio/SoundFX/`.
##
##   Suoni.nel_mondo(nodo, Suoni.SCHIANTO_MASSO)      # posizionato, si attenua
##   Suoni.addosso(Suoni.voce_lieve())                # sul giocatore, non attenuato
##   var l := Suoni.loop_nel_mondo(campo, Suoni.MORSA_GELO)  ... l.spegni(0.4)
##
## ─── PERCHÉ ESISTE (invece di mettere AudioStreamPlayer3D nelle scene) ───────
## I sistemi che devono suonare — schianti, crolli, colpi subiti — NASCONO A
## RUNTIME e non hanno una scena propria dove appendere un nodo audio. Servirebbe
## comunque codice; tanto vale che sia in un posto solo e che porti con sé le tre
## cose che nessuno si ricorda mai di fare:
##   ① la VARIANTE a caso, così lo stesso colpo non si ripete identico;
##   ② il PITCH a caso, che è ciò che rende diverse anche due riproduzioni della
##      stessa variante;
##   ③ il bus giusto, così il giocatore può abbassare gli effetti senza toccare
##      la musica.
##
## ⚠️ Il nodo si autodistrugge a fine riproduzione. Senza, ogni colpo lascerebbe
## un AudioStreamPlayer3D morto nell'albero: in uno scontro lungo sono centinaia.

const BUS := "SFX"

## ─── La libreria ────────────────────────────────────────────────────────────
const SCHIANTO_MASSO  := "res://audio/SoundFX/schianto/schianto_masso_1.wav"
const CROLLO_COLONNA  := "res://audio/SoundFX/schianto/crollo_colonna_1.wav"
const CARICA_ARCANA   := "res://audio/SoundFX/magia/carica_arcana_1.wav"
const VERATH_SPETTRALE := "res://audio/SoundFX/magia/verath_spettrale_1.wav"
const ICE_SHARD       := "res://audio/SoundFX/magia/ice_shard_1.wav"
const MORSA_GELO      := "res://audio/SoundFX/magia/morsa_del_gelo_loop.wav"
const MORSA_GELO_UNA  := "res://audio/SoundFX/magia/morsa_del_gelo_oneshot.wav"
const ULULATO_ALPHA   := "res://audio/SoundFX/nemici/ululato_alpha_1.wav"
const LUPO_RINGHIO    := "res://audio/SoundFX/nemici/lupo_ringhio_1.wav"
const LUPO_MORSO      := "res://audio/SoundFX/nemici/lupo_morso_1.wav"
const CONSUMATO_COLPITO := "res://audio/SoundFX/nemici/consumato_colpito_1.wav"
const SENZANOME_RUGGITO := "res://audio/SoundFX/nemici/senzanome_ruggito_1.wav"
const CONO_ACCUMULO   := "res://audio/SoundFX/ambiente/cono_accumulo_calmo_loop.wav"
const PYRRATH_FRESA   := "res://audio/SoundFX/ambiente/pyrrath_fresatrice_acciaio_loop.wav"

## ⚠️ ANNUNCI DEI CONSUMATI: uno a caso fra le indoli. Sono creature diverse per
## tipologia e casata, quindi qui la varieta' di VOCE e' voluta — al contrario
## del protagonista, dove sarebbe un difetto (vedi `voce_lieve`).
const CONSUMATO_ANNUNCI : PackedStringArray = [
	"res://audio/SoundFX/nemici/consumato_annuncio_saggio_1.wav",
	"res://audio/SoundFX/nemici/consumato_annuncio_saggio_2.wav",
	"res://audio/SoundFX/nemici/consumato_annuncio_belligerante_1.wav",
	"res://audio/SoundFX/nemici/consumato_annuncio_mago_tuha.wav",
	"res://audio/SoundFX/nemici/consumato_annuncio_mago_saka.wav",
]
## Morte: tre gradi della stessa firma, a caso.
const CONSUMATO_MORTI : PackedStringArray = [
	"res://audio/SoundFX/nemici/consumato_morte_A.wav",
	"res://audio/SoundFX/nemici/consumato_morte_B.wav",
	"res://audio/SoundFX/nemici/consumato_morte_C.wav",
]

## ─── Fendenti ───────────────────────────────────────────────────────────────
## ⚠️ Indicizzati per MODO DI ATTRAVERSARE L'ARIA, non per arma. Una lama e una
## lancia fendono; una mazza SPINGE. Sono due suoni diversi, e bastano loro due
## per tutto l'arsenale — la personalita' della singola arma sta nel COLPO.
const FENDENTI := {
	"TAGLIO":        ["fendente_taglio_leggero_1", "fendente_taglio_pesante_1"],
	"PERFORAZIONE":  ["fendente_perforazione_leggero_1", "fendente_perforazione_pesante_1"],
	"SCHIANTO":      ["fendente_schianto_leggero_1", "fendente_schianto_pesante_1"],
}

## ─── Colpi ──────────────────────────────────────────────────────────────────
## ⚠️ QUI vive la personalita' dell'arma, non nel fendente. Nell'aria una lama e
## una lancia suonano uguale; e' quando TOCCANO che si distinguono — e si
## distinguono due volte, perche' conta anche COSA hanno toccato.
const COLPI := {
	"TAGLIO":       ["colpo_taglio_bersaglio_1", "colpo_taglio_mondo_1"],
	"PERFORAZIONE": ["colpo_perforazione_bersaglio_1", "colpo_perforazione_mondo_1"],
	"SCHIANTO":     ["colpo_schianto_bersaglio_1", "colpo_schianto_mondo_1"],
}

## Colpo per tipo di danno e bersaglio colpito. `nel_mondo` = ha preso una parete,
## il terreno, una colonna — qualcosa che non sanguina.
static func colpo(damage_type : String, sul_mondo : bool) -> String:
	var fam : Array = COLPI.get(damage_type, COLPI["TAGLIO"])
	return "res://audio/SoundFX/colpi/%s.wav" % fam[1 if sul_mondo else 0]


## Fendente per tipo di danno dell'arma e peso del colpo. I tipi che non hanno
## una famiglia loro (CRIO, SACRO, EROSIONE...) ricadono sul taglio: sono quasi
## sempre lame incantate, e il metallo nell'aria suona uguale.
static func fendente(damage_type : String, pesante : bool) -> String:
	var fam : Array = FENDENTI.get(damage_type, FENDENTI["TAGLIO"])
	return "res://audio/SoundFX/fendenti/%s.wav" % fam[1 if pesante else 0]

## Un annuncio a caso fra le indoli dei Consumati.
static func consumato_annuncio() -> String:
	return CONSUMATO_ANNUNCI[randi() % CONSUMATO_ANNUNCI.size()]

static func consumato_morte() -> String:
	return CONSUMATO_MORTI[randi() % CONSUMATO_MORTI.size()]

## ─── Voce del protagonista ──────────────────────────────────────────────────
## ⚠️ Le due voci NON sono intercambiabili a caso: sono due persone diverse, e
## il giocatore ne ha scelta una. Si imposta una volta e vale per tutto.
enum Voce { MASCHILE, FEMMINILE }
static var voce : Voce = Voce.MASCHILE

const LIEVI := 5   ## quante varianti del lamento leggero ci sono su disco

## Una delle 5 varianti del dolore lieve, a caso.
static func voce_lieve() -> String:
	return "res://audio/SoundFX/player/voce_%s_lieve_%d.wav" % [_v(), randi_range(1, LIEVI)]

## Il grido del colpo grave. ⚠️ Ce n'è UNO SOLO: è raro per costruzione (serve un
## colpo che tolga più di metà vita), quindi la ripetizione non si nota. Se un
## giorno diventasse frequente, vorrà dire che il bilanciamento è cambiato — e
## servirebbero le varianti prima ancora del suono nuovo.
static func voce_forte() -> String:
	return "res://audio/SoundFX/player/voce_%s_forte_1.wav" % _v()

## Il lamento continuo (danno nel tempo). È un LOOP: va spento, non aspettato.
static func voce_continua() -> String:
	return "res://audio/SoundFX/player/voce_%s_continuo_loop.wav" % _v()

static func _v() -> String:
	return "f" if voce == Voce.FEMMINILE else "m"


# ---------------------------------------------------------------------------
# RIPRODUZIONE
# ---------------------------------------------------------------------------

## Suono POSIZIONATO nel mondo: si attenua con la distanza e arriva da dove
## succede. Per schianti, crolli, magie, nemici.
static func nel_mondo(dove : Node3D, percorso : String, volume_db : float = 0.0,
		variazione_tono : float = 0.12) -> AudioStreamPlayer3D:
	if dove == null or not dove.is_inside_tree():
		return null
	var s := _stream(percorso)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = BUS
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-variazione_tono, variazione_tono)
	## ⚠️ Tarato sulla camera ISOMETRICA (~20-30 m). I default di Godot sono
	## pensati per la prima persona: con quelli, un crollo a dieci metri sarebbe
	## già quasi inudibile e il campo di battaglia risulterebbe muto.
	p.unit_size = 12.0
	p.max_distance = 60.0
	## Al nodo RADICE, non a `dove`: un boss che muore non deve portarsi via il
	## suono del colpo che lo ha ucciso.
	var radice := dove.get_tree().current_scene
	if radice == null:
		radice = dove.get_tree().root
	radice.add_child(p)
	p.global_position = dove.global_position
	p.play()
	p.finished.connect(p.queue_free)
	return p


## Suono ADDOSSO al giocatore: niente attenuazione, niente direzione. Per la sua
## voce e per la UI. ⚠️ Un lamento posizionato nello spazio suonerebbe come se a
## lamentarsi fosse qualcun altro.
static func addosso(percorso : String, volume_db : float = 0.0,
		variazione_tono : float = 0.06) -> AudioStreamPlayer:
	var albero := Engine.get_main_loop() as SceneTree
	if albero == null:
		return null
	var s := _stream(percorso)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = BUS
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-variazione_tono, variazione_tono)
	var radice : Node = albero.current_scene if albero.current_scene else albero.root
	radice.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


## Loop posizionato che si tiene e si spegne a comando (campo di gelo, Cono,
## officine, lamento continuo). Ritorna il nodo: chiamare `spegni()` su di esso.
static func loop_nel_mondo(dove : Node3D, percorso : String,
		volume_db : float = 0.0) -> AudioStreamPlayer3D:
	var p := nel_mondo(dove, percorso, volume_db, 0.0)
	if p == null:
		return null
	## Il segnale `finished` non arriva mai su un loop, quindi la connessione
	## fatta da `nel_mondo` è innocua ma inutile: la vita la decide chi chiama.
	_rendi_loop(p.stream)
	return p


## Spegne un loop in dissolvenza e lo libera.
##
## ⚠️ È QUI che si fa la dissolvenza di un loop, non nel file. Un fade cotto
## dentro un campione che gira diventa un avvallamento a ogni giro, e si sente
## come un battito regolare.
static func spegni(p : Node, durata : float = 0.4) -> void:
	if p == null or not is_instance_valid(p):
		return
	var tw := (p as Node).create_tween()
	tw.tween_property(p, "volume_db", -60.0, durata)
	tw.tween_callback(p.queue_free)


# ---------------------------------------------------------------------------
# DOLORE CONTINUO — il lamento mentre si brucia, si avvelena, si gela
# ---------------------------------------------------------------------------
#
# ⚠️ A CONTEGGIO, non acceso/spento. Le fonti di danno nel tempo possono essere
# più d'una insieme (il muro di fuoco del Senza Nome mentre il veleno della sua
# spada sta già scorrendo): con un semplice booleano, la prima che finisce
# spegnerebbe il lamento mentre l'altra sta ancora facendo male. Ogni sorgente
# apre e chiude la SUA, e la voce tace solo quando non ne resta nessuna.
#
# ⚠️ Ed è UNO SOLO per tutte. Due fonti insieme non devono dare due lamenti
# sovrapposti — quello è il rumore di due persone che soffrono, non di una che
# soffre il doppio.

static var _dolore_fonti : int = 0
static var _dolore_voce : Node = null

## Una fonte di danno continuo è cominciata.
static func dolore_continuo_avvia() -> void:
	_dolore_fonti += 1
	if _dolore_fonti > 1 or _dolore_voce != null:
		return
	_dolore_voce = addosso(voce_continua(), -6.0, 0.0)
	if _dolore_voce != null:
		_rendi_loop((_dolore_voce as AudioStreamPlayer).stream)
		## `addosso` collega `finished` a `queue_free`: su un loop non scatta
		## mai, ma la connessione resterebbe lì a confondere chi legge.
		var p := _dolore_voce as AudioStreamPlayer
		if p.finished.is_connected(p.queue_free):
			p.finished.disconnect(p.queue_free)

## Quella fonte è finita. Alla fine dell'ultima, la voce si spegne.
static func dolore_continuo_ferma() -> void:
	_dolore_fonti = maxi(_dolore_fonti - 1, 0)
	if _dolore_fonti > 0:
		return
	spegni(_dolore_voce, 0.6)
	_dolore_voce = null

## Azzera tutto. Da chiamare alla morte e ai cambi di scena: il conteggio è
## statico e sopravvivrebbe al caricamento di un livello, lasciando il
## protagonista a lamentarsi in un posto dove non gli sta succedendo niente.
static func dolore_continuo_azzera() -> void:
	_dolore_fonti = 0
	spegni(_dolore_voce, 0.2)
	_dolore_voce = null


static func _rendi_loop(s : AudioStream) -> void:
	## I WAV importati da Godot non sono in loop di default: lo si dice qui, così
	## chi aggiunge un suono nuovo non deve ricordarsi di toccare il .import.
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = (s as AudioStreamWAV).data.size() / 2


static var _cache : Dictionary = {}

static func _stream(percorso : String) -> AudioStream:
	if _cache.has(percorso):
		return _cache[percorso]
	if not ResourceLoader.exists(percorso):
		push_warning("Suoni: manca %s" % percorso)
		_cache[percorso] = null
		return null
	var s : AudioStream = load(percorso)
	_cache[percorso] = s
	return s
