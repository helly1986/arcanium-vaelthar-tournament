shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled, depth_draw_opaque;

// GHIACCIO SOLIDO — materiale della lama dello Shard e delle punte del campo.
//
// UNSHADED, e non è una scorciatoia: è una decisione presa DOPO averlo visto
// a schermo. Con un materiale illuminato succedevano due cose, entrambe
// verificate su screenshot isometrici dell'arena reale:
//   1. l'arena ha una sola luce debole e azzurrina (MoonLight): metà cristallo
//      restava NERO, e stagliato contro il campo di gelo additivo la lama si
//      leggeva come un buco a forma di triangolo — l'opposto di "ghiaccio";
//   2. con `cull_disabled` (serve: la lama è una bipiramide sottile e va vista
//      da entrambi i lati) le facce posteriori venivano illuminate al
//      contrario, quindi il difetto cambiava lato a ogni rollio.
// Un incantesimo non può dipendere dall'illuminazione della stanza per essere
// visibile. Qui il volume lo fanno DUE termini che non chiedono nulla alla
// scena:
//   • FRESNEL — i bordi visti di taglio si accendono → silhouette vetrosa;
//   • VENE — reticolo procedurale in spazio-MONDO che fa "vedere dentro" al
//     cristallo. Spazio mondo e non UV perché la mesh della lama è generata a
//     mano in SurfaceTool (ice_shard_projectile._build_blade_mesh) e non ha UV.
// In più unshaded costa meno: nessuna valutazione di luci per un oggetto che
// può essere in scena in più copie (proiettili in volo + 8 punte per campo).
//
// La matematica invariante sta in vertex() e passa per varying: fragment()
// gira milioni di volte, vertex() una per punto.

uniform vec4 ice_tint : source_color = vec4(0.62, 0.90, 1.0, 1.0);
uniform vec4 core_tint : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.6;
uniform float glow_energy : hint_range(0.0, 8.0) = 1.8;
uniform float vein_scale = 7.0;
uniform float vein_speed = 0.6;
// Luminosità di fondo del corpo del cristallo (quanto è "acceso" al netto di
// bordi e vene). Tenuta lontana da 1.0: il ghiaccio deve restare più cupo dei
// suoi spigoli, altrimenti diventa una sagoma bianca piatta.
uniform float base_level : hint_range(0.0, 1.0) = 0.32;
// Opacità di base del corpo: sotto ~0.45 il cristallo diventa un fantasma.
uniform float body_opacity : hint_range(0.0, 1.0) = 0.62;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// cull_disabled ⇒ si vedono anche le facce posteriori, dove NORMAL punta
	// dalla parte sbagliata e il fresnel si ribalterebbe. mix() invece di
	// if/else: FRONT_FACING è un flag hardware, non serve un branch.
	vec3 n = normalize(NORMAL) * mix(-1.0, 1.0, float(FRONT_FACING));
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), fresnel_power);

	// Reticolo 3D: tre sinusoidi ortogonali, una in scorrimento → le vene
	// migrano lentamente dentro il ghiaccio invece di stare cucite alla mesh.
	float veins = sin(v_world.x * vein_scale)
		* sin(v_world.y * vein_scale * 1.3 + TIME * vein_speed)
		* sin(v_world.z * vein_scale * 0.9);
	veins = smoothstep(0.25, 0.92, abs(veins));

	// In unshaded Godot scrive ALBEDO direttamente: il "bagliore" si ottiene
	// portando il colore sopra 1.0, non con EMISSION (che qui viene ignorata).
	vec3 col = ice_tint.rgb * base_level
		+ core_tint.rgb * veins * 0.45
		+ ice_tint.rgb * fres * 0.9;

	ALBEDO = col * glow_energy;
	ALPHA = clamp(body_opacity + fres * 0.45 + veins * 0.20, 0.0, 1.0);
}
