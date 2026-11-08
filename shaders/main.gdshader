
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.08, 0.09, 0.14, 1.0);
uniform vec4 line_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);

uniform float cell_size = 1.0;
uniform float line_width : hint_range(0.0, 0.2) = 0.03;
uniform float emission_strength = 1.5;

// Moving lines
uniform vec4 move_color : source_color = vec4(1.0);
uniform vec2 move_dir = vec2(0.0, 1.0);
uniform float move_speed = 0.5;
uniform float move_spacing = 0.5;
uniform float move_width = 0.015;
uniform float move_emission = 2.0;

// Spikes
uniform float spike_size = 0.2;
uniform float spike_height = 0.12;
uniform float spike_width = 0.25;
uniform float spike_speed = 1.0;
uniform float spike_pulse = 0.5;
uniform float spike_randomness = 0.5;

varying vec3 world_pos;
varying vec3 world_normal;

// Random hash
float hash(float x) {
  return fract(sin(x * 127.1) * 43758.5453);
}

// Procedural spike shape
float spike_at(float x, float k) {
  float seed = hash(k);

  // Random spike center
  float center = k + 0.5 +
      (hash(k + 10.0) - 0.5) * spike_randomness;

  // Random width
  float width = spike_width *
      mix(0.6, 1.4, hash(k + 20.0));

  // Random height
  float height = mix(0.4, 1.0, hash(k + 30.0));

  // Animated pulse
  float pulse = 1.0 +
      spike_pulse * sin(
          TIME * spike_speed + seed * 6.2831
      );

  float dx = abs(x - center);

  // Triangle-shaped spike
  float tip = max(0.0, 1.0 - dx / width);

  return tip * height * pulse;
}

// Animated spike pattern
float spike_pattern(float along) {
  float x = along / spike_size - TIME * spike_speed;

  float k = floor(x);

  float a = spike_at(x, k - 1.0);
  float b = spike_at(x, k);
  float c = spike_at(x, k + 1.0);

  return max(a, max(b, c));
}

void vertex() {
  world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

  world_normal = normalize(
      (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz
  );
}

void fragment() {

  // Triplanar-style projection
  vec3 n = abs(normalize(world_normal));

  vec2 uv;

  if (n.y > n.x && n.y > n.z) {
      uv = world_pos.xz;
  }
  else if (n.x > n.z) {
      uv = world_pos.zy;
  }
  else {
      uv = world_pos.xy;
  }

  // --------------------------------
  // STATIC GRID
  // --------------------------------

  vec2 d = abs(fract(uv / cell_size) - 0.5);

  float grid = smoothstep(
      0.5 - line_width,
      0.5,
      max(d.x, d.y)
  );

  // --------------------------------
  // MOVING LINES
  // --------------------------------

  vec2 direction = normalize(move_dir);

  // Direction perpendicular to line movement
  vec2 normal_dir = vec2(-direction.y, direction.x);

  // Coordinates along and across the line
  float along = dot(uv, direction);

  float across = dot(uv, normal_dir);

  // Moving repeating lines
  float line_phase = across / move_spacing
      - TIME * move_speed;

  float line_distance = abs(
      fract(line_phase + 0.5) - 0.5
  ) * move_spacing;

  // --------------------------------
  // SPIKES
  // --------------------------------

  float spikes = spike_pattern(along);

  // Give each moving line a spiky silhouette
  float width = move_width +
      spikes * spike_height;

  float moving_line = 1.0 - smoothstep(
      width,
      width + 0.01,
      line_distance
  );

  // --------------------------------
  // COLOR
  // --------------------------------

  vec3 color = base_color.rgb;

  color = mix(
      color,
      line_color.rgb,
      grid
  );

  color = mix(
      color,
      move_color.rgb,
      moving_line
  );

  // --------------------------------
  // EMISSION
  // --------------------------------

  vec3 emission =
      line_color.rgb * grid * emission_strength;

  emission +=
      move_color.rgb * moving_line * move_emission;

  ALBEDO = color;
  EMISSION = emission;
  ROUGHNESS = 0.35;
  METALLIC = 0.1;
}
