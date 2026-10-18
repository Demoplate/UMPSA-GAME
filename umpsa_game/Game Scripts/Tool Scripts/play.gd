extends Area2D

@export var target_scene_path: String = "res://Level_Scenes/lvl1.tscn"
@export var build_area_path: NodePath = NodePath("../BuildingArea")

func _input_event(_viewport, event, _shape_idx):
	if (event is InputEventScreenTouch and event.pressed) or \
	   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		transition_to_new_scene()

func transition_to_new_scene():
	# Ensure tool is set appropriately before transitioning
	if "current_tool" in GameData and "ToolMode" in GameData:
		GameData.current_tool = GameData.ToolMode.SPAWN

	GameData.saved_parts.clear()
	
	var build_area = get_node_or_null(build_area_path)
	if not build_area:
		print("ERROR: Couldn't find BuildingArea node!")
		return
		
	for area in build_area.get_overlapping_areas():
		if area.name != "BuildingArea" and not area.is_dragging:
			var current_path = area.scene_file_path
			
			# Grab assigned keys if the part has them
			var key_assigned = ""
			if "assigned_key" in area:
				key_assigned = area.assigned_key
				
			var rev_key_assigned = ""
			if "reverse_key" in area:
				rev_key_assigned = area.reverse_key
			
			if "wheel" in current_path.to_lower():
				var rigid_wheel_path = current_path.replace("cloned_parts", "rigid_blocks").replace("wheel.tscn", "rigid_wheel.tscn")
				GameData.saved_parts.append({
					"type": "wheel",
					"scene_path": rigid_wheel_path,
					"global_position": area.global_position,
					"rotation": area.global_rotation,
					"assigned_key": key_assigned,
					"reverse_key": rev_key_assigned
				})
			elif "thruster" in current_path.to_lower():
				var rigid_thruster_path = current_path.replace("cloned_parts", "rigid_blocks").replace("thruster.tscn", "rigid_thruster.tscn")
				GameData.saved_parts.append({
					"type": "thruster",
					"scene_path": rigid_thruster_path,
					"global_position": area.global_position,
					"rotation": area.global_rotation,
					"assigned_key": key_assigned
				})
			elif "watergun" in current_path.to_lower():
				var rigid_watergun_path = current_path.replace("cloned_parts", "rigid_blocks").replace("watergun.tscn", "rigid_watergun.tscn")
				GameData.saved_parts.append({
					"type": "watergun",
					"scene_path": rigid_watergun_path,
					"global_position": area.global_position,
					"rotation": area.global_rotation,
					"assigned_key": key_assigned
				})
			elif "command" in current_path.to_lower():
				var rigid_command_path = current_path.replace("cloned_parts", "rigid_blocks").replace("command.tscn", "rigid_command.tscn")
				GameData.saved_parts.append({
					"type": "command",
					"scene_path": rigid_command_path,
					"global_position": area.global_position,
					"rotation": area.global_rotation
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
