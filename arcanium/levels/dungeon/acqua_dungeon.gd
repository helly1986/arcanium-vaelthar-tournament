extends Area3D

## L'acqua dei canali: chi ci cammina dentro va piano (rallentamento_terreno
## del giocatore, vedi player_charbody3D.gd). I nemici non ci entrano: per la
## guida l'acqua non e' pavimento, ma ci possono finire spinti.
##
## Chi ci sta dentro e' anche BAGNATO (bagnato_effect.gd), finche' ci resta e ancora per
## un po' dopo: prepara lo Shock.

@export_range(0.1, 1.0) var rallentamento : float = 0.45


func _ready() -> void:
	collision_layer = 0
	## Il giocatore (2) e i nemici (4).
	collision_mask = 2 | 4
	monitoring = true
	body_entered.connect(_dentro)
	body_exited.connect(_fuori)


func _dentro(corpo : Node) -> void:
	if "rallentamento_terreno" in corpo:
		corpo.rallentamento_terreno = rallentamento
	_bagna(corpo)


## Si rinnova finche' si resta dentro.
func _physics_process(_delta : float) -> void:
	for corpo in get_overlapping_bodies():
		_bagna(corpo)


func _bagna(corpo : Node) -> void:
	var salute = corpo.get("health_system")
	var host = salute.get("status_host") if salute != null else null
	if host != null and host.has_method("bagna"):
		host.bagna()


func _fuori(corpo : Node) -> void:
	if "rallentamento_terreno" in corpo:
		corpo.rallentamento_terreno = 1.0
