extends SceneTree

## Il BANCO DELLE IMPUGNATURE di un campione, generato dalla sua scheda:
## arcanium/tools/banco_impugnatura_<nome>.tscn, dove l'autore sistema a mano
## la presa (vedi CampioneResource.presa_arma / presa_scudo).
##
## Dentro: il GLB del campione nella posa in cui sta in gioco da fermo con
## l'arma del suo kit (a riposo la presa veniva di lato, Edran 2026-10-23),
## gli agganci RightHand e LeftHand con i perni del player, `Sword` con dentro
## il modello dell'arma del kit (held_model) e `Shield` se il kit ha lo scudo.
## Sword e Shield partono dalla presa gia' nella scheda.
##
## La posa: con un'arma a una mano la POSA del GLB (fotogramma 0); con
## un'arma a due mani la GUARDIA della HeavyIdle del moveset, portata sul suo
## corpo, perche' la sinistra deve trovare l'asta (Zarine, Aurin).
##
## I nodi aggiunti dentro il GLB vogliono `[editable path=...]`, o il primo
## salvataggio dall'editor li butta via: qui si mette da se'. Si genera una
## volta per campione: rigenerarlo cancella cio' che l'autore ha sistemato e
## non e' ancora nella scheda.
##
## Uso: godot --headless --path . --script res://arcanium/tools/banco_impugnatura.gd -- <casata> [uscita.tscn]

