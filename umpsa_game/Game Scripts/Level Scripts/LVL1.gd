extends Node2D

@export var grid_size: float = 16.0
@export var thruster_power: float = 2000.0
@export var wheel_power: float = 20000.0
@export_file("*.tscn") var next_scene_path: String

@export_group("Piston")
@export var piston_power: float = 20000.0
@export_range(1.0, 500.0, 1.0, "or_greater") var piston_max_extension: float = 40.0
@export_range(1.0, 500.0, 1.0, "or_greater") var piston_speed: float = 60.0
@export_range(1.0, 1000.0, 1.0, "or_greater") var piston_stiffness: float = 200.0
@export_range(0.0, 200.0, 0.5, "or_greater") var piston_damping: float = 25.0
@export_range(2.0, 100.0, 1.0, "or_greater") var piston_guide_spacing: float = 10.0
@export_range(0.0, 5000.0, 10.0, "or_greater") var piston_rotation_stiffness: float = 400.0
@export_range(0.0, 500.0, 1.0, "or_greater") var piston_rotation_damping: float = 40.0
@export var piston_flip: bool = false
@export_range(0.0, 50.0, 0.5, "or_greater") var piston_rod_width: float = 6.0
@export var piston_rod_color: Color = Color(0.6, 0.6, 0.65)
@export_group("")

var active_keys = {}
var key_map = {}
var ui_buttons = {}
var thruster_groups = {}
var wheel_forward_groups = {}
var wheel_reverse_groups = {}
var watergun_groups = {}
var piston_extend_groups = {}
var piston_retract_groups = {}
var pistons = []

var ui_layer: CanvasLayer
var ui_root: Control
var toggle_edit_btn: Button
var is_ui_unlocked: bool = false
var button_count: int = 0

