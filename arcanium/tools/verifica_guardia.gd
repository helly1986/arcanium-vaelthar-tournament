extends SceneTree

## Cancello della GUARDIA. Non legge i numeri scritti nello scudo: istanzia il
## Fante, gli tira addosso colpi veri da angoli veri e MISURA la vita che perde.
##
##   godot --headless --path . --script res://arcanium/tools/verifica_guardia.gd
##
## Serve perché tutta la catena è fatta di cose che falliscono in silenzio:
## `block_resistances` è la frazione che PASSA (invertirla non dà nessun errore,
## dà uno scudo che raddoppia il danno), la bottega vende a `value * 0.5`, e un
## colpo alle spalle deve entrare pieno o il posizionamento smette di contare.

const FANTE := "res://arcanium/characters/sylvorn_fante.tscn"
const SPADONE := "res://arcanium/characters/sylvorn_fante_spadone.tscn"
const SCUDO := "res://arcanium/resources/equipment/scudo_guarnigione_sylvorn.tres"

## Quanto deve essere BLOCCATO, per tipo. Sono i numeri di progetto: se qualcuno
## tocca lo scudo, questo cancello lo dice.
const ATTESO_BLOCCO := {
	"TAGLIO": 0.85, "PERFORAZIONE": 0.85, "SCHIANTO": 0.60,
	"FUOCO": 0.90, "SACRO": 0.75,
	"CRIO": 0.25, "EROSIONE": 0.25, "FRATTURA": 0.25,
	"VELENO": 0.25, "FULMINE": 0.25,
}

class ColpoFinto extends RefCounted:
	var power : int = 20
	var damage_type : String = "TAGLIO"
	func _init(p : int, t : String) -> void:
		power = p
		damage_type = t

var guasti := 0

## ⚠️ `_initialize()` e NON `_init()`: in uno script SceneTree l'`_init` gira
## mentre l'albero si sta ancora costruendo, quindi ogni nodo aggiunto a `root`
## risulta `!is_inside_tree()` e **ogni `global_transform` torna l'identità**.
## Il test direzionale passava per finta: davanti e dietro erano lo stesso punto.
func _initialize() -> void:
	_tabella_scudo()
	_avvia()


## ⚠️ E non basta `_initialize`: serve ASPETTARE UN FRAME. Prima di quello i nodi
## aggiunti a `root` non sono ancora dentro l'albero, `global_transform` torna
## l'identità e il test direzionale confronta due punti coincidenti — cioè
## risponde "sì" a qualunque domanda.
func _avvia() -> void:
	await process_frame
	_prova_in_gioco()
	_passo_di_fanteria()
	print("\n%s — %d problemi" % ["FALLITO" if guasti > 0 else "PASSATO", guasti])
	quit(1 if guasti > 0 else 0)


func _tabella_scudo() -> void:
	print("=== SCUDO DI GUARNIGIONE SYLVORN ===")
	var sc : Resource = load(SCUDO)
	if sc == null:
		print("  ⚠ lo scudo non carica"); guasti += 1; return
	print("  vendita a Solan: %d Arcanium  (value %d × resa 0.5)" %
		[int(round(float(sc.value) * 0.5)), int(sc.value)])
	if int(round(float(sc.value) * 0.5)) != 50:
		print("  ⚠ NON sono i 50 previsti"); guasti += 1
	for tipo in ATTESO_BLOCCO.keys():
		if not sc.block_resistances.has(tipo):
			print("  ⚠ %-13s ASSENTE dalla tabella" % tipo); guasti += 1; continue
		var passa := float(sc.block_resistances[tipo])
		var bloccato := 1.0 - passa
		var ok : bool = absf(bloccato - float(ATTESO_BLOCCO[tipo])) < 0.001
		print("  %-13s blocca %3.0f%%  (passa %.2f)%s" %
			[tipo, bloccato * 100.0, passa, "" if ok else "   ⚠ atteso %.0f%%" % (float(ATTESO_BLOCCO[tipo]) * 100.0)])
		if not ok:
			guasti += 1


