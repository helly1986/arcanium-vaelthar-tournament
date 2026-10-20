extends RefCounted

## La PIANTA di un mini-dungeon: solo dati, niente geometria.
##
## Un mini-dungeon (docs/16_GDD.md, «le arene»; decisione dell'autore del
## 2026-10-20) e' fatto di stanze collegate da corridoi, con porte, baratri,
## trappole, nemici da cercare e forzieri. Come Dungeon Architect: prima il
## GRAFO (stanze e collegamenti), poi la GRIGLIA (celle di pavimento, baratro,
## vuoto), poi il POPOLAMENTO. La geometria la costruisce costruttore_dungeon.gd
## leggendo questa pianta, e la stessa pianta guida i nemici
## (guida_dungeon.gd): cosi' cio' che si vede e cio' che si percorre non
## possono divergere.
##
## Tutto deriva dal SEME: stesso seme, stesso dungeon. Le regole numeriche
## stanno nel profilo (profilo_dungeon.gd), che e' una risorsa: un territorio
## nuovo o un DLC aggiunge un profilo, non codice.
##
## Livello singolo per ora; il multilivello verra' dopo.

const Profilo := preload("res://arcanium/levels/dungeon/profilo_dungeon.gd")

## Contenuto di una cella.
## ACQUA: la fontana e i suoi canali. Non si cammina per la guida (i nemici
## girano intorno o passano dai ponti), ma il giocatore ci guada rallentato o la
## salta: sotto c'e' il pavimento.
enum Cella { VUOTO, PAVIMENTO, BARATRO, ACQUA }

## Ruolo di una stanza. USCITA: dove finisce il percorso (obiettivo USCITA).
enum Ruolo { INGRESSO, COMBATTIMENTO, CHIUSA, TESORO, USCITA }

## Cosa chiede lo scontro (richiesta dell'autore, 2026-10-20: «alcune volte
## l'obiettivo potrebbe essere di trovare l'uscita piuttosto che uccidere per
## forza tutti i nemici»):
##   ELIMINA: si vince quando cadono tutti;
##   USCITA: la pianta e' un PERCORSO dall'ingresso all'uscita, con stanze
##   laterali a vicolo cieco (dove stanno i forzieri); si vince uscendo, i
##   nemici si possono evitare.
enum Obiettivo { ELIMINA, USCITA }

## Forma di una stanza, dentro il suo rettangolo d'ingombro.
enum Forma { RETTANGOLO, CERCHIO, CROCE, ELLE, IRREGOLARE }

var seme : int
var larghezza : int
var profondita : int
var lato_cella : float

## celle[z * larghezza + x] -> Cella
var celle : PackedByteArray
## stanza_di[z * larghezza + x] -> indice stanza, -1 corridoio o vuoto
var stanza_di : PackedInt32Array

## Ogni stanza: {"rect": Rect2i (ingombro), "ruolo": Ruolo, "forma": Forma,
##                "centro": Vector2i (una cella sicuramente sua)}
var stanze : Array[Dictionary] = []
## Collegamenti del grafo: [a, b] indici di stanza.
var collegamenti : Array[Vector2i] = []
## Porte: {"celle": [Vector2i dentro, Vector2i fuori] per ogni cella del varco,
##         "stanza": int, "normale": Vector2i (verso fuori), "chiusa": bool}
var porte : Array[Dictionary] = []
## Trappole: celle con le punte.
var trappole : Array[Vector2i] = []
## Nemici: {"cella": Vector2i, "stanza": int, "tipo": int (indice nel profilo)}
var nemici : Array[Dictionary] = []
## Forzieri: {"cella": Vector2i, "stanza": int, "raro": bool}
var forzieri : Array[Dictionary] = []
## Dove nasce il giocatore.
var ingresso : Vector2i
## Le fontane: {"stanza", "cella"} (la cella al centro della vasca), e i ponti
## sui canali: {"cella", "dir"} (dir = verso del canale).
var obiettivo : int = Obiettivo.ELIMINA
## Obiettivo USCITA: la cella dell'uscita, e le stanze del percorso
## principale nell'ordine in cui si attraversano (dall'ingresso all'uscita).
var uscita := Vector2i(-1, -1)
var percorso : Array[int] = []
## Le trappole a PIASTRA (richiesta dell'autore, 2026-10-20: «piastre a
## pressione che generano palle di fuoco, fulmini, dardi di ghiaccio, dardi
## avvelenati»): {"cella", "tipo" (Piastra), "bocca": la cella al muro da cui
## parte il colpo, "dir": il verso dalla bocca alla piastra}. Il fulmine cade
## dall'alto: niente bocca.
enum Piastra { FUOCO, FULMINE, GHIACCIO, VELENO }
var piastre : Array[Dictionary] = []
var fontane : Array[Dictionary] = []
var ponti : Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _p : Resource


