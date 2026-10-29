extends Node

@export var scene_to_spawn: PackedScene
@export var spawn_positions: Array[Vector2] = []
@export var fade_duration: float = 1.0

var _has_spawned: bool = false
var _initial_check_done: bool = false

func _ready() -> void:
	child_exiting_tree.connect(_on_child_exiting_tree)
	
	await get_tree().process_frame
	_initial_check_done = true
	_check_if_empty()

func _on_child_exiting_tree(_node: Node) -> void:
	if not _initial_check_done or _has_spawned:
		return
	call_deferred("_check_if_empty")

func _check_if_empty() -> void:
	if _has_spawned:
		return
	
	if get_child_count() == 0:
		_spawn_scenes()

func _spawn_scenes() -> void:
	if _has_spawned or not scene_to_spawn:
		return
	_has_spawned = true
	
	for pos in spawn_positions:
		var instance = scene_to_spawn.instantiate()
		
		if instance is Node2D:
			instance.global_position = pos
			
		if instance is CanvasItem:
			var start_color = instance.modulate
			start_color.a = 0.0
			instance.modulate = start_color
			
			get_parent().add_child(instance)
			
			var tween := create_tween()
			tween.tween_property(instance, "modulate:a", 1.0, fade_duration)
		else:
			get_parent().add_child(instance)
		
	print("All items cleared! Spawned packed scenes at defined positions.")
