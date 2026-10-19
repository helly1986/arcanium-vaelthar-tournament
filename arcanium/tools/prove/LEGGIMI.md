# Le prove

Script ed esiti degli esperimenti che hanno deciso la pipeline di vestizione.
Non sono strumenti di produzione: sono **la prova** di cio' che `docs/13` afferma,
tenuta perche' le strade sbagliate vengono ritentate.

⚠️ C'e' un `.gdignore`: Godot non deve importare questi render come texture di
gioco.

| file | cosa dimostra |
|---|---|
| `prova_guscio_derivato.py` | ritagliare il corpo da' un pezzo che copre e aderisce per costruzione |
| `prova_conformazione.py` | i sei modi di conformare un pezzo generato, dal peggiore al migliore |
| `rifai_guanto.py` | le cinque strade fallite per ricavare un guanto dalla mano |
| `guanto_lamelle.py` | il guanto costruito sulle ossa: 17 lamelle piu' il GAMBESON ricavato dal corpo, tutte le misure lette dal corpo. `SOLO_GAMBESON=1` e `SENZA_CORPO=1` per guardarlo a strati |
| `sonda_verso_dorsale.py` | dove sta il dorso della mano: assi locali delle ossa contro normale del piano ricavata dalla carne |
| `guarda_gambali.py` | il .glb sorgente dei gambali, isolato |
| `confronta_gambali.py` | il set esportato, stessa inquadratura: e' scheggiato |
| `bisezione_gambali.py` | **la bisezione**: rende il pezzo dopo OGNI stadio, stessa camera e stesso materiale. F (gonfiato) pulito, G (conformato) scheggiato |
| `diagnosi_conformazione.py` | dentro lo shrinkwrap: chi si muove, di quanto, e se e' la parete interna o quella ESTERNA |
| `guarda_bersaglio.py` | la regione contro cui si conforma, coi bordi in rosso |
| `prova_wrap_mode.py` | la matrice modo x bersaglio che indica la cura |
| `prova_fondo_aderenza.py` | fin dove ha senso tirare fuori un vertice sepolto: i fondi 60/35/18 mm |
| `guarda_set.py` | il set esportato indossato. `-- <altro.glb> <prefisso>` per confrontare due versioni nella stessa inquadratura |
| `esito_A_oggi.png` | com'era: il bracciale posato rigido, che galleggia |
| `esito_B_proiettato.png` | proiezione dei vertici: aderisce e azzera il rilievo |
| `esito_H_ricetta_avambraccio.png` | scorticatura + shrinkwrap: buca |
| `esito_I_ricetta_braccio_intero.png` | idem sul braccio intero: copre ma si strappa |
| `esito_J_sartoriale.png` | **il risultato buono**: vertex group di aderenza, nessuno strappo |
| `esito_guscio_derivato.png` | il guscio ritagliato dal corpo, braccio e gamba |
| `esito_bisez_F_gonfiato_pulito.png` | lo stadio PRIMA della conformazione: nessuna scheggia |
| `esito_bisez_G_conformato_scheggiato.png` | lo stadio DOPO: e' la conformazione a rompere |
| `esito_bisez_G_ginocchio_sfrangiato.png` | il ginocchio da vicino, il sintomo che si vede in gioco |
| `esito_bersaglio_bucato.png` | il bersaglio della conformazione: bordi in rosso, e il PIEDE staccato |
| `esito_wrap_OUTSIDE_SURFACE.png` | `OUTSIDE_SURFACE`: proietta tutto, la fascia del ginocchio si spezza |
| `esito_wrap_OUTSIDE.png` | `OUTSIDE`: muove solo cio' che sta dentro. Ginocchio e calzare interi |
| `esito_fondo_NESSUNO.png` | senza fondo: la cima del cosciale, sepolta 12 cm nel bacino, viene catapultata fuori a schegge |
| `esito_fondo_035.png` | col fondo a 35 mm: la cima resta intera e la conformazione lavora lo stesso |
| `esito_set_PRIMA_ginocchia.png` | **il prima**: fasce del ginocchio spezzate, lamine accavallate |
| `esito_set_DOPO_ginocchia.png` | **il dopo**, stessa inquadratura: fasce intere. Le chiazze di pelle sono un'altra cosa (copertura) |
| `esito_set_DOPO_intero.png` | l'armatura intera dopo le correzioni |
| `esito_corazza_scollo_PRIMA.png` | lo scollo com'era: scodella larga e bassa, clavicole scoperte |
| `esito_corazza_scollo_DOPO.png` | alzato di 5 cm: chiude sulla base del collo |
| `esito_corazza_su15_troppo.png` | e a +15 cm, che l'utente aveva stimato: il colletto arriva al mento |
| `esito_guanto_lamelle_dorso.png` | **il guanto prima**: lamelle di taglio, il rollio non era vincolato da niente |
| `esito_guanto_rollio_osso_x.png` | rollio preso dall'asse X delle ossa: le quattro dita vanno bene, il POLLICE esce di taglio |
| `esito_guanto_DOPO_dorso.png` | rollio dalla normale della carne, e due semiassi misurati: le piastre si appoggiano |
| `esito_guanto_DOPO_tre_quarti.png` | lo stesso di tre quarti — cinque dita, tre lamelle ciascuna, gambeson sotto |
| `esito_guanto_gambeson.png` | il gambeson da solo: ritagliato dal corpo, aderisce per costruzione ed eredita i pesi |

⚠️ I render di lavoro finiscono in `bisezione/`, che e' ignorata da git: sono
decine di PNG rigenerabili. Qui restano solo i fotogrammi che reggono
un'affermazione, copiati a mano come `esito_*.png`.
