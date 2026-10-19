extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: una mossa a DUE colpi colpisce DUE volte
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_finestre_combo.gd
##
## La combo dello spadone (`S2`, sword_th_combo_01) e' un fendente e poi un gran
## colpo dall'alto. Ci sono DUE strade con cui un umanoide consegna il danno, e
## la combo deve reggere su entrambe:
##
##   A. la TIMELINE (i Fanti oggi: nessuna `blade` assegnata) — un `_apply_hit`
##      per contatto misurato. Promessa: due contatti, a 1,05 e 2,83 s, e il
##      bersaglio davanti viene colpito due volte.
##   B. la LAMA FISICA (il Senza Nome, e chi verra') — la hitbox ha un dedup
##      "un colpo per swing", quindi la mossa deve armare DUE finestre prese
##      dalla tabella, accendere la lama solo dentro, spegnerla fra le due e
##      RIACCENDERLA azzerando il dedup. Con l'unione di prima il secondo
##      colpo andava a vuoto su chi aveva preso il primo, e la lama restava
##      viva per tutto il carico sopra la testa.
##
## Lo spadone non ha l'AnimationTree ne' una `blade`: per la strada B gliene
## si assegna una finta nel test. La clip si manda avanti a mano
## (`AnimationPlayer.advance`), che gira anche in headless.

const FANTE := "res://arcanium/characters/sylvorn_fante_spadone.tscn"
const MOSSA := "S2"
const PASSO := 1.0 / 60.0

var guasti := 0
## Il tempo del giro in corso: le lambda di GDScript catturano le locali PER
## VALORE, e un orologio `func(): return t` segna sempre zero.
var _t := 0.0


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


## Bersaglio finto: registra QUANDO viene colpito.
class Manichino extends Node3D:
	var colpi : Array = []
	var orologio : Callable
	func hit(_chi, _mossa) -> void:
		colpi.append(orologio.call())


func _initialize() -> void:
	_prova()


