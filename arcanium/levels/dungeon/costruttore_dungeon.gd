extends Node3D

## Il COSTRUTTORE di un mini-dungeon: dalla pianta (pianta_dungeon.gd) alla
## scena giocabile.
##
## Costruisce, in quest'ordine:
##   1. il pavimento, una mesh sola sulle celle di pavimento (sui baratri no);
##   2. i muri, una mesh sola, alti dove chiudono la vista lontano dalla camera
##      e BASSI fra la stanza e la camera (+z): la camera isometrica guarda da
##      sud, e un muro alto davanti nasconderebbe il giocatore;
##   3. il vuoto sotto i baratri, e la zona di caduta: chi ci finisce dentro
##      e' fuori (il giocatore perde il match, un nemico muore);
##   4. porte e archi sui varchi delle stanze;
##   5. trappole, forzieri, arredo (colonne, coni, macerie, sassi);
##   6. i nemici e la guida che li porta per i corridoi;
##   7. il giocatore all'ingresso;
##   8. la nebbia di guerra (nebbia_dungeon.gd).
##
## L'obiettivo dello scontro normale e' eliminare tutti i nemici: quando
## l'ultimo cade parte `ripulito`. Se il giocatore cade nel baratro, `caduto`.
##
## Lancio: arcanium/levels/dungeon/dungeon_prova.tscn (seme da inspector; -1 a
## caso). Verifica: arcanium/tools/verifica_dungeon.gd.

const Misura := preload("res://arcanium/levels/dungeon/misura_pezzo.gd")
const Pianta := preload("res://arcanium/levels/dungeon/pianta_dungeon.gd")
const Guida := preload("res://arcanium/levels/dungeon/guida_dungeon.gd")
const Porta := preload("res://arcanium/levels/dungeon/porta_dungeon.gd")
const Trappola := preload("res://arcanium/levels/dungeon/trappola_punte.gd")
const Forziere := preload("res://arcanium/levels/dungeon/forziere_dungeon.gd")
const Fuoco := preload("res://arcanium/levels/dungeon/fuoco_dungeon.gd")
const Nebbia := preload("res://arcanium/levels/dungeon/nebbia_dungeon.gd")

signal ripulito
signal caduto
signal forziere_aperto(raro : bool)

@export var profilo : Resource
## Il seme del dungeon; -1 ne tira uno a caso.
@export var seme : int = -1
## Il giocatore da portare all'ingresso (vuoto: nessuno).
@export var giocatore : NodePath
## Costruisce da solo all'avvio della scena.
@export var costruisci_subito : bool = true
## Mostra il contatore dei nemici rimasti.
@export var mostra_contatore : bool = true
## Nebbia di guerra: si vede solo cio' che il giocatore ha in vista.
@export var nebbia_attiva : bool = true

var pianta : RefCounted
var guida : Node
var nebbia : Node
var _nemici_vivi := 0
var _contatore : Label
var _rng := RandomNumberGenerator.new()

const QUOTA_CADUTA := -6.0
const SPESSORE_MURO := 0.4


func _ready() -> void:
	if costruisci_subito:
		costruisci()


func costruisci() -> void:
	for c in get_children():
		c.queue_free()
	var s := seme if seme >= 0 else randi() % 1000000
	pianta = Pianta.new()
	pianta.genera(profilo, s)
	_rng.seed = s + 7919
	print("DUNGEON: seme %d, %d stanze, %d porte (%d chiuse), %d nemici, %d forzieri, %d trappole" % [
		s, pianta.stanze.size(), pianta.porte.size(),
		pianta.porte.filter(func(p): return p["chiusa"]).size(),
		pianta.nemici.size(), pianta.forzieri.size(), pianta.trappole.size()])
	guida = Guida.new()
	guida.name = "Guida"
	guida.pianta = pianta
	add_child(guida)
	_costruisci_pavimento()
	_costruisci_muri()
	_costruisci_luci()
	_costruisci_vuoto()
	_costruisci_porte()
	_costruisci_trappole()
	_costruisci_forzieri()
	_costruisci_arredo()
	_costruisci_nemici()
	_porta_giocatore()
	_costruisci_nebbia()
	if mostra_contatore:
		_costruisci_contatore()


