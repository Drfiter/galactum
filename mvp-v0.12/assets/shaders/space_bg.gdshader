shader_type canvas_item;
// Fondo del sistema solar: nebulosa procedural + 3 capas de estrellas con
// parallax + rejilla del mapa en coordenadas de mundo + borde del sistema.

uniform vec2 cam_pos = vec2(9600.0, 9600.0);   // centro de cámara en px de mundo
uniform float zoom = 1.0;
uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform float tile = 32.0;
uniform float map_tiles = 600.0;
uniform float grid_alpha = 1.0;
uniform vec4 nebula_a : source_color = vec4(0.16, 0.08, 0.34, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.02, 0.18, 0.32, 1.0);
uniform vec4 base_col : source_color = vec4(0.012, 0.02, 0.055, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
float stars(vec2 p, float density, float size) {
	vec2 cell = floor(p); vec2 f = fract(p);
	float h = hash(cell);
	if (h > density) return 0.0;
	vec2 c = vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.8 + 0.1;
	float d = length(f - c);
	float tw = 0.75 + 0.25 * sin(TIME * (1.0 + h * 3.0) + h * 40.0);
	return smoothstep(size, 0.0, d) * tw;
}

void fragment() {
	vec2 frag = UV * screen_size;
	vec2 world = cam_pos + (frag - screen_size * 0.5) / zoom;   // px de mundo
	vec3 col = base_col.rgb;

	// Nebulosa con parallax lento
	vec2 np = (cam_pos * 0.12 + (frag - screen_size * 0.5)) / 900.0;
	float n1 = fbm(np + vec2(TIME * 0.004, 0.0));
	float n2 = fbm(np * 1.7 + vec2(4.2, 1.3));
	col += nebula_a.rgb * smoothstep(0.45, 0.95, n1) * 0.55;
	col += nebula_b.rgb * smoothstep(0.5, 1.0, n2) * 0.5;

	// Estrellas: tres capas con parallax distinto
	vec2 sp = frag;
	col += vec3(0.75, 0.85, 1.0) * stars((sp + cam_pos * 0.05) / 9.0, 0.08, 0.10) * 0.55;
	col += vec3(1.0, 0.95, 0.85) * stars((sp + cam_pos * 0.12) / 23.0, 0.10, 0.08) * 0.8;
	col += vec3(0.7, 0.9, 1.0) * stars((sp + cam_pos * 0.25) / 61.0, 0.12, 0.06) * 1.0;

	// Rejilla de sectores (cada 10 casillas) y casillas finas al acercar
	vec2 t = world / tile;
	vec2 g10 = abs(fract(t / 10.0 - 0.5) - 0.5) * 10.0 * tile * zoom;
	float line10 = 1.0 - smoothstep(0.0, 1.3, min(g10.x, g10.y));
	vec2 g1 = abs(fract(t - 0.5) - 0.5) * tile * zoom;
	float line1 = (1.0 - smoothstep(0.0, 1.0, min(g1.x, g1.y))) * smoothstep(0.7, 1.4, zoom);
	float inside = step(0.0, t.x) * step(0.0, t.y) * step(t.x, map_tiles) * step(t.y, map_tiles);

	// Disco del sistema y anillo de borde
	float r = length(t - vec2(map_tiles * 0.5)) / (map_tiles * 0.5 - 6.0);
	float disc = 1.0 - smoothstep(0.98, 1.0, r);
	col += vec3(0.15, 0.35, 0.75) * (line10 * 0.10 + line1 * 0.035) * inside * disc * grid_alpha;
	float ring = exp(-pow((r - 1.0) * 60.0, 2.0));
	col += vec3(0.25, 0.55, 1.0) * ring * 0.35;
	// Tenue resplandor central (zona rica / Portal de Salto)
	col += vec3(0.35, 0.22, 0.6) * exp(-r * r * 9.0) * 0.18;

	COLOR = vec4(col, 1.0);
}
