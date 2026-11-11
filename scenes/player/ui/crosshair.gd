extends Control
class_name Crosshair
# Put this on a Control under a CanvasLayer in the level (it fills the screen and draws at its centre).
# System-window styling: four ticks with a glow, a centre dot, and a ring that fills while the grenade recharges.
# The ticks spread out with the player's horizontal speed. Hidden while the replay viewer is open.

@export var blueColor := Color(0.25, 0.85, 1.0)
@export var redColor := Color(0.85, 0.05, 1.0)
@export var base_gap := 5.0 # distance of the ticks from the centre when standing still
@export var spread := 9.0 # extra gap at full speed
@export var full_speed := 25.0 # horizontal speed that counts as "full"
@export var tick_length := 9.0
@export var thickness := 2.0
@export var cooldown_ticks := 30 # same as the check in Player.step()
@export var ring_radius := 18.0

var player: Player
var gap := 0.0

func _ready() -> void:
  player = global.player
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  gap = base_gap

func _process(delta: float) -> void:
  visible = player.current_mode != Player.ReplayMode.VIEWING
  if not visible: return
  var speed := Vector2(player.velocity.x, player.velocity.z).length()
  gap = lerpf(gap, base_gap + clampf(speed / full_speed, 0.0, 1.0) * spread, 1.0 - exp(-14.0 * delta))
  queue_redraw()

func _draw() -> void:
  var c := size * 0.5
  var white := Color(0.9, 0.99, 1.0)
  var color = blueColor if player.canUseGrenade else redColor

  # four ticks: soft glow, cyan body, white core
  for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
    var a := c + dir * gap
    var b := c + dir * (gap + tick_length)
    draw_line(a, b, Color(color, 0.18), thickness + 6.0)
    draw_line(a, b, Color(color, 0.5), thickness + 2.0)
    draw_line(a, b, white, thickness)

  # centre dot
  draw_circle(c, 3.5, Color(color, 0.3))
  draw_circle(c, 1.6, white)

  # grenade recharge ring
  var since := player.tickCount - player.lastGrenadeTick
  if since < cooldown_ticks:
    var progress := clampf(float(since) / cooldown_ticks, 0.0, 1.0)
    draw_arc(c, ring_radius, -PI * 0.5, -PI * 0.5 + TAU, 48, Color(color, 0.15), 1.5)
    draw_arc(c, ring_radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, Color(white, 0.9), 2.0)
