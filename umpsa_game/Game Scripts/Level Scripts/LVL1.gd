extends Node2D

@export var grid_size: float = 16.0
@export var thruster_power: float = 2000.0
@export var wheel_power: float = 20000.0

# Unified dictionaries for key inputs and groups
var active_keys = {}
var thruster_groups = {}
var wheel_forward_groups = {}
var wheel_reverse_groups = {}

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
			var is_wheel = (p_data.get("type") == "wheel") or ("wheel" in p_data.get("scene_path", "").to_lower())
			var is_thruster = (p_data.get("type") == "thruster") or ("thruster" in p_data.get("scene_path", "").to_lower())
			
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
				
				# Track thrusters using the shared UI system
				if is_thruster:
					var assigned_key = p_data.get("assigned_key", "")
					if assigned_key != "":
						if not thruster_groups.has(assigned_key):
							thruster_groups[assigned_key] = []
						
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
					
					# Track forward key for powered wheels
					var assigned_key = p_data.get("assigned_key", "")
					if assigned_key != "":
						if not wheel_forward_groups.has(assigned_key):
							wheel_forward_groups[assigned_key] = []
						_create_ui_button(assigned_key)
						wheel_forward_groups[assigned_key].append({
							"rolling_body": rolling_body
						})

					# Track reverse key for powered wheels
					var reverse_key = p_data.get("reverse_key", "")
					if reverse_key != "":
						if not wheel_reverse_groups.has(reverse_key):
							wheel_reverse_groups[reverse_key] = []
						_create_ui_button(reverse_key)
						wheel_reverse_groups[reverse_key].append({
							"rolling_body": rolling_body
						})

	for inst in part_nodes:
		inst.queue_free()

	print("Vehicle built successfully with dual wheel controls and exported power settings!")

func _physics_process(_delta: float):
	active_thrust_indicators.clear()
	
	# Loop through all active key states and apply actions for thrusters and wheels
	for key in active_keys.keys():
		var is_key_pressed = active_keys[key]
		
		# 1. Handle Thrusters and Particles for this key
		if thruster_groups.has(key):
			for t_data in thruster_groups[key]:
				var body: RigidBody2D = t_data["body"]
				var particles: CPUParticles2D = t_data.get("particles")
				
				if is_instance_valid(body):
					if is_key_pressed:
						var local_pos = t_data["local_pos"]
						var local_rot = t_data["local_rot"]
						
						var rotated_local_pos = local_pos.rotated(body.global_rotation)
						var current_global_pos = body.global_position + rotated_local_pos
						
						var current_global_rot = body.global_rotation + local_rot
						var direction = Vector2.UP.rotated(current_global_rot)
						var force = direction * thruster_power
						
						body.apply_force(force, rotated_local_pos)
						
						if is_instance_valid(particles):
							particles.emitting = true
						
						active_thrust_indicators.append({
							"pos": current_global_pos,
							"dir": direction
						})
					else:
						if is_instance_valid(particles):
							particles.emitting = false

		# 2. Handle Forward Wheels (Positive Torque)
		if wheel_forward_groups.has(key) and is_key_pressed:
			for w_data in wheel_forward_groups[key]:
				var rolling_body: RigidBody2D = w_data["rolling_body"]
				if is_instance_valid(rolling_body):
					rolling_body.apply_torque(wheel_power)

		# 3. Handle Reverse Wheels (Negative Torque)
		if wheel_reverse_groups.has(key) and is_key_pressed:
			for w_data in wheel_reverse_groups[key]:
				var rolling_body: RigidBody2D = w_data["rolling_body"]
				if is_instance_valid(rolling_body):
					rolling_body.apply_torque(-wheel_power)
	
	queue_redraw()

# Shared UI button creator for all control keys
func _create_ui_button(key: String):
	if active_keys.has(key):
		return
		
	active_keys[key] = false
	
	var container = canvas_layer.get_node_or_null("ButtonContainer")
	if not container:
		return
		
	var btn = Button.new()
	btn.text = key
	btn.custom_minimum_size = Vector2(100, 50)
	container.add_child(btn)
	
	btn.button_down.connect(func():
		active_keys[key] = true
	)
	
	btn.button_up.connect(func():
		active_keys[key] = false
	)

func _find_part_instance_from_collider(collider: Object, part_nodes: Array) -> Node:
	var curr = collider
	while curr and curr is Node:
		if curr in part_nodes:
			return curr
		curr = curr.get_parent()
	return null
