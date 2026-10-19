extends Node

## ═══════════════════════════════════════════════════════════════════════════
## MISURATORE DEL TIRO CON L'ARCO — incocco, apertura, rilascio
## ═══════════════════════════════════════════════════════════════════════════
##
##   godot --headless --path . res://arcanium/tools/misura_arco.tscn -- \
##       res://assets/characters/enemies/anims/sword/sword_bow_shot_01.glb \
##       [res://arcanium/characters/sylvorn_soldato_scelto.tscn]
##
## Una clip d'arco non ha un "colpo": ha tre istanti, e nessuno dei tre e' un
## picco di velocita' dell'osso armato — il misuratore dei contatti li sbaglia
## tutti (vedi `tiro_arco.gd`, che porta i criteri e il perche').
##
##   • INCOCCO: la sinistra si posa sulla corda. Si misura sulla trazione
##     VISIBILE: la mano che tira (Prop_Attachment_L) portata nel riferimento
##     della corda e vincolata come fa `corda_arco.gd`, contro l'incocco a
##     riposo. La corda sta nell'arco, l'arco nella destra: si ricostruisce
##     dalla posa di Prop_Attachment_R, dalla presa tarata nella scena
##     dell'arciere (`MountArma/ArcoDiSpiritoSylvorn`) e dal marker
##     `Corda/Incocco`. Da qui la corda deve seguire la mano.
##   • APERTURA: la distanza massima fra le due mani dopo che si sono unite,
##     cioe' la sinistra alla guancia.
##   • RILASCIO: le mani si richiudono, cioe' la sinistra lascia la corda e va
##     avanti. Sul tiro caricato, dove la mano si stacca piano prima di aprire
##     le dita, il numero va letto sui fotogrammi (vedi la nota in tiro_arco.gd).
##
## Stampa il profilo frame per frame e i tre istanti. I numeri vanno nel
## moveset (`tendi_da` e i contatti, o la tabella dei tempi via
## `measure_attack_contacts`) e nel `SetArco` (`incocco`, `rilascio`, frazioni).
##
## ⚠️ E' una SCENA: da `_init` di un SceneTree le pose non avanzano. Le due
## mani e la testa si leggono dalle pose delle ossa, che in headless avanzano
## con `seek`; un BoneAttachment3D no.

const TiroArco := preload("res://arcanium/tools/tiro_arco.gd")

