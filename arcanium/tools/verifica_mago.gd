extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: il Mago Guerriero Sylvorn, la Voce Rimasta
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_mago.gd
##
## Le tre mosse di `arcanium_mago_enemy.gd`, chiamate a mano con la fisica
## spenta (in headless lo scheletro non si muove, e qui interessa cosa le mosse
## fanno nel MONDO, non la posa — quella si guarda con anteprima_clip_nemico):
##   1. e' un mago: corpo riggato, tre mosse, tiene le distanze
##   2. RADICI: tre cerchi di traverso, il centro sul bersaglio; chi e' dentro e'
##      preso, chi ne esce no; e con la sbandata partono verso nessuno
##   3. RICHIAMO: escono le Eco Guaste, col bersaglio gia' dato, mai oltre il tetto
##   4. RESPINTA: il cerchio attorno a lui colpisce e SPINGE via
##   5. la ritirata ereditata dall'arciere parte col bersaglio addosso
##   6. FRUSTA: i rampicanti escono dalle mani, la mira si ferma sul punto, chi
##      sta sulla linea e' preso e chi si e' spostato di lato no
##   7. LACERAZIONE: due frustate piene fanno scattare il sanguinamento — colpo
##      secco agli HP, poi stamina che cala senza rigenerarsi per 5 s; la barra
##      d'accumulo si vede e cala da sola; chi para non accumula

const MAGO := "res://arcanium/characters/sylvorn_mago.tscn"

var guasti := 0


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


## Un corpo che sa essere colpito e spinto, sul layer del player (2).
class Manichino extends CharacterBody3D:
	var colpi : Array = []
	var spinte : Array = []
	func spingi(verso : Vector3, forza : float) -> void:
		spinte.append([verso, forza])
	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		var f := CollisionShape3D.new()
		var c := CapsuleShape3D.new()
		c.radius = 0.4
		c.height = 1.8
		f.shape = c
		f.position = Vector3(0, 0.9, 0)
		add_child(f)
	func hit(_chi, mossa) -> void:
		colpi.append(mossa)


## Un corpo con vita, stati e vitali come quelli del giocatore.
class Ferito extends Node3D:
	var health_system : Node
	var status_host : Node
	var vitals : Node
	func _init() -> void:
		status_host = (load("res://arcanium/systems/status/status_host.gd") as GDScript).new()
		status_host.name = "StatusHost"
		status_host.set("log_to_console", false)
		add_child(status_host)
		health_system = (load("res://arcanium/systems/arcanium_health_system.gd") as GDScript).new()
		health_system.name = "HealthSystem"
		health_system.set("total_health", 100)
		health_system.set("status_host", status_host)
		add_child(health_system)
		vitals = (load("res://arcanium/systems/player_vitals.gd") as GDScript).new()
		vitals.name = "PlayerVitals"
		vitals.set("status_host", status_host)
		add_child(vitals)


func _initialize() -> void:
	_prova()


func _mossa(m : Node, id : String):
	for x in m.move_set.moves:
		if x.id == id:
			return x
	return null


