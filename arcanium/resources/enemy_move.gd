extends EquipmentResource
class_name EnemyMove

## Una mossa del move set di un nemico (Arcanium). Estende EquipmentResource così
## può essere passata direttamente alla pipeline di hit del template: quando il
## nemico attacca, l'AI infila questa risorsa come `equipment_info` dell'arma, e
## ArcaniumHealthSystem del bersaglio legge `power` + i campi status qui sotto.
##
## `power` (ereditato) = danno della mossa. I campi status hanno gli STESSI nomi
## che ArcaniumHealthSystem cerca (duck-typing), come su ArcaniumEquipmentResource.

## Identificativo (es. "A1", "B1") e gruppo (A=build-up Erosione, B=Frattura,
## C=special pesante con cooldown, S=evocazione).
@export var id : String = "A1"
@export_enum("A", "B", "C", "S") var group : String = "A"
## Nome dell'animazione da riprodurre per questa mossa (nell'AnimationPlayer del
## nemico). Se vuoto, il controller usa un fallback.
@export var anim : String = ""
## Velocità di riproduzione SOLO per questa mossa (0 = usa `anim_speed_scale`
## del nemico). Serve quando due mosse nascono dalla stessa sorgente e devono
## SEPARARSI a schermo: l'affondo semplice a 1.0 e quello caricato a 0.9 si
## distinguono per peso, non solo per posa.
##
## Non è una scorciatoia per tarare i tempi di contatto: quelli si leggono dal
## playhead, che è già in tempo-clip e si adegua da solo.
@export_range(0.0, 2.0, 0.01) var anim_speed : float = 0.0

## ─── MOSSE A STRATO: il gesto che non prende possesso del corpo ─────────────
## Con `strato = true` la clip di questa mossa NON sostituisce quella del corpo:
## viene mescolata SOPRA, su una catena d'ossa sola, e le gambe continuano a
## camminare mentre il braccio colpisce.
##
## Nasce per la Legione Testuggine — l'affondo che il Fante tira di lato sopra
## lo scudo senza abbassarlo — e non era esprimibile finche' il nemico suonava
## una clip per volta: la clip dell'affondo avrebbe scritto sopra la guardia,
## che e' proprio la cosa che la mossa non deve fare.
##
## ⚠️ La clip va autorata di conseguenza: tutto il corpo A RIPOSO tranne la
## catena che si muove, perche' in gioco il resto viene FILTRATO via. Una clip a
## strato autorata come una clip normale porta dentro un busto e delle gambe che
## il filtro butta, e il gesto arriva monco senza che niente lo dica.
@export var strato : bool = false
## L'osso da cui parte il filtro dello strato: si prende lui e tutta la sua
## discendenza. Vuoto = il nemico usa il suo predefinito.
@export var strato_radice : String = ""
## Utilizzabile SOLO con la guardia alzata. E' la condizione che rende la
## Testuggine una tecnica invece di un attacco in piu': esiste perche' lo scudo
## e' alzato, e sparisce quando cade.
@export var solo_in_guardia : bool = false


## ─── Parametri AI (da Lite/Constants.js SENZA_NOME) ──────────────────────────
## ⚠️ NON governa più il danno. Nasceva nell'era Meshy, quando le clip non
## avevano alcun wind-up: il controller doveva INVENTARE l'istante dell'impatto
## con un timer, perché nell'animazione non c'era niente da cui dedurlo. Le clip
## del pack Nephilite hanno il wind-up authorato e la lama è FISICA (Area3D +
## sonda swept), quindi il colpo arriva quando la spada tocca: non c'è più niente
## da predire, e tararlo per "far arrivare i colpi" è una pista morta (ci ho
## perso un giro: i valori qui erano sfasati anche di 0.7s dallo swing vero delle
## clip nuove, e a B2 dicevano 0.55 mentre il boss è ancora in aria).
## Gli restano tre usi legittimi: durata del VFX di carica, istante di spawn del
## proiettile per le mosse ranged, e momento in cui il facing si BLOCCA (il punto
## di impegno della mossa). La finestra della lama vive invece a frazione della
## clip, vedi `blade_open_frac` in arcanium_humanoid_enemy.gd.
@export var telegraph : float = 0.5   ## impegno/carica: NON è più l'istante della hitbox

