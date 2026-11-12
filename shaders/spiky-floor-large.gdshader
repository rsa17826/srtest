shader_type spatial;
render_mode specular_disabled;

// One big flat quad instead of many tiles.
//
// The old shader displaced vertices, which needs a dense mesh (this spike size would want
// hundreds of vertices per square unit). This one keeps the quad at 4 vertices and ray-marches
// the spike field per pixel instead, writing the real depth so spikes still occlude, intersect
// and get lit like geometry.
//
// Requirements for the MeshInstance3D using it:
//  - a flat, upward facing quad (PlaneMesh, no subdivisions needed), position = floor level
//  - rotation 0 and scale.y = 1 (x/z scale or the mesh size can be anything)
//  - cast_shadow = off (the quad is flat, so spikes can't cast shadows; they still receive them)

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

uniform int max_steps : hint_range(16, 256) = 96;  // upper bound on coarse steps; step size adapts to the view angle
uniform int refine_steps : hint_range(0, 8) = 5;   // bisection steps after the coarse hit

vec2 hash2(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453);
}

// identical to the tiled shader: returns vec3(height, dh/dx, dh/dz) at a point on the floor plane
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
      if (dist >= spike_width) continue;

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
  // lift the quad to the top of the spike volume; the fragment shader marches down from here
  VERTEX.y += spike_height;
}

void fragment() {
  vec3 top_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
  vec3 dir = normalize(top_pos - CAMERA_POSITION_WORLD);
  float base_y = top_pos.y - spike_height;

  // distance along the ray from the top plane down to the floor plane
  float t_end = spike_height / max(-dir.y, 1e-3);

  // step size: at least 8 steps through the spike height, and never more than a quarter of a spike's
  // base radius sideways. a fixed step count skips whole spikes at shallow view angles, which turns
  // the field into scattered dots.
  float horiz = max(length(dir.xz), 1e-3);
  float cone_r = spike_width / spike_density;
  // the floor on max_steps makes the march always reach the floor plane. without it, far away rays (long
  // shallow paths through the volume) ran out of steps near the tops of the spikes and only the glowing
  // tips were ever found, which is the distant dots.
  float dt = max(min(t_end / 8.0, 0.25 * cone_r / horiz), t_end / float(max_steps));

  // coarse search for the first point at or below the spike surface; reaching t_end means the floor
  float lo = 0.0;
  float hi = t_end;
  for (int i = 1; i <= max_steps; i++) {
    float t = dt * float(i);
    if (t >= t_end) break;
    vec3 p = top_pos + dir * t;
    if (p.y - base_y <= field(p.xz).x) {
      hi = t;
      break;
    }
    lo = t;
  }

  for (int i = 0; i < refine_steps; i++) {
    float mid = 0.5 * (lo + hi);
    vec3 p = top_pos + dir * mid;
    if (p.y - base_y <= field(p.xz).x) {
      hi = mid;
    } else {
      lo = mid;
    }
  }

  vec3 hit = top_pos + dir * hi;
  vec3 f = field(hit.xz);
  vec3 n_world = normalize(vec3(-f.y, 1.0, -f.z));
  float tip = clamp(f.x / spike_height, 0.0, 1.0);

  vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(hit, 1.0));
  DEPTH = clip.z / clip.w;
  NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

  ALBEDO = base_color.rgb;
  ROUGHNESS = 1.0;
  SPECULAR = 0.0;
  METALLIC = 0.0;

  float fres = pow(1.0 - clamp(dot(NORMAL, normalize(VIEW)), 0.0, 1.0), rim_power);
  float beat = 0.6 + 0.4 * sin(TIME * pulse_speed);
  EMISSION = glow_color.rgb * (fres * rim_strength * beat + tip * tip * tip_glow * beat);
}
