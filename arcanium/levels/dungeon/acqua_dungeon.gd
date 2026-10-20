extends Area3D

## L'acqua dei canali: chi ci cammina dentro va piano (rallentamento_terreno
## del giocatore, vedi player_charbody3D.gd). I nemici non ci entrano: per la
## guida l'acqua non e' pavimento.

@export_range(0.1, 1.0) var rallentamento : float = 0.45


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_dentro)
	body_exited.connect(_fuori)


func _dentro(corpo : Node) -> void:
	if "rallentamento_terreno" in corpo:
		corpo.rallentamento_terreno = rallentamento


func _fuori(corpo : Node) -> void:
	if "rallentamento_terreno" in corpo:
		corpo.rallentamento_terreno = 1.0
