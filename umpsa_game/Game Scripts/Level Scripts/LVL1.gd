extends Node2D

@export var grid_size: float = 16.0
@export var thruster_power: float = 2000.0
@export var wheel_power: float = 20000.0
@export var saw_power: float = 20000.0
@export_file("*.tscn") var next_scene_path: String

@export_group("Piston")
@export_range(1.0, 500.0, 1.0, "or_greater") var piston_max_extension: float = 40.0
@export_range(1.0, 500.0, 1.0, "or_greater") var piston_speed: float = 60.0
@export var piston_flip: bool = false
@export_range(0.0, 1.0, 0.05) var piston_wheel_rigidity: float = 0.5
@export_range(0.0, 50.0, 0.5, "or_greater") var piston_rod_width: float = 6.0
@export var piston_rod_color: Color = Color(0.6, 0.6, 0.65)
@export_group("")

@export_group("Laser")
@export_range(10.0, 5000.0, 10.0, "or_greater") var laser_range: float = 600.0
@export_range(0.5, 30.0, 0.5, "or_greater") var laser_width: float = 3.0
@export_range(0.0, 30.0, 0.5, "or_greater") var laser_dot_size: float = 4.0
@export var laser_color: Color = Color(1.0, 0.15, 0.15)
@export var laser_destroy_meta: String = "dest"
@export_flags_2d_physics var laser_collision_mask: int = 1
@export_range(-4096, 4096, 1) var laser_z_index: int = 10
@export_group("")

var active_keys = {}
var toggle_keys = {}
var key_map = {}
var ui_buttons = {}
var thruster_groups = {}
var wheel_forward_groups = {}
var wheel_reverse_groups = {}
var saw_groups = {}
var watergun_groups = {}
var laser_groups = {}
var piston_extend_groups = {}
var piston_retract_groups = {}
var pistons = []
var frozen_to_chassis = {}
var head_wheels = []

var laser_drawer: Node2D
var ui_layer: CanvasLayer
var ui_root: Control
var toggle_edit_btn: Button
var is_ui_unlocked: bool = false
var button_count: int = 0

