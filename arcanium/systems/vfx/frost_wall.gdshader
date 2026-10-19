shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// PARETE DI BRINA — cilindro aperto (senza tappi) piantato sul bordo del campo
// di gelo. Serve UNA cosa sola: dare ALTEZZA al confine del raggio.
//
// Perche' non basta il disco: in isometrica un nemico alto ~1.8 m nasconde col
// proprio corpo la porzione di disco che gli sta dietro. Un velo verticale di
// ~0.8 m sul perimetro resta leggibile anche con gente in mezzo, e dice "qui
// dentro" da qualunque azimut ruoti la camera (IsoCam orbita).
//
// Tenuto BASSO apposta: piu' alto occluderebbe i piedi dei nemici DENTRO il
// campo, che e' proprio l'informazione che il player deve leggere.
//
// Coordinate: NON si usano le UV della CylinderMesh (la convenzione di v
// cambia tra le primitive ed e' facile ritrovarsi il gradiente capovolto).
// Si usa la posizione LOCALE del vertice, che per CylinderMesh e' centrata
// sull'origine: y va da -height/2 a +height/2, sempre, in ogni versione.

uniform vec4 tint : source_color = vec4(0.62, 0.90, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 1.6;
uniform float life : hint_range(0.0, 1.0) = 1.0;
uniform float open : hint_range(0.0, 1.0) = 1.0;
// Altezza della CylinderMesh, in metri. DEVE combaciare con mesh.height.
uniform float mesh_height = 0.8;
// Quanto in fretta l'alpha muore salendo (1 = sfuma piano, 4 = solo alla base).
uniform float falloff : hint_range(0.5, 6.0) = 2.4;
uniform float shimmer_scale = 9.0;
uniform float shimmer_speed = 0.5;

varying float v_h;     // 0 alla base, 1 in cima
varying float v_ang;   // angolo attorno all'asse, per lo scintillio

void vertex() {
	v_h = clamp(VERTEX.y / max(mesh_height, 0.0001) + 0.5, 0.0, 1.0);
	v_ang = atan(VERTEX.x, VERTEX.z);
}

void fragment() {
	// Il velo sale dal pavimento mentre il campo si apre.
	float grow = smoothstep(0.0, 1.0, open);
	float vertical = pow(1.0 - v_h, falloff) * smoothstep(0.0, 0.15, grow - v_h + 0.15);

	// Colonne di brina che salgono lente attorno al perimetro.
	float shimmer = sin(v_ang * shimmer_scale + TIME * shimmer_speed * 2.0)
		* sin(v_ang * shimmer_scale * 0.63 - TIME * shimmer_speed);
	shimmer = 0.55 + 0.45 * smoothstep(-0.2, 0.9, shimmer);

	// Il velo si abbassa insieme al tempo rimanente: ridondanza col disco, cosi'
	// la durata si legge anche quando il pavimento e' coperto dai corpi.
	float fade = mix(0.30, 1.0, life);

	ALBEDO = tint.rgb * energy;
	ALPHA = clamp(vertical * shimmer * fade, 0.0, 1.0);
}
