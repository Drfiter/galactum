shader_type canvas_item;
// Transición de salto interestelar: estelas radiales que se alargan.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.45, 0.75, 1.0, 1.0);

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = (FRAGCOORD.xy - 0.5 * res) / res.y;
	float r = length(uv);
	float a = atan(uv.y, uv.x) / 6.28318 + 0.5;
	vec3 col = vec3(0.01, 0.015, 0.05);
	for (int layer = 0; layer < 3; layer++) {
		float lanes = 90.0 + float(layer) * 70.0;
		float f = a * lanes;
		float id = floor(f) + float(layer) * 1000.0;
		float h = h1(id);
		float spd = (0.25 + h * 0.8) * (0.3 + intensity * 2.2);
		float head = fract(h * 5.3 + TIME * spd) * 1.25;
		float len = 0.02 + intensity * (0.25 + h * 0.3);
		float d = head - r;
		float streak = step(0.0, d) * (1.0 - smoothstep(0.0, len, d));
		float lane = abs(fract(f) - 0.5);
		streak *= 1.0 - smoothstep(0.05, 0.25 + intensity * 0.1, lane);
		streak *= smoothstep(0.02, 0.15, r);
		vec3 sc = mix(tint.rgb, vec3(0.85, 0.6, 1.0), h);
		col += sc * streak * (1.4 + h);
	}
	col += tint.rgb * (1.0 - smoothstep(0.0, 0.45, r)) * (0.25 + intensity * 0.6);
	col = mix(col, vec3(1.0), flash);
	COLOR = vec4(col, alpha);
}
