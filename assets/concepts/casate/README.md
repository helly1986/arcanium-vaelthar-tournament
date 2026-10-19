# Sigilli e vessilli delle sette casate

Stavano in `concepts/Houses Logo/` fuori da `assets/`, ed e' il motivo per cui
non li trovava nessuno. Spostati qui il 2026-08-20, con `git mv`: la storia dei
file e' intatta e non erano referenziati da nessuna scena.

Per ogni casata due file, **e non sono la stessa cosa**:

| file | cos'e' |
|---|---|
| `<casata>_logo.png` | il **sigillo**: medaglione circolare, cornice metallica a intreccio, campo smaltato |
| `<casata>_vessillo.png` | la **bandiera**: stendardo di stoffa appeso a un'asta |

Casate: `aethon`, `amareth`, `dawnkeep`, `kaelvar`, `sylvorn`, `verath`,
`vorrkai`. Piu' `Order of the Amber Arch Logo.png`, che e' un ordine e non una
casata. `_confronto.html` li mette in fila per guardarli insieme.

## ⚠️ Come si applica un emblema a un oggetto

Il vessillo e' il precedente da seguire, e dice una cosa che il sigillo da solo
non direbbe: **su un supporto fisico la cornice metallica si BUTTA**. Sul
vessillo di Sylvorn sopravvive solo l'albero — argento su verde di casata — piu'
un bordo che segue la forma dell'oggetto. L'anello a intreccio resta solo sul
sigillo, che *e'* un pezzo di metallo.

Vale per scudi, tabarri, casse, insegne: si prende il **device** (l'albero, per
Sylvorn), non il medaglione intero. Sul petto del Fante Consumato
(`assets/characters/enemies/consumati_sylvorn/_concept/`) il tondo c'e' perche'
li' e' davvero una placca smaltata avvitata alla corazza.

Sono anche i **riferimenti** giusti da passare a `meshy.py rilettura` quando si
genera un oggetto di casata.
