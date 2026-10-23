extends "res://arcanium/levels/dungeon/costruttore_dungeon.gd"

## Il BATTLEGROUND (design-battleground; decisioni dell'autore del 2026-10-23:
## «un'arena larga e grande dove i due schieramenti dei due arcimaghi si
## scontrano»). Una piana aperta: a sud il giocatore con le tre truppe base
## della casata, schierate prima di cominciare; a nord l'armata del CAMPIONE
## RIVALE, un altro dei sei campioni, che resta nelle sue retrovie. Quando
## l'arcimago rivale cade, la sua armata si sbanda e la battaglia e' vinta.
##
## Eredita dal costruttore del mini-dungeon tutto cio' che non e' il luogo: la
## forza del nodo della mappa, i miglioramenti della run, il perk della
## rivincita, la fine dello scontro col torneo, la rivincita e la Pietra del
## Varco. Qui cambia solo la costruzione.

const CampioneCorpo := preload("res://arcanium/systems/corpo_campione.gd")
const SCHIERA := preload("res://arcanium/levels/battleground/schiera_battleground.gd")
const CARTELLA_CAMPIONI := "res://arcanium/resources/campioni/"

## La piana, in metri: larga (x) e profonda (z). Il giocatore parte a sud (+z).
const LARGO := 80.0
const PROFONDO := 54.0
## L'aggro dei combattenti: nella piana le armate si cercano da un capo
## all'altro (l'aggro dei mini-dungeon e' di 12-15 m).
const AGGRO_CAMPALE := 200.0

## L'armata del rival: gli umanoidi gia' fatti (finche' ogni casata non ha le
## sue truppe), e quanti per tappa.
const ARMATA := [
	"res://arcanium/characters/sylvorn_fante.tscn",
	"res://arcanium/characters/sylvorn_fante_spadone.tscn",
	"res://arcanium/characters/sylvorn_soldato_scelto.tscn",
	"res://arcanium/characters/consumato.tscn",
]
const ARMATA_BASE := 7
const ARMATA_PER_TAPPA := 2
## Il corpo da nemico che indossa il campione rival: il Comandante Sylvorn ha
## lo stesso rig dei campioni (NephiliteRig, stesso import).
const CORPO_RIVALE := "res://arcanium/characters/sylvorn_comandante.tscn"
## Vita e taglia dell'arcimago rival rispetto al Comandante.
const RIVALE_VITA := 3.0
const RIVALE_TAGLIA := 4.0

## Le truppe della casata del giocatore (design-battleground: tre di base).
const TRUPPE_BASE := [
	{"nome": "Footman", "scena": "res://arcanium/characters/sylvorn_fante.tscn"},
	{"nome": "Greatsword", "scena": "res://arcanium/characters/sylvorn_fante_spadone.tscn"},
	{"nome": "Marksman", "scena": "res://arcanium/characters/sylvorn_soldato_scelto.tscn"},
]

## La tinta della luce per territorio: la piana prende il colore della regione.
const TINTE := {
	"kalvorn": Color(0.55, 0.75, 0.55), "pyrrath": Color(1.0, 0.55, 0.35),
	"halrath": Color(0.6, 0.75, 1.0), "davrath": Color(0.95, 0.82, 0.55),
	"pianure_grigie": Color(0.7, 0.75, 0.68), "kalath_dun": Color(1.0, 0.75, 0.45),
}

## L'arcimago rival (il nodo nemico) e la sua scheda di campione.
var rivale : Node3D
var campione_rivale : Resource
## Le truppe in campo.
var alleati : Array = []
var _schiera : Control


func costruisci() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_nemici_vivi = 0
	alleati.clear()
	var torneo := get_node_or_null("/root/Torneo")
	if torneo != null and not torneo.in_corso:
		torneo.inizia()
	var nodo : Dictionary = torneo.nodo_in_corso() if torneo != null else {}
	var s := seme if seme >= 0 else randi() % 1000000
	if not nodo.is_empty():
		s = int(nodo["seme"])
	if _prossimo_seme != -2:
		s = _prossimo_seme if _prossimo_seme >= 0 else s
		_prossimo_seme = -2
	_seme_usato = s
	_finito = false
	_tempo = 0.0
	_forzieri_aperti = 0
	_rng.seed = s + 7919
	_forza = _forza_del_nodo(nodo) if not nodo.is_empty() else FORZA_BATTLEGROUND
	var territorio := ""
	if torneo != null and not nodo.is_empty():
		territorio = String(torneo.regione(int(nodo["regione"])).get("territorio", ""))
	_costruisci_piana(territorio)
	_costruisci_armata(nodo)
	_costruisci_rivale(torneo)
	_porta_giocatore()
	_nemici_tot = _nemici_vivi
	BonusRun.applica(get_node_or_null(giocatore) if not giocatore.is_empty() else null, torneo)
	PerkRivincita.applica(perk_attivo, get_node_or_null(giocatore) if not giocatore.is_empty() else null, self)
	if mostra_contatore:
		_costruisci_contatore()
	print("BATTLEGROUND: seme %d, %d nemici, arcimago rivale %s (%s), forza %.2f" % [s, _nemici_vivi,
			campione_rivale.nome if campione_rivale else "-", territorio, _forza])
	_apri_schiera()