func _ready():
	_build_ui()

	laser_drawer = LaserDrawer.new()
	laser_drawer.loader = self
	laser_drawer.z_index = laser_z_index
	laser_drawer.z_as_relative = false
	add_child(laser_drawer)

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
			instance.global_rotation = p["rotation"]
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
	for head in head_to_piston.keys():
		all_nodes.append(head)

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

		for head in head_to_piston.keys():
			if head.is_ancestor_of(curr_instance) or curr_instance == head:
				for rc in curr_instance.find_children("*", "RayCast2D", true, false):
					ray_entries.append([rc, head])

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

		if "wheel" in scene_path or "saw" in scene_path:
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
				var island_a = node_to_island.get(ray_owner)
				var island_b = node_to_island.get(hit)
				if island_a and island_b and island_a != island_b and not _would_lock_piston(island_a, island_b, head_to_piston):
					for node in island_b:
						island_a.append(node)
						node_to_island[node] = island_a
					islands.erase(island_b)

	var node_to_body = {}
	var wheel_pins = []

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
			if p_data == null:
				continue
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
			if p_data == null:
				continue
			var scene_path = p_data.get("scene_path", "").to_lower()
			var p_type = p_data.get("type", "").to_lower()

			var is_wheel = (p_type == "wheel") or ("wheel" in scene_path)
			var is_saw = (p_type == "saw") or ("saw" in scene_path)
			var is_piston = (p_type == "piston") or ("piston" in scene_path)
			var is_thruster = (p_type == "thruster") or ("thruster" in scene_path)
			var is_watergun = (p_type == "watergun") or ("watergun" in scene_path)
			var is_laser = (p_type == "laser") or ("laser" in scene_path)

			var assigned_key = _get_key(p_data, "assigned_key")
			var reverse_key = _get_key(p_data, "reverse_key")

			if not is_wheel and not is_saw and not is_piston:
				var duplicated_particles = null
				var duplicated_water_cast = null
				var duplicated_laser_ray = null

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

						if is_laser and dup is RayCast2D and dup.name == "laser_cast":
							dup.collision_mask = laser_collision_mask
							dup.enabled = false
							if dup.target_position != Vector2.ZERO:
								dup.target_position = dup.target_position.normalized() * laser_range
							duplicated_laser_ray = dup

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

				if is_laser and assigned_key != "":
					if duplicated_laser_ray == null:
						duplicated_laser_ray = RayCast2D.new()
						duplicated_laser_ray.collision_mask = laser_collision_mask
						duplicated_laser_ray.enabled = false
						duplicated_laser_ray.target_position = Vector2(0, -laser_range)
						master_body.add_child(duplicated_laser_ray)
						duplicated_laser_ray.global_position = inst.global_position
						duplicated_laser_ray.global_rotation = inst.global_rotation
					if not laser_groups.has(assigned_key):
						laser_groups[assigned_key] = []
					_create_ui_button(assigned_key)
					laser_groups[assigned_key].append({"ray": duplicated_laser_ray})

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
					if child is RayCast2D or child.name == "WheelRolling" or child.name == "SawRolling" or child is PinJoint2D:
						continue
					if child is CollisionShape2D or child is Sprite2D or child is Node2D:
						var global_pos = child.global_position
						var global_rot = child.global_rotation
						var dup = child.duplicate()
						master_body.add_child(dup)
						dup.global_position = global_pos
						dup.global_rotation = global_rot

				var rolling_node = inst.get_node_or_null("WheelRolling")
				if not rolling_node:
					rolling_node = inst.get_node_or_null("SawRolling")
				var pin_joint = inst.get_node_or_null("PinJoint2D")

				if rolling_node:
					var rolling_body = rolling_node.duplicate()
					rolling_body.can_sleep = false
					rolling_body.contact_monitor = true
					rolling_body.max_contacts_reported = 8
					get_tree().current_scene.add_child(rolling_body)
					rolling_body.global_transform = rolling_node.global_transform

					var roll_mat = PhysicsMaterial.new()
					roll_mat.friction = 0.8
					rolling_body.physics_material_override = roll_mat

					if pin_joint:
						var new_pin = pin_joint.duplicate()
						new_pin.disable_collision = true
						get_tree().current_scene.add_child(new_pin)
						new_pin.global_position = pin_joint.global_position
						new_pin.node_a = master_body.get_path()
						new_pin.node_b = rolling_body.get_path()
						wheel_pins.append({
							"pin": new_pin,
							"wheel": rolling_body,
							"master": master_body,
							"pivot": pin_joint.global_position
						})

					if is_saw:
						if assigned_key != "":
							if not saw_groups.has(assigned_key):
								saw_groups[assigned_key] = []
								toggle_keys[assigned_key] = false
							_create_ui_button(assigned_key)
							saw_groups[assigned_key].append({"rolling_body": rolling_body})
					else:
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

		if frozen_to_chassis.has(head_body) or _root_body(chassis_body) == head_body:
			continue

		var anchor_world = head_node.global_position

		head_body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		head_body.freeze = true
		frozen_to_chassis[head_body] = chassis_body

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

	for p_data in pistons:
		var head_body = p_data["head"]
		var root_body = _root_body(p_data["chassis"])
		root_body.mass += head_body.mass
		var head_shapes = []
		for child in head_body.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				var dup = child.duplicate()
				root_body.add_child(dup)
				dup.transform = root_body.global_transform.affine_inverse() * head_body.global_transform * child.transform
				child.set_deferred("disabled", true)
				head_shapes.append({"node": dup, "local": child.transform})
		p_data["shapes"] = head_shapes
		p_data["root"] = root_body

	var piston_by_head = {}
	for p_data in pistons:
		piston_by_head[p_data["head"]] = p_data

	for w in wheel_pins:
		var master = w["master"]
		if not frozen_to_chassis.has(master):
			continue
		var wheel_root = _root_body(master)
		w["pin"].queue_free()
		w["wheel"].add_collision_exception_with(wheel_root)
		w["wheel"].add_collision_exception_with(master)
		head_wheels.append({
			"wheel": w["wheel"],
			"head": master,
			"root": wheel_root,
			"axle_local": master.to_local(w["pivot"]),
			"wheel_local": w["wheel"].to_local(w["pivot"]),
			"piston": piston_by_head[master]
		})

	var vehicle_bodies = []
	for b in node_to_body.values():
		if not vehicle_bodies.has(b):
			vehicle_bodies.append(b)
	for group in wheel_forward_groups.values():
		for d in group:
			if not vehicle_bodies.has(d["rolling_body"]):
				vehicle_bodies.append(d["rolling_body"])
	for group in wheel_reverse_groups.values():
		for d in group:
			if not vehicle_bodies.has(d["rolling_body"]):
				vehicle_bodies.append(d["rolling_body"])
	for group in saw_groups.values():
		for d in group:
			if not vehicle_bodies.has(d["rolling_body"]):
				vehicle_bodies.append(d["rolling_body"])
	for group in laser_groups.values():
		for l_data in group:
			for b in vehicle_bodies:
				l_data["ray"].add_exception(b)

	for inst in part_nodes:
		inst.queue_free()