# ─── 1. Pavimento ──────────────────────────────────────────────────────────

## Lato di un blocco di pavimento, in celle. Il renderer Mobile da' a ogni
## oggetto al massimo 8 luci: un pavimento in un pezzo solo, con le torce di
## tutto il dungeon, ne perderebbe la maggior parte. A blocchi, ognuno riceve
## solo le luci vicine, e quelli fuori schermo non si disegnano.
const BLOCCO := 8

func _costruisci_pavimento() -> void:
	var blocchi := {}
	var facce := PackedVector3Array()
	var l : float = pianta.lato_cella
	for z in pianta.profondita:
		for x in pianta.larghezza:
			var c := Vector2i(x, z)
			if not pianta.camminabile(c):
				continue
			var k := Vector2i(x / BLOCCO, z / BLOCCO)
			if not blocchi.has(k):
				var nuovo := SurfaceTool.new()
				nuovo.begin(Mesh.PRIMITIVE_TRIANGLES)
				blocchi[k] = nuovo
			var st : SurfaceTool = blocchi[k]
			var o : Vector3 = pianta.centro(c) - Vector3(l * 0.5, 0.0, l * 0.5)
			var q := [o, o + Vector3(l, 0, 0), o + Vector3(l, 0, l), o + Vector3(0, 0, l)]
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(q[i].x, q[i].z))
				st.add_vertex(q[i])
				facce.append(q[i])
	for k in blocchi:
		var st : SurfaceTool = blocchi[k]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = "Pavimento_%d_%d" % [k.x, k.y]
		mi.mesh = st.commit()
		mi.material_override = profilo.materiale_pavimento
		add_child(mi)
	var corpo := StaticBody3D.new()
	corpo.name = "PavimentoCorpo"
	var forma := CollisionShape3D.new()
	var tri := ConcavePolygonShape3D.new()
	tri.set_faces(facce)
	forma.shape = tri
	corpo.add_child(forma)
	add_child(corpo)


# ─── 2. Muri ───────────────────────────────────────────────────────────────

const DIREZIONI := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Un muro sta sul bordo fra una cella "dentro" (pavimento o baratro) e una
## vuota. I tratti contigui con la stessa direzione si fondono in una corsa.
func _costruisci_muri() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corpo := StaticBody3D.new()
	corpo.name = "MuriCorpo"
	add_child(corpo)
	var l : float = pianta.lato_cella
	for dir in DIREZIONI:
		var alto : float = profilo.muro_basso if dir == Vector2i(0, 1) else profilo.muro_alto
		## Le corse scorrono lungo l'asse perpendicolare a `dir`.
		var lungo_x : bool = dir.y != 0
		var n_righe : int = pianta.profondita if lungo_x else pianta.larghezza
		var n_col : int = pianta.larghezza if lungo_x else pianta.profondita
		for r in n_righe:
			var inizio := -1
			for k in n_col + 1:
				var c := Vector2i(k, r) if lungo_x else Vector2i(r, k)
				var serve : bool = k < n_col and _dentro(c) and pianta.cella(c + dir) == Pianta.Cella.VUOTO
				if serve and inizio < 0:
					inizio = k
				elif not serve and inizio >= 0:
					var a := Vector2i(inizio, r) if lungo_x else Vector2i(r, inizio)
					var b := Vector2i(k - 1, r) if lungo_x else Vector2i(r, k - 1)
					_corsa(st, corpo, a, b, dir, alto)
					inizio = -1
	if profilo.muro_modulo != null:
		return
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Muri"
	mi.mesh = st.commit()
	mi.material_override = profilo.materiale_muro
	add_child(mi)


func _dentro(c : Vector2i) -> bool:
	return pianta.cella(c) != Pianta.Cella.VUOTO


