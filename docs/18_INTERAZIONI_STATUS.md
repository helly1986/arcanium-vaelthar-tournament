# Interazioni fra gli status

Decise dall'autore il 2026-11-07 partendo dalla bozza della matrice. Il codice sta in `arcanium/systems/status/` e in `_route_statuses` di `arcanium/systems/arcanium_health_system.gd`. Il cancello è `arcanium/tools/verifica_interazioni.gd`.

## Gli status

| Stato (in gioco) | Come arriva | Che cosa fa |
|---|---|---|
| Emorragia (Hemorrhage) | barra 100 | 22% della vita massima + 6 di colpo. Sul giocatore, 5 s di stamina che cala. Sui nemici non fa altro. |
| Congelamento (Frostbite) | barra 100 | 5 s, velocità ×0,4. Taglio e Perforazione ×1,2, Schianto ×1,5. |
| Ghiacciato (Frozen Solid) | barra 100, solo da Congelato | 10 s immobile, −5 HP/s. Taglio e Perforazione ×1,2, Schianto ×2. Colpisce anche il giocatore. |
| Bruciatura (Burn) | barra 100 | 6 s, 12% della vita massima + 8 a morsi. Rossa dal fuoco. |
| Bruciatura teal | barra 100, accumulo ×0,7 | Dal fuoco spirituale: come sopra, ma danno ×1,5. |
| Shock | barra 100, +50 a ogni Shock da asciutto | −20% della vita massima, subito. |
| Bagnato (Wet) | acqua, colpi con `inflicts_wet` | 10 s. Da solo non fa danni. |
| Frattura (Fracture) | diretta | Danno subito ×1,35. |
| Erosione dell'Eco (Echo Erosion) | barra 100 | 5 s, −8 Arcanium/s, rigenerazione della stamina ×0,25. Solo sul giocatore. |
| Guardia rotta (Stance Broken) | barra 100, o parata | 4 s di stordimento. |
| Spiriti (Awakened Spirits) | diretta | 5 s, velocità ×0,55, danno a morsi. Se uccidono, ridanno a chi li ha mandati l'Arcanium e metà del danno come vita. |
| Veleno (Poison) | barra 100 | 10 s, 15% della vita massima + 10 a morsi, cure ×0,5. |
| Blinded by Light | barra 100 | 25% della vita massima + 10 di colpo. Per 10 s il giocatore non ha lock-on e i nemici attaccano alla cieca. |

Ogni colpo di tipo Veleno accumula 20 e ogni colpo Sacro 25, salvo che dichiari `poison_buildup` o `blind_buildup`.

## Quando uno status incontra un altro

**Fuoco**
- Il danno di fuoco e la Bruciatura arrestano l'Emorragia, anche solo la barra.
- Sciolgono Congelamento e Ghiacciato.
- Asciugano il Bagnato: la Bruciatura che arriva su un Bagnato accumula a metà.

**Acqua**
- Bagnarsi spegne la Bruciatura e ne azzera la barra.
- Da Bagnato il Congelamento accumula ×1,5.
- Da Bagnato lo Shock toglie il 25% e la soglia torna quella di partenza.
- Da Bagnato il Fulmine fa ×1,25 in ogni colpo.

**Gelo**
- Un colpo che congela spegne la Bruciatura.
- Sui Congelati la barra della Guardia sale ×1,5.
- Uno Schianto su un Ghiacciato fa ×2 e rompe il ghiaccio.
- Uno Shock su un Ghiacciato toglie il 25% e chiude il Ghiacciato. La soglia dello Shock sale lo stesso.

**Frattura**
- Amplifica anche i morsi di Bruciatura, Ghiacciato, Spiriti e Veleno.

**Spiriti**
- L'Emorragia attiva li nutre: morsi ×1,25.
- La Bruciatura teal li nutre: morsi ×1,25. Quella rossa no.
- I rallentamenti si moltiplicano con quello del Congelamento.

**Sacro**
- Ogni colpo purifica: scaccia gli Spiriti e azzera tutte le barre di accumulo. La barra della Guardia resta, perché non è un'afflizione.

**Lo stesso status due volte**
- Mentre uno status è attivo, la sua barra non ricarica.
- Il colore della Bruciatura attiva non cambia.
- Bagnato, Frattura e Spiriti si rinnovano.

## Chi resiste

- **Boss:** `ArcaniumBoss.resistenza_accumuli` vale 0,5 e dimezza tutti gli accumuli.
- **Boss vulnerabili:** quelli al fulmine mettono `"shock"` in `accumuli_esenti`. Un giocatore abile può batterli con 4-5 Shock. Un boss a due fasi di vita intera ne chiede il doppio.
- **Giocatore:** subisce tutto tranne Spiriti, che oggi nessun nemico manda.

## Ambiente

- **Piastre:** fuoco e fulmine accumulano 35, veleno 40, ghiaccio 35.
- **Bagnato:** deve restare raro ma non impossibile. Oggi lo danno solo i corsi d'acqua. Mancano le caverne con acqua gocciolante, gli incantesimi dedicati e gli effetti ambientali decisi dall'autore. Il campo `inflicts_wet` sui colpi è già pronto.

## Cifre scelte da Claude, da confermare giocando

- Veleno: durata, quota e cure dimezzate.
- Blinded by Light: 25% + 10.
- Accumuli per colpo di Sacro e Veleno, e delle piastre.
- Boss ×0,5.
- Fuoco spirituale: accumulo ×0,7 e danno ×1,5.
