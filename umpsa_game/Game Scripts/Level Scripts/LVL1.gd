extends Node2D

@export var grid_size: float = 16.0

# Dictionary to hold lists of individual thruster data grouped by key
var thruster_groups = {}
# Dictionary to track which keys are currently being held down on mobile
var active_thruster_keys = {}
# Array to store active thruster visual indicators for the current frame
var active_thrust_indicators = []

var canvas_layer: CanvasLayer

func _ready():
	if GameData.saved_parts.is_empty():
		return
		
	# Setup UI Canvas Layer for mobile buttons dynamically if it doesn't exist
	canvas_layer = get_node_or_null("CanvasLayer")
	if not canvas_layer:
		canvas_layer = CanvasLayer.new()
		canvas_layer.name = "CanvasLayer"
		add_child(canvas_layer)
		
		var vbox = VBoxContainer.new()
		vbox.name = "ButtonContainer"
		vbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		vbox.offset_left = -120
		vbox.offset_top = -200
		canvas_layer.add_child(vbox)

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
		
		# Apply custom physics material override for chassis friction
		var chassis_mat = PhysicsMaterial.new()
		chassis_mat.friction = 0.4
		master_body.physics_material_override = chassis_mat
		
		for inst in island:
			var p_data = data_to_node[inst]
			var is_wheel = (p_data.get("type") == "wheel")
			var is_thruster = (p_data.get("type") == "thruster")
			
			if not is_wheel:
				var duplicated_particles = null
				
				for child in inst.get_children():
					if child is CollisionShape2D or child is Sprite2D or child is RayCast2D or child is CPUParticles2D:
						var global_pos = child.global_position
						var global_rot = child.global_rotation
						
						var dup = child.duplicate()
						master_body.add_child(dup)
						dup.global_position = global_pos
						dup.global_rotation = global_rot
						dup.position = master_body.to_local(global_pos)
						
						# Capture reference to the duplicated CPU particles node
						if is_thruster and dup is CPUParticles2D:
							duplicated_particles = dup
				
				# Track thrusters with live references to the duplicated particles on the master body
				if is_thruster:
					var assigned_key = p_data.get("assigned_key", "")
					if assigned_key != "":
						if not thruster_groups.has(assigned_key):
							thruster_groups[assigned_key] = []
							active_thruster_keys[assigned_key] = false
							_create_ui_button(assigned_key)
						
						thruster_groups[assigned_key].append({
							"body": master_body,
							"local_pos": master_body.to_local(inst.global_position),
							"local_rot": inst.global_rotation - master_body.global_rotation,
							"particles": duplicated_particles
						})
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
					
					# Apply higher friction material for wheel traction
					var wheel_mat = PhysicsMaterial.new()
					wheel_mat.friction = 0.8
					rolling_body.physics_material_override = wheel_mat
					
					if pin_joint:
						var new_pin = pin_joint.duplicate()
						get_tree().current_scene.add_child(new_pin)
						new_pin.global_position = pin_joint.global_position
						new_pin.node_a = master_body.get_path()
						new_pin.node_b = rolling_body.get_path()
						new_pin.disable_collision = true

	for inst in part_nodes:
		inst.queue_free()

	print("Vehicle built successfully with safe CPU particle tracking!")
	GameData.saved_parts.clear()

func _physics_process(_delta: float):
	active_thrust_indicators.clear()
	
	# Continuously apply force and toggle CPU particles every frame while a button is held down
	for key in active_thruster_keys.keys():
		var is_key_pressed = active_thruster_keys[key]
		if thruster_groups.has(key):
			for t_data in thruster_groups[key]:
				var body: RigidBody2D = t_data["body"]
				var particles: CPUParticles2D = t_data.get("particles")
				
				if is_instance_valid(body):
					if is_key_pressed:
						var local_pos = t_data["local_pos"]
						var local_rot = t_data["local_rot"]
						
						# Rotate local position offset by current body rotation so application point updates live
						var rotated_local_pos = local_pos.rotated(body.global_rotation)
						var current_global_pos = body.global_position + rotated_local_pos
						
						# Dynamically compute current global rotation of the thruster
						var current_global_rot = body.global_rotation + local_rot
						var direction = Vector2.UP.rotated(current_global_rot)
						var force = direction * 2000.0 # Adjust thrust strength here
						
						# Apply force at the dynamically rotated local position offset
						body.apply_force(force, rotated_local_pos)
						
						# Safely turn CPU particles on if valid
						if is_instance_valid(particles):
							particles.emitting = true
						
						# Record visual indicator data for drawing the arrow
						active_thrust_indicators.append({
							"pos": current_global_pos,
							"dir": direction
						})
					else:
						# Safely turn CPU particles off when released
						if is_instance_valid(particles):
							particles.emitting = false
	
	queue_redraw()

func _create_ui_button(key: String):
	var container = canvas_layer.get_node_or_null("ButtonContainer")
	if not container:
		return
		
	var btn = Button.new()
	btn.text =  key
	btn.custom_minimum_size = Vector2(100, 50)
	container.add_child(btn)
	
	btn.button_down.connect(func():
		active_thruster_keys[key] = true
	)
	
	btn.button_up.connect(func():
		active_thruster_keys[key] = false
	)

func _find_part_instance_from_collider(collider: Object, part_nodes: Array) -> Node:
	var curr = collider
	while curr and curr is Node:
		if curr in part_nodes:
			return curr
		curr = curr.get_parent()
	return null
