extends SceneTree

## Controllo di SANITA' di una clip sul nemico vero, senza aprire finestre.
##
## Perche' esiste: una clip esportata con le ossa in centimetri invece che in
## metri passa TUTTI i controlli di struttura — file valido, tracce giuste,
## durata giusta — e in gioco fa esplodere il personaggio. L'unico modo di
## accorgersene senza guardare e' misurare l'INGOMBRO dello scheletro mentre la
## clip gira, e confrontarlo con una clip che si sa sana.
##
## Uso: godot --headless --script arcanium/tools/verifica_clip_nemico.gd

## Ogni voce: scena del nemico, clip di RIFERIMENTO sana, clip da provare.
const BANCHI := [
	{
		"scena": "res://arcanium/characters/consumato.tscn",
		"riferimento": "sword/sword_light_attack_01",
		"prova": ["spear/spear_thrust_01", "spear/spear_thrust_charged_01"],
	},
	{
		"scena": "res://arcanium/characters/lupo.tscn",
		"riferimento": "wolf/wolf_bite_01",
		"prova": ["wolf/wolf_bite_combo_01", "wolf/wolf_death_01"],
	},
]
## Un umanoide sta dentro un paio di metri. Oltre, e' esploso.
const LIMITE_ALTEZZA := 3.0


func _init() -> void:
	var esito := 0
	for banco in BANCHI:
		esito = maxi(esito, await _banco(banco))
	print("esito: ", "TUTTO SANO" if esito == 0 else "PROBLEMI")
	quit(esito)


func _banco(banco : Dictionary) -> int:
	var pg : Node3D = load(banco["scena"]).instantiate()
	get_root().add_child(pg)
	await process_frame
	await process_frame
	var sk : Skeleton3D = pg.find_child("Skeleton3D", true, false)
	var ap : AnimationPlayer = pg.find_child("AnimationPlayer", true, false)
	var esito := 0
	var rif : String = banco["riferimento"]
	if sk == null or ap == null or not ap.has_animation(rif):
		print("BANCO NON PRONTO: ", banco["scena"], " (riferimento ", rif, ")")
		pg.queue_free()
		return 1
	var atteso := await _misura(sk, ap, rif)
	print("RIFERIMENTO %-34s ingombro %.2f x %.2f x %.2f" % [rif, atteso.x, atteso.y, atteso.z])
	for nome in banco["prova"]:
		if not ap.has_animation(nome):
			print("ASSENTE     %s" % nome)
			esito = 1
			continue
		var d : Vector3 = await _misura(sk, ap, nome)
		var rapporto : float = d.y / maxf(atteso.y, 0.001)
		var ok : bool = d.y < LIMITE_ALTEZZA and rapporto > 0.6 and rapporto < 1.6
		print("%-11s %-34s ingombro %.2f x %.2f x %.2f  (altezza %.2fx il riferimento)" %
			["OK" if ok else "ROTTA", nome, d.x, d.y, d.z, rapporto])
		if not ok:
			esito = 1
	pg.queue_free()
	await process_frame
	return esito


## Ingombro massimo dello scheletro durante la clip: campiona le ossa a piu'
## istanti e tiene il riquadro piu' grande visto.
func _misura(sk : Skeleton3D, ap : AnimationPlayer, nome : String) -> Vector3:
	var peggio := Vector3.ZERO
	var a := ap.get_animation(nome)
	for i in 12:
		var t : float = a.length * float(i) / 11.0
		ap.play(nome, 0.0, 1.0)
		ap.seek(t, true)
		await process_frame
		var basso := Vector3.INF
		var alto := -Vector3.INF
		for b in sk.get_bone_count():
			var p : Vector3 = sk.get_bone_global_pose(b).origin
			basso = basso.min(p)
			alto = alto.max(p)
		peggio = peggio.max(alto - basso)
	return peggio