## ISTANTI DI CONTATTO della mossa: secondi sulla clip A VELOCITÀ 1.0, uno per
## ogni impatto (una spallata ne ha uno, una combo di due morsi ne ha due). È il
## modo giusto di dire "quando arriva il colpo" per chi NON ha una hitbox fisica
## che possa deciderlo da sola — vedi ArcaniumEnemy._execute_move.
##
## Vuoto = si ripiega su `telegraph`, che però è tarato come tempo di CARICA, non
## di impatto: è esattamente da lì che nasceva il colpo del Consumato che
## arrivava con un secondo abbondante di ritardo rispetto alla lancia che si
## vedeva scendere. Il numero da mettere qui si legge dalla timeline in Blender
## (il frame in cui l'arma tocca), diviso per l'fps della clip.
@export var contact_times : PackedFloat32Array = PackedFloat32Array()

## Nome del nodo Area3D da usare come hitbox per QUESTA mossa, cercato tra le
## hitbox dichiarate dal nemico. Vuoto = l'arma principale (o, se il nemico non
## ne ha, il cono matematico).
##
## È il gancio per le creature con più punti offensivi — quattro braccia, coda,
## morso + zampata: non serve un controller nuovo, bastano più Area3D nella
## scena e il nome giusto qui.
@export var hitbox : String = ""

## Finestra della lama per QUESTA mossa, come frazione della clip. A -1 usa i
## default globali del nemico (`blade_open_frac`/`blade_close_frac`).
## Serve perché una frazione unica non regge su clip di durata molto diversa: sul
## balzo (5.0s a velocità di gioco) il 15%-90% dà **3.75 secondi di lama viva** —
## non esiste un istante in cui la spada è spenta, quindi rotolare sotto al salto
## è impossibile per costruzione. Una mossa lunga vuole una finestra stretta
## attorno al colpo vero, non proporzionale alla sua durata.
@export var blade_open_frac : float = -1.0
@export var blade_close_frac : float = -1.0

## > 0 = la mossa è una SCARICA RADIALE, non una spadata: niente lama, il danno
## esce da un check a raggio attorno al boss.
##
## Perché è legittimo un check matematico qui, dopo aver tolto il cono dalle
## spadate: un'onda d'urto radiale **è** davvero radiale, quindi il raggio non è
## un'approssimazione di comodo — descrive esattamente la cosa. Il cono sulle
## spadate invece mentiva, perché la lama sta in un punto preciso e il cono no.
##
## Serve perché le clip di spada del pack sono authorate per colpire un avversario
## grande quanto l'attaccante a ~3m: da vicino mancano per geometria, e nessuna
## taratura lo aggiusta. Una scarica non deve "raggiungere" niente: esplode dove
## sta lui, e chiude la falla del corpo a corpo senza barare.
@export var burst_radius : float = 0.0

## Quando esplode la scarica, come frazione della clip. A -1 esplode al
## `telegraph` (le mosse di sola scarica, es. la Respinta). Sul balzo invece deve
## cadere sull'ISTANTE IN CUI LA SPADA TOCCA TERRA: è la spada che canalizza
## l'energia, quindi l'onda deve nascere dal contatto, non da un timer scollegato.
@export var burst_frac : float = -1.0
## Potenza della scarica. A 0 usa `power`. Sul balzo è più bassa della lama: se ti
## becca la spada paghi il prezzo pieno, se ti becca solo l'onda paghi meno ma ti
## carichi di Erosione — così le due gravità di errore hanno due prezzi diversi.
@export var burst_power : int = 0
## La scarica carica Erosione dell'Eco anche se la mossa in sé non lo fa. Serve a
## dare all'onda un'identità diversa dalla lama sulla stessa mossa.
@export var burst_builds_echo : bool = false

## Il boss "aggancia" il bersaglio durante il volo e ci atterra sopra, invece di
## limitarsi alla traiettoria authorata. La root motion del balzo porta appena
## +0.36m: la clip è fatta per un salto sul posto, non per chiudere una distanza.
## È lecito solo sui salti — a mezz'aria i piedi non toccano, quindi allungare la
## traiettoria non produce foot-sliding. Su una spadata a terra si vedrebbe.
@export var leap_to_target : bool = false
## Distanza massima che il balzo può coprire.
@export var leap_max : float = 9.0