func _prova() -> void:
	await process_frame
	## Un pavimento: i cerchi e le Eco si posano sul suolo con un raggio.
	var suolo := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(80, 1, 80)
	fs.shape = bx
	fs.position = Vector3(0, -0.5, 0)
	suolo.add_child(fs)
	root.add_child(suolo)

	var m : Node3D = (load(MAGO) as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.set_physics_process(false)
	var avanti : Vector3 = m.global_transform.basis.z
	avanti.y = 0.0
	avanti = avanti.normalized()

	print("=== 1. e' un mago ===")
	var sk := m.get_node_or_null("Model/NephiliteRig/Skeleton3D") as Skeleton3D
	_sia(sk != null and sk.get_bone_count() >= 79, "corpo riggato sul Nephilite (%d ossa)" % (sk.get_bone_count() if sk else 0))
	var radici = _mossa(m, "RADICI")
	var richiamo = _mossa(m, "RICHIAMO")
	var respinta = _mossa(m, "RESPINTA")
	var frusta = _mossa(m, "FRUSTA")
	_sia(radici != null and richiamo != null and respinta != null and frusta != null,
		"quattro mosse: RADICI, RICHIAMO, RESPINTA, FRUSTA")
	_sia(m.move_set.melee_threshold >= 6.0, "l'inseguimento si ferma a distanza (%.1f m)" % m.move_set.melee_threshold)
	_sia(m.anim_player != null and m.anim_player.has_animation("sword/sword_cast_01"),
		"la clip di lancio c'e' nel suo AnimationPlayer")
	if radici == null or richiamo == null or respinta == null or frusta == null:
		_fine()
		return

	var b := Manichino.new()
	b.add_to_group("player")
	root.add_child(b)
	b.global_position = m.global_position + avanti * 8.0
	m.target = b
	await physics_frame

	print()
	print("=== 2. RADICI ===")
	m.sbandata = 0.0
	m._segna_radici(radici)
	var punti : Array = m.get("_punti")
	_sia(punti.size() == 3, "tre cerchi (%d)" % punti.size())
	if punti.size() == 3:
		var c0 : Vector3 = punti[0]
		_sia(Vector2(c0.x - b.global_position.x, c0.z - b.global_position.z).length() < 0.05,
			"il primo e' sotto il bersaglio")
		var fianco : Vector3 = (punti[1] as Vector3) - c0
		_sia(absf(fianco.normalized().dot(avanti)) < 0.05 and absf(fianco.length() - m.radici_scarto) < 0.05,
			"gli altri due di traverso, a %.1f m" % fianco.length())
		_sia(absf(c0.y) < 0.05, "posati sul suolo (y %.2f)" % c0.y)
	m._deliver_hit(radici)
	_sia(b.colpi.size() == 1 and b.colpi[0] == radici, "chi e' dentro e' preso (stordito %.1f s)" % radici.stun_time)
	b.colpi.clear()
	m._segna_radici(radici)
	b.global_position += avanti * (m.radici_raggio + 0.3)
	m._deliver_hit(radici)
	_sia(b.colpi.is_empty(), "chi ne esce in avanti no")
	## Il bersaglio fuori dall'anello della sbandata (4-8 m), o un punto a caso
	## gli cade vicino e la prova non distingue.
	b.global_position = m.global_position + avanti * 12.0
	m.sbandata = 1.0
	var lontani := 0
	for i in 6:
		m._segna_radici(radici)
		var c : Vector3 = (m.get("_punti") as Array)[0]
		var d := Vector2(c.x - m.global_position.x, c.z - m.global_position.z).length()
		if Vector2(c.x - b.global_position.x, c.z - b.global_position.z).length() > 0.5 \
				and d >= m.sbandata_distanza.x - 0.05 and d <= m.sbandata_distanza.y + 0.05:
			lontani += 1
	_sia(lontani == 6, "con la sbandata partono verso nessuno, attorno a lui (%d su 6)" % lontani)
	m.sbandata = 0.15
	m._clear_move_state()

	print()
	print("=== 3. RICHIAMO ===")
	_sia(m._move_is_usable(richiamo), "senza evocate il richiamo si sceglie")
	var eco_prima := _conta_eco()
	m._on_move_started(richiamo, 3.0)
	_sia((m.get("_punti") as Array).size() == m.richiamo_quante, "segna %d uscite" % m.richiamo_quante)
	m._deliver_hit(richiamo)
	await process_frame
	_sia(_conta_eco() - eco_prima == m.richiamo_quante, "escono %d Eco Guaste" % (_conta_eco() - eco_prima))
	var col_bersaglio := 0
	for e in _eco():
		if e.get("target") == b:
			col_bersaglio += 1
	_sia(col_bersaglio == m.richiamo_quante, "con il bersaglio gia' dato (%d)" % col_bersaglio)
	m._clear_move_state()
	m._on_move_started(richiamo, 3.0)
	m._deliver_hit(richiamo)
	await process_frame
	_sia(_conta_eco() - eco_prima == m.richiamo_max, "il secondo richiamo si ferma al tetto (%d vive, tetto %d)"
		% [_conta_eco() - eco_prima, m.richiamo_max])
	_sia(not m._move_is_usable(richiamo), "e col tetto pieno il richiamo non si sceglie")
	for e in _eco():
		e.queue_free()
	await process_frame
	await process_frame
	_sia(m._move_is_usable(richiamo), "morte le evocate, torna sceglibile")
	m._clear_move_state()

	print()
	print("=== 4. RESPINTA ===")
	b.colpi.clear()
	b.spinte.clear()
	b.global_position = m.global_position + avanti * 2.0
	m._on_move_started(respinta, 2.1)
	m._deliver_hit(respinta)
	_sia(b.colpi.size() == 1, "a 2 m e' colpito")
	_sia(b.spinte.size() == 1 and (b.spinte[0][0] as Vector3).dot(avanti) > 0.95 and is_equal_approx(b.spinte[0][1], respinta.spinta),
		"e spinto via da lui, a %.1f m/s" % respinta.spinta)
	b.colpi.clear()
	b.global_position = m.global_position + avanti * (m.respinta_raggio + 0.5)
	m._deliver_hit(respinta)
	_sia(b.colpi.is_empty(), "fuori dal cerchio no")
	m._clear_move_state()

	print()
	print("=== 5. la ritirata ===")
	m.set("_root_motion_delta", Vector3.ZERO)
	m.set("_next_attack", m._now() + 1000.0)
	b.global_position = m.global_position + avanti * 3.0
	m.velocity = Vector3.ZERO
	m._ai_step(1.0 / 60.0)
	_sia(bool(m.get("_in_ritirata")), "col bersaglio a 3 m si gira e corre")
	var via : Vector3 = m.velocity
	via.y = 0.0
	_sia(via.length() > 0.1 and via.normalized().dot(-avanti) > 0.8, "via dal bersaglio")
	m.set("_in_ritirata", false)
	m.velocity = Vector3.ZERO

	print()
	print("=== 6. FRUSTA ===")
	b.colpi.clear()
	b.global_position = m.global_position + avanti * 5.0
	m._on_move_started(frusta, 2.77)
	var fr = m.get("_frusta")
	_sia(fr != null and is_instance_valid(fr), "i rampicanti escono (nodo %s)" % (fr.name if fr else "-"))
	var sk_m : Skeleton3D = m._scheletro()
	_sia(sk_m != null and sk_m.find_bone(m.mano_sinistra) >= 0 and sk_m.find_bone(m.mano_destra) >= 0,
		"dalle ossa delle mani (%s, %s)" % [m.mano_sinistra, m.mano_destra])
	m._mira_frusta()
	var punto : Vector3 = m.get("_frusta_punto")
	_sia(Vector2(punto.x - b.global_position.x, punto.z - b.global_position.z).length() < 0.05,
		"la mira si ferma dove sta il bersaglio")
	m._deliver_hit(frusta)
	_sia(b.colpi.size() == 1 and b.colpi[0] == frusta, "chi resta sulla linea e' preso")
	b.colpi.clear()
	var di_lato := Vector3(avanti.z, 0.0, -avanti.x)
	b.global_position += di_lato * (m.frusta_larghezza + 0.5)
	m._deliver_hit(frusta)
	_sia(b.colpi.is_empty(), "chi si sposta di lato dopo la mira no")
	b.global_position = m.global_position + avanti * 20.0
	m._mira_frusta()
	var lontano : Vector3 = m.get("_frusta_punto")
	_sia(absf(Vector2(lontano.x - m.global_position.x, lontano.z - m.global_position.z).length() - m.frusta_portata) < 0.05,
		"e non arriva oltre la portata (%.1f m)" % m.frusta_portata)
	m._clear_move_state()
	for _i in 30:
		await process_frame
	_sia(fr == null or not is_instance_valid(fr) or fr.fase() == 3, "interrotta, la frusta torna nelle mani")

	print()
	print("=== 7. LACERAZIONE ===")
	var corpo := Ferito.new()
	root.add_child(corpo)
	await process_frame
	var hs = corpo.health_system
	var sh = corpo.status_host
	var vit = corpo.vitals
	var vita0 : float = float(hs.current_health)
	hs._on_damage_signal(frusta)
	var lac = sh.get_effect("laceration")
	_sia(lac != null and absf(lac.meter - frusta.laceration_buildup) < 0.01,
		"una frustata riempie la barra di %.0f su %.0f" % [lac.meter if lac else 0.0, lac.threshold if lac else 0.0])
	_sia(sh.accumuli().size() == 1 and sh.accumuli()[0].id == "laceration", "e la barra d'accumulo si vede (HUD)")
	_sia(not lac.is_active(), "senza scattare")
	var dopo_uno : float = float(hs.current_health)
	hs._on_damage_signal(frusta)
	var atteso : float = float(frusta.power) * 2.0 + float(hs.total_health) * lac.frazione_vita + lac.danno_fisso
	_sia(lac.is_active(), "la seconda la fa SCATTARE")
	_sia(absf((vita0 - float(hs.current_health)) - atteso) <= 1.0,
		"colpo secco agli HP: %d -> %d (atteso -%.0f: due frustate + %.0f%% della vita + %.0f)"
		% [int(vita0), hs.current_health, atteso, lac.frazione_vita * 100.0, lac.danno_fisso])
	_sia(dopo_uno == vita0 - float(frusta.power), "(la prima aveva tolto solo il suo danno)")
	vit.stamina = 60.0
	for _i in 60:
		await process_frame
	_sia(vit.stamina < 60.0, "mentre sanguina la stamina cala e non si rigenera (60 -> %.1f in 1 s)" % vit.stamina)
	lac.remaining = 0.01
	for _i in 30:
		await process_frame
	var st0 : float = vit.stamina
	for _i in 30:
		await process_frame
	_sia(not lac.is_active() and vit.stamina > st0, "finito lo scatto la stamina torna a salire")
	sh.build_laceration(40.0)
	for _i in 60:
		await process_frame
	_sia(absf(lac.meter - 40.0) < 0.01, "per qualche secondo dopo un colpo la barra resta ferma (%.1f)" % lac.meter)
	lac.set("_fermo", 0.0)
	for _i in 60:
		await process_frame
	_sia(lac.meter < 40.0 and lac.meter > 0.0, "poi cala da sola (40 -> %.1f in 1 s)" % lac.meter)
	lac.meter = 0.0
	var vita_parata : float = float(hs.current_health)
	hs.apply_damage(float(frusta.power) * 0.5, "TAGLIO")
	_sia(lac.meter == 0.0 and float(hs.current_health) < vita_parata, "la frustata parata ferisce ma non accumula")

	_fine()


func _eco() -> Array:
	var out := []
	for c in root.get_children():
		if str(c.scene_file_path).ends_with("eco_radicata_guasta.tscn") and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _conta_eco() -> int:
	return _eco().size()


func _fine() -> void:
	print()
	print("%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)
