shader_type spatial;
// Cracks-only shader for breakable walls. Stackable: put it in the wall's
// GeometryInstance3D.material_overlay (or a material's next_pass) on top of any base material,
// including the hologram shader. World-space triplanar, so no UVs and no seams between blocks.
// `damage` 0..1 reveals cracks progressively (set per wall with an instance uniform).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

group_uniforms look;
uniform vec4 color : source_color = vec4(1.0, 0.75, 0.35, 1.0);
uniform float intensity : hint_range(0.0, 6.0) = 2.5;
uniform float glow_width : hint_range(0.0, 0.2) = 0.06;   // soft halo around each crack
uniform float crack_width : hint_range(0.002, 0.08) = 0.016;
uniform float flicker : hint_range(0.0, 1.0) = 0.25;      // cracks shimmer as if energy leaks out

group_uniforms pattern;
uniform float scale = 1.6;            // cells per metre (smaller = bigger chunks)
uniform float warp = 0.35;            // wobble so cracks aren't straight lines
uniform float seed = 0.0;             // change per wall for variety

instance uniform float damage : hint_range(0.0, 1.0) = 0.5;

varying vec3 wpos;
varying vec3 wnrm;

vec2 hash2(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453);
}
float hash1(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// returns x = distance to nearest cell border, y = per-border random threshold
vec2 crack(vec2 p) {
  p += warp * (hash2(floor(p * 0.7) + seed) - 0.5) * 2.0 * sin(p.yx * 1.7 + seed);
  vec2 ip = floor(p);
  vec2 fp = fract(p);
  float d1 = 8.0, d2 = 8.0;
  vec2 id1 = vec2(0.0), id2 = vec2(0.0);
  vec2 pt1 = vec2(0.0), pt2 = vec2(0.0);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 g = vec2(float(i), float(j));
      vec2 o = hash2(ip + g + seed);
      vec2 r = g + o - fp;
      float d = dot(r, r);
      if (d < d1) { d2 = d1; id2 = id1; pt2 = pt1; d1 = d; id1 = ip + g; pt1 = r; }
      else if (d < d2) { d2 = d; id2 = ip + g; pt2 = r; }
    }
  }
  // exact distance to the bisector between the two nearest points
  vec2 mid = 0.5 * (pt1 + pt2);
  float edge = dot(mid, normalize(pt2 - pt1));
  float thr = fract(hash1(id1) + hash1(id2)); // symmetric per-border value
  return vec2(edge, thr);
}

void vertex() {
  wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
  wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
  vec3 n = abs(normalize(wnrm));
  vec2 uv;
  if (n.x > n.y && n.x > n.z) uv = wpos.zy;
  else if (n.y > n.z) uv = wpos.xz;
  else uv = wpos.xy;

  vec2 c = crack(uv * scale);
  float dist = c.x / scale;                 // metres to the crack line
  // a border appears once damage passes its threshold; it then grows over the next 15%
  float grow = clamp((damage - c.y * 0.85) / 0.15, 0.0, 1.0);
  float w = crack_width * grow;
  float line = 1.0 - smoothstep(w * 0.4, w, dist);
  float halo = (1.0 - smoothstep(0.0, glow_width, dist)) * grow * 0.35;
  float fl = 1.0 - flicker * fract(sin(floor(TIME * 18.0 + c.y * 50.0)) * 4375.5);

  vec3 col = color.rgb * (line + halo) + vec3(1.0) * line * 0.5;
  ALBEDO = col * intensity * fl;
  ALPHA = clamp(line + halo, 0.0, 1.0);
}
