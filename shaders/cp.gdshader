shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec2 pane_size = vec2(3.0, 4.0);   // world units, must match the QuadMesh size

uniform vec4 blue : source_color = vec4(0.1, 0.6, 1.0, 1.0);
uniform vec4 blue_accent : source_color = vec4(0.8, 0.95, 1.0, 1.0);
uniform vec4 green : source_color = vec4(0.1, 1.0, 0.4, 1.0);
uniform vec4 green_accent : source_color = vec4(0.85, 1.0, 0.85, 1.0);

// 0 = blue, 1 = green. Per instance, so each checkpoint switches on its own.
instance uniform float collected : hint_range(0.0, 1.0) = 0.0;
uniform float wipe_softness = 0.3;

uniform float intensity = 1.6;                 // above 1 so glow/bloom picks it up
uniform float fill : hint_range(0.0, 0.5) = 0.08;
uniform float line_width = 0.012;              // half-width in world units
uniform float grid_size = 0.25;
uniform float scan_speed = 0.3;
uniform float scan_strength = 0.35;
uniform float dot_density = 8.0;               // dot cells per world unit
uniform float dot_amount : hint_range(0.0, 1.0) = 0.25;
uniform float dot_size = 0.18;
uniform float dot_drift = 0.15;
uniform float flicker : hint_range(0.0, 0.3) = 0.05;

float hash11(float n) {
  return fract(sin(n * 127.1) * 43758.5453);
}

float hash12(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453);
}

// 1 within half-width w of a line at distance d, antialiased
float stroke(float d, float w, float aa) {
  return 1.0 - smoothstep(w - aa, w + aa, d);
}

float grid(vec2 p, float size, float w, float aa) {
  vec2 d = abs(fract(p / size + 0.5) - 0.5) * size;
  return stroke(min(d.x, d.y), w, aa);
}

// ring at radius r; segs > 0 breaks it into random arcs that rotate with rot
float ring(float rad, float ang, float r, float w, float aa, float segs, float seed, float rot, float cover) {
  float on = 1.0;
  if (segs > 0.0) {
    float seg = floor(fract(ang / TAU + rot) * segs);
    on = step(hash11(seg + seed * 17.0), cover);
  }
  return stroke(abs(rad - r), w, aa) * on;
}