## Un muro dal bordo della cella `a` al bordo della cella `b`, verso `dir`:
## un parallelepipedo appena fuori dal pavimento.
func _corsa(st : SurfaceTool, corpo : StaticBody3D, a : Vector2i, b : Vector2i, dir : Vector2i, alto : float) -> void:
	var l : float = pianta.lato_cella
	var ca : Vector3 = pianta.centro(a)
	var cb : Vector3 = pianta.centro(b)
	var n := Vector3(dir.x, 0, dir.y)
	var lungo := Vector3(absf(dir.y), 0, absf(dir.x))
	var meta := (ca + cb) * 0.5 + n * (l * 0.5 + SPESSORE_MURO * 0.5)
	var lunghezza := (cb - ca).length() + l + SPESSORE_MURO * 2.0
	var mezzo := lungo * lunghezza * 0.5 + n * SPESSORE_MURO * 0.5
	var minimo := meta - Vector3(absf(mezzo.x), 0, absf(mezzo.z))
	var massimo := meta + Vector3(absf(mezzo.x), alto, absf(mezzo.z))
	if profilo.muro_modulo != null:
		_moduli(meta, lunghezza, n, lungo, alto)
	else:
		_scatola(st, minimo, massimo)
	var forma := CollisionShape3D.new()
	var box := BoxShape3D.new()
	## La collisione e' sempre alta: un muro basso si vede sopra, ma non si
	## scavalca.
	box.size = Vector3(massimo.x - minimo.x, profilo.muro_alto, massimo.z - minimo.z)
	forma.shape = box
	forma.position = Vector3((minimo.x + massimo.x) * 0.5, profilo.muro_alto * 0.5, (minimo.z + massimo.z) * 0.5)
	corpo.add_child(forma)


## Il muro vero: il modulo ripetuto lungo il tratto, col fronte (zoccolo e
## cornice) verso la stanza; sui muri alti, pilastri ai capi e ogni
## `pilastro_ogni` metri. La collisione resta la scatola di `_corsa`.
var _pilastri_messi := {}

func _moduli(meta : Vector3, lunghezza : float, n : Vector3, lungo : Vector3, alto : float) -> void:
	var quanti := maxi(1, roundi(lunghezza / profilo.muro_modulo_lungo))
	var passo := lunghezza / quanti
	var verso := atan2(-n.x, -n.z)
	var inizio := meta - lungo * lunghezza * 0.5
	for i in quanti:
		var m : Node3D = profilo.muro_modulo.instantiate()
		add_child(m)
		var box := Misura.ingombro(m)
		m.scale = Vector3(passo / box.size.x * 1.02, alto / box.size.y, SPESSORE_MURO * 1.6 / box.size.z)
		m.rotation.y = verso
		m.position = inizio + lungo * passo * (i + 0.5)
	## Niente pilastri sui tratti corti: i cerchi e le forme irregolari fanno
	## scalini, e un pilastro per scalino e' una palizzata.
	if profilo.pilastro == null or alto < profilo.muro_alto or lunghezza < pianta.lato_cella * 3.0:
		return
	var quanti_p := maxi(1, roundi(lunghezza / profilo.pilastro_ogni))
	for i in quanti_p + 1:
		var p := inizio + lungo * (lunghezza * i / quanti_p) - n * 0.15
		var chiave := Vector2i(roundi(p.x * 2.0), roundi(p.z * 2.0))
		if _pilastri_messi.has(chiave):
			continue
		_pilastri_messi[chiave] = true
		var pil : Node3D = profilo.pilastro.instantiate()
		add_child(pil)
		var bp := Misura.ingombro(pil)
		var s := 0.9 / maxf(bp.size.x, bp.size.z)
		pil.scale = Vector3(s, (alto + 0.3) / bp.size.y, s)
		pil.position = p


## Le cinque facce visibili di una scatola (la base no), con UV nel mondo.
func _scatola(st : SurfaceTool, mn : Vector3, mx : Vector3) -> void:
	var v := [
		Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)]
	var facce := [
		[[4, 5, 6, 7], Vector3.UP],
		[[3, 2, 6, 7], Vector3.BACK],
		[[1, 0, 4, 5], Vector3.FORWARD],
		[[2, 1, 5, 6], Vector3.RIGHT],
		[[0, 3, 7, 4], Vector3.LEFT]]
	for f in facce:
		var idx : Array = f[0]
		var nn : Vector3 = f[1]
		var q : Array[Vector3] = []
		for i in idx:
			q.append(v[i])
		## Ordine dei vertici: si orienta la faccia verso la sua normale.
		var giusta := (q[1] - q[0]).cross(q[2] - q[0]).dot(nn) < 0.0
		var ordine := [0, 1, 2, 0, 2, 3] if giusta else [0, 2, 1, 0, 3, 2]
		for i in ordine:
			var p : Vector3 = q[i]
			st.set_normal(nn)
			var uv := Vector2(p.x + p.z, p.y) if absf(nn.y) < 0.5 else Vector2(p.x, p.z)
			st.set_uv(uv)
			st.add_vertex(p)


