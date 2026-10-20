extends Node

## La GUIDA dei nemici in un mini-dungeon.
##
## I nemici di Arcanium non hanno navmesh: inseguono in linea retta (vedi
## «Dislivelli» e «I PASSAGGI» in arcanium_enemy.gd). In un dungeon la linea
## retta sbatte contro il primo muro. La guida conosce la pianta e risponde a
## due domande:
##   - `prossimo_punto(da, meta)`: dove camminare adesso per arrivare alla meta
##     passando da porte e corridoi (il bersaglio stesso, se la strada e' libera);
##   - `in_vista(a, b)`: se da `a` si vede `b` (muri e porte chiuse coprono).
## Il nemico la trova nel gruppo `guida_percorso`; dove la guida non c'e' (le
## arene, i playground) tutto resta com'era.
##
## Il percorso e' un campo di distanze (BFS sulle celle) calcolato dalla cella
## della meta e tenuto finche' la meta non cambia cella: con piu' nemici sullo
## stesso bersaglio si calcola una volta sola.

const GRUPPO := "guida_percorso"

var pianta : RefCounted
## Le porte chiuse, come insiemi di attraversamenti bloccati: chiave
## "x,z>x,z" in entrambi i versi. Le aggiorna il costruttore quando una porta
## si apre.
var _bloccati := {}

var _campo_meta := Vector2i(-9999, -9999)
var _campo := PackedInt32Array()
## Quanti passi avanti sul percorso si prova a tagliare dritto.
const TAGLIO := 6


func _ready() -> void:
	add_to_group(GRUPPO)


func blocca(a : Vector2i, b : Vector2i, si : bool) -> void:
	var k1 := "%d,%d>%d,%d" % [a.x, a.y, b.x, b.y]
	var k2 := "%d,%d>%d,%d" % [b.x, b.y, a.x, a.y]
	if si:
		_bloccati[k1] = true
		_bloccati[k2] = true
	else:
		_bloccati.erase(k1)
		_bloccati.erase(k2)
	_campo_meta = Vector2i(-9999, -9999)


func _passabile(a : Vector2i, b : Vector2i) -> bool:
	return pianta.camminabile(b) and not _bloccati.has("%d,%d>%d,%d" % [a.x, a.y, b.x, b.y])


## Dove camminare adesso, da `da`, per arrivare a `meta`.
func prossimo_punto(da : Vector3, meta : Vector3) -> Vector3:
	if pianta == null:
		return meta
	var c0 : Vector2i = pianta.cella_di(da)
	var cm : Vector2i = pianta.cella_di(meta)
	if c0 == cm or segmento_libero(da, meta):
		return meta
	_aggiorna_campo(cm)
	var i0 := _indice(c0)
	if i0 < 0 or _campo[i0] < 0:
		return meta
	## Si scende il campo per qualche passo, e si mira al passo piu' lontano
	## ancora raggiungibile in linea retta col corpo intero: il nemico taglia
	## gli angoli invece di andare a scalini, ma non li sfiora.
	var c := c0
	var mira : Variant = null
	for k in TAGLIO:
		var prossima := _discesa(c)
		if prossima == c:
			break
		c = prossima
		if segmento_libero(da, pianta.centro(c)):
			mira = pianta.centro(c)
		else:
			break
	## Nemmeno il primo passo e' dritto (si e' di sbieco contro uno spigolo):
	## prima si torna al centro della propria cella.
	return mira if mira != null else pianta.centro(c0)


## Raggio del corpo che deve passare: un nemico non e' un punto.
const RAGGIO := 0.4
const PASSO_CAMPIONE := 0.25

## Se il segmento da `a` a `b` si percorre col corpo intero: ogni campione, e i
## quattro punti a `RAGGIO` intorno, su pavimento; e nessuna porta chiusa
## attraversata.
func segmento_libero(a : Vector3, b : Vector3) -> bool:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var n := maxi(1, ceili(d.length() / PASSO_CAMPIONE))
	var prec : Vector2i = pianta.cella_di(a)
	for i in n + 1:
		var p := a + d * (float(i) / n)
		var c : Vector2i = pianta.cella_di(p)
		if c != prec and _bloccati.has("%d,%d>%d,%d" % [prec.x, prec.y, c.x, c.y]):
			return false
		prec = c
		for off in [Vector3(RAGGIO, 0, 0), Vector3(-RAGGIO, 0, 0), Vector3(0, 0, RAGGIO), Vector3(0, 0, -RAGGIO)]:
			if not pianta.camminabile(pianta.cella_di(p + off)):
				return false
	return true


func _discesa(c : Vector2i) -> Vector2i:
	var migliore := c
	var dmin : int = _campo[_indice(c)]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q : Vector2i = c + d
		var iq := _indice(q)
		if iq < 0 or _campo[iq] < 0 or not _passabile(c, q):
			continue
		if _campo[iq] < dmin:
			dmin = _campo[iq]
			migliore = q
	return migliore


func _indice(c : Vector2i) -> int:
	if not pianta.dentro(c):
		return -1
	return c.y * pianta.larghezza + c.x


func _aggiorna_campo(meta : Vector2i) -> void:
	if meta == _campo_meta:
		return
	_campo_meta = meta
	_campo.resize(pianta.larghezza * pianta.profondita)
	_campo.fill(-1)
	var im := _indice(meta)
	if im < 0 or not pianta.camminabile(meta):
		return
	_campo[im] = 0
	var coda : Array[Vector2i] = [meta]
	var testa := 0
	while testa < coda.size():
		var c : Vector2i = coda[testa]
		testa += 1
		var dc : int = _campo[_indice(c)]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q : Vector2i = c + d
			var iq := _indice(q)
			if iq < 0 or _campo[iq] >= 0 or not _passabile(c, q):
				continue
			_campo[iq] = dc + 1
			coda.append(q)


## Se da `a` si vede `b`: le celle in mezzo devono essere pavimento o baratro
## (sopra un baratro si vede), e nessuna porta chiusa sul tragitto.
func in_vista(a : Vector3, b : Vector3) -> bool:
	if pianta == null:
		return true
	return _linea_libera(pianta.cella_di(a), pianta.cella_di(b), false)


## Attraversamento delle celle fra `a` e `b` (supercover: non si scavalcano gli
## spigoli). `cammino` = per camminare (il baratro ferma), altrimenti per vedere.
func _linea_libera(a : Vector2i, b : Vector2i, cammino : bool) -> bool:
	## Amanatides-Woo fra i centri delle due celle, un asse alla volta: un
	## passaggio in diagonale fra due muri non risulta mai libero.
	var d := Vector2(b - a)
	var sx := signi(b.x - a.x)
	var sz := signi(b.y - a.y)
	var passo_x : float = absf(1.0 / d.x) if d.x != 0.0 else INF
	var passo_z : float = absf(1.0 / d.y) if d.y != 0.0 else INF
	var t_x : float = passo_x * 0.5
	var t_z : float = passo_z * 0.5
	var c := a
	var prec := a
	while c != b:
		if t_x < t_z:
			c.x += sx
			t_x += passo_x
		else:
			c.y += sz
			t_z += passo_z
		if not _attraversabile(prec, c, cammino):
			return false
		prec = c
	return true


func _attraversabile(a : Vector2i, b : Vector2i, cammino : bool) -> bool:
	if _bloccati.has("%d,%d>%d,%d" % [a.x, a.y, b.x, b.y]):
		return false
	var v : int = pianta.cella(b)
	if cammino:
		return v == pianta.Cella.PAVIMENTO
	return v != pianta.Cella.VUOTO
