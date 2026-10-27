extends SceneTree

## Gli SCATTI IN USCITA dall'idle d'autore: quanto strappa la posa quando un
## gesto parte a meta' idle, contro lo stesso gesto partito dalla Posa.
##
## Kessra nel dungeon di prova, senza nemici. Per ogni fase dell'idle (la Posa,
## la mano al giogo, il martello alzato) e ogni uscita (fendente, schivata,
## cammino) si parte e si registra la posa delle ossa che si vedono di piu';
## e c'e' la fermata, dal cammino all'idle. In tre modi:
##   dissolvenza — l'albero com'era: sfumature, e la fusione del cammino che
##                 insegue l'input del 20% per fotogramma;
##   rampa       — la fusione limitata dentro il cerchio dell'idle
##                 (player_anim_tree.gd, `raccordo_cammino`), solo cammino e
##                 fermata: sui gesti non cambia niente;
##   inerzia     — sfumature d'ingresso a ZERO e inerzia_anim.gd sullo
##                 scheletro, come sul Fante; sul cammino lo scarto si riprende
##                 a ogni fotogramma in cui la fusione si muove dentro il
##                 cerchio dell'idle.
##
## Le misure, per osso, sui 0,25 s dopo la partenza (la sfumatura dura 0,2 s,
## l'inerzia 0,25): piu' in la' il picco e' quello della clip d'arrivo, uguale
## da qualunque fase si parta — la prima versione misurava 0,5 s e dava tre
## numeri identici per il fendente. In gradi:
##   velocita' — rotazione fra due fotogrammi;
##   strappo   — quanto cambia la velocita' da un fotogramma al successivo
##               (la differenza dei vettori di rotazione): e' lo scatto che si
##               vede, una posa che cambia direzione o ritmo di colpo.
## Si legge la posa che esce dai modificatori: un registratore messo per
## ULTIMO fra i figli dello scheletro (get_bone_global_pose da fuori da' la
## posa dell'animazione, inerzia_anim.gd).
##
## Uso (APPDATA isolato, --fixed-fps 60):
##   godot --headless --path . --fixed-fps 60 --script res://arcanium/tools/misura_uscita_idle.gd

const CASA := "vorrkai"
const FASI := {"Posa": 0.2, "giogo": 1.5, "martello": 4.2}
const USCITE := ["fendente", "schivata", "cammino", "fermata"]
const MODI := {"dissolvenza": USCITE, "rampa": ["cammino", "fermata"], "inerzia": USCITE}
const OSSA := ["RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm",
		"LeftHand", "Spine", "Chest", "Neck", "Head"]
const FINESTRA := 30
## I fotogrammi del passaggio, contati dalla partenza.
const PASSAGGIO := 15
## La partenza nel registro: si registrano 3 fotogrammi prima.
const PRIMA := 3
const INERZIA := preload("res://arcanium/systems/inerzia_anim.gd")


class Registratore extends SkeletonModifier3D:
	var ossa : PackedInt32Array = []
	var pose : Array = []
	var attivo := false
	var _ultimo := -1

	## Lo scheletro si aggiorna anche due volte per tick di fisica (l'albero
	## gira in fisica): una posa sola per tick, o i doppioni passano per
	## velocita' nulla e il tick dopo per uno strappo. E l'ULTIMA del tick:
	## nella prima l'inerzia riceve delta zero e non lavora, e il registro
	## mostrava il passaggio grezzo, un taglio secco.
	func _process_modification_with_delta(_delta : float) -> void:
		if not attivo:
			return
		var sk := get_skeleton()
		var riga : Array[Quaternion] = []
		for o in ossa:
			riga.append(sk.get_bone_pose_rotation(o))
		if Engine.get_physics_frames() == _ultimo and not pose.is_empty():
			pose[-1] = riga
		else:
			pose.append(riga)
		_ultimo = Engine.get_physics_frames()


var _pl : Node
var _albero
var _sk : Skeleton3D
var _reg : Registratore
var _inerzia : SkeletonModifier3D
var _tempo := ""


func _init() -> void:
	await process_frame
	var salva : Node = root.get_node("SaveManager")
	salva._house = CASA
	root.get_node("EquipmentLoadout").clear_all()
	salva._tecniche_del_campione()
	var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
	scena.get_node("Dungeon").seme = 0
	root.add_child(scena)
	for k in 40:
		await process_frame
	for e in get_nodes_in_group("nemico_dungeon"):
		e.queue_free()
	_pl = scena.get_node("Player")
	_albero = _pl.animation_tree
	_sk = _pl.get_node("protagonist/BaseArmature/GeneralSkeleton")
	_tempo = "parameters/MovementStates/%s_tree/MoveStrafe/%s/Idle/current_position" % [_albero.weapon_type,
			String(_albero._idle_seek[_albero.weapon_type + "_tree"]).get_slice("/MoveStrafe/", 1).get_slice("/", 0)]
	_reg = Registratore.new()
	for nome in OSSA:
		_reg.ossa.append(_sk.find_bone(nome))
	_sk.add_child(_reg)
	await _fisica(120)

	print("RIFERIMENTO: l'idle da sola, un giro intero")
	_reg.pose.clear()
	_reg.attivo = true
	await _fisica(360)
	_reg.attivo = false
	print("  %s" % _riassunto(_reg.pose, 1, _reg.pose.size()))

	for modo in MODI:
		_albero.raccordo_cammino = "rampa" if modo == "rampa" else "nessuno"
		if modo == "inerzia":
			_accendi_inerzia()
		for uscita in MODI[modo]:
			for fase in (["cammino"] if uscita == "fermata" else FASI.keys()):
				var misura : String = await _prova(uscita, FASI.get(fase, 0.2))
				print("%-11s %-8s da %-8s  %s" % [modo, uscita, fase, misura])
	quit()