## `obiettivo_voluto` -1: lo decide il seme, con la probabilita' del profilo.
func genera(profilo : Resource, seme_dungeon : int, obiettivo_voluto : int = -1) -> void:
	_p = profilo
	seme = seme_dungeon
	_rng.seed = seme_dungeon
	larghezza = _p.larghezza
	profondita = _p.profondita
	lato_cella = _p.lato_cella
	celle = PackedByteArray()
	celle.resize(larghezza * profondita)
	celle.fill(Cella.VUOTO)
	stanza_di = PackedInt32Array()
	stanza_di.resize(larghezza * profondita)
	stanza_di.fill(-1)
	stanze.clear()
	collegamenti.clear()
	porte.clear()
	trappole.clear()
	nemici.clear()
	forzieri.clear()
	fontane.clear()
	ponti.clear()
	percorso.clear()
	piastre.clear()
	uscita = Vector2i(-1, -1)
	## L'obiettivo con un generatore suo: quello della pianta resta identico, e
	## i dungeon da ripulire di un seme restano quelli di prima.
	obiettivo = obiettivo_voluto
	if obiettivo < 0:
		var tiro := RandomNumberGenerator.new()
		tiro.seed = seme_dungeon * 7349 + 17
		obiettivo = Obiettivo.USCITA if tiro.randf() < _p.probabilita_uscita else Obiettivo.ELIMINA
	_piazza_stanze()
	_collega_stanze()
	_scava_corridoi()
	_svasa_imbocchi()
	_trova_porte()
	_assegna_ruoli()
	_scava_baratri()
	_scava_fontane()
	_sistema_uscita()
	_popola()
	_metti_piastre()


# ─── Accesso alla griglia ──────────────────────────────────────────────────