func _is_piston(p_data) -> bool:
	var scene_path = p_data.get("scene_path", "").to_lower()
	var p_type = p_data.get("type", "").to_lower()
	return p_type == "piston" or "piston" in scene_path

func _root_body(body: RigidBody2D) -> RigidBody2D:
	var current = body
	var guard = 0
	while frozen_to_chassis.has(current) and guard < 32:
		current = frozen_to_chassis[current]
		guard += 1
	return current

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
			if saw_groups.has(key):
				toggle_keys[key] = not toggle_keys[key]
				ui_buttons[key].modulate = Color(0.6, 1.0, 0.6) if toggle_keys[key] else Color.WHITE
			else:
				active_keys[key] = true
	)
	btn.button_up.connect(func():
		if not is_ui_unlocked:
			if not saw_groups.has(key):
				active_keys[key] = false
	)

func _unhandled_input(event: InputEvent):
	if is_ui_unlocked:
		return
	if event is InputEventKey and not event.echo:
		var key_name = OS.get_keycode_string(event.keycode).to_upper()
		if key_map.has(key_name):
			var key = key_map[key_name]
			if saw_groups.has(key):
				if event.pressed:
					toggle_keys[key] = not toggle_keys[key]
					if ui_buttons.has(key):
						ui_buttons[key].modulate = Color(0.6, 1.0, 0.6) if toggle_keys[key] else Color.WHITE
			else:
				active_keys[key] = event.pressed
				if ui_buttons.has(key):
					ui_buttons[key].modulate = Color(0.6, 1.0, 0.6) if event.pressed else Color.WHITE

func _physics_process(delta: float):
	# Apply toggle state for saws continuously and check collisions for destruction
	for key in saw_groups.keys():
		if toggle_keys.get(key, false):
			for d in saw_groups[key]:
				var saw_body = d["rolling_body"]
				if is_instance_valid(saw_body):
					saw_body.apply_torque(saw_power)
					
					if saw_body.has_method("get_colliding_bodies"):
						for collider in saw_body.get_colliding_bodies():
							_check_and_destroy_target(collider)

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
						var root = _root_body(body)
						var world_pos = body.global_position + rotated_local_pos
						root.apply_force(direction * thruster_power, world_pos - root.global_position)
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

		if laser_groups.has(key):
			for l_data in laser_groups[key]:
				var ray: RayCast2D = l_data.get("ray")
				if is_instance_valid(ray):
					ray.enabled = is_key_pressed
					if is_key_pressed:
						ray.force_raycast_update()
						if ray.is_colliding():
							var target = ray.get_collider()
							if target and target.has_meta(laser_destroy_meta) and target.get_meta(laser_destroy_meta) == true:
								_fade_out_target(target)

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
		_drive_piston(p_data, delta)

	for h in head_wheels:
		_constrain_head_wheel(h, delta)

	if is_instance_valid(laser_drawer):
		laser_drawer.z_index = laser_z_index
		laser_drawer.queue_redraw()

	queue_redraw()

func _check_and_destroy_target(target: Object) -> void:
	if target and target is Node and target.has_meta(laser_destroy_meta) and target.get_meta(laser_destroy_meta) == true:
		_fade_out_target(target)

func _fade_out_target(target: Node) -> void:
	if not is_instance_valid(target) or target.has_meta("is_fading") and target.get_meta("is_fading") == true:
		return
	target.set_meta("is_fading", true)

	if target is CanvasItem:
		var fade_tween := create_tween()
		fade_tween.tween_property(target, "modulate:a", 0.0, 3.0)
		fade_tween.tween_callback(func():
			_disable_target_collisions(target)
			target.queue_free()
		)
	else:
		var timer = get_tree().create_timer(3.0)
		timer.timeout.connect(func():
			_disable_target_collisions(target)
			target.queue_free()
		)
func _disable_target_collisions(target: Node) -> void:
	if not is_instance_valid(target):
		return
	for collision_shape in target.find_children("*", "CollisionShape2D", true, false):
		collision_shape.set_deferred("disabled", true)
	for collision_shape in target.find_children("*", "CollisionPolygon2D", true, false):
		collision_shape.set_deferred("disabled", true)
		
	if target is CollisionObject2D:
		target.set_deferred("collision_layer", 0)
		target.set_deferred("collision_mask", 0)