func _accendi_inerzia() -> void:
	for g in ["Attack", "Dodge"]:
		_albero.tree_root.get_node(g).fadein_time = 0.0
	_inerzia = INERZIA.new()
	_inerzia.name = "Inerzia"
	_sk.add_child(_inerzia)
	_sk.move_child(_inerzia, 0)
	## Lo scarto si prende quando la clip parte DAVVERO nell'albero: chiamato
	## subito dopo attack() arrivava prima del colpo (che passa per
	## trigger_event), non trovava differenze, e il passaggio a sfumatura zero
	## restava un taglio secco.
	_albero.animation_started.connect(func(_n): _inerzia.avvia())


func _prova(uscita : String, fase : float) -> String:
	## L'idle riparte dalla Posa al rientro: si aspetta che sia ferma e a fase.
	for k in 900:
		await physics_frame
		if not _albero.idle_nascosta() and absf(float(_albero.get(_tempo)) - fase) < 0.02 \
				and (_pl.vitals == null or _pl.vitals.stamina >= _pl.vitals.max_stamina * 0.9):
			break
	var partita : float = _albero.get(_tempo)
	if uscita == "fermata":
		Input.action_press("move_up")
		await _fisica(60)
	_reg.pose.clear()
	_reg.attivo = true
	await _fisica(PRIMA)
	match uscita:
		"fendente":
			_pl.attack()
		"schivata":
			_pl.dodge()
		"cammino":
			Input.action_press("move_up")
		"fermata":
			Input.action_release("move_up")
	var fusione := "parameters/MovementStates/%s_tree/MoveStrafe/blend_position" % _albero.weapon_type
	var prima : Vector2 = _albero.get(fusione)
	for k in FINESTRA:
		await physics_frame
		## La fusione scritta dall'albero nel _process precedente si applica in
		## questo tick: lo scarto va preso adesso, prima che giri.
		var ora : Vector2 = _albero.get(fusione)
		if _inerzia != null and ora != prima and minf(ora.length(), prima.length()) < _albero.IDLE_SPARITA:
			_inerzia.avvia()
		prima = ora
	_reg.attivo = false
	Input.action_release("move_up")
	await _fisica(90)
	var diag := ""
	if _inerzia != null:
		diag = "  [inerzia: %d chiamate, scarto massimo %.1f gradi]" % [_inerzia.chiamate, rad_to_deg(_inerzia.scarto_massimo_applicato)]
		_inerzia.chiamate = 0
		_inerzia.scarto_massimo_applicato = 0.0
	return "(idle a %.2f s)  %s%s" % [partita, _riassunto(_reg.pose, PRIMA, PRIMA + PASSAGGIO), diag]


## Velocita' e strappo di picco fra i fotogrammi [da, a), in gradi per
## fotogramma, e l'osso e il fotogramma che li fanno.
func _riassunto(pose : Array, da : int, a : int) -> String:
	var v_max := 0.0
	var v_osso := ""
	var s_max := 0.0
	var s_osso := ""
	var s_fot := 0
	for i in OSSA.size():
		var prec := Vector3.ZERO
		for f in range(1, pose.size()):
			var d : Quaternion = (pose[f - 1][i].inverse() * pose[f][i]).normalized()
			if d.w < 0.0:
				d = -d
			var rv := d.get_axis() * rad_to_deg(d.get_angle()) if d.get_angle() > 1e-6 else Vector3.ZERO
			if f < da or f >= a:
				prec = rv
				continue
			if rv.length() > v_max:
				v_max = rv.length()
				v_osso = OSSA[i]
			if f > 1 and (rv - prec).length() > s_max:
				s_max = (rv - prec).length()
				s_osso = OSSA[i]
				s_fot = f - da
			prec = rv
	## La velocita' dell'osso peggiore nei primi fotogrammi del passaggio.
	var serie := PackedStringArray()
	var i_peggio := OSSA.find(s_osso)
	for f in range(maxi(da - 1, 1), mini(da + 7, pose.size())):
		var d : Quaternion = (pose[f - 1][i_peggio].inverse() * pose[f][i_peggio]).normalized()
		serie.append("%.0f" % rad_to_deg(d.get_angle() if d.w >= 0.0 else (-d).get_angle()))
	return "velocita' %5.1f (%s)  strappo %5.1f (%s, fot. %d)  serie %s" % [v_max, v_osso, s_max, s_osso, s_fot, " ".join(serie)]


func _fisica(n : int) -> void:
	for k in n:
		await physics_frame
