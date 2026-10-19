extends SceneTree

## Prova che il punto di mira del lock-on stia sulla MESH del bersaglio, e che
## il colpo scenda quando il nemico e' piu' basso del player.
##
## Perche' esiste: il mirino usava una quota FISSA di 2.2 m, tarata sugli
## umanoidi (~3 m). Su un lupo galleggiava sopra la schiena, e l'Ice Shard —
## che parte orizzontale dall'altezza del petto — gli passava sopra.
##
## Uso: godot --headless --script arcanium/tools/verifica_mira_lockon.gd

const BERSAGLI := [
	"res://arcanium/characters/lupo.tscn",
	"res://arcanium/characters/consumato.tscn",
]
## Altezza della bocca da fuoco del player (player_charbody3D.spell_muzzle_offset.y)
const QUOTA_MUZZLE := 1.4
## Distanza tipica di tiro, per stampare l'inclinazione in gradi.
const DISTANZA := 8.0
## Quota che il mirino usava prima, per confronto.
const VECCHIA_QUOTA := 2.2


func _init() -> void:
	## L'albero non e' ancora pronto dentro `_init`: senza questa attesa il primo
	## `add_child` non attecchisce e piazzare il bersaglio stampa un errore su
	## `get_global_transform`.
	await process_frame
	var esito := 0
	var lock := load("res://arcanium/systems/lock_on/iso_lock_on.gd").new() as Node3D
	get_root().add_child(lock)
	for percorso in BERSAGLI:
		esito = maxi(esito, await _prova(lock, percorso))
	print("esito: ", "MIRA SANA" if esito == 0 else "PROBLEMI")
	quit(esito)


func _prova(lock : Node3D, percorso : String) -> int:
	if not ResourceLoader.exists(percorso):
		print("ASSENTE ", percorso)
		return 1
	var pg : Node3D = load(percorso).instantiate()
	get_root().add_child(pg)
	pg.global_position = Vector3(0.0, 0.0, DISTANZA)
	await process_frame
	await process_frame

	var mira : Vector3 = lock.aim_point(pg)
	var alto := mira == Vector3.ZERO
	var origine := Vector3(0.0, QUOTA_MUZZLE, 0.0)
	var d := (mira - origine).normalized()
	var pendenza := rad_to_deg(asin(d.y))
	var vecchia := (pg.global_position + Vector3.UP * VECCHIA_QUOTA - origine).normalized()

	print("%-42s mira y=%.2f  (vecchia quota fissa y=%.2f)" % [
		percorso.get_file(), mira.y, pg.global_position.y + VECCHIA_QUOTA])
	print("    tiro da %.2f m: %+.1f gradi  (prima %+.1f gradi)" % [
		QUOTA_MUZZLE, pendenza, rad_to_deg(asin(vecchia.y))])
	pg.queue_free()
	await process_frame
	if alto:
		print("    NESSUNA MESH TROVATA: si ripiega sulla quota fissa")
		return 1
	return 0