const PLAYER := "res://characters/player_dawnkeep_v4.tscn"
const SCHELETRO_PLAYER := "protagonist/BaseArmature/GeneralSkeleton"
const MOVESET := "res://player/animation_libraries/MeleeLib.res"
const GUARDIA_PESANTE := "HeavyIdle"
const SPADA := "res://characters/equipment/sword_arcane.tscn"
const SCUDO := "res://player/equipment_system/equipment/shield.tscn"
const PERNO_DESTRA := "WeaponSystem/RightHand/HandPivot"
const PERNO_SINISTRA := "GadgetSystem/LeftHand/HandPivot"
const Retarget := preload("res://arcanium/tools/rig_retarget.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("uso: ... -- <casata> [uscita.tscn]")
		quit(1)
		return
	var scheda : Resource = load("res://arcanium/resources/campioni/%s.tres" % args[0])
	var nome := String(scheda.nome).split(" ")[0]
	var uscita : String = args[1] if args.size() > 1 else "res://arcanium/tools/banco_impugnatura_%s.tscn" % nome.to_lower()
	var kit : Resource = load(scheda.dotazione["arma_primaria"]) if scheda.dotazione.has("arma_primaria") else null
	var pesante := kit != null and String(kit.object_type) == "HEAVY"

	## I perni delle mani e lo scheletro su cui e' cotto il moveset, dalla
	## scena del player (non entra nell'albero).
	var pl : Node = (load(PLAYER) as PackedScene).instantiate()
	var perno_d : Transform3D = (pl.get_node(PERNO_DESTRA) as Node3D).transform
	var perno_s : Transform3D = (pl.get_node(PERNO_SINISTRA) as Node3D).transform

	## La posa, letta da un'istanza nell'albero.
	var corpo : Node3D = (load(scheda.corpo) as PackedScene).instantiate()
	root.add_child(corpo)
	var sk : Skeleton3D = corpo.find_children("*", "Skeleton3D", true, false)[0]
	var posa := ""
	if pesante:
		var guardia := Retarget.retarget((load(MOVESET) as AnimationLibrary).get_animation(GUARDIA_PESANTE),
				pl.get_node(SCHELETRO_PLAYER) as Skeleton3D, sk)
		for k in guardia.get_track_count():
			var osso := sk.find_bone(String(guardia.track_get_path(k).get_concatenated_subnames()))
			if osso < 0 or osso == sk.find_bone("Root"):
				continue
			match guardia.track_get_type(k):
				Animation.TYPE_ROTATION_3D:
					sk.set_bone_pose_rotation(osso, guardia.rotation_track_interpolate(k, 0.0))
				Animation.TYPE_POSITION_3D:
					sk.set_bone_pose_position(osso, guardia.position_track_interpolate(k, 0.0))
		posa = GUARDIA_PESANTE
	else:
		for n in corpo.find_children("*", "AnimationPlayer", true, false):
			var ap := n as AnimationPlayer
			if ap.has_animation("Posa"):
				ap.play("Posa")
				ap.seek(0.0, true)
				posa = "Posa"
	pl.free()
	var p_sk := String(corpo.get_path_to(sk))

	## Il testo della scena, come lo salva l'editor (una scena salvata con
	## PackedScene.pack si portava dentro tutte le mesh del GLB: 3,5 MB).
	var risorse := [scheda.corpo, SPADA]
	var modello : PackedScene = kit.held_model if kit != null and "held_model" in kit else null
	if modello != null:
		risorse.append(modello.resource_path)
	var con_scudo : bool = scheda.dotazione.has("scudo")
	if con_scudo:
		risorse.append(SCUDO)
	var t := "[gd_scene format=3]\n\n"
	for k in risorse.size():
		t += '[ext_resource type="PackedScene" path="%s" id="%d"]\n' % [risorse[k], k + 1]
	t += '\n[node name="BancoImpugnatura%s" type="Node3D"]\n\n' % nome
	t += '[node name="%s" parent="." instance=ExtResource("1")]\n\n' % nome
	t += '[node name="%s" parent="%s/%s"]\n' % [sk.name, nome, p_sk.get_base_dir()]
	for b in sk.get_bone_count():
		if not sk.get_bone_pose_position(b).is_equal_approx(sk.get_bone_rest(b).origin):
			t += "bones/%d/position = %s\n" % [b, var_to_str(sk.get_bone_pose_position(b))]
		t += "bones/%d/rotation = %s\n" % [b, var_to_str(sk.get_bone_pose_rotation(b))]
	t += "\n"
	var p_osso := "%s/%s" % [nome, p_sk]
	t += _mano(p_osso, "RightHand", perno_d, "Sword", 2, scheda.presa_arma)
	var p_spada := "%s/RightHand/HandPivot/Sword" % p_osso
	var editabili := [nome]
	if modello != null:
		## Il modello dell'arma del kit, come lo monta held_weapon.gd: quelli
		## della spada del player si spengono.
		var spada : Node = (load(SPADA) as PackedScene).instantiate()
		for figlio in spada.get_children():
			if figlio is VisualInstance3D:
				t += '[node name="%s" parent="%s"]\nvisible = false\n\n' % [figlio.name, p_spada]
		spada.free()
		t += '[node name="ModelloEquipaggiato" parent="%s" instance=ExtResource("3")]\ntransform = %s\n\n' % [
				p_spada, var_to_str(kit.held_transform)]
		editabili.append(p_spada)
	if con_scudo:
		t += _mano(p_osso, "LeftHand", perno_s, "Shield", risorse.find(SCUDO) + 1, scheda.presa_scudo)
	for e in editabili:
		t += '[editable path="%s"]\n' % e
	var f := FileAccess.open(uscita, FileAccess.WRITE)
	f.store_string(t)
	f.close()
	print("BANCO: %s, posa %s, in mano %s%s -> %s" % [nome, posa if posa != "" else "MANCANTE",
			kit.name if kit != null else "la spada del player", ", scudo" if con_scudo else "", uscita])
	quit()


## Aggancio all'osso, perno del player e l'oggetto con la presa della scheda.
func _mano(p_osso : String, osso : String, perno : Transform3D, nome : String, risorsa : int,
		presa : Transform3D) -> String:
	var t := '[node name="%s" type="BoneAttachment3D" parent="%s"]\nbone_name = "%s"\n\n' % [osso, p_osso, osso]
	t += '[node name="HandPivot" type="Marker3D" parent="%s/%s"]\ntransform = %s\n\n' % [p_osso, osso, var_to_str(perno)]
	t += '[node name="%s" parent="%s/%s/HandPivot" instance=ExtResource("%d")]\ntransform = %s\n\n' % [
			nome, p_osso, osso, risorsa, var_to_str(presa)]
	return t
