extends Node3D

@onready var pane: MeshInstance3D = $Pane

func collect() -> void:
  create_tween().tween_method(
    func(v: float) -> void: pane.set_instance_shader_parameter("collected", v),
    0.0, 1.0, 0.8)

func reset() -> void:
  pane.set_instance_shader_parameter("collected", 0.0)