func _ready():
	_build_ui()

	if GameData.saved_parts.is_empty():
		return

	var part_nodes = []
	var data_to_node = {}

	for p in GameData.saved_parts:
		var scene = load(p["scene_path"])
		if scene:
			var instance = scene.instantiate()
			get_tree().current_scene.add_child(instance)
			instance.global_position = p["global_position"]
			instance.rotation = p["rotation"]
			part_nodes.append(instance)
			data_to_node[instance] = p

	await get_tree().physics_frame
	await get_tree().physics_frame

	var head_to_piston = {}
	var piston_to_head = {}
	for inst in part_nodes:
		if _is_piston(data_to_node[inst]):
			var head = inst.get_node_or_null("Head")
			if head:
				head_to_piston[head] = inst
				piston_to_head[inst] = head

	var all_nodes = part_nodes.duplicate()
	all_nodes.append_array(head_to_piston.keys())

	var islands = []
	var node_to_island = {}

	for node in all_nodes:
		var island = [node]
		islands.append(island)
		node_to_island[node] = island

	for curr_instance in part_nodes:
		var p_data = data_to_node[curr_instance]
		var scene_path = p_data.get("scene_path", "").to_lower()
		var own_head = piston_to_head.get(curr_instance)

		var ray_entries = []
		for rc in curr_instance.find_children("*", "RayCast2D", true, false):
			var ray_owner = curr_instance
			if own_head and own_head.is_ancestor_of(rc):
				ray_owner = own_head
			ray_entries.append([rc, ray_owner])

		if "thruster" in scene_path:
			ray_entries = ray_entries.filter(func(e): return e[0].name == "Raycast2D_Top")

		var colliding = []
		for e in ray_entries:
			var rc = e[0]
			if rc.name == "water_cast":
				continue
			rc.collision_mask = 2
			rc.add_exception(curr_instance)
			if own_head:
				rc.add_exception(own_head)
			rc.force_raycast_update()
			if rc.is_colliding():
				colliding.append(e)

		if "wheel" in scene_path:
			var has_bottom = false
			var has_others = false
			for e in colliding:
				if e[0].name == "Raycast2D_Bottom":
					has_bottom = true
				else:
					has_others = true
			if has_bottom and not has_others:
				colliding.clear()

		for e in colliding:
			var hit = _find_node_from_collider(e[0].get_collider(), all_nodes)
			var ray_owner = e[1]
			if hit and hit != ray_owner:
				var island_a = node_to_island[ray_owner]
				var island_b = node_to_island[hit]
				if island_a != island_b and not _would_lock_piston(island_a, island_b, head_to_piston):
					for node in island_b:
						island_a.append(node)
						node_to_island[node] = island_a
					islands.erase(island_b)

	var node_to_body = {}

	for island in islands:
		var first_head = null
		for node in island:
			if head_to_piston.has(node):
				first_head = node
				break

		var master_body
		if first_head:
			master_body = first_head.duplicate()
			master_body.can_sleep = false
			get_tree().current_scene.add_child(master_body)
			master_body.global_transform = first_head.global_transform
		else:
			var center_pos = Vector2.ZERO
			for inst in island:
				center_pos += inst.global_position
			center_pos /= island.size()
			master_body = RigidBody2D.new()
			master_body.can_sleep = false
			get_tree().current_scene.add_child(master_body)
			master_body.global_position = center_pos

		var chassis_mat = PhysicsMaterial.new()
		chassis_mat.friction = 0.4
		master_body.physics_material_override = chassis_mat

		var has_command = false
		for inst in island:
			node_to_body[inst] = master_body
			if head_to_piston.has(inst):
				continue
			var p_data = data_to_node[inst]
			var scene_path = p_data.get("scene_path", "").to_lower()
			var p_type = p_data.get("type", "").to_lower()
			if p_type == "command" or "command" in scene_path or inst.name.to_lower().contains("command"):
				has_command = true

		if has_command:
			var camera = Camera2D.new()
			master_body.add_child(camera)
			camera.make_current()

			var flag_detector = Area2D.new()
			flag_detector.name = "ProgrammaticFlagpoleDetector"
			master_body.add_child(flag_detector)

			var detector_shape = CollisionShape2D.new()
			var rect_shape = RectangleShape2D.new()
			rect_shape.size = Vector2(40, 40)
			detector_shape.shape = rect_shape
			flag_detector.add_child(detector_shape)

			flag_detector.monitorable = true
			flag_detector.monitoring = true

			flag_detector.area_entered.connect(func(area):
				var target_name = area.name.to_lower()
				var parent_name = area.get_parent().name.to_lower() if area.get_parent() else ""
				if "flagpole" in target_name or "flagpole" in parent_name or area.is_in_group("flagpole"):
					if next_scene_path and not next_scene_path.is_empty():
						GameData.saved_parts.clear()
						get_tree().change_scene_to_file(next_scene_path)
					else:
						print("[ERROR] Next scene path is not assigned on the Level Loader node!")
			)

		for inst in island:
			if head_to_piston.has(inst):
				if inst != first_head:
					for child in inst.get_children():
						if child is CollisionShape2D or child is Sprite2D:
							var global_pos = child.global_position
							var global_rot = child.global_rotation
							var dup = child.duplicate()
							master_body.add_child(dup)
							dup.global_position = global_pos
							dup.global_rotation = global_rot
				continue

			var p_data = data_to_node[inst]
			var scene_path = p_data.get("scene_path", "").to_lower()
			var p_type = p_data.get("type", "").to_lower()

			var is_wheel = (p_type == "wheel") or ("wheel" in scene_path)
			var is_piston = (p_type == "piston") or ("piston" in scene_path)
			var is_thruster = (p_type == "thruster") or ("thruster" in scene_path)
			var is_watergun = (p_type == "watergun") or ("watergun" in scene_path)

			var assigned_key = _get_key(p_data, "assigned_key")
			var reverse_key = _get_key(p_data, "reverse_key")

			if not is_wheel and not is_piston:
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

						if (is_thruster or is_watergun) and dup is CPUParticles2D:
							duplicated_particles = dup

						if is_watergun and dup is RayCast2D and dup.name == "water_cast":
							dup.collision_mask = 1
							duplicated_water_cast = dup

				if is_thruster and assigned_key != "":
					if not thruster_groups.has(assigned_key):
						thruster_groups[assigned_key] = []
					_create_ui_button(assigned_key)
					thruster_groups[assigned_key].append({
						"body": master_body,
						"local_pos": master_body.to_local(inst.global_position),
						"local_rot": inst.global_rotation - master_body.global_rotation,
						"particles": duplicated_particles
					})

				if is_watergun and assigned_key != "":
					if not watergun_groups.has(assigned_key):
						watergun_groups[assigned_key] = []
					_create_ui_button(assigned_key)
					watergun_groups[assigned_key].append({
						"particles": duplicated_particles,
						"water_cast": duplicated_water_cast
					})

			elif is_piston:
				for child in inst.get_children():
					if child.name != "Head" and child.name != "GrooveJoint":
						if child is CollisionShape2D or child is Sprite2D:
							var global_pos = child.global_position
							var global_rot = child.global_rotation
							var dup = child.duplicate()
							master_body.add_child(dup)
							dup.global_position = global_pos
							dup.global_rotation = global_rot

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

				var wheel_rolling = inst.get_node_or_null("WheelRolling")
				var pin_joint = inst.get_node_or_null("PinJoint2D")

				if wheel_rolling:
					var rolling_body = wheel_rolling.duplicate()
					rolling_body.can_sleep = false
					get_tree().current_scene.add_child(rolling_body)
					rolling_body.global_transform = wheel_rolling.global_transform

					var wheel_mat = PhysicsMaterial.new()
					wheel_mat.friction = 0.8
					rolling_body.physics_material_override = wheel_mat

					if pin_joint:
						var new_pin = pin_joint.duplicate()
						new_pin.disable_collision = true
						get_tree().current_scene.add_child(new_pin)
						new_pin.global_position = pin_joint.global_position
						new_pin.node_a = master_body.get_path()
						new_pin.node_b = rolling_body.get_path()

					if assigned_key != "":
						if not wheel_forward_groups.has(assigned_key):
							wheel_forward_groups[assigned_key] = []
						_create_ui_button(assigned_key)
						wheel_forward_groups[assigned_key].append({"rolling_body": rolling_body})

					if reverse_key != "":
						if not wheel_reverse_groups.has(reverse_key):
							wheel_reverse_groups[reverse_key] = []
						_create_ui_button(reverse_key)
						wheel_reverse_groups[reverse_key].append({"rolling_body": rolling_body})

	for piston_inst in piston_to_head.keys():
		var head_node = piston_to_head[piston_inst]
		var chassis_body = node_to_body[piston_inst]
		var head_body = node_to_body[head_node]
		if chassis_body == head_body:
			continue

		var p_data = data_to_node[piston_inst]
		var assigned_key = _get_key(p_data, "assigned_key")
		var reverse_key = _get_key(p_data, "reverse_key")

		var axis = Vector2.UP.rotated(piston_inst.global_rotation)
		if piston_flip:
			axis = -axis

		var side = axis.orthogonal() * piston_guide_spacing
		var joint_rot = axis.angle() - PI / 2.0
		var anchor_world = head_node.global_position

		for offset in [Vector2.ZERO, side]:
			var joint = GrooveJoint2D.new()
			joint.length = piston_max_extension
			joint.initial_offset = 0.0
			joint.disable_collision = true
			get_tree().current_scene.add_child(joint)
			joint.global_position = anchor_world + offset
			joint.global_rotation = joint_rot
			joint.node_a = chassis_body.get_path()
			joint.node_b = head_body.get_path()

		var rod = Line2D.new()
		rod.width = piston_rod_width
		rod.default_color = piston_rod_color
		rod.begin_cap_mode = Line2D.LINE_CAP_ROUND
		rod.end_cap_mode = Line2D.LINE_CAP_ROUND
		rod.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
		get_tree().current_scene.add_child(rod)
		get_tree().current_scene.move_child(rod, mini(chassis_body.get_index(), head_body.get_index()))

		var piston_data = {
			"head": head_body,
			"chassis": chassis_body,
			"rod": rod,
			"local_anchor": chassis_body.to_local(anchor_world),
			"head_anchor": head_body.to_local(anchor_world),
			"local_axis": chassis_body.global_transform.affine_inverse().basis_xform(axis).normalized(),
			"rot_offset": head_body.global_rotation - chassis_body.global_rotation,
			"target": 0.0
		}
		pistons.append(piston_data)

		if assigned_key != "":
			if not piston_extend_groups.has(assigned_key):
				piston_extend_groups[assigned_key] = []
			_create_ui_button(assigned_key)
			piston_extend_groups[assigned_key].append(piston_data)

		if reverse_key != "":
			if not piston_retract_groups.has(reverse_key):
				piston_retract_groups[reverse_key] = []
			_create_ui_button(reverse_key)
			piston_retract_groups[reverse_key].append(piston_data)

	for inst in part_nodes:
		inst.queue_free()