## Le luci: una luce di riempimento debole per stanza, in alto al centro, e
## le TORCE sui muri alti (nord, est, ovest: quelli che la camera vede in
## faccia), lontane dalle porte e distanziate fra loro.
func _costruisci_luci() -> void:
	for i in pianta.stanze.size():
		var r : Rect2i = pianta.stanze[i]["rect"]
		var luce := OmniLight3D.new()
		luce.name = "LuceStanza"
		luce.light_color = profilo.luce_stanza_colore
		luce.light_energy = profilo.luce_stanza_energia
		luce.omni_range = Vector2(r.size).length() * pianta.lato_cella * 0.6
		luce.omni_attenuation = 1.2
		luce.position = pianta.centro(r.position + r.size / 2) + Vector3(0, profilo.muro_alto + 0.8, 0)
		add_child(luce)
		if profilo.torcia != null:
			_torce_della_stanza(i)


func _torce_della_stanza(i : int) -> void:
	var posti : Array = []
	for c in pianta.celle_di(i):
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if pianta.cella(c + d) == Pianta.Cella.VUOTO and pianta.camminabile(c) and not pianta._vicino_a_porta(c, 1):
				posti.append([c, d])
	var quante := _rng.randi_range(profilo.torce_per_stanza_min, profilo.torce_per_stanza_max)
	var messe : Array[Vector2i] = []
	for k in 40:
		if messe.size() >= quante or posti.is_empty():
			break
		var scelto : Array = posti[_rng.randi_range(0, posti.size() - 1)]
		var c : Vector2i = scelto[0]
		var lontana := true
		for m in messe:
			if Vector2(m - c).length() < 3.0:
				lontana = false
		if not lontana:
			continue
		messe.append(c)
		var d : Vector2i = scelto[1]
		var n := Vector3(d.x, 0, d.y)
		var torcia : Node3D = profilo.torcia.instantiate()
		add_child(torcia)
		var box := Misura.ingombro(torcia)
		var s := 0.75 / box.size.y
		torcia.scale = Vector3.ONE * s
		torcia.rotation.y = atan2(-n.x, -n.z)
		torcia.position = pianta.centro(c) + n * (pianta.lato_cella * 0.5 - 0.02) + Vector3(0, 1.9, 0)
		## La fiamma sulla testa della torcia, che sporge un po' verso la stanza.
		var f := Fuoco.new()
		f.colore = profilo.luce_fuoco_colore
		f.energia = profilo.luce_fuoco_energia
		f.portata = profilo.luce_fuoco_portata
		f.grandezza = 0.8
		f.sfasamento = _rng.randf()
		f.position = torcia.position - n * (box.size.z * s * 0.35) + Vector3(0, box.size.y * s * 0.95, 0)
		add_child(f)


# ─── 3. Il vuoto sotto i baratri, e la zona di caduta ──────────────────────

func _costruisci_vuoto() -> void:
	var lato : float = maxf(pianta.larghezza, pianta.profondita) * pianta.lato_cella + 20.0
	var zona := Area3D.new()
	zona.name = "ZonaCaduta"
	zona.monitorable = false
	zona.collision_mask = 0xFFFF
	var forma := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(lato, 4.0, lato)
	forma.shape = box
	zona.add_child(forma)
	zona.position = Vector3(0, QUOTA_CADUTA, 0)
	zona.body_entered.connect(_su_caduta)
	add_child(zona)
	## Il fondo: nero, lontano. Si vede solo guardando dentro un baratro.
	var fondo := MeshInstance3D.new()
	fondo.name = "Abisso"
	var pm := PlaneMesh.new()
	pm.size = Vector2(lato, lato)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 0.0, 0.0)
	pm.material = mat
	fondo.mesh = pm
	fondo.position = Vector3(0, -14.0, 0)
	add_child(fondo)