func _drive_piston(p_data: Dictionary, delta: float):
	var head: RigidBody2D = p_data["head"]
	var chassis: RigidBody2D = p_data["chassis"]
	if not is_instance_valid(head) or not is_instance_valid(chassis):
		return

	var axis = chassis.global_transform.basis_xform(p_data["local_axis"]).normalized()
	var prev_target = p_data.get("prev_target", p_data["target"])
	p_data["ext_speed"] = (p_data["target"] - prev_target) / delta
	p_data["prev_target"] = p_data["target"]
	p_data["axis"] = axis
	var origin = chassis.to_global(p_data["local_anchor"])
	var rot = chassis.global_rotation + p_data["rot_offset"]
	var head_point = origin + axis * p_data["target"]
	var head_origin = head_point - Transform2D(rot, Vector2.ZERO) * p_data["head_anchor"]
	var head_xf = Transform2D(rot, head_origin)
	head.global_transform = head_xf

	var root: RigidBody2D = p_data["root"]
	var root_inv = root.global_transform.affine_inverse()
	for s in p_data["shapes"]:
		if is_instance_valid(s["node"]):
			s["node"].transform = root_inv * head_xf * s["local"]

	var rod: Line2D = p_data["rod"]
	if is_instance_valid(rod):
		rod.width = piston_rod_width
		rod.default_color = piston_rod_color
		rod.points = PackedVector2Array([rod.to_local(origin), rod.to_local(head_point)])

func _constrain_head_wheel(h: Dictionary, delta: float):
	var wheel: RigidBody2D = h["wheel"]
	var head: RigidBody2D = h["head"]
	var root: RigidBody2D = h["root"]
	if not is_instance_valid(wheel) or not is_instance_valid(head) or not is_instance_valid(root):
		return

	var sw = PhysicsServer2D.body_get_direct_state(wheel.get_rid())
	var sc = PhysicsServer2D.body_get_direct_state(root.get_rid())
	if sw == null or sc == null:
		return

	var anchor = head.to_global(h["axle_local"])
	var wheel_point = wheel.to_global(h["wheel_local"])
	var pos_c = anchor - root.global_position
	var pos_w = wheel_point - wheel.global_position
	var r_c = pos_c - sc.center_of_mass
	var r_w = pos_w - sw.center_of_mass

	var piston: Dictionary = h["piston"]
	var v_anchor = sc.linear_velocity + Vector2(-r_c.y, r_c.x) * sc.angular_velocity
	v_anchor += piston.get("axis", Vector2.ZERO) * piston.get("ext_speed", 0.0)
	var v_wheel = sw.linear_velocity + Vector2(-r_w.y, r_w.x) * sw.angular_velocity

	var err = wheel_point - anchor
	var rhs = -((v_wheel - v_anchor) + piston_wheel_rigidity * err / delta)

	var m_w = sw.inverse_mass
	var m_c = sc.inverse_mass
	var i_w = sw.inverse_inertia
	var i_c = sc.inverse_inertia
	var k11 = m_w + m_c + i_w * r_w.y * r_w.y + i_c * r_c.y * r_c.y
	var k22 = m_w + m_c + i_w * r_w.x * r_w.x + i_c * r_c.x * r_c.x
	var k12 = -i_w * r_w.x * r_w.y - i_c * r_c.x * r_c.y
	var det = k11 * k22 - k12 * k12
	if absf(det) < 0.000001:
		return

	var impulse = Vector2((k22 * rhs.x - k12 * rhs.y) / det, (k11 * rhs.y - k12 * rhs.x) / det)
	wheel.apply_impulse(impulse, pos_w)
	root.apply_impulse(-impulse, pos_c)

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

class LaserDrawer extends Node2D:
	var loader: Node2D = null

	func _draw():
		if loader == null:
			return
		for key in loader.laser_groups:
			if not loader.active_keys.get(key, false):
				continue
			for l_data in loader.laser_groups[key]:
				var ray: RayCast2D = l_data.get("ray")
				if not is_instance_valid(ray) or not ray.enabled:
					continue
				var start_pos = ray.global_position
				var end_pos = ray.get_collision_point() if ray.is_colliding() else ray.to_global(ray.target_position)
				draw_line(start_pos, end_pos, loader.laser_color, loader.laser_width, true)
				if ray.is_colliding() and loader.laser_dot_size > 0.0:
					draw_circle(end_pos, loader.laser_dot_size, loader.laser_color)

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