func _is_piston(p_data) -> bool:
	var scene_path = p_data.get("scene_path", "").to_lower()
	var p_type = p_data.get("type", "").to_lower()
	return p_type == "piston" or "piston" in scene_path

func _would_lock_piston(island_a: Array, island_b: Array, head_to_piston: Dictionary) -> bool:
	for node in island_a:
		if head_to_piston.has(node) and head_to_piston[node] in island_b:
			return true
	for node in island_b:
		if head_to_piston.has(node) and head_to_piston[node] in island_a:
			return true
	return false

func _get_key(p_data, field: String) -> String:
	var v = p_data.get(field, "")
	if v == null:
		return ""
	if typeof(v) == TYPE_INT:
		return OS.get_keycode_string(v) if v != 0 else ""
	return str(v)

func _build_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.name = "VehicleUILayer"
	ui_layer.layer = 128
	add_child(ui_layer)

	ui_root = Control.new()
	ui_root.name = "VehicleUIRoot"
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	toggle_edit_btn = Button.new()
	toggle_edit_btn.name = "ToggleEditButton"
	toggle_edit_btn.text = "Unlock UI"
	toggle_edit_btn.focus_mode = Control.FOCUS_NONE
	toggle_edit_btn.custom_minimum_size = Vector2(110, 45)
	ui_root.add_child(toggle_edit_btn)
	toggle_edit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toggle_edit_btn.offset_left = -140
	toggle_edit_btn.offset_top = 20
	toggle_edit_btn.offset_right = -20
	toggle_edit_btn.offset_bottom = 65
	toggle_edit_btn.pressed.connect(_on_toggle_edit_pressed)

