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
const Piastra := preload("res://arcanium/levels/dungeon/trappola_piastra.gd")
const Forziere := preload("res://arcanium/levels/dungeon/forziere_dungeon.gd")
const Fuoco := preload("res://arcanium/levels/dungeon/fuoco_dungeon.gd")
const Nebbia := preload("res://arcanium/levels/dungeon/nebbia_dungeon.gd")
const PezzoTema := preload("res://arcanium/levels/dungeon/pezzo_tema.gd")
const FineScontro := preload("res://arcanium/ui/fine_scontro/fine_scontro.gd")
const PerkRivincita := preload("res://arcanium/systems/perk_rivincita.gd")

signal ripulito
signal caduto
signal forziere_aperto(raro : bool)
## Obiettivo USCITA: il giocatore ha preso la scala.
signal uscito
## La run finisce qui (sconfitta, «Abbandona»).
signal abbandonato

@export var profilo : Resource
## Il seme del dungeon; -1 ne tira uno a caso.
@export var seme : int = -1
## Il giocatore da portare all'ingresso (vuoto: nessuno).
@export var giocatore : NodePath
## Costruisce da solo all'avvio della scena.
@export var costruisci_subito : bool = true
## Mostra il contatore dei nemici rimasti.
@export var mostra_contatore : bool = true
## Cosa chiede lo scontro (pianta_dungeon.gd, Obiettivo): -1 lo decide il
## seme, 0 ripulire, 1 trovare l'uscita.
@export_range(-1, 1) var obiettivo : int = -1
## La schermata di vittoria/sconfitta a fine scontro (fine_scontro.gd).
@export var mostra_fine : bool = true
## Nebbia di guerra: si vede solo cio' che il giocatore ha in vista.
@export var nebbia_attiva : bool = true

var pianta : RefCounted
var guida : Node
var nebbia : Node
## Il tema di ogni stanza (tema_stanza.gd), o null: rovine.
var temi_stanze : Array = []
var _nemici_vivi := 0
var _contatore : Label
var _rng := RandomNumberGenerator.new()

const QUOTA_CADUTA := -6.0
const SPESSORE_MURO := 0.4


## Il seme da usare alla prossima costruzione, anche dopo aver ricaricato la
## scena (la schermata di fine: «Riprova» lo stesso, «Nuovo» un altro). -2:
## nessuno, vale l'export.
static var _prossimo_seme := -2
## Il perk della rivincita attivo (perk_rivincita.gd), "" nessuno: passa da
## una ricarica della scena all'altra come il seme.
static var perk_attivo := ""

var _finito := false
var _tempo := 0.0
var _nemici_tot := 0
var _forzieri_aperti := 0
var _seme_usato := 0


func _ready() -> void:
	ripulito.connect(_su_ripulito)
	uscito.connect(func(): _fine(true, "Hai trovato l'uscita"))
	caduto.connect(func(): _fine(false, "Sei precipitato nel baratro"))
	forziere_aperto.connect(_su_forziere)
	if costruisci_subito:
		costruisci()


func _process(delta : float) -> void:
	if not _finito:
		_tempo += delta


func costruisci() -> void:
	## Fuori dall'albero subito, liberati a fine frame: finche' restano figli,
	## gruppi e ricerche (nemici, guida, nebbia) li vedrebbero insieme ai nuovi.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	## Ricostruire deve dare lo stesso dungeon di una costruzione da zero: lo
	## stato fra una volta e l'altra si azzera qui (i pilastri gia' messi
	## restavano, e il secondo dungeon usciva diverso dal primo).
	_pilastri_messi.clear()
	_nemici_vivi = 0
	var s := seme if seme >= 0 else randi() % 1000000
	if _prossimo_seme != -2:
		s = _prossimo_seme if _prossimo_seme >= 0 else randi() % 1000000
		_prossimo_seme = -2
	_seme_usato = s
	_finito = false
	_tempo = 0.0
	_forzieri_aperti = 0
	pianta = Pianta.new()
	pianta.genera(profilo, s, obiettivo)
	_rng.seed = s + 7919
	print("DUNGEON: seme %d, %d stanze, %d porte (%d chiuse), %d nemici, %d forzieri, %d trappole" % [
		s, pianta.stanze.size(), pianta.porte.size(),
		pianta.porte.filter(func(p): return p["chiusa"]).size(),
		pianta.nemici.size(), pianta.forzieri.size(), pianta.trappole.size()])
	guida = Guida.new()
	guida.name = "Guida"
	guida.pianta = pianta
	add_child(guida)
	_scegli_temi()
	_prepara_rilievo(s)
	_costruisci_pavimento()
	_costruisci_decal()
	_costruisci_muri()
	_costruisci_luci()
	_costruisci_vuoto()
	_costruisci_acqua()
	_costruisci_uscita()
	_costruisci_porte()
	_costruisci_trappole()
	_costruisci_piastre()
	_costruisci_forzieri()
	_costruisci_arredo()
	_adagia_sul_rilievo()
	_costruisci_nemici()
	_porta_giocatore()
	_nemici_tot = _nemici_vivi
	_costruisci_nebbia()
	PerkRivincita.applica(perk_attivo, get_node_or_null(giocatore) if not giocatore.is_empty() else null, self)
	if mostra_contatore:
		_costruisci_contatore()


# ─── 0. Temi ───────────────────────────────────────────────────────────────

