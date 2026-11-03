shader_type canvas_item;
// Recorta el arte de xenoforma/retrato a un círculo con borde brillante.
uniform vec2 center = vec2(0.5, 0.46);
uniform float radius = 0.37;
uniform vec4 ring_color : source_color = vec4(1.0, 0.3, 0.4, 1.0);
uniform float ring_width = 0.035;
uniform float flash = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, center);
	float mask = 1.0 - smoothstep(radius - 0.01, radius, d);
	float ring = smoothstep(radius - ring_width - 0.01, radius - ring_width, d) * (1.0 - smoothstep(radius, radius + 0.012, d));
	vec3 col = mix(c.rgb, vec3(1.0), flash);
	col = mix(col, ring_color.rgb, ring * 0.9);
	float a = max(mask * c.a, ring * 0.95);
	COLOR = vec4(col, a) * COLOR;
}
