extends SceneTree

## Cancello del CORPO DEL CAMPIONE in gioco (arcanium/systems/corpo_campione.gd),
## per ognuno dei sei campioni, dentro il dungeon vero:
##   1. il giocatore porta il corpo del campione della run: le ossa del suo
##      GLB nel GeneralSkeleton di sempre, la sua mesh visibile, quelle del
##      protagonista svuotate (niente Skin che cerca ossa che non ci sono);
##   2. mani e schiena hanno l'osso giusto: armi e scudo seguono il campione;
##   3. da fermo suona la sua Posa (braccia lungo i fianchi), non la guardia
##      del moveset; e gli attacchi ci sono, portati sul suo scheletro;
##   4. ArmaturaIndossata e' spenta: sul campione non si indossa nessun pezzo;
##   5. il kit e' quello della sua casata (dotazione della scheda): l'arma in
##      mano e' la sua, e lo scudo in mano sinistra c'e' solo se il kit ce l'ha.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_corpo_campione.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const CASATE := ["dawnkeep", "sylvorn", "vorrkai", "aethon", "verath", "amareth"]
const ATTESE := 6 * 5

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	var salva : Node = root.get_node("SaveManager")
	for casa in CASATE:
		salva._house = casa
		root.get_node("EquipmentLoadout").clear_all()
		var scheda : Resource = load("res://arcanium/resources/campioni/%s.tres" % casa)
		var glb : Node = (load(scheda.corpo) as PackedScene).instantiate()
		var sk_glb : Skeleton3D = glb.find_children("*", "Skeleton3D", true, false)[0]
		var ossa_glb := sk_glb.get_bone_count()
		glb.free()

		var scena : Node = load("res://arcanium/levels/dungeon/dungeon_prova.tscn").instantiate()
		scena.get_node("Dungeon").seme = 0
		root.add_child(scena)
		for k in 10:
			await process_frame
		var pl : Node = scena.get_node("Player")
		var corpo : Node = pl.get_node("CorpoCampione")
		var sk : Skeleton3D = pl.get_node("protagonist/BaseArmature/GeneralSkeleton")

		## 1.
		var visibili : Array = []
		var con_skin_vecchia := 0
		for m in sk.get_children():
			if m is MeshInstance3D:
				var mi := m as MeshInstance3D
				if mi.visible and mi.mesh != null:
					visibili.append(String(mi.name))
				elif mi.skin != null:
					con_skin_vecchia += 1
		_ok(corpo.campione == scheda and sk.get_bone_count() == ossa_glb and visibili.size() >= 1
				and con_skin_vecchia == 0,
				"%s: corpo di %s, %d ossa (GLB %d), mesh %s, skin vecchie %d" % [casa,
				corpo.campione.nome if corpo.campione != null else "nessuno", sk.get_bone_count(), ossa_glb,
				str(visibili), con_skin_vecchia])

		## 2.
		var storti : Array = []
		for ba in pl.find_children("*", "BoneAttachment3D", true, false):
			var b := ba as BoneAttachment3D
			if b.bone_name != "" and b.use_external_skeleton and b.get_node_or_null(b.external_skeleton) == sk \
					and sk.find_bone(b.bone_name) < 0:
				storti.append(b.bone_name)
		_ok(storti.is_empty() and sk.find_bone("RightHand") >= 0 and sk.find_bone("LeftHand") >= 0,
				"%s: gli agganci trovano le loro ossa %s" % [casa, str(storti)])

		## 3.
		var ap : AnimationPlayer = pl.get_node("protagonist/AnimationPlayer")
		var idle := ap.get_animation("MeleeLib/LightIdle")
		var fendente := ap.get_animation("MeleeLib/root-Slash1")
		ap.play("MeleeLib/LightIdle")
		ap.seek(0.0, true)
		var bacino := sk.get_bone_global_pose(sk.find_bone("Hips")).origin.y
		var mani_giu := sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin.y < bacino \
				and sk.get_bone_global_pose(sk.find_bone("RightHand")).origin.y < bacino
		_ok(idle != null and mani_giu and fendente != null and fendente.get_track_count() > 0,
				"%s: da fermo in Posa con le mani sotto il bacino (%s), il fendente c'e' (%d tracce)" % [casa,
				mani_giu, fendente.get_track_count() if fendente != null else 0])

		## 4.
		var arm : Node = pl.get_node_or_null("ArmaturaIndossata")
		_ok(arm == null or (arm.get_script() == null and arm.process_mode == Node.PROCESS_MODE_DISABLED),
				"%s: ArmaturaIndossata spenta" % casa)

		## 5.
		var armadio : Node = root.get_node("EquipmentLoadout")
		var arma_kit : Resource = load(scheda.dotazione["arma_primaria"])
		var in_mano = pl.get_node("WeaponSystem").current_equipment
		var info = in_mano.equipment_info if in_mano != null else null
		var scudo : Node3D = pl.get_node("GadgetSystem/LeftHand/HandPivot/Shield")
		var vuole_scudo : bool = scheda.dotazione.has("scudo")
		_ok(armadio.equipped_in("arma_primaria") == arma_kit and info == arma_kit and scudo.visible == vuole_scudo,
				"%s: kit di casata, in mano %s, scudo %s" % [casa,
				info.name if info != null and "name" in info else "-", "visibile" if scudo.visible else "nascosto"])

		root.remove_child(scena)
		scena.free()
		await process_frame

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