## Ogni stanza prende un tema compatibile col suo ruolo, a peso; un tema gia'
## usato pesa un quarto, cosi' in un dungeon se ne vedono il piu' possibile.
func _scegli_temi() -> void:
	temi_stanze.clear()
	var usati := {}
	for i in pianta.stanze.size():
		var ruolo : int = pianta.stanze[i]["ruolo"]
		## La stanza dell'uscita si veste come una di combattimento.
		if ruolo == Pianta.Ruolo.USCITA:
			ruolo = Pianta.Ruolo.COMBATTIMENTO
		var adatti : Array = []
		var pesi : Array[float] = []
		var muri := _celle_al_muro_alto(i)
		for tema in profilo.temi:
			if tema != null and ruolo in tema.ruoli and muri >= tema.muri_minimi:
				adatti.append(tema)
				pesi.append(tema.peso * (0.25 if usati.has(tema) else 1.0))
		var scelto : Resource = null
		if not adatti.is_empty():
			var tot := 0.0
			for w in pesi:
				tot += w
			var tiro := _rng.randf() * tot
			for k in adatti.size():
				tiro -= pesi[k]
				if tiro <= 0.0 or k == adatti.size() - 1:
					scelto = adatti[k]
					break
			usati[scelto] = true
		temi_stanze.append(scelto)


## Quante celle della stanza hanno un muro alto alle spalle (nord, est,
## ovest): i posti per scaffali e rastrelliere.
func _celle_al_muro_alto(i : int) -> int:
	var n := 0
	for c in pianta.celle_di(i):
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if pianta.cella(c + d) == Pianta.Cella.VUOTO and not pianta._vicino_a_porta(c, 0):
				n += 1
				break
	return n


func tema_di(i : int) -> Resource:
	return temi_stanze[i] if i >= 0 and i < temi_stanze.size() else null


## Il pavimento di una cella: quello del tema della sua stanza, quello dei
## corridoi, o quello di base.
func _materiale_cella(c : Vector2i) -> Material:
	var i : int = pianta.stanza(c)
	if i < 0:
		return profilo.materiale_corridoio if profilo.materiale_corridoio != null else profilo.materiale_pavimento
	var tema := tema_di(i)
	if tema != null and tema.pavimento != null:
		return tema.pavimento
	return profilo.materiale_pavimento


# ─── 1. Pavimento ──────────────────────────────────────────────────────────

## Lato di un blocco di pavimento, in celle. Il renderer Mobile da' a ogni
## oggetto al massimo 8 luci: un pavimento in un pezzo solo, con le torce di
## tutto il dungeon, ne perderebbe la maggior parte. A blocchi, ognuno riceve
## solo le luci vicine, e quelli fuori schermo non si disegnano.
const BLOCCO := 8

## Il RILIEVO del pavimento (richiesta dell'autore, 2026-10-20: «non teniamo
## tutto tutto piatto»): ondulazioni di pochi centimetri ovunque, e qua e la'
## un rigonfiamento o un avvallamento piu' marcato. Resta sotto la soglia del
## gioco: si cammina, si cade e si combatte come sul piano. Sulle trappole e'
## zero, che la piastra deve stare a filo.
const SUDDIVISIONI := 2
const RILIEVO_FINE := 0.05
const RILIEVO_GROSSO := 0.12
var _rumore_fine := FastNoiseLite.new()
var _rumore_grosso := FastNoiseLite.new()
var _celle_piatte := {}
var _celle_ponte := {}


func _prepara_rilievo(s : int) -> void:
	_rumore_fine.seed = s
	_rumore_fine.frequency = 0.22
	_rumore_grosso.seed = s + 101
	_rumore_grosso.frequency = 0.06
	_celle_piatte.clear()
	_celle_ponte.clear()
	for c in pianta.trappole:
		_celle_piatte[c] = true
	for pz in pianta.piastre:
		_celle_piatte[pz["cella"]] = true
	## Acqua e ponti piatti, e le celle accanto pure: l'orlo dei canali e' a
	## filo dell'acqua.
	for z in pianta.profondita:
		for x in pianta.larghezza:
			if pianta.cella(Vector2i(x, z)) == Pianta.Cella.ACQUA:
				_celle_piatte[Vector2i(x, z)] = true
	for pt in pianta.ponti:
		_celle_ponte[pt["cella"]] = true
		_celle_piatte[pt["cella"]] = true
	if pianta.uscita.x >= 0:
		for dz in [-2, -1, 0, 1, 2]:
			for dx in [-2, -1, 0, 1, 2]:
				_celle_piatte[pianta.uscita + Vector2i(dx, dz)] = true


## Le 3x3 celle della scala: niente pavimento visibile (si vedono i gradini
## che scendono), la collisione resta.
func _sotto_uscita(c : Vector2i) -> bool:
	return pianta.uscita.x >= 0 and absi(c.x - pianta.uscita.x) <= 1 and absi(c.y - pianta.uscita.y) <= 1


func altezza_pavimento(x : float, z : float) -> float:
	## Un vertice sul bordo di una cella piatta e' piatto anche per la vicina.
	var l : float = pianta.lato_cella
	var o : Vector3 = pianta.origine()
	var gx := (x + o.x) / l
	var gz := (z + o.z) / l
	for dz in [-0.001, 0.001]:
		for dx in [-0.001, 0.001]:
			if _celle_piatte.has(Vector2i(floori(gx + dx), floori(gz + dz))):
				return 0.0
	var h := _rumore_fine.get_noise_2d(x, z) * RILIEVO_FINE
	## Il rumore grosso conta solo dove e' forte: macchie rare, non un mare mosso.
	var g := _rumore_grosso.get_noise_2d(x, z)
	h += signf(g) * smoothstep(0.35, 0.75, absf(g)) * RILIEVO_GROSSO
	return h


## Porta alla quota del rilievo tutto cio' che sta sul pavimento (arredo,
## forzieri, bracieri e le loro fiamme, trappole). Muri, pilastri, archi e
## porte stanno sui bordi e restano dove sono; i nemici li sistema la fisica.
func _adagia_sul_rilievo() -> void:
	var fermi := ["muro_modulo", "pilastro", "arch", "porta_dungeon", "torcia"]
	for c in get_children():
		if not (c is Node3D) or c is Light3D or c.is_in_group("nemico_dungeon"):
			continue
		var nome : String = String(c.name)
		if nome.begins_with("Pavimento") or nome.begins_with("Muri") or nome in ["Abisso", "ZonaCaduta", "Porta", "Arco"]:
			continue
		var scena : String = c.scene_file_path.get_file().get_basename()
		if scena in fermi:
			continue
		var n3 := c as Node3D
		n3.position.y += altezza_pavimento(n3.position.x, n3.position.z) - 0.02


