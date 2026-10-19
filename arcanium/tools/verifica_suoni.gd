extends Node

## CANCELLO DI VERIFICA dell'audio: che ogni suono dichiarato in `Suoni` esista
## davvero su disco e sia caricabile, e che il bus SFX ci sia.
##
## ⚠️ Serve perché il fallimento è SILENZIOSO: `Suoni._stream` su un percorso
## sbagliato emette un warning e restituisce null, quindi il gioco continua
## normalissimo — e semplicemente muto. È il tipo di difetto che si scopre tre
## settimane dopo.

func _ready() -> void:
	var errori := 0
	var bus := AudioServer.get_bus_index(Suoni.BUS)
	if bus < 0:
		push_error("BUS '%s' INESISTENTE: tutti i suoni finirebbero sul Master." % Suoni.BUS)
		errori += 1
	else:
		print("[suoni] bus '%s' trovato all'indice %d" % [Suoni.BUS, bus])

	var lista : Array[String] = [
		Suoni.SCHIANTO_MASSO, Suoni.CROLLO_COLONNA, Suoni.CARICA_ARCANA,
		Suoni.VERATH_SPETTRALE, Suoni.ICE_SHARD, Suoni.MORSA_GELO,
		Suoni.MORSA_GELO_UNA, Suoni.ULULATO_ALPHA, Suoni.CONO_ACCUMULO,
		Suoni.PYRRATH_FRESA,
	]
	## Nemici e fendenti: si passa dalle FUNZIONI, non dalle costanti, cosi' il
	## test copre anche l'indicizzazione (un tipo di danno che cade sulla famiglia
	## sbagliata, o un indice fuori posto, qui si vede).
	lista.append(Suoni.LUPO_RINGHIO)
	lista.append(Suoni.LUPO_MORSO)
	lista.append(Suoni.CONSUMATO_COLPITO)
	lista.append(Suoni.SENZANOME_RUGGITO)
	for a in Suoni.CONSUMATO_ANNUNCI:
		lista.append(a)
	for m in Suoni.CONSUMATO_MORTI:
		lista.append(m)
	for tipo in ["TAGLIO", "PERFORAZIONE", "SCHIANTO", "CRIO"]:
		for pesante in [false, true]:
			lista.append(Suoni.fendente(tipo, pesante))
		for sul_mondo in [false, true]:
			lista.append(Suoni.colpo(tipo, sul_mondo))

	for v in [Suoni.Voce.MASCHILE, Suoni.Voce.FEMMINILE]:
		Suoni.voce = v
		lista.append(Suoni.voce_forte())
		lista.append(Suoni.voce_continua())
		for i in Suoni.LIEVI:
			lista.append("res://audio/SoundFX/player/voce_%s_lieve_%d.wav"
					% ["f" if v == Suoni.Voce.FEMMINILE else "m", i + 1])

	for p in lista:
		if not ResourceLoader.exists(p):
			push_error("MANCA: %s" % p)
			errori += 1
			continue
		var s := load(p)
		if s == null:
			push_error("NON CARICABILE: %s" % p)
			errori += 1
			continue
		var d : float = (s as AudioStream).get_length()
		print("[suoni] ok  %-58s %.2fs" % [p.replace("res://audio/SoundFX/", ""), d])

	## ─── La VOCE segue il sesso del personaggio ─────────────────────────────
	## ⚠️ Si prova per davvero passando da SaveManager, non leggendo `Suoni.voce`:
	## il difetto possibile e' proprio che il collegamento non ci sia.
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		push_error("SaveManager assente: la voce non puo' seguire il personaggio.")
		errori += 1
	else:
		## ⚠️ NON si chiama `begin_new_run` per provare la voce. Quella funzione
		## CANCELLA IL SALVATAGGIO (azzera flag, quest, stat, livello, portafoglio
		## e rimuove il file da disco): usarla in un test distrugge la partita di
		## chi lo lancia. Ci sono cascato una volta.
		## Si scrive il campo e si chiama l'aggancio, che e' esattamente cio' che
		## il test deve verificare — e alla fine si rimette com'era.
		var originale : String = sm.get_gender()
		for coppia in [["female", Suoni.Voce.FEMMINILE], ["male", Suoni.Voce.MASCHILE]]:
			sm.set("_gender", coppia[0])
			sm._applica_voce()
			if Suoni.voce != coppia[1]:
				push_error("voce NON seguita: run '%s' -> Suoni.voce = %d" % [coppia[0], Suoni.voce])
				errori += 1
			else:
				print("[suoni] voce ok: personaggio '%s' -> %s" %
						[coppia[0], "femminile" if coppia[1] == Suoni.Voce.FEMMINILE else "maschile"])

		sm.set("_gender", originale)
		sm._applica_voce()

	## ─── Il conteggio del dolore continuo ───────────────────────────────────
	## Due fonti insieme (fuoco + veleno) devono dare UN lamento, e la prima che
	## finisce non deve spegnerlo.
	Suoni.dolore_continuo_azzera()
	Suoni.dolore_continuo_avvia()
	var v1 = Suoni._dolore_voce
	Suoni.dolore_continuo_avvia()
	if Suoni._dolore_voce != v1:
		push_error("due fonti hanno aperto DUE lamenti invece di uno")
		errori += 1
	Suoni.dolore_continuo_ferma()
	if Suoni._dolore_voce == null:
		push_error("la prima fonte che finisce ha spento il lamento dell'altra")
		errori += 1
	Suoni.dolore_continuo_ferma()
	if Suoni._dolore_voce != null:
		push_error("l'ultima fonte non ha spento il lamento")
		errori += 1
	if errori == 0:
		print("[suoni] dolore continuo ok: 2 fonti = 1 lamento, si spegne solo con l'ultima")

	print("[suoni] === %d suoni controllati, %d errori ===" % [lista.size(), errori])
	get_tree().quit(1 if errori > 0 else 0)