func _create_ui_button(key: String):
	if key == "" or active_keys.has(key):
		return

	active_keys[key] = false
	key_map[key.to_upper()] = key

	var btn = DraggableButton.new()
	btn.loader = self
	btn.text = key
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(100, 50)
	btn.size = Vector2(100, 50)
	ui_root.add_child(btn)
	ui_buttons[key] = btn

	var vp = get_viewport().get_visible_rect().size
	var col = button_count % 2
	var row = int(button_count / 2)
	btn.position = Vector2(vp.x - 120 - col * 110, vp.y - 70 - row * 60)
	button_count += 1

	btn.button_down.connect(func():
		if not is_ui_unlocked:
			active_keys[key] = true
	)
	btn.button_up.connect(func():
		if not is_ui_unlocked:
			active_keys[key] = false
	)

func _unhandled_input(event: InputEvent):
	if is_ui_unlocked:
		return
	if event is InputEventKey and not event.echo:
		var key_name = OS.get_keycode_string(event.keycode).to_upper()
		if key_map.has(key_name):
			var key = key_map[key_name]
			active_keys[key] = event.pressed
			if ui_buttons.has(key):
				ui_buttons[key].modulate = Color(0.6, 1.0, 0.6) if event.pressed else Color.WHITE

func _physics_process(delta: float):
	for key in active_keys.keys():
		var is_key_pressed = active_keys[key]

		if thruster_groups.has(key):
			for t_data in thruster_groups[key]:
				var body: RigidBody2D = t_data["body"]
				var particles: CPUParticles2D = t_data.get("particles")
				if is_instance_valid(body):
					if is_key_pressed:
						var rotated_local_pos = t_data["local_pos"].rotated(body.global_rotation)
						var direction = Vector2.UP.rotated(body.global_rotation + t_data["local_rot"])
						body.apply_force(direction * thruster_power, rotated_local_pos)
					if is_instance_valid(particles):
						particles.emitting = is_key_pressed

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
						if water_cast.is_colliding():
							var collider = water_cast.get_collider()
							if collider:
								var fire_node: Node = null
								if collider.name == "Fire" or (collider.has_meta("is_fire") and collider.get_meta("is_fire")):
									fire_node = collider
								elif collider.get_parent() and collider.get_parent().name == "Fire":
									fire_node = collider.get_parent()
								if fire_node:
									_fade_out_fire(fire_node)

		if is_key_pressed:
			if wheel_forward_groups.has(key):
				for w_data in wheel_forward_groups[key]:
					if is_instance_valid(w_data["rolling_body"]):
						w_data["rolling_body"].apply_torque(wheel_power)

			if wheel_reverse_groups.has(key):
				for w_data in wheel_reverse_groups[key]:
					if is_instance_valid(w_data["rolling_body"]):
						w_data["rolling_body"].apply_torque(-wheel_power)

			if piston_extend_groups.has(key):
				for p_data in piston_extend_groups[key]:
					p_data["target"] = minf(p_data["target"] + piston_speed * delta, piston_max_extension)

			if piston_retract_groups.has(key):
				for p_data in piston_retract_groups[key]:
					p_data["target"] = maxf(p_data["target"] - piston_speed * delta, 0.0)

	for p_data in pistons:
		_drive_piston(p_data)

	queue_redraw()

