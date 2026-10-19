extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: il Comandante Consumato (③) e il suo ordine
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_comandante.gd
##
## Un Comandante e tre Fanti contro un manichino nel gruppo `player`, con la
## fisica accesa (in headless la root motion e' zero e si marcia a velocita'
## fissa: qui interessa DOVE vanno e QUANDO attaccano, non la posa):
##   1. l'ordine arruola i tre Fanti;
##   2. ACCERCHIANO: chi non e' di turno sta sull'anello attorno al bersaglio, a
##      spicchi, e mai piu' di `attaccanti` sono di turno insieme;
##   3. il turno GIRA: in venti secondi attaccano in piu' d'uno;
##   4. il TELL: il Comandante volta la testa verso i suoi, a intervalli;
##   5. morto il Comandante i Fanti tornano SINGOLI: niente ordine, e vanno
##      dritti sul bersaglio invece di aspettare al posto.

const COMANDANTE := "res://arcanium/characters/sylvorn_comandante.tscn"
## La prova gira con le due varianti del Fante: lo spadone e lo SCUDO. Gli
## scudi hanno guardia e Testuggine (arcanium_humanoid_enemy.gd), e nel Nido
## della Radice Sorda il Comandante ne comanda sei (2026-10-02).
const FANTI := [
	"res://arcanium/characters/sylvorn_fante_spadone.tscn",
	"res://arcanium/characters/sylvorn_fante.tscn",
]

var guasti := 0


func _sia(c : bool, cosa : String) -> void:
	if c:
		print("  ok    ", cosa)
	else:
		guasti += 1
		print("  ROTTO ", cosa)


## Un bersaglio che sa essere colpito, sul layer del player (2), fermo.
class Manichino extends CharacterBody3D:
	var colpi := 0
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
	func spingi(_verso : Vector3, _forza : float) -> void:
		pass
	func hit(_chi, _mossa) -> void:
		colpi += 1


## Quanti Fanti vivi sono a portata di spada dal bersaglio (all'origine).
func _a_portata(fanti : Array[Node3D]) -> int:
	var n := 0
	for f in fanti:
		if is_instance_valid(f) and not f.is_dead() 				and Vector2(f.global_position.x, f.global_position.z).length() < 3.4:
			n += 1
	return n


func _initialize() -> void:
	_tutte()


func _tutte() -> void:
	for f in FANTI:
		print("\n##### con %s #####" % f.get_file())
		await _prova(f)
	print("\n%s" % ("PASSATO — 0 problemi" if guasti == 0 else "FALLITO — %d problemi" % guasti))
	quit(0 if guasti == 0 else 1)


func _attendi(s : float) -> void:
	var t := 0.0
	while t < s:
		await physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)


