extends SceneTree

## ═══════════════════════════════════════════════════════════════════════════
## CANCELLO: la barretta di vita sopra i nemici comuni
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . --script res://arcanium/tools/verifica_barretta_vita.gd
##
## Perche' esiste. La barretta e' fatta di tre quad billboard, e per mesi ha
## mostrato un numero sbagliato senza che niente si lamentasse:
##
##  1. **non si accorciava.** L'accorciamento passava da `mi.scale.x`, ma un
##     materiale con `billboard_mode` riscrive la base della matrice del
##     modello e la scala del nodo la BUTTA VIA (`billboard_keep_scale` e'
##     `false` di default). A meta' vita il rosso copriva ancora tre quarti.
##  2. **scorreva nel mondo, non nello schermo.** `mi.position.x` sopravvive al
##     billboard, ma nello spazio del MONDO: girando attorno al nemico lo
##     scorrimento diventava uno spostamento in profondita'.
##  3. **stava un metro e mezzo sopra la testa**, perche' l'altezza si deduceva
##     dalla capsula di collisione con una formula che contava l'altezza una
##     volta e mezza (2,92 m su una testa a 1,55).
##  4. **non seguiva il veleno.** Si aggiornava solo da `hit()`, quindi il danno
##     da status, il drenaggio e le cure le passavano sotto il naso.
##
## Nessuno di questi quattro rompeva niente: il gioco girava, la barra si
## vedeva, e il numero era sbagliato. Ecco perche' qui si misura la LARGHEZZA
## DELLA MESH e non lo stato interno — e' l'unica cosa che il giocatore vede.
##
## ⚠️ Cio' che questo cancello NON puo' vedere e' l'orientamento: il billboard
## e' un fatto del vertex shader e headless non renderizza. Per quello serve un
## fermo immagine, e ne esiste uno di prova nella cronologia della sessione del
## 2026-08-26.

const NEMICI := [
	"res://arcanium/characters/sylvorn_fante.tscn",
	"res://arcanium/characters/consumato.tscn",
	"res://arcanium/characters/lupo.tscn",
]
const BARRA := preload("res://arcanium/ui/hud/enemy_health_bar.gd")

var guasti := 0


func _initialize() -> void:
	_prova()


