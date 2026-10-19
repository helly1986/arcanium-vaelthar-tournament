extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: il Fante legge l'avversario
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_pressione.gd
##
## Il patto e' questo, e sono quattro promesse separate:
##
##   1. chi picchia di fila lo fa TRINCERARE: smette di attaccare e resta dietro
##      lo scudo;
##   2. chi smette lo fa USCIRE, e il colpo parte subito — e' la slealta';
##   3. una guardia ROTTA azzera tutto: chi si rialza dallo stagger non torna in
##      trincea, mena;
##   4. chi non ha scudo non si trincera MAI (il Fante Spadone, i boss).
##
## ⚠️ La pressione si fa scorrere chiamando `_aggiorna_pressione(delta)` a mano,
## non aspettando davvero due secondi: e' l'unica grandezza in gioco che sia
## governata da un delta e non dall'orologio, quindi la prova e' deterministica
## e dura un decimo di secondo invece di venti.
##
## ⚠️ I colpi di prova hanno potenza 1: con la potenza vera il Fante muore al
## terzo, e un cadavere non si trincera. Non e' un trucco — qui si misura la
## LETTURA, non il danno, e il danno ha gia' il suo cancello (`verifica_guardia`).

const FANTE := "res://arcanium/characters/sylvorn_fante.tscn"
const SPADONE := "res://arcanium/characters/sylvorn_fante_spadone.tscn"

class ColpoFinto extends RefCounted:
	var power : int = 1
	var damage_type : String = "TAGLIO"

var guasti := 0


func _initialize() -> void:
	_prova()


func _prova() -> void:
	await process_frame
	await _si_trincera_e_esce()
	await _la_guardia_rotta_azzera()
	await _senza_scudo_non_si_trincera()
	print("\n%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)


func _nasci(percorso : String) -> Node:
	var n : Node = (load(percorso) as PackedScene).instantiate()
	root.add_child(n)
	await process_frame
	return n


## ⚠️ IL PRIMO CONTROLLO E' CHE IL MECCANISMO ESISTA.
##
## Senza, questo cancello MENTE: provato in negativo su un Fante a cui il
## meccanismo era stato tolto, stampava «PASSATO — 0 problemi». Perche'
## `f.get("_trincerato")` su una proprieta' che non c'e' torna `null`, cioe'
## falso, cioe' «non e' trincerato»: ogni promessa risultava mantenuta da un
## nemico che non sapeva nemmeno cosa fossero. Gli errori di chiamata a funzione
## inesistente finiscono nel log e l'esecuzione tira dritto.
func _c_e_il_meccanismo(f : Node) -> bool:
	var mancano : PackedStringArray = []
	for m in ["_aggiorna_pressione", "_registra_pressione", "_legge_avversario"]:
		if not f.has_method(m):
			mancano.append(m + "()")
	for v in ["_pressione", "_trincerato", "_soglia_su"]:
		if not (v in f):
			mancano.append(v)
	if mancano.is_empty():
		return true
	_guasto("il meccanismo non c'e' proprio: mancano %s" % str(mancano))
	return false


func _si_trincera_e_esce() -> void:
	print("=== sotto pressione si trincera, e uscendo colpisce subito ===")
	var f : Node = await _nasci(FANTE)
	if not _c_e_il_meccanismo(f):
		f.queue_free()
		await process_frame
		return

	if f.get("_trincerato"):
		_guasto("nasce gia' trincerato")
	if f._choose_move(2.0) == null:
		_guasto("da fermo non sa scegliere nessuna mossa: la prova non direbbe niente")
	else:
		print("  ok    da fermo una mossa la sceglie")

	var soglia : float = float(f.get("_soglia_su"))
	var colpi := int(ceil(soglia / f.pressione_per_colpo))
	for i in colpi:
		f.hit(null, ColpoFinto.new())
	f._aggiorna_pressione(0.0)
	print("  %d colpi -> pressione %.2f (soglia di questo Fante %.2f)"
		% [colpi, float(f.get("_pressione")), soglia])

	if not f.get("_trincerato"):
		_guasto("dopo %d colpi di fila NON si trincera" % colpi)
	else:
		print("  ok    si e' trincerato")
	if f._choose_move(2.0) != null:
		_guasto("trincerato sceglie ancora una mossa: attaccherebbe lo stesso")
	else:
		print("  ok    e trincerato non attacca")

	# ⚠️ Lo scudo deve restare SU: se il meccanismo lo abbassasse, «trincerarsi»
	# vorrebbe dire solo «smettere di attaccare», che e' un regalo al giocatore.
	f._aggiorna_guardia()
	if not f.get("_in_guardia") and is_instance_valid(f.target):
		_guasto("trincerato ma con la guardia abbassata")

	f.set("_next_attack", 999999.0)
	await _pausa_e_controlla(f)
	f.queue_free()
	await process_frame


func _pausa_e_controlla(f : Node) -> void:
	var t := 0.0
	var passo := 1.0 / 60.0
	while f.get("_trincerato") and t < 10.0:
		f._aggiorna_pressione(passo)
		t += passo
	if f.get("_trincerato"):
		_guasto("non esce piu' dalla trincea nemmeno dopo dieci secondi di calma")
		return
	print("  ok    esce dalla trincea dopo %.2f s di calma" % t)
	if t < 0.5 or t > 4.0:
		_guasto("la finestra e' fuori misura: %.2f s (attesi fra 0,5 e 4)" % t)
	if float(f.get("_next_attack")) != 0.0:
		_guasto("uscendo NON azzera l'attesa: il colpo non arriva sulla pausa")
	else:
		print("  ok    e uscendo colpisce al primo fotogramma utile")
	await process_frame


func _la_guardia_rotta_azzera() -> void:
	print("\n=== una guardia rotta scioglie la trincea ===")
	var f : Node = await _nasci(FANTE)
	if not _c_e_il_meccanismo(f):
		f.queue_free()
		await process_frame
		return
	for i in 6:
		f.hit(null, ColpoFinto.new())
	f._aggiorna_pressione(0.0)
	if not f.get("_trincerato"):
		_guasto("sei colpi non bastano a trincerarlo")
	f._rompi_guardia()
	if f.get("_trincerato") or float(f.get("_pressione")) > 0.0:
		_guasto("dopo la rottura resta trincerato (pressione %.2f)" % float(f.get("_pressione")))
	else:
		print("  ok    la rottura azzera pressione e trincea")
	f.queue_free()
	await process_frame


func _senza_scudo_non_si_trincera() -> void:
	print("\n=== senza scudo non esiste trincea ===")
	var f : Node = await _nasci(SPADONE)
	if not _c_e_il_meccanismo(f):
		f.queue_free()
		await process_frame
		return
	if f.scudo != null:
		print("  (questo Fante uno scudo ce l'ha: prova saltata)")
		f.queue_free(); await process_frame; return
	for i in 10:
		f.hit(null, ColpoFinto.new())
	f._aggiorna_pressione(0.0)
	if f.get("_trincerato"):
		_guasto("uno spadone senza scudo si e' trincerato: resterebbe fermo a prenderle")
	else:
		print("  ok    dieci colpi e non si trincera (pressione %.2f)" % float(f.get("_pressione")))
	if f._choose_move(2.0) == null:
		_guasto("e per giunta non attacca piu'")
	else:
		print("  ok    e continua ad attaccare")
	f.queue_free()
	await process_frame


func _guasto(msg : String) -> void:
	print("  ROTTO  " + msg)
	guasti += 1
