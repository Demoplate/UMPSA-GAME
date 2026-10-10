extends Node2D

func _ready():
	if GameData.saved_parts.is_empty():
		return
		
	# 1. Calculate the center point of all placed parts combined
	var center_pos = Vector2.ZERO
	for part_data in GameData.saved_parts:
		center_pos += part_data["global_position"]
	center_pos /= GameData.saved_parts.size()
	
	# 2. Spawn ONE master RigidBody2D for the entire structure
	var master_body = RigidBody2D.new()
	get_tree().current_scene.add_child(master_body)
	master_body.global_position = center_pos
	
	# 3. Pull the collision shapes and sprites from each block and attach them to the master body
	for part_data in GameData.saved_parts:
		var scene = load(part_data["scene_path"])
		if scene:
			var block_instance = scene.instantiate()
			
			# Extract Sprite2D and CollisionShape2D from the block scene
			for child in block_instance.get_children():
				if child is CollisionShape2D or child is Sprite2D:
					var dup = child.duplicate()
					master_body.add_child(dup)
					
					# Position them accurately relative to the new master body center
					dup.global_position = part_data["global_position"] + child.position.rotated(part_data["rotation"])
					dup.rotation = part_data["rotation"] + child.rotation
					
					# Convert to local coordinates of the master body
					dup.position = master_body.to_local(dup.global_position)
			
			block_instance.queue_free()
			
	print("Spawned structure as a single solid RigidBody2D with zero wobble!")
	GameData.saved_parts.clear()
