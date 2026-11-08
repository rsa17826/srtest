shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.1, 0.05, 0.15, 1.0);
uniform float width : hint_range(0.0, 0.1) = 0.02;

void vertex() {
  VERTEX += NORMAL * width;
}

void fragment() {
  ALBEDO = outline_color.rgb;
}
