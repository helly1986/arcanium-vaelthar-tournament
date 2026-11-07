extends StatusEffect

## ⚠️ Niente `class_name`: si importa con `preload` (status_host.gd).

## Bagnato — chi e' stato in acqua, o colpito da spell ed effetti che bagnano (2026-11-07).
## Da solo non fa danni: prepara lo Shock (shock_effect.gd), che da bagnato morde di piu' e
## azzera la soglia in piu'. Si rinnova finche' si resta nell'acqua.


func _init() -> void:
	id = "bagnato"
	label = "Wet"
	icon = "💧"
	color = Color("#5aa9e6")
	duration = 10.0


## Sull'acqua il fulmine morde di piu', in ogni colpo.
func damage_multiplier_for(dtype : String) -> float:
	return 1.25 if dtype == "FULMINE" else 1.0
