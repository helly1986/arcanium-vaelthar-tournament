extends SceneTree

## Cancello del SALVATAGGIO DELLA RUN fra un nodo e l'altro (Torneo.to_dict,
## SaveManager, mappa_schermo):
##   1. aprire la mappa scrive il primo salvataggio e «Continue» riporta lei;
##   2. ogni passo della run si salva: dopo due nodi completati e un riposo il
##      file sul disco li ha;
##   3. ricaricando, la run torna com'era: mappa, sentiero, nodo aperto,
##      sconfitte, miglioramenti, rivali battuti, Arcanium, casata;
##   4. una run finita cancella il salvataggio (niente «Continue»).
##
## ⚠️ Scrive e cancella user://arcanium_save.cfg: va lanciato SOLO con un
## APPDATA isolato.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_salvataggio_run.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 4

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	if OS.get_user_data_dir().contains("Roaming"):
		push_error("APPDATA non isolato: questo cancello cancella il salvataggio. Mi fermo.")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var salva : Node = root.get_node("SaveManager")
	var torneo : Node = root.get_node("Torneo")
	var banca : Node = root.get_node("CrystalBank")
	salva.begin_new_run("vorrkai", "female")
	torneo.inizia(33)

	## 1.
	var m : Node = load("res://arcanium/ui/mappa/mappa_schermo.tscn").instantiate()
	root.add_child(m)
	await process_frame
	_ok(salva.has_save() and salva.get_resume_scene() == salva.MAPPA_RUN,
			"la mappa scrive il primo salvataggio, «Continue» porta a %s" % salva.get_resume_scene())
	root.remove_child(m)
	m.free()

	## 2.
	for k in 2:
		torneo.scegli(torneo.raggiungibili()[0])
		torneo.completa()
	torneo.affilature = 2
	torneo.salute_bonus = 6
	torneo.batti_rivale("aethon")
	banca.add(123)
	torneo.scegli(torneo.raggiungibili()[0])
	torneo.registra_sconfitta()
	banca.add(77)
	var atteso : Dictionary = torneo.to_dict()
	var cristalli : int = banca.crystals
	var cfg := ConfigFile.new()
	cfg.load(salva.SAVE_PATH)
	var su_disco : Dictionary = cfg.get_value("torneo", "data", {})
	_ok((su_disco.get("completati", []) as Array).size() == 2 and su_disco.get("nodo_corrente", "") == atteso["nodo_corrente"]
			and int(su_disco.get("sconfitte", 0)) == 1,
			"sul disco: %d nodi fatti, nodo aperto %s, sconfitte %d" % [(su_disco.get("completati", []) as Array).size(),
			su_disco.get("nodo_corrente", ""), int(su_disco.get("sconfitte", 0))])

	## 3. Come alla riapertura del gioco: la memoria azzerata (senza segnali,
	## che salverebbero il vuoto), poi il ripristino dal disco.
	salva.persist_state()
	torneo.in_corso = false
	torneo.mappa = {}
	torneo.completati = []
	torneo.nodo_corrente = ""
	torneo.sconfitte = 0
	torneo.affilature = 0
	torneo.salute_bonus = 0
	torneo.rivali_battuti = []
	banca.crystals = 0
	salva._house = "dawnkeep"
	salva._ready()
	salva._restore_state()
	await process_frame
	var ripreso : Dictionary = torneo.to_dict()
	_ok(var_to_str(ripreso) == var_to_str(atteso) and banca.crystals == cristalli and salva.get_house() == "vorrkai",
			"ricaricata: run identica %s, ◆ %d, casata %s" % [var_to_str(ripreso) == var_to_str(atteso), banca.crystals, salva.get_house()])

	## 4.
	torneo.termina()
	await process_frame
	_ok(not salva.has_save(), "run finita: salvataggio cancellato (has_save=%s)" % salva.has_save())

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
