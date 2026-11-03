shader_type spatial;
// Sombreado cartoon (estilo juego móvil) sin depender de luces de escena:
// 2 bandas de luz + luz de borde (rim) + emisión. Color por vértice:
// COLOR.rgb = albedo, COLOR.a = máscara de emisión (1 = brilla).
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 sun_dir = vec3(-0.45, 0.85, 0.35);
uniform vec4 shadow_color : source_color = vec4(0.42, 0.45, 0.72, 1.0);
uniform vec4 rim_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float rim_strength = 0.55;
uniform float emission_strength = 1.7;
uniform float flash = 0.0;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec3 base = vcol.rgb * tint.rgb;
	vec3 n = normalize(NORMAL);
	vec3 l = normalize((VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz);
	float ndl = dot(n, l);
	float band = smoothstep(-0.08, 0.06, ndl) * 0.65 + smoothstep(0.55, 0.65, ndl) * 0.35;
	vec3 lit = mix(base * shadow_color.rgb, base * 1.08, band);
	float rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 3.0);
	lit += rim_color.rgb * rim * rim_strength * (0.35 + 0.65 * band);
	lit = mix(lit, base * emission_strength, vcol.a);
	lit = mix(lit, vec3(1.0), flash);
	ALBEDO = lit;
}