func _su_caduta(corpo : Node3D) -> void:
	if corpo.is_in_group("nemico_dungeon"):
		var hs = corpo.get("health_system")
		if hs != null and hs.has_method("apply_damage"):
			hs.apply_damage(1.0e9, "FISICO")
		return
	if corpo.is_in_group("player") and corpo.has_method("interact"):
		print("DUNGEON: il giocatore e' caduto nel baratro: match perso")
		caduto.emit()


# ─── 4. Porte e archi ──────────────────────────────────────────────────────

func _costruisci_porte() -> void:
	var l : float = pianta.lato_cella
	for p in pianta.porte:
		var celle : Array = p["celle"]
		var normale : Vector2i = p["normale"]
		var somma := Vector3.ZERO
		for coppia in celle:
			somma += (pianta.centro(coppia[0]) + pianta.centro(coppia[1])) * 0.5
		var centro := somma / celle.size()
		var largo : float = celle.size() * l
		## L'asse della porta: lungo il muro.
		var ruota := 0.0 if normale.y != 0 else PI * 0.5
		if p["chiusa"]:
			var porta := Porta.new()
			porta.name = "Porta"
			porta.scena = profilo.porta
			porta.larghezza = largo
			porta.altezza = profilo.muro_alto * 0.95
			porta.position = centro
			porta.rotation.y = ruota
			porta.guida = guida
			for coppia in celle:
				porta.attraversamenti.append([coppia[0], coppia[1]])
			add_child(porta)
		elif normale != Vector2i(0, 1) and profilo.arco != null:
			## Un arco sul varco; non su quelli fra la stanza e la camera, dove
			## il muro e' basso.
			## Senza collisione: la scatola del suo ingombro chiuderebbe il varco
			## (playtest inseguimento_dungeon, 2026-10-20). Ai lati ci sono i muri.
			var arco := _pezzo(profilo.arco, largo + 1.2, profilo.muro_alto + 0.6, "larghezza", false)
			arco.position = centro
			arco.rotation.y = ruota
			arco.name = "Arco"


# ─── 5. Trappole, forzieri, arredo ─────────────────────────────────────────

func _costruisci_trappole() -> void:
	for c in pianta.trappole:
		var t := Trappola.new()
		t.name = "Trappola"
		t.scena = profilo.trappola
		t.lato = pianta.lato_cella * 0.9
		t.position = pianta.centro(c)
		t.sfasamento = _rng.randf() * 2.0
		add_child(t)


func _costruisci_forzieri() -> void:
	for f in pianta.forzieri:
		var c : Vector2i = f["cella"]
		var fz := Forziere.new()
		fz.name = "ForziereRaro" if f["raro"] else "Forziere"
		var comuni : Array = profilo.forzieri
		fz.scena = profilo.forziere_raro if f["raro"] or comuni.is_empty() 			else comuni[_rng.randi_range(0, comuni.size() - 1)]
		fz.raro = f["raro"]
		fz.position = pianta.centro(c)
		## Con la schiena al muro piu' vicino.
		fz.rotation.y = _verso_il_centro(c, f["stanza"])
		fz.aperto.connect(func(raro): forziere_aperto.emit(raro))
		add_child(fz)
		guida.ostacolo(c)


func _verso_il_centro(c : Vector2i, i : int) -> float:
	var centro : Vector3 = pianta.centro(pianta.stanze[i]["centro"])
	var d : Vector3 = centro - pianta.centro(c)
	return atan2(d.x, d.z)