func _prova(scena_fante : String) -> void:
	await process_frame
	## Tutto sotto un nodo solo, che si libera a fine prova: la seconda
	## variante non deve trovare i corpi della prima.
	var scena := Node3D.new()
	root.add_child(scena)
	var suolo := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(80, 1, 80)
	fs.shape = bx
	fs.position = Vector3(0, -0.5, 0)
	suolo.add_child(fs)
	scena.add_child(suolo)

	var pl := Manichino.new()
	pl.add_to_group("player")
	scena.add_child(pl)

	var com : Node3D = (load(COMANDANTE) as PackedScene).instantiate()
	scena.add_child(com)
	com.global_position = Vector3(0, 0.05, 9)
	var fanti : Array[Node3D] = []
	for p in [Vector3(-4, 0.05, 7), Vector3(4, 0.05, 7), Vector3(0, 0.05, 11)]:
		var f : Node3D = (load(scena_fante) as PackedScene).instantiate()
		scena.add_child(f)
		f.global_position = p
		fanti.append(f)
	var ordine : Node = com.get_node("OrdineComandante")

	print("=== 1. L'ORDINE ARRUOLA ===")
	await _attendi(2.0)
	_sia(ordine.fanti().size() == 3, "tre Fanti sotto ordine (%d)" % ordine.fanti().size())
	_sia(fanti.all(func(f): return f.ordine == ordine), "e ognuno sa a chi obbedisce")

	print("=== 2. ACCERCHIANO ===")
	var peggio_turni := 0
	var di_turno_visti := {}
	var sguardi := 0
	var sguardo_prima := false
	var t := 0.0
	var sul_anello_max := 0
	var a_portata_ordine := 0
	while t < 20.0:
		await _attendi(0.1)
		t += 0.1
		pl.global_position = Vector3.ZERO
		var dt : Array = ordine.di_turno()
		peggio_turni = maxi(peggio_turni, dt.size())
		for f in dt:
			di_turno_visti[f] = true
		var g : bool = ordine.guarda_i_suoi()
		if g and not sguardo_prima:
			sguardi += 1
		sguardo_prima = g
		## quanti di quelli NON di turno stanno sull'anello, adesso
		var sull := 0
		for f in fanti:
			if dt.has(f):
				continue
			var d := Vector2(f.global_position.x, f.global_position.z).length()
			if absf(d - ordine.raggio_per(f)) < 0.8:
				sull += 1
		sul_anello_max = maxi(sul_anello_max, sull)
		## Chi ATTACCA insieme: in una mossa. Nel cambio di turno chi ha appena
		## colpito puo' essere ancora vicino mentre torna al posto, ma non colpisce.
		a_portata_ordine = maxi(a_portata_ordine, fanti.filter(func(f): return f._busy).size())
	_sia(sul_anello_max >= 2, "chi non e' di turno aspetta sull'anello a %.1f m (fino a %d insieme)" % [ordine.raggio_per(fanti[0]), sul_anello_max])
	var angoli : Array = []
	for f in fanti:
		angoli.append(atan2(f.global_position.x, f.global_position.z))
	var sep := TAU
	for i in angoli.size():
		for j in range(i + 1, angoli.size()):
			sep = minf(sep, absf(wrapf(angoli[i] - angoli[j], -PI, PI)))
	_sia(sep > deg_to_rad(50.0), "a spicchi: separazione minima %.0f gradi" % rad_to_deg(sep))
	_sia(peggio_turni <= ordine.attaccanti, "mai piu' di %d di turno insieme (visti %d)" % [ordine.attaccanti, peggio_turni])
	_sia(a_portata_ordine <= ordine.attaccanti, "mai piu' di %d in una mossa insieme (visti %d)" % [ordine.attaccanti, a_portata_ordine])
	print("=== 3. IL TURNO GIRA ===")
	_sia(di_turno_visti.size() >= 2, "in 20 s il turno e' passato a %d Fanti" % di_turno_visti.size())
	_sia(pl.colpi > 0, "e i colpi arrivano (%d)" % pl.colpi)
	print("=== 4. IL TELL ===")
	var sk := com.get_node("Model/NephiliteRig/Skeleton3D") as Skeleton3D
	var la := sk.get_node_or_null("SguardoAiSuoi") as SkeletonModifier3D
	_sia(la != null, "il Comandante ha il modificatore sulla testa")
	_sia(sguardi >= 2, "in 20 s si e' voltato verso i suoi %d volte" % sguardi)

	print("=== 5. MORTO IL COMANDANTE ===")
	com.health_system.apply_damage(10000.0)
	await _attendi(1.0)
	_sia(not is_instance_valid(com) or com.is_dead(), "il Comandante e' morto")
	_sia(fanti.all(func(f): return f.ordine == null), "i Fanti non hanno piu' un ordine")
	## Singoli: vanno tutti dritti sul bersaglio. Si misura quanti arrivano a
	## portata di spada insieme, che sotto ordine era uno solo.
	var dentro_max := 0
	t = 0.0
	while t < 8.0:
		await _attendi(0.1)
		t += 0.1
		pl.global_position = Vector3.ZERO
		dentro_max = maxi(dentro_max, _a_portata(fanti))
	_sia(dentro_max >= 2, "tornati singoli, a portata di spada in %d insieme" % dentro_max)

	scena.queue_free()
	await process_frame
