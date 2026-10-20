extends Node

## La NEBBIA DI GUERRA del mini-dungeon (richiesta dell'autore, 2026-10-20:
## «Non devi sapere cosa si cela dietro il prossimo muro o nella prossima
## stanza»).
##
## Ogni cella ha tre stati: mai vista (nero), esplorata ma ora fuori vista
## (in penombra), vista adesso. La vista si ricalcola quando il giocatore
## cambia cella o una porta si apre, con la linea di vista della guida: muri
## e porte chiuse coprono, il baratro no.
##
## Come si vede:
##   - la geometria del dungeon porta un material_overlay
##     (nebbia_dungeon.gdshader) che legge una texture con un texel per cella;
##   - i nemici si mostrano solo mentre la loro cella e' in vista;
##   - luci e fiamme si accendono solo quando la loro zona e' esplorata: niente
##     bagliori da dietro i muri, e meno luci da calcolare.
## Le celle passano da uno stato all'altro sfumando, non a scatti.
##
## Verifica: arcanium/tools/verifica_nebbia.gd.

const Shader_ := preload("res://arcanium/levels/dungeon/nebbia_dungeon.gdshader")

var pianta : RefCounted
var guida : Node
var giocatore : Node3D
## Fin dove si vede, in celle.
var raggio : int = 12
## Velocita' della sfumatura, in stati al secondo.
var sfumatura : float = 3.0

var materiale : ShaderMaterial
var _img : Image
var _tex : ImageTexture
## Bersagli (0/1) e valori mostrati, per cella.
var _esplorata := PackedByteArray()
var _vista := PackedByteArray()
var _mostra_e := PackedFloat32Array()
var _mostra_v := PackedFloat32Array()
## Celle che stanno sfumando: indice -> true.
var _attive := {}
var _cella_giocatore := Vector2i(-9999, -9999)
var _porte_bloccate := -1
## [nodo, cella] di luci e fiamme, e i nemici.
var _a_cella : Array = []
var _nemici : Array = []