func dentro(c : Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < larghezza and c.y < profondita


func cella(c : Vector2i) -> int:
	return celle[c.y * larghezza + c.x] if dentro(c) else Cella.VUOTO


func _metti(c : Vector2i, v : int) -> void:
	if dentro(c):
		celle[c.y * larghezza + c.x] = v


func stanza(c : Vector2i) -> int:
	return stanza_di[c.y * larghezza + c.x] if dentro(c) else -1


## Il centro di una cella nel mondo (y = 0, il pavimento).
func centro(c : Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * lato_cella, 0.0, (c.y + 0.5) * lato_cella) - origine()


## Il dungeon e' centrato sull'origine del mondo.
func origine() -> Vector3:
	return Vector3(larghezza * lato_cella * 0.5, 0.0, profondita * lato_cella * 0.5)


func cella_di(p : Vector3) -> Vector2i:
	var q := p + origine()
	return Vector2i(floori(q.x / lato_cella), floori(q.z / lato_cella))


func camminabile(c : Vector2i) -> bool:
	return cella(c) == Cella.PAVIMENTO


# ─── 1. Le stanze: forme e misure molto diverse ────────────────────────────
##
## Non solo rettangoli (indicazione dell'autore, 2026-10-20): cerchi, croci,
## stanze a L e stanze irregolari (due o tre blocchi sovrapposti), da piccole
## a grandissime. La stanza e' l'insieme delle sue celle; il rettangolo e'
## solo l'ingombro, che tiene le stanze distanti fra loro.

func _piazza_stanze() -> void:
	var quante := _rng.randi_range(_p.stanze_min, _p.stanze_max)
	var tentativi := 0
	while stanze.size() < quante and tentativi < 600:
		tentativi += 1
		var w := _rng.randi_range(_p.stanza_lato_min, _p.stanza_lato_max)
		var h := _rng.randi_range(_p.stanza_lato_min, _p.stanza_lato_max)
		var x := _rng.randi_range(1, larghezza - w - 1)
		var z := _rng.randi_range(1, profondita - h - 1)
		var r := Rect2i(x, z, w, h)
		## Fra due stanze resta sempre uno spazio: ci passa il muro, e un
		## corridoio non fonde mai due stanze in una sola.
		var libera := true
		for s in stanze:
			if (s["rect"] as Rect2i).grow(_p.distacco_stanze).intersects(r):
				libera = false
				break
		if not libera:
			continue
		var forma := _tira_forma(w, h)
		var celle_stanza := _celle_della_forma(r, forma)
		if celle_stanza.size() < 12:
			continue
		var i := stanze.size()
		for c in celle_stanza:
			_metti(c, Cella.PAVIMENTO)
			stanza_di[c.y * larghezza + c.x] = i
		## Il centro: la cella della stanza piu' vicina al centro dell'ingombro.
		var cr := r.position + r.size / 2
		var migliore : Vector2i = celle_stanza[0]
		for c in celle_stanza:
			if (c - cr).length_squared() < (migliore - cr).length_squared():
				migliore = c
		stanze.append({"rect": r, "ruolo": Ruolo.COMBATTIMENTO, "forma": forma, "centro": migliore})


func _tira_forma(w : int, h : int) -> int:
	var pesi : PackedFloat32Array = _p.pesi_forme
	## Croce e L hanno bisogno di spazio per avere bracci veri.
	var tot := 0.0
	for k in pesi.size():
		if (k == Forma.CROCE or k == Forma.ELLE) and mini(w, h) < 8:
			continue
		tot += pesi[k]
	var t := _rng.randf() * tot
	for k in pesi.size():
		if (k == Forma.CROCE or k == Forma.ELLE) and mini(w, h) < 8:
			continue
		t -= pesi[k]
		if t <= 0.0:
			return k
	return Forma.RETTANGOLO


func _celle_della_forma(r : Rect2i, forma : int) -> Array[Vector2i]:
	var out : Array[Vector2i] = []
	var w := r.size.x
	var h := r.size.y
	match forma:
		Forma.CERCHIO:
			## Ellisse inscritta nell'ingombro.
			var cx := (w - 1) * 0.5
			var cz := (h - 1) * 0.5
			for z in h:
				for x in w:
					var dx := (x - cx) / (w * 0.5)
					var dz := (z - cz) / (h * 0.5)
					if dx * dx + dz * dz <= 1.0:
						out.append(r.position + Vector2i(x, z))
		Forma.CROCE:
			var bx := maxi(3, w / 3)
			var bz := maxi(3, h / 3)
			for z in h:
				for x in w:
					var nel_braccio_x := x >= (w - bx) / 2 and x < (w - bx) / 2 + bx
					var nel_braccio_z := z >= (h - bz) / 2 and z < (h - bz) / 2 + bz
					if nel_braccio_x or nel_braccio_z:
						out.append(r.position + Vector2i(x, z))
		Forma.ELLE:
			## Si toglie un quadrante a caso: resta una L.
			var tx := _rng.randi_range(w / 3, w / 2)
			var tz := _rng.randi_range(h / 3, h / 2)
			var angolo := _rng.randi_range(0, 3)
			for z in h:
				for x in w:
					var vx := x >= w - tx if angolo % 2 == 0 else x < tx
					var vz := z >= h - tz if angolo < 2 else z < tz
					if not (vx and vz):
						out.append(r.position + Vector2i(x, z))
		Forma.IRREGOLARE:
			## Due o tre blocchi sovrapposti dentro l'ingombro, poi solo la parte
			## collegata al primo.
			var piene := {}
			var blocchi := _rng.randi_range(2, 3)
			for b in blocchi:
				var bw := _rng.randi_range(maxi(3, w / 2), w)
				var bh := _rng.randi_range(maxi(3, h / 2), h)
				var bxo := _rng.randi_range(0, w - bw)
				var bzo := _rng.randi_range(0, h - bh)
				for z in range(bzo, bzo + bh):
					for x in range(bxo, bxo + bw):
						piene[Vector2i(x, z)] = true
			## Due blocchi possono non toccarsi: resta il pezzo piu' grande.
			var migliore : Array[Vector2i] = []
			var visti := {}
			for k in piene.keys():
				if visti.has(k):
					continue
				var pezzo : Array[Vector2i] = []
				var coda : Array = [k]
				visti[k] = true
				while not coda.is_empty():
					var q : Vector2i = coda.pop_back()
					pezzo.append(q)
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var v : Vector2i = q + d
						if piene.has(v) and not visti.has(v):
							visti[v] = true
							coda.append(v)
				if pezzo.size() > migliore.size():
					migliore = pezzo
			for k in migliore:
				out.append(r.position + k)
		_:
			for z in h:
				for x in w:
					out.append(r.position + Vector2i(x, z))
	return out


func _centro_stanza(i : int) -> Vector2i:
	return stanze[i]["centro"]


## Le celle di una stanza.
func celle_di(i : int) -> Array[Vector2i]:
	var r : Rect2i = stanze[i]["rect"]
	var out : Array[Vector2i] = []
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, z)
			if stanza(c) == i:
				out.append(c)
	return out


# ─── 2. Il grafo: albero minimo, piu' qualche anello ───────────────────────

