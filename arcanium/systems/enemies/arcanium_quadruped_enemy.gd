extends "res://arcanium/systems/enemies/arcanium_enemy.gd"
class_name ArcaniumQuadrupedEnemy

## ═══════════════════════════════════════════════════════════════════════════
## NEMICO QUADRUPEDE — il Branco Guasto (lupo comune e Alpha)
## ═══════════════════════════════════════════════════════════════════════════
##
## Una bestia che colpisce col CORPO: niente arma, niente hitbox fisica da
## spazzare, niente finisher subiti. Il morso arriva agli istanti di contatto
## dichiarati dal move set — cioè esattamente il modello della superclasse — e
## qui restano solo le tre cose davvero quadrupedi:
##
##   • BRANCO: se cade l'Alpha i superstiti fuggono (lore 3bis) — vittoria
##     senza sterminio.
##   • ULULATO: l'Alpha richiama rinforzi; il segnale lo raccoglie il director.
##   • BALZO: volo agganciato al bersaglio, con lo spostamento guidato dal
##     codice perché le clip sono IN-PLACE.
##
## ⚠️ Le clip del lupo sono authorate IN-PLACE (vedi wolf_rig.blend): NON
## animare `Hips.location`, o il corpo sprofonda e scivola. L'avanzamento lo
## mette il controller via velocity.

@export_group("Identità")
## L'Alpha è un MINI-BOSS: scala, HP e danni maggiorati stanno sull'ISTANZA
## (override di scena); qui vive solo ciò che cambia nel COMPORTAMENTO —
## l'ululato di richiamo e la morte che scioglie il branco.
@export var is_alpha : bool = false
## L'Alpha della Traccia e' un MINI-BOSS: barra a fondo schermo (la aggancia il
## director) e banner alla morte. Il capobranco di Kalvorn (lupo_capobranco.tscn)
## e' un Alpha senza quel rango: comanda il branco e lo richiama, ma tiene la
## barretta sopra la testa come ogni lupo. Senza barretta e senza barra da boss
## sarebbe l'unico nemico di cui non si vede la vita.
@export var mini_boss : bool = true

## Emesso dall'Alpha all'apice dell'ululato: il director spawna i rinforzi.
signal howl_summon

## Clip dell'ululato: non fa danno, richiama. Riconosciuta per nome perché è una
## coreografia, non un attacco.
const HOWL_ANIM := "howl"
## L'ululato può arrivare dal GLB base (`howl`) o dalla libreria separata
## (`wolf/wolf_howl_01`, animato a mano in Cascadeur: 15 ossa in movimento
## contro l'unica del GLB base). Il riconoscimento accetta ENTRAMBI, così
## cambiare sorgente non spegne la chiamata dei rinforzi — che è l'unica cosa
## che questa clip deve fare.
const HOWL_ANIM_LIB := "wolf/wolf_howl_01"
## Istante (s, clip a velocità 1.0) in cui il muso arriva su e parte il richiamo.
## ⚠️ Va tenuto VICINO ALLA FINE della clip. Era 0.55 su un ululato che dura
## 2.67s: il branco arrivava prima che l'Alpha avesse finito di alzare il muso,
## e la chiamata sembrava scollegata da ciò che la causava. Il richiamo deve
## essere la CONCLUSIONE del gesto, non il suo inizio.
const HOWL_CALL_TIME := 2.20
## Finestra di volo del balzo, come frazioni della clip (accucciata a f8,
## atterraggio a f26 su 36).
const LEAP_AIR_START := 0.22
const LEAP_AIR_END := 0.72
const LEAP_LAND_OFFSET := 1.0
const LEAP_MAX_SPEED := 16.0
## Quanto corre via un superstite prima di sparire.
const FLEE_TIME := 5.0

