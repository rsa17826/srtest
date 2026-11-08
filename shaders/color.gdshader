shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.1, 0.05, 0.15, 1.0);

void vertex() {
}

void fragment() {
  ALBEDO = outline_color.rgb;
}