func _drive_piston(p_data: Dictionary):
	var head: RigidBody2D = p_data["head"]
	var chassis: RigidBody2D = p_data["chassis"]
	if not is_instance_valid(head) or not is_instance_valid(chassis):
		return

	var axis = chassis.global_transform.basis_xform(p_data["local_axis"]).normalized()
	var origin = chassis.to_global(p_data["local_anchor"])
	var head_point = head.to_global(p_data["head_anchor"])
	var extension = (head_point - origin).dot(axis)
	var rel_vel = (head.linear_velocity - chassis.linear_velocity).dot(axis)
	var accel = piston_stiffness * (p_data["target"] - extension) - piston_damping * rel_vel
	var force = clampf(head.mass * accel, -piston_power, piston_power)
	var push = axis * force

	head.apply_central_force(push)
	chassis.apply_force(-push, head_point - chassis.global_position)

	if piston_rotation_stiffness > 0.0:
		var rot_err = wrapf(head.global_rotation - chassis.global_rotation - p_data["rot_offset"], -PI, PI)
		var rel_ang_vel = head.angular_velocity - chassis.angular_velocity
		var inertia = head.inertia if head.inertia > 0.0 else head.mass * 1000.0
		var torque = inertia * (-piston_rotation_stiffness * rot_err - piston_rotation_damping * rel_ang_vel)
		head.apply_torque(torque)
		chassis.apply_torque(-torque)

	var rod: Line2D = p_data["rod"]
	if is_instance_valid(rod):
		rod.width = piston_rod_width
		rod.default_color = piston_rod_color
		rod.points = PackedVector2Array([rod.to_local(origin), rod.to_local(head_point)])

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

func _on_toggle_edit_pressed():
	is_ui_unlocked = not is_ui_unlocked
	toggle_edit_btn.text = "Lock UI" if is_ui_unlocked else "Unlock UI"
	if is_ui_unlocked:
		for key in active_keys.keys():
			active_keys[key] = false
			if ui_buttons.has(key):
				ui_buttons[key].modulate = Color.WHITE

func _find_node_from_collider(collider: Object, nodes: Array) -> Node:
	var curr = collider
	while curr and curr is Node:
		if curr in nodes:
			return curr
		curr = curr.get_parent()
	return null

class DraggableButton extends Button:
	var loader: Node = null
	var is_dragging: bool = false
	var drag_offset: Vector2 = Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		if loader == null or not loader.is_ui_unlocked:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			if event.pressed:
				drag_offset = get_global_mouse_position() - global_position
			accept_event()
		elif event is InputEventMouseMotion and is_dragging:
			var target = get_global_mouse_position() - drag_offset
			var vp = get_viewport_rect().size
			global_position = Vector2(
				clampf(target.x, 0.0, vp.x - size.x),
				clampf(target.y, 0.0, vp.y - size.y)
			)
			accept_event()