func prepara(radice : Node) -> void:
	var n : int = pianta.larghezza * pianta.profondita
	for a in [_esplorata, _vista]:
		a.resize(n)
		a.fill(0)
	for a in [_mostra_e, _mostra_v]:
		a.resize(n)
		a.fill(0.0)
	_img = Image.create(pianta.larghezza, pianta.profondita, false, Image.FORMAT_RG8)
	_img.fill(Color(0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	materiale = ShaderMaterial.new()
	materiale.shader = Shader_
	materiale.set_shader_parameter("nebbia", _tex)
	var o : Vector3 = pianta.origine()
	materiale.set_shader_parameter("angolo", Vector2(-o.x, -o.z))
	materiale.set_shader_parameter("lato", pianta.lato_cella)
	materiale.set_shader_parameter("dimensioni", Vector2(pianta.larghezza, pianta.profondita))
	_raccogli(radice)
	aggiorna(true)


## Mette il velo su ogni mesh del dungeon e registra cio' che si accende o si
## mostra per cella. I nemici e il giocatore restano fuori dal velo.
func _raccogli(nodo : Node) -> void:
	for c in nodo.get_children():
		if c.is_in_group("nemico_dungeon"):
			_nemici.append(c)
			c.visible = false
			continue
		if c == giocatore or c is CanvasLayer:
			continue
		if c is Light3D or c is GPUParticles3D:
			_a_cella.append([c, pianta.cella_di((c as Node3D).global_position)])
			c.visible = false
		elif c is MeshInstance3D:
			(c as MeshInstance3D).material_overlay = materiale
		_raccogli(c)


func _process(delta : float) -> void:
	if is_queued_for_deletion():
		return
	aggiorna(false)
	_sfuma(delta)


## Ricalcola la vista se il giocatore ha cambiato cella o una porta si e'
## aperta. `forza` la ricalcola comunque e salta la sfumatura.
func aggiorna(forza : bool) -> void:
	if giocatore == null or not is_instance_valid(giocatore):
		return
	var cg : Vector2i = pianta.cella_di(giocatore.global_position)
	var porte : int = guida._bloccati.size()
	if not forza and cg == _cella_giocatore and porte == _porte_bloccate:
		_mostra_nemici()
		return
	_cella_giocatore = cg
	_porte_bloccate = porte
	var nuova := {}
	for dz in range(-raggio, raggio + 1):
		for dx in range(-raggio, raggio + 1):
			if dx * dx + dz * dz > raggio * raggio:
				continue
			var c := cg + Vector2i(dx, dz)
			if not pianta.dentro(c) or pianta.cella(c) == pianta.Cella.VUOTO:
				continue
			if guida.in_vista_celle(cg, c):
				nuova[c.y * pianta.larghezza + c.x] = true
	for i in _vista.size():
		var v := 1 if nuova.has(i) else 0
		if v != _vista[i]:
			_vista[i] = v
			_attive[i] = true
		if v == 1 and _esplorata[i] == 0:
			_esplorata[i] = 1
			_attive[i] = true
	if forza:
		for i in _attive:
			_mostra_e[i] = _esplorata[i]
			_mostra_v[i] = _vista[i]
		_scrivi(_attive.keys())
		_attive.clear()
	_accendi()
	_mostra_nemici()


func _sfuma(delta : float) -> void:
	if _attive.is_empty():
		return
	var passo := sfumatura * delta
	var cambiate : Array = _attive.keys()
	for i in cambiate:
		_mostra_e[i] = move_toward(_mostra_e[i], _esplorata[i], passo)
		_mostra_v[i] = move_toward(_mostra_v[i], _vista[i], passo)
		if is_equal_approx(_mostra_e[i], _esplorata[i]) and is_equal_approx(_mostra_v[i], _vista[i]):
			_attive.erase(i)
	_scrivi(cambiate)


## Scrive le celle cambiate nella texture, e con loro le celle VUOTE accanto:
## sono i muri, e prendono il massimo dei vicini (vedi lo shader).
func _scrivi(indici : Array) -> void:
	var w : int = pianta.larghezza
	var vuote := {}
	for i in indici:
		var c := Vector2i(i % w, i / w)
		_img.set_pixel(c.x, c.y, Color(_mostra_e[i], _mostra_v[i], 0))
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var q := c + Vector2i(dx, dz)
				if pianta.dentro(q) and pianta.cella(q) == pianta.Cella.VUOTO:
					vuote[q] = true
	for q in vuote:
		var e := 0.0
		var v := 0.0
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var r : Vector2i = q + Vector2i(dx, dz)
				if pianta.dentro(r) and pianta.cella(r) != pianta.Cella.VUOTO:
					e = maxf(e, _mostra_e[r.y * w + r.x])
					v = maxf(v, _mostra_v[r.y * w + r.x])
		_img.set_pixel(q.x, q.y, Color(e, v, 0))
	_tex.update(_img)


## Una luce o una fiamma si accende quando la sua cella, o una accanto (le
## torce stanno sul muro), e' esplorata.
func _accendi() -> void:
	for coppia in _a_cella:
		## Si controlla prima di assegnare: quando il dungeon si ricostruisce
		## questa nebbia vive ancora un frame accanto ai pezzi gia' liberati.
		if not is_instance_valid(coppia[0]):
			continue
		var nodo : Node3D = coppia[0]
		if nodo.visible:
			continue
		var c : Vector2i = coppia[1]
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if esplorata(c + d):
				nodo.visible = true
				break


func _mostra_nemici() -> void:
	for e in _nemici.duplicate():
		if not is_instance_valid(e):
			_nemici.erase(e)
		else:
			e.visible = in_vista(pianta.cella_di(e.global_position))


func esplorata(c : Vector2i) -> bool:
	return pianta.dentro(c) and _esplorata[c.y * pianta.larghezza + c.x] == 1


func in_vista(c : Vector2i) -> bool:
	return pianta.dentro(c) and _vista[c.y * pianta.larghezza + c.x] == 1