# ─── La piana ───────────────────────────────────────────────────────────────

func _costruisci_piana(territorio : String) -> void:
	## Il terreno: un piano largo col pavimento delle rovine, e la collisione.
	var mi := MeshInstance3D.new()
	mi.name = "Terreno"
	var pm := PlaneMesh.new()
	pm.size = Vector2(LARGO + 24.0, PROFONDO + 24.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mi.mesh = pm
	if profilo.materiale_pavimento != null:
		var m : Material = profilo.materiale_pavimento.duplicate()
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).uv1_scale = Vector3((LARGO + 24.0) / 4.0, (PROFONDO + 24.0) / 4.0, 1.0)
		mi.material_override = m
	add_child(mi)
	var suolo := StaticBody3D.new()
	suolo.name = "Suolo"
	var fs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(LARGO + 24.0, 1.0, PROFONDO + 24.0)
	fs.shape = bs
	fs.position = Vector3(0, -0.5, 0)
	suolo.add_child(fs)
	add_child(suolo)
	## I bordi: muri invisibili, e davanti rovine e pezzi grossi in fila larga.
	for lato in [[Vector3(0, 2, -PROFONDO * 0.5 - 1), Vector3(LARGO + 4, 4, 1)],
			[Vector3(0, 2, PROFONDO * 0.5 + 1), Vector3(LARGO + 4, 4, 1)],
			[Vector3(-LARGO * 0.5 - 1, 2, 0), Vector3(1, 4, PROFONDO + 4)],
			[Vector3(LARGO * 0.5 + 1, 2, 0), Vector3(1, 4, PROFONDO + 4)]]:
		var muro := StaticBody3D.new()
		var f := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = lato[1]
		f.shape = b
		muro.position = lato[0]
		muro.add_child(f)
		add_child(muro)
	var pezzi : Array = profilo.pezzi_grossi.duplicate()
	if profilo.fontana != null:
		pezzi.append(profilo.fontana)
	if not pezzi.is_empty():
		## Il contorno: un pezzo ogni ~9 m, appena fuori dal campo.
		var passo := 9.0
		var x := -LARGO * 0.5
		while x <= LARGO * 0.5:
			for z in [-PROFONDO * 0.5 - 3.0, PROFONDO * 0.5 + 3.0]:
				_metti(pezzi, Vector3(x + _rng.randf_range(-2, 2), 0, z + _rng.randf_range(-1.5, 1.5)), 5.5)
			x += passo
		var z2 := -PROFONDO * 0.5 + 6.0
		while z2 <= PROFONDO * 0.5 - 6.0:
			for x2 in [-LARGO * 0.5 - 3.0, LARGO * 0.5 + 3.0]:
				_metti(pezzi, Vector3(x2, 0, z2 + _rng.randf_range(-2, 2)), 5.5)
			z2 += passo
		## Qualche copertura nella fascia centrale, lontana dai due schieramenti.
		for k in 5:
			var p := Vector3(_rng.randf_range(-LARGO * 0.38, LARGO * 0.38), 0, _rng.randf_range(-6.0, 6.0))
			_metti(pezzi, p, 4.0)
	## La luce: una luna tinta col territorio, e fuochi lungo i due fronti.
	var tinta : Color = TINTE.get(territorio, Color(0.75, 0.75, 0.8))
	var luna := DirectionalLight3D.new()
	luna.name = "Luna"
	luna.light_color = tinta.lerp(Color(0.6, 0.7, 0.9), 0.5)
	luna.light_energy = 0.55
	luna.shadow_enabled = true
	luna.directional_shadow_max_distance = 80.0
	luna.rotation_degrees = Vector3(-52, 35, 0)
	add_child(luna)
	for z in [-PROFONDO * 0.5 + 4.0, PROFONDO * 0.5 - 4.0]:
		for k in 4:
			var luce := OmniLight3D.new()
			luce.light_color = Color(1.0, 0.62, 0.32).lerp(tinta, 0.3)
			luce.light_energy = 2.2
			luce.omni_range = 18.0
			luce.position = Vector3(-LARGO * 0.375 + k * LARGO * 0.25, 3.5, z)
			add_child(luce)
	var centro := OmniLight3D.new()
	centro.light_color = tinta
	centro.light_energy = 1.2
	centro.omni_range = 34.0
	centro.position = Vector3(0, 9, 0)
	add_child(centro)


