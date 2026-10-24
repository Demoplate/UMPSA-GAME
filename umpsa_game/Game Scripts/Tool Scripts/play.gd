extends Area2D

@export_file("*.tscn") var target_scene_path: String = "res://Level_Scenes/lvl1.tscn"
@export var build_area_path: NodePath = NodePath("../BuildingArea")
@export var warning_label_path: NodePath = NodePath("../CanvasLayer/UIRoot/WarningLabel")

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
			elif "piston" in current_path.to_lower():
				var rigid_piston_path = current_path.replace("cloned_parts", "rigid_blocks").replace("piston.tscn", "rigid_piston.tscn")
				GameData.saved_parts.append({
					"type": "piston",
					"scene_path": rigid_piston_path,
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
	
	# Check if a command block was actually placed
	var has_command_block = false
	for part in GameData.saved_parts:
		if part["type"] == "command":
			has_command_block = true
			break
			
	var warning_label = get_node_or_null(warning_label_path)
	
	if not has_command_block:
		print("[BUILD] Cannot start: No command block placed!")
		if warning_label:
			warning_label.text = "You must place a Command Block to play!"
			warning_label.modulate.a = 1.0 # Ensure it's fully opaque
			warning_label.visible = true
			
			# Create a smooth fade-out effect after 2 seconds
			var fade_tween = create_tween()
			fade_tween.tween_interval(2.0) # Stay visible for 2 seconds
			fade_tween.tween_property(warning_label, "modulate:a", 0.0, 1.0) # Fade alpha to 0 over 1 second
			fade_tween.tween_callback(func(): warning_label.visible = false) # Hide completely when done
		return
		
	# Hide warning label if check passes and switch scene
	if warning_label:
		warning_label.visible = false
		
	print("Saved ", GameData.saved_parts.size(), " parts! Switching scenes...")
	get_tree().change_scene_to_file(target_scene_path)
