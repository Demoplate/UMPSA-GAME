extends Node2D

@export var grid_size: float = 16.0
@export var thruster_power: float = 2000.0
@export var wheel_power: float = 20000.0

# Unified dictionaries for key inputs and groups
var active_keys = {}
var thruster_groups = {}
var wheel_forward_groups = {}
var wheel_reverse_groups = {}
var watergun_groups = {}

var active_thrust_indicators = []
var canvas_layer: CanvasLayer
var ui_root: Control = null

# State tracker for UI layout editing
var is_ui_unlocked: bool = false
var toggle_edit_btn: Button = null

func _ready():
	if GameData.saved_parts.is_empty():
		print("[BUILD] Warning: GameData.saved_parts is empty!")
		return
		
	# Setup UI Canvas Layer and full-rect wrapper control for correct layout scaling
	canvas_layer = get_node_or_null("CanvasLayer")
	if not canvas_layer:
		canvas_layer = CanvasLayer.new()
		canvas_layer.name = "CanvasLayer"
		add_child(canvas_layer)
		
	ui_root = canvas_layer.get_node_or_null("UIRoot")
	if not ui_root:
		ui_root = Control.new()
		ui_root.name = "UIRoot"
		ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas_layer.add_child(ui_root)
		
		# GridContainer for organized vehicle controls at the bottom right
		var grid = GridContainer.new()
		grid.name = "ButtonContainer"
		grid.columns = 2
		grid.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		grid.offset_left = -240
		grid.offset_top = -300
		grid.offset_right = -20
		grid.offset_bottom = -20
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		ui_root.add_child(grid)
		
		# Toggle edit button pinned strictly to the TOP RIGHT
		toggle_edit_btn = Button.new()
		toggle_edit_btn.name = "ToggleEditButton"
		toggle_edit_btn.text = "Unlock UI"
		toggle_edit_btn.custom_minimum_size = Vector2(110, 45)
		toggle_edit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		toggle_edit_btn.offset_left = -140
		toggle_edit_btn.offset_top = 20
		toggle_edit_btn.offset_right = -20
		toggle_edit_btn.offset_bottom = 65
		ui_root.add_child(toggle_edit_btn)
		
		toggle_edit_btn.pressed.connect(_on_toggle_edit_pressed)
	else:
		toggle_edit_btn = ui_root.get_node_or_null("ToggleEditButton")
		if toggle_edit_btn and not toggle_edit_btn.pressed.is_connected(_on_toggle_edit_pressed):
			toggle_edit_btn.pressed.connect(_on_toggle_edit_pressed)

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

	# 2. Group parts into islands
	var islands = []
	var part_to_island = {}
	
	for node in part_nodes:
		var island = [node]
		islands.append(island)
		part_to_island[node] = island

	for curr_instance in part_nodes:
		var scan_node = node_to_scan[curr_instance]
		var p_data = data_to_node[curr_instance]
		var scene_path = p_data.get("scene_path", "").to_lower()
		
		var raycasts = []
		if scan_node is Node:
			for child in scan_node.find_children("*", "RayCast2D", true, false):
				raycasts.append(child)
		
		if "thruster" in scene_path:
			raycasts = raycasts.filter(func(rc): return rc.name == "Raycast2D_Top")
		
		var colliding_rcs = []
		for rc in raycasts:
			if rc.name == "water_cast":
				continue
			rc.collision_mask = 2
			rc.add_exception(curr_instance)
			rc.force_raycast_update()
			
			if rc.is_colliding():
				colliding_rcs.append(rc)
		
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
				
				if island_a != island_b:
					for node in island_b:
						island_a.append(node)
						part_to_island[node] = island_a
					islands.erase(island_b)

	# 3. Build unified RigidBody2D chassis islands
	for island in islands:
		var center_pos = Vector2.ZERO
		for inst in island:
			center_pos += inst.global_position
		center_pos /= island.size()
		
		var master_body = RigidBody2D.new()
		get_tree().current_scene.add_child(master_body)
		master_body.global_position = center_pos
		
		var chassis_mat = PhysicsMaterial.new()
		chassis_mat.friction = 0.4
		master_body.physics_material_override = chassis_mat
		
		var has_command = false
		for inst in island:
			var p_data = data_to_node[inst]
			if (p_data.get("type") == "command") or ("command" in p_data.get("scene_path", "").to_lower()):
				has_command = true
				break
				
		if has_command:
			var camera = Camera2D.new()
			master_body.add_child(camera)
			camera.make_current()
		
		for inst in island:
			var p_data = data_to_node[inst]
			var is_wheel = (p_data.get("type") == "wheel") or ("wheel" in p_data.get("scene_path", "").to_lower())
			var is_thruster = (p_data.get("type") == "thruster") or ("thruster" in p_data.get("scene_path", "").to_lower())
			var is_watergun = (p_data.get("type") == "watergun") or ("watergun" in p_data.get("scene_path", "").to_lower())
			
			if not is_wheel:
				var duplicated_particles = null
				var duplicated_water_cast = null
				
				for child in inst.get_children():
					if child is CollisionShape2D or child is Sprite2D or child is RayCast2D or child is CPUParticles2D:
						var global_pos = child.global_position
						var global_rot = child.global_rotation
						
						var dup = child.duplicate()
						master_body.add_child(dup)
						dup.global_position = global_pos
						dup.global_rotation = global_rot
						dup.position = master_body.to_local(global_pos)
						
						if (is_thruster or is_watergun) and dup is CPUParticles2D:
							duplicated_particles = dup
							
						if is_watergun and dup is RayCast2D and dup.name == "water_cast":
							dup.collision_mask = 1
							duplicated_water_cast = dup
				
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
						
				if is_watergun:
					var assigned_key = p_data.get("assigned_key", "")
					if assigned_key != "":
						if not watergun_groups.has(assigned_key):
							watergun_groups[assigned_key] = []
						_create_ui_button(assigned_key)
						watergun_groups[assigned_key].append({
							"particles": duplicated_particles,
							"water_cast": duplicated_water_cast
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
					
					var assigned_key = p_data.get("assigned_key", "")
					if assigned_key != "":
						if not wheel_forward_groups.has(assigned_key):
							wheel_forward_groups[assigned_key] = []
						_create_ui_button(assigned_key)
						wheel_forward_groups[assigned_key].append({
							"rolling_body": rolling_body
						})

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

func _physics_process(_delta: float):
	active_thrust_indicators.clear()
	
	for key in active_keys.keys():
		var is_key_pressed = active_keys[key]
		
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
					else:
						if is_instance_valid(particles):
							particles.emitting = false

		if watergun_groups.has(key):
			for w_data in watergun_groups[key]:
				var particles: CPUParticles2D = w_data.get("particles")
				var water_cast: RayCast2D = w_data.get("water_cast")
				
				if is_instance_valid(particles):
					particles.emitting = is_key_pressed
					
				if is_instance_valid(water_cast):
					water_cast.enabled = is_key_pressed
					if is_key_pressed:
						water_cast.force_raycast_update()
					if is_key_pressed and water_cast.is_colliding():
						var collider = water_cast.get_collider()
						if collider:
							var fire_node: Node = null
							if collider.name == "Fire" or (collider.has_meta("is_fire") and collider.get_meta("is_fire")):
								fire_node = collider
							elif collider.get_parent() and collider.get_parent().name == "Fire":
								fire_node = collider.get_parent()
							if fire_node:
								_fade_out_fire(fire_node)

		if wheel_forward_groups.has(key) and is_key_pressed:
			for w_data in wheel_forward_groups[key]:
				var rolling_body: RigidBody2D = w_data["rolling_body"]
				if is_instance_valid(rolling_body):
					rolling_body.apply_torque(wheel_power)

		if wheel_reverse_groups.has(key) and is_key_pressed:
			for w_data in wheel_reverse_groups[key]:
				var rolling_body: RigidBody2D = w_data["rolling_body"]
				if is_instance_valid(rolling_body):
					rolling_body.apply_torque(-wheel_power)
	
	queue_redraw()

func _draw():
	for key in watergun_groups:
		if not active_keys.get(key, false):
			continue
		for w_data in watergun_groups[key]:
			var water_cast: RayCast2D = w_data.get("water_cast")
			if not is_instance_valid(water_cast) or not water_cast.enabled:
				continue

			var ray_start = to_local(water_cast.global_position)
			var ray_end_global = water_cast.get_collision_point() if water_cast.is_colliding() else water_cast.to_global(water_cast.target_position)
			var ray_end = to_local(ray_end_global)
			var ray_color = Color.RED if water_cast.is_colliding() else Color.CYAN
			draw_line(ray_start, ray_end, ray_color, 3.0, true)
			draw_circle(ray_end, 5.0, ray_color)

func _fade_out_fire(fire_node: Node) -> void:
	if not is_instance_valid(fire_node) or fire_node.get_meta("is_fading", false):
		return
	fire_node.set_meta("is_fading", true)

	for collision_shape in fire_node.find_children("*", "CollisionShape2D", true, false):
		collision_shape.set_deferred("disabled", true)
	if fire_node is CollisionObject2D:
		fire_node.set_deferred("collision_layer", 0)
		fire_node.set_deferred("collision_mask", 0)

	if fire_node is CanvasItem:
		var fade_tween := create_tween()
		fade_tween.tween_property(fire_node, "modulate:a", 0.0, 1.0)
		fade_tween.tween_callback(fire_node.queue_free)
	else:
		fire_node.queue_free()

func _create_ui_button(key: String):
	if key == "" or active_keys.has(key):
		return
		
	active_keys[key] = false
	
	var container = ui_root.get_node_or_null("ButtonContainer")
	if not container:
		return
		
	var btn = DraggableButton.new()
	btn.text = key
	btn.custom_minimum_size = Vector2(100, 50)
	container.add_child(btn)
	
	btn.button_down.connect(func():
		if not is_ui_unlocked:
			active_keys[key] = true
	)
	
	btn.button_up.connect(func():
		if not is_ui_unlocked:
			active_keys[key] = false
	)

func _on_toggle_edit_pressed():
	is_ui_unlocked = not is_ui_unlocked
	if is_ui_unlocked:
		toggle_edit_btn.text = "Lock UI"
		print("[UI] UI layout unlocked. Drag buttons to move them!")
	else:
		toggle_edit_btn.text = "Unlock UI"
		print("[UI] UI layout locked.")

func _find_part_instance_from_collider(collider: Object, part_nodes: Array) -> Node:
	var curr = collider
	while curr and curr is Node:
		if curr in part_nodes:
			return curr
		curr = curr.get_parent()
	return null

class DraggableButton extends Button:
	var is_dragging: bool = false
	var drag_offset: Vector2 = Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		var main_node = get_tree().current_scene
		if main_node and "is_ui_unlocked" in main_node and main_node.is_ui_unlocked:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					is_dragging = true
					drag_offset = get_global_mouse_position() - global_position
					accept_event()
				else:
					is_dragging = false
			elif event is InputEventMouseMotion and is_dragging:
				if get_parent() is GridContainer or get_parent() is VBoxContainer:
					var current_pos = global_position
					var parent_container = get_parent()
					parent_container.remove_child(self)
					
					# Re-parent directly to UIRoot for free-floating movement
					var ui_root_node = main_node.get_node_or_null("CanvasLayer/UIRoot")
					if ui_root_node:
						ui_root_node.add_child(self)
					else:
						main_node.add_child(self)
						
					global_position = current_pos
				
				global_position = get_global_mouse_position() - drag_offset
				accept_event()
