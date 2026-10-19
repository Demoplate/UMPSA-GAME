extends Area2D

@export var part_scene: PackedScene
@export var rotate_button: Area2D
@export var max_parts: int = 5

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var count_label: Label = $Label

var last_rotate_msec := -1000
var last_spawn_msec := -1000
var current_parts_count: int = 0

func _ready() -> void:
	if rotate_button:
		rotate_button.input_event.connect(_on_rotate_button_clicked)
	else:
		print("Bro, assign the rotate_button in the inspector!")

	sync_count_with_game_data()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("connect_existing_scene_parts")
	update_visuals()

func sync_count_with_game_data() -> void:
	current_parts_count = 0
	if not part_scene or not "saved_parts" in GameData:
		return

	var target_path = part_scene.resource_path.get_file().to_lower().replace("rigid_", "")

	for p in GameData.saved_parts:
		var p_path = p.get("scene_path", "").get_file().to_lower().replace("rigid_", "")
		if target_path == p_path or target_path in p_path or p_path in target_path:
			current_parts_count += 1

func connect_existing_scene_parts() -> void:
	for node in get_tree().current_scene.find_children("*", "Node2D", true, false):
		_try_connect(node)

func _on_node_added(node: Node) -> void:
	if node is Node2D:
		_try_connect.call_deferred(node)

func _try_connect(node: Node) -> void:
	if not is_instance_valid(node) or not _matches_part(node):
		return
	if not node.tree_exited.is_connected(_on_part_tree_exited):
		node.tree_exited.connect(_on_part_tree_exited)

func _matches_part(node: Node) -> bool:
	if node == self or not part_scene:
		return false
	var target_path = part_scene.resource_path.get_file().to_lower().replace("rigid_", "")
	var node_path = ""
	if node.scene_file_path != "":
		node_path = node.scene_file_path.get_file().to_lower().replace("rigid_", "")
	elif node.has_meta("scene_path"):
		node_path = node.get_meta("scene_path").get_file().to_lower().replace("rigid_", "")
	return node_path != "" and (target_path == node_path or target_path in node_path or node_path in target_path)

func _on_part_tree_exited() -> void:
	current_parts_count = max(0, current_parts_count - 1)
	update_visuals()

func _process(_delta: float) -> void:
	var is_select_or_delete = false

	if "current_tool" in GameData:
		if GameData.current_tool == GameData.ToolMode.SELECT or GameData.current_tool == GameData.ToolMode.DELETE:
			is_select_or_delete = true

	visible = !is_select_or_delete

	if sprite:
		sprite.visible = !is_select_or_delete

	if collision_shape:
		collision_shape.disabled = is_select_or_delete

	if count_label:
		count_label.visible = !is_select_or_delete

	if rotate_button:
		rotate_button.visible = !is_select_or_delete
		for child in rotate_button.get_children():
			if child is CollisionShape2D:
				child.disabled = is_select_or_delete

func update_visuals() -> void:
	var remaining = max_parts - current_parts_count

	if count_label:
		count_label.text = str(remaining)

	if sprite:
		if max_parts > 0 and current_parts_count >= max_parts:
			sprite.modulate.a = 0.4
		else:
			sprite.modulate.a = 1.0

func _is_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and event.pressed:
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return true
	return false

func _on_rotate_button_clicked(viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not visible:
		return

	if _is_press(event):
		viewport.set_input_as_handled()

		var now := Time.get_ticks_msec()
		if now - last_rotate_msec < 250:
			return
		last_rotate_msec = now

		rotate(deg_to_rad(90.0))

func _input_event(viewport, event, _shape_idx):
	if not visible:
		return

	if _is_press(event):
		viewport.set_input_as_handled()

		var now := Time.get_ticks_msec()
		if now - last_spawn_msec < 250:
			return
		last_spawn_msec = now

		if max_parts > 0 and current_parts_count >= max_parts:
			print("Part limit reached! Max allowed: ", max_parts)
			return

		spawn_and_drag(global_position)

func spawn_and_drag(pos: Vector2):
	if not part_scene:
		return

	current_parts_count += 1
	update_visuals()

	var new_part = part_scene.instantiate() as Node2D
	new_part.set_meta("scene_path", part_scene.resource_path)

	get_tree().current_scene.add_child(new_part)

	new_part.top_level = true
	new_part.global_position = pos
	new_part.global_rotation = global_rotation

	if not new_part.tree_exited.is_connected(_on_part_tree_exited):
		new_part.tree_exited.connect(_on_part_tree_exited)

	if new_part.has_method("start_dragging"):
		new_part.start_dragging()
