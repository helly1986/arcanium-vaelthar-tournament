extends Node
class_name PlayerCombatLink

## Collega il player del template ai sistemi di Arcanium SENZA logica invasiva,
## solo ascoltandone i segnali:
##  - CRISTALLI: alla morte (death_started) applica la penalità del 50% su
##    CrystalBank (l'autoload che sopravvive al reload di scena), ma solo fuori
##    dal torneo: nella run la regola e' di torneo.gd.
##
## NB: il consumo di STAMINA NON è più qui — è gestito direttamente nel player
## (`_try_spend_stamina` in player_charbody3D.gd), che spende E blocca l'azione se
## la stamina è insufficiente. Tenerlo lì evita doppio consumo e permette il gating.
##
## Da appendere come figlio del player; `player` si auto-risolve dal genitore.

@export var player : CharacterBody3D

func _ready() -> void:
	if player == null and get_parent() is CharacterBody3D:
		player = get_parent()
	if player == null:
		push_warning("PlayerCombatLink: nessun player trovato.")
		return

	# Penalità cristalli alla morte (connessione per stringa, come il template).
	if player.has_signal("death_started"):
		player.connect("death_started", _on_death)

func _on_death() -> void:
	## Nel torneo l'Arcanium lo toglie la fine dello scontro (torneo.gd), per
	## la morte come per il baratro: qui si perderebbe due volte.
	var torneo := get_node_or_null("/root/Torneo")
	if torneo != null and torneo.in_corso:
		return
	var bank := get_node_or_null("/root/CrystalBank")
	if bank:
		bank.penalize_on_death()
