extends RefCounted
class_name MenuStyle

## ═══════════════════════════════════════════════════════════════════════════
## STILE DEL MENU — impianto "pergamena e oro" alla Elden Ring
## ═══════════════════════════════════════════════════════════════════════════
##
## Tutto il look del menu passa da qui: colori, cornici, righe, titoli. Cambiare
## una costante in questo file cambia il menu intero.
##
## ─── Cosa rende quel menu riconoscibile ─────────────────────────────────────
## Non è il disegno, sono cinque regole, e sono tutte imitabili senza asset:
##  1. NIENTE ANGOLI ARROTONDATI. Tutto è squadrato: cornici, righe, riquadri.
##     Gli angoli tondi leggono "app", non "tomo".
##  2. IL FONDO È QUASI NERO E OCCUPA TUTTO LO SCHERMO. Non un pannello che
##     galleggia sul gioco: una lastra che lo copre, col mondo che resta appena
##     percepibile sotto.
##  3. L'ORO È UN FILO, NON UNA CAMPITURA. Bordi da un pixel, sottolineature,
##     un cursore sottile. Nessuna superficie dorata piena.
##  4. LE INTESTAZIONI SONO IN MAIUSCOLO E SPAZIATE. È quel che dà il tono
##     solenne quando non si può usare un font serif dedicato.
##  5. IL SELEZIONATO SI VEDE DA UNA BARRA, NON DA UN RIQUADRO. Fondo appena
##     più chiaro e un trattino d'oro a sinistra.
##
## ✅ Il font c'è (dal 2026-07-27). Non è più il sans-serif di default di Godot:
## `res://arcanium/ui/theme/arcanium_theme.tres` è registrato in project.godot
## sotto [gui] theme/custom e cascata su OGNI Control del gioco, comprese le UI
## costruite via codice come questa. Vedi ui/theme/README.md per i font
## (EB Garamond e Cinzel, inclusi nel gioco).
##
## Gli override qui sotto restano validi e vincono sul tema: sono override di
## CORPO e COLORE, non di font — non collidono.

# ─── Palette ────────────────────────────────────────────────────────────────
const FONDO := Color(0.035, 0.031, 0.027, 0.93)   ## lastra a schermo intero
const PANNELLO := Color(0.07, 0.065, 0.055, 0.55) ## riquadri interni
const ORO := Color(0.784, 0.671, 0.427)           ## filo dorato, accenti
const ORO_TENUE := Color(0.784, 0.671, 0.427, 0.28)
const TESTO := Color(0.851, 0.812, 0.729)         ## pergamena
const TESTO_FIOCO := Color(0.541, 0.502, 0.435)   ## etichette, aiuti
const SELEZIONE := Color(0.784, 0.671, 0.427, 0.10)

## Pergamena del grimorio: la pagina è più CALDA e appena più chiara della
## lastra, mai bianca. Una pergamena chiara su fondo quasi nero brucerebbe
## l'occhio e romperebbe la regola 2 (la lastra copre tutto); qui la pagina è
## carta vecchia vista a lume di candela, non un foglio in pieno sole.
const PERGAMENA := Color(0.128, 0.108, 0.082, 0.92)
const PERGAMENA_BORDO := Color(0.784, 0.671, 0.427, 0.20)

const CORPO_TITOLO := 30
const CORPO_SEZIONE := 19
const CORPO_VOCE := 18
const CORPO_ETICHETTA := 13
const CORPO_AIUTO := 13

## Font da titolo (MSDF): solo per i corpi grandi, vedi ui/theme/README.md.
const FONT_TITOLO := preload("res://arcanium/ui/theme/serif_display.tres")


## Lastra di fondo: copre lo schermo, il mondo resta appena leggibile sotto.
static func sfondo() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FONDO
	sb.set_content_margin_all(0)
	return sb


