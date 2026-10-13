extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var reports: Array[Dictionary] = []
	var issues := PackedStringArray()
	for asset: String in ["thief_robot", "healer_robot"]:
		var packed := load("res://assets/models/" + asset + ".glb") as PackedScene
		if packed == null:
			issues.append("Cannot load imported scene " + asset)
			continue
		var model := packed.instantiate() as Node3D
		root.add_child(model)
		await process_frame
		var skeleton := _find(model, "Skeleton3D") as Skeleton3D
		var player := _find(model, "AnimationPlayer") as AnimationPlayer
		var mesh := _find(model, "MeshInstance3D") as MeshInstance3D
		if skeleton == null or player == null or mesh == null or mesh.skin == null:
			issues.append("Missing actual skeleton/animation/skin " + asset)
			model.free()
			continue
		var clips: Dictionary = {}
		for clip: StringName in player.get_animation_list():
			if clip == &"RESET":
				continue
			var animation := player.get_animation(clip)
			animation.loop_mode = Animation.LOOP_NONE
			var samples: Array[Dictionary] = []
			for fraction: float in [0.0, .25, .5, .75, 1.0]:
				player.play(clip)
				player.seek(animation.length * fraction, true)
				player.advance(0)
				skeleton.force_update_all_bone_transforms()
				var sample: Dictionary = {"time": animation.length * fraction}
				for bone: String in ["Foot_L", "Foot_R", "Shin_L", "Shin_R", "Hand_L", "Hand_R"]:
					var index := skeleton.find_bone(bone)
					if index < 0:
						issues.append("Missing bone " + bone)
						continue
					var position := skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
					sample[bone] = [position.x, position.y, position.z]
				samples.append(sample)
			if clip == &"Walk":
				if absf(float(samples[0]["Foot_L"][2]) - float(samples[2]["Foot_L"][2])) < .60 or absf(float(samples[1]["Foot_R"][1]) - float(samples[0]["Foot_R"][1])) < .12:
					issues.append("Actual Godot leg motion is not articulated " + asset)
			if clip == &"SelfHeal" and absf(float(samples[2]["Hand_L"][1]) - float(samples[0]["Hand_L"][1])) < .30:
				issues.append("Actual Godot repair wrist does not reach chest")
			clips[str(clip)] = {"duration": animation.length, "tracks": animation.get_track_count(), "samples": samples}
		if skeleton.get_bone_count() != 17 or mesh.skin.get_bind_count() != 17 or mesh.mesh.get_surface_count() != 1:
			issues.append("Actual Godot skin submission contract differs " + asset)
		reports.append({"id": asset, "bones": skeleton.get_bone_count(), "binds": mesh.skin.get_bind_count(), "surfaces": mesh.mesh.get_surface_count(), "clips": clips})
		model.free()
	var report := {"engine": Engine.get_version_info().string, "scope": "headless actual imported skeleton/animation; renderer and gameplay review separate", "assets": reports, "issues": issues, "ok": issues.is_empty()}
	var file := FileAccess.open("res://../source-assets/evidence/character-godot-import.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify({"imported": reports.size(), "issues": issues, "ok": issues.is_empty()}))
	quit(0 if issues.is_empty() else 1)

func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child: Node in node.get_children():
		var result := _find(child, type)
		if result != null:
			return result
	return null
