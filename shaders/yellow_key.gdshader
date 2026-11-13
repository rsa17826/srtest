shader_type spatial;
render_mode cull_back;

// Yellow key: shiny gold metal with a rim glow and a glint that sweeps across it.

uniform vec4 base_color : source_color = vec4(1.0, 0.82, 0.1, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.5, 1.0);
uniform vec4 glint_color : source_color = vec4(1.0, 1.0, 0.85, 1.0);

uniform float metallic : hint_range(0.0, 1.0) = 0.9;
uniform float roughness : hint_range(0.0, 1.0) = 0.25;

uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.6;

uniform float glint_speed = 0.6;
uniform float glint_width : hint_range(0.01, 0.5) = 0.08;
uniform float glint_strength : hint_range(0.0, 3.0) = 1.5;
uniform float glint_pause : hint_range(0.0, 4.0) = 1.5; // idle time between sweeps
uniform vec3 glint_dir = vec3(1.0, 1.0, 0.0); // model-space direction the glint travels

varying vec3 model_pos;

void vertex() {
  model_pos = VERTEX;
}

void fragment() {
  float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

  // sweep: position along glint_dir wraps over a cycle longer than the sweep, giving a pause
  float cycle = 1.0 + glint_pause;
  float phase = mod(TIME * glint_speed, cycle) - 0.5;
  float along = dot(model_pos, normalize(glint_dir));
  float glint = smoothstep(glint_width, 0.0, abs(along - phase));

  ALBEDO = base_color.rgb;
  METALLIC = metallic;
  ROUGHNESS = roughness;
  EMISSION = rim_color.rgb * fresnel * rim_strength + glint_color.rgb * glint * glint_strength;
}
