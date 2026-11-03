shader_type spatial;
// Anillo luminoso en el suelo (selección, relación, destino).
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 color : source_color = vec4(0.25, 0.8, 1.0, 1.0);
uniform float dashes = 0.0;
uniform float speed = 0.6;
uniform float intensity = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.78, 0.86, r) * (1.0 - smoothstep(0.92, 1.0, r));
	float inner = (1.0 - smoothstep(0.0, 0.9, r)) * 0.12;
	float a = atan(p.y, p.x) / 6.2831 + 0.5;
	float d = dashes > 0.0 ? step(0.45, fract(a * dashes + TIME * speed)) : 1.0;
	ALBEDO = color.rgb * (ring * d * 1.6 + inner) * intensity;
	ALPHA = 1.0;
}
