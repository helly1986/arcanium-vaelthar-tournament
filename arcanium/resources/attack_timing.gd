extends Resource
class_name AttackTiming

## ═══════════════════════════════════════════════════════════════════════════
## TABELLA DEI TEMPI DI CONTATTO — una sola verità per clip
## ═══════════════════════════════════════════════════════════════════════════
##
## Per ogni clip d'attacco: QUANDO l'arma colpisce davvero, in secondi sulla
## clip a velocità 1.0. Generata misurando le animazioni vere con
## `arcanium/tools/measure_attack_contacts.gd` — non si scrive a mano.
##
## Perché sta qui e non dentro le mosse: il Consumato e il Senza Nome usano le
## STESSE clip del pack Nephilite. Se il tempo di contatto vivesse in ogni
## `EnemyMove`, la stessa animazione avrebbe due verità che prima o poi
## divergono. La clip è una, il suo istante di contatto è uno.
##
## `EnemyMove.contact_times` resta come OVERRIDE per i casi speciali (una mossa
## che usa la stessa clip ma colpisce in un altro momento, per esempio perché
## la si riproduce a metà). Se è vuoto, vince questa tabella.
##
## ─── Unità: tempo di CLIP, non tempo reale ─────────────────────────────────
## Tutti i valori sono in tempo-clip a velocità 1.0. È l'unità giusta perché
## coincide con `AnimationPlayer.current_animation_position`: chi legge non deve
## dividere per `anim_speed_scale`, e un nemico che gioca la stessa clip più
## lenta colpisce automaticamente nel punto giusto.

## clip → { "contacts": PackedFloat32Array, "window": Vector2, "length": float,
##          "windows": Array[Vector2] }
##
## `window` è l'UNIONE degli archi di tutti i colpi; `windows` è una finestra
## PER COLPO. La differenza conta solo per le clip a più colpi: con l'arma
## fisica il dedup è per finestra ("un colpo per swing"), e con una finestra
## sola che copre due fendenti il secondo non toccherebbe mai chi ha preso il
## primo. È la combo dello spadone Sylvorn ad averlo fatto emergere.
@export var clips : Dictionary = {}


func set_clip(clip : String, contacts : PackedFloat32Array, window : Vector2,
		length : float, windows : Array = []) -> void:
	clips[clip] = {"contacts": contacts, "window": window, "length": length,
		"windows": windows.duplicate()}


func has_clip(clip : String) -> bool:
	return clips.has(clip)


## Istanti di contatto della clip; vuoto se non è stata misurata.
##
## ⚠️ Ritorna sempre una COPIA, e non è pignoleria. Un PackedFloat32Array tirato
## fuori da un Dictionary condivide il buffer con quello dentro il Dictionary:
## chi lo riceve e poi lo modifica sta modificando la tabella. Il consumatore
## naturale di questi dati è il controller dei nemici, che si tiene i contatti
## in coda e li TOGLIE mano a mano che li consegna — quindi senza copia il primo
## nemico che attacca svuota la tabella per tutti, e dal secondo in poi ogni
## clip risulta "non misurata" e si ricade sul `telegraph`. Sintomo in gioco:
## il primo Consumato colpisce a tempo, gli altri tre no.
func contacts_for(clip : String) -> PackedFloat32Array:
	var e = clips.get(clip)
	if e == null:
		return PackedFloat32Array()
	var c : PackedFloat32Array = e.get("contacts", PackedFloat32Array())
	return c.duplicate()


## Durata NATIVA misurata (utile per accorgersi che una clip è stata
## ri-esportata con lunghezza diversa e la tabella è da rigenerare).
func length_of(clip : String) -> float:
	var e = clips.get(clip)
	if e == null:
		return 0.0
	return float(e.get("length", 0.0))


## Finestra in cui l'arma sta DAVVERO spazzando, misurata: dall'inizio del
## primo colpo alla fine dell'ultimo, `lead`/`trail` di margine a piacere.
##
## È il modo onesto di accendere una hitbox fisica. L'alternativa usata prima —
## una frazione fissa della clip, 15%-90% — teneva la lama viva anche durante il
## wind-up e il recovery: su una clip da 3.7 s significava quasi tre secondi di
## lama accesa, quindi ti feriva mentre ALZAVA la spada e non esisteva istante in
## cui schivare fosse la risposta giusta. Ritorna (-1,-1) se la clip non è stata
## misurata: chi chiama ricade sulle frazioni.
## Una finestra PER COLPO, ciascuna allargata di lead/trail. Se la clip è
## stata misurata prima che le finestre per colpo esistessero, ripiega
## sull'unione: una lista con la sola `window`. Vuota se non misurata.
func windows_for(clip : String, lead : float = 0.0, trail : float = 0.0) -> Array[Vector2]:
	var out : Array[Vector2] = []
	var e = clips.get(clip)
	if e == null:
		return out
	var lista = e.get("windows", [])
	if lista is Array and not lista.is_empty():
		for w in lista:
			if w is Vector2 and w.x >= 0.0:
				out.append(Vector2(maxf(w.x - lead, 0.0), w.y + trail))
		return out
	var w := window_for(clip, lead, trail)
	if w.x >= 0.0:
		out.append(w)
	return out


func window_for(clip : String, lead : float = 0.0, trail : float = 0.0) -> Vector2:
	var e = clips.get(clip)
	if e == null:
		return Vector2(-1.0, -1.0)
	var w : Vector2 = e.get("window", Vector2(-1.0, -1.0))
	if w.x < 0.0:
		return w
	return Vector2(maxf(w.x - lead, 0.0), w.y + trail)
