extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: la Legione Testuggine nelle mani del PLAYER
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_testuggine_player.gd
##
## Nove promesse, e ognuna, se salta, produce un difetto DIVERSO:
##
##   1. la clip e' nella libreria del player, sulle SUE ossa     -> altrimenti
##      il braccio cerca un rig che non c'e'
##   2. lo slot e' in cima all'albero e filtrato sul braccio armato -> altrimenti
##      lo scudo cade o le gambe si fermano
##   3. senza tomo non esiste                                     -> altrimenti
##      e' un attacco in piu' regalato
##   4. senza guardia non parte                                   -> altrimenti
##      e' un affondo gratis, non la mossa della trincea
##   5. NON alza `busy` e NON riapre `parry_active`               -> altrimenti
##      lo scudo cade / parate infinite
##   6. costa stamina, e mette il cooldown                        -> altrimenti
##      si spamma
##   7. la lama si accende nella finestra, con la portata corta,
##      e si spegne alla fine ripristinando la sonda              -> altrimenti
##      colpisce a 2,6 m, o resta accesa
##   8. il contatto porta il danno della TECNICA (frazione, perforazione)
##   9. un colpo subito interrompe il gesto e spegne la lama
##  10. l'INPUT: scudo su + colpo leggero = tecnica e nessun fendente in coda;
##      scudo giu' + colpo leggero = fendente come sempre        -> altrimenti
##      la guardia si apre proprio mentre la si tiene chiusa
##
## ⚠️ In headless lo SCHELETRO non si muove: qui si prova la logica, non la
## posa. La portata sul corpo del player si misura con un render vero.

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"
const TECNICA := "res://arcanium/resources/tecniche_guerra/legione_testuggine.tres"

var guasti := 0
var _fatto := false
var _finite : Array = []
var _rifiuti : Array = []
var _colpi : Array = []


func _sia(condizione : bool, cosa : String) -> void:
	if condizione:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


## Bersaglio finto: registra cosa gli arriva.
class Manichino extends Node3D:
	var ricevuti : Array = []
	func hit(_chi, info) -> void:
		ricevuti.append(info)


func _process(_dt : float) -> bool:
	if not _fatto:
		_fatto = true
		_prova()
	return false