## Riquadro interno: fondo appena percepibile e filo d'oro. Squadrato.
static func pannello(margine : int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANNELLO
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(margine)
	sb.border_color = ORO_TENUE
	sb.set_border_width_all(1)
	return sb


## Riga di una lista. Da selezionata: fondo appena più chiaro e trattino d'oro
## a sinistra — il riquadro pieno appartiene a un'altra estetica.
static func riga(selezionata : bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	if selezionata:
		sb.bg_color = SELEZIONE
		sb.border_color = ORO
		sb.border_width_left = 3
	else:
		sb.bg_color = Color(0, 0, 0, 0)
	return sb


## Filo orizzontale d'oro: separa senza pesare.
static func separatore() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ORO_TENUE
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.set_corner_radius_all(0)
	s.add_theme_stylebox_override("separator", sb)
	s.add_theme_constant_override("separation", 1)
	return s


## Spaziatura fra le lettere, che è ciò che dà il tono solenne quando non si può
## usare un font dedicato. Godot non ha letter-spacing sui Label, quindi si
## inseriscono spazi fini fra i caratteri.
## Il tipo di danno come lo legge il giocatore: la sigla interna ("CRIO") e'
## una chiave, non un testo. Aggettivo inglese, che regge sia "20 frost" sia
## "Frost resistance". Lo usano il grimorio e la scheda dell'oggetto.
const NOMI_DANNO := {
	"FISICO": "physical", "TAGLIO": "slashing", "PERFORAZIONE": "piercing",
	"SCHIANTO": "crushing", "CRIO": "frost", "EROSIONE": "erosion",
	"SACRO": "holy", "FRATTURA": "fracture", "VELENO": "poison",
	"FUOCO": "fire", "FULMINE": "lightning",
}

static func nome_danno(sigla : String) -> String:
	return TranslationServer.translate(NOMI_DANNO.get(sigla.to_upper(), sigla.to_lower()))


static func spaziato(testo : String) -> String:
	var out := ""
	## Prima si traduce, poi si spazia: «S E T T I N G S» non e' una chiave.
	var su := TranslationServer.translate(testo).to_upper()
	for i in su.length():
		out += su[i]
		if i < su.length() - 1:
			out += " "
	return out


static func applica(l : Label, corpo : int, colore : Color = TESTO) -> Label:
	l.add_theme_font_size_override("font_size", corpo)
	l.add_theme_color_override("font_color", colore)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func testo(t : String, corpo : int = CORPO_VOCE,
		colore : Color = TESTO) -> Label:
	var l := Label.new()
	l.text = t
	return applica(l, corpo, colore)


## Intestazione di sezione: maiuscolo spaziato in oro, col filo sotto.
static func intestazione(t : String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(testo(spaziato(t), CORPO_SEZIONE, ORO))
	v.add_child(separatore())
	return v


## Titolo grande: usa il font MSDF, che è l'unico che regge i corpi da 30 in su
## senza mostrare le grazie a scaletta.
static func titolo(t : String, corpo : int = CORPO_TITOLO,
		colore : Color = ORO) -> Label:
	var l := testo(t, corpo, colore)
	l.add_theme_font_override("font", FONT_TITOLO)
	return l


## ─── Pagina di pergamena ────────────────────────────────────────────────────
## Una facciata del grimorio. Squadrata come tutto il resto (regola 1) e col
## filo d'oro al posto della cornice piena (regola 3).
static func pagina(margine : int = 26) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PERGAMENA
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(margine)
	sb.border_color = PERGAMENA_BORDO
	sb.set_border_width_all(1)
	return sb


## Il dorso del libro: due fili d'oro ravvicinati fra le due facciate. È il
## dettaglio che fa leggere "tomo aperto" invece di "due riquadri affiancati".
static func dorso() -> Control:
	var c := HBoxContainer.new()
	c.add_theme_constant_override("separation", 3)
	for larghezza in [1, 2]:
		var filo := ColorRect.new()
		filo.color = ORO_TENUE
		filo.custom_minimum_size = Vector2(larghezza, 0)
		filo.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.add_child(filo)
	return c


## ─── Testo lungo ────────────────────────────────────────────────────────────
## RichTextLabel per il corpo dei testi (lore, descrizioni): accetta BBCode, e
## quindi permette di dare enfasi DENTRO una frase — cosa che un Label non sa
## fare senza spezzarla in tre nodi.
##
## ⚠️ `larghezza` NON è opzionale per davvero. Un autowrap acceso senza una
## larghezza dichiarata, dentro un contenitore che si dimensiona sul contenuto,
## trova larghezza minima zero e manda a capo OGNI CARATTERE: il testo diventa
## una colonna verticale di lettere. È la stessa trappola documentata in
## ArcaniumPrompt.etichetta. Qui `fit_content` fa crescere l'altezza da sé, ma
## la larghezza va DETTA.
static func corpo_ricco(bbcode : String, larghezza : float,
		corpo : int = CORPO_VOCE, colore : Color = TESTO) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size = Vector2(max(larghezza, 1.0), 0.0)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("normal_font_size", corpo)
	r.add_theme_color_override("default_color", colore)
	r.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	r.add_theme_constant_override("shadow_offset_x", 1)
	r.add_theme_constant_override("shadow_offset_y", 1)
	r.text = bbcode
	return r


## Il testo si scrive da sé, come inchiostro che compare. Si anima
## `visible_ratio` e NON la stringa: riscrivere `text` a ogni frame rifà il
## parsing del BBCode sessanta volte al secondo (e fa sfarfallare il layout).
static func svela(r : RichTextLabel, durata : float = 0.45) -> Tween:
	r.visible_ratio = 0.0
	var t := r.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(r, "visible_ratio", 1.0, durata)
	return t
