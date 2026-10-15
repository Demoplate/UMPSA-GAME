extends Node2D

@export var grid_size: float = 16.0

func _ready():
	if GameData.saved_parts.is_empty():
		return
		
	var all_parts = GameData.saved_parts
	var part_nodes = []
	var data_to_node = {}
	var node_to_scan = {}
	
	# 1. Instantiate all saved parts temporarily
	for p in all_parts:
		var scene = load(p["scene_path"])
		if scene:
			var instance = scene.instantiate()
			get_tree().current_scene.add_child(instance)
			instance.global_position = p["global_position"]
			instance.rotation = p["rotation"]
			
			part_nodes.append(instance)
			data_to_node[instance] = p
			node_to_scan[instance] = instance

	await get_tree().physics_frame
	await get_tree().physics_frame

	# 2. Group parts into islands where every part starts in its own individual island
	var islands = []
	var part_to_island = {}
	
	for node in part_nodes:
		var island = [node]
		islands.append(island)
		part_to_island[node] = island

	# Force raycasts to update and merge islands dynamically with connection rules
	for curr_instance in part_nodes:
		var scan_node = node_to_scan[curr_instance]
		var p_data = data_to_node[curr_instance]
		var scene_path = p_data.get("scene_path", "").to_lower()
		
		var raycasts = []
		if scan_node is Node:
			for child in scan_node.find_children("*", "RayCast2D", true, false):
				raycasts.append(child)
		
		# Rule 1: Thrusters only connect if Raycast2D_Top is used
		if "thruster" in scene_path:
			raycasts = raycasts.filter(func(rc): return rc.name == "Raycast2D_Top")
		
		var colliding_rcs = []
		for rc in raycasts:
			rc.collision_mask = 2
			rc.add_exception(curr_instance)
			rc.force_raycast_update()
			
			if rc.is_colliding():
				colliding_rcs.append(rc)
		
		# Rule 2: Wheels don't connect if the bottom is the ONLY place connected
		if "wheel" in scene_path:
			var has_bottom = false
			var has_others = false
			for rc in colliding_rcs:
				if rc.name == "Raycast2D_Bottom":
					has_bottom = true
				else:
					has_others = true
			
			if has_bottom and not has_others:
				colliding_rcs.clear()
		
		for rc in colliding_rcs:
			var collider = rc.get_collider()
			var hit_instance = _find_part_instance_from_collider(collider, part_nodes)
			
			if hit_instance and hit_instance != curr_instance:
				var island_a = part_to_island[curr_instance]
				var island_b = part_to_island[hit_instance]
				
				# If they are in different islands, merge them together!
				if island_a != island_b:
					print("[MERGE] Connecting part at ", curr_instance.global_position, " with part at ", hit_instance.global_position)
					for node in island_b:
						island_a.append(node)
						part_to_island[node] = island_a
					islands.erase(island_b)

	print("\n--- FINAL ISLAND COUNT AFTER MERGING: ", islands.size(), " ---\n")

	# 3. Build unified RigidBody2D chassis islands
	for island in islands:
		var center_pos = Vector2.ZERO
		for inst in island:
			center_pos += inst.global_position
		center_pos /= island.size()
		
		var master_body = RigidBody2D.new()
		get_tree().current_scene.add_child(master_body)
		master_body.global_position = center_pos
		
		for inst in island:
			var p_data = data_to_node[inst]
			var is_wheel = (p_data.get("type") == "wheel")
			
			if not is_wheel:
				for child in inst.get_children():
					if child is CollisionShape2D or child is Sprite2D or child is RayCast2D:
						var global_pos = child.global_position
						var global_rot = child.global_rotation
						
						var dup = child.duplicate()
						master_body.add_child(dup)
						dup.global_position = global_pos
						dup.global_rotation = global_rot
						dup.position = master_body.to_local(global_pos)
			else:
				for child in inst.get_children():
					if child is RayCast2D or child.name == "WheelRolling" or child is PinJoint2D:
						continue
					if child is CollisionShape2D or child is Sprite2D or child is Node2D:
						var global_pos = child.global_position
						var global_rot = child.global_rotation
						
						var dup = child.duplicate()
						master_body.add_child(dup)
						dup.global_position = global_pos
						dup.global_rotation = global_rot
						dup.position = master_body.to_local(global_pos)
				
				var wheel_rolling = inst.get_node_or_null("WheelRolling")
				var pin_joint = inst.get_node_or_null("PinJoint2D")
				
				if wheel_rolling:
					var rolling_body = wheel_rolling.duplicate()
					get_tree().current_scene.add_child(rolling_body)
					rolling_body.global_position = wheel_rolling.global_position
					rolling_body.rotation = wheel_rolling.global_rotation
					
					if pin_joint:
						var new_pin = pin_joint.duplicate()
						get_tree().current_scene.add_child(new_pin)
						new_pin.global_position = pin_joint.global_position
						new_pin.node_a = master_body.get_path()
						new_pin.node_b = rolling_body.get_path()
						new_pin.disable_collision = true

	for inst in part_nodes:
		inst.queue_free()

	print("Vehicle built successfully with dynamic island merging!")
	GameData.saved_parts.clear()

func _find_part_instance_from_collider(collider: Object, part_nodes: Array) -> Node:
	var curr = collider
	while curr and curr is Node:
		if curr in part_nodes:
			return curr
		curr = curr.get_parent()
	return null