func _collega_stanze() -> void:
	var n := stanze.size()
	if n < 2:
		return
	if obiettivo == Obiettivo.USCITA:
		_collega_a_percorso()
		return
	## Prim sulle distanze fra i centri: tutte le stanze collegate, e i
	## corridoi corti.
	var nell_albero := {0: true}
	while nell_albero.size() < n:
		var migliore := Vector2i(-1, -1)
		var dmin := INF
		for a in nell_albero.keys():
			for b in n:
				if nell_albero.has(b):
					continue
				var d := Vector2(_centro_stanza(a) - _centro_stanza(b)).length()
				if d < dmin:
					dmin = d
					migliore = Vector2i(a, b)
		nell_albero[migliore.y] = true
		collegamenti.append(migliore)
	## Un anello o due: un dungeon ad albero puro non lascia mai scegliere la
	## strada, e chi scappa resta chiuso in un vicolo.
	var anelli := _rng.randi_range(_p.anelli_min, _p.anelli_max)
	for k in anelli:
		var a := _rng.randi_range(0, n - 1)
		var b := _rng.randi_range(0, n - 1)
		if a == b or collegamenti.has(Vector2i(a, b)) or collegamenti.has(Vector2i(b, a)):
			continue
		collegamenti.append(Vector2i(a, b))


## Il PERCORSO dell'obiettivo USCITA: i due capi sono le stanze piu' lontane
## fra loro; le stanze piu' vicine alla linea fra i capi fanno la strada
## principale, in ordine lungo quella linea; le altre (le piu' scostate, un
## terzo) si attaccano alla strada come vicoli ciechi. Niente anelli: c'e' un
## verso, e chi esplora i vicoli lo fa apposta.
func _collega_a_percorso() -> void:
	var n := stanze.size()
	var a := 0
	var b := 1
	var dmax := -1.0
	for i in n:
		for j in range(i + 1, n):
			var d := Vector2(_centro_stanza(i) - _centro_stanza(j)).length()
			if d > dmax:
				dmax = d
				a = i
				b = j
	var pa := Vector2(_centro_stanza(a))
	var asse := (Vector2(_centro_stanza(b)) - pa).normalized()
	var altre : Array = []
	for i in n:
		if i != a and i != b:
			var v := Vector2(_centro_stanza(i)) - pa
			altre.append([i, v.dot(asse), absf(v.cross(asse))])
	## Le piu' scostate dalla linea diventano laterali.
	altre.sort_custom(func(x, y): return x[2] > y[2])
	var laterali := int((n - 2) * 0.35)
	var lato : Array = altre.slice(0, laterali)
	var strada : Array = altre.slice(laterali)
	strada.sort_custom(func(x, y): return x[1] < y[1])
	percorso.clear()
	percorso.append(a)
	for s in strada:
		percorso.append(s[0])
	percorso.append(b)
	for k in percorso.size() - 1:
		collegamenti.append(Vector2i(percorso[k], percorso[k + 1]))
	## Ogni laterale alla stanza della strada piu' vicina, mai all'uscita.
	for s in lato:
		var migliore := a
		var dm := INF
		for k in percorso.size() - 1:
			var d := Vector2(_centro_stanza(s[0]) - _centro_stanza(percorso[k])).length()
			if d < dm:
				dm = d
				migliore = percorso[k]
		collegamenti.append(Vector2i(migliore, s[0]))


# ─── 3. I corridoi: tortuosi, di larghezza variabile ──────────────────────
##
## Da un centro all'altro passando per 0-2 deviazioni a caso, a tratti
## dritti; ogni corridoio ha la sua larghezza, da uno stretto budello a una
## galleria.

func _scava_corridoi() -> void:
	for e in collegamenti:
		var a := _centro_stanza(e.x)
		var b := _centro_stanza(e.y)
		var largo := _rng.randi_range(_p.corridoio_largo_min, _p.corridoio_largo_max)
		var tappe : Array[Vector2i] = [a]
		var deviazioni := _rng.randi_range(_p.deviazioni_min, _p.deviazioni_max)
		for k in deviazioni:
			var f := float(k + 1) / (deviazioni + 1)
			var base := Vector2(a).lerp(Vector2(b), f)
			var scarto : Vector2 = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _p.deviazione_ampiezza
			var q := Vector2i(base + scarto)
			q.x = clampi(q.x, 2, larghezza - 3)
			q.y = clampi(q.y, 2, profondita - 3)
			tappe.append(q)
		tappe.append(b)
		for k in tappe.size() - 1:
			var da : Vector2i = tappe[k]
			var verso : Vector2i = tappe[k + 1]
			var gomito := Vector2i(verso.x, da.y) if _rng.randf() < 0.5 else Vector2i(da.x, verso.y)
			_scava_tratto(da, gomito, largo)
			_scava_tratto(gomito, verso, largo)


func _scava_tratto(da : Vector2i, a : Vector2i, largo : int) -> void:
	var passo := Vector2i(signi(a.x - da.x), signi(a.y - da.y))
	var c := da
	while true:
		for k in largo:
			## Lo spessore va di lato rispetto alla direzione di marcia; a un
			## gomito si allarga in tutte e due le direzioni.
			for lato in [Vector2i(k, 0), Vector2i(0, k)]:
				var q : Vector2i = c + lato
				if dentro(q) and q.x > 0 and q.y > 0 and q.x < larghezza - 1 and q.y < profondita - 1 \
						and cella(q) == Cella.VUOTO:
					_metti(q, Cella.PAVIMENTO)
		if c == a:
			break
		c += passo


