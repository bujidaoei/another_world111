extends SceneTree

func _initialize() -> void:
	var output: Dictionary = {}
	for id: String in ["thief", "healer"]:
		var model := (load("res://assets/models/" + id + "_robot.glb") as PackedScene).instantiate()
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var clips: Dictionary = {}
		for clip: String in player.get_animation_list():
			var animation := player.get_animation(clip)
			var tracks: Array = []
			for index: int in range(animation.get_track_count()):
				tracks.append({"path": str(animation.track_get_path(index)), "type": animation.track_get_type(index), "keys": animation.track_get_key_count(index)})
			clips[clip] = tracks
		output[id] = clips
		model.free()
	var file := FileAccess.open("res://../source-assets/evidence/character-native-tracks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	quit(0)
