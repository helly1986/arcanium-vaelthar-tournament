extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: le mosse A STRATO, e la Legione Testuggine
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_strato.gd
##
## Una mossa a strato e' un gesto che NON prende possesso del corpo: la clip si
## mescola sopra, filtrata su una catena d'ossa sola, e le gambe continuano a
## camminare mentre il braccio colpisce. La Testuggine e' la prima: un affondo
## che passa SOPRA lo scudo senza farlo cadere.
##
## Sono cinque promesse, e ognuna, se salta, produce un difetto DIVERSO:
##
##   1. senza guardia la mossa non esiste       -> altrimenti e' un attacco in piu'
##   2. da trincerato invece SI'                -> altrimenti la trincea resta passiva
##   3. non fa cadere la guardia                -> altrimenti cancella la propria ragione
##   4. non sostituisce la clip del corpo       -> altrimenti le gambe si fermano
##   5. il colpo lo consegna il playhead DELLO  -> altrimenti gli istanti di contatto
##      STRATO, non quello del corpo               cadono su una clip che non c'entra
##
## ⚠️ Il primo controllo e' che il meccanismo ESISTA: `get()` su una proprieta'
## assente torna `null`, cioe' falso, e un nemico che non sa cosa sia uno strato
## passerebbe tutte le promesse a vuoto. E' gia' successo su `verifica_pressione`.

const FANTE := "res://arcanium/characters/sylvorn_fante.tscn"
const MOSSA := "T1"

var guasti := 0


func _initialize() -> void:
	_prova()


func _prova() -> void:
	await process_frame
	var f : Node = (load(FANTE) as PackedScene).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame

	if not _c_e_il_meccanismo(f):
		print("\nFALLITO — %d problemi" % guasti)
		quit(1)
		return

	var m = f.move_set.find_move(MOSSA)
	if m == null:
		_guasto("il moveset non ha la mossa %s" % MOSSA)
		print("\nFALLITO — %d problemi" % guasti)
		quit(1)
		return
	print("=== %s — %s ===" % [m.id, m.name])
	print("  clip %s | strato=%s | solo_in_guardia=%s" % [m.anim, str(m.strato), str(m.solo_in_guardia)])
	if not m.strato:
		_guasto("la mossa non e' dichiarata a strato")
	if not m.solo_in_guardia:
		_guasto("la mossa non e' dichiarata solo_in_guardia")

	# ─── 1. senza guardia non esiste ────────────────────────────────────────
	f.set("_in_guardia", false)
	if f._move_is_usable(m):
		_guasto("senza guardia la Testuggine risulta utilizzabile")
	else:
		print("  ok    senza guardia non e' utilizzabile")

	# ─── 2. da trincerato SI' ───────────────────────────────────────────────
	f.set("_in_guardia", true)
	f.set("_trincerato", true)
	if not f._move_is_usable(m):
		_guasto("da trincerato la Testuggine NON passa: la trincea resta un bersaglio fermo")
	else:
		print("  ok    da trincerato passa (ed e' l'unica)")
	var normale = f.move_set.find_move("F1")
	if normale != null and f._move_is_usable(normale):
		_guasto("da trincerato passa anche una mossa normale")
	f.set("_trincerato", false)

	# ─── 3/4/5. il gesto non prende possesso del corpo ──────────────────────
	## ⚠️ Il ciclo di fisica va SPENTO, o non si misura la mossa: senza bersaglio
	## l'AI chiama `_go_idle()` a ogni frame e rimette l'idle sul corpo. Il primo
	## giro di questo cancello dava «la mossa ha sostituito la clip del corpo»
	## per quel motivo — cioe' accusava lo strato di una cosa fatta dall'AI.
	f.set_physics_process(false)
	f._play(f.walk_anim, true)
	var corpo_prima : String = str(f.get("_current_anim"))
	f._begin_move(m)
	await process_frame
	await process_frame

	print("  corpo prima: %s | dopo: %s" % [corpo_prima, str(f.get("_current_anim"))])
	if str(f.get("_current_anim")) != corpo_prima:
		_guasto("la mossa ha SOSTITUITO la clip del corpo (%s -> %s): le gambe si fermano"
			% [corpo_prima, str(f.get("_current_anim"))])
	else:
		print("  ok    il corpo continua a camminare")

	if str(f.get("_strato_attivo")) != m.anim:
		_guasto("lo strato non porta la clip della mossa (%s)" % str(f.get("_strato_attivo")))
	else:
		print("  ok    lo strato porta %s" % m.anim)

	## ⚠️ La guardia si ricalcola: non basta che il flag sia rimasto, deve
	## sopravvivere al giro di `_aggiorna_guardia`, che e' quello che in gioco
	## la fa cadere quando il nemico e' `_busy`.
	f.target = f
	f._aggiorna_guardia()
	if not f.get("_in_guardia"):
		_guasto("la mossa ha fatto CADERE la guardia: cancella la propria ragione d'esistere")
	else:
		print("  ok    la guardia resta alzata durante il gesto")

	if f._clip_corrente() != m.anim:
		_guasto("`_clip_corrente()` dice %s invece della clip dello strato: gli istanti di "
			% f._clip_corrente() + "contatto cadrebbero su un'altra clip")
	else:
		print("  ok    il colpo lo consegna il playhead dello strato")

	# ─── e a mossa finita lo strato si spegne ───────────────────────────────
	f._clear_move_state()
	if str(f.get("_strato_attivo")) != "":
		_guasto("lo strato resta acceso dopo che la mossa e' stata annullata")
	else:
		print("  ok    annullando la mossa lo strato si spegne")

	f.queue_free()
	await process_frame
	print("\n%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)


func _c_e_il_meccanismo(f : Node) -> bool:
	var mancano : PackedStringArray = []
	for m in ["_e_a_strato", "_rifiltra_strato", "_ossa_da"]:
		if not f.has_method(m):
			mancano.append(m + "()")
	if not ("_strato_attivo" in f):
		mancano.append("_strato_attivo")
	if f.get("_albero") == null:
		mancano.append("l'AnimationTree (usa_anim_tree spento?)")
	if mancano.is_empty():
		return true
	_guasto("il meccanismo non c'e' proprio: mancano %s" % str(mancano))
	return false


func _guasto(msg : String) -> void:
	print("  ROTTO  " + msg)
	guasti += 1
