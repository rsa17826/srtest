shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color : source_color = vec4(0.2, 0.7, 1.0, 1.0);
uniform vec4 accent : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform float height = 20.0;               // must match the mesh height
uniform float intensity = 1.5;             // above 1 so glow/bloom picks it up
uniform float fill : hint_range(0.0, 1.0) = 0.1;   // base translucency of the column
uniform float top_fade : hint_range(0.0, 20.0) = 0.6; // fraction of height spent fading out
uniform float edge_power = 2.5;
uniform float edge_strength = 0.8;
uniform float spin_speed = 0.05;   // turns per second, positive = clockwise seen from above
uniform float spin_offset = 0.0;   // extra rotation in turns, driven from script while winning

// system-window panels
uniform float panel_count = 4.0;           // panels around the circumference (integer)
uniform float window_height = 3.0;         // world units per stacked window
uniform float frame_width = 0.06;          // world units
uniform float frame_strength = 0.9;
uniform float header_height = 0.35;        // world units
uniform float text_density = 4.0;          // text rows per world unit
uniform float text_scroll = 0.5;           // rows per second, upward
uniform float text_strength = 0.45;

// light streaks / scan ring
uniform float streak_count = 48.0;         // integer
uniform float streak_strength = 0.35;
uniform float scan_speed = 0.3;
uniform float flicker : hint_range(0.0, 0.5) = 0.08;

varying vec3 local_pos;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// block "text": p.x = 0..1 across the panel, p.y = rows
float text(vec2 p, float seed) {
  float row = floor(p.y);
  float line = step(0.28, fract(p.y)) - step(0.72, fract(p.y));

  float words = 12.0;
  float wx = p.x * words;
  float cell = floor(wx);
  float seg = step(0.12, fract(wx)) - step(0.82, fract(wx));

  float row_len = 0.35 + 0.6 * hash(vec2(row, seed));
  float present = step(hash(vec2(row * 3.7 + cell, seed + 1.3)), 0.6) * step(cell, row_len * words);
  float inside = step(0.08, p.x) - step(0.92, p.x);
  return line * seg * present * inside;
}

void vertex() {
  local_pos = VERTEX;
}

void fragment() {
  float y = local_pos.y + height * 0.5;          // distance up from the base
  float yn = clamp(y / height, 0.0, 1.0);
  float ang = fract(atan(local_pos.x, local_pos.z) / TAU + 0.5 + TIME * spin_speed + spin_offset);

  // panel / window coordinates
  float pa = ang * panel_count;
  float panel_id = floor(pa);
  float pu = fract(pa);
  float wy = y / window_height;
  float win_id = floor(wy);
  float wv = fract(wy);

  float panel_w = TAU * length(local_pos.xz) / panel_count;
  float from_side = min(pu, 1.0 - pu) * panel_w;
  float from_top = (1.0 - wv) * window_height;
  float from_bottom = wv * window_height;

  // frame and header bar, same thickness in world units on every side
  float frame = 1.0 - smoothstep(frame_width * 0.5, frame_width, min(from_side, min(from_top, from_bottom)));
  float header = step(frame_width, from_top) - step(frame_width + header_height, from_top);
  float body = step(frame_width + header_height, from_top) * step(frame_width * 2.0, from_bottom);
  float txt = text(vec2(pu, y * text_density - TIME * text_scroll), panel_id + win_id * 3.0) * body;

  // rim glow
  float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), edge_power);

  // rising streaks
  float sx = ang * streak_count;
  float sr = hash(vec2(floor(sx), 7.0));
  float sw = 1.0 - smoothstep(0.0, 0.2, abs(fract(sx) - 0.5));
  float sy = fract(y * 0.06 + sr * 10.0 - TIME * (0.25 + sr * 0.5));
  float streak = sw * pow(sy, 10.0) * step(0.5, sr);

  // bright ring sweeping upward
  float scan = pow(1.0 - abs(fract(y * 0.08 - TIME * scan_speed) * 2.0 - 1.0), 16.0);

  float pattern = frame * frame_strength + header * 0.35 + txt * text_strength
    + streak * streak_strength + scan * 0.4;
  float light = fill + fres * edge_strength + pattern;

  float env = 1.0 - smoothstep(1.0 - top_fade, 1.0, yn);   // fade out toward the top
  float base_glow = 1.0 - smoothstep(0.0, 0.04, yn);        // bright line where it meets the floor
  float flick = 1.0 + flicker * sin(TIME * 31.0 + y * 0.9) * sin(TIME * 7.3);

  ALBEDO = mix(color.rgb, accent.rgb, clamp(pattern, 0.0, 1.0)) * intensity;
  ALPHA = clamp(light * env * flick + base_glow * 0.6, 0.0, 1.0);
}