## Mossa di balzo in corso: il VOLO è coreografia (la clip è in-place, lo
## spostamento lo mette il codice), ma il COLPO no — quello arriva all'istante
## di contatto misurato come per ogni altra mossa. Prima l'impatto era inchiodato
## alla fine della finestra di volo, cioè 0.86 s, mentre il muso tocca a 0.70:
## un ritardo di oltre un decimo e mezzo su una mossa che si deve schivare a
## tempo.
var _leap_move : EnemyMove = null
## La mossa in corso, per chi deve consultarne i parametri mentre gira (lo
## scatto di `_slancio_su_contatto` legge `passo_avanti` e `contact_times`).
var _mossa_corrente : EnemyMove = null
## Metri di mondo che la clip ha gia' fatto percorrere (vedi `segue_root_motion`).
var _avanzato_clip : float = 0.0
var _flee_until : float = 0.0


func _init() -> void:
	# Il branco è più svelto e più reattivo di un umanoide corazzato.
	walk_speed = 1.6
	run_speed = 4.2
	turn_rate = 3.0
	run_distance = 3.5
	aggro_range = 12.0


func _setup() -> void:
	add_to_group("wolf_pack")
	# `is_alpha` arriva dall'istanza, quindi si legge qui e non in `_init`:
	# l'Alpha è un mini-boss e ha già la barra a fondo schermo.
	if is_alpha and mini_boss:
		show_floating_health = false
	_load_extra_library()


# ═══════════════════════════════════════════════════════════════════════════
# Clip autorate a mano, fuori dal GLB del modello
# ═══════════════════════════════════════════════════════════════════════════
## Il GLB del lupo HA una clip `death`, ma è inerte: misurata, in 1.6s il corpo
## scende di 4 cm — meno dell'idle, che ne scende 7. Il lupo moriva in piedi e
## spariva. La morte vera è autorata a parte ed esportata come GLB di SOLA
## ARMATURA (39 KB): così il GLB del modello — 6.7 MB con le texture — non va
## mai ri-esportato, che è la regola imparata a caro prezzo sul pugno del
## protagonista (ri-esportare il base sopra il file buono lo distrugge).
const EXTRA_ANIM_DIR := "res://assets/characters/enemies/anims/wolf/"
## `wolf_bite_01` / `wolf_bite_combo_01`: le clip d'attacco del GLB non avevano
## un anticipo leggibile. Misurate: in tutta la carica del morso la testa
## arretrava di 2.8 cm e saliva di 2.1 (su una testa che sta 31 cm sopra l'anca)
## e il corpo non si accovacciava affatto — con lo zoom isometrico il morso
## arrivava senza preavviso. Le nuove hanno una carica vera (accovacciamento,
## muso alzato, orecchie indietro) e, nella combo, una SECONDA carica visibile
## fra i due morsi, che prima erano attaccati.
const EXTRA_CLIPS : PackedStringArray = [
	"wolf_death_01", "wolf_bite_01", "wolf_bite_combo_01", "wolf_howl_01",
]
const EXTRA_LIB := "wolf"

func _load_extra_library() -> void:
	if anim_player == null:
		return
	## Prefisso di traccia REALE: si ricava dallo scheletro vero di questa scena
	## invece di darlo per scontato, così vale anche se un domani il modello
	## viene sostituito con un rig dal nome diverso.
	var sk : Skeleton3D = null
	var radice : Node = anim_player.get_node_or_null(anim_player.root_node)
	if radice:
		sk = radice.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return
	var sk_rel := str(radice.get_path_to(sk))

	var lib := AnimationLibrary.new()
	for clip in EXTRA_CLIPS:
		var path := EXTRA_ANIM_DIR + clip + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate()
		var ap : AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if ap == null or ap.get_animation_list().is_empty():
			inst.queue_free()
			continue
		var anim : Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		for i in anim.get_track_count():
			var p := str(anim.track_get_path(i))
			var colon := p.find(":")
			if colon >= 0:
				anim.track_set_path(i, "%s:%s" % [sk_rel, p.substr(colon + 1)])
		lib.add_animation(clip, anim)
		inst.queue_free()
	if lib.get_animation_list().is_empty():
		return
	if anim_player.has_animation_library(EXTRA_LIB):
		anim_player.remove_animation_library(EXTRA_LIB)
	anim_player.add_animation_library(EXTRA_LIB, lib)

	## Si passa alla clip nuova solo se è arrivata davvero: se il GLB manca, il
	## lupo continua a usare la `death` del modello invece di restare senza.
	if anim_player.has_animation("%s/wolf_death_01" % EXTRA_LIB):
		death_anim = "%s/wolf_death_01" % EXTRA_LIB