func _metti(pezzi : Array, dove : Vector3, misura : float) -> void:
	var n := _pezzo(pezzi[_rng.randi_range(0, pezzi.size() - 1)], misura, 0.0, "larghezza", true)
	n.position = dove
	n.rotation.y = _rng.randf() * TAU


# ─── Le armate ──────────────────────────────────────────────────────────────

## L'armata del rival in tre file a nord, coi piu' forti dietro.
func _costruisci_armata(nodo : Dictionary) -> void:
	var tappa := int(nodo.get("regione", 0)) + 1
	var quanti := ARMATA_BASE + ARMATA_PER_TAPPA * (tappa - 1)
	var per_fila := int(ceil(quanti / 3.0))
	for k in quanti:
		var fila := k / per_fila
		var posto := k % per_fila
		var scena : String = ARMATA[mini(fila + _rng.randi_range(0, 1), ARMATA.size() - 1)]
		var e : Node3D = (load(scena) as PackedScene).instantiate()
		var x := (posto - (per_fila - 1) * 0.5) * 4.5 + _rng.randf_range(-0.8, 0.8)
		e.position = Vector3(x, 0.1, -PROFONDO * 0.5 + 12.0 + fila * 3.5)
		e.rotation.y = 0.0
		e.set("aggro_range", AGGRO_CAMPALE)
		e.add_to_group("nemico_dungeon")
		add_child(e)
		_rafforza(e)
		_nemici_vivi += 1
		if e.has_signal("death_started"):
			e.death_started.connect(_su_nemico_morto, CONNECT_ONE_SHOT)


## Il campione rival: un altro dei sei, scelto dal seme del nodo, sul corpo
## del Comandante; nelle retrovie della sua armata.
func _costruisci_rivale(torneo : Node) -> void:
	var mia := ""
	var salva := get_node_or_null("/root/SaveManager")
	if salva != null:
		mia = String(salva.get_house())
	var candidati : Array = []
	for f in DirAccess.get_files_at(CARTELLA_CAMPIONI):
		var nome := f.trim_suffix(".remap")
		if nome.ends_with(".tres"):
			var c : Resource = load(CARTELLA_CAMPIONI + nome)
			if c != null and String(c.casata) != mia and String(c.corpo) != "":
				candidati.append(c)
	candidati.sort_custom(func(a, b): return String(a.casata) < String(b.casata))
	if candidati.is_empty():
		return
	campione_rivale = candidati[_rng.randi_range(0, candidati.size() - 1)]
	rivale = (load(CORPO_RIVALE) as PackedScene).instantiate()
	rivale.name = "ArcimagoRivale"
	## Via cio' che e' del Comandante e non del campione: i drop d'armatura,
	## il mantello simulato, l'ordine alla truppa.
	for n in rivale.get_children():
		if String(n.name).begins_with("Drop_") or n.name in ["StoffaSimulata", "OrdineComandante"]:
			rivale.remove_child(n)
			n.free()
	var corpo := CampioneCorpo.new()
	corpo.name = "CorpoCampione"
	corpo.scheletro = rivale.get_node("Model/NephiliteRig/Skeleton3D")
	corpo.animazioni = rivale.get_node("Model/AnimationPlayer")
	corpo.casata_forzata = String(campione_rivale.casata)
	rivale.add_child(corpo)
	_arma_del_rivale()
	rivale.position = Vector3(0, 0.1, -PROFONDO * 0.5 + 4.5)
	rivale.set("aggro_range", AGGRO_CAMPALE)
	rivale.add_to_group("arcimago_rivale")
	add_child(rivale)
	var hs = rivale.get("health_system")
	if hs != null:
		hs.total_health = int(round(float(hs.total_health) * RIVALE_VITA * _forza))
		hs._health_f = float(hs.total_health)
		hs.current_health = hs.total_health
		if hs.has_signal("health_updated"):
			hs.health_updated.connect(func(_v): _aggiorna_contatore())
	for c in rivale.get_children():
		if c is CrystalBounty:
			(c as CrystalBounty).amount = int(round(float((c as CrystalBounty).amount) * RIVALE_TAGLIA * _forza))
	if rivale.has_signal("death_started"):
		rivale.death_started.connect(_su_rivale_caduto, CONNECT_ONE_SHOT)


