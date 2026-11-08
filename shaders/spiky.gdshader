shader_type spatial;
render_mode specular_disabled;

uniform vec4 base_color : source_color = vec4(0.01, 0.01, 0.015, 1.0);
uniform vec4 glow_color : source_color = vec4(0.7, 0.0, 0.12, 1.0);
uniform float rim_power = 3.0;
uniform float rim_strength = 1.2;
uniform float tip_glow = 1.5;

uniform float radius = 1.0;
uniform float spike_height = 0.7;
uniform float spike_freq = 4.0;        // more = more, smaller spikes
uniform float spike_width = 0.7;       // base width of each spike
uniform float spike_sharpness = 2.0;   // higher = thinner, pointier
uniform float pulse_speed = 2.0;
uniform float pulse_amount = 0.5;      // how much each spike grows/shrinks
uniform float breathe_amount = 0.08;   // whole-body expansion

varying float tip;

vec3 hash3(vec3 p) {
  p = vec3(
    dot(p, vec3(127.1, 311.7, 74.7)),
    dot(p, vec3(269.5, 183.3, 246.1)),
    dot(p, vec3(113.5, 271.9, 124.6)));
  return fract(sin(p) * 43758.5453);
}

// x = distance to nearest spike point, y = random id of that spike
vec2 nearest_spike(vec3 dir) {
  vec3 p = dir * spike_freq;
  vec3 ip = floor(p);
  float best = 10.0;
  float id = 0.0;
  for (int x = -1; x <= 1; x++) {
    for (int y = -1; y <= 1; y++) {
      for (int z = -1; z <= 1; z++) {
        vec3 c = ip + vec3(float(x), float(y), float(z));
        vec3 h = hash3(c);
        float d = distance(p, c + h);
        if (d < best) {
          best = d;
          id = h.x;
        }
      }
    }
  }
  return vec2(best, id);
}

float surface_radius(vec3 dir) {
  vec2 s = nearest_spike(dir);
  // each spike gets its own phase so they don't all pulse in sync
  float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed + s.y * 6.2831);
  float breathe = 1.0 + breathe_amount * sin(TIME * pulse_speed);
  // distance has a sharp minimum at each point, which gives pointed tips
  float spike = pow(clamp(1.0 - s.x / spike_width, 0.0, 1.0), spike_sharpness);
  return radius * breathe + spike_height * spike * pulse;
}

void vertex() {
  vec3 dir = normalize(VERTEX);

  // tangent frame to sample neighbors for the new normal
  vec3 up = abs(dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
  vec3 t = normalize(cross(up, dir));
  vec3 b = cross(dir, t);
  float e = 0.02;
  vec3 d1 = normalize(dir + t * e);
  vec3 d2 = normalize(dir + b * e);

  float r0 = surface_radius(dir);
  vec3 p0 = dir * r0;
  vec3 p1 = d1 * surface_radius(d1);
  vec3 p2 = d2 * surface_radius(d2);

  VERTEX = p0;
  NORMAL = normalize(cross(p1 - p0, p2 - p0));
  tip = clamp((r0 - radius) / spike_height, 0.0, 1.0);
}

void fragment() {
  ALBEDO = base_color.rgb;       // keep near-black, e.g. vec4(0.0, 0.0, 0.0, 1.0)
  ROUGHNESS = 1.0;               // fully rough = no sharp highlights
  SPECULAR = 0.0;                // no specular lobe at all
  METALLIC = 0.0;                // metallic would reflect the sky

  float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
  float beat = 0.6 + 0.4 * sin(TIME * pulse_speed);
  EMISSION = glow_color.rgb * (fres * rim_strength * beat + tip * tip * tip_glow * beat);
}