func _normale_pavimento(x : float, z : float) -> Vector3:
	const E := 0.05
	var dx := altezza_pavimento(x + E, z) - altezza_pavimento(x - E, z)
	var dz := altezza_pavimento(x, z + E) - altezza_pavimento(x, z - E)
	return Vector3(-dx, 2.0 * E, -dz).normalized()


# ─── 3-ter. L'uscita (obiettivo USCITA) ───────────────────────────────────

var _uscito := false

## La scala che scende sotto l'arco runico, sulle 3x3 celle dell'uscita: un
## chiarore freddo dalle rune la segnala appena entra in vista, e chi ci
## mette piede ha vinto. I nemici non ci camminano (la guida la gira).
func _costruisci_uscita() -> void:
	_uscito = false
	if pianta.uscita.x < 0:
		return
	var c : Vector2i = pianta.uscita
	var l : float = pianta.lato_cella
	var centro : Vector3 = pianta.centro(c)
	if profilo.uscita != null:
		var u := _pezzo(profilo.uscita, l * 3.0 * 0.92, 0.0, "larghezza", false)
		## La scala scende: la base del modello e' il fondo dei gradini, e il
		## bordo deve stare appena sopra il pavimento.
		u.position = centro + Vector3(0, -profilo.uscita_affondo, 0)
		## L'arco dal lato del muro piu' lontano dalla camera: a nord.
		u.rotation.y = profilo.uscita_rotazione
		u.name = "Uscita"
	var chiarore := OmniLight3D.new()
	chiarore.name = "LuceUscita"
	chiarore.light_color = Color(0.4, 0.6, 1.0)
	chiarore.light_energy = 2.4
	chiarore.omni_range = 10.0
	chiarore.omni_attenuation = 1.3
	chiarore.position = centro + Vector3(0, 2.2, -l * 0.8)
	add_child(chiarore)
	var area := Area3D.new()
	area.name = "AreaUscita"
	area.collision_layer = 0
	area.collision_mask = 2
	var forma := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(l * 1.2, 2.0, l * 1.2)
	forma.shape = b
	area.add_child(forma)
	area.position = centro + Vector3(0, 1.0, 0)
	area.body_entered.connect(_su_uscita)
	add_child(area)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			guida.ostacolo(c + Vector2i(dx, dz))


func _su_uscita(corpo : Node3D) -> void:
	if _uscito or giocatore.is_empty() or corpo != get_node_or_null(giocatore):
		return
	_uscito = true
	_aggiorna_contatore()
	uscito.emit()


# ─── 3-bis. L'acqua: fontane e canali ─────────────────────────────────────

const ACQUA_QUOTA := 0.07
const LETTO_QUOTA := -0.35
const Acqua := preload("res://arcanium/levels/dungeon/acqua_dungeon.gd")
const AcquaShader := preload("res://arcanium/levels/dungeon/acqua_dungeon.gdshader")

