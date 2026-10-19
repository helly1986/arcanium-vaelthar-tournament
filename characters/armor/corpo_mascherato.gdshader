shader_type spatial;
render_mode cull_back, depth_prepass_alpha;

// ═══════════════════════════════════════════════════════════════════════════
// CORPO MASCHERATO — la pelle sotto l'armatura non si nasconde: SPARISCE
// ═══════════════════════════════════════════════════════════════════════════
//
// Il problema che risolve: sovrapporre una piastra rigida alla pelle produce
// compenetrazione a ogni posa estrema, e non c'è offset che la elimini — la
// carne si gonfia nelle pieghe, la piastra no. Misurato sul protagonista v4:
// spallacci al 23% di vertici dentro la pelle, e il gambeson che sporge 30 mm
// bucava la corazza da sotto.
//
// La soluzione è quella che usano gli altri giochi (Skyrim, WoW, Monster
// Hunter): il pezzo d'armatura non COPRE la regione di corpo, la SOSTITUISCE.
// Se sotto la corazza non c'è pelle, la compenetrazione non è risolta: è
// impossibile per costruzione.
//
// ─── Come funziona la maschera ─────────────────────────────────────────────
// `maschera` è una mappa di IDENTIFICATORI, non di canali: il canale rosso
// porta un valore quantizzato a passi di 1/8, e l'id è quel valore per 8.
//   0 = pelle sempre visibile   1 = testa   2 = torso   3 = braccia
//   4 = gambe                   5, 6, 7 = liberi (mantello, veste, …)
//
// ⚠️ Perché gli id e non un canale per slot: usare l'alfa come dato è una
// trappola — l'importatore premoltiplica e distrugge l'RGB dove alfa è zero.
// Un canale solo regge otto regioni invece di quattro ed è immune.
//
// ⚠️ La maschera va importata con filtro NEAREST e SENZA mipmap. Interpolando
// fra 2 (torso) e 4 (gambe) si ottiene 3 (braccia), e sparirebbero avambracci
// a caso sui bordi.
//
// `regioni_nascoste` è una maschera di bit: il bit N acceso nasconde l'id N.
// Il sistema di equipaggiamento la ricalcola quando cambia un pezzo indosso.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normale_tex : hint_normal, filter_linear_mipmap;
// glTF impacchetta metallico e ruvidità in un solo file: G = ruvidità, B = metallico
uniform sampler2D metallico_ruvidita_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D maschera : hint_default_black, filter_nearest;

uniform int regioni_nascoste : hint_range(0, 255) = 0;
uniform float profondita_normale : hint_range(0.0, 4.0) = 1.0;
uniform float ruvidita_scala : hint_range(0.0, 2.0) = 1.0;
uniform float metallico_scala : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	// L'id si legge dal solo canale rosso. Il round è necessario: la texture è
	// a 8 bit, e 2/8 non è esattamente 0.25 dopo la conversione.
	int id = int(round(texture(maschera, UV).r * 8.0));
	if (id > 0 && (regioni_nascoste & (1 << id)) != 0) {
		discard;
	}

	ALBEDO = texture(albedo_tex, UV).rgb;
	NORMAL_MAP = texture(normale_tex, UV).rgb;
	NORMAL_MAP_DEPTH = profondita_normale;

	vec3 mr = texture(metallico_ruvidita_tex, UV).rgb;
	ROUGHNESS = clamp(mr.g * ruvidita_scala, 0.0, 1.0);
	METALLIC = clamp(mr.b * metallico_scala, 0.0, 1.0);
}