func _prova() -> void:
	var flags := root.get_node_or_null("PlayerFlags")
	_sia(flags != null, "l'autoload PlayerFlags c'e'")
	if flags == null:
		quit(1)
		return
	var tecnica : Resource = load(TECNICA)
	var flag : String = str(tecnica.get("unlock_flag"))
	## Si parte SENZA la tecnica appresa. `clear` emette `changed` (autosave):
	## qui non c'e' un salvataggio dell'utente da proteggere perche' non si
	## tocca nulla che la partita salvi, a parte questo flag che si rimette.
	var era_appresa : bool = flags.has(flag)
	flags.clear(flag)

	var p : Node = (load(PLAYER) as PackedScene).instantiate()
	root.add_child(p)
	await process_frame
	await process_frame

	var caster : Node = p.get_node_or_null("TecnicaGuerraCaster")
	_sia(caster != null, "il player ha il TecnicaGuerraCaster")
	if caster == null:
		_fine(p, flags, flag, era_appresa)
		return
	caster.finita.connect(func(t): _finite.append(t))
	caster.rifiutata.connect(func(m): _rifiuti.append(m))

	print()
	print("=== 1. la clip e' del player ===")
	var ap : AnimationPlayer = p.find_child("AnimationPlayer", true, false)
	var nome := "TecnicheLib/legione_testuggine"
	_sia(ap != null and ap.has_animation(nome), "esiste '%s'" % nome)
	if ap != null and ap.has_animation(nome):
		var a := ap.get_animation(nome)
		var estranee := 0
		var destre := 0
		for i in a.get_track_count():
			var path := str(a.track_get_path(i))
			if not path.begins_with("%GeneralSkeleton:"):
				estranee += 1
			if path.find(":Right") >= 0:
				destre += 1
		_sia(estranee == 0, "tutte le %d tracce stanno su %%GeneralSkeleton" % a.get_track_count())
		_sia(destre >= 4, "e il braccio destro c'e' (%d tracce Right*)" % destre)
		_sia(absf(a.length - 1.30) < 0.05, "durata 1,30 s (%.2f)" % a.length)

	print()
	print("=== 2. lo slot in cima all'albero, filtrato sul braccio armato ===")
	var albero : AnimationTree = p.get_node_or_null("AnimStateTree")
	var radice := albero.tree_root as AnimationNodeBlendTree if albero else null
	_sia(radice != null and radice.has_node("TecnicaGuerra") and radice.has_node("TecnicaGuerraAnim"),
		"i due nodi ci sono")
	if radice != null and radice.has_node("TecnicaGuerra"):
		var conn = radice.get("node_connections")
		var alimenta_output := ""
		var base_strato := ""
		var i := 0
		while conn is Array and i + 2 < conn.size():
			if str(conn[i]) == "output" and int(conn[i + 1]) == 0:
				alimenta_output = str(conn[i + 2])
			if str(conn[i]) == "TecnicaGuerra" and int(conn[i + 1]) == 0:
				base_strato = str(conn[i + 2])
			i += 3
		_sia(alimenta_output == "TecnicaGuerra", "`output` e' alimentato dallo strato (%s)" % alimenta_output)
		_sia(base_strato == "Summon", "e lo strato prende come base cio' che prima alimentava `output` (%s)" % base_strato)

	print()
	print("=== 3. senza tomo non esiste ===")
	_sia(caster.tecnica_di_guardia() == null, "nessuna tecnica di guardia")
	_rifiuti.clear()
	_sia(not caster.lancia(), "lancia() rifiuta")
	_sia(_rifiuti == ["nessuna_tecnica"], "col motivo 'nessuna_tecnica' (%s)" % str(_rifiuti))

	print()
	print("=== 4. appresa ma senza guardia non parte ===")
	flags.set_flag(flag)
	_sia(caster.tecnica_di_guardia() == tecnica, "adesso la tecnica di guardia e' la Testuggine")
	p.guarding = false
	_rifiuti.clear()
	_sia(not caster.lancia(), "lancia() rifiuta")
	_sia(_rifiuti == ["senza_guardia"], "col motivo 'senza_guardia' (%s)" % str(_rifiuti))

	print()
	print("=== 5/6. in guardia parte: niente busy, niente parata, stamina e cooldown ===")
	var vitals : Node = p.get("vitals")
	var stamina_prima : float = float(vitals.stamina) if vitals else -1.0
	## La guardia si alza A MANO, senza `start_guard()`: cosi' `parry_active`
	## parte FALSO e se dopo il lancio e' vero, e' stata la tecnica a riaprirla.
	p.guarding = true
	p.parry_active = false
	p.busy = false
	_sia(caster.lancia(), "lancia() parte")
	_sia(caster.in_corso() == tecnica, "e la tecnica e' in corso")
	_sia(p.tecnica_in_corso == tecnica, "il player sa quale tecnica sta facendo")
	_sia(not p.busy, "`busy` e' rimasto falso (lo scudo non cade)")
	_sia(not p.parry_active, "`parry_active` e' rimasto falso (niente parate rinfrescate)")
	_sia(p.guarding, "e la guardia e' ancora su")
	if vitals:
		_sia(absf((stamina_prima - float(vitals.stamina)) - float(tecnica.get("costo_stamina"))) < 0.01,
			"stamina spesa: %.0f -> %.0f" % [stamina_prima, float(vitals.stamina)])
	_rifiuti.clear()
	_sia(not caster.lancia() and _rifiuti == ["gia_in_corso"], "un secondo lancio e' rifiutato: 'gia_in_corso'")
	var uno : AnimationNodeOneShot = radice.get_node("TecnicaGuerra") if radice else null
	if uno != null:
		var f := uno.filters
		var solo_destre := true
		for path in f:
			if str(path).find(":Right") < 0:
				solo_destre = false
		_sia(uno.filter_enabled and f.size() >= 4 and solo_destre,
			"il filtro e' SOLO il braccio destro (%d ossa)" % f.size())
		var clip_nodo : AnimationNodeAnimation = radice.get_node("TecnicaGuerraAnim")
		_sia(str(clip_nodo.animation) == nome, "lo slot suona '%s'" % str(clip_nodo.animation))

	print()
	print("=== 7/8. la finestra: lama accesa, portata corta, danno della tecnica ===")
	var ws : Node = p.get("weapon_system")
	var arma = ws.current_equipment if ws else null
	_sia(arma != null, "c'e' un'arma in mano")
	var portata_riposo : float = float(ws.proximity_cone_range) if ws else -1.0
	var manichino := Manichino.new()
	manichino.add_to_group("targets")
	root.add_child(manichino)
	## Un metro davanti al player, lungo il suo +Z (e' il forward della sonda).
	manichino.global_position = p.global_position + p.global_transform.basis.z * 1.0
	var durata : float = float(caster.get("_durata"))
	_sia(durata > 1.0, "durata del gesto misurata dalla clip (%.2f s)" % durata)
	## ⚠️ Si aspetta in TEMPO DI FISICA, non con un timer a muro: la finestra
	## la muove `_physics_process`, e in un processo che sta anche scrivendo
	## l'autosave la fisica resta indietro sull'orologio (misurato: _t=0,45 a
	## 0,585 s di muro). Un timer diceva "e' a meta' gesto" quando non lo era.
	await _fino_a_fisica(caster, durata * 0.55)
	_sia(arma != null and arma.monitoring, "a meta' gesto la lama monitora")
	_sia(ws != null and absf(float(ws.proximity_cone_range) - float(tecnica.get("portata"))) < 0.01,
		"con la sonda al tetto della portata (%.2f m)" % float(ws.proximity_cone_range))
	## La sonda di prossimita' gira in _physics_process dell'EquipmentSystem: un
	## giro a mano basta a farle vedere il manichino.
	if ws != null:
		ws._physics_process(0.016)
	_sia(manichino.ricevuti.size() == 1, "il manichino e' stato colpito una volta (%d)" % manichino.ricevuti.size())
	if manichino.ricevuti.size() == 1 and arma != null:
		var info = manichino.ricevuti[0]
		var base : int = int(arma.equipment_info.power)
		var atteso : int = maxi(1, int(round(base * float(tecnica.get("danno_moltiplicatore")))))
		_sia(int(info.power) == atteso, "col danno della tecnica: %d (arma %d x %.2f)" % [int(info.power), base, float(tecnica.get("danno_moltiplicatore"))])
		_sia(str(info.damage_type) == str(tecnica.get("tipo_danno")), "e il tipo di danno della tecnica (%s)" % str(info.damage_type))
		_sia(info != arma.equipment_info, "su una COPIA della risorsa dell'arma, non sull'originale")
	await _fino_a_fine(caster, durata * 2.0)
	_sia(arma != null and not arma.monitoring, "a gesto finito la lama e' spenta")
	_sia(ws != null and absf(float(ws.proximity_cone_range) - portata_riposo) < 0.01,
		"e la sonda e' tornata a %.2f m" % float(ws.proximity_cone_range))
	_sia(caster.in_corso() == null and p.tecnica_in_corso == null, "la tecnica non e' piu' in corso")
	_sia(_finite.size() == 1, "`finita` emesso una volta")
	_rifiuti.clear()
	_sia(not caster.lancia() and _rifiuti == ["cooldown"], "e subito dopo si e' in cooldown")

	print()
	print("=== 9. un colpo subito interrompe il gesto ===")
	caster.set("_cooldown_fino", {})
	if vitals:
		vitals.stamina = vitals.max_stamina
	_sia(caster.lancia(), "riparte")
	await _fino_a_fisica(caster, durata * 0.55)
	_sia(arma != null and arma.monitoring, "lama accesa")
	p.hurt_started.emit()
	await process_frame
	_sia(caster.in_corso() == null, "dopo `hurt_started` la tecnica e' chiusa")
	_sia(arma != null and not arma.monitoring, "e la lama e' spenta")
	_sia(ws != null and absf(float(ws.proximity_cone_range) - portata_riposo) < 0.01, "e la sonda e' tornata a riposo")

	print()
	print("=== 10. l'input: decide la guardia ===")
	await _fino_a_fine(caster, durata * 2.0)
	caster.set("_cooldown_fino", {})
	if vitals:
		vitals.stamina = vitals.max_stamina
	var colpo := InputEventAction.new()
	colpo.action = "use_weapon_light"
	colpo.pressed = true
	## Scudo su: il colpo leggero e' la Testuggine, e NON finisce in coda come
	## fendente (che aprirebbe la guardia).
	p.guarding = true
	p.set("_buffered_attack", false)
	p._input(colpo)
	_sia(caster.in_corso() == tecnica, "scudo su + colpo leggero -> parte la Testuggine")
	_sia(not bool(p.get("_buffered_attack")), "e nessun fendente in coda")
	## Ancora in corso: un secondo click viene rifiutato ma CONSUMATO — niente
	## fendente di ripiego.
	p.set("_buffered_attack", false)
	p._input(colpo)
	_sia(not bool(p.get("_buffered_attack")), "un secondo click durante il gesto non mette in coda un fendente")
	await _fino_a_fine(caster, durata * 2.0)
	## Scudo giu': il colpo leggero e' un fendente, come sempre.
	p.guarding = false
	p.set("_buffered_attack", false)
	p._input(colpo)
	_sia(caster.in_corso() == null, "scudo giu' + colpo leggero -> nessuna Testuggine")
	_sia(bool(p.get("_buffered_attack")), "e il fendente va in coda come sempre")
	p.set("_buffered_attack", false)

	manichino.queue_free()
	_fine(p, flags, flag, era_appresa)


## Aspetta finche' il tempo del gesto (`_t`, che avanza con la fisica) non ha
## raggiunto `t`. Tetto di 600 frame per non restare appesi se il gesto chiude.
func _fino_a_fisica(caster : Node, t : float) -> void:
	for _i in 600:
		if float(caster.get("_t")) >= t or caster.in_corso() == null:
			return
		await physics_frame


func _fino_a_fine(caster : Node, tetto_s : float) -> void:
	var frame := int(ceil(tetto_s * 60.0)) + 30
	for _i in frame:
		if caster.in_corso() == null:
			## Un frame in piu': `_chiudi` e' gia' passato, ma il ripristino
			## della sonda e la chiusura della lama vanno lasciati assestare.
			await physics_frame
			return
		await physics_frame


func _fine(p : Node, flags : Node, flag : String, era_appresa : bool) -> void:
	if era_appresa:
		flags.set_flag(flag)
	else:
		flags.clear(flag)
	p.queue_free()
	await process_frame
	print()
	print("%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)