## Il letto dei canali (un poco piu' giu', visto attraverso l'acqua), le
## sponde, la superficie che scorre, l'area che rallenta; poi le fontane e i
## ponti. La collisione resta quella del pavimento, a filo: si guada.
func _costruisci_acqua() -> void:
	var celle : Array[Vector2i] = []
	for z in pianta.profondita:
		for x in pianta.larghezza:
			var c := Vector2i(x, z)
			if pianta.cella(c) == Pianta.Cella.ACQUA or _celle_ponte.has(c) or _sotto_uscita(c):
				celle.append(c)
	if celle.is_empty():
		return
	var l : float = pianta.lato_cella
	var letto := SurfaceTool.new()
	letto.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sponde := SurfaceTool.new()
	sponde.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pelo := SurfaceTool.new()
	pelo.begin(Mesh.PRIMITIVE_TRIANGLES)
	var area : Area3D = Acqua.new()
	area.name = "Acqua"
	for c in celle:
		var o : Vector3 = pianta.centro(c) - Vector3(l * 0.5, 0.0, l * 0.5)
		_quad(letto, o + Vector3(0, LETTO_QUOTA, 0), Vector3(l, 0, 0), Vector3(0, 0, l), Vector3.UP)
		_quad(pelo, o + Vector3(0, ACQUA_QUOTA, 0), Vector3(l, 0, 0), Vector3(0, 0, l), Vector3.UP)
		## Le pareti del canale verso il pavimento asciutto, e un cordolo di
		## pietra sull'orlo.
		for d in DIREZIONI:
			var q : Vector2i = c + d
			if pianta.cella(q) == Pianta.Cella.ACQUA or _celle_ponte.has(q):
				continue
			var n := Vector3(d.x, 0, d.y)
			var lato := Vector3(-n.z, 0, n.x)
			var mezzo : Vector3 = pianta.centro(c) + n * l * 0.5
			var a : Vector3 = mezzo - lato * l * 0.5
			_quad(sponde, a + Vector3(0, LETTO_QUOTA, 0), lato * l, Vector3(0, -LETTO_QUOTA + 0.12, 0), -n)
			var p1 : Vector3 = mezzo - lato * l * 0.5 - n * 0.12
			var p2 : Vector3 = mezzo + lato * l * 0.5 + n * 0.08 + Vector3(0, 0.14, 0)
			_scatola(sponde, Vector3(minf(p1.x, p2.x), 0.0, minf(p1.z, p2.z)),
					Vector3(maxf(p1.x, p2.x), 0.14, maxf(p1.z, p2.z)))
		if pianta.cella(c) == Pianta.Cella.ACQUA:
			var forma := CollisionShape3D.new()
			var b := BoxShape3D.new()
			b.size = Vector3(l * 0.9, 1.2, l * 0.9)
			forma.shape = b
			forma.position = pianta.centro(c) + Vector3(0, 0.6, 0)
			area.add_child(forma)
	for k in [[letto, _materiale_cella(celle[0]), "LettoAcqua"], [sponde, profilo.materiale_muro, "Sponde"]]:
		var st : SurfaceTool = k[0]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = k[2]
		mi.mesh = st.commit()
		mi.material_override = k[1]
		add_child(mi)
	var acqua := MeshInstance3D.new()
	acqua.name = "PeloAcqua"
	acqua.mesh = pelo.commit()
	var mat := ShaderMaterial.new()
	mat.shader = AcquaShader
	var crespe := NoiseTexture2D.new()
	crespe.seamless = true
	crespe.as_normal_map = true
	crespe.bump_strength = 6.0
	crespe.noise = FastNoiseLite.new()
	crespe.noise.frequency = 0.02
	mat.set_shader_parameter("crespe", crespe)
	acqua.material_override = mat
	acqua.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(acqua)
	add_child(area)
	## La fontana al centro della vasca, i ponti sui canali.
	for f in pianta.fontane:
		if profilo.fontana == null:
			break
		var fo := _pezzo(profilo.fontana, l * 3.0 * 0.95, 0.0, "larghezza", true)
		fo.position = pianta.centro(f["cella"])
		fo.rotation.y = _rng.randf() * TAU
		fo.name = "Fontana"
		## La fontana e' una fonte di luce a se': l'acqua incantata da' un
		## chiarore freddo, l'unico non di fuoco del dungeon.
		var chiarore := OmniLight3D.new()
		chiarore.light_color = Color(0.45, 0.75, 0.85)
		chiarore.light_energy = 1.6
		chiarore.omni_range = 9.0
		chiarore.omni_attenuation = 1.4
		chiarore.position = fo.position + Vector3(0, 1.2, 0)
		add_child(chiarore)
	for pt in pianta.ponti:
		if profilo.ponticello == null:
			break
		var po := _pezzo(profilo.ponticello, l * 1.3, 0.0, "larghezza", false)
		var box := Misura.ingombro(po)
		var d : Vector2i = pt["dir"]
		## Il ponte attraversa il canale: il suo lato lungo va di traverso.
		var lungo_x := box.size.x >= box.size.z
		var attraverso_x := d.y != 0
		po.rotation.y = 0.0 if lungo_x == attraverso_x else PI * 0.5
		po.position = pianta.centro(pt["cella"])
		po.name = "Ponte"
		## Ci si cammina sopra: la collisione e' la forma vera, non una scatola.
		for m in po.find_children("*", "MeshInstance3D", true, false):
			var corpo := StaticBody3D.new()
			var forma := CollisionShape3D.new()
			forma.shape = (m as MeshInstance3D).mesh.create_trimesh_shape()
			corpo.add_child(forma)
			m.add_child(corpo)


func _quad(st : SurfaceTool, a : Vector3, u : Vector3, v : Vector3, n : Vector3) -> void:
	var q := [a, a + u, a + u + v, a + v]
	var ordine := [0, 1, 2, 0, 2, 3] if u.cross(v).dot(n) < 0.0 else [0, 2, 1, 0, 3, 2]
	for i in ordine:
		st.set_normal(n)
		st.set_uv(Vector2(q[i].x + q[i].y, q[i].z + q[i].y))
		st.add_vertex(q[i])


## Crepe, sporco e muschio sul pavimento: decal sparsi, girati e scalati a
## caso, mai sulle trappole (la piastra si deve leggere).
func _costruisci_decal() -> void:
	var tipi : Array = [[profilo.decal_crepe, 0.5, Vector2(1.4, 3.0)],
			[profilo.decal_sporco, 0.35, Vector2(1.6, 3.5)],
			[profilo.decal_muschio, 0.15, Vector2(1.2, 2.6)]]
	var celle : Array[Vector2i] = []
	for z in pianta.profondita:
		for x in pianta.larghezza:
			var c := Vector2i(x, z)
			if pianta.camminabile(c) and not _celle_piatte.has(c):
				celle.append(c)
	if celle.is_empty() or profilo.decal_ogni_celle <= 0.0:
		return
	var quanti := int(celle.size() / profilo.decal_ogni_celle)
	for k in quanti:
		var tiro := _rng.randf()
		var tipo : Array = tipi[0]
		for tp in tipi:
			tiro -= tp[1]
			if tiro <= 0.0:
				tipo = tp
				break
		var lista : Array = tipo[0]
		if lista.is_empty():
			continue
		var c : Vector2i = celle[_rng.randi_range(0, celle.size() - 1)]
		var dec := Decal.new()
		dec.texture_albedo = lista[_rng.randi_range(0, lista.size() - 1)]
		var lato : float = _rng.randf_range(tipo[2].x, tipo[2].y)
		## Alto quanto il rilievo e un po' di piu': proietta solo sul pavimento.
		dec.size = Vector3(lato, 0.6, lato)
		dec.position = pianta.centro(c) + Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
		dec.rotation.y = _rng.randf() * TAU
		dec.modulate = Color(1, 1, 1, _rng.randf_range(0.6, 1.0))
		dec.upper_fade = 0.3
		dec.lower_fade = 0.3
		dec.cull_mask = 1
		add_child(dec)