# ═══════════════════════════════════════════════════════════════════════════
# Fuga (branco sciolto)
# ═══════════════════════════════════════════════════════════════════════════

func _special_state_step(delta : float) -> bool:
	if _state != State.FLEE:
		return false
	# Corre via dal player e sparisce a fine fuga: il combattimento si risolve
	# senza doverli inseguire uno per uno.
	if _now() > _flee_until:
		queue_free()
		return true
	_apply_gravity(delta)
	if is_instance_valid(target):
		var away := -_flat_dir_to(target)
		rotation.y = lerp_angle(rotation.y, atan2(away.x, away.z),
			clampf(turn_rate * 2.0 * delta, 0.0, 1.0))
		velocity.x = away.x * run_speed * 1.3
		velocity.z = away.z * run_speed * 1.3
	_play(run_anim, true)
	move_and_slide()
	return true


## Lore: se l'Alpha cade, i superstiti fuggono.
func on_ally_died() -> void:
	if is_alpha or _state == State.DEAD:
		return
	_state = State.FLEE
	_busy = false
	_leap_move = null
	_flee_until = _now() + FLEE_TIME


# ═══════════════════════════════════════════════════════════════════════════
# Movimento in attacco
# ═══════════════════════════════════════════════════════════════════════════

func _attack_motion(delta : float) -> void:
	_controlla_atterraggio_balzo()
	var volo := _leap_air_remaining()
	if _busy and _mossa_corrente != null and _mossa_corrente.segue_root_motion:
		# La clip porta il passo: il corpo lo segue lungo il proprio verso.
		var fatto := _avanzamento_clip()
		var passo : float = fatto - _avanzato_clip
		_avanzato_clip = fatto
		var avanti := global_transform.basis.z
		avanti.y = 0.0
		avanti = avanti.normalized()
		var v : float = passo / delta if delta > 0.0 else 0.0
		velocity.x = avanti.x * v
		velocity.z = avanti.z * v
	elif _busy and volo > 0.0 and is_instance_valid(target):
		# BALZO AGGANCIATO: mentre è per aria punta te, non la traiettoria della
		# clip. È lecito SOLO qui — a mezz'aria i piedi non toccano, quindi
		# allungare il volo non produce foot-sliding; a terra si vedrebbe.
		var dir := _flat_dir_to(target)
		var gap : float = maxf(_flat_distance(target) - LEAP_LAND_OFFSET, 0.0)
		var spd : float = clampf(gap / volo, 0.0, LEAP_MAX_SPEED)
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
	elif _busy and not _attack_released:
		# Durante la CARICA il lupo sta fermo: gira verso di te (facing) ma non
		# cammina. Prima qui veniva avanti a passo (walk_speed) per tutto il
		# wind-up: misurato con misura_carica.py, il doppio morso guadagnava da
		# 0,9 a 1,3 m mentre caricava. L'utente (2026-10-15): un lupo che carica
		# il balzo resta fermo, semmai arretra — ed e' cio' che fa il morso
		# singolo, la cui clip porta indietro il corpo (segue_root_motion).
		# Una clip in-place non arretra per codice: le zampe scivolerebbero.
		velocity.x = 0.0
		velocity.z = 0.0
	elif _busy and is_instance_valid(target):
		var scatto := _slancio_su_contatto()
		if scatto > 0.0:
			var sdir := _flat_dir_to(target)
			velocity.x = sdir.x * scatto
			velocity.z = sdir.z * scatto
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0


