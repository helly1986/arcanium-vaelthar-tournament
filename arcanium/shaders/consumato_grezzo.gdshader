shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ═══════════════════════════════════════════════════════════════════════════
// CONSUMATO — l'Arcanium grezzo che è entrato dalle giunture
// ═══════════════════════════════════════════════════════════════════════════
//
// Fratello di `pelo_guasto.gdshader`, e per la stessa ragione: il segno non si
// dipinge sulla texture, si fa emergere DOVE LA LORE DICE CHE STA.
//
//   «Non è negromanzia: è Arcanium grezzo che ha invaso senza rituale,
//    sostituendo quello che c'era prima.»                — LA_MAREA_SORDA.md
//
// Da cui le due regole di questo shader:
//
// 1. L'ARMATURA RESTA INTATTA. Niente ruggine, niente marcio, niente colature.
//    L'orrore dei Consumati è che stanno benissimo: «indossano i colori di
//    qualcun altro» e ripetono l'ultimo ordine. Sporcarli li trasformerebbe in
//    zombie, che è precisamente ciò che la lore rifiuta.
//
// 2. IL GREZZO È ENTRATO DALLE FESSURE. L'emissione affiora solo dove l'albedo
//    è SCURO — giunture, sottopiastre, l'ombra dentro l'elmo — perché è lì che
//    c'è un varco. Sulle piastre lucide non c'è niente da vedere.
//
// ⚠️ IL COLORE È VIOLA, NON IL TEAL DI KALVORN, e la distinzione porta peso:
//    il teal (#00c8aa) è la voce VIVA della foresta, il viola è la cosa che
//    l'ha zittita. Sono già i colori del progetto — gli occhi dell'Alpha del
//    Branco Guasto e `pelo_guasto` usano questo stesso viola. Tingere di teal
//    un Consumato direbbe che è uno spirito del bosco: il contrario di quello
//    che è.
//
// ⚠️ IL GLOW DI SCENA È SPENTO in tutto il progetto (renderer mobile). Quindi
//    l'emissione qui deve reggere DA SOLA, senza contare sul bloom a valle:
//    per questo si somma direttamente ad EMISSION invece di affidarsi a una
//    sbavatura che non arriverà mai.
//
// ⚠️ Valori BASSI di proposito, come sul lupo. Il primo tentativo del pelo
//    stava a 1.1 di forza e in gioco usciva un'insegna al neon. Su un fresnel
//    l'unico strumento che funziona è guardarlo a schermo.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool usa_normal = false;

// Lo stesso viola dell'Alpha e di `pelo_guasto`: la creatura parla una lingua
// sola con tutto ciò che l'Arcanium ha toccato.
uniform vec3 viola : source_color = vec3(0.65, 0.18, 1.0);

uniform float metallico : hint_range(0.0, 1.0) = 0.85;
uniform float ruvidita : hint_range(0.0, 1.0) = 0.42;

// ─── Il bordo di sbieco ────────────────────────────────────────────────────
// Debolissimo: non deve disegnare un contorno, deve far sospettare che dietro
// l'acciaio ci sia una luce.
uniform float bordo_forza : hint_range(0.0, 2.0) = 0.16;
uniform float bordo_stretto : hint_range(1.0, 8.0) = 5.0;

// ─── Le giunture ───────────────────────────────────────────────────────────
uniform float giunture_forza : hint_range(0.0, 4.0) = 0.70;
// Sotto questa luminosità dell'albedo siamo in una fessura, non su una piastra.
uniform float giunture_soglia : hint_range(0.0, 1.0) = 0.20;

// ─── LA PREGHIERA INTERROTTA ───────────────────────────────────────────────
// «Ripetono l'ultimo ordine ricevuto a intervalli, come una preghiera
//  interrotta a metà e mai ripresa.»
//
// Questa è la ragione per cui il battito NON è un seno. Un seno respira, e una
// cosa che respira è viva. Qui la luce SALE e viene TRONCATA di netto, poi
// resta spenta più a lungo di quanto è stata accesa — la forma d'onda di una
// frase che riparte sempre dall'inizio e non arriva mai in fondo.
//
// È l'unica parte di questo shader che il giocatore non saprà di aver notato.
uniform float ciclo_secondi : hint_range(0.5, 12.0) = 4.2;
// Quanta parte del ciclo è "accesa". Bassa = silenzi lunghi, che è il punto.
uniform float frase_durata : hint_range(0.05, 1.0) = 0.34;

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	ALBEDO = alb.rgb;
	METALLIC = metallico;
	ROUGHNESS = ruvidita;
	if (usa_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}

	// La frase: rampa 0→1 troncata di netto, poi buio.
	float t = fract(TIME / ciclo_secondi);
	// `smoothstep` sulla salita e un taglio secco alla fine: è la troncatura a
	// fare il lavoro, non la salita.
	float frase = smoothstep(0.0, frase_durata * 0.7, t) * step(t, frase_durata);

	// Di sbieco: forte dove la superficie fugge dallo sguardo.
	float sbieco = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
			bordo_stretto);

	// Le fessure: dove l'albedo è scuro.
	float lum = dot(alb.rgb, vec3(0.299, 0.587, 0.114));
	float fessura = 1.0 - smoothstep(0.0, giunture_soglia, lum);

	// Le giunture pulsano con la frase; il bordo resta sempre, appena percettibile.
	// Sommare invece di mescolare: senza glow di scena, l'emissione è tutto ciò
	// che si vedrà.
	EMISSION = viola * (bordo_forza * sbieco
		+ giunture_forza * fessura * (0.35 + 0.65 * frase));
}
