# Prompt per la sessione dedicata — AnimationTree sui nemici

> Da incollare come primo messaggio in una sessione nuova. Scritto il 2026-08-25
> a fine di una sessione lunga; qui dentro c'è tutto il contesto che serve.

---

Portiamo i nemici di Arcanium dall'`AnimationPlayer` all'**AnimationTree**,
cominciando dal Fante con spada e scudo.

**LEGGI PRIMA:** i cappelli di `arcanium/systems/enemies/arcanium_enemy.gd` e
`arcanium/systems/enemies/arcanium_humanoid_enemy.gd`, tutto
`player/player_anim_tree.gd` (è il modello da copiare), il cappello di
`arcanium/characters/sylvorn_fante.tscn`. Servono le skill
`godot-animation-tree-mastery` e `game-animation-craft`, e le memorie
`clip-bone-map-import`, `tscn-cappelli-e-editor`,
`arcanium-animation-tree-ovunque`, `kalvorn-ricostruire-fuori-editor`.

## PERCHÉ, e non è una rifinitura

Oggi ogni nemico passa da `_play(nome, loop)` in `arcanium_enemy.gd`, che chiama
`anim_player.play()`: **una clip per volta**. Due conseguenze che costano:

1. **Non esiste «parte alta che fa una cosa, parte bassa che ne fa un'altra».**
   Gli arcieri in arrivo devono **tirare mentre indietreggiano**, e con
   l'AnimationPlayer quella capacità non c'è affatto.
2. **La guardia col scudo è già bloccata su questo.**
   `guardia_idle_anim` è dichiarata in `arcanium_humanoid_enemy.gd:100` e **non
   viene suonata da nessuna parte**: non è una svista, è che con una clip per
   volta non si può tenere una posa mentre il corpo cammina. Il Fante alza lo
   scudo per mezzo secondo e la locomozione ci scrive sopra.

Il protagonista lo fa già, ed è il modello: in `player_anim_tree.gd`

```gdscript
func set_guarding():
    if player_node.guarding && !player_node.busy:
        guard_value = 1
    else:
        guard_value = 0
    var new_blend = lerp(get("parameters/Guarding/blend_amount"), guard_value, .2)
```

Uno **strato mescolato** sopra la locomozione, sfumato con un `lerp`. Nessuna
clip di transizione.

## OBIETTIVO DI QUESTA SESSIONE

Il Fante (`arcanium/characters/sylvorn_fante.tscn`) con un AnimationTree e un
blend `Guardia`, alimentato da **UNA sola clip** di posa a scudo alzato.

Conseguenze volute:
- spariscono `guardia_up_anim` e `guardia_idle_anim` come clip separate;
- resta da autorare **una** clip, non tre.

⚠️ `guardia_block_anim` (`sword_guard_block_medium_01`) è un'altra cosa: è la
reazione a un colpo incassato, non una posa. Per il primo giro si può rimandare
o ripiegare su `sword_hit_01`, che esiste già. **Non trattarla come la terza
parte dello stesso lavoro.**

## VINCOLI, tutti pagati

⚠️ **`_play()` è condiviso da 18 nemici.** Vive in `arcanium_enemy.gd` e lo usano
lupi, Consumati, boss. Non riscriverlo per tutti in un colpo: la strada sicura è
sovrascriverlo in `ArcaniumHumanoidEnemy` (o introdurre uno strato che regga
entrambe le vie) e lasciare gli altri dove sono finché non c'è un cancello che
copre anche loro.

⚠️ **La ROOT MOTION passa da lì.** `_carica_famiglia` imposta
`anim_player.root_motion_track = "<scheletro>:Root"` e il `CharacterBody` legge
`get_root_motion_position()`. Con l'AnimationTree quella lettura si sposta
sull'albero (`AnimationTree.get_root_motion_position()`) e va **rimisurata**: le
clip hanno l'orizzontale bakeata sul `Root` e la verticale nativa sull'`Hips`.
Se si sbaglia, il nemico scivola con la mesh e il corpo resta fermo.

⚠️ **Le librerie sono per FAMIGLIA D'ARMA.** `_carica_famiglia` costruisce a
runtime una `AnimationLibrary` per `sword`, `spear`, ... rimappando il prefisso
delle tracce. L'AnimationTree deve continuare a pescare da lì: non cablare i
nomi delle clip nell'albero.

⚠️ **La `retarget/bone_map` nel `.import`.** Ogni clip nuova va importata con
quel blocco o metà delle sue tracce cade nel vuoto in silenzio e il personaggio
si vede coricato. `verifica_famiglie_anim` ora lo controlla: guardalo dopo ogni
clip aggiunta. Dettagli nella memoria `clip-bone-map-import`.

⚠️ **I `.tscn` si modificano NEL TESTO, mai salvandoli dall'editor:** Godot
cancella i cappelli di commenti, e quelli del Fante contengono le trasformazioni
d'aggancio di spada e scudo calcolate a mano.

⚠️ **`AnimationNodeBlendTree.connect_node`: prima l'uscita, poi gli ingressi.**
Chiamarlo al contrario non lascia traccia e il nodo resta scollegato senza
errori. E l'albero **non espone la lettura** delle connessioni: si verifica
leggendo `node_connections` dal `.tscn` salvato.

## CANCELLI DA PASSARE

    verifica_famiglie_anim   verifica_piedi   verifica_guardia
    verifica_cambio_armatura   verifica_nuova_partita

`verifica_guardia` è quello che conta qui: oggi passa perché prova la logica
(danno assorbito, tenuta, niente parry). Dopo il lavoro deve continuare a
passare **e** la guardia deve vedersi.

⚠️ Se una clip nuova entra, `verifica_famiglie_anim` va passato **dopo** — è
anche l'unico posto in cui parla il guasto intermittente di `famiglie_anim`.

## COME SI COLLAUDA

Non basta che compili. Si guarda **a runtime**, con `godot-mcp-pro`:
`play_scene` su `res://arcanium/levels/kalvorn_sylvorn.tscn`, poi
`execute_game_script` per contare quante tracce della clip trovano davvero il
loro osso, e `capture_frames` per vedere il blend entrare e uscire.

Il collaudo che conta: **il Fante cammina verso il giocatore con lo scudo
alzato**, e quando attacca lo scudo scende. Oggi non succede.

## CONVENZIONI

Commit piccoli e push; mai `git add -A`; si guarda il render, non il numero;
quando un cancello fallisce il primo sospettato è il cancello.
