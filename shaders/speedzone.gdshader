shader_type spatial;
// Speed zone: orange translucent surface with chevron arrows streaming toward `direction`
// (default 2 right : 1 up, arrows point the same way). Pattern is in each face's UV space,
// so it needs UVs 0..1 per face (BoxMesh / QuadMesh defaults are fine).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

group_uniforms look;
uniform vec4 color : source_color = vec4(1.0, 0.5, 0.05, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.6;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.2;

group_uniforms arrows;
uniform vec2 direction = vec2(2.0, 1.0); // u (right), v (up) -- arrows point and move this way
uniform float columns = 3.0;             // arrows per UV unit along the direction
uniform float rows = 3.0;                // arrow rows across the direction
uniform float speed = 0.6;               // cycles per second
uniform float slope : hint_range(0.2, 1.5) = 0.8;   // arrowhead sweep-back
uniform float thickness : hint_range(0.02, 0.2) = 0.07;
uniform float arm_length : hint_range(0.1, 0.5) = 0.38;

group_uniforms frame;
uniform float border_width : hint_range(0.0, 0.2) = 0.03;
uniform float border_strength : hint_range(0.0, 4.0) = 1.5;
uniform float rim_strength : hint_range(0.0, 3.0) = 0.6;

float chevron(vec2 uv) {
  vec2 d = normalize(direction);
  vec2 perp = vec2(-d.y, d.x);
  vec2 p = vec2(dot(uv, d) * columns, dot(uv, perp) * rows);

  float row = floor(p.y);
  float fx = fract(p.x - TIME * speed + 0.5 * mod(row, 2.0)); // alternate rows offset
  float s = fx - 0.5;
  float py = fract(p.y) - 0.5;

  // V shape: tip at py = 0, arms sweep back toward -x
  float dist = abs(s + abs(py) * slope);
  float aa = fwidth(dist) + 0.002;
  float m = 1.0 - smoothstep(thickness, thickness + aa + 0.02, dist);
  m *= 1.0 - smoothstep(arm_length - 0.05, arm_length, abs(py));
  return m;
}

void fragment() {
  float arrows = chevron(UV);

  vec2 e = min(UV, 1.0 - UV);
  float border = 1.0 - smoothstep(0.0, max(border_width, 0.0001), min(e.x, e.y));

  float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
  float pulse = 1.0 - pulse_amount * (0.5 + 0.5 * sin(TIME * 3.0));

  float glow = base_alpha + arrows * 1.5 + border * border_strength + fres * rim_strength;
  ALBEDO = color.rgb * glow * intensity * pulse;
  ALPHA = 1.0;
}
