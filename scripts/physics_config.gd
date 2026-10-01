extends Resource

@export var width: float = 600.0
@export var height: float = 1000.0
@export var puck_radius: float = 18.0
@export var paddle_radius: float = 44.0
@export var paddle_speed: float = 1050.0
@export var paddle_acceleration: float = 40000.0
@export var puck_speed: float = 2300.0
@export var puck_damping: float = 0.08
@export var paddle_mass: float = 5.0
@export var goal_width: float = 220.0
@export var stall_seconds: float = 5.0
@export var action_ticks: int = 4

func fingerprint() -> String:
	return FileAccess.get_sha256("res://resources/physics.tres")
