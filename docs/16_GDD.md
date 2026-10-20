# Vaelthar Tournament — Game Design Document (minimo)

> Stato: **v0.1, 2026-10-19**. Tutte le decisioni qui sotto sono dell'autore, prese una per una.
> Dove c'è scritto **APERTO**, la decisione non è ancora stata presa.
> Il piano di lavoro sta in `docs/17_PIANO_FASI.md`.

## 1. In una frase

Un roguelike soulslike breve. Il campione di una casata attraversa le qualificazioni del Grande Torneo di Vaelthar, uno scontro dopo l'altro, in arene piccole ma complesse. Vincendo diventa sempre più forte. Se perde tre volte è fuori.

**Ispirazione:** il Crogiolo di *No Rest for the Wicked*. Dell'originale teniamo quattro cose:

- tutto ruota intorno al combattimento e alla sopravvivenza;
- le arene sono piccole ma verticali, con baratri in cui puoi cadere o spingere i nemici;
- a fine scontro si comprano potenziamenti;
- run dopo run si impara il nemico.

Una cosa del Crogiolo non la vogliamo: lì gli oggetti usati si consumano anche nel gioco principale. Vaelthar è un gioco a sé, quindi il problema non si pone.

**Scopo del progetto:** far conoscere l'autore prima di tornare ad *Arcanium*, con un gioco piccolo, finito e vendibile.

## 2. Il mondo

Vaelthar è il mondo di Arcanium. Una volta l'anno le sei casate si sfidano nel **Grande Torneo** all'Arena Arcana di Valdris, la capitale. Nei territori periferici si combattono invece le **battaglie clandestine**, vietate dalla Corona e praticate da tutti. Una run è il cammino di un campione attraverso le qualificazioni nei territori.

Il lore completo sta in `LORE/`, fuori da git. Si legge per scrivere i contenuti e non si copia nel repo.

## 3. La run

| | |
|---|---|
| Durata | il torneo intero: **4 territori** pescati a sorte fra 6, circa **24 scontri**, 60–90 minuti |
| Ordine | a sorte. La difficoltà dipende dalla **tappa** (1ª–4ª), non dal territorio: lo stesso boss è più duro se arriva per ultimo |
| Salvataggio | tra un match e l'altro: su mobile si esce e si riprende |
| Picco di potenza | l'endgame arriva dopo una ventina di scontri, cioè verso la 3ª–4ª regione |

### 3.1 La mappa di un territorio

Ogni territorio ha un **albero visibile**, come in Slay the Spire: circa 5 piani di nodi su 2–3 corsie che si incrociano. Di ogni nodo si vede il tipo, quindi il giocatore sceglie quanto rischiare.

| Nodo | Cosa succede |
|---|---|
| **Scontro** | un match normale |
| **Élite** | un match duro; rende di più (sez. 5.2) |
| **Battleground** | la tua armata contro quella nemica (sez. 6) |
| **Boss** | il boss regionale, in fondo all'albero |
| **Tesoro** | un oggetto senza combattere |
| **Imprevisto** | un evento del torneo. **APERTO:** quali eventi |
| **Riposo** | ci si cura |
| **Mercante** | armi, incantesimi, evocazioni, cure; si può rimuovere o rilanciare un potenziamento |

I tipi di nodo sono **dati**: le espansioni ne aggiungeranno altri.

### 3.2 Sconfitta, rivincita, eliminazione

- **Tre sconfitte** in tutta la run e sei eliminato.
- Dopo una sconfitta scegli un **perk speciale** e rigiochi **lo stesso match**: stessi nemici, stessa arena. Il perk svanisce quando vinci, e la mappa non avanza finché non hai vinto. **APERTO:** l'elenco dei perk.
- **Cadere in un baratro** significa perdere il match. Un nemico che cade muore.
- **La regola souls sull'Arcanium.** Una sconfitta ti toglie tutto l'Arcanium **non speso**; i potenziamenti già comprati restano. Se vinci la rivincita lo riprendi intero, più la taglia del match. Se perdi anche la rivincita, quel mucchio è perso per sempre, e la sconfitta conta come un'altra delle tre.

## 4. I mini-dungeon

Deciso il 2026-10-20: **ogni scontro si gioca in un mini-dungeon**, non in un'arena chiusa.