## Metri di MONDO che la clip in corso ha percorso dal suo inizio, letti dalla
## traccia del `Root` lungo il suo asse di viaggio (inizio -> fine). Solo la
## lunghezza: gli assi del Root seguono la convenzione dello scheletro, e per
## il lupo (WolfRig ruotato) indovinarli e' gia' costato un giro sbagliato.
## Scalata col modello, come la falcata (`_velocita_di_falcata`).
func _avanzamento_clip() -> float:
	if anim_player == null or anim_player.root_motion_track.is_empty():
		return 0.0
	var nome := anim_player.current_animation
	if nome == "" or not anim_player.has_animation(nome):
		return 0.0
	var a : Animation = anim_player.get_animation(nome)
	var i : int = a.find_track(anim_player.root_motion_track, Animation.TYPE_POSITION_3D)
	if i < 0 or a.length <= 0.0:
		return 0.0
	var p0 : Vector3 = a.position_track_interpolate(i, 0.0)
	var asse : Vector3 = a.position_track_interpolate(i, a.length) - p0
	if asse.length() < 0.0001:
		return 0.0
	var p : Vector3 = a.position_track_interpolate(i, anim_player.current_animation_position)
	var scala := 1.0
	if model != null:
		scala = model.global_transform.basis.get_scale().x
	return (p - p0).dot(asse.normalized()) * scala


## Velocità dello SCATTO che precede un contatto, o 0 fuori dalle finestre.
##
## Serve alle mosse che devono leggersi come avanzanti ma hanno una clip che non
## avanza (vedi `passo_avanti` in enemy_move.gd). Il lupo guadagna terreno **a
## ogni morso** invece che di continuo: è la differenza fra una combo che ti
## incalza e una che ti insegue.
##
## ⚠️ Tre guardie, e servono tutte e tre:
##  1. **mai dentro il telegraph** — la finestra viene troncata all'istante in
##     cui la carica finisce. La carica è il momento in cui il giocatore legge
##     la mossa: un nemico che intanto guadagna terreno gliela rende illeggibile,
##     ed è precisamente ciò che questa funzione NON deve fare;
##  2. **mai addosso** — sotto la distanza di contatto lo scatto si spegne, o il
##     lupo spinge il giocatore invece di morderlo;
##  3. **niente sconfinamenti fra un contatto e l'altro** — la finestra non può
##     essere più lunga dell'intervallo fra due morsi, o il secondo scatto
##     comincerebbe prima che il primo abbia finito e si sommerebbero.
## ⚠️ È una distanza, quindi CRESCE COL CORPO. Riferita alla scala del lupo
## comune (3.6): l'Alpha, che sta a 6.5, si ferma di conseguenza più lontano.
## Con un valore fisso il nemico grosso avrebbe continuato a spingere quando ti
## è già addosso — la stessa disattenzione per cui l'Alpha aveva le portate del
## lupo piccolo pur avendo un corpo lungo il doppio.
const SCATTO_DISTANZA_MINIMA := 1.15
const SCATTO_SCALA_RIFERIMENTO := 3.6

func _slancio_su_contatto() -> float:
	var move := _mossa_corrente
	if move == null or move.passo_avanti <= 0.0 or anim_player == null:
		return 0.0
	if move.contact_times.is_empty():
		return 0.0
	var scala := 1.0
	if model != null:
		scala = model.global_transform.basis.get_scale().x
	if _flat_distance(target) <= SCATTO_DISTANZA_MINIMA * (scala / SCATTO_SCALA_RIFERIMENTO):
		return 0.0

	## Il playhead è in secondi di clip a velocità nativa: gli istanti di
	## contatto sono espressi nella stessa unità, quindi si confrontano diretti.
	var pos : float = anim_player.current_animation_position
	var precedente := move.telegraph
	for c in move.contact_times:
		var contatto := float(c)
		var finestra : float = minf(move.passo_finestra, maxf(contatto - precedente, 0.0))
		precedente = contatto
		if finestra <= 0.001:
			continue
		if pos >= contatto - finestra and pos < contatto:
			## Metri al secondo REALI: la finestra è in tempo di clip, e una
			## clip rallentata la fa durare di più.
			return move.passo_avanti / (finestra / maxf(anim_speed_scale, 0.01))
	return 0.0


