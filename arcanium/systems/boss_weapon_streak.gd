extends MeshStreak
class_name BossWeaponStreak

## Scia della lama del boss, gemella di quella del player (`weapon_streak.gd`).
##
## Il punto NON è decorativo: come nel template, la scia è agganciata alla
## finestra in cui la hitbox della lama è davvero attiva, quindi disegna
## letteralmente cosa colpisce. Se la vedi passare sopra la tua testa, quel
## colpo non ti ha toccato — è l'onestà spaziale che rende leggibile il combat.
##
## Non si può riusare `weapon_streak.gd` così com'è: il suo `sync_property()`
## legge `get_parent().current_equipment`, che esiste solo sotto un
## EquipmentSystem. Il boss non lo usa (perderebbe la potenza per-mossa della
## EnemyMove), quindi qui leggiamo direttamente la hitbox.

## L'Area3D della lama: la scia emette esattamente quando questa monitora.
@export var blade : Area3D

func sync_property() -> void:
	if blade:
		emitting = blade.monitoring