## ─── AVANZAMENTO A SCATTI ───────────────────────────────────────────────────
## Metri guadagnati **a ogni contatto**, per le mosse che devono LEGGERSI come
## avanzanti quando la clip non lo racconta da sola.
##
## Nasce dal Doppio Morso del lupo: la sua clip ha il Root identico a quella del
## morso singolo (0.385 m alla terza cifra), ma dura un secondo di più — cioè la
## combo avanzava **più lentamente di ogni altra mossa**, l'esatto contrario di
## come dovrebbe leggersi. Non potendo riautorare la clip, lo scatto lo mette il
## controller.
##
## ⚠️ È SEMPRE una bugia sui piedi: a terra un corpo spinto più avanti di quanto
## dica l'animazione scivola. Il trucco per cui funziona lo stesso è **dove** si
## mette la bugia — in una finestra corta che finisce sull'impatto, dove l'occhio
## guarda il colpo e non le zampe. Fuori da lì si vedrebbe eccome.
##
## ⚠️ E NON DEVE MAI INVADERE IL TELEGRAPH: la carica è il momento in cui il
## giocatore legge la mossa e decide, e un nemico che intanto guadagna terreno
## gliela rende illeggibile. `_slancio_su_contatto` tronca la finestra
## all'istante in cui il telegraph finisce.
@export var passo_avanti : float = 0.0
## true = il CORPO segue l'avanzamento che la clip porta sul `Root`, frame per
## frame, invece di stare fermo (quadrupedi). Serve alle clip autorate col peso
## vero, dove le zampe sono piantate nel MONDO mentre il corpo avanza: il morso
## del lupo rifatto in Cascadeur (2026-10-15). Senza, il Root viene tolto dalla
## posa (`root_motion_track`) e non va a nessuno: il corpo resta li' e le zampe
## piantate scivolano indietro di quanto il lupo doveva avanzare.
## Dal Root si legge solo QUANTO avanza, lungo il suo asse di viaggio; la
## direzione resta il verso del nemico (bloccato dal rilascio).
@export var segue_root_motion : bool = false
## Durata della finestra di scatto, in secondi di clip a velocità 1.0.
## Corta di proposito: è uno scatto, non una camminata.
@export var passo_finestra : float = 0.28

## La lama DISEGNA un muro persistente lungo il proprio giro (vedi boss_wall.gd).
## Il muro nasce dove la spada è passata davvero, campionato durante lo swing.
@export var wall_scene : PackedScene = null
@export var wall_duration : float = 6.0
@export var wall_tick_damage : int = 4
@export var wall_tick_interval : float = 0.55
## La spada si CARICA durante il windup. Obbligatorio su una mossa che lascia un
## muro: se un colpo diventa molto più pericoloso deve anche diventare molto più
## leggibile, o è solo un'imboscata.
@export var sword_glow : bool = false
## Scariche lungo la lama per tutto il wind-up. La "Presa della Frattura" è un
## colpo magico, non solo fisico: senza un tell magico si legge come una spadata
## qualunque, e non lo è. Colore preso da `damage_type` (vedi `_glow_tint`).
@export var sword_sparks : bool = false
@export var move_range : float = 2.0  ## distanza max per essere scelta
## Distanza MINIMA per essere scelta: sotto questa la mossa è scartata. Serve alle
## mosse a distanza (spell): castare in faccia è brutto e punibile male. 0 = nessun
## minimo (mosse melee, invariate).
@export var min_range : float = 0.0
@export var arc : float = 0.9         ## ampiezza del cono (rad), per check direzionale

## > 0 = PORTATA DEL COLPO, distinta da quella da cui la mossa si sceglie.
## Distanza massima fra i centri all'istante del contatto (piu' il mezzo metro
## di tolleranza di `_apply_hit`). 0 = si usa `move_range`, come prima.
## Serve ai corpi lunghi: `move_range` dell'Alpha (4,33) e' proporzionato alla
## stazza ed e' giusto come distanza da cui PARTIRE, ma usato anche per il
## colpo lo faceva mordere a 3,3 m dal player con la punta del muso a 1,31 m
## davanti al proprio centro (misurato con tools/misura_muso_lupi.gd e visto
## sui fotogrammi dello scenario colpi_lupi, 2026-10-08).
@export var portata_colpo : float = 0.0

