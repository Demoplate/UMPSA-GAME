extends Node2D

@export var grid_size: float = 16.0

func _ready():
	if GameData.saved_parts.is_empty():
		return
		
	var block_data_list = []
	var wheel_data_list = []
	
	for part in GameData.saved_parts:
		if part.get("type") == "wheel":
			wheel_data_list.append(part)
		else:
			block_data_list.append(part)
			
	# 1. Group connected blocks into islands using scene RayCasts and spawn the RigidBody2D chassis
	var islands = await _find_block_islands_with_scene_raycasts(block_data_list)
	var created_bodies = []
	
	for island in islands:
		var center_pos = Vector2.ZERO
		for b in island:
			center_pos += b["global_position"]
		center_pos /= island.size()
		
		var master_body = RigidBody2D.new()
		get_tree().current_scene.add_child(master_body)
		master_body.global_position = center_pos
		created_bodies.append(master_body)
		
		for b in island:
			var scene = load(b["scene_path"])
			if scene:
				var instance = scene.instantiate()
				for child in instance.get_children():
					if child is CollisionShape2D or child is Sprite2D:
						var dup = child.duplicate()
						master_body.add_child(dup)
						dup.global_position = b["global_position"] + child.position.rotated(b["rotation"])
						dup.rotation = b["rotation"] + child.rotation
						dup.position = master_body.to_local(dup.global_position)
				instance.queue_free()

	# Give physics a frame to register the new chassis bodies in space
	await get_tree().physics_frame

	# 2. Spawn wheels and use their internal RayCast2D nodes to detect and attach to nearby chassis bodies
	for w in wheel_data_list:
		var wheel_scene = load(w["scene_path"])
		if wheel_scene:
			var wheel_body = wheel_scene.instantiate()
			get_tree().current_scene.add_child(wheel_body)
			wheel_body.global_position = w["global_position"]
			wheel_body.rotation = w["rotation"]
			
			# Check wheel's raycasts to see if they hit any of our created chassis bodies
			var attached_body = null
			for child in wheel_body.get_children():
				if child is RayCast2D:
					child.add_exception(wheel_body) # Prevent self-collision with wheel itself
					child.force_raycast_update()
					if child.is_colliding():
						var collider = child.get_collider()
						var hit_body = _find_body_from_collider(collider, created_bodies)
						if hit_body:
							attached_body = hit_body
							break
			
			# If a wheel raycast successfully touched a chassis body, link them via PinJoint2D!
			if attached_body:
				var hinge = PinJoint2D.new()
				get_tree().current_scene.add_child(hinge)
				hinge.global_position = w["global_position"]
				hinge.node_a = attached_body.get_path()
				hinge.node_b = wheel_body.get_path()
				hinge.disable_collision = true
			else:
				print("Wheel raycasts hit nothing—left independent!")
				
	print("Vehicle and wheels spawned successfully using native RayCasts!")
	GameData.saved_parts.clear()

# Helper: Traces a collider up the parent tree to check if it belongs to a chassis body
func _find_body_from_collider(collider: Object, bodies: Array) -> RigidBody2D:
	var curr = collider
	while curr and curr is Node:
		if curr in bodies:
			return curr
		curr = curr.get_parent()
	return null

# Helper: Uses block scene RayCasts with self-collision ignored
func _find_block_islands_with_scene_raycasts(blocks: Array) -> Array:
	var block_nodes = []
	var block_to_data = {}
	
	for b in blocks:
		var scene = load(b["scene_path"])
		if scene:
			var instance = scene.instantiate()
			get_tree().current_scene.add_child(instance)
			instance.global_position = b["global_position"]
			instance.rotation = b["rotation"]
			block_nodes.append(instance)
			block_to_data[instance] = b

	await get_tree().physics_frame

	var unvisited = block_nodes.duplicate()
	var islands = []

	while not unvisited.is_empty():
		var current_island_nodes = []
		var queue = [unvisited.pop_front()]
		current_island_nodes.append(queue[0])

		while not queue.is_empty():
			var current_node = queue.pop_front()
			
			for child in current_node.get_children():
				if child is RayCast2D:
					child.add_exception(current_node)
					child.force_raycast_update()
					
					if child.is_colliding():
						var collider = child.get_collider()
						if collider:
							var hit_block = _find_block_node_from_collider(collider, block_nodes)
							if hit_block and hit_block in unvisited and hit_block != current_node:
								current_island_nodes.append(hit_block)
								queue.append(hit_block)
								unvisited.erase(hit_block)

		islands.append(current_island_nodes)

	var final_islands = []
	for node_island in islands:
		var data_island = []
		for node in node_island:
			if block_to_data.has(node):
				data_island.append(block_to_data[node])
		final_islands.append(data_island)

	for node in block_nodes:
		node.queue_free()

	return final_islands

# Helper: Traces a collider to find which block node it belongs to
func _find_block_node_from_collider(collider: Object, block_nodes: Array) -> Node:
	var curr = collider
	while curr and curr is Node:
		if curr in block_nodes:
			return curr
		curr = curr.get_parent()
	return null
