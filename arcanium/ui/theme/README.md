# Font di gioco

Il progetto non conteneva alcun font: ogni Label usava il sans-serif di default
di Godot, ed era l'unica cosa che separava il menu (già approvato per il resto)
dal tono "tomo" che cerca — vedi la nota in fondo a `er_style.gd`.

## Perché SystemFont e non un .ttf importato

Un `.ttf` va scaricato, e uno scaricamento è una dipendenza in più (licenza,
peso, permesso). `SystemFont` prende il font dal sistema **per nome**, con una
pila di alternative: vince la prima presente. La pila usata qui —

    Palatino Linotype → Book Antiqua → Constantia → Georgia → Cambria → serif

— è tutta di serif con grazie marcate e occhio grande (leggibili a 13px, "da
tomo" a 30px), e tutte e cinque risultano installate su Windows 11.
L'ultimo anello, `serif`, è il generico: su Linux/macOS il sistema sceglie il
suo. Se un giorno servisse un font d'autore, basta sostituire `default_font`
in `arcanium_theme.tres` — nessun altro file cambia.

## I due file

| File | Uso | MSDF |
|---|---|---|
| `serif_ui.tres` | corpo del testo: menu, dialoghi, sottotitoli, HUD | no |
| `serif_display.tres` | titoli grandi: banner Announcer, testata del grimorio | sì |

`multichannel_signed_distance_field` rasterizza il glifo una volta e lo scala
senza sgranare: a corpo 64 (il banner "SEI MORTO") un font normale mostra le
grazie a scaletta e i contorni neri sfarfallano. **Sotto i ~28px MSDF
ammorbidisce**, quindi non va usato per il corpo del testo.

`allow_system_fallback = true` è ciò che tiene in vita le icone emoji del menu
(⚔ ◈ ⬒ 🛡 ❄ ✧): nessun serif le contiene, il fallback le pesca da Segoe UI
Symbol/Emoji. Spegnerlo le trasformerebbe in tofu.

## Come arriva a tutti i testi

`arcanium_theme.tres` è registrato in `project.godot` sotto `[gui]
theme/custom`: Godot lo assegna alla radice di ogni finestra e da lì cascata su
**ogni Control del gioco**, comprese le UI costruite via codice (menu, HUD,
Announcer, dialoghi) senza toccarne una riga.

Gli `add_theme_font_size_override` / `font_color` già presenti in quei file
continuano a vincere sul tema: sono override di *corpo* e *colore*, non di
*font*, quindi non collidono. È il motivo per cui non è stato necessario
riscriverli.
