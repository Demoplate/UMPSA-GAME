extends Node2D

@export_file("*.tscn") var next_scene_path: String
@export var wait_time: float = 2.0

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play("CUTSCENE1ST")

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != "CUTSCENE1ST":
		return

	await get_tree().create_timer(wait_time).timeout

	if next_scene_path.is_empty():
		push_error("Next scene path is not assigned on the cutscene script!")
		return

	get_tree().change_scene_to_file(next_scene_path)
