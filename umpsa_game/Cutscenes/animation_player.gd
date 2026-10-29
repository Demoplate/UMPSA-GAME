extends Node2D

# Reference your AnimationPlayer node
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	# Play the animation by its exact name in the AnimationPlayer panel
	animation_player.play("CUTSCENE1ST")