## L'arredo: rovine sparse che danno carattere senza chiudere i passaggi.
## Colonne agli angoli delle stanze grandi, un cono in qualche centro,
## macerie, lastre e sassi sul pavimento libero.
func _costruisci_arredo() -> void:
	var occupate := {}
	for n in pianta.nemici:
		occupate[n["cella"]] = true
	for f in pianta.forzieri:
		occupate[f["cella"]] = true
	for c in pianta.trappole:
		occupate[c] = true
	occupate[pianta.ingresso] = true
	for i in pianta.stanze.size():
		var r : Rect2i = pianta.stanze[i]["rect"]
		## Colonne negli angoli (una cella dentro), nelle stanze ampie.
		if pianta.stanze[i]["forma"] == Pianta.Forma.RETTANGOLO and mini(r.size.x, r.size.y) >= 6 and profilo.colonna != null:
			for ang in [r.position + Vector2i(1, 1), Vector2i(r.end.x - 2, r.position.y + 1),
					Vector2i(r.position.x + 1, r.end.y - 2), r.end - Vector2i(2, 2)]:
				if pianta.stanza(ang) == i and pianta.camminabile(ang) and not occupate.has(ang) and _rng.randf() < 0.7:
					var col := _pezzo(profilo.colonna if _rng.randf() < 0.6 else profilo.cono, 0.0, profilo.muro_alto + 1.6, "altezza")
					col.position = pianta.centro(ang)
					occupate[ang] = true
					guida.ostacolo(ang)
		## Un braciere nelle stanze grandi (due nelle grandissime).
		if profilo.braciere != null and mini(r.size.x, r.size.y) >= profilo.braciere_stanza_min:
			var n_b := 2 if mini(r.size.x, r.size.y) >= profilo.braciere_stanza_min + 2 else 1
			for k in n_b:
				var c := Vector2i(_rng.randi_range(r.position.x + 2, r.end.x - 3), _rng.randi_range(r.position.y + 2, r.end.y - 3))
				if pianta.stanza(c) != i or not pianta.camminabile(c) or occupate.has(c) or pianta._vicino_a_porta(c, 2):
					continue
				occupate[c] = true
				var b := _pezzo(profilo.braciere, 1.0, 0.0, "larghezza")
				b.position = pianta.centro(c)
				guida.ostacolo(c)
				var h := Misura.ingombro(b).size.y * b.scale.y
				var f := Fuoco.new()
				f.colore = profilo.luce_fuoco_colore
				f.energia = profilo.luce_fuoco_energia * 1.3
				f.portata = profilo.luce_fuoco_portata * 1.2
				f.grandezza = 2.0
				f.sfasamento = _rng.randf()
				f.position = b.position + Vector3(0, h, 0)
				add_child(f)
		## Rovine sparse.
		var quante := _rng.randi_range(1, 3)
		for k in quante:
			var c := Vector2i(_rng.randi_range(r.position.x + 1, r.end.x - 2), _rng.randi_range(r.position.y + 1, r.end.y - 2))
			if pianta.stanza(c) != i or not pianta.camminabile(c) or occupate.has(c) or pianta._vicino_a_porta(c, 1):
				continue
			occupate[c] = true
			var tiro := _rng.randf()
			var pezzo : Node3D
			if tiro < 0.3 and profilo.colonna_caduta != null:
				pezzo = _pezzo(profilo.colonna_caduta, 2.4, 0.0, "larghezza")
			elif tiro < 0.55 and profilo.macerie != null:
				pezzo = _pezzo(profilo.macerie, 2.0, 0.0, "larghezza")
			elif profilo.lastre != null:
				pezzo = _pezzo(profilo.lastre, 2.2, 0.0, "larghezza")
			if pezzo != null:
				pezzo.position = pianta.centro(c)
				pezzo.rotation.y = _rng.randf() * TAU
				## Chi ha corpo occupa la cella: la guida ci gira intorno.
				if pezzo.find_children("*", "StaticBody3D", true, false).size() > 0:
					guida.ostacolo(c)
	## Sassi lungo i muri, ovunque: rompono la linea dritta della pietra.
	if profilo.sasso != null:
		for z in pianta.profondita:
			for x in pianta.larghezza:
				var c := Vector2i(x, z)
				if not pianta.camminabile(c) or occupate.has(c) or _rng.randf() > 0.06:
					continue
				var al_muro := false
				for d in DIREZIONI:
					if pianta.cella(c + d) == Pianta.Cella.VUOTO:
						al_muro = true
				if not al_muro:
					continue
				var s := _pezzo(profilo.sasso, 0.4 + _rng.randf() * 0.5, 0.0, "larghezza")
				s.position = pianta.centro(c) + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
				s.rotation = Vector3(_rng.randf() * 0.5, _rng.randf() * TAU, _rng.randf() * 0.5)
				if s.find_children("*", "StaticBody3D", true, false).size() > 0:
					guida.ostacolo(c)