float ticks(float rad, float ang, float r, float tick_len, float count, float w, float aa, float rot) {
  float k = fract(ang / TAU + rot) * count;
  float across = abs(fract(k + 0.5) - 0.5) * rad * TAU / count;
  return stroke(across, w, aa) * step(abs(rad - r), tick_len * 0.5);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

float trace_level(float i, float seed) {
  return floor(hash11(i + seed * 31.0) * 4.0) / 4.0;
}

// horizontal runs joined by diagonal steps, 0..1
float trace_y(float x, float seed) {
  float u = x / 0.9;
  float i = floor(u);
  float k = clamp((fract(u) - 0.55) / 0.45, 0.0, 1.0);
  return mix(trace_level(i, seed), trace_level(i + 1.0, seed), k);
}

void fragment() {
  vec2 p = (UV - 0.5) * pane_size;   // world units from the pane center
  p.y = -p.y;
  float y01 = 1.0 - UV.y;            // 0 at the bottom, 1 at the top
  float aa = (fwidth(p.x) + fwidth(p.y)) * 0.75;
  float R = min(pane_size.x, pane_size.y) * 0.5;
  float rad = length(p);
  float ang = atan(p.y, p.x);

  // blue -> green wipe rising from the bottom, with a bright front
  float edge_pos = collected * (1.0 + wipe_softness);
  float m = clamp((edge_pos - y01) / wipe_softness, 0.0, 1.0);
  float fx = (edge_pos - y01) / (wipe_softness * 0.35);
  float front = exp(-fx * fx) * step(0.001, collected) * step(collected, 0.999);

  // scan line sweeping upward; the grid lights up where it passes
  float scan = pow(1.0 - abs(fract(y01 - TIME * scan_speed) * 2.0 - 1.0), 24.0);

  float grids = grid(p, grid_size, line_width * 0.5, aa) * 0.18
    + grid(p, grid_size * 4.0, line_width * 0.8, aa) * 0.4;

  float rings = ring(rad, ang, R * 0.82, line_width, aa, 0.0, 0.0, 0.0, 1.0) * 0.8
    + ring(rad, ang, R * 0.68, line_width * 2.5, aa, 12.0, 1.0, TIME * 0.05, 0.6)
    + ring(rad, ang, R * 0.52, line_width * 1.8, aa, 9.0, 2.0, -TIME * 0.08, 0.55)
    + ring(rad, ang, R * 0.38, line_width * 0.8, aa, 0.0, 0.0, 0.0, 1.0) * 0.7
    + ring(rad, ang, R * 0.27, line_width * 3.0, aa, 6.0, 3.0, TIME * 0.12, 0.5)
    + ticks(rad, ang, R * 0.9, R * 0.07, 72.0, line_width * 0.6, aa, TIME * 0.02) * 0.8;

  // circuit traces near the top and bottom, with pulses running along them
  float traces = 0.0;
  float H = pane_size.y * 0.5;
  for (int i = 0; i < 4; i++) {
    float s = float(i);
    float row = (i % 2 == 0) ? 0.78 : 0.9;
    float by = ((i < 2) ? -1.0 : 1.0) * H * row;
    float ty = by + (trace_y(p.x + s * 3.1, s) - 0.5) * H * 0.12;
    float pulse = pow(fract(p.x * 0.35 - TIME * (0.3 + 0.1 * s) + s * 0.37), 6.0);
    traces += stroke(abs(p.y - ty), line_width, aa) * (0.35 + 0.9 * pulse);
  }

  // twinkling dots drifting upward
  vec2 q = p * dot_density + vec2(0.0, -TIME * dot_drift);
  vec2 id = floor(q);
  vec2 h = hash22(id);
  float present = step(1.0 - dot_amount, hash12(id + 3.7));
  float twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(TIME * (1.0 + h.x * 3.0) + h.y * 6.2831));
  float dd = length(fract(q) - 0.5 - (h - 0.5) * 0.6);
  float dots_v = present * twinkle * pow(1.0 - smoothstep(0.0, dot_size, dd), 2.0);

  // frame and corner brackets
  vec2 e = pane_size * 0.5 - abs(p);
  float edge = min(e.x, e.y);
  float bl = R * 0.24;
  float bw = line_width * 2.5;
  float frame = stroke(abs(edge - line_width), line_width * 0.6, aa) * 0.5
    + stroke(abs(e.x - bw), bw, aa) * step(e.y, bl)
    + stroke(abs(e.y - bw), bw, aa) * step(e.x, bl);

  // center mark: diamond before, checkmark after
  float diamond = stroke(abs(abs(p.x) + abs(p.y) - 0.14 * R), line_width * 1.5, aa);
  vec2 ca = vec2(-0.2, 0.02) * R;
  vec2 cb = vec2(-0.06, -0.14) * R;
  vec2 cc = vec2(0.24, 0.2) * R;
  float check = stroke(min(seg_dist(p, ca, cb), seg_dist(p, cb, cc)), line_width * 3.0, aa);
  float marks = diamond * (1.0 - m) + check * m;

  float body = fill * mix(1.0, 0.35, y01);
  float base = body + grids * (1.0 + scan * 4.0) + scan * scan_strength;
  float detail = rings + traces + frame + marks + dots_v;

  vec3 c_main = mix(blue.rgb, green.rgb, m);
  vec3 c_acc = mix(blue_accent.rgb, green_accent.rgb, m);
  vec3 col = mix(c_main, c_acc, clamp(detail * 0.8, 0.0, 1.0)) + c_acc * front * 2.0;

  float flick = 1.0 + flicker * sin(TIME * 43.0) * sin(TIME * 5.1);
  ALBEDO = col * intensity * flick;
  ALPHA = clamp((base + detail) * flick + front * 0.8, 0.0, 1.0);
}