func _prova() -> void:
	await process_frame
	for percorso in NEMICI:
		await _un_nemico(percorso)
	print("\n%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)


func _un_nemico(percorso : String) -> void:
	var pk := load(percorso) as PackedScene
	if pk == null:
		_guasto("%s non carica" % percorso.get_file())
		return
	var n : Node = pk.instantiate()
	root.add_child(n)
	await process_frame

	print("\n=== %s ===" % percorso.get_file())
	if not n.get("show_floating_health"):
		print("  (barretta spenta su questo nemico: niente da controllare)")
		n.queue_free()
		return

	# ─── il danno da STATUS, che non e' un colpo d'arma ─────────────────────
	var hs = n.health_system
	var totale := float(hs.total_health)
	hs.apply_damage(totale * 0.5, "TAGLIO")
	await process_frame
	var b = n.get("_health_bar")
	if b == null:
		_guasto("un danno da status non fa comparire la barretta")
		## ⚠️ Non si esce: si costruisce la barretta a mano e si va avanti con
		## gli altri controlli. Un cancello che si ferma al primo guasto
		## racconta un difetto per volta, e chi lo legge crede che sia l'unico
		## — quando questi quattro erano tutti presenti insieme.
		n._update_floating_health()
		await process_frame
		b = n.get("_health_bar")
		if b == null:
			n.queue_free()
			return

	# ─── l'ALTEZZA: sopra la testa, ma attaccata al nemico ──────────────────
	var cima := _cima_del_corpo(n)
	var y : float = b.position.y
	print("  corpo alto %.2f, barretta a %.2f" % [cima, y])
	if y < cima:
		_guasto("la barretta sta DENTRO il corpo (%.2f < %.2f)" % [y, cima])
	elif y > cima + 0.6:
		_guasto("la barretta fluttua staccata dal nemico (%.2f, cioe' %.2f sopra la testa)"
			% [y, y - cima])
	else:
		print("  ok    appesa %.2f m sopra la testa" % (y - cima))

	# ─── la LARGHEZZA VISTA: e' la mesh a dover essere corta, non il nodo ───
	var atteso : float = float(hs.current_health) / totale
	var vita : MeshInstance3D = b.get("_vita")
	var fondo : MeshInstance3D = b.get("_fondo")
	var largo_vita : float = (vita.mesh as QuadMesh).size.x
	var largo_fondo : float = (fondo.mesh as QuadMesh).size.x
	var visto : float = largo_vita / maxf(largo_fondo, 0.0001)
	print("  vita %d/%d = %.2f;  mesh larga %.3f su %.3f = %.2f"
		% [hs.current_health, int(totale), atteso, largo_vita, largo_fondo, visto])
	if absf(visto - atteso) > 0.02:
		_guasto("la barretta MOSTRA %.0f%% mentre la vita e' %.0f%% (la mesh non si accorcia)"
			% [visto * 100.0, atteso * 100.0])
	else:
		print("  ok    quello che si vede e' quello che vale")

	# ─── e si accorcia da SINISTRA, non verso il centro ─────────────────────
	var bordo : float = (vita.mesh as QuadMesh).center_offset.x - largo_vita * 0.5
	var bordo_fondo : float = -largo_fondo * 0.5
	if absf(bordo - bordo_fondo) > 0.001:
		_guasto("il bordo sinistro della vita non e' allineato al fondo (%.3f contro %.3f)"
			% [bordo, bordo_fondo])
	else:
		print("  ok    si accorcia da sinistra")

	# ─── il nodo NON deve portare la trasformazione: il billboard la butta ──
	for mi in [vita, fondo, b.get("_chip")]:
		if not mi.scale.is_equal_approx(Vector3.ONE) or not mi.position.is_equal_approx(Vector3.ZERO):
			_guasto("un quad porta scala/posizione sul NODO (%s / %s): sotto billboard non si vede"
				% [str(mi.scale), str(mi.position)])
			break

	# ─── la CURA la deve seguire ────────────────────────────────────────────
	hs.heal(totale * 0.25)
	await process_frame
	var atteso2 : float = float(hs.current_health) / totale
	var visto2 : float = (vita.mesh as QuadMesh).size.x / maxf(largo_fondo, 0.0001)
	if absf(visto2 - atteso2) > 0.02:
		_guasto("dopo una cura mostra %.0f%% invece di %.0f%%" % [visto2 * 100.0, atteso2 * 100.0])
	else:
		print("  ok    segue anche la cura (%.0f%%)" % (atteso2 * 100.0))

	# ─── e sparisce col cadavere ────────────────────────────────────────────
	hs.apply_damage(totale * 4.0, "TAGLIO")
	await process_frame
	if n.get("_health_bar") != null:
		_guasto("la barretta resta appesa a un cadavere")
	else:
		print("  ok    sparisce con la morte")
	n.queue_free()
	await process_frame


## La cima del corpo, misurata sulle mesh impellicciate — la stessa regola che
## usa `_floating_health_offset`, ricopiata QUI apposta: se un giorno le due
## divergono, e' il cancello a doversene accorgere.
func _cima_del_corpo(n : Node) -> float:
	var cima := -INF
	var inv : Transform3D = (n as Node3D).global_transform.affine_inverse()
	for x in n.find_children("*", "MeshInstance3D", true, false):
		var mi := x as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		if mi.get_node_or_null(mi.skeleton) as Skeleton3D == null:
			continue
		var ab : AABB = (inv * mi.global_transform) * mi.get_aabb()
		cima = maxf(cima, ab.position.y + ab.size.y)
	return cima if cima > -INF else 0.0


func _guasto(msg : String) -> void:
	print("  ROTTO  " + msg)
	guasti += 1
