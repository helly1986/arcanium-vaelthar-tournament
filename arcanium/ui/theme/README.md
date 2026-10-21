# Font di gioco

Dal 2026-10-21 i font stanno **dentro il gioco** (`assets/fonts/`), con licenza
SIL Open Font License 1.1: le `OFL.txt` accanto ai file vanno distribuite col
gioco (crediti). Prima il tema usava un `SystemFont` con Palatino, che su
Android e iOS non esiste: i telefoni ricadevano ciascuno sul proprio serif.

| File | Font | Uso |
|---|---|---|
| `serif_ui.tres` | EB Garamond, peso 500 | corpo del testo: menu, HUD, schermate |
| `serif_display.tres` | Cinzel, peso 600 | titoli grandi e numeri in evidenza |

Sono `FontVariation` sui `.ttf` variabili: il peso si sceglie con
`variation_opentype` (la chiave 2003265652 e' il tag `wght`). EB Garamond a 400
e' esile a corpi piccoli su telefono, per questo 500.

## I simboli

Nessuno dei due font ha i glifi delle icone (◆ ◈ ⚔ ❤ ✧ ➶). Li pesca il
`SystemFont` nei `fallbacks` (Segoe UI Symbol/Emoji su Windows, Noto su
Android, Apple Symbols su iOS). Toglierlo li trasformerebbe in tofu.

## Come arriva a tutti i testi

`arcanium_theme.tres` e' registrato in `project.godot` sotto `[gui]
theme/custom`: Godot lo assegna alla radice di ogni finestra e da li' cascata su
ogni Control, comprese le UI costruite via codice. Chi vuole il titolo carica
`serif_display.tres` e lo mette come override (`fine_scontro.gd`, `er_style.gd`).