func _costruisci_pavimento() -> void:
	var blocchi := {}
	var facce := PackedVector3Array()
	var l : float = pianta.lato_cella
	for z in pianta.profondita:
		for x in pianta.larghezza:
			var c := Vector2i(x, z)
			## Sotto l'acqua il pavimento c'e' (si guada), ma non si vede: si
			## vede il letto del canale (_costruisci_acqua). Idem sotto i ponti.
			if pianta.cella(c) == Pianta.Cella.ACQUA or _celle_ponte.has(c) or _sotto_uscita(c):
				var o2 : Vector3 = pianta.centro(c) - Vector3(l * 0.5, 0.0, l * 0.5)
				for v in [o2, o2 + Vector3(l, 0, 0), o2 + Vector3(l, 0, l), o2, o2 + Vector3(l, 0, l), o2 + Vector3(0, 0, l)]:
					facce.append(v)
				continue
			if not pianta.camminabile(c):
				continue
			## Un blocco per materiale: stanze di temi diversi e corridoi hanno
			## pavimenti diversi anche dentro lo stesso blocco.
			var mat := _materiale_cella(c)
			var k := [Vector2i(x / BLOCCO, z / BLOCCO), mat]
			if not blocchi.has(k):
				var nuovo := SurfaceTool.new()
				nuovo.begin(Mesh.PRIMITIVE_TRIANGLES)
				blocchi[k] = nuovo
			var st : SurfaceTool = blocchi[k]
			var o : Vector3 = pianta.centro(c) - Vector3(l * 0.5, 0.0, l * 0.5)
			## Ogni cella in SUDDIVISIONI x SUDDIVISIONI quadrati, coi vertici
			## alzati o abbassati dal rilievo: lo stesso punto del mondo ha la
			## stessa quota in tutte le celle che lo toccano, quindi niente
			## scalini fra una cella e l'altra.
			var passo := l / SUDDIVISIONI
			for sz in SUDDIVISIONI:
				for sx in SUDDIVISIONI:
					var a := o + Vector3(sx * passo, 0, sz * passo)
					var q := [a, a + Vector3(passo, 0, 0), a + Vector3(passo, 0, passo), a + Vector3(0, 0, passo)]
					for i in [0, 1, 2, 0, 2, 3]:
						var v : Vector3 = q[i]
						v.y = altezza_pavimento(v.x, v.z)
						st.set_normal(_normale_pavimento(v.x, v.z))
						st.set_uv(Vector2(v.x, v.z))
						st.add_vertex(v)
						facce.append(v)
	for k in blocchi:
		var st : SurfaceTool = blocchi[k]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = "Pavimento_%d_%d" % [k[0].x, k[0].y]
		mi.mesh = st.commit()
		mi.material_override = k[1]
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
		## Ogni modulo un po' diverso dal vicino: i muri alti con la cima che
		## sale e scende di qualche centimetro (l'occhio smette di contare le
		## ripetizioni). Niente specchio: con la scala negativa la luce gli
		## arriva al rovescio e il modulo esce scuro.
		var alto_m := alto * (_rng.randf_range(0.95, 1.05) if alto >= profilo.muro_alto else 1.0)
		m.scale = Vector3(passo / box.size.x * 1.02, alto_m / box.size.y, SPESSORE_MURO * 1.6 / box.size.z)
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
		var tema := tema_di(i)
		var luce := OmniLight3D.new()
		luce.name = "LuceStanza"
		luce.light_color = tema.luce_colore if tema != null else profilo.luce_stanza_colore
		luce.light_energy = tema.luce_energia if tema != null else profilo.luce_stanza_energia
		luce.omni_range = Vector2(r.size).length() * pianta.lato_cella * 0.6
		luce.omni_attenuation = 1.2
		luce.position = pianta.centro(r.position + r.size / 2) + Vector3(0, profilo.muro_alto + 0.8, 0)
		add_child(luce)
		if profilo.torcia != null and (tema == null or tema.torce):
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


func _costruisci_piastre() -> void:
	var l : float = pianta.lato_cella
	for pz in pianta.piastre:
		var t : Node3D = Piastra.new()
		t.name = "Piastra"
		t.tipo = pz["tipo"]
		t.scena_piastra = profilo.piastra
		t.scena_bocca = profilo.bocca_trappola
		t.lato = l * 0.75
		var d : Vector2i = pz["dir"]
		t.direzione = Vector3(d.x, 0, d.y)
		## La faccia del muro dietro la cella della bocca.
		t.bocca = pianta.centro(pz["bocca"]) - t.direzione * (l * 0.5 - SPESSORE_MURO * 0.5)
		t.position = pianta.centro(pz["cella"])
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
	## Le piastre e la loro linea di tiro fino alla bocca: un barile in mezzo
	## spegnerebbe la trappola.
	for pz in pianta.piastre:
		var q : Vector2i = pz["cella"]
		occupate[q] = true
		var d : Vector2i = -pz["dir"]
		if d != Vector2i.ZERO:
			while q != pz["bocca"]:
				q += d
				occupate[q] = true
	occupate[pianta.ingresso] = true
	## La scala dell'uscita e un giro di celle intorno: ci si deve arrivare
	## senza girare intorno a una rastrelliera.
	if pianta.uscita.x >= 0:
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				occupate[pianta.uscita + Vector2i(dx, dz)] = true
	for i in pianta.stanze.size():
		var r : Rect2i = pianta.stanze[i]["rect"]
		var tema := tema_di(i)
		## Le stanze grandissime senza fontana: un pezzo GROSSO al centro (la
		## testa del colosso, il lampadario caduto), prima di tutto il resto.
		_pezzo_grosso(i, occupate)
		## I pezzi del tema per primi: sono quelli che danno l'identita', e
		## vogliono i posti buoni (il centro, i muri lunghi).
		if tema != null:
			_arredo_del_tema(i, tema, occupate)
		## Colonne negli angoli (una cella dentro), nelle stanze ampie.
		if (tema == null or tema.colonne) and pianta.stanze[i]["forma"] == Pianta.Forma.RETTANGOLO and mini(r.size.x, r.size.y) >= 6 and profilo.colonna != null:
			for ang in [r.position + Vector2i(1, 1), Vector2i(r.end.x - 2, r.position.y + 1),
					Vector2i(r.position.x + 1, r.end.y - 2), r.end - Vector2i(2, 2)]:
				if pianta.stanza(ang) == i and pianta.camminabile(ang) and not occupate.has(ang) and _rng.randf() < 0.7:
					var col := _pezzo(profilo.colonna if _rng.randf() < 0.6 else profilo.cono, 0.0, profilo.muro_alto + 1.6, "altezza")
					col.position = pianta.centro(ang)
					if _occupa(col, [ang]):
						occupate[ang] = true
		## Un braciere nelle stanze grandi (due nelle grandissime).
		if profilo.braciere != null and (tema == null or tema.bracieri) and mini(r.size.x, r.size.y) >= profilo.braciere_stanza_min:
			var n_b := 2 if mini(r.size.x, r.size.y) >= profilo.braciere_stanza_min + 2 else 1
			for k in n_b:
				var c := Vector2i(_rng.randi_range(r.position.x + 2, r.end.x - 3), _rng.randi_range(r.position.y + 2, r.end.y - 3))
				if pianta.stanza(c) != i or not pianta.camminabile(c) or occupate.has(c) or pianta._vicino_a_porta(c, 2):
					continue
				occupate[c] = true
				var b := _pezzo(profilo.braciere, 1.0, 0.0, "larghezza")
				b.position = pianta.centro(c)
				if not _occupa(b, [c]):
					continue
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
		var quante := _rng.randi_range(1, 3) if tema == null else _rng.randi_range(tema.rovine_min, tema.rovine_max)
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
					_occupa(pezzo, [c])
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
					_occupa(s, [c])


