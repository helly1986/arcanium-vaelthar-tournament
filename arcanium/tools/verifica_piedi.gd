extends SceneTree

## ⛔ CANCELLO: i piedi del protagonista poggiano a terra?
##
## ⚠️ Il difetto non sta nell'ASSET: in Blender l'osso del piede va dalla
## caviglia (z 0.123) alle dita (z 0.019), cioe' in avanti e in GIU'. E' Godot
## che glielo raddrizza — `retarget/rest_fixer/fix_silhouette` allinea le ossa
## alla posa di riferimento umanoide, e per il piede quella posa e' ORIZZONTALE.
## Risultato: dita alla stessa quota della caviglia, e il personaggio cammina
## con le punte all'insu'. La pelle segue l'osso, quindi si vede.
##
## Si misura sul REST importato, non a occhio: le dita devono stare piu' in
## basso della caviglia.
##
##     godot --headless --script res://arcanium/tools/verifica_piedi.gd

const CORPO := "res://assets/characters/base_body/protagonista_v4.glb"
## quanto devono stare piu' in basso, come minimo (metri)
const DISLIVELLO_MINIMO := 0.04

var _fatto := false
var guasti := 0


func _process(_dt : float) -> bool:
	if _fatto:
		return true
	_fatto = true
	var scena := Node.new()
	root.add_child(scena)
	current_scene = scena
	var corpo = load(CORPO).instantiate()
	scena.add_child(corpo)
	var sk : Skeleton3D = corpo.find_children("*", "Skeleton3D", true, false)[0]

	for lato in ["Left", "Right"]:
		var i_piede := sk.find_bone(lato + "Foot")
		var i_dita := sk.find_bone(lato + "Toes")
		if i_piede < 0 or i_dita < 0:
			print("  ROTTO manca %sFoot o %sToes" % [lato, lato])
			guasti += 1
			continue
		var caviglia : float = sk.get_bone_global_rest(i_piede).origin.y
		var punta : float = sk.get_bone_global_rest(i_dita).origin.y
		var giu : float = caviglia - punta
		if giu >= DISLIVELLO_MINIMO:
			print("  ok    %-5s caviglia %.3f, dita %.3f -> le dita stanno %.3f piu' in basso"
				% [lato, caviglia, punta, giu])
		else:
			guasti += 1
			print("  ROTTO %-5s caviglia %.3f, dita %.3f -> dislivello %.3f (ne servono %.2f):"
				% [lato, caviglia, punta, giu, DISLIVELLO_MINIMO]
				+ " il piede e' orizzontale o all'insu'")

	print()
	if guasti == 0:
		print("TUTTO A POSTO: i piedi poggiano.")
	else:
		print("%d CONTROLLI FALLITI — guarda `fix_silhouette/filter` nel .import del corpo" % guasti)
	quit(1 if guasti > 0 else 0)
	return true