## > 0 = BACKSTOP RAVVICINATO. A corto raggio (fino a questa distanza) la lama
## fisica passa DI LATO al player: le clip del pack sono authorate per un
## avversario alto quanto l'attaccante a ~3m, e a 0.5-2m mancano per geometria,
## sempre, di ~0.8m (misurato). Con questo, se sei dentro l'arco frontale della
## spadata E abbastanza vicino, ti becca comunque — come stare sotto uno che
## frusta uno spadone. NON è il vecchio cono a tutto raggio (che mentiva perché
## la lama sta in un punto e il cono no): questo vale SOLO nella fascia stretta
## dove la geometria della clip non può fisicamente raggiungerti, gira INSIEME
## alla lama fisica (che ha priorità e resta il colpo onesto a distanza giusta) e
## condivide con lei "un colpo per swing". Fuori da questa fascia, zero effetto.
## Colpisce a metà swing (non nel windup): una schivata a tempo ti porta fuori
## raggio o fuori arco prima, quindi la contromossa resta.
@export var close_hit_range : float = 0.0

## > 0 = al RILASCIO il boss SCIVOLA in avanti verso il player, fino a questa
## distanza (metri), in una frazione di secondo. Serve alle "prese" (es. B1): se
## ti sei allontanato di poco durante il lungo windup, la presa ti raggiunge
## comunque invece di chiudersi nel vuoto. Rispetta le collisioni (velocity +
## move_and_slide, non un tween che attraversa i muri) e si ferma a distanza di
## colpo. Il facing è già bloccato al rilascio, quindi scivola dove aveva mirato.
@export var release_slide : float = 0.0

@export var recovery : float = 0.7    ## pausa dopo la mossa
@export var cooldown : float = 0.0    ## riuso minimo (0 = solo link_gap del set)

## ─── Mossa a distanza (proiettile) ───────────────────────────────────────────
## Se valorizzato, la mossa è RANGED: a fine telegraph, invece del check istantaneo
## di distanza/cono (_apply_hit), il boss istanzia questa scena come proiettile. Il
## danno viaggia col proiettile e arriva per contatto, con la stessa pipeline
## duck-typing del melee (target.hit(self, move) → HealthSystem legge power+status).
@export var projectile_scene : PackedScene
## Velocità del proiettile (m/s) e quanto "guida" il bersaglio in movimento (0 =
## mira alla posizione attuale, 1 = lead pieno; ~0.5 = schivabile col dash a tempo
## ma non camminando via — souls).
@export var projectile_speed : float = 12.0
@export_range(0.0, 1.0) var projectile_lead : float = 0.5
## SPINTA: quanto il colpo SPOSTA chi lo prende, in m/s orizzontali nel verso
## del colpo (0 = niente). Il bersaglio la riceve con `spingi()` e la
## smaltisce in pochi decimi di secondo (vedi `SPINTA_DECADIMENTO`): 3 sposta
## di un passo, 7 di qualche metro — abbastanza da cadere da un cavalcavia.
## E' la TATTICA degli arcieri Sylvorn: un tiro caricato a chi sta sul bordo.
## Uno spostamento di v0 m/s con decadimento a percorre v0^2 / (2a) metri.
@export var spinta : float = 0.0
## CORDA (solo archi): da che istante della clip — secondi a velocita' 1.0,
## come `contact_times` — la corda dell'arco segue la mano che tira. E'
## l'INCOCCO: la sinistra si posa sulla corda con la freccia, e da li' fino al
## rilascio (il contatto) la corda va con lei. Prima di quell'istante la mano
## sta nella faretra, e una corda che la insegue fin la' si vede (era cosi'
## fino al 2026-09-14). Si misura con `arcanium/tools/misura_arco.tscn`.
## 0 = dall'inizio della mossa.
@export var tendi_da : float = 0.0
## FRECCIA IN MANO (solo archi): da che istante della clip (secondi a
## velocita' 1.0) la freccia si VEDE nella mano che tira, estratta dalla
## faretra; da `tendi_da` in poi sta incoccata sulla corda, al contatto vola
## (`freccia_in_mano.gd`). -1 = niente freccia in mano. Si misura con
## `misura_arco.tscn` (la mano alla bocca della faretra): sul Soldato Scelto
## la mano e' nella faretra a 0,70 s, ma ne esce con la freccia solo verso
## 0,97 s, e prima di allora una freccia rigida in mano attraverserebbe il
## fodero. Si guarda il render.
@export var estrai_da : float = -1.0
## Peso per la scelta come APERTURA (selezione pesata per fascia, stile Lite
## DECISION.MELEE/RANGE_WEIGHTS). 0 = mai aperta a caso (solo via catena, es. C1).
@export var pick_weight : float = 1.0