- **Struttura:** stanze collegate da corridoi, con porte, baratri e trappole, generate da un seme. Il modello è Dungeon Architect di Unreal: prima il grafo delle stanze, poi la griglia, poi il popolamento.
- **Obiettivo dello scontro normale:** eliminare **tutti** i nemici. Alcuni stanno chiusi nelle loro stanze, dietro porte che si aprono avvicinandosi, quindi bisogna **esplorare**.
- **Forzieri:** forzieri normali e rari, con una certa probabilità; la stanza del tesoro ne ha sempre uno.
- **Baratri:** chi ci cade perde il match, mentre un nemico che ci cade muore. Ogni baratro ha un ponte, che è il posto giusto per le spinte.
- **Verticalità:** piccoli ma non semplici. Il multilivello verrà dopo; **per ora il livello è singolo**.
- **Contenuto come dati:** ogni territorio ha il suo profilo (stanze, pezzi, nemici, probabilità). Le espansioni aggiungono profili.

Il codice sta in `arcanium/levels/dungeon/`. Il cancello è `arcanium/tools/verifica_dungeon.gd`, la scena di prova `dungeon_prova.tscn`.

## 5. Combattimento e crescita

### 5.1 Il combattimento

È quello di Arcanium:

- attacco leggero e pesante, schivata, parata;
- lock-on;
- incantesimi e evocazioni col Sigillo;
- stati (Erosione, Frattura e gli altri);
- 11 tipi di danno, con resistenze e vulnerabilità per nemico.

Vedi il README per la mappa dei sistemi.

**La spinta.** Non ha un tasto dedicato. Spingono gli **attacchi pesanti**, alcune **armi** (mazze, scudo) e alcuni **incantesimi**. Ogni nemico ha un **peso**: i lupi volano via, il Fante scivola, i boss quasi non si muovono.

### 5.2 I potenziamenti di fine match

A fine match escono **3 offerte** a sorte, che si comprano con l'**Arcanium** finché bastano i soldi. Ci sono tre categorie:

- **Statistiche**.
- **Marche.** Restano, con uno scaling molto più forte di Arcanium; la curva di `marche_progression.gd` va rifatta per un endgame dopo circa 20 scontri.
- **Effetti sui colpi**, organizzati in **famiglie di danno** (Fuoco, Crio, Fulmine, Veleno…). Un effetto fa prendere ai colpi quel tipo e il suo stato. Con **2, 4 e 6 effetti** della stessa famiglia scattano bonus a soglia.

**Rarità:** comune, raro, leggendario. Dipende dal nodo:

- lo scontro normale offre quasi solo comuni;
- l'élite garantisce almeno un raro;
- il boss regionale garantisce almeno un leggendario (il bonus speciale per il boss caduto).

I prezzi salgono con la tappa.

Armi, incantesimi ed evocazioni forti **si trovano nella run**: dal Mercante, dal Tesoro e come premi di élite e boss.

### 5.3 Il bestiario a scoperta

Ogni nemico ha una scheda che si riempie giocando. Le **debolezze compaiono solo dopo averle provate** su di lui: niente viene svelato in anticipo. Il bestiario resta tra una run e l'altra e mostra anche le unità delle casate sbloccate (sez. 6).

## 6. Il battleground

- **Schiera e intervieni.** Prima della battaglia scegli e schieri le truppe. Durante la battaglia l'armata combatte da sola, e tu hai **2–3 incantesimi da lanciare dall'alto**, ognuno con la sua ricarica.
- **Slot:** 3 all'inizio, più 1 a ogni cambio di territorio (3 → 4 → 5 → 6).
- **Truppe:** ogni casata parte con **3 truppe base**. Nella run si trovano evocazioni più potenti, sempre della tua casata.
- **Bonus casata:** scatta quando le 3 truppe base sono tutte in campo. Con 3 slot devi scegliere tra il bonus e la potenza; più avanti puoi avere entrambi.
- **Esercito nemico nascosto:** si vede solo pagando Arcanium.
- **Futuro:** le unità sbloccate serviranno a una **modalità skirmish**, che uscirà come DLC.

## 7. I campioni

**Sei campioni, uno per casata:** Dawnkeep, Sylvorn, Vorrkai, Aethon, Verath, Amareth. Sono **tre uomini e tre donne**. **APERTO:** quale casata ha un uomo e quale una donna, e i nomi.

Ogni campione ha cinque cose sue, mentre scheletro e moveset base restano condivisi:

- **kit di partenza**: non tutti hanno lo scudo;
- **Marche di partenza**: già in `house_catalog.gd`;
- **affinità** con una famiglia di danno, i cui potenziamenti escono più spesso;
- **un'abilità di casata**;
- **3 truppe base** per il battleground.

Kaelvar, la Casa Reale, non è giocabile: segreto o espansione.

### 7.1 Sblocco e finale

