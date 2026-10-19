extends Node

## Regista del Prologo nell'Arena Senza Fuoco. Porta in Godot il flusso di Game.js
## (_checkDeaths / _transitionToHub) di Arcanium-Lite, senza logica invasiva nel
## template: ascolta i segnali di morte di boss e player e pilota Announcer,
## inventario, veleno scriptato e il cambio scena a fine scontro.
##
## Vaelthar Tournament: il Crocevia (l'hub di Arcanium) non c'e' piu' e il
## roguelike non ha ancora il suo. Finche' non arriva la mappa della run, a fine
## scontro si torna al menu principale e non si registra nessun checkpoint.
##
##  • Boss morto   → "LEGEND DEFEATED", popup "Ottenuto: Spada del Senza Nome",
##    spada nell'inventario, avvio del veleno scriptato. Esito Prologo = vittoria.
##  • Player morto (dal boss o dal veleno) → "BACK TO ARCANIUM FLOW", poi risveglio
##    a `hub_scene_path` (oggi il menu). Esito = sconfitta (se non già vittoria).
##
## Da mettere come nodo nell'arena; assegnare `boss` e `player` in editor.

@export var boss : Node
@export var player : Node
@export var hub_scene_path : String = "res://arcanium/ui/main_menu/main_menu.tscn"

## Attesa tra "LEGEND DEFEATED" e popup spada + avvio veleno.
@export var legend_hold : float = 3.0
## Attesa tra "BACK TO ARCANIUM FLOW" e il cambio scena verso l'hub.
@export var death_to_hub_delay : float = 2.5

const ScriptedPoisonScript := preload("res://arcanium/systems/scripted_poison.gd")
const SWORD_ITEM := preload("res://arcanium/resources/items/spada_senza_nome.tres")
const POISON_DEATH_FALLBACK_SEC := 6.5


var _handled_boss := false
var _handled_player := false
var _poison : Node

func _ready() -> void:
	_poison = ScriptedPoisonScript.new()
	add_child(_poison)

	if boss and boss.has_signal("death_started"):
		boss.death_started.connect(_on_boss_death)
	if player and player.has_signal("death_started"):
		player.death_started.connect(_on_player_death)

## Vittoria: registra l'esito, annuncia, poi consegna la spada + avvia il veleno.
func _on_boss_death() -> void:
	if _handled_boss:
		return
	_handled_boss = true

	var save := get_node_or_null("/root/SaveManager")
	if save:
		save.set_outcome("victorious")

	var announcer := get_node_or_null("/root/Announcer")
	if announcer:
		announcer.legend_defeated()

	await get_tree().create_timer(legend_hold).timeout

	var inventory := get_node_or_null("/root/ArcaniumInventory")
	if inventory:
		## Il popup NON si chiama più qui: ci pensa l'Announcer agganciato al
		## segnale `item_added` dell'inventario. Chiamarlo anche a mano darebbe
		## due popup sovrapposti per la stessa spada.
		inventory.add(SWORD_ITEM, 1)

	# Morte per veleno: il player si afferra la gola e stramazza a terra, TUTTI i
	# comandi bloccati (si guarda solo la fine). Allineiamo la durata del veleno
	# alla lunghezza della clip, così gli HP si azzerano col collasso → died →
	# player.death() → back_to_arcanium → hub.
	var death_len := POISON_DEATH_FALLBACK_SEC
	if player and player.has_method("begin_poison_death"):
		death_len = player.begin_poison_death()
	if player and "health_system" in player and player.health_system:
		_poison.duration = death_len
		_poison.start(player.health_system)

## Sconfitta (dal boss o dal veleno post-vittoria) → si esce dall'arena.
func _on_player_death() -> void:
	if _handled_player:
		return
	_handled_player = true

	var save := get_node_or_null("/root/SaveManager")
	if save:
		if save.get_outcome() != "victorious":
			save.set_outcome("defeated")

	var announcer := get_node_or_null("/root/Announcer")
	if announcer:
		announcer.back_to_arcanium()

	await get_tree().create_timer(death_to_hub_delay).timeout

	if announcer:
		announcer.clear()
	_go_to_hub()


func _go_to_hub() -> void:
	get_tree().change_scene_to_file(hub_scene_path)