func _prova() -> void:
	await process_frame
	var f : Node3D = (load(FANTE) as PackedScene).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame
	f.set_physics_process(false)

	var m = f.move_set.find_move(MOSSA)
	_sia(m != null, "lo spadone ha la mossa %s" % MOSSA)
	if m == null:
		_fine(f)
		return
	print("=== %s — %s (%s) ===" % [m.id, m.name, m.anim])
	var ap : AnimationPlayer = f.anim_player
	var durata : float = f._anim_len(m.anim)
	_sia(absf(durata - 3.33) < 0.05, "la clip dura 3,33 s (%.2f)" % durata)

	# ─── A. la timeline: due contatti, due colpi ────────────────────────────
	print()
	print("=== A. timeline (i Fanti oggi): due contatti, due colpi ===")
	var contatti : PackedFloat32Array = f._contact_times(m)
	_sia(contatti.size() == 2, "la mossa ha due contatti dalla tabella (%s)" % str(contatti))
	if contatti.size() == 2:
		_sia(absf(contatti[0] - 1.05) < 0.02 and absf(contatti[1] - 2.83) < 0.02,
			"a 1,05 (fendente) e 2,83 (gran colpo)")
	var bersaglio := Manichino.new()
	bersaglio.add_to_group("targets")
	root.add_child(bersaglio)
	bersaglio.global_position = f.global_position + f.global_transform.basis.z * 1.5
	f.target = bersaglio
	_t = 0.0
	bersaglio.orologio = func(): return _t
	f._play(f.idle_anim, true)
	f._begin_move(m)
	f.set("_pending_contacts", contatti.duplicate())
	f.set("_released_this_move", false)
	while _t < durata + 0.1:
		ap.advance(PASSO)
		_t += PASSO
		f._advance_attack_timeline()
	_sia(bersaglio.colpi.size() == 2, "il manichino davanti e' stato colpito due volte (%d)" % bersaglio.colpi.size())
	if bersaglio.colpi.size() == 2:
		_sia(absf(bersaglio.colpi[0] - 1.05) < 0.05 and absf(bersaglio.colpi[1] - 2.83) < 0.05,
			"agli istanti misurati (%.2f, %.2f)" % [bersaglio.colpi[0], bersaglio.colpi[1]])
	f._clear_move_state()
	ap.stop()

	# ─── B. la lama fisica: due finestre, due accensioni ────────────────────
	print()
	print("=== B. lama fisica (Senza Nome e futuri): due finestre ===")
	var lama := Area3D.new()
	lama.name = "LamaFinta"
	lama.monitoring = false
	f.add_child(lama)
	f.blade = lama
	var lib = f._timing()
	var attese : Array = lib.windows_for(m.anim, f.weapon_window_lead, f.weapon_window_trail) if lib else []
	_sia(attese.size() == 2, "la tabella misurata ha DUE finestre per la clip (%d)" % attese.size())

	f._play(f.idle_anim, true)
	f._begin_move(m)
	var finestre : Array = f.get("_finestre")
	_sia(finestre.size() == 2, "la mossa ha armato due finestre (%d)" % finestre.size())
	if finestre.size() == 2:
		print("        %.2f-%.2f  e  %.2f-%.2f" % [finestre[0].x, finestre[0].y, finestre[1].x, finestre[1].y])
		_sia(finestre[1].x > finestre[0].y + 0.5, "con un vuoto fra le due (il carico del gran colpo)")
	_sia(f._armed_hitbox == lama, "e la lama da accendere")

	var aperture := 0
	var chiusure := 0
	var accesa_prima := false
	var fuori_ma_accesa := 0
	var dedup_azzerato := false
	_t = 0.0
	while _t < durata + 0.2:
		ap.advance(PASSO)
		_t += PASSO
		f._update_weapon_window()
		var pos : float = f._clip_pos()
		var accesa : bool = f._active_hitbox != null
		var dentro := false
		for w in finestre:
			if pos >= w.x - PASSO and pos <= w.y + PASSO:
				dentro = true
		if accesa and not dentro:
			fuori_ma_accesa += 1
		if accesa and not accesa_prima:
			aperture += 1
			if aperture == 2:
				dedup_azzerato = not bool(f.get("_hit_done"))
		if accesa_prima and not accesa:
			chiusure += 1
		if accesa and aperture == 1 and not bool(f.get("_hit_done")):
			## Simula un colpo consegnato nella PRIMA finestra.
			f.set("_hit_done", true)
		accesa_prima = accesa
	_sia(aperture == 2, "la lama si e' accesa due volte (%d)" % aperture)
	_sia(chiusure == 2, "e spenta due volte (%d)" % chiusure)
	_sia(fuori_ma_accesa == 0, "mai accesa fuori dalle finestre (%d frame)" % fuori_ma_accesa)
	_sia(dedup_azzerato, "alla seconda apertura `_hit_done` era azzerato: il secondo colpo puo' entrare")

	f._clear_move_state()
	_sia((f.get("_finestre") as Array).is_empty(), "a mossa finita le finestre sono sgombre")

	print()
	print("=== C. l'IA la sceglie davvero ===")
	## Un moveset puo' essere perfetto e la mossa non partire mai: la combo e'
	## stata un mese nel gruppo "S", che `eligible()` apre solo in fase 2 — e la
	## fase 2 e' del boss. Qui si interroga la scelta vera, a distanza da mischia,
	## con i cooldown azzerati a ogni giro.
	var scelte := {}
	for _i in 300:
		(f.get("_cooldown_until") as Dictionary).clear()
		f.set("_last_move", "")
		f.set("_second_last", "")
		var m2 : Resource = f._choose_move(2.4)
		var id_ : String = m2.id if m2 != null else "-"
		scelte[id_] = int(scelte.get(id_, 0)) + 1
	var quota : float = float(scelte.get(MOSSA, 0)) / 300.0
	_sia(quota > 0.15, "a 2,4 m la combo esce nel %.0f%% delle scelte (%s)" % [quota * 100.0, str(scelte)])
	_sia(not scelte.has("-"), "e a quella distanza c'e' sempre qualcosa da fare")
	bersaglio.queue_free()
	_fine(f)


func _fine(f : Node) -> void:
	f.queue_free()
	await process_frame
	print("\n%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)
