extends Node

## ═══════════════════════════════════════════════════════════════════════════
## VIGORE DEI MINION — l'Estratto di Kalvorn
## ═══════════════════════════════════════════════════════════════════════════
##
## LORE/ITEMS_LORE: «+50% durata minion evocati, 60 secondi». Ma i minion di
## Arcanium non hanno una durata: vivono finche' non li uccidono, e intanto
## rendono Arcanium Vivo. Deciso con l'utente il 2026-10-02: «durare di piu'»
## vuol dire REGGERE di piu' — per `durata` secondi ogni minion del giocatore
## ha `quota` di vita massima in piu', e la quota aggiunta arriva anche come
## cura (un minion ferito non resta con la barra mezza vuota).
##
## Vale per i minion gia' in campo E per quelli evocati mentre l'effetto dura:
## chi arriva dopo lo prende al primo controllo. Alla fine si toglie quello che
## si e' dato, e la vita attuale non supera il nuovo massimo.
##
## Figlio del giocatore, uno solo: riusato mentre dura, il tempo riparte e la
## quota NON si somma.

const NOME := "VigoreMinion"
const GRUPPO := "arcanium_minion"
const META := "vigore_minion_dato"

var quota := 0.5
var durata := 60.0
var _resta := 0.0
var _t := 0.0


## Applica (o rinnova) l'effetto sul giocatore. Torna sempre vero: l'Estratto
## vale anche per i minion che si evocheranno nel minuto.
static func applica(player : Node, quota_: float, durata_: float) -> bool:
	if player == null:
		return false
	var v : Node = player.get_node_or_null(NOME)
	if v == null:
		v = (load("res://arcanium/systems/summons/vigore_minion.gd") as GDScript).new()
		v.name = NOME
		player.add_child(v)
	v.quota = quota_
	v.durata = durata_
	v._resta = durata_
	v._potenzia_tutti()
	return true


## Secondi che restano (per HUD e verifiche).
func resta() -> float:
	return _resta


func _process(delta : float) -> void:
	_resta -= delta
	if _resta <= 0.0:
		_spegni()
		queue_free()
		return
	## I nuovi arrivati, quattro volte al secondo: un minion appena evocato
	## non resta un minuto intero senza.
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_potenzia_tutti()


func _potenzia_tutti() -> void:
	for m in get_tree().get_nodes_in_group(GRUPPO):
		if m.has_meta(META):
			continue
		var hs := _salute(m)
		if hs == null:
			continue
		var extra := int(round(float(hs.total_health) * quota))
		if extra <= 0:
			continue
		hs.total_health += extra
		hs.heal(float(extra))
		m.set_meta(META, extra)


func _spegni() -> void:
	for m in get_tree().get_nodes_in_group(GRUPPO):
		if not m.has_meta(META):
			continue
		var hs := _salute(m)
		var extra := int(m.get_meta(META))
		m.remove_meta(META)
		if hs == null:
			continue
		hs.total_health = maxi(1, int(hs.total_health) - extra)
		## La vita attuale scende solo se sta oltre il nuovo massimo.
		if hs.get("_health_f") != null and float(hs.get("_health_f")) > float(hs.total_health):
			hs.set("_health_f", float(hs.total_health))
			hs.current_health = hs.total_health
			if hs.has_signal("health_updated"):
				hs.health_updated.emit(hs.current_health)


func _exit_tree() -> void:
	## Se il giocatore se ne va (cambio scena) si restituisce cio' che si e'
	## dato, o un minion che sopravvive al cambio terrebbe la quota per sempre.
	if _resta > 0.0 and is_inside_tree():
		_spegni()


func _salute(m : Node) -> Node:
	var hs : Node = m.get_node_or_null("HealthSystem")
	if hs != null and "total_health" in hs and hs.has_method("heal"):
		return hs
	return null
