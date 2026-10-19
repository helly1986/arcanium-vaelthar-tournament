extends SceneTree

## Prova la salita di livello ai Coni: curva dei costi, spesa effettiva sul
## portafoglio, punti applicati alla Marca giusta e sopravvivenza al
## salvataggio.
##
## La parte che conta e' che il livello si PAGHI: un progresso che si prende i
## punti senza togliere i cristalli non e' un costo, e un costo che non morde
## non e' souls-like.
##
## Uso: godot --headless --script arcanium/tools/verifica_salita_livello.gd

const Marche := preload("res://arcanium/resources/marche_stats.gd")


func _init() -> void:
	await process_frame
	var esito := 0

	var prog := root.get_node_or_null("/root/MarcheProgression")
	var banca := root.get_node_or_null("/root/CrystalBank")
	if prog == null or banca == null:
		push_error("MarcheProgression o CrystalBank non registrati come autoload")
		quit(1)
		return

	prog.reset()
	banca.reset()

	## ─── la curva ───────────────────────────────────────────────────────────
	var massimo: int = prog.LIVELLO_MASSIMO
	print("livello massimo: %d  (7 Marche da %d a %d)" % [massimo, prog.MARCA_PARTENZA, prog.MARCA_MASSIMA])
	print("livello -> costo del passo successivo    (cumulato da L1)")
	var cumulato := 0
	for l in range(1, massimo):
		cumulato += prog.costo_per_livello(l)
		if l in [1, 2, 10, 50, 100, 300, massimo - 1]:
			print("  L%-4d %9s %18s" % [l, _mille(prog.costo_per_livello(l)), _mille(cumulato)])
	print("  totale per cappare tutte e 7 le Marche: %s Arcanium" % _mille(cumulato))

	esito = _controlla("il primo livello costa 100", prog.costo_per_livello(1) == 100, esito)
	esito = _controlla("il secondo costa 125", prog.costo_per_livello(2) == 125, esito)
	esito = _controlla("la curva e' sempre crescente", _crescente(prog, massimo), esito)
	esito = _controlla("il livello massimo e' 624", massimo == 624, esito)
	## Il cap e' pensato su tre cicli (NG0, NG+, NG+2): ~10 milioni per giro.
	## Se sfonda i 40 milioni non e' piu' un traguardo da completista, e' farming.
	esito = _controlla("cappare tutto sta sotto i 40 milioni", cumulato < 40000000, esito)
	esito = _controlla("l'ultimo passo resta a sei cifre",
			prog.costo_per_livello(massimo - 1) < 1000000, esito)

	## ─── la spesa ───────────────────────────────────────────────────────────
	esito = _controlla("senza cristalli non si sale", not prog.sali(Marche.Marca.VOL), esito)
	esito = _controlla("il livello e' rimasto 1", prog.livello == 1, esito)

	banca.add(250)
	esito = _controlla("con 250 si puo' salire", prog.puo_salire(), esito)
	esito = _controlla("la salita riesce", prog.sali(Marche.Marca.VOL), esito)
	esito = _controlla("il livello e' 2", prog.livello == 2, esito)
	esito = _controlla("ha pagato 100 (restano 150)", banca.crystals == 150, esito)
	esito = _controlla("il punto e' andato su VOL", prog.punti_spesi(Marche.Marca.VOL) == 1, esito)
	esito = _controlla("le altre Marche sono intatte",
			prog.punti_spesi(Marche.Marca.CON) == 0, esito)

	## il secondo livello costa 125: con 150 ci sta, e poi si resta a secco
	esito = _controlla("la seconda salita riesce", prog.sali(Marche.Marca.RES), esito)
	esito = _controlla("ha pagato 125 (restano 25)", banca.crystals == 25, esito)
	esito = _controlla("a 25 cristalli non si sale piu'", not prog.puo_salire(), esito)

	## ─── i punti finiscono sulle Marche vere ────────────────────────────────
	var stats := MarcheStats.new()
	prog.applica_a(stats)
	esito = _controlla("applica_a somma il punto di VOL (10 -> 11)",
			stats.get_marca(Marche.Marca.VOL) == 11, esito)
	esito = _controlla("applica_a somma il punto di RES (10 -> 11)",
			stats.get_marca(Marche.Marca.RES) == 11, esito)
	esito = _controlla("una Marca non comprata resta a 10",
			stats.get_marca(Marche.Marca.CON) == 10, esito)

	## ─── il tetto di 99 per Marca ───────────────────────────────────────────
	## Senza player in scena il valore e' base + punti comprati, che basta per
	## provare il tetto: portiamo CON al massimo falsificando i punti.
	prog.reset()
	banca.reset()
	banca.add(100000000)
	var da_comprare: int = prog.MARCA_MASSIMA - prog.MARCA_PARTENZA
	var tutte_ok := true
	for _i in da_comprare:
		if not prog.sali(Marche.Marca.CON):
			tutte_ok = false
			break
	esito = _controlla("si comprano tutti gli 89 punti di CON", tutte_ok, esito)
	esito = _controlla("CON e' arrivata a 99",
			prog.valore_marca(Marche.Marca.CON) == prog.MARCA_MASSIMA, esito)
	esito = _controlla("CON risulta al massimo", prog.marca_al_massimo(Marche.Marca.CON), esito)

	var saldo_prima: int = banca.crystals
	esito = _controlla("una Marca a 99 non si puo' piu' alzare",
			not prog.sali(Marche.Marca.CON), esito)
	esito = _controlla("il tentativo non ha speso niente", banca.crystals == saldo_prima, esito)
	esito = _controlla("le altre Marche restano disponibili",
			prog.esistono_marche_disponibili(), esito)
	esito = _controlla("un'altra Marca si alza ancora", prog.sali(Marche.Marca.EMP), esito)

	## ─── il giro dal salvataggio ────────────────────────────────────────────
	## Si salva lo stato COM'E' ora (CON al massimo, EMP a 11): un salvataggio
	## che regge solo su numeri piccoli non dimostra niente.
	var livello_atteso: int = prog.livello
	var salvato : Dictionary = prog.to_dict()
	prog.reset()
	esito = _controlla("dopo reset si riparte da L1", prog.livello == 1, esito)
	esito = _controlla("dopo reset CON e' tornata libera",
			not prog.marca_al_massimo(Marche.Marca.CON), esito)
	prog.from_dict(salvato)
	esito = _controlla("ricaricando torna il livello di prima",
			prog.livello == livello_atteso, esito)
	esito = _controlla("ricaricando CON e' di nuovo al massimo",
			prog.punti_spesi(Marche.Marca.CON) == da_comprare, esito)
	esito = _controlla("ricaricando torna anche il punto su EMP",
			prog.punti_spesi(Marche.Marca.EMP) == 1, esito)

	quit(esito)


func _mille(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += "."
		out += s[i]
	return out


func _crescente(prog: Node, fino_a: int) -> bool:
	var precedente := 0
	for l in range(1, fino_a):
		var c: int = prog.costo_per_livello(l)
		if c <= precedente:
			return false
		precedente = c
	return true


func _controlla(cosa: String, passato: bool, esito_finora: int) -> int:
	print("%s  %s" % ["[ok]" if passato else "[NO]", cosa])
	return esito_finora if passato else 1
