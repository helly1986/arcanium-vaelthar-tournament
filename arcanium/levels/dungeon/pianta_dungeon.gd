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
enum Cella { VUOTO, PAVIMENTO, BARATRO }

## Ruolo di una stanza.
enum Ruolo { INGRESSO, COMBATTIMENTO, CHIUSA, TESORO }

var seme : int
var larghezza : int
var profondita : int
var lato_cella : float

## celle[z * larghezza + x] -> Cella
var celle : PackedByteArray
## stanza_di[z * larghezza + x] -> indice stanza, -1 corridoio o vuoto
var stanza_di : PackedInt32Array

## Ogni stanza: {"rect": Rect2i, "ruolo": Ruolo}
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

var _rng := RandomNumberGenerator.new()
var _p : Resource


func genera(profilo : Resource, seme_dungeon : int) -> void:
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
	_piazza_stanze()
	_collega_stanze()
	_scava_corridoi()
	_trova_porte()
	_assegna_ruoli()
	_scava_baratri()
	_popola()


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


# ─── 1. Le stanze ──────────────────────────────────────────────────────────

func _piazza_stanze() -> void:
	var quante := _rng.randi_range(_p.stanze_min, _p.stanze_max)
	var tentativi := 0
	while stanze.size() < quante and tentativi < 400:
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
		stanze.append({"rect": r, "ruolo": Ruolo.COMBATTIMENTO})
		var i := stanze.size() - 1
		for zz in range(r.position.y, r.end.y):
			for xx in range(r.position.x, r.end.x):
				_metti(Vector2i(xx, zz), Cella.PAVIMENTO)
				stanza_di[zz * larghezza + xx] = i


func _centro_stanza(i : int) -> Vector2i:
	var r : Rect2i = stanze[i]["rect"]
	return r.position + r.size / 2


# ─── 2. Il grafo: albero minimo, piu' qualche anello ───────────────────────

func _collega_stanze() -> void:
	var n := stanze.size()
	if n < 2:
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


# ─── 3. I corridoi: a L, larghi `corridoio_largo` celle ────────────────────

func _scava_corridoi() -> void:
	for e in collegamenti:
		var a := _centro_stanza(e.x)
		var b := _centro_stanza(e.y)
		var prima_x := _rng.randf() < 0.5
		var gomito := Vector2i(b.x, a.y) if prima_x else Vector2i(a.x, b.y)
		_scava_tratto(a, gomito)
		_scava_tratto(gomito, b)


func _scava_tratto(da : Vector2i, a : Vector2i) -> void:
	var passo := Vector2i(signi(a.x - da.x), signi(a.y - da.y))
	var c := da
	var largo : int = _p.corridoio_largo
	while true:
		for k in largo:
			## Lo spessore va di lato rispetto alla direzione di marcia.
			var lato := Vector2i(k, 0) if passo.x == 0 else Vector2i(0, k)
			var q := c + lato
			if dentro(q) and cella(q) == Cella.VUOTO:
				_metti(q, Cella.PAVIMENTO)
		if c == a:
			break
		c += passo


# ─── 4. Le porte: dove un corridoio entra in una stanza ────────────────────

func _trova_porte() -> void:
	const DIREZIONI := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in stanze.size():
		var r : Rect2i = stanze[i]["rect"]
		for dir in DIREZIONI:
			## Le celle di bordo della stanza su quel lato, in ordine.
			var bordo : Array[Vector2i] = []
			if dir.x != 0:
				var x := r.end.x - 1 if dir.x > 0 else r.position.x
				for z in range(r.position.y, r.end.y):
					bordo.append(Vector2i(x, z))
			else:
				var z := r.end.y - 1 if dir.y > 0 else r.position.y
				for x in range(r.position.x, r.end.x):
					bordo.append(Vector2i(x, z))
			## Un varco e' una serie di celle di bordo con il pavimento subito
			## fuori: celle contigue = una porta sola.
			var varco : Array = []
			for c in bordo:
				var fuori : Vector2i = c + dir
				if camminabile(fuori) and stanza(fuori) == -1:
					varco.append([c, fuori])
				elif not varco.is_empty():
					porte.append({"celle": varco, "stanza": i, "normale": dir, "chiusa": false})
					varco = []
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


# ─── 6. I baratri: una fascia attraverso la stanza, con un ponte ───────────

func _scava_baratri() -> void:
	for i in stanze.size():
		if stanze[i]["ruolo"] == Ruolo.INGRESSO:
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
				## Mai davanti a una porta: chi entra non deve cadere al primo passo.
				if _vicino_a_porta(c, 1):
					continue
				_metti(c, Cella.BARATRO)
				scavate.append(c)
		## Il ponte deve tenere unito il dungeon: se non lo fa, si richiude.
		if not _tutto_raggiungibile():
			for c in scavate:
				_metti(c, Cella.PAVIMENTO)


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
	for i in stanze.size():
		var ruolo : int = stanze[i]["ruolo"]
		if ruolo == Ruolo.INGRESSO:
			continue
		var libere := _celle_libere_di(i, occupate)
		## Nemici: piu' grande la stanza, piu' nemici. Il tesoro ha un custode.
		var area : int = (stanze[i]["rect"] as Rect2i).get_area()
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
		var vuole_forziere : bool = ruolo == Ruolo.TESORO or _rng.randf() < _p.probabilita_forziere
		if vuole_forziere:
			var bordo := _celle_al_muro(i, occupate)
			if not bordo.is_empty():
				var c : Vector2i = bordo[_rng.randi_range(0, bordo.size() - 1)]
				occupate[c] = true
				var p_raro : float = _p.probabilita_raro * (2.0 if ruolo == Ruolo.TESORO else 1.0)
				forzieri.append({"cella": c, "stanza": i, "raro": _rng.randf() < p_raro})
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


func _celle_libere_di(i : int, occupate : Dictionary) -> Array[Vector2i]:
	var r : Rect2i = stanze[i]["rect"]
	var out : Array[Vector2i] = []
	for z in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1, r.end.x - 1):
			var c := Vector2i(x, z)
			if camminabile(c) and not occupate.has(c) and not _vicino_a_porta(c, 1):
				out.append(c)
	return out


func _celle_al_muro(i : int, occupate : Dictionary) -> Array[Vector2i]:
	var r : Rect2i = stanze[i]["rect"]
	var out : Array[Vector2i] = []
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, z)
			var al_bordo := x == r.position.x or x == r.end.x - 1 or z == r.position.y or z == r.end.y - 1
			if al_bordo and camminabile(c) and not occupate.has(c) and not _vicino_a_porta(c, 2):
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
