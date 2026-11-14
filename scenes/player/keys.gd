extends Label

func _process(_delta: float) -> void:
  text = "keys: %s/%s" % [global.player.keysCollected, global.level.totalKeys]
