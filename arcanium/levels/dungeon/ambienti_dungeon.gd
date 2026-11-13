extends Resource

## Gli AMBIENTI dei mini-dungeon per territorio: quale profilo (rovine,
## dimora, ...) esce in uno scontro della run, a peso. Ogni voce e' un
## Dictionary {"territorio": String, "profilo": Resource, "peso": float};
## territorio "*" vale per tutti. Un territorio o un profilo nuovo (patch, DLC)
## e' una voce in piu' in ambienti.tres, il codice resta quello.
##
## La scelta usa il seme del nodo della mappa: lo stesso nodo da' lo stesso
## ambiente, anche nella rivincita.

@export var voci : Array[Dictionary] = []


## Il profilo per un territorio e un seme; null se nessuna voce lo copre.
func scegli(territorio : String, seme : int) -> Resource:
	var adatte : Array = []
	var tot := 0.0
	for v in voci:
		var t := String(v.get("territorio", "*"))
		if (t == territorio or t == "*") and v.get("profilo") != null and float(v.get("peso", 0.0)) > 0.0:
			adatte.append(v)
			tot += float(v["peso"])
	if adatte.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seme * 31 + 17
	var tiro := rng.randf() * tot
	for v in adatte:
		tiro -= float(v["peso"])
		if tiro <= 0.0:
			return v["profilo"]
	return adatte[-1]["profilo"]