## L'arredo che da' l'identita' a una stanza: ogni pezzo del tema al suo
## posto (pezzo_tema.gd). Un pezzo si mette solo se tutte le celle che copre
## sono pavimento libero della stanza, lontano dalle porte: una rastrelliera
## lunga due celle non deve tappare un varco, ne' schiacciare un nemico.
func _arredo_del_tema(i : int, tema : Resource, occupate : Dictionary) -> void:
	var celle : Array = pianta.celle_di(i)
	var fuochi := 0
	for pt in tema.arredo:
		if pt == null or pt.scena == null:
			continue
		var quanti := _rng.randi_range(pt.quanti_min, pt.quanti_max)
		if pt.celle_per_pezzo > 0.0:
			quanti = clampi(pt.quanti_min + int(celle.size() / pt.celle_per_pezzo), pt.quanti_min, pt.quanti_max)
		var posti := _posti_per(i, pt, occupate)
		var messi := 0
		var tentativi := 0
		for posto in posti:
			if messi >= quanti or tentativi >= 40:
				break
			tentativi += 1
			var n := _metti_pezzo_tema(i, pt, posto, occupate)
			if n == null:
				continue
			messi += 1
			if pt.fuoco and fuochi < 2:
				## Al massimo due fiamme di tema per stanza: con le torce e la luce
				## della stanza il renderer Mobile ne regge otto per oggetto.
				fuochi += 1
				var h := Misura.ingombro(n).size.y * n.scale.y
				var f := Fuoco.new()
				f.colore = profilo.luce_fuoco_colore
				f.energia = profilo.luce_fuoco_energia * 0.8
				f.portata = profilo.luce_fuoco_portata * 0.8
				f.grandezza = 0.5
				f.sfasamento = _rng.randf()
				f.position = n.position + Vector3(0, h, 0)
				add_child(f)