## In mano l'arma della sua casata (dotazione della scheda) al posto dello
## spadone del Comandante: stesso aggancio, la presa dell'arma nell'origine e
## la lama lungo lo stesso asse dello spadone.
func _arma_del_rivale() -> void:
	var mount := rivale.get_node_or_null("Model/NephiliteRig/Skeleton3D/MountArma")
	if mount == null or campione_rivale == null or not campione_rivale.dotazione.has("arma_primaria"):
		return
	var arma : Resource = load(campione_rivale.dotazione["arma_primaria"])
	var modello : PackedScene = arma.get("held_model")
	if modello == null:
		return
	var vecchia := mount.get_node_or_null("Spadone") as Node3D
	var n : Node3D = modello.instantiate()
	n.name = "ArmaRivale"
	if vecchia != null:
		## Lo spadone del Comandante ha la lama lungo il suo +Y scalato: si
		## tiene la stessa rotazione, a scala 1 (le armi dei campioni sono gia'
		## in metri).
		var b := vecchia.transform.basis.orthonormalized()
		n.transform = Transform3D(b, Vector3.ZERO)
		mount.remove_child(vecchia)
		vecchia.free()
	mount.add_child(n)


## Le truppe: dove sono state schierate, nella meta' sud.
func punti_schieramento() -> Array:
	var fronte := PROFONDO * 0.5 - 12.0
	return [
		{"nome": "Centre", "pos": Vector3(0, 0, fronte)},
		{"nome": "Left flank", "pos": Vector3(-LARGO * 0.28, 0, fronte)},
		{"nome": "Right flank", "pos": Vector3(LARGO * 0.28, 0, fronte)},
		{"nome": "Rear guard", "pos": Vector3(0, 0, PROFONDO * 0.5 - 5.0)},
	]


func _apri_schiera() -> void:
	var truppe : Array = []
	for t in TRUPPE_BASE:
		truppe.append({"nome": t["nome"], "scena": load(t["scena"])})
	_schiera = SCHIERA.new()
	_schiera.name = "SchieraBattleground"
	_schiera.truppe = truppe
	_schiera.punti = punti_schieramento()
	_schiera.scelte_iniziali = [1, 0, 2]
	_schiera.rivale = campione_rivale.nome if campione_rivale != null else ""
	_schiera.schierato.connect(_schiera_truppe.bind(truppe))
	var strato := CanvasLayer.new()
	strato.name = "StratoSchiera"
	strato.layer = 30
	strato.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(strato)
	strato.add_child(_schiera)
	get_tree().paused = true


func _schiera_truppe(scelte : Array, truppe : Array) -> void:
	var punti : Array = punti_schieramento()
	for k in truppe.size():
		var e : Node3D = (truppe[k]["scena"] as PackedScene).instantiate()
		e.set("alleato", true)
		e.set("aggro_range", AGGRO_CAMPALE)
		var p : Vector3 = punti[int(scelte[k])]["pos"]
		e.position = p + Vector3(_rng.randf_range(-1.5, 1.5), 0.1, _rng.randf_range(-1.0, 1.0))
		e.rotation.y = PI
		e.add_to_group("alleato_dungeon")
		for c in e.get_children():
			if c is CrystalBounty:
				c.queue_free()
		add_child(e)
		alleati.append(e)
	_schiera = null
	var strato := get_node_or_null("StratoSchiera")
	if strato != null:
		strato.queue_free()
	get_tree().paused = false


# ─── La fine ────────────────────────────────────────────────────────────────

## L'arcimago rival e' caduto: la sua armata si sbanda (cade con lui) e la
## battaglia e' vinta.
func _su_rivale_caduto() -> void:
	for e in get_tree().get_nodes_in_group("nemico_dungeon"):
		var hs = e.get("health_system")
		if hs != null and hs.has_signal("died") and float(hs.get("_health_f")) > 0.0:
			hs._health_f = 0.0
			hs.current_health = 0
			hs.died.emit()
	_fine(true, "The rival archmage has fallen", 1.6)


## L'armata sterminata non basta: si vince abbattendo l'arcimago.
func _su_ripulito() -> void:
	_aggiorna_contatore()


func _forzieri_tot() -> int:
	return 0


func _luogo_ingresso() -> Vector3:
	return Vector3(0, 0, PROFONDO * 0.5 - 8.0)


func _aggiorna_contatore() -> void:
	if _contatore == null:
		return
	var hs = rivale.get("health_system") if is_instance_valid(rivale) else null
	if hs == null or campione_rivale == null:
		_contatore.text = tr("Enemies left: %d") % _nemici_vivi
		return
	_contatore.text = tr("Bring down %s  —  %d HP  ·  %d troops") % [tr(String(campione_rivale.nome)),
			int(ceil(float(hs._health_f))), _nemici_vivi]
