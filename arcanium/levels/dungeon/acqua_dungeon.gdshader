shader_type spatial;

// L'acqua dei canali e della fontana: scura, poco profonda, che scorre piano
// lungo `flusso`. Due rumori che scivolano in versi diversi fanno le crespe;
// il fresnel la schiarisce di taglio, cosi' si legge anche al buio, dove la
// colpisce una torcia.

render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 colore : source_color = vec4(0.05, 0.11, 0.12, 0.82);
uniform vec4 colore_riflesso : source_color = vec4(0.35, 0.45, 0.5, 1.0);
uniform sampler2D crespe : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 flusso = vec2(0.0, 0.25);
uniform float scala = 0.35;

varying vec3 pos_mondo;

void vertex() {
	pos_mondo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = pos_mondo.xz * scala;
	vec3 n1 = texture(crespe, uv + flusso * TIME).rgb;
	vec3 n2 = texture(crespe, uv * 1.7 - flusso.yx * TIME * 0.6).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.6;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(colore.rgb, colore_riflesso.rgb, fresnel * 0.6);
	ALPHA = mix(colore.a, 1.0, fresnel * 0.5);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