## Combo graph: regole di follow-up valutate in ordine, la prima che passa
## banda (`when`: "melee"/"range"/"any") e tiro (`chance`; `chance2` = override
## in fase 2) vince. `special: true` = mossa con cooldown (finisher).
## Es: [{"next":"A2","chance":0.55,"when":"melee"}, ...]
@export var chains : Array[Dictionary] = []

## ─── Danno / status (letti da ArcaniumHealthSystem del bersaglio) ────────────
@export_enum("FISICO", "TAGLIO", "PERFORAZIONE", "SCHIANTO", "CRIO", "EROSIONE", "SACRO", "FRATTURA", "VELENO", "FUOCO", "FULMINE") var damage_type : String = "FISICO"
## Gruppo A: alimenta l'Erosione dell'Eco.
@export var builds_echo : bool = false
## Gruppo B1: infligge Frattura (vulnerabilità).
@export var inflicts_fracture : bool = false
@export var fracture_multiplier : float = 1.35
@export var fracture_duration : float = 15.0
## LACERAZIONE: build-up per colpo andato a segno (soglia 100, vedi
## `laceration_effect.gd`). A soglia: colpo secco agli HP e fiato corto.
@export var laceration_buildup : float = 0.0

## ─── STORDIMENTO: il colpo che ti toglie il controllo ───────────────────────
## ⚠️ Il GIOCATORE non ha uno StatusHost. Il poise-break e la Frattura sono
## meccaniche che il giocatore INFLIGGE ai nemici, non che subisce, e `hurt()`
## non è uno stun: fa partire la clip di dolore e avvia `hurt_cool_down`, che
## sono frame d'INVULNERABILITÀ — cioè l'opposto di «vulnerabile».
##
## Perciò lo stun è dichiarato qui e applicato dal giocatore, senza passare da
## nessun sistema di status: è una proprietà della MOSSA, come il danno.
##
## ⚠️⚠️ Mentre lo stun è attivo, `hurt_cool_down` va tenuto a ZERO. Altrimenti
## i frame d'invulnerabilità che già esistono renderebbero lo stordito più
## SICURO invece che più esposto, ed è esattamente il contrario del senso della
## mossa: si viene storditi per essere puniti.
##
## La taratura non è a occhio, si conta. Sulla botta di scudo del Fante:
## contatto al frame 50 (1,667 s di clip), coda 1,067 s, `link_gap` 0,15,
## carica del fendente 0,671 s → il primo colpo della combo arriva **1,888 s**
## dopo la botta. Lo stun a 2,0 s lo copre con un decimo di margine; il secondo
## colpo cade fuori, e quello si può ancora parare. È voluto: il prezzo di
## essersi fatti prendere è UN colpo gratis, non l'intera combo.
@export var stun_time : float = 0.0
## Quanto resta vulnerabile, e di quanto. Parte dallo stesso istante dello stun
## e di solito dura di più: ti riprendi il controllo prima di riprenderti la
## guardia.
@export var vulnerable_time : float = 0.0
@export var vulnerable_mult : float = 1.35

## Due patti che una mossa puo' rompere, INDIPENDENTI (un colpo puo' romperne
## uno solo):
##   `imparabile`   — la GUARDIA non lo ferma (lo scudo alzato non serve);
##   `imparriabile` — la PARATA perfetta non lo ferma (il tempismo non serve).
## Con tutti e due si evita solo SPOSTANDOSI: e' il caso dei colpi che non
## arrivano da una lama davanti a te — la radice che esce da SOTTO i piedi, il
## sorso che beve l'Arcanium (Eco Radicata Guasta). Una mossa cosi' deve avere
## un avviso che si legge da lontano (il cerchio a terra): senza, un colpo che
## non si para e' solo un colpo che non si evita.
@export var imparabile : bool = false
@export var imparriabile : bool = false
