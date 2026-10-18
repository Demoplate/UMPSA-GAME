extends Node2D

func _ready() -> void:
	if GameData.saved_parts.is_empty():
		return

	var parts: Array = GameData.saved_parts.duplicate()
	GameData.saved_parts.clear()

	for p in parts:
		var rigid_path: String = p["scene_path"]
		var interactive_path: String

		if "wheel" in rigid_path.to_lower():
			interactive_path = rigid_path.replace("rigid_blocks", "cloned_parts").replace("rigid_wheel.tscn", "wheel.tscn")
		elif "thruster" in rigid_path.to_lower():
			interactive_path = rigid_path.replace("rigid_blocks", "cloned_parts").replace("rigid_thruster.tscn", "thruster.tscn")
		elif "watergun" in rigid_path.to_lower():
			interactive_path = rigid_path.replace("rigid_blocks", "cloned_parts").replace("rigid_watergun.tscn", "watergun.tscn")
		else:
			interactive_path = rigid_path.replace("rigid_blocks", "cloned_parts").replace("rigid_block.tscn", "block.tscn")

		var scene := load(interactive_path) as PackedScene
		if scene == null:
			print("FAILED to load scene at: ", interactive_path)
			continue

		var instance := scene.instantiate() as Node2D
		for child in instance.find_children("*", "CollisionShape2D", true, false):
			child.disabled = true

		get_tree().current_scene.add_child(instance)
		instance.top_level = true
		instance.global_position = p["global_position"]
		instance.rotation = p["rotation"]

		if "is_dragging" in instance:
			instance.is_dragging = false
		if "assigned_key" in instance and p.has("assigned_key"):
			instance.assigned_key = p["assigned_key"]
		if "reverse_key" in instance and p.has("reverse_key"):
			instance.reverse_key = p["reverse_key"]

		await get_tree().process_frame

		if is_instance_valid(instance):
			for child in instance.find_children("*", "CollisionShape2D", true, false):
				child.disabled = false
