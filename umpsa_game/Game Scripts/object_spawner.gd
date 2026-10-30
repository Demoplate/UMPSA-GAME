extends Area2D

@export var scene_to_spawn: PackedScene
@export var spawn_target: Node2D # Drag a Marker2D or any Node2D here in the Inspector
@export var hold_duration: float = 3.0 # Seconds required to touch/stay in the area
@export var spawn_count: int = 1 # How many instances to spawn

var _is_holding: float = 0.0
var _is_touching: bool = false
var _has_triggered: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(_body: Node) -> void:
	if _has_triggered:
		return
	_is_touching = true

func _on_body_exited(_body: Node) -> void:
	_is_touching = false
	_is_holding = 0.0

func _process(delta: float) -> void:
	if _has_triggered:
		return
		
	if _is_touching:
		_is_holding += delta
		print("Holding time: ", snappedf(_is_holding, 0.1), " / ", hold_duration)
		
		if _is_holding >= hold_duration:
			_spawn_scenes()
			_has_triggered = true # Set to false or comment out if you want it to repeat

func _spawn_scenes() -> void:
	if not scene_to_spawn:
		print("ERROR: No scene assigned to spawn!")
		return
		
	if not spawn_target:
		print("ERROR: No spawn target node assigned!")
		return
	
	var base_position: Vector2 = spawn_target.global_position
	
	for i in range(spawn_count):
		var instance = scene_to_spawn.instantiate()
		
		if instance is Node2D:
			# If spawning multiple items, offsets each slightly so they don't stack directly on top of each other
			instance.global_position = base_position + Vector2(i * 15.0, 0.0)
			
		get_tree().current_scene.add_child(instance)
		
	print("Successfully spawned ", spawn_count, " instances at ", base_position)