func _pezzo_grosso(i : int, occupate : Dictionary) -> void:
	var st : Dictionary = pianta.stanze[i]
	var r : Rect2i = st["rect"]
	if profilo.pezzi_grossi.is_empty() or st["ruolo"] != Pianta.Ruolo.COMBATTIMENTO 			or mini(r.size.x, r.size.y) < profilo.fontana_stanza_min 			or _rng.randf() > profilo.probabilita_pezzo_grosso:
		return
	for f in pianta.fontane:
		if f["stanza"] == i:
			return
	## In ordine casuale, finche' uno ci sta: se il primo non entra (il
	## lampadario e' largo e basso, chiude piu' celle) si prova l'altro.
	var scelte : Array = profilo.pezzi_grossi.duplicate()
	for k in range(scelte.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var tmp = scelte[k]
		scelte[k] = scelte[j]
		scelte[j] = tmp
	for scena in scelte:
		var pt : Resource = PezzoTema.new()
		pt.scena = scena
		pt.posto = PezzoTema.Posto.CENTRO
		pt.larghezza = 5.0 if String(scena.resource_path).contains("lampadario") else 6.0
		pt.solido = true
		var n := _metti_pezzo_tema(i, pt, [st["centro"], _rng.randf() * TAU], occupate)
		if n != null:
			n.name = "PezzoGrosso"
			return


## I posti candidati per un pezzo, gia' mescolati: [cella, rotazione y].
func _posti_per(i : int, pt : Resource, occupate : Dictionary) -> Array:
	var out : Array = []
	var stanza : Dictionary = pianta.stanze[i]
	match pt.posto:
		PezzoTema.Posto.MURO:
			## Mai sui muri a sud: sono bassi, verso la camera.
			for c in pianta.celle_di(i):
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
					if pianta.cella(c + d) == Pianta.Cella.VUOTO:
						out.append([c, atan2(-float(d.x), -float(d.y)), d])
		PezzoTema.Posto.CENTRO:
			out.append([stanza["centro"], 0.0])
		PezzoTema.Posto.ANGOLO:
			for c in pianta.celle_di(i):
				var vuoti := 0
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
					if pianta.cella(c + d) == Pianta.Cella.VUOTO:
						vuoti += 1
				if vuoti >= 2:
					out.append([c, _verso_il_centro(c, i)])
		PezzoTema.Posto.SPARSO:
			for c in pianta.celle_di(i):
				out.append([c, _rng.randf() * TAU])
		PezzoTema.Posto.FILE:
			## Due file lungo il lato lungo dell'ingombro, a un terzo e a due
			## terzi del lato corto; i pezzi paralleli fra loro.
			var r : Rect2i = stanza["rect"]
			var lungo_x := r.size.x >= r.size.y
			var corto := r.size.y if lungo_x else r.size.x
			var lungo := r.size.x if lungo_x else r.size.y
			for fila in [corto / 3, corto - 1 - corto / 3]:
				for k in range(2, lungo - 2, 3):
					var c := r.position + (Vector2i(k, fila) if lungo_x else Vector2i(fila, k))
					out.append([c, 0.0 if lungo_x else PI * 0.5, null, true])
	if pt.posto != PezzoTema.Posto.FILE:
		## Col generatore del dungeon, non con shuffle(): quello usa il caso
		## globale, e lo stesso seme dava ogni volta un arredo diverso (e un
		## playtest che passava o no a seconda del lancio).
		for k in range(out.size() - 1, 0, -1):
			var j := _rng.randi_range(0, k)
			var tmp = out[k]
			out[k] = out[j]
			out[j] = tmp
	return out


## Mette un pezzo del tema in un posto, se ci sta. Ritorna il pezzo o null.
func _metti_pezzo_tema(i : int, pt : Resource, posto : Array, occupate : Dictionary) -> Node3D:
	var c : Vector2i = posto[0]
	if pianta.stanza(c) != i or not pianta.camminabile(c) or occupate.has(c) or c == pianta.ingresso:
		return null
	var n := _pezzo(pt.scena, pt.larghezza, pt.altezza,
			"larghezza" if pt.larghezza > 0.0 else "altezza", pt.solido)
	var box := Misura.ingombro(n)
	var rot : float = posto[1]
	## Nelle file il lato lungo del pezzo va di traverso alle file; chi deve
	## mostrare la faccia guarda invece la camera.
	if posto.size() > 3 and pt.verso_camera:
		rot = 0.0
	elif posto.size() > 3 and box.size.x < box.size.z:
		rot += PI * 0.5
	n.rotation.y = rot
	n.position = pianta.centro(c) + Vector3(0, pt.quota, 0)
	if posto.size() > 2 and posto[2] != null:
		## Schiena al muro: si arretra fino a sfiorarlo.
		var d : Vector2i = posto[2]
		var verso := Vector3(d.x, 0, d.y)
		var fondo := box.size.z * n.scale.z
		n.position += verso * maxf(0.0, pianta.lato_cella * 0.5 - fondo * 0.5 - 0.05)
	## Le celle che copre: tutte libere, della stanza, lontane dalle porte. Chi
	## sta al muro puo' stare accanto a un varco (non sopra): che non lo chiuda
	## lo garantisce la stanza unita, qui sotto.
	var coperte := _celle_coperte(n)
	var raggio_porta := 0 if pt.posto == PezzoTema.Posto.MURO else 1
	for q in coperte:
		if pianta.stanza(q) != i or not pianta.camminabile(q) or occupate.has(q) \
				or q == pianta.ingresso or pianta._vicino_a_porta(q, raggio_porta):
			## Via subito, non a fine frame: chi conta i triangoli appena dopo
			## la costruzione (verifica_dungeon) lo vedrebbe ancora.
			remove_child(n)
			n.free()
			return null
	## Un pezzo solido non deve spezzare la stanza: un magazzino pieno di casse
	## puo' chiudere un passaggio, o murare un nemico in un angolo.
	if pt.solido and not _stanza_resta_unita(i, coperte):
		remove_child(n)
		n.free()
		return null
	for q in coperte:
		occupate[q] = true
		if pt.solido:
			guida.ostacolo(q)
	return n


## Segna `celle` come ostacolo per la guida, ma solo se tutto il pavimento
## libero resta raggiungibile dall'ingresso (porte chiuse comprese: si aprono).
## Se no il pezzo se ne va: un sasso d'angolo e un sarcofago, insieme,
## muravano una meta' di stanza con diciassette nemici (seme 42).
func _occupa(n : Node3D, celle : Array) -> bool:
	var tolte := {}
	for c in celle:
		tolte[c] = true
	var totale := 0
	for z in pianta.profondita:
		for x in pianta.larghezza:
			var c := Vector2i(x, z)
			if pianta.camminabile(c) and not guida._ostacoli.has(c) and not tolte.has(c):
				totale += 1
	var visti := {pianta.ingresso: true}
	var coda : Array[Vector2i] = [pianta.ingresso]
	while not coda.is_empty():
		var c : Vector2i = coda.pop_back()
		for d in DIREZIONI:
			var q : Vector2i = c + d
			if not visti.has(q) and pianta.camminabile(q) and not guida._ostacoli.has(q) and not tolte.has(q):
				visti[q] = true
				coda.append(q)
	if visti.size() < totale:
		remove_child(n)
		n.free()
		return false
	for c in celle:
		guida.ostacolo(c)
	return true


## Le celle libere della stanza restano un pezzo solo anche togliendo
## `in_piu`? (BFS sulle sole celle della stanza: poche centinaia.)
func _stanza_resta_unita(i : int, in_piu : Array) -> bool:
	var libere := {}
	for c in pianta.celle_di(i):
		if pianta.camminabile(c) and not guida._ostacoli.has(c) and not in_piu.has(c):
			libere[c] = true
	if libere.is_empty():
		return false
	var primo : Vector2i = libere.keys()[0]
	var visti := {primo: true}
	var coda : Array[Vector2i] = [primo]
	while not coda.is_empty():
		var c : Vector2i = coda.pop_back()
		for d in DIREZIONI:
			var q : Vector2i = c + d
			if libere.has(q) and not visti.has(q):
				visti[q] = true
				coda.append(q)
	return visti.size() == libere.size()


## Le celle sotto l'ingombro in pianta di un pezzo gia' messo (un po' stretto:
## un bordo che sfiora una cella non la occupa).
func _celle_coperte(n : Node3D) -> Array[Vector2i]:
	var box := Misura.ingombro(n)
	var out : Array[Vector2i] = []
	var mn := Vector3(INF, 0, INF)
	var mx := Vector3(-INF, 0, -INF)
	for k in 8:
		var p : Vector3 = n.transform * (box.get_endpoint(k))
		mn = Vector3(minf(mn.x, p.x), 0, minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), 0, maxf(mx.z, p.z))
	var margine := 0.25
	var a : Vector2i = pianta.cella_di(mn + Vector3(margine, 0, margine))
	var b : Vector2i = pianta.cella_di(mx - Vector3(margine, 0, margine))
	for z in range(a.y, maxi(a.y, b.y) + 1):
		for x in range(a.x, maxi(a.x, b.x) + 1):
			out.append(Vector2i(x, z))
	return out


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


