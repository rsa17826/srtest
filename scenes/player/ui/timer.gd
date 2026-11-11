extends Label

func _process(_delta):
  var time: float = global.player.tickCount * 1 / 60.0
  var minutes: float = time / 60
  var seconds: float = fmod(time, 60)
  var milliseconds: float = fmod(time, 1) * 100
  text = "%02d:%02d:%02d" % [minutes, seconds, milliseconds]