1. Si parte con **Dawnkeep**.
2. Una run conta solo se **vinci il torneo**, cioè batti 4 boss regionali. Il torneo vinto finisce con una breve scena a Valdris: il campione incastona la **gemma della sua casata** nel **Grande Portale** della capitale.
3. Vincere sblocca un nuovo campione, **estratto a sorte**. Puoi continuare con i campioni già sbloccati, ma il successivo si sblocca solo vincendo con quello nuovo.
4. Con **tutte e sei le gemme**, la run si fa con un **campione a scelta**. Alla fine del torneo **l'Ispettore Primo** ti sbarra la strada all'Arena Arcana.
5. Se lo batti si apre la **dimensione oscura**, dove ti aspetta il boss finale: **uno Sha-Des potentissimo**. **APERTO:** chi è.

## 8. I boss

| Territorio | Casata | Boss regionale |
|---|---|---|
| Kalvorn — la Foresta Perpetua | Sylvorn | Vyrath |
| Pyrrath — le Terre del Fuoco | Vorrkai | Il Perfetto |
| Halrath — le Montagne della Guardia | Dawnkeep | Sera la Vegliante |
| Davrath — le Pianure del Giudizio | Aethon | Khanna l'Atesh |
| Le Pianure Grigie | Verath | Drath il Portatore |
| Kalath-Dun — il Mare di Sabbia | Amareth | Sorath-Dun |
| Valdris — l'Arena Arcana | Kaelvar | l'Ispettore Primo (guardiano) |
| La dimensione oscura | — | uno Sha-Des (finale) |

**Mob:** circa 30 al lancio, divisi tra i territori. **APERTO:** il roster di ogni territorio oltre a Kalvorn.

## 9. Fuori dalla run

- **Fama.** È una seconda valuta, che si guadagna **anche perdendo**, in base a quanto lontano sei arrivato. Serve soprattutto a **sbloccare contenuto nel pool** delle run (armi, incantesimi, evocazioni, potenziamenti). In piccola parte compra **bonus permanenti piccoli e con un tetto**. L'abilità deve contare più dei bonus.
- **Gradi di sfida**, al lancio. Vincere sblocca il grado successivo, che aggiunge una regola dura e dà più Fama. I gradi si contano per campione.
- **Sfide giornaliere**, in una patch: seme e modificatori uguali per tutti, con classifica online.
- L'**Arcanium** vale solo dentro la run.

## 10. Piattaforme e controlli

- **Lancio insieme** su iOS, Android e PC (Steam). Le console arrivano dopo, tramite una porting house (W4 Games o simili).
- **Touch:** pad completo a schermo. I tasti importanti sono grandi, i minori piccoli. Restano il gamepad su tutte le piattaforme e la tastiera su PC.
- **Prestazioni:**
  - minimo iPhone 11 e Android con Vulkan di fascia media dal 2021, a **30 fps** stabili;
  - telefoni recenti a **60 fps**;
  - un'opzione 30/60 nel menu.
  - Renderer Mobile. I protagonisti restano a circa 120k triangoli, con i LOD di Godot. Il costo da misurare per primo è la stoffa simulata in GPU.
- **iOS da Windows:** build su **GitHub Actions** con runner macOS (gratuiti per i repo pubblici), poi **TestFlight**. Serve l'account Apple Developer.

## 11. Modello di business

- **Premium, circa 7 €.**
- Aggiornamenti ed espansioni piccole **gratis**. Le espansioni corpose diventano **DLC** a pagamento e aprono modalità nuove (per esempio lo skirmish).
- Niente valute premium né pubblicità.
- **Demo gratuita su Steam** prima dell'uscita (per esempio allo Steam Next Fest), con Dawnkeep e Kalvorn. Su mobile nessuna demo.

## 12. Espandibilità

Il gioco deve crescere con patch e DLC senza riscrivere codice. Territori, arene, mob, boss, campioni, potenziamenti, famiglie, tipi di nodo, imprevisti, perk e gradi di sfida sono **risorse** (`.tres`) che un catalogo raccoglie. Aggiungere contenuto significa aggiungere file.

## 13. La vertical slice

Una regione completa, che è anche la demo Steam:

- **Dawnkeep**, a **Kalvorn**, fino a **Vyrath**, giocabile su telefono e su PC;
- l'albero con tutti gli 8 tipi di nodo;
- il banco di fine match con **2 famiglie** di danno;
- sconfitte e rivincite, con la regola souls sull'Arcanium;
- il bestiario a scoperta e il pad touch;
- **4–5 arene** diverse, con baratri, porte e trappole;
- un battleground con le 3 truppe base di Dawnkeep: Sentinella del Passo (già evocabile), Custode Glaciale e Lama del Vento Polare.

**Mob già pronti per Kalvorn:** lupo, capobranco, Alpha, Consumato, Eco Radicata Guasta, Fante, Fante con spadone, Soldato Scelto, Mago, Comandante.

**Da fare:** Vyrath (modello Tripo, rig, animazioni) e le due truppe Dawnkeep che mancano.
