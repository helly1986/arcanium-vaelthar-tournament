extends RefCounted
## Confronta canale per canale una texture SORGENTE con quella che il motore ha
## davvero in memoria, e dice quale delle tre cose e' successa: canale sano,
## canale degradato, canale PERSO.
##
## Si importa per percorso, non per class_name:
##   const Canali := preload("res://arcanium/tools/confronto_canali.gd")
##
## ⚠️ La domanda e' «il canale C'E' ANCORA?», non «quanto e' lossy?». Sono due
## cose diverse e confonderle fa fallire un cancello quando tutto va bene.
## Misurato il 2026-08-27 sul set del terreno di Kalvorn passato a BPTC:
##
##   canale sano             r 0.91-0.99   err 1.4-2.9   sd 8.8 -> 8.6
##   canale sano poco vario  r 0.74-0.90   err 1.2-9.3   sd 16.7 -> 13.7
##   canale BUTTATO VIA      r 0.00        err 45.9      sd 27.0 -> 0.0
##
## La riga di mezzo e' il rumore di BC7 su un canale che di suo varia poco: in
## valore assoluto sono 8 livelli su 255, e sul render non si distingue
## (differenza media fra due scatti dalla stessa posa: 1,3 su 255). E' una
## degradazione da dire, non un fallimento. Il fallimento e' la terza riga, e la
## si riconosce perche' la VARIANZA CROLLA: un canale che non c'e' piu' e' una
## costante.

const VARIANZA_SUPERSTITE_MIN := 0.35   ## sd_dopo / sd_prima
const CORRELAZIONE_ROTTA := 0.50        ## sotto: il canale non e' piu' quello
const CORRELAZIONE_PULITA := 0.90       ## sopra: nemmeno degradato
const ERRORE_MEDIO_MAX := 25.0          ## rete per la corruzione grossolana
## Sotto questa deviazione standard il canale sorgente non porta informazione
## comunque: la correlazione non significa niente e si giudica solo sull'errore.
const PIATTO := 2.0
## Punti per lato del campionamento a griglia.
const GRIGLIA := 128

const NOMI := ["R", "G", "B", "A"]


## Riporta l'immagine in RGBA8 non compresso, pronta per il confronto.
## ⚠️ Si DUPLICA, non si ricostruisce con `create_from_data`: un'immagine con
## mipmap porta anche quelle in `get_data()`, e la ricostruzione a mipmaps=false
## trova piu' byte di quanti ne aspetta — restituendo un'immagine 0x0 invece di
## un errore. Ci e' gia' costata una corsa.
static func in_chiaro(img: Image) -> Image:
	var fuori := (img.duplicate() as Image)
	if fuori.is_compressed():
		if fuori.decompress() != OK:
			return null
	fuori.convert(Image.FORMAT_RGBA8)
	return fuori


## Per ogni canale: correlazione con la sorgente, errore medio in livelli 0-255,
## deviazioni standard prima e dopo, e il verdetto.
static func metrica(a_img: Image, b_img: Image) -> Array:
	var passo := maxi(1, a_img.get_width() / GRIGLIA)
	var err := [0.0, 0.0, 0.0, 0.0]
	var sa := [0.0, 0.0, 0.0, 0.0]
	var sb := [0.0, 0.0, 0.0, 0.0]
	var saa := [0.0, 0.0, 0.0, 0.0]
	var sbb := [0.0, 0.0, 0.0, 0.0]
	var sab := [0.0, 0.0, 0.0, 0.0]
	var n := 0
	for y in range(0, a_img.get_height(), passo):
		for x in range(0, a_img.get_width(), passo):
			var pa := a_img.get_pixel(x, y)
			var pb := b_img.get_pixel(x, y)
			var va := [pa.r * 255.0, pa.g * 255.0, pa.b * 255.0, pa.a * 255.0]
			var vb := [pb.r * 255.0, pb.g * 255.0, pb.b * 255.0, pb.a * 255.0]
			for c in 4:
				err[c] += absf(va[c] - vb[c])
				sa[c] += va[c]
				sb[c] += vb[c]
				saa[c] += va[c] * va[c]
				sbb[c] += vb[c] * vb[c]
				sab[c] += va[c] * vb[c]
			n += 1

	var fuori: Array = []
	var f := float(n)
	for c in 4:
		var medio: float = err[c] / f
		var var_a: float = maxf(0.0, saa[c] / f - pow(sa[c] / f, 2.0))
		var var_b: float = maxf(0.0, sbb[c] / f - pow(sb[c] / f, 2.0))
		var cov: float = sab[c] / f - (sa[c] / f) * (sb[c] / f)
		var sd_a := sqrt(var_a)
		var sd_b := sqrt(var_b)
		var piatto: bool = sd_a < PIATTO
		# Se la sorgente e' gia' piatta la correlazione non significa niente; se
		# a essersi appiattito e' il risultato, la correlazione e' proprio zero.
		var r := 1.0
		if not piatto:
			r = 0.0 if sd_b < PIATTO else cov / maxf(1e-6, sqrt(var_a * var_b))
		var crollata: bool = not piatto and sd_b < sd_a * VARIANZA_SUPERSTITE_MIN
		var rotto: bool = (medio > ERRORE_MEDIO_MAX
			or crollata
			or (not piatto and r < CORRELAZIONE_ROTTA))
		fuori.append({
			"r": r, "err": medio, "piatto": piatto, "sd_a": sd_a, "sd_b": sd_b,
			"rotto": rotto,
			"degradato": not rotto and not piatto and r < CORRELAZIONE_PULITA,
		})
	return fuori


