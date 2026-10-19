@tool
extends Resource

## `@tool` perché è un DATO: senza, l'editor ne istanzia un segnaposto e ogni
## strumento che voglia validarla fallisce con "Attempt to call a method on a
## placeholder instance". Stessa ragione di `lucida_tecnica.gd`.

## ═══════════════════════════════════════════════════════════════════════════
## TECNICA DI GUERRA — un gesto, o un saper fare, che si impara da un tomo
## ═══════════════════════════════════════════════════════════════════════════
##
## ⚠️ Niente `class_name`: si importa con
## `preload("res://arcanium/resources/tecnica_guerra.gd")`. Vedi `fazioni.gd`.
##
## ─── PERCHÉ NON È UNA `LucidaTecnica` ───────────────────────────────────────
## Si somigliano — sono entrambe "un colpo speciale definito da dati" — e la
## tentazione di riusare quella risorsa è forte. Ma le due hanno forma diversa
## in tre punti che non si riconciliano allargando un campo:
##
##   • **Da dove vengono.** Una Lucida Tecnica è una proprietà dell'ARMA: la
##     impugni, ce l'hai; posi la spada, l'hai persa. Una tecnica di guerra la
##     SAI: te la porti dietro qualunque cosa tu abbia in mano.
##   • **Come si muove il corpo.** La Lucida Tecnica è un gesto INTERO
##     (OneShot su tutto lo scheletro). Questa è A STRATO: si mescola sopra la
##     guardia, filtrata dalla spina in su, e le gambe non se ne accorgono. È
##     tutto il punto della Testuggine — un affondo che passa sopra lo scudo
##     senza farlo cadere.
##   • **Cosa costa.** Arcanium Vivo contro STAMINA. Una tecnica marziale che
##     spendesse magia sarebbe una magia.
##
## Il precedente da non ripetere è "chi posso ferire", finito scritto in quattro
## punti prima di diventare `Fazioni.colpibile`. Ma la regola gemella vale
## quanto quella: due cose che si somigliano e si comportano diversamente non
## diventano una sola aggiungendo un `if`. Il giorno che una terza forma renda
## queste due davvero uguali, si fondono ALLORA — con tre casi in mano invece
## che con due e mezzo.


## ─── Identità (popup, Diario, futuro menu delle tecniche) ───────────────────
@export var id : String = "tecnica"
@export var name : String = "Tecnica di guerra"
@export var icon : String = "⚔"
## L'illustrazione del tomo. Vedi la pipeline asset: ogni oggetto non-prop ha
## la sua illustrazione, ed è quella che il popup mostra accanto al filmato.
@export var image : Texture2D
@export_multiline var lore : String = ""


## ─── COME SI ESEGUE ─────────────────────────────────────────────────────────
## Il testo che il popup mostra sotto la dimostrazione. È l'unica parte del
## sistema scritta per il GIOCATORE e non per il motore: va detto cosa premere e
## quando, non cosa fa il codice.
@export_multiline var come_si_esegue : String = ""


## ─── L'APPRENDIMENTO ────────────────────────────────────────────────────────
## La chiave in `PlayerFlags` che dice "questa tecnica è appresa".
##
## ⚠️ È la STESSA strada che i summon usano già (`unlock_flag` su
## `SummonSpellResource`, filtrato in `SpellSelection._scan_unlocked_summons`), e
## la scelta è deliberata: `PlayerFlags` è già serializzato da `SaveManager`,
## quindi una tecnica appresa sopravvive al salvataggio senza che nessuno
## scriva una riga di persistenza. Un contenitore dedicato sarebbe stato un
## secondo magazzino da tenere allineato — esattamente l'errore che
## l'inventario ha già pagato una volta (vedi `arcanium_inventory.gd`).
@export var unlock_flag : String = ""


## ─── IL GESTO ───────────────────────────────────────────────────────────────
## Il GLB da cui viene la clip. Il caster del player la carica da qui, riscrive
## il prefisso delle tracce sul suo scheletro e la registra come
## `TecnicheLib/<id>`: la stessa clip vive con nomi diversi sul Fante
## (`sword/sword_guard_thrust_01`) e sul player, e il dato dice il FILE, che è
## l'unica cosa che i due hanno in comune.
##
## VUOTO per una tecnica che non ha un gesto suo (vedi L'ABILITAZIONE, sotto):
## l'Arcieria non si "lancia", si SA — e da lì l'arco si può impugnare. Il
## caster lista solo le tecniche con `gesto()`.
@export_file("*.glb") var clip_glb : String = ""
@export var speed_scale : float = 1.0

