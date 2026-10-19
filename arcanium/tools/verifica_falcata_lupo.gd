extends SceneTree

## Che velocità legge il controller dalla clip, in gioco?
##
## Istanzia lupo e Alpha davvero, e stampa il numero che uscirà da
## `_velocita_di_falcata` — quello che finisce in `velocity` durante
## l'inseguimento. Va confrontato con la falcata misurata da
## `arcanium/tools/misura_falcata_lupo.py`, moltiplicata per la scala del
## modello: se non torna, il lupo pattina.
##
##   godot --headless --script res://arcanium/tools/verifica_falcata_lupo.gd

const SCENE := {
	"Lupo": "res://arcanium/characters/lupo.tscn",
	"Alpha": "res://arcanium/characters/lupo_alpha.tscn",
}
## Metri al secondo misurati sulle zampe piantate, a scala 1.
const MISURATO := {"walk": 0.355, "run": 1.092}


var _fatto := false

## ⚠️ Non in `_initialize`: lì i nodi appena appesi non risultano ancora
## `is_inside_tree()`, e `global_transform` restituisce l'identità con un errore
## in console — la scala del modello usciva 1.00 per tutti.
func _process(_delta : float) -> bool:
	if _fatto:
		return true
	_fatto = true
	_esamina()
	return true


func _esamina() -> void:
	var radice := Node3D.new()
	root.add_child(radice)

	for etichetta in SCENE:
		var ps : PackedScene = load(SCENE[etichetta])
		if ps == null:
			print("MANCA la scena ", SCENE[etichetta])
			continue
		var n = ps.instantiate()
		radice.add_child(n)

		var scala := 1.0
		if n.model != null:
			scala = n.model.global_transform.basis.get_scale().x
		print("── %s  scala modello %.2f  anim_speed_scale %.2f  walk_speed %.2f  run_speed %.2f"
			% [etichetta, scala, n.anim_speed_scale, n.walk_speed, n.run_speed])
		print("   root_motion_track: '%s'" % str(n.anim_player.root_motion_track))
		var w : Animation = n.anim_player.get_animation(n.walk_anim)
		if w != null:
			var con_root := []
			for t in w.get_track_count():
				var p := str(w.track_get_path(t))
				if p.contains("Root"):
					con_root.append(p + " tipo=" + str(w.track_get_type(t)))
			print("   tracce con 'Root' in walk: %s" % str(con_root))

		for coppia in [["walk", n.walk_anim, n.walk_speed], ["run", n.run_anim, n.run_speed]]:
			var chiave : String = coppia[0]
			var clip : String = coppia[1]
			var vecchia : float = coppia[2]
			var v : float = n._velocita_di_falcata(clip)
			if v <= 0.0:
				print("   %-4s clip '%s': NESSUN root motion (ripiego su %.2f)"
					% [chiave, clip, vecchia])
				continue
			## ⚠️ L'atteso comprende `anim_speed_scale`, o l'Alpha sembra sbagliato
			## del 10%: riproduce le clip a 0.9, quindi copre la stessa falcata in
			## piu' tempo ed e' GIUSTO che vada piu' piano.
			var atteso : float = MISURATO[chiave] * scala * n.anim_speed_scale
			var scarto : float = abs(v - atteso) / atteso * 100.0
			print("   %-4s clip '%s': %.3f m/s   atteso %.3f   scarto %.1f%%   (prima: %.2f, %+.0f%%)"
				% [chiave, clip, v, atteso, scarto, vecchia,
				   (vecchia - v) / v * 100.0])

		n.queue_free()

	quit()
