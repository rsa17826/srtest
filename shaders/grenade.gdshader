shader_type spatial;
// Purple explosive ball in the same hologram style as the blocks: additive, wire-sphere lines,
// fresnel rim, scanlines, row-slide glitch. Adds cracking energy veins, a hot core and an
// unstable pulsing swell. Drive `fuse` (0 = idle, 1 = about to blow) from the grenade script:
//   $MeshInstance3D.set_instance_shader_parameter("fuse", t)
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

instance uniform float fuse : hint_range(0.0, 1.0) = 0.0;

group_uniforms look;
uniform vec4 color : source_color = vec4(0.6, 0.2, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.6, 1.0, 1.0); // veins / core / flash as fuse rises
uniform float intensity : hint_range(0.0, 4.0) = 1.5;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.1;
uniform float rim_power : hint_range(0.5, 8.0) = 2.2;
uniform float rim_strength : hint_range(0.0, 3.0) = 1.3;

group_uniforms wireframe;
uniform float lat_lines = 8.0;
uniform float long_lines = 12.0;
uniform float line_width : hint_range(0.005, 0.2) = 0.05;
uniform float line_strength : hint_range(0.0, 4.0) = 1.8;

group_uniforms scanlines;
uniform float scan_density = 40.0;
uniform float scan_speed = 1.5;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.3;

group_uniforms energy;
uniform float vein_scale = 3.0;
uniform float vein_strength : hint_range(0.0, 4.0) = 1.6;
uniform float core_strength : hint_range(0.0, 4.0) = 1.2;

group_uniforms instability;
uniform float idle_pulse_rate = 1.2;   // pulses per second at fuse 0
uniform float armed_pulse_rate = 12.0; // ... and at fuse 1
uniform float swell : hint_range(0.0, 0.2) = 0.05;   // surface breathes outward on each pulse
uniform float spikes : hint_range(0.0, 0.3) = 0.08;  // jagged bulges that grow with the fuse
uniform float flicker : hint_range(0.0, 1.0) = 0.12;

group_uniforms glitch;
uniform float glitch_rate = 6.0;
uniform float glitch_chance : hint_range(0.0, 1.0) = 0.25; // raised automatically as the fuse burns
uniform float glitch_rows = 20.0;
uniform float glitch_row_chance : hint_range(0.0, 1.0) = 0.3;
uniform float glitch_shift : hint_range(0.0, 0.5) = 0.12;  // fraction of a full turn
uniform float glitch_split : hint_range(0.0, 0.1) = 0.015;

varying vec3 lpos;
varying vec3 wpos;
varying float g;
varying float pulse;

float hash(float n) {
  return fract(sin(n * 127.1) * 43758.5453);
}

float hash3(vec3 p) {
  return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float n000 = hash3(i);
  float n100 = hash3(i + vec3(1, 0, 0));
  float n010 = hash3(i + vec3(0, 1, 0));
  float n110 = hash3(i + vec3(1, 1, 0));
  float n001 = hash3(i + vec3(0, 0, 1));
  float n101 = hash3(i + vec3(1, 0, 1));
  float n011 = hash3(i + vec3(0, 1, 1));
  float n111 = hash3(i + vec3(1, 1, 1));
  return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
    mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
  lpos = VERTEX;
  float rate = mix(idle_pulse_rate, armed_pulse_rate, fuse * fuse);
  pulse = 0.5 + 0.5 * sin(TIME * rate * 6.2831853);
  pulse = pow(pulse, 3.0); // short sharp beats

  vec3 origin = MODEL_MATRIX[3].xyz;
  float tick = floor(TIME * glitch_rate);
  float id = dot(floor(origin), vec3(1.0, 57.0, 113.0));
  float fire = step(1.0 - clamp(glitch_chance + fuse * 0.6, 0.0, 1.0), hash(tick + id));
  g = fire * pow(1.0 - fract(TIME * glitch_rate), 3.0);

  // unstable surface: breathing + jagged bulges that crawl around the sphere as the fuse burns
  vec3 p = normalize(VERTEX);
  float bump = vnoise(p * 4.0 + vec3(0.0, TIME * 2.0, 0.0));
  float disp = swell * pulse * (0.4 + fuse) + spikes * fuse * bump * bump;
  VERTEX += NORMAL * disp;
  wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float thin_line(float x, float count) {
  // distance to the nearest multiple of 1/count, as a bright line
  float d = abs(fract(x * count + 0.5) - 0.5) / count;
  return 1.0 - smoothstep(0.0, line_width * 0.25, d);
}

float surface_pattern(vec3 p, float lon_shift) {
  float lat = asin(clamp(p.y, -1.0, 1.0)) / 3.14159265 + 0.5; // 0..1 pole to pole
  float lon = atan(p.z, p.x) / 6.2831853 + 0.5 + lon_shift;   // 0..1 around
  float lines = max(thin_line(lat, lat_lines), thin_line(lon, long_lines));

  // cracking energy: bright ridges of noise that flow over the surface
  float n = vnoise(p * vein_scale + vec3(0.0, -TIME * 0.5, 0.0));
  float ridge = 1.0 - abs(n * 2.0 - 1.0);
  ridge = pow(ridge, 6.0);
  return lines * line_strength + ridge * vein_strength * (0.35 + fuse);
}

void fragment() {
  vec3 N = normalize(NORMAL);
  vec3 V = normalize(VIEW);
  float facing = clamp(dot(N, V), 0.0, 1.0);
  float fres = pow(1.0 - facing, rim_power);
  float core = pow(facing, 4.0) * core_strength * (0.3 + fuse) * (0.6 + 0.8 * pulse);

  vec3 p = normalize(lpos);

  // glitch: rows of the surface pattern slide around the ball (a sideways slide on a face)
  float tick = floor(TIME * glitch_rate);
  float row = floor(wpos.y * glitch_rows);
  float slides = step(0.02, g) * step(1.0 - glitch_row_chance, hash(row * 3.7 + tick * 17.0 + dot(floor(MODEL_MATRIX[3].xyz), vec3(1.0, 57.0, 113.0))));
  float shift = (hash(row + tick * 31.0) - 0.5) * 2.0 * glitch_shift * slides;

  float p0 = surface_pattern(p, shift);
  float p1 = surface_pattern(p, shift + glitch_split);
  float p2 = surface_pattern(p, shift - glitch_split);

  float scan = 0.5 + 0.5 * sin(wpos.y * scan_density * 6.2831853 / 6.0 - TIME * scan_speed * 6.2831853);
  scan = mix(1.0, scan, scan_strength);

  float f = 1.0 - flicker * hash(floor(TIME * 30.0));
  f *= 1.0 - 0.5 * step(0.985, hash(floor(TIME * 6.0) + 7.0));

  // colour heats from purple toward hot pink-white as the fuse burns; each beat flashes it
  float heat = clamp(fuse * 0.7 + pulse * fuse * 0.6, 0.0, 1.0);
  vec3 tint = mix(color.rgb, hot_color.rgb, heat);

  float body = base_alpha + fres * rim_strength;
  vec3 glow = tint * (body + p0 + core) * scan
    + vec3(1.0, 0.3, 0.6) * p1 * slides * 0.5
    + vec3(0.4, 0.6, 1.0) * p2 * slides * 0.5;
  glow *= 1.0 + pulse * (0.3 + fuse * 1.2); // beat
  glow *= 1.0 + slides * 0.5;

  ALBEDO = glow * f * intensity;
  ALPHA = 1.0;
}