## Da quale osso in giù la clip si mescola: si prende lui e tutta la sua
## discendenza. Per la Testuggine è il BRACCIO ARMATO (`RightShoulder`), non la
## spina: è così che lo scudo resta su — la clip porta un braccio sinistro a
## riposo, e se il filtro lo includesse lo scudo cadrebbe durante l'affondo.
## È lo stesso `strato_radice_predefinita` del Fante. Una tecnica che muovesse
## anche il busto dichiarerebbe `Spine`; una che coinvolge le gambe, `Hips`.
@export var filtro_osso : String = "RightShoulder"

## In FRAZIONI della clip, non in secondi: così la finestra sopravvive a un
## `speed_scale` diverso e a una ri-esportazione con durata leggermente diversa.
## È la regola di `LucidaTecnica`, e vale per lo stesso motivo.
@export_range(0.0, 1.0) var finestra_da : float = 0.40
@export_range(0.0, 1.0) var finestra_a : float = 0.72


## ─── IL COSTO E LA PORTATA ──────────────────────────────────────────────────
## La portata si MISURA sul corpo di chi esegue, con un render vero (in
## headless le ossa non si muovono): `arcanium/tools/misura_testuggine_player.tscn`
## registra a ogni frame quanto la PUNTA della lama si spinge avanti. Il Fante
## ha l'avambraccio al 131% del protagonista, quindi il suo numero (T1:
## `close_hit_range` 2,0) non vale per il player.
##
## Legione Testuggine sul protagonista v4, misurata il 2026-09-12: punta a
## 1,31 m avanti al 58% del gesto, a 1,36 m da terra. La portata dichiarata è
## quella più mezzo corpo di bersaglio (la sonda misura fino all'ORIGINE del
## nemico, che sta al centro dei piedi): 1,6 m.
##
## Durante il gesto la portata è il TETTO della sonda di prossimità dell'arma
## (`EquipmentSystem.proximity_cone_range`, 2,6 m per i fendenti): un affondo
## corto che colpisse a due metri e mezzo non sarebbe corto.
@export var portata : float = 1.6

## Il danno è una FRAZIONE della potenza dell'arma in mano, non un numero:
## una spada migliore affonda più forte, e la tecnica non deve diventare
## inutile al primo cambio d'arma. Sul Fante la `T1` vale 11 contro i 20 del
## fendente — poco più della metà — ed è da lì che viene il 0,55.
@export_range(0.0, 3.0, 0.05) var danno_moltiplicatore : float = 0.55
## Un affondo perfora, qualunque sia il tipo di danno dichiarato dalla spada.
@export_enum("FISICO", "TAGLIO", "PERFORAZIONE", "SCHIANTO", "CRIO", "EROSIONE", "SACRO", "FRATTURA", "VELENO", "FUOCO", "FULMINE") var tipo_danno : String = "PERFORAZIONE"
@export var costo_stamina : float = 18.0
@export var cooldown : float = 2.4


## ─── L'ABILITAZIONE ─────────────────────────────────────────────────────────
## I tipi d'arma (`object_type` dell'equipaggiamento: "BOW", ...) che si possono
## EQUIPAGGIARE solo sapendo questa tecnica. Vuoto per le tecniche che sono un
## colpo e basta (la Testuggine non chiude nessun armadio).
##
## L'Arcieria dichiara `BOW`: l'arco si può TROVARE prima di saperlo tirare —
## cade dal Soldato Scelto, sta nella vetrina di Solan — ed entra nel posseduto
## come ogni pezzo; ma nell'armadio resta chiuso, col suo lucchetto e il nome
## del tomo che lo apre, finché il tomo non è letto. Frecce e faretra non sono
## oggetti (le frecce le porta l'arco, `ArcaniumEquipmentResource.freccia`): il
## giorno che lo diventassero, dichiarerebbero il loro tipo qui.
##
## Il cancello sta in `EquipmentLoadout.sbloccato()`, che è l'UNICO posto da cui
## si equipaggia (menu, ciclo, ricarica di una partita): non nel menu, che è
## solo uno dei modi di arrivarci. Il lucchetto è per TIPO e non per pezzo,
## così un arco nuovo nasce chiuso senza che nessuno debba ricordarsi di
## chiuderlo.
@export var abilita_tipi : PackedStringArray = PackedStringArray()