## Un pezzo d'arredo, scalato alla misura voluta sull'ingombro reale (come fa
## arena_builder): "larghezza" scala uniforme sul lato maggiore in pianta,
## "altezza" sull'altezza.
func _pezzo(scena : PackedScene, larghezza : float, altezza : float, modo : String, solido : bool = true) -> Node3D:
	var n : Node3D = scena.instantiate()
	add_child(n)
	var box := Misura.ingombro(n)
	var s := 1.0
	if modo == "altezza" and box.size.y > 0.0:
		s = altezza / box.size.y
	elif box.size.x > 0.0 or box.size.z > 0.0:
		s = larghezza / maxf(box.size.x, box.size.z)
	n.scale = Vector3.ONE * s
	if modo == "larghezza" and altezza > 0.0 and box.size.y > 0.0:
		n.scale.y = altezza / box.size.y
	## Collisione semplice: una scatola sull'ingombro, se il pezzo e' alto
	## abbastanza da essere un ostacolo.
	if solido and box.size.y * n.scale.y > 0.5:
		var corpo := StaticBody3D.new()
		var forma := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = box.size * 0.85
		forma.shape = b
		forma.position = box.get_center()
		corpo.add_child(forma)
		n.add_child(corpo)
	return n



# ─── 6. Nemici ─────────────────────────────────────────────────────────────

func _costruisci_nemici() -> void:
	_nemici_vivi = 0
	for n in pianta.nemici:
		var scene : Array = profilo.nemici
		if scene.is_empty():
			return
		var ps : PackedScene = scene[clampi(n["tipo"], 0, scene.size() - 1)]
		var e : Node3D = ps.instantiate()
		e.position = pianta.centro(n["cella"]) + Vector3(0, 0.1, 0)
		e.rotation.y = _rng.randf() * TAU
		e.add_to_group("nemico_dungeon")
		add_child(e)
		_nemici_vivi += 1
		if e.has_signal("death_started"):
			e.death_started.connect(_su_nemico_morto, CONNECT_ONE_SHOT)


func _su_nemico_morto() -> void:
	_nemici_vivi -= 1
	_aggiorna_contatore()
	if _nemici_vivi <= 0:
		print("DUNGEON: tutti i nemici eliminati")
		ripulito.emit()


func nemici_vivi() -> int:
	return _nemici_vivi


# ─── 7. Il giocatore ───────────────────────────────────────────────────────

func _porta_giocatore() -> void:
	if giocatore.is_empty():
		return
	var g := get_node_or_null(giocatore) as Node3D
	if g != null:
		g.global_position = pianta.centro(pianta.ingresso) + Vector3(0, 0.2, 0)


func _costruisci_nebbia() -> void:
	nebbia = null
	var g := get_node_or_null(giocatore) as Node3D if not giocatore.is_empty() else null
	if not nebbia_attiva or g == null:
		return
	nebbia = Nebbia.new()
	nebbia.name = "Nebbia"
	nebbia.pianta = pianta
	nebbia.guida = guida
	nebbia.giocatore = g
	add_child(nebbia)
	nebbia.prepara(self)


func _costruisci_contatore() -> void:
	var strato := CanvasLayer.new()
	strato.layer = 50
	_contatore = Label.new()
	_contatore.anchor_left = 0.5
	_contatore.anchor_right = 0.5
	_contatore.position = Vector2(-120, 14)
	_contatore.size = Vector2(240, 30)
	_contatore.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contatore.add_theme_font_size_override("font_size", 22)
	_contatore.add_theme_color_override("font_outline_color", Color.BLACK)
	_contatore.add_theme_constant_override("outline_size", 6)
	strato.add_child(_contatore)
	add_child(strato)
	_aggiorna_contatore()


func _aggiorna_contatore() -> void:
	if _contatore != null:
		_contatore.text = "Nemici rimasti: %d" % _nemici_vivi if _nemici_vivi > 0 else "Dungeon ripulito"