static func riga(misure: Array) -> String:
	var pezzi: Array[String] = []
	for c in 4:
		pezzi.append("%s r=%.3f err %4.1f sd %4.1f->%4.1f" % [
			NOMI[c], misure[c]["r"], misure[c]["err"],
			misure[c]["sd_a"], misure[c]["sd_b"]])
	return "  ".join(pezzi)


## Prova che il criterio sappia bocciare un canale appiattito, cioe' il guasto
## vero che questi cancelli esistono per prendere. Un cancello che non sa dire
## di no e' peggio di nessun cancello.
static func autoprova(sorgente: Image) -> Dictionary:
	var sana := in_chiaro(sorgente)
	var guasta := (sana.duplicate() as Image)
	# Un formato a due canali non lascia rumore: lascia una costante.
	for y in guasta.get_height():
		for x in guasta.get_width():
			var c := guasta.get_pixel(x, y)
			c.a = 0.5
			guasta.set_pixel(x, y, c)
	return metrica(sana, guasta)[3]


## I nomi dei formati di Image, per indice. Stampare il NUMERO e' gia' costato un
## errore: il 22 e' BPTC_RGBA (BC7), non DXT5 (che e' il 19).
const NOMI_FORMATO := [
	"L8", "LA8", "R8", "RG8", "RGB8", "RGBA8", "RGBA4444", "RGB565",
	"RF", "RGF", "RGBF", "RGBAF", "RH", "RGH", "RGBH", "RGBAH", "RGBE9995",
	"DXT1", "DXT3", "DXT5", "RGTC_R", "RGTC_RG", "BPTC_RGBA", "BPTC_RGBF",
	"BPTC_RGBFU", "ETC", "ETC2_R11", "ETC2_R11S", "ETC2_RG11", "ETC2_RG11S",
	"ETC2_RGB8", "ETC2_RGBA8", "ETC2_RGB8A1", "ETC2_RA_AS_RG", "DXT5_RA_AS_RG",
	"ASTC_4x4", "ASTC_4x4_HDR", "ASTC_8x8", "ASTC_8x8_HDR",
]

static func nome_formato(f: int) -> String:
	return "%s (%d)" % [NOMI_FORMATO[f] if f < NOMI_FORMATO.size() else "?", f]


## I formati che NON hanno il canale alpha, e che quindi buttano via la mappa
## impacchettata li' dentro senza dare nessun errore. RGTC_RG (BC5) e' quello in
## cui si cade mettendo `compress/normal_map=1` su una texture `_nrm_rgh`.
const SENZA_ALPHA := ["RGB8", "DXT1", "RGTC_R", "RGTC_RG", "BPTC_RGBF",
	"BPTC_RGBFU", "ETC", "ETC2_R11", "ETC2_RG11", "ETC2_RGB8", "RF", "RGF", "RGBF"]

static func ha_alpha(f: int) -> bool:
	return not SENZA_ALPHA.has(NOMI_FORMATO[f] if f < NOMI_FORMATO.size() else "?")