## ⚠️ CHI PORTA LO SCUDO NON CORRE, e non e' una taratura di velocita': un
## fante di linea avanza, non carica. A schermo la differenza si legge subito —
## una corsa con lo scudo davanti sembra una fuga in avanti invece di una
## manovra. Il Fante Spadone, che lo scudo non ce l'ha, deve continuare a correre.
func _passo_di_fanteria() -> void:
	print("
=== chi ha lo scudo avanza, non carica ===")
	for percorso in [FANTE, SPADONE]:
		var n : Node = (load(percorso) as PackedScene).instantiate()
		root.add_child(n)
		n.set_physics_process(false)
		n.target = n           # basta un bersaglio valido: qui si guarda la CLIP
		n._chase(1.0 / 60.0, n.run_distance + 6.0)
		var clip : String = str(n.get("_current_anim"))
		var corre : bool = clip == n.run_anim
		var deve : bool = n.get("insegue_di_corsa")
		print("  %-30s scudo:%-3s insegue_di_corsa:%-5s -> %s"
			% [percorso.get_file(), "si" if n.scudo != null else "no", str(deve), clip])
		if corre != deve:
			print("  ROTTO  %s da %.1f m %s" % [percorso.get_file(), n.run_distance + 6.0,
				"CORRE e non dovrebbe" if corre else "cammina e dovrebbe correre"])
			guasti += 1
		else:
			print("  ok    %s" % ("corre" if corre else "avanza camminando"))
		n.queue_free()


## La prova che conta: due Fanti veri, colpi veri, vita misurata.
func _prova_in_gioco() -> void:
	for path in [FANTE, SPADONE]:
		var scena : PackedScene = load(path)
		var n : Node = scena.instantiate()
		root.add_child(n)
		var hs = n.get_node_or_null("HealthSystem")
		var ha_scudo : bool = n.get("scudo") != null
		print("\n=== %s (scudo: %s) ===" % [path.get_file(), "sì" if ha_scudo else "no"])

		# frontale, in guardia
		n._in_guardia = ha_scudo
		for prova in [[20, "TAGLIO"], [34, "SCHIANTO"], [30, "FUOCO"]]:
			var prima : float = hs._health_f
			n._blocca(null, ColpoFinto.new(int(prova[0]), str(prova[1]))) if ha_scudo \
				else hs.apply_damage(float(prova[0]), str(prova[1]))
			var perso : float = prima - hs._health_f
			var atteso : float = float(prova[0]) * (1.0 - float(ATTESO_BLOCCO.get(prova[1], 0.0))) if ha_scudo else float(prova[0])
			var ok : bool = absf(perso - atteso) < 0.01
			print("  %-12s potenza %2d -> perde %5.2f HP (atteso %5.2f)%s" %
				[prova[1], prova[0], perso, atteso, "" if ok else "   ⚠"])
			if not ok:
				guasti += 1
			hs._health_f = float(hs.total_health)

		if ha_scudo:
			# ⚠ il colpo ALLE SPALLE deve entrare PIENO
			n._in_guardia = true
			var dietro := Node3D.new()
			root.add_child(dietro)
			dietro.global_position = n.global_position - n.global_transform.basis.z * 2.0
			var copre_dietro : bool = n._guardia_copre(dietro)
			print("  colpo alle spalle: %s" % ("⚠ PARATO (sbagliato)" if copre_dietro else "entra pieno, giusto"))
			if copre_dietro:
				guasti += 1
			var davanti := Node3D.new()
			root.add_child(davanti)
			davanti.global_position = n.global_position + n.global_transform.basis.z * 2.0
			var copre_davanti : bool = n._guardia_copre(davanti)
			print("  colpo frontale   : %s" % ("parato, giusto" if copre_davanti else "⚠ NON parato"))
			if not copre_davanti:
				guasti += 1
			dietro.free(); davanti.free()

			# la guardia si ROMPE accumulando
			n._in_guardia = true
			n._guardia_assorbito = 0.0
			var colpi := 0
			while n._in_guardia and colpi < 20:
				n._blocca(null, ColpoFinto.new(20, "TAGLIO"))
				colpi += 1
			print("  guardia rotta dopo %d fendenti da 20 (tenuta %.0f)" % [colpi, n.guardia_tenuta])
			if colpi >= 20:
				print("  ⚠ non si rompe mai"); guasti += 1

		# ⚠ un Consumato non para MAI: non deve esistere il gancio del parry
		var para : bool = n.has_method("parry") or bool(n.get("parry_active") != null)
		print("  può fare PARRY: %s" % ("⚠ SÌ — non deve" if para else "no, corretto"))
		if para:
			guasti += 1
		n.queue_free()