## ─── LA DIMOSTRAZIONE ───────────────────────────────────────────────────────
## Chi esegue il gesto dentro il popup, e quale mossa gli si chiede.
##
## ⚠️ NON SI SUONA LA CLIP DA SOLA. `sword_guard_thrust_01` è autorata **col
## corpo a riposo tranne il braccio destro**, perché in gioco tutto il resto
## viene filtrato via: messa in un player di animazioni «sembra rotta», e non lo
## è — manca il corpo che ci sta sotto. La dimostrazione deve quindi rifare
## quello che fa il gioco: posa di guardia sotto, affondo mescolato sopra.
##
## Il modo più economico di garantirlo è non rifarlo affatto: si istanzia la
## scena che quel meccanismo ce l'ha già (il Fante) e le si chiede la sua mossa.
## Un rig di anteprima costruito a parte sarebbe una seconda implementazione da
## tenere allineata, e si accorgerebbe di essere sfasata solo a schermo.
@export var dimostrazione : PackedScene
## L'id della mossa dentro il moveset di `dimostrazione` (per la Testuggine: "T1").
@export var dimostrazione_mossa : String = ""
## Da dove si guarda, nel mondo del popup (il dimostratore sta sull'origine e
## guarda +Z). I valori di default sono quelli tarati sul Fante: tre quarti
## frontale dal lato della spada, dal ginocchio in su, camera bassa (vedi
## `tomo_modal.gd`, `_costruisci_mondo`). L'arciere vuole un'altra inquadratura
## — l'arco è alto un metro e trenta e il gesto è a due mani — e ogni tecnica
## la dichiara qui invece di farla indovinare al popup.
@export var dimostrazione_camera : Vector3 = Vector3(-1.75, 1.30, 1.60)
@export var dimostrazione_mira : Vector3 = Vector3(0.05, 1.05, 0.15)


## Una tecnica senza `unlock_flag` non è apprendibile; una senza né clip né
## abilitazione non fa niente. Servono a distinguere "risorsa da finire" da
## "risorsa rotta", che a schermo si assomigliano.
func valida() -> bool:
	return unlock_flag != "" and (clip_glb != "" or not abilita_tipi.is_empty())


## Vero se la tecnica è un GESTO da eseguire (ha una clip): è ciò che il caster
## del player lista e lancia. Un'abilitazione pura (l'Arcieria) non lo è.
func gesto() -> bool:
	return clip_glb != ""


## Vero se equipaggiare un pezzo di questo `object_type` richiede questa tecnica.
func abilita(tipo : String) -> bool:
	return tipo != "" and abilita_tipi.has(tipo)


## Tutte le tecniche del gioco, dalla cartella che le contiene, in ordine di
## nome di file. È il catalogo che leggono il caster (per i gesti) e l'armadio
## (per i lucchetti): un posto solo per scandire la cartella, così un `.remap`
## di build o un file di troppo si gestiscono una volta.
const CARTELLA := "res://arcanium/resources/tecniche_guerra/"

static func catalogo() -> Array[Resource]:
	var fuori : Array[Resource] = []
	var dir := DirAccess.open(CARTELLA)
	if dir == null:
		return fuori
	var nomi : Array[String] = []
	for f in dir.get_files():
		## In build i .tres diventano .remap: senza questo la lista sarebbe
		## vuota nel gioco esportato e piena solo in editor.
		var nome := f.trim_suffix(".remap")
		if nome.ends_with(".tres") or nome.ends_with(".res"):
			nomi.append(nome)
	nomi.sort()
	for n in nomi:
		var t : Resource = load(CARTELLA + n)
		if t != null and t.has_method("valida") and t.valida():
			fuori.append(t)
	return fuori


## Vero se il giocatore l'ha imparata. Unico posto che sa COME si legge lo
## stato: se un giorno l'apprendimento si sposta altrove, si cambia qui.
func appresa(albero : SceneTree) -> bool:
	if unlock_flag == "" or albero == null:
		return false
	var flags := albero.root.get_node_or_null("PlayerFlags")
	return flags != null and flags.has(unlock_flag)