# ─── 8. La fine dello scontro ─────────────────────────────────────────────

func _su_ripulito() -> void:
	## Nel dungeon a uscita ripulire e' un di piu', non la vittoria.
	if pianta.obiettivo == Pianta.Obiettivo.ELIMINA:
		_fine(true, "Dungeon ripulito")


func _su_morte() -> void:
	_fine(false, "Sei caduto in battaglia", 1.8)


## Ferma il cronometro, aspetta un attimo (la caduta, l'animazione di
## morte), mette in pausa il mondo e mostra la schermata.
func _fine(vinto : bool, motivo : String, attesa : float = 0.6) -> void:
	if _finito:
		return
	_finito = true
	print("DUNGEON: fine scontro — %s (%s)" % ["vittoria" if vinto else "sconfitta", motivo])
	if not mostra_fine:
		return
	await get_tree().create_timer(attesa, true, false, true).timeout
	if not is_inside_tree():
		return
	var schermo : CanvasLayer = FineScontro.new()
	schermo.name = "FineScontro"
	_schermo = schermo
	add_child(schermo)
	schermo.scelto.connect(_su_scelta)
	get_tree().paused = true
	schermo.mostra(vinto, {
		"titolo_motivo": motivo,
		"tempo": _tempo,
		"abbattuti": _nemici_tot - _nemici_vivi,
		"nemici": _nemici_tot,
		"forzieri": _forzieri_aperti,
		"forzieri_tot": pianta.forzieri.size(),
		"pietre_varco": _pietre_varco(),
		"perk": [] if vinto else PerkRivincita.tre(_rng_perk()),
	})


var _schermo : Node

func _rng_perk() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = _seme_usato * 31 + int(_tempo * 10.0)
	return r


const PIETRA_VARCO := "pietra_del_varco"

## Il contenuto dei forzieri arriva con la Fase 4; intanto i rari danno la
## Pietra del Varco, l'unico oggetto che il dungeon sa gia' cosa farne.
func _su_forziere(raro : bool) -> void:
	_forzieri_aperti += 1
	if not raro:
		return
	var inv := get_node_or_null("/root/ArcaniumInventory")
	if inv == null:
		return
	var def : Resource = load("res://arcanium/resources/items/pietra_del_varco.tres")
	inv.add(def, 1, true)
	var annunci := get_node_or_null("/root/Announcer")
	if annunci != null and annunci.has_method("item_acquired"):
		annunci.item_acquired(def.item_name, def.icon)
const MENU_PRINCIPALE := "res://arcanium/ui/main_menu/main_menu.tscn"

func _pietre_varco() -> int:
	var inv := get_node_or_null("/root/ArcaniumInventory")
	if inv == null:
		return 0
	var n := 0
	for s in inv.slots:
		if s.def != null and s.def.id == PIETRA_VARCO:
			n += int(s.count)
	return n


## «Riprova» lo stesso seme; «Avanti» e «Prosegui» (spendendo la Pietra del
## Varco) un altro; «Abbandona» chiude la run e torna al menu. Nella scena di
## gioco si ricarica la scena (il giocatore torna intero); in un banco senza
## scena corrente (i cancelli) si ricostruisce sul posto.
##
## Il perk della rivincita (design-crogiolo: si sceglie dopo una sconfitta e
## vale per quello scontro) non c'e' ancora: quando arrivera', «Riprova» e
## «Prosegui» lo portano con se', «Avanti» e «Abbandona» lo lasciano.
func _su_scelta(azione : String) -> void:
	get_tree().paused = false
	## Il perk viaggia con la rivincita e con la Pietra del Varco; la vittoria
	## e l'abbandono lo spengono.
	if azione in ["riprova", "varco"] and _schermo != null:
		perk_attivo = String(_schermo.perk_scelto)
	else:
		perk_attivo = ""
	var corrente_a := get_tree().current_scene
	var in_gioco : bool = corrente_a != null and corrente_a.is_ancestor_of(self)
	if azione == "abbandona":
		abbandonato.emit()
		if in_gioco:
			get_tree().change_scene_to_file(MENU_PRINCIPALE)
		return
	if azione == "varco":
		var inv := get_node_or_null("/root/ArcaniumInventory")
		if inv == null or not inv.consuma(PIETRA_VARCO):
			push_warning("DUNGEON: «Prosegui» senza Pietra del Varco")
			return
	_prossimo_seme = _seme_usato if azione == "riprova" else -1
	var corrente := get_tree().current_scene
	if corrente != null and corrente.is_ancestor_of(self):
		get_tree().reload_current_scene()
	else:
		costruisci()


# ─── 7. Il giocatore ───────────────────────────────────────────────────────

func _porta_giocatore() -> void:
	if giocatore.is_empty():
		return
	var gp := get_node_or_null(giocatore)
	if gp != null and gp.has_signal("death_started") and not gp.death_started.is_connected(_su_morte):
		gp.death_started.connect(_su_morte)
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
	if _contatore == null:
		return
	if pianta.obiettivo == Pianta.Obiettivo.USCITA:
		_contatore.text = "Uscita trovata" if _uscito else "Trova l'uscita"
	else:
		_contatore.text = "Nemici rimasti: %d" % _nemici_vivi if _nemici_vivi > 0 else "Dungeon ripulito"
	var p := PerkRivincita.dati(perk_attivo)
	if not p.is_empty():
		_contatore.text += "   ·   %s %s" % [p["icona"], p["nome"]]