# ─── 4. Le porte: dove un corridoio entra in una stanza ────────────────────

## Gli imbocchi si allargano di una cella per lato, lungo il muro della
## stanza: un corridoio che sbuca della sua larghezza esatta sembra una
## feritoia. Si raccolgono prima e si scavano dopo, o l'allargamento si
## allargherebbe a sua volta lungo tutto il muro.
func _svasa_imbocchi() -> void:
	var nuove := {}
	for i in stanze.size():
		for c in celle_di(i):
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var fuori : Vector2i = c + dir
				if not camminabile(fuori) or stanza(fuori) != -1:
					continue
				var lato := Vector2i(dir.y, dir.x)
				for s in [lato, -lato]:
					var q : Vector2i = fuori + s
					if cella(q) == Cella.VUOTO and stanza(q - dir) == i \
							and q.x > 0 and q.y > 0 and q.x < larghezza - 1 and q.y < profondita - 1:
						nuove[q] = true
	for q in nuove:
		_metti(q, Cella.PAVIMENTO)


func _trova_porte() -> void:
	const DIREZIONI := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in stanze.size():
		var celle_stanza := celle_di(i)
		for dir in DIREZIONI:
			## I bordi della stanza su questo lato che danno su un corridoio,
			## raggruppati per riga (o colonna) e contigui: un gruppo, una porta.
			var per_linea := {}
			for c in celle_stanza:
				var fuori : Vector2i = c + dir
				if camminabile(fuori) and stanza(fuori) == -1:
					var linea : int = c.x if dir.x != 0 else c.y
					if not per_linea.has(linea):
						per_linea[linea] = []
					per_linea[linea].append(c)
			for linea in per_linea:
				var lista : Array = per_linea[linea]
				lista.sort_custom(func(p, q): return (p.y if dir.x != 0 else p.x) < (q.y if dir.x != 0 else q.x))
				var varco : Array = []
				var prec : Variant = null
				for c in lista:
					var lungo : int = c.y if dir.x != 0 else c.x
					if prec != null and lungo != int(prec) + 1:
						porte.append({"celle": varco, "stanza": i, "normale": dir, "chiusa": false})
						varco = []
					varco.append([c, c + dir])
					prec = lungo
				if not varco.is_empty():
					porte.append({"celle": varco, "stanza": i, "normale": dir, "chiusa": false})


func porte_di(i : int) -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for p in porte:
		if p["stanza"] == i:
			out.append(p)
	return out


# ─── 5. I ruoli: ingresso, stanze chiuse, tesoro ───────────────────────────

func _assegna_ruoli() -> void:
	if obiettivo == Obiettivo.USCITA:
		_assegna_ruoli_percorso()
		return
	## L'ingresso e' la stanza piu' lontana dal baricentro: si parte da un capo
	## del dungeon e lo si attraversa.
	var bari := Vector2.ZERO
	for i in stanze.size():
		bari += Vector2(_centro_stanza(i))
	bari /= maxf(1.0, stanze.size())
	var lontana := 0
	var dmax := -1.0
	for i in stanze.size():
		var d := Vector2(_centro_stanza(i)).distance_to(bari)
		if d > dmax:
			dmax = d
			lontana = i
	stanze[lontana]["ruolo"] = Ruolo.INGRESSO
	ingresso = _centro_stanza(lontana)
	for i in stanze.size():
		if i == lontana:
			continue
		var tiro := _rng.randf()
		if tiro < _p.probabilita_tesoro:
			stanze[i]["ruolo"] = Ruolo.TESORO
		elif tiro < _p.probabilita_tesoro + _p.probabilita_chiusa:
			stanze[i]["ruolo"] = Ruolo.CHIUSA
	## Le porte delle stanze chiuse (e del tesoro) sono chiuse: dentro non si
	## vede, e chi c'e' resta li' finche' non si apre.
	for p in porte:
		var ruolo : int = stanze[p["stanza"]]["ruolo"]
		p["chiusa"] = ruolo == Ruolo.CHIUSA or ruolo == Ruolo.TESORO


