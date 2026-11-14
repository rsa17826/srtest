shader_type spatial;
// Laser beam for a CylinderMesh (height axis = beam axis, UV.y runs along it).
// Hot white core + coloured halo (view-angle falloff), energy pulses streaming away from the
// emitter, flicker, and a tip flare. `power` 0..1 drives telegraph (thin/dim) -> full fire.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

group_uniforms look;
uniform vec4 color : source_color = vec4(1.0, 0.1, 0.15, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.85, 1.0);
uniform float intensity : hint_range(0.0, 6.0) = 2.5;
uniform float core_sharpness : hint_range(1.0, 12.0) = 5.0;
uniform float halo_falloff : hint_range(0.5, 6.0) = 1.6;

group_uniforms pulses;
uniform float length_units = 10.0;      // beam length in metres (set by the script)
uniform float pulse_speed = 14.0;       // metres per second
uniform float pulse_spacing = 1.5;      // metres between pulses
uniform float pulse_strength : hint_range(0.0, 2.0) = 0.7;
uniform float flicker : hint_range(0.0, 1.0) = 0.15;

group_uniforms state;
uniform float power : hint_range(0.0, 1.0) = 1.0;
uniform float fade_end_units = 0.6;     // tip fade length

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void fragment() {
  vec3 n = normalize(NORMAL);
  float facing = abs(dot(n, normalize(VIEW)));          // 1 at the beam's centreline, 0 at its edge
  float core = pow(facing, core_sharpness);
  float halo = pow(facing, halo_falloff);

  float along = UV.y * length_units;
  float pulse_phase = fract((along - TIME * pulse_speed) / pulse_spacing);
  float pulses = smoothstep(0.0, 0.08, pulse_phase) * (1.0 - smoothstep(0.08, 0.6, pulse_phase));
  float fl = 1.0 - flicker * hash(floor(TIME * 40.0));

  // Telegraph: thin dim line. Fire: full width. (Width itself is the mesh radius, set by the script.)
  float amt = power * power;
  float tip = smoothstep(0.0, fade_end_units, length_units - along);
  float base = smoothstep(0.0, 0.25, along);

  vec3 col = color.rgb * halo + core_color.rgb * core * 1.5;
  col *= (1.0 + pulses * pulse_strength) * fl * tip * base;
  ALBEDO = col * intensity * amt;
  ALPHA = clamp(max(halo, core), 0.0, 1.0) * amt;
}
