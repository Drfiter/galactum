shader_type spatial;
// Suelo del sistema solar: nebulosa + rejilla holográfica de sectores + borde
// del disco + resplandor central. Coordenadas de mundo = casillas.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float map_tiles = 600.0;
uniform float grid_alpha = 1.0;
uniform vec4 deep : source_color = vec4(0.02, 0.035, 0.11, 1.0);
uniform vec4 neb_a : source_color = vec4(0.30, 0.12, 0.55, 1.0);
uniform vec4 neb_b : source_color = vec4(0.05, 0.32, 0.55, 1.0);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.05; a *= 0.5; }
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 t = wpos.xz;
	vec3 col = deep.rgb;
	float n1 = fbm(t / 60.0 + vec2(TIME * 0.01, 0.0));
	float n2 = fbm(t / 37.0 + vec2(3.7, 9.1));
	col += neb_a.rgb * smoothstep(0.35, 0.85, n1) * 0.9;
	col += neb_b.rgb * smoothstep(0.4, 0.9, n2) * 0.75;
	// polvo estelar
	vec2 sc = floor(t * 0.7);
	vec2 sf = fract(t * 0.7) - vec2(hash(sc + 3.1), hash(sc + 7.3)) * 0.6 - 0.2;
	float st = step(0.93, hash(sc)) * (1.0 - smoothstep(0.0, 0.06, length(sf))) * (0.6 + 0.4 * sin(TIME * 2.0 + hash(sc + 1.0) * 30.0));
	col += vec3(0.75, 0.88, 1.0) * st * 0.9;
	// rejilla: sectores de 10 casillas y casillas finas
	vec2 g10 = abs(fract(t / 10.0 - 0.5) - 0.5) * 10.0;
	float l10 = 1.0 - smoothstep(0.0, 0.09, min(g10.x, g10.y));
	vec2 g1 = abs(fract(t - 0.5) - 0.5);
	float l1 = 1.0 - smoothstep(0.0, 0.035, min(g1.x, g1.y));
	float r = length(t - vec2(map_tiles * 0.5)) / (map_tiles * 0.5 - 6.0);
	float inside = 1.0 - smoothstep(0.985, 1.0, r);
	col += vec3(0.20, 0.45, 0.95) * (l10 * 0.22 + l1 * 0.06) * inside * grid_alpha;
	col += vec3(0.30, 0.65, 1.0) * exp(-pow((r - 1.0) * 70.0, 2.0)) * 0.8;
	col += vec3(0.45, 0.25, 0.8) * exp(-r * r * 10.0) * 0.25;
	col *= mix(0.35, 1.0, inside);
	ALBEDO = col;
}
