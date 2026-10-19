extends "res://arcanium/systems/enemies/arcanium_distanza_enemy.gd"

## ⚠️ Niente `class_name`: come gli altri nemici si aggancia per percorso (vedi
## `fazioni.gd` sul perche' le classi globali qui non si registrano sempre).

## ═══════════════════════════════════════════════════════════════════════════
## ARCIERE — un umanoide che tiene la distanza
## ═══════════════════════════════════════════════════════════════════════════
##
## Tutto il TIRO sta nell'umanoide (linea di tiro, mira predittiva, rilascio al
## contatto misurato: vedi «Mosse a distanza» in arcanium_humanoid_enemy.gd) e
## nel moveset: una mossa con `projectile_scene` valorizzato e `min_range` >
## 0, e `melee_threshold` del set alla distanza a cui l'inseguimento si ferma.
## Con quei due dati un umanoide qualunque gia' tira da lontano e si avvicina
## solo fino a li'.
##
## Quello che nessun melee ha e' UNA cosa sola: la RITIRATA. Dal 2026-09-26
## sta in `arcanium_distanza_enemy.gd`, da cui questo file eredita, perche' il
## Mago Guerriero la usa uguale; le regole restano quelle scritte qui.
## Un arciere con il player addosso non deve restare li' a tirare a
## bruciapelo — si gira e corre a riprendere la distanza, poi si rigira e
## tira. E si ritira con giudizio:
##
##   • parte solo sotto `distanza_ritirata`, e si ferma a `distanza_preferita`
##     o dopo `ritirata_max` secondi: una corsa, non una fuga infinita;
##   • dopo una ritirata riposa `ritirata_pausa` secondi prima di farne
##     un'altra: e' la finestra in cui il giocatore che ha chiuso la distanza
##     viene PAGATO, invece di inseguire per sempre un bersaglio che scappa;
##   • se e' in un angolo (non avanza) smette subito: un arciere che spinge
##     contro un tronco e' un arciere che non tira.
##
## Durante la ritirata guarda DOVE CORRE, non il bersaglio: la clip di corsa
## e' in avanti, e correre all'indietro guardando il player sarebbe un
## moonwalk. `_face` e' l'unico posto che decide il facing, e lo si sovrascrive.
##
## E c'e' l'ARCO. Si impugna con la DESTRA (scena `arco_di_spirito_sylvorn.tscn`
## sotto il BoneAttachment dell'arma, come la spada del Fante) e porta la sua
## corda come nodo: qui si dice solo QUANDO tenderla — dall'INCOCCO al
## rilascio — e con quale mano, che e' la SINISTRA. L'origine della freccia
## (`cast_origin`) e' l'incocco della corda: la freccia parte dall'arco, non
## dal petto.
##
## Quando: dal playhead, come i contatti. La corda si tende quando la clip
## passa `EnemyMove.tendi_da` — la sinistra si e' posata sulla corda con la
## freccia — e scatta a riposo al contatto, che per un arco e' il rilascio.
## Non dall'inizio della mossa: nel primo mezzo secondo la mano sta nella
## faretra dietro la spalla, e una corda che la insegue fin la' disegna un
## triangolo sopra la testa (cosi' era fino al 2026-09-14).
##
## E la FRECCIA si vede: da `EnemyMove.estrai_da` sta nella mano che tira
## (estratta dalla faretra), dall'incocco sta sulla corda e arretra con lei,
## al rilascio sparisce e vola il proiettile — `freccia_in_mano.gd`, col
## modello dello stesso proiettile della mossa.

@export_group("Arco")
## La scena dell'arco in mano: un figlio `Corda` con `tendi`/`rilascia`.
@export var arco : NodePath
## La mano che tira la corda: il BoneAttachment della sinistra.
@export var mano_che_tira : NodePath
## La presa della FRECCIA nella mano che tira, fra l'estrazione e l'incocco
## (`freccia_in_mano.gd`): calcolata da `misura_presa_arco.tscn` all'istante
## dell'incocco, cosi' la freccia passa dalla mano alla corda senza scatti.
@export var presa_freccia : Transform3D = Transform3D.IDENTITY


const FrecciaInMano := preload("res://arcanium/systems/armi/freccia_in_mano.gd")

var _freccia : Node3D = null


func _ready() -> void:
	super._ready()
	_freccia = FrecciaInMano.new()
	_freccia.name = "FrecciaInMano"
	add_child(_freccia)


# ═══════════════════════════════════════════════════════════════════════════
# La corda
# ═══════════════════════════════════════════════════════════════════════════

## Il nodo `Corda` dell'arco montato, o null se questo arciere non ne ha uno
## (la scena e' opzionale: un arciere con un altro arco non deve rompersi qui).
func _corda() -> Node:
	if arco == NodePath(""):
		return null
	var a := get_node_or_null(arco)
	if a == null:
		return null
	var c := a.get_node_or_null("Corda")
	return c if c != null and c.has_method("tendi") else null


## Ogni frame di fisica, prima dei contatti: se la mossa in corso e' un tiro
## e il playhead ha passato l'incocco, la corda segue la mano che tira.
## Stesso orologio dei contatti (`_clip_pos`, tempo-clip): un arciere che
## suona la clip piu' lenta incocca da solo nel punto giusto. Dopo il
## rilascio (`_released_this_move`) non si ritende: la mano torna alla
## faretra e la corda resta a riposo.
func _advance_attack_timeline() -> void:
	var move := _active_move
	if move != null and move.projectile_scene != null and not _released_this_move 			and _clip_corrente() == move.anim:
		var pos := _clip_pos()
		var c := _corda()
		var mano := get_node_or_null(mano_che_tira) as Node3D
		## La freccia in mano, dall'estrazione: il modello e' quello del
		## proiettile di QUESTA mossa.
		if _freccia != null and mano != null and move.estrai_da >= 0.0 				and pos >= move.estrai_da and _freccia.fase() == FrecciaInMano.Fase.NASCOSTA:
			_freccia.monta(FrecciaInMano.modello_di(move.projectile_scene))
			_freccia.estrai(mano, presa_freccia)
		if pos >= move.tendi_da and c != null and mano != null and not c.tesa():
			c.tendi(mano)
			if _freccia != null and _freccia.fase() != FrecciaInMano.Fase.NASCOSTA:
				_freccia.incocca(c)
	super._advance_attack_timeline()


## Il rilascio: la corda scatta a riposo nello stesso istante in cui parte la
## freccia, prima ancora di crearla.
func _deliver_hit(move : EnemyMove) -> void:
	if move.projectile_scene != null:
		var c := _corda()
		if c != null:
			c.rilascia()
		if _freccia != null:
			_freccia.rilascia()
	super._deliver_hit(move)


## Un tiro interrotto (colpo subito, morte) lascia andare la corda: non deve
## restare agganciata a una mano che ormai fa altro.
func _clear_move_state() -> void:
	var c := _corda()
	if c != null:
		c.rilascia()
	if _freccia != null:
		_freccia.rilascia()
	super._clear_move_state()


## E una mossa finita senza rilascio (non dovrebbe succedere: il contatto
## c'e' sempre) non la lascia tesa per sempre.
func _on_move_finished(move : EnemyMove) -> void:
	var c := _corda()
	if c != null:
		c.rilascia()
	if _freccia != null:
		_freccia.rilascia()
	super._on_move_finished(move)
