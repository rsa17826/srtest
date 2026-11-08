shader_type spatial;
render_mode specular_disabled;

uniform vec4 base_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.7, 0.0, 0.12, 1.0);
uniform float rim_power = 4.0;
uniform float rim_strength = 0.4;
uniform float tip_glow = 0.5;

uniform float spike_density = 3.0;      // spikes per world unit (each axis)
uniform float spike_width = 0.4;        // cone base radius in spike-cells, keep <= ~0.45
uniform float spike_height = 0.5;       // world units
uniform float spike_sharpness = 2.0;    // higher = thinner, pointier
uniform float jitter : hint_range(0.0, 1.0) = 0.8;
uniform float height_variation : hint_range(0.0, 1.0) = 0.4;
uniform float pulse_speed = 2.0;
uniform float pulse_amount : hint_range(0.0, 0.9) = 0.4;

varying float tip;

vec2 hash2(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453);
}

// height of the spike field at a point on the surface plane
// returns vec3(height, dh/du, dh/dv) in world units; requires spike_width < 0.5
vec3 field(vec2 uv) {
  vec2 p = uv * spike_density;
  vec2 base = floor(p - spike_width);
  vec3 best = vec3(0.0);
  for (int y = 0; y < 2; y++) {
    for (int x = 0; x < 2; x++) {
      vec2 c = base + vec2(float(x), float(y));
      vec2 r = hash2(c);
      vec2 pt = c + 0.5 + (r - 0.5) * jitter;
      vec2 v = p - pt;
      float dist = length(v);
      if (dist >= spike_width) continue;   // skips the expensive math for most cells

      float k = 1.0 - dist / spike_width;
      float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed + r.x * 6.2831);
      float amp = pulse * (1.0 - height_variation * r.y) * spike_height;
      float h = pow(k, spike_sharpness) * amp;
      if (h > best.x) {
        vec2 g = -spike_sharpness * pow(k, spike_sharpness - 1.0) / spike_width
          * (v / max(dist, 1e-5)) * amp;
        best = vec3(h, g * spike_density);
      }
    }
  }
  return best;
}

void vertex() {
  vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
  vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
  vec3 an = abs(wn);

  vec3 a;
  vec3 b;
  if (an.y > an.x && an.y > an.z) {
    a = vec3(1.0, 0.0, 0.0);
    b = vec3(0.0, 0.0, 1.0);
  } else if (an.x > an.z) {
    a = vec3(0.0, 0.0, 1.0);
    b = vec3(0.0, 1.0, 0.0);
  } else {
    a = vec3(1.0, 0.0, 0.0);
    b = vec3(0.0, 1.0, 0.0);
  }
  vec2 uv = vec2(dot(wp, a), dot(wp, b));

  vec3 f = field(uv);
  VERTEX += NORMAL * f.x;
  NORMAL = normalize(wn - f.y * a - f.z * b);
  tip = clamp(f.x / spike_height, 0.0, 1.0);
}

void fragment() {
  ALBEDO = base_color.rgb;
  ROUGHNESS = 1.0;
  SPECULAR = 0.0;
  METALLIC = 0.0;

  float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
  float beat = 0.6 + 0.4 * sin(TIME * pulse_speed);
  EMISSION = glow_color.rgb * (fres * rim_strength * beat + tip * tip * tip_glow * beat);
}
