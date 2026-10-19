extends EquipmentResource
class_name ArcaniumShieldResource

## Scudo Arcanium: a differenza del template (che nega il danno mentre `guarding`
## è true), lo scudo RIDUCE il danno per tipo — il fisico si tiene fuori quasi
## tutto, la magia passa più facilmente. Letto da `player_charbody3D.gd::block()`.
##
## Valore = frazione di danno che PASSA (0.25 = -75%, 1.0 = nessuna riduzione).

## ─── Display (menu Inventario/Equipaggiamento) ───────────────────────────────
@export var icon : String = "🛡"
## Illustrazione per la modale di equipaggiamento. Lo scudo NON deriva da
## ArcaniumEquipmentResource (estende direttamente EquipmentResource del
## template), quindi il campo va dichiarato anche qui: senza, il .tres lo
## scriveva e Godot lo scartava in silenzio — la modale mostrava il simbolo al
## posto dell'illustrazione senza che niente segnalasse l'errore.
@export var image : Texture2D
@export_multiline var lore : String = ""
@export var equip_slot : String = "scudo"

@export var block_resistances : Dictionary = {
	"FISICO": 0.25,
	"CRIO": 0.6,
	"EROSIONE": 0.6,
	"SACRO": 0.6,
	"FRATTURA": 1.0,
}
