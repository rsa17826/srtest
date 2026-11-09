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
uniform float glitch : hint_range(0.0, 0.2) = 0.04;       // sideways tear when the band passes

varying vec3 lpos;
varying vec3 wpos;

float hash(float n) {
  return fract(sin(n * 127.1) * 43758.5453);
}

float band_at(float y) {
  return fract(y / sweep_period - TIME * sweep_speed);
}

void vertex() {
  lpos = VERTEX;
  vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
  wpos = w;
  // tear: vertices inside the sweep band slide sideways in a hash-based direction
  float b = band_at(w.y);
  float in_band = smoothstep(0.0, 0.03, b) * (1.0 - smoothstep(0.03, 0.06, b));
  float tick = floor(TIME * 12.0);
  VERTEX.x += (hash(tick) - 0.5) * 2.0 * glitch * in_band;
}

void fragment() {
  // fresnel rim
  float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);

  // cube edges: bright where two faces' borders meet
  vec3 n = smoothstep(half_size - edge_width, half_size, abs(lpos));
  float edge = clamp(n.x * n.y + n.y * n.z + n.x * n.z, 0.0, 1.0);

  // scanlines + travelling sweep band (world space)
  float scan = 0.5 + 0.5 * sin(wpos.y * scan_density * 6.2831853 / 6.0 - TIME * scan_speed * 6.2831853);
  scan = mix(1.0, scan, scan_strength);
  float b = band_at(wpos.y);
  float sweep = smoothstep(0.0, 0.02, b) * pow(1.0 - b, 6.0) * sweep_strength;

  // flicker: fast low-amplitude noise plus an occasional brief dip
  float tick = floor(TIME * 30.0);
  float f = 1.0 - flicker * hash(tick);
  f *= 1.0 - 0.5 * step(0.985, hash(floor(TIME * 6.0) + 7.0));

  float glow = base_alpha + fres * rim_strength + edge * edge_strength + sweep;
  glow *= scan * f * intensity;

  ALBEDO = color.rgb * glow;
  ALPHA = 1.0; // blend_add: brightness carries the effect
}
