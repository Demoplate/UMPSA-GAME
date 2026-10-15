extends Area2D

@export var target_scene_path: String = "res://lvl1.tscn"
@export var build_area_path: NodePath = NodePath("../BuildingArea")

func _input_event(_viewport, event, _shape_idx):
	if (event is InputEventScreenTouch and event.pressed) or \
	   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		transition_to_new_scene()

func transition_to_new_scene():
	GameData.saved_parts.clear()
	
	var build_area = get_node_or_null(build_area_path)
	if not build_area:
		print("ERROR: Couldn't find BuildingArea node!")
		return
		
	for area in build_area.get_overlapping_areas():
		if area.name != "BuildingArea" and not area.is_dragging:
			var current_path = area.scene_file_path
			
			# Swap folder from cloned_parts to rigid_blocks and match the rigid filename
			if "wheel" in current_path.to_lower():
				var rigid_wheel_path = current_path.replace("cloned_parts", "rigid_blocks").replace("wheel.tscn", "rigid_wheel.tscn")
				GameData.saved_parts.append({
					"type": "wheel",
					"scene_path": rigid_wheel_path,
					"global_position": area.global_position,
					"rotation": area.global_rotation
				})
			elif "thruster" in current_path.to_lower():
				var rigid_thruster_path = current_path.replace("cloned_parts", "rigid_blocks").replace("thruster.tscn", "rigid_thruster.tscn")
				
				# Safely grab the assigned key from the cloned thruster instance if it exists
				var key_assigned = ""
				if "assigned_key" in area:
					key_assigned = area.assigned_key
				
				GameData.saved_parts.append({
					"type": "thruster",
					"scene_path": rigid_thruster_path,
					"global_position": area.global_position,
					"rotation": area.global_rotation,
					"assigned_key": key_assigned
				})
			else:
				var rigid_block_path = current_path.replace("cloned_parts", "rigid_blocks").replace("block.tscn", "rigid_block.tscn")
				GameData.saved_parts.append({
					"type": "block",
					"scene_path": rigid_block_path,
					"global_position": area.global_position,
					"rotation": area.global_rotation
				})
			
	print("Saved ", GameData.saved_parts.size(), " parts! Switching scenes...")
	get_tree().change_scene_to_file(target_scene_path)