## Percorso: l'ingresso a un capo, l'uscita all'altro. Le stanze laterali
## sono quelle che premiano chi devia: tesori e stanze chiuse stanno li'.
func _assegna_ruoli_percorso() -> void:
	var primo : int = percorso[0]
	var ultimo : int = percorso[percorso.size() - 1]
	stanze[primo]["ruolo"] = Ruolo.INGRESSO
	ingresso = _centro_stanza(primo)
	stanze[ultimo]["ruolo"] = Ruolo.USCITA
	uscita = _centro_stanza(ultimo)
	for i in stanze.size():
		if i == primo or i == ultimo:
			continue
		var tiro := _rng.randf()
		if not percorso.has(i):
			## Vicolo cieco: piu' facile che valga la deviazione.
			if tiro < _p.probabilita_tesoro * 3.0:
				stanze[i]["ruolo"] = Ruolo.TESORO
			elif tiro < _p.probabilita_tesoro * 3.0 + _p.probabilita_chiusa:
				stanze[i]["ruolo"] = Ruolo.CHIUSA
		elif tiro < _p.probabilita_chiusa * 0.5:
			stanze[i]["ruolo"] = Ruolo.CHIUSA
	for p in porte:
		var ruolo : int = stanze[p["stanza"]]["ruolo"]
		p["chiusa"] = ruolo == Ruolo.CHIUSA or ruolo == Ruolo.TESORO


## La scala dell'uscita su una cella di pavimento vera: il centro di una
## croce o di una stanza irregolare puo' non esserlo. Si prende la cella della
## stanza piu' vicina al centro con le otto vicine di pavimento (la scala e'
## larga), o almeno camminabile.
func _sistema_uscita() -> void:
	if uscita.x < 0:
		return
	var i := stanza(uscita)
	if i < 0:
		i = percorso[percorso.size() - 1]
	var migliore := uscita
	var punti := -1
	var dmin := INF
	for c in celle_di(i):
		if not camminabile(c):
			continue
		var pieni := 0
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if camminabile(c + Vector2i(dx, dz)) and stanza(c + Vector2i(dx, dz)) == i:
					pieni += 1
		var d := Vector2(c - stanze[i]["centro"]).length()
		if pieni > punti or (pieni == punti and d < dmin):
			punti = pieni
			dmin = d
			migliore = c
	uscita = migliore


# ─── 6. I baratri: una fascia attraverso la stanza, con un ponte ───────────

func _scava_baratri() -> void:
	for i in stanze.size():
		if stanze[i]["ruolo"] == Ruolo.INGRESSO or stanze[i]["ruolo"] == Ruolo.USCITA:
			continue
		var r : Rect2i = stanze[i]["rect"]
		if mini(r.size.x, r.size.y) < _p.baratro_stanza_min or _rng.randf() > _p.probabilita_baratro:
			continue
		## La fascia corre lungo il lato lungo, a meta' stanza; il ponte e' un
		## tratto lasciato pieno.
		var orizzontale := r.size.x >= r.size.y
		var spessore : int = _p.baratro_spessore
		var lungo := r.size.x if orizzontale else r.size.y
		var largo := r.size.y if orizzontale else r.size.x
		var inizio := (largo - spessore) / 2
		var ponte := _rng.randi_range(1, lungo - 1 - _p.ponte_largo)
		var scavate : Array[Vector2i] = []
		for s in spessore:
			for l in lungo:
				if l >= ponte and l < ponte + _p.ponte_largo:
					continue
				var c := Vector2i(r.position.x + l, r.position.y + inizio + s) if orizzontale \
					else Vector2i(r.position.x + inizio + s, r.position.y + l)
				## Solo dentro la stanza (le forme non riempiono l'ingombro), e mai
				## davanti a una porta: chi entra non deve cadere al primo passo.
				if stanza(c) != i or _vicino_a_porta(c, 1):
					continue
				_metti(c, Cella.BARATRO)
				scavate.append(c)
		## Il ponte deve tenere unito il dungeon: se non lo fa, si richiude.
		if not _tutto_raggiungibile():
			for c in scavate:
				_metti(c, Cella.PAVIMENTO)


# ─── 6-bis. Le fontane: un pezzo grosso nelle stanze grandissime ──────────
##
## Richiesta dell'autore, 2026-10-20: «nelle stanze grandissime proviamo a
## mettere qualcosa di GROSSO (ex. fontana con corsi d'acqua da saltare)». La
## vasca prende 3x3 celle al centro; da li' quattro canali larghi una cella
## corrono verso i muri e si fermano due celle prima, con un ponte a meta'.
## Il dungeon deve restare unito per chi cammina (i nemici): se no, niente.