const SCENA_ARCIERE := "res://arcanium/characters/sylvorn_soldato_scelto.tscn"
const HZ := 240.0
## L'altezza del fodero (prepara_frecce.py, faretra a 0,75 m): la bocca.
const ALTEZZA_FARETRA := 0.75


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("uso: -- <clip.glb> [scena_arciere.tscn]")
		get_tree().quit(2)
		return
	var scena : String = args[1] if args.size() >= 2 else SCENA_ARCIERE
	var presa := _presa(scena)
	if presa.is_empty():
		get_tree().quit(1)
		return
	var inst : Node = (load(args[0]) as PackedScene).instantiate()
	add_child(inst)
	var ap : AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var sk : Skeleton3D = inst.find_child("Skeleton3D", true, false)
	var nome : String = ap.get_animation_list()[0]
	var anim := ap.get_animation(nome)
	var b_r := sk.find_bone("Prop_Attachment_R")
	var b_l := sk.find_bone("Prop_Attachment_L")
	var b_testa := sk.find_bone("Head")
	var b_faretra : int = sk.find_bone(presa["osso_faretra"]) if presa.has("osso_faretra") else -1
	if b_r < 0 or b_l < 0 or b_testa < 0:
		push_error("ossa assenti (Prop_Attachment_R/L, Head)")
		get_tree().quit(1)
		return

	var tempi : Array[float] = []
	var corda : Array[float] = []
	var mani : Array[float] = []
	var testa : Array[float] = []
	var bocca : Array[float] = []
	var vel : Array[float] = []
	var step := 1.0 / HZ
	var prev := Vector3.ZERO
	var riposo : Vector3 = presa["incocco"]
	var lato := signf(riposo.x) if riposo.x != 0.0 else 1.0
	var t := 0.0
	while t <= anim.length + 0.0001:
		ap.play(nome)
		ap.seek(t, true)
		var posa_r : Transform3D = sk.get_bone_global_pose(b_r)
		var mano : Vector3 = sk.get_bone_global_pose(b_l).origin
		## La mano nel riferimento della corda, vincolata come in gioco: nel
		## piano dell'arco, mai oltre il riposo verso l'impugnatura.
		var p : Vector3 = (posa_r * presa["arco"]).affine_inverse() * mano
		p.z = riposo.z
		if p.x * lato < riposo.x * lato:
			p.x = riposo.x
		tempi.append(t)
		corda.append(p.distance_to(riposo))
		mani.append(mano.distance_to(posa_r.origin))
		testa.append(mano.distance_to(sk.get_bone_global_pose(b_testa).origin))
		if b_faretra >= 0:
			var bocca_p : Vector3 = sk.get_bone_global_pose(b_faretra) * presa["faretra"] * Vector3(0.0, ALTEZZA_FARETRA, 0.0)
			bocca.append(mano.distance_to(bocca_p))
		else:
			bocca.append(-1.0)
		vel.append(mano.distance_to(prev) / step if t > 0.0 else 0.0)
		prev = mano
		t += step

	var i_inc := TiroArco.incocco(tempi, corda)
	var tr := TiroArco.trazione(tempi, mani)
	## ESTRAZIONE: la mano alla bocca della faretra, cioe' il minimo della
	## distanza prima dell'incocco. Da qui la freccia si vede in mano.
	var i_est := -1
	if b_faretra >= 0 and i_inc > 0:
		var d_min := 1e9
		for i in i_inc:
			if bocca[i] < d_min:
				d_min = bocca[i]
				i_est = i
	var vmax := 0.0
	for v in vel:
		vmax = maxf(vmax, v)
	print("clip %s (%.2f s)" % [nome, anim.length])
	print("frame  t      corda    mano-mano  mano-testa  mano-faretra  vel.mano")
	var frame_tot := int(round(anim.length * 30.0))
	for f in range(0, frame_tot + 1):
		var i := clampi(int(round(f / 30.0 * HZ)), 0, tempi.size() - 1)
		var segno := ""
		if i_est >= 0 and absf(tempi[i] - tempi[i_est]) < 0.017:
			segno = "  <- ESTRAZIONE"
		elif i_inc >= 0 and absf(tempi[i] - tempi[i_inc]) < 0.017:
			segno = "  <- INCOCCO"
		elif tr["apertura"] >= 0 and absf(tempi[i] - tempi[tr["apertura"]]) < 0.017:
			segno = "  <- APERTURA"
		elif tr["rilascio"] >= 0 and absf(tempi[i] - tempi[tr["rilascio"]]) < 0.017:
			segno = "  <- RILASCIO"
		print("f%-4d %5.2f  %5.1f cm  %6.1f cm  %6.1f cm  %7.1f cm  %4.0f%%%s" % [
			f, tempi[i], corda[i] * 100.0, mani[i] * 100.0, testa[i] * 100.0, bocca[i] * 100.0,
			100.0 * vel[i] / maxf(vmax, 0.001), segno])
	print()
	_riga("ESTRAZ. ", i_est, tempi, anim.length,
		"mano a %.1f cm dalla bocca della faretra" % (bocca[i_est] * 100.0) if i_est >= 0 else "")
	_riga("INCOCCO ", i_inc, tempi, anim.length,
		"trazione visibile %.1f cm" % (corda[i_inc] * 100.0) if i_inc >= 0 else "")
	_riga("APERTURA", tr["apertura"], tempi, anim.length,
		"mani a %.1f cm" % (mani[tr["apertura"]] * 100.0) if tr["apertura"] >= 0 else "")
	_riga("RILASCIO", tr["rilascio"], tempi, anim.length, "")
	get_tree().quit(0)


func _riga(nome : String, i : int, tempi : Array[float], durata : float, coda : String) -> void:
	if i < 0:
		print("%s  NON TROVATO" % nome)
		return
	print("%s  %.2f s  (%.0f%% della clip, frame %d)  %s" % [
		nome, tempi[i], 100.0 * tempi[i] / durata, int(round(tempi[i] * 30.0)), coda])


## La presa dell'arco nella scena dell'arciere: la trasformazione del modello
## sotto il mount della destra e la posizione a riposo dell'incocco. Si legge
## dall'istanza senza metterla in scena: niente `_ready`, niente AI.
func _presa(scena : String) -> Dictionary:
	var a : Node = (load(scena) as PackedScene).instantiate()
	var percorso : NodePath = a.get("arco")
	var arco : Node3D = a.get_node_or_null(percorso) as Node3D
	var incocco : Node3D = arco.get_node_or_null("Corda/Incocco") as Node3D if arco else null
	if arco == null or incocco == null:
		push_error("misura_arco: '%s' non ha l'arco con la corda (%s)" % [scena.get_file(), str(percorso)])
		a.free()
		return {}
	var out := {"arco": arco.transform, "incocco": incocco.position}
	## E la faretra, per l'ESTRAZIONE: la bocca del fodero sta a `altezza`
	## sopra la sua base (prepara_frecce.py: base a y=0, asse sull'origine).
	var faretra : Node3D = a.get_node_or_null("Model/NephiliteRig/Skeleton3D/MountFaretra/Faretra") as Node3D
	if faretra != null:
		out["faretra"] = faretra.transform
		out["osso_faretra"] = (faretra.get_parent() as BoneAttachment3D).bone_name
	a.free()
	return out
