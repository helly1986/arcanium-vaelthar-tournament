extends SceneTree

## Cancello della SELEZIONE DEL CAMPIONE (selezione_campione.gd) e dei dati dei
## campioni (arcanium/resources/campioni/*.tres):
##   1. sei campioni, nell'ordine delle casate, con ogni testo compilato,
##      un'affinita' che e' un tipo di danno vero e un kit;
##   2. le Marche di Sylvorn sono quelle della scheda (CON 10, VOL 10);
##   3. un campione non forgiato si vede come sagoma alta 1,8 m sulla pedana;
##   4. cambiare campione cambia il corpo (uno solo alla volta);
##   5. trascinare gira il campione;
##   6. un campione bloccato non si sceglie («Begin» spento, nessun segnale);
##   7. Dawnkeep si sceglie e la conferma dice casata e genere.
##
## Uso: godot --headless --path . --script res://arcanium/tools/verifica_selezione.gd
## (con APPDATA isolato, e project.godot da ripristinare dopo).

const ATTESE := 7
const MenuStyle := preload("res://arcanium/ui/game_menu/er_style.gd")
const HouseCatalog := preload("res://arcanium/systems/house_catalog.gd")

var _fatti := 0
var _falliti := 0


func _ok(cond : bool, cosa : String) -> void:
	_fatti += 1
	if not cond:
		_falliti += 1
	print("%s %s" % ["ok   " if cond else "NO   ", cosa])


func _init() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var s : Node = load("res://arcanium/ui/selezione_campione/selezione_campione.tscn").instantiate()
	root.add_child(s)
	await process_frame
	await process_frame

	## 1.
	var casate : Array = s.campioni.map(func(c): return c.casata)
	var buchi : Array = []
	for c in s.campioni:
		for campo in ["nome", "epiteto", "bio", "battuta", "bio_casata", "territorio", "abilita_nome", "abilita_testo"]:
			if String(c.get(campo)).strip_edges() == "":
				buchi.append("%s.%s" % [c.casata, campo])
		if not MenuStyle.NOMI_DANNO.has(c.affinita) or c.kit.is_empty():
			buchi.append("%s affinita'/kit" % c.casata)
	_ok(casate == ["dawnkeep", "sylvorn", "vorrkai", "aethon", "verath", "amareth"] and buchi.is_empty(),
			"sei campioni in ordine, schede complete (%s; mancano %s)" % [str(casate), str(buchi)])

	## 2.
	var m : Dictionary = HouseCatalog.get_house("sylvorn")["marche"]
	_ok(m["CON"] == 10 and m["VOL"] == 10, "le Marche di Sylvorn sono quelle della scheda (CON %d, VOL %d)" % [m["CON"], m["VOL"]])

	## 3. La sagoma: il primo campione non ancora forgiato.
	var non_forgiato := 0
	for i in s.campioni.size():
		if s.campioni[i].corpo == "":
			non_forgiato = i
			break
	s._scegli(non_forgiato)
	await process_frame
	var corpo : Node3D = s._corpo
	var mesh : Array = corpo.find_children("*", "MeshInstance3D", true, false) if corpo != null else []
	var sagome := mesh.filter(func(mi): return mi.material_override is ShaderMaterial and mi.material_override.shader == s.SAGOMA)
	var box := AABB()
	for i in mesh.size():
		var b : AABB = mesh[i].global_transform * mesh[i].get_aabb()
		box = b if i == 0 else box.merge(b)
	_ok(not mesh.is_empty() and sagome.size() == mesh.size() and absf(box.size.y - 1.8) < 0.05 and absf(box.position.y) < 0.05,
			"%s non forgiato e' una sagoma alta %.2f m coi piedi a %.2f" % [s.campioni[non_forgiato].nome, box.size.y, box.position.y])

	## 4.
	s._scegli(3)
	await process_frame
	_ok(s._perno.get_child_count() == 1 and s._corpo != corpo, "cambiando campione resta un solo corpo, quello nuovo")

	## 5.
	var prima : float = s._perno.rotation.y
	var giu := InputEventMouseButton.new()
	giu.button_index = MOUSE_BUTTON_LEFT
	giu.pressed = true
	s._su_input_anteprima(giu)
	var muovi := InputEventMouseMotion.new()
	muovi.relative = Vector2(120, 0)
	s._su_input_anteprima(muovi)
	_ok(absf(s._perno.rotation.y - prima) > 1.0, "trascinare gira il campione (%.2f rad)" % (s._perno.rotation.y - prima))

	## 6. e 7.
	var scelte : Array = []
	s.confirmed.connect(func(h, g): scelte.append([h, g]))
	s._conferma()
	_ok(s._inizia.disabled and scelte.is_empty(), "Zarine bloccata: «Begin» spento e nessuna conferma")
	s._scegli(0)
	await process_frame
	s._conferma()
	_ok(not s._inizia.disabled and scelte == [["dawnkeep", "male"]], "Edran si sceglie: %s" % str(scelte))

	if _fatti < ATTESE:
		_falliti += 1
		print("NO    eseguiti %d controlli su %d attesi" % [_fatti, ATTESE])
	print("ESITO: %s (%d fallite)" % ["OK" if _falliti == 0 else "FALLITA", _falliti])
	quit(1 if _falliti > 0 else 0)
