shader_type spatial;
// Hologram block: additive, unshaded. Works on GridMap tiles (no instance uniforms used,
// every effect is derived from world position so neighbouring blocks line up).
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

group_uniforms look;
uniform vec4 color : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.12;   // see-through body fill
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;     // fresnel tightness
uniform float rim_strength : hint_range(0.0, 3.0) = 1.2;
uniform float intensity : hint_range(0.0, 4.0) = 1.5;

group_uniforms edges;
uniform float half_size = 0.5;                            // half the block's size in mesh space
uniform float edge_width : hint_range(0.01, 0.3) = 0.06;
uniform float edge_strength : hint_range(0.0, 4.0) = 2.0;

group_uniforms scanlines;
uniform float scan_density = 40.0;                        // lines per world unit
uniform float scan_speed = 1.5;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.35;
uniform float sweep_speed = 0.25;                         // the bright band that travels upward
uniform float sweep_period = 12.0;                        // world units between bands
uniform float sweep_strength : hint_range(0.0, 3.0) = 1.0;

group_uniforms instability;
uniform float flicker : hint_range(0.0, 1.0) = 0.12;

group_uniforms glitch;
uniform float glitch_rate = 6.0;                          // glitch checks per second
uniform float glitch_chance : hint_range(0.0, 1.0) = 0.25; // chance a block glitches on a check
uniform float glitch_rows = 24.0;                         // glitch rows per world unit of height
uniform float glitch_row_chance : hint_range(0.0, 1.0) = 0.3; // share of rows that slide while glitching
uniform float glitch_shift : hint_range(0.0, 0.5) = 0.18; // max sideways slide, in block units
uniform float glitch_split : hint_range(0.0, 0.1) = 0.02; // horizontal colour fringe on slid rows

varying vec3 lpos;
varying vec3 lnrm;
varying vec3 wpos;
varying float g; // 1 at the start of a block's glitch burst, decaying to 0

float hash(float n) {
  return fract(sin(n * 127.1) * 43758.5453);
}

float band_at(float y) {
  return fract(y / sweep_period - TIME * sweep_speed);
}

void vertex() {
  lpos = VERTEX;
  lnrm = NORMAL;
  vec3 origin = MODEL_MATRIX[3].xyz; // same for every vertex of this block
  float tick = floor(TIME * glitch_rate);
  float id = dot(floor(origin), vec3(1.0, 57.0, 113.0));
  float fire = step(1.0 - glitch_chance, hash(tick + id));
  g = fire * pow(1.0 - fract(TIME * glitch_rate), 3.0);
  wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// edges + scanlines + sweep, evaluated at a (possibly displaced) position
float pattern(vec3 lp, vec3 wp) {
  vec3 n = smoothstep(half_size - edge_width, half_size, abs(lp));
  float edge = clamp(n.x * n.y + n.y * n.z + n.x * n.z, 0.0, 1.0);

  float scan = 0.5 + 0.5 * sin(wp.y * scan_density * 6.2831853 / 6.0 - TIME * scan_speed * 6.2831853);
  scan = mix(1.0, scan, scan_strength);
  float b = band_at(wp.y);
  float sweep = smoothstep(0.0, 0.02, b) * pow(1.0 - b, 6.0) * sweep_strength;

  return (edge * edge_strength + sweep) * scan;
}

void fragment() {
  float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);

  // glitch: some horizontal rows of this face slide sideways, along the face (never in/out)
  float tick = floor(TIME * glitch_rate);
  float row = floor(wpos.y * glitch_rows);
  float slides = step(0.02, g) * step(1.0 - glitch_row_chance, hash(row * 3.7 + tick * 17.0 + dot(floor(MODEL_MATRIX[3].xyz), vec3(1.0, 57.0, 113.0))));
  float amount = (hash(row + tick * 31.0) - 0.5) * 2.0 * glitch_shift * slides;

  vec3 nrm = normalize(lnrm);
  vec3 tang = cross(vec3(0.0, 1.0, 0.0), nrm);
  tang = length(tang) < 0.01 ? vec3(1.0, 0.0, 0.0) : normalize(tang); // top / bottom faces

  // slide along the tangent and wrap inside the block so lines don't run off the face
  float along = dot(lpos, tang);
  float moved = mod(along + amount + half_size, 2.0 * half_size) - half_size;
  vec3 lp = lpos + tang * (moved - along);

  float p0 = pattern(lp, wpos);
  float p1 = pattern(lp + tang * glitch_split, wpos); // colour fringe, sideways only
  float p2 = pattern(lp - tang * glitch_split, wpos);
  float fringe = slides;

  float f = 1.0 - flicker * hash(floor(TIME * 30.0));
  f *= 1.0 - 0.5 * step(0.985, hash(floor(TIME * 6.0) + 7.0));

  float body = base_alpha + fres * rim_strength;
  vec3 glow = color.rgb * (body + p0)
    + vec3(1.0, 0.3, 0.6) * p1 * fringe * 0.5
    + vec3(0.4, 0.6, 1.0) * p2 * fringe * 0.5;
  glow *= 1.0 + slides * 0.5; // slid rows are a bit brighter

  ALBEDO = glow * f * intensity;
  ALPHA = 1.0;
}
