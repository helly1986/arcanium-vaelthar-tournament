extends RefCounted

## Il colpo di una trappola, nella forma che hit() e l'HealthSystem leggono
## (come un'arma): potenza, tipo di danno, e gli accumuli di status.

var power : float = 10.0
var damage_type : String = "FISICO"
var frozen_buildup : float = 0.0
var imparabile := false
var imparriabile := false


## Lo porta a segno su un corpo: hit() se ce l'ha (animazione di dolore,
## parata e guardia valgono), altrimenti il danno diretto.
func colpisci(corpo : Node, autore : Node) -> bool:
	if corpo == null or not is_instance_valid(corpo):
		return false
	if corpo.has_method("hit") and "health_system" in corpo and corpo.health_system != null:
		## I nemici non devono mettersi a inseguire la trappola: niente autore.
		corpo.hit(autore if corpo.is_in_group("player") else null, self)
		return true
	var hs = corpo.get("health_system")
	if hs != null and hs.has_method("apply_damage"):
		hs.apply_damage(power, damage_type)
		return true
	return false
