extends SceneTree

## Prova il percorso DI MENU dei talismani, non solo il sistema sotto.
##
## Il sistema (EquipmentLoadout) era gia' coperto da verifica_bottega.gd. Qui si
## controlla la parte che si tocca col dito: che i quattro slot compaiano nel
## menu, che la modale si apra su uno slot talismano, e soprattutto che si possa
## TOGLIERE un talismano. Metterne uno e non poterlo piu' levare sarebbe una
## trappola, e su quattro slot situazionali sarebbe la trappola piu' facile da
## sbattere.
##
## Uso: godot --headless --script arcanium/tools/verifica_talismani_ui.gd

const GameMenuScript := preload("res://arcanium/ui/game_menu/game_menu.gd")
const EquipModal := preload("res://arcanium/ui/game_menu/equip_modal.gd")


func _init() -> void:
	await process_frame
	var esito := 0

	var lo := root.get_node_or_null("/root/EquipmentLoadout")
	var menu := root.get_node_or_null("/root/GameMenu")
	if lo == null or menu == null:
		push_error("EquipmentLoadout o GameMenu non registrati come autoload")
		quit(1)
		return

	## ─── gli slot nel menu ──────────────────────────────────────────────────
	var slots: Array = GameMenuScript.EQUIP_SLOTS
	print("slot nel menu: %s" % [slots])
	var talismani := 0
	for s in slots:
		if str(s).begins_with("talismano_"):
			talismani += 1
	esito = _controlla("il menu mostra quattro slot talismano", talismani == 4, esito)
	esito = _controlla("ogni slot talismano ha un'etichetta",
			GameMenuScript.EQUIP_SLOT_LABELS.has("talismano_1")
			and GameMenuScript.EQUIP_SLOT_LABELS.has("talismano_4"), esito)
	esito = _controlla("e un'icona per quando e' vuoto",
			GameMenuScript.EQUIP_SLOT_EMPTY_ICON.has("talismano_3"), esito)

	## ─── possesso e compatibilita' ──────────────────────────────────────────
	var anello: Resource = load("res://arcanium/resources/equipment/anello_arco_ambra.tres")
	esito = _controlla("senza possederlo lo slot non offre nulla",
			lo.owned_for_slot("talismano_1").is_empty(), esito)

	lo.acquire(anello)
	esito = _controlla("comprato, compare in TUTTI e quattro gli slot",
			lo.owned_for_slot("talismano_1").has(anello)
			and lo.owned_for_slot("talismano_4").has(anello), esito)
	esito = _controlla("non compare fra le armi",
			not lo.owned_for_slot("arma_primaria").has(anello), esito)

	## ─── la modale sa equipaggiare ──────────────────────────────────────────
	var modale: CanvasLayer = EquipModal.new()
	modale.set("slot_id", "talismano_2")
	modale.set("etichetta_slot", "Talismano II")
	modale.set("alternative", [null, anello])
	modale.set("equipaggiato_ora", null)
	root.add_child(modale)
	await process_frame

	modale.set("_sel", 1)          ## l'Anello
	modale._conferma()
	await process_frame
	esito = _controlla("confermando l'Anello, lo slot lo indossa",
			lo.equipped_in("talismano_2") == anello, esito)
	esito = _controlla("e il bonus e' attivo",
			is_equal_approx(lo.arcanium_multiplier(), 1.2), esito)

	## ─── e sa TOGLIERE, che e' il punto ─────────────────────────────────────
	var modale2: CanvasLayer = EquipModal.new()
	modale2.set("slot_id", "talismano_2")
	modale2.set("etichetta_slot", "Talismano II")
	modale2.set("alternative", [null, anello])
	modale2.set("equipaggiato_ora", anello)
	root.add_child(modale2)
	await process_frame

	modale2.set("_sel", 0)         ## "Nessuno"
	modale2._conferma()
	await process_frame
	esito = _controlla("scegliendo Nessuno lo slot si svuota",
			lo.equipped_in("talismano_2") == null, esito)
	esito = _controlla("il bonus sparisce con lui",
			is_equal_approx(lo.arcanium_multiplier(), 1.0), esito)
	esito = _controlla("ma l'Anello resta di tua proprieta'", lo.owns(anello), esito)

	quit(esito)


func _controlla(cosa: String, passato: bool, esito_finora: int) -> int:
	print("%s  %s" % ["[ok]" if passato else "[NO]", cosa])
	return esito_finora if passato else 1