## ─── SCHIANTO DELL'ATTERRAGGIO (solo l'Alpha) ───────────────────────────────
##
## L'Alpha è un mini-boss lungo il doppio di un lupo comune e il suo balzo
## caricato è la mossa più pesante che ha: quando ricade deve SENTIRSI. I lupetti
## no — se ogni membro del branco alzasse zolle, a tre lupi in campo il terreno
## sarebbe una nuvola perenne e lo schianto smetterebbe di voler dire "attenzione".
## È la stessa regola di scopo della direzione artistica, applicata agli effetti:
## l'accento conta perché è raro.

## Tinta dei detriti: la terra della Traccia Perduta, che è dove si combatte il
## Branco Guasto. Esposta per non doverla cambiare a codice se il branco compare
## altrove.
@export var detriti_tinta : Color = SchiantoATerra.TERRA_TRACCIA
## Se false, niente detriti neanche per l'Alpha.
@export var detriti_attivi : bool = true

## Lo schianto è già stato consegnato per QUESTO balzo?
var _balzo_schiantato : bool = false


## Chiamata ogni frame di fisica mentre una mossa è in corso.
##
## ⚠️ L'istante giusto NON è `_on_move_released` (il primo contatto della mossa,
## che sul balzo cade su `telegraph` = 0.3s, cioè mentre il lupo è ancora in
## aria). È la FINE DELLA FASE AEREA, `LEAP_AIR_END`, la stessa frazione che già
## governa lo sterzo in volo: quella è l'unica che descrive il momento in cui le
## zampe toccano. Legare il colpo d'occhio a una costante diversa da quella del
## movimento vorrebbe dire vederli scollarsi alla prima ritaratura della clip.
func _controlla_atterraggio_balzo() -> void:
	if _balzo_schiantato or not is_alpha or not detriti_attivi:
		return
	if _leap_move == null or anim_player == null:
		return
	if anim_player.current_animation != _leap_move.anim:
		return
	var len_nativa : float = _anim_len(_leap_move.anim)
	if anim_player.current_animation_position < len_nativa * LEAP_AIR_END:
		return
	_balzo_schiantato = true
	## Un lupo che ricade da un balzo pesa meno di un'onda del Senza Nome ma più
	## di una spadata: 1.2 lo mette nel mezzo.
	SchiantoATerra.sotto(self, 1.2, detriti_tinta)


## L'ululato dell'Alpha.
##
## ⚠️ Parte all'INIZIO della clip, non al richiamo. Sembrerebbe piu' sensato
## farlo scattare a `HOWL_CALL_TIME`, ma il campione ha un arco suo: sale, tiene
## e cala. Misurato, a 2.20 s (il richiamo) e' ancora al 92% del suo picco —
## quindi facendolo partire da zero i due archi COINCIDONO, e la voce e' piena
## proprio quando il muso e' su. Partendo al richiamo si sentirebbe l'attacco
## dell'ululato mentre l'animazione lo sta gia' concludendo.
func _suona_ululato() -> void:
	if is_alpha:
		Suoni.nel_mondo(self, Suoni.ULULATO_ALPHA, 2.0, 0.05)


## Secondi di volo che restano, letti dal PLAYHEAD: la fase aerea è un tratto
## della clip, quindi si misura sulla clip. Zero se non si sta volando.
func _leap_air_remaining() -> float:
	if _leap_move == null or anim_player == null:
		return 0.0
	if anim_player.current_animation != _leap_move.anim:
		return 0.0
	var len_nativa : float = _anim_len(_leap_move.anim)
	var pos : float = anim_player.current_animation_position
	var fine : float = len_nativa * LEAP_AIR_END
	if pos < len_nativa * LEAP_AIR_START or pos >= fine:
		return 0.0
	# Riportato in secondi REALI: è un tempo di volo, non un istante di clip.
	return maxf((fine - pos) / anim_speed_scale, 0.05)


## ─── La voce del Branco Guasto ──────────────────────────────────────────────
## ⚠️ L'ululato NON passa da qui: e' una coreografia sua, agganciata all'inizio
## della clip (vedi `_suona_ululato`). Qui c'e' il resto.
func _voce_ingaggio() -> String:
	return Suoni.LUPO_RINGHIO

