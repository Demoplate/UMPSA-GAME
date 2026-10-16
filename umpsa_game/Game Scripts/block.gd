extends Area2D

@export var is_thruster: bool = false
@export var assigned_key: String = ""
@export var reverse_key: String = "" # Added to support wheel reverse controls
@export var grid_size: float = 32.0
@export var is_selectable: bool = true
@export var max_search_cells: int = 10

static var last_spawn_frame := -1

var is_dragging := false
var active_index := -1

func _ready():
	if GameData.current_tool == GameData.ToolMode.SPAWN:
		var frame := Engine.get_frames_drawn()
		if frame == last_spawn_frame:
			queue_free()
			return
		last_spawn_frame = frame
		is_dragging = true
		active_index = 0
	else:
		is_dragging = false
		queue_free()

func start_dragging(pointer_index: int = 0):
	if GameData.current_tool == GameData.ToolMode.SELECT:
		return
	is_dragging = true
	active_index = pointer_index

func _to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _input(event):
	if not is_dragging:
		return

	if event is InputEventScreenDrag:
		active_index = event.index
		global_position = _to_world(event.position)
	elif event is InputEventMouseMotion:
		global_position = _to_world(event.position)

	var released := false
	if event is InputEventScreenTouch and not event.pressed:
		released = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		released = true

	if released:
		is_dragging = false
		active_index = -1
		_try_place()

func _inside_building_area(pos: Vector2) -> bool:
	var area = get_tree().get_first_node_in_group("building_area")
	if area == null:
		return false
	for child in area.get_children():
		if child is CollisionShape2D and child.shape:
			var local_pos = child.to_local(pos)
			if child.shape.get_rect().has_point(local_pos):
				return true
	return false

func _get_own_shape() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D and child.shape:
			return child
	return null

func _is_spot_free(pos: Vector2, own_shape: CollisionShape2D) -> bool:
	if not _inside_building_area(pos):
		return false

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = own_shape.shape
	params.transform = Transform2D(global_rotation, pos) * own_shape.transform
	params.collision_mask = collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = [get_rid()]

	var results := get_world_2d().direct_space_state.intersect_shape(params, 32)
	for result in results:
		var collider = result.collider
		if collider is Node and not collider.is_in_group("building_area"):
			return false
	return true

func _find_nearest_free_spot(origin: Vector2, own_shape: CollisionShape2D) -> Variant:
	var base := origin.snapped(Vector2(grid_size, grid_size))
	var candidates: Array[Vector2] = []

	for x in range(-max_search_cells, max_search_cells + 1):
		for y in range(-max_search_cells, max_search_cells + 1):
			candidates.append(base + Vector2(x, y) * grid_size)

	candidates.sort_custom(func(a, b): return a.distance_squared_to(origin) < b.distance_squared_to(origin))

	for candidate in candidates:
		if _is_spot_free(candidate, own_shape):
			return candidate
	return null

func _try_place():
	await get_tree().physics_frame

	if not is_inside_tree():
		return

	if not _inside_building_area(global_position):
		queue_free()
		return

	var own_shape := _get_own_shape()
	if own_shape == null:
		global_position = global_position.snapped(Vector2(grid_size, grid_size))
		return

	var spot = _find_nearest_free_spot(global_position, own_shape)
	if spot == null:
		queue_free()
	else:
		global_position = spot

func _input_event(_viewport, event, _shape_idx):
	if is_dragging:
		return

	var touch_press = (event is InputEventScreenTouch and event.pressed)
	var mouse_press = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)

	if touch_press or mouse_press:
		if GameData.current_tool == GameData.ToolMode.SELECT:
			if is_selectable:
				select_this_part()
		elif GameData.current_tool == GameData.ToolMode.DELETE:
			delete_this_part()
		elif touch_press:
			start_dragging(event.index)

func select_this_part():
	if GameData.selected_part and is_instance_valid(GameData.selected_part):
		for child in GameData.selected_part.find_children("*", "Sprite2D", true, false):
			child.modulate = Color(1, 1, 1)

	GameData.selected_part = self
	for child in find_children("*", "Sprite2D", true, false):
		child.modulate = Color(1.4, 1.4, 0.6)

	# Open configuration UI for any selectable part (thruster or wheel)
	var popup_ui = get_tree().current_scene.get_node_or_null("Properties")
	if popup_ui:
		if popup_ui.has_method("open_for_part"):
			popup_ui.open_for_part(self)
		elif popup_ui.has_method("open_for_thruster"):
			popup_ui.open_for_thruster(self)

func delete_this_part():
	if GameData.selected_part == self:
		GameData.selected_part = null
	queue_free()
