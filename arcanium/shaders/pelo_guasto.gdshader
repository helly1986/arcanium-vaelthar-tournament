shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ═══════════════════════════════════════════════════════════════════════════
// PELO GUASTO — l'Arcanium bevuto per generazioni, visibile solo di sbieco
// ═══════════════════════════════════════════════════════════════════════════
//
// Non è una decisione estetica: è nella lore del `Manto del Branco Guasto`.
//
//   «Le generazioni passate a bere Arcanium residuo hanno lasciato un riflesso
//    viola in fondo alle setole, VISIBILE SOLO DI SBIECO.»
//
// «Visibile solo di sbieco» è esattamente un fresnel: il riflesso c'è dove la
// superficie fugge via dallo sguardo — fianchi, spalle, profilo del muso — e
// sparisce dove il pelo guarda dritto in camera. Chiazzare il lupo di viola
// avrebbe raccontato un'altra cosa: una malattia della pelle invece di un
// deposito nel fondo delle setole.
//
// ⚠️ Serve all'ALPHA, non al lupo comune: è il segno del capobranco, quello che
// ha bevuto più a lungo. Applicarlo a tutto il branco toglierebbe il segnale.
//
// Le SCHEGGE sono l'eccesso della stessa cosa: dove il deposito ha sfondato la
// pelle affiora il cristallo. Qui è la parte emissiva, accesa dove il fresnel è
// già forte e la texture è scura (il fondo delle setole, non le punte chiare).
//
// ⚠️ I valori qui sotto sono BASSI di proposito. Il primo tentativo stava a
// forza 1.1 con esponente 3.2, e in gioco usciva un lupo al neon: un'insegna,
// non un riflesso in fondo al pelo. Guardato a schermo, non nei numeri —
// sui valori di un fresnel l'occhio è l'unico strumento che funziona.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;

// Il viola dell'Arcanium: lo stesso degli occhi dell'Alpha in lupo_alpha.tscn,
// così la creatura parla una lingua sola.
uniform vec3 viola : source_color = vec3(0.65, 0.18, 1.0);

uniform float sbieco_forza : hint_range(0.0, 3.0) = 0.22;
// Quanto stretto è il bordo. Alto = solo il profilo estremo, basso = invade il
// corpo e sembra una vernice.
uniform float sbieco_stretto : hint_range(1.0, 8.0) = 5.5;

uniform float schegge_forza : hint_range(0.0, 4.0) = 0.45;
// Le schegge affiorano dove il pelo è SCURO: sotto questa soglia di luminosità.
uniform float schegge_soglia : hint_range(0.0, 1.0) = 0.22;
// Respiro lento: il manto «vibra appena, come se il branco continuasse a
// respirare». Non un lampeggio — un battito sotto la soglia dell'attenzione.
uniform float respiro_hz : hint_range(0.0, 2.0) = 0.35;
uniform float respiro_ampiezza : hint_range(0.0, 1.0) = 0.20;

void fragment() {
	vec4 col = texture(albedo_tex, UV);
	ALBEDO = col.rgb;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;

	// di sbieco: 0 dove la superficie guarda in camera, 1 sul profilo
	float sbieco = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), sbieco_stretto);

	// il deposito sta in FONDO alle setole: dove il pelo è scuro
	float luminosita = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	float fondo = 1.0 - smoothstep(0.0, schegge_soglia, luminosita);

	float respiro = 1.0 + respiro_ampiezza * sin(TIME * respiro_hz * 6.2831853);

	EMISSION = viola * (sbieco * sbieco_forza + sbieco * fondo * schegge_forza) * respiro;
	// il riflesso tinge appena anche l'albedo, o resterebbe una luce appiccicata
	// sopra un pelo che non la conosce
	ALBEDO = mix(ALBEDO, ALBEDO * viola, clamp(sbieco * 0.15, 0.0, 1.0));
}