func _scava_fontane() -> void:
	for i in stanze.size():
		if stanze[i]["ruolo"] != Ruolo.COMBATTIMENTO or stanze[i]["forma"] == Forma.IRREGOLARE:
			continue
		var r : Rect2i = stanze[i]["rect"]
		if mini(r.size.x, r.size.y) < _p.fontana_stanza_min or _rng.randf() > _p.probabilita_fontana:
			continue
		var c : Vector2i = stanze[i]["centro"]
		var scavate : Array[Vector2i] = []
		var adatta := true
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var q := c + Vector2i(dx, dz)
				if stanza(q) != i or cella(q) != Cella.PAVIMENTO or _vicino_a_porta(q, 2):
					adatta = false
		if not adatta:
			continue
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				_metti(c + Vector2i(dx, dz), Cella.ACQUA)
				scavate.append(c + Vector2i(dx, dz))
		var ponti_qui : Array[Dictionary] = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var canale : Array[Vector2i] = []
			var q : Vector2i = c + d * 2
			while stanza(q + d * 2) == i and cella(q) == Cella.PAVIMENTO and not _vicino_a_porta(q, 1):
				canale.append(q)
				q += d
			if canale.size() < 3:
				continue
			var ponte : Vector2i = canale[canale.size() / 2]
			for k in canale:
				if k != ponte:
					_metti(k, Cella.ACQUA)
					scavate.append(k)
			ponti_qui.append({"cella": ponte, "dir": d})
		if not _tutto_raggiungibile():
			for k in scavate:
				_metti(k, Cella.PAVIMENTO)
			continue
		fontane.append({"stanza": i, "cella": c})
		ponti.append_array(ponti_qui)


func _vicino_a_porta(c : Vector2i, raggio : int) -> bool:
	for p in porte:
		for coppia in p["celle"]:
			var d : Vector2i = (coppia[0] as Vector2i) - c
			if absi(d.x) <= raggio and absi(d.y) <= raggio:
				return true
	return false


## Tutte le celle di pavimento raggiungibili dall'ingresso (porte chiuse
## comprese: si aprono avvicinandosi).
func raggiungibili() -> Dictionary:
	var visti := {ingresso: true}
	var coda : Array[Vector2i] = [ingresso]
	while not coda.is_empty():
		var c : Vector2i = coda.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q : Vector2i = c + d
			if camminabile(q) and not visti.has(q):
				visti[q] = true
				coda.append(q)
	return visti


func _tutto_raggiungibile() -> bool:
	var visti := raggiungibili()
	for z in profondita:
		for x in larghezza:
			if celle[z * larghezza + x] == Cella.PAVIMENTO and not visti.has(Vector2i(x, z)):
				return false
	return true


# ─── 7. Il popolamento: nemici, trappole, forzieri ─────────────────────────

func _popola() -> void:
	var occupate := {}
	occupate[ingresso] = true
	if uscita.x >= 0:
		## L'uscita e le celle intorno libere: ci va la scala.
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				occupate[uscita + Vector2i(dx, dz)] = true
	for i in stanze.size():
		var ruolo : int = stanze[i]["ruolo"]
		if ruolo == Ruolo.INGRESSO:
			continue
		var libere := _celle_libere_di(i, occupate)
		## Nemici: piu' grande la stanza, piu' nemici. Il tesoro ha un custode.
		var area : int = celle_di(i).size()
		var n : int = clampi(int(area / _p.celle_per_nemico) + _rng.randi_range(0, 1), 1, _p.nemici_per_stanza_max)
		if ruolo == Ruolo.TESORO:
			n = 1
		for k in n:
			if libere.is_empty():
				break
			var c : Vector2i = libere.pop_at(_rng.randi_range(0, libere.size() - 1))
			occupate[c] = true
			nemici.append({"cella": c, "stanza": i, "tipo": _tira_tipo()})
		## Forzieri: sempre nel tesoro (raro col doppio della probabilita'),
		## a caso altrove. Contro un muro, lontano dalle porte.
		var vuole_forziere : bool = ruolo == Ruolo.TESORO or (ruolo != Ruolo.USCITA and _rng.randf() < _p.probabilita_forziere)
		if vuole_forziere:
			var bordo := _celle_al_muro(i, occupate)
			if not bordo.is_empty():
				var c : Vector2i = bordo[_rng.randi_range(0, bordo.size() - 1)]
				occupate[c] = true
				var p_raro : float = _p.probabilita_raro * (2.0 if ruolo == Ruolo.TESORO else 1.0)
				forzieri.append({"cella": c, "stanza": i, "raro": _rng.randf() < p_raro})
	## Gruppi di nemici anche nei CORRIDOI: si combatte anche per strada, e nei
	## budelli stretti in modo diverso che in una sala.
	var corridoio : Array[Vector2i] = []
	for z in profondita:
		for x in larghezza:
			var c := Vector2i(x, z)
			if camminabile(c) and stanza(c) == -1 and not occupate.has(c) and not _vicino_a_porta(c, 2) \
					and (c - ingresso).length() > 8.0:
				corridoio.append(c)
	var gruppi := _rng.randi_range(_p.gruppi_corridoio_min, _p.gruppi_corridoio_max)
	for g in gruppi:
		if corridoio.is_empty():
			break
		var capo : Vector2i = corridoio[_rng.randi_range(0, corridoio.size() - 1)]
		var quanti := _rng.randi_range(1, 3)
		for c in corridoio.duplicate():
			if quanti <= 0:
				break
			if (c - capo).length() <= 2.0 and not occupate.has(c):
				occupate[c] = true
				corridoio.erase(c)
				nemici.append({"cella": c, "stanza": -1, "tipo": _tira_tipo()})
				quanti -= 1
	## Trappole: sul pavimento libero, mai davanti a una porta ne' nell'ingresso.
	var candidati : Array[Vector2i] = []
	for z in profondita:
		for x in larghezza:
			var c := Vector2i(x, z)
			if not camminabile(c) or occupate.has(c) or _vicino_a_porta(c, 1):
				continue
			var s := stanza(c)
			if s >= 0 and stanze[s]["ruolo"] == Ruolo.INGRESSO:
				continue
			candidati.append(c)
	var quante := _rng.randi_range(_p.trappole_min, _p.trappole_max)
	for k in quante:
		if candidati.is_empty():
			break
		var c : Vector2i = candidati.pop_at(_rng.randi_range(0, candidati.size() - 1))
		trappole.append(c)
		occupate[c] = true