func _voce_attacco(move : EnemyMove) -> String:
	## Solo i morsi. Il balzo ha gia' il suo schianto all'atterraggio, e
	## sovrapporgli un morso li farebbe suonare come due mosse insieme.
	if move != null and move.leap_to_target:
		return ""
	return Suoni.LUPO_MORSO


func _on_move_started(move : EnemyMove, _clip_len : float) -> void:
	_leap_move = move if move.leap_to_target else null
	_mossa_corrente = move
	_avanzato_clip = 0.0
	## ⚠️ Si riarma all'INIZIO di ogni mossa, non alla fine di quella prima. Una
	## mossa interrotta (morte, stagger, catena spezzata) può non passare mai da
	## `_on_move_finished`, e un flag rimasto alzato lì significherebbe che il
	## balzo successivo non alza più niente — un difetto che si manifesta una
	## volta ogni tanto ed è impossibile da riprodurre a comando.
	_balzo_schiantato = false

func _on_move_finished(_move : EnemyMove) -> void:
	_leap_move = null
	_mossa_corrente = null

func _clear_move_state() -> void:
	super._clear_move_state()
	_leap_move = null
	_balzo_schiantato = false


# ═══════════════════════════════════════════════════════════════════════════
# Coreografie: ululato
# ═══════════════════════════════════════════════════════════════════════════
## Il BALZO non è più qui: il volo lo gestisce `_attack_motion` leggendo il
## playhead, e il colpo arriva dalla timeline comune all'istante di contatto
## misurato, come per ogni altra mossa. L'ululato invece resta una coreografia
## vera: non colpisce, chiama.

## Vero per la clip dell'ululato, da qualunque sorgente arrivi. Esiste perche'
## il nome va confrontato in QUATTRO punti — chi la esegue, chi non la
## interrompe, chi la esclude dalle mosse ravvicinate — e dimenticarne uno la
## romperebbe in silenzio.
func _e_ululato(nome : String) -> bool:
	return nome == HOWL_ANIM or nome == HOWL_ANIM_LIB


func _execute_special(move : EnemyMove, clip_len : float) -> bool:
	if _e_ululato(move.anim):
		await _run_howl(clip_len)
		return true
	return false


func _run_howl(clip_len : float) -> void:
	_suona_ululato()
	var call_at : float = HOWL_CALL_TIME / anim_speed_scale
	await get_tree().create_timer(call_at).timeout
	if _move_aborted():
		return
	howl_summon.emit()
	await get_tree().create_timer(maxf(clip_len - call_at, 0.05)).timeout


# ═══════════════════════════════════════════════════════════════════════════
# Morte
# ═══════════════════════════════════════════════════════════════════════════

func _on_died() -> void:
	if _state == State.DEAD:
		return
	super._on_died()
	if not is_alpha:
		return
	# L'Alpha è un mini-boss, non una Leggenda: banner "FIEND DEFEATED" viola,
	# non l'oro riservato alle Leggende.
	get_tree().call_group("wolf_pack", "on_ally_died")
	if not mini_boss:
		return
	var ann := get_node_or_null("/root/Announcer")
	if ann and ann.has_method("fiend_defeated"):
		ann.fiend_defeated()


## Un colpo non interrompe un attacco in corso né la fuga.
func _can_react_to_hit() -> bool:
	return not _busy and _state != State.FLEE


# ═══════════════════════════════════════════════════════════════════════════
# Helper
# ═══════════════════════════════════════════════════════════════════════════

## Portata a cui fermarsi: la più corta tra i morsi VERI del move set (balzo e
## ululato non contano — uno serve a chiudere la distanza, l'altro non colpisce).
func _combat_range() -> float:
	var best := 1.6
	if move_set:
		for m in move_set.moves:
			if m and m.min_range <= 0.0 and not m.leap_to_target and not _e_ululato(m.anim):
				best = maxf(best, m.move_range - 0.3)
	return best