## Le piastre, con un generatore loro (il resto della pianta di un seme non
## cambia). Una piastra va su pavimento libero, lontana da porte, ingresso,
## uscita e altre trappole; per fuoco, ghiaccio e veleno serve un muro in
## linea retta entro 7 celle, con pavimento libero in mezzo: li' sta la bocca.
const PORTATA_BOCCA := 7

func _metti_piastre() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seme * 911 + 3
	var prese := {}
	for c in trappole:
		prese[c] = true
	for n in nemici:
		prese[n["cella"]] = true
	for f in forzieri:
		prese[f["cella"]] = true
	var candidati : Array[Vector2i] = []
	for z in profondita:
		for x in larghezza:
			var c := Vector2i(x, z)
			if not camminabile(c) or prese.has(c) or _vicino_a_porta(c, 1):
				continue
			if Vector2(c - ingresso).length() < 5.0 or (uscita.x >= 0 and Vector2(c - uscita).length() < 3.0):
				continue
			candidati.append(c)
	var quante := rng.randi_range(_p.piastre_min, _p.piastre_max)
	var tentativi := 0
	while piastre.size() < quante and not candidati.is_empty() and tentativi < 200:
		tentativi += 1
		var c : Vector2i = candidati.pop_at(rng.randi_range(0, candidati.size() - 1))
		var lontana := true
		for p in piastre:
			if Vector2(p["cella"] - c).length() < 4.0:
				lontana = false
		if not lontana:
			continue
		var tipo : int = rng.randi_range(0, 3)
		var voce := {"cella": c, "tipo": tipo, "bocca": c, "dir": Vector2i.ZERO}
		if tipo != Piastra.FULMINE:
			var vie : Array = []
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := c
				var passi := 0
				while passi < PORTATA_BOCCA and camminabile(q + d):
					q += d
					passi += 1
				if passi >= 2 and cella(q + d) == Cella.VUOTO:
					vie.append([q, -d])
			if vie.is_empty():
				tipo = Piastra.FULMINE
				voce["tipo"] = tipo
			else:
				var via : Array = vie[rng.randi_range(0, vie.size() - 1)]
				voce["bocca"] = via[0]
				voce["dir"] = via[1]
		piastre.append(voce)
		prese[c] = true


func _celle_libere_di(i : int, occupate : Dictionary) -> Array[Vector2i]:
	var out : Array[Vector2i] = []
	for c in celle_di(i):
		## Lontano dai muri di una cella: i nemici non nascono incastrati.
		var interna := true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cella(c + d) == Cella.VUOTO:
				interna = false
		if interna and camminabile(c) and not occupate.has(c) and not _vicino_a_porta(c, 1):
			out.append(c)
	return out


func _celle_al_muro(i : int, occupate : Dictionary) -> Array[Vector2i]:
	var out : Array[Vector2i] = []
	for c in celle_di(i):
		var al_muro := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cella(c + d) == Cella.VUOTO:
				al_muro = true
		if al_muro and camminabile(c) and not occupate.has(c) and not _vicino_a_porta(c, 2):
			out.append(c)
	return out


func _tira_tipo() -> int:
	var pesi : PackedFloat32Array = _p.pesi_nemici
	var tot := 0.0
	for w in pesi:
		tot += w
	var t := _rng.randf() * tot
	for k in pesi.size():
		t -= pesi[k]
		if t <= 0.0:
			return k
	return pesi.size() - 1
