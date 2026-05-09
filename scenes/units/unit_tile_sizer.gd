@tool
extends Node

@export var tile_width: int = 1:
	set(value):
		tile_width = max(value, 1)
		update_tile_sizing()

@export var tile_height: int = 1:
	set(value):
		tile_height = max(value, 1)
		update_tile_sizing()

@export var fallback_tile_size: int = 64:
	set(value):
		fallback_tile_size = max(value, 1)
		update_tile_sizing()

@export var sprite_size_multiplier: float = 1.0:
	set(value):
		sprite_size_multiplier = max(value, 0.1)
		update_tile_sizing()

@export var hitbox_size_multiplier: float = 1.0:
	set(value):
		hitbox_size_multiplier = max(value, 0.1)
		update_tile_sizing()

@export var movement_collision_size_multiplier: float = 0.35:
	set(value):
		movement_collision_size_multiplier = max(value, 0.05)
		update_tile_sizing()

@export var health_bar_width_multiplier: float = 1.0:
	set(value):
		health_bar_width_multiplier = max(value, 0.1)
		update_tile_sizing()

@export var snap_to_grid_in_editor: bool = true:
	set(value):
		snap_to_grid_in_editor = value
		update_tile_sizing()

@export var snap_to_grid_on_ready: bool = true

var cached_grid_manager: Node = null

func _ready():
	set_process(Engine.is_editor_hint())
	update_tile_sizing()

	if not Engine.is_editor_hint() and snap_to_grid_on_ready:
		var unit_root = get_unit_root()

		if unit_root != null:
			snap_unit_to_grid(unit_root)

func _process(_delta):
	if Engine.is_editor_hint():
		update_tile_sizing()

func get_unit_root() -> Node2D:
	var parent = get_parent()

	if parent is Node2D:
		return parent

	return null

func get_tile_size() -> int:
	var grid_manager = get_grid_manager()

	if grid_manager != null:
		return grid_manager.tile_size

	return fallback_tile_size

func get_base_pixel_size() -> Vector2:
	var tile_size = get_tile_size()

	return Vector2(
		tile_width * tile_size,
		tile_height * tile_size
	)

func update_tile_sizing():
	if not is_inside_tree():
		return

	var unit_root = get_unit_root()

	if unit_root == null:
		return

	var base_pixel_size = get_base_pixel_size()

	update_sprite_size(unit_root, base_pixel_size)
	update_movement_collision_size(unit_root, base_pixel_size)
	update_hitbox_size(unit_root, base_pixel_size)
	update_health_bar_size(unit_root, base_pixel_size)

	if Engine.is_editor_hint() and snap_to_grid_in_editor:
		snap_unit_to_grid(unit_root)

func update_sprite_size(unit_root: Node2D, base_pixel_size: Vector2):
	var sprite: Sprite2D = unit_root.get_node_or_null("Sprite2D")

	if sprite == null:
		return

	if sprite.texture == null:
		return

	var texture_size = sprite.texture.get_size()

	if texture_size.x <= 0 or texture_size.y <= 0:
		return

	var wanted_size = base_pixel_size * sprite_size_multiplier

	sprite.scale = Vector2(
		wanted_size.x / texture_size.x,
		wanted_size.y / texture_size.y
	)

	sprite.centered = true
	sprite.offset = Vector2.ZERO
	sprite.position = Vector2.ZERO
	
func update_movement_collision_size(unit_root: Node2D, base_pixel_size: Vector2):
	var collision: CollisionShape2D = unit_root.get_node_or_null("CollisionShape2D")

	if collision == null:
		return

	if collision.shape == null:
		collision.shape = RectangleShape2D.new()

	var wanted_size = base_pixel_size * movement_collision_size_multiplier

	if collision.shape is RectangleShape2D:
		collision.shape.size = wanted_size

	if collision.shape is CircleShape2D:
		collision.shape.radius = min(wanted_size.x, wanted_size.y) / 2.0

func update_hitbox_size(unit_root: Node2D, base_pixel_size: Vector2):
	var hitbox_collision: CollisionShape2D = unit_root.get_node_or_null("Hitbox/CollisionShape2D")

	if hitbox_collision == null:
		return

	if hitbox_collision.shape == null:
		hitbox_collision.shape = RectangleShape2D.new()

	var wanted_size = base_pixel_size * hitbox_size_multiplier

	if hitbox_collision.shape is RectangleShape2D:
		hitbox_collision.shape.size = wanted_size

	if hitbox_collision.shape is CircleShape2D:
		hitbox_collision.shape.radius = min(wanted_size.x, wanted_size.y) / 2.0

func update_health_bar_size(unit_root: Node2D, base_pixel_size: Vector2):
	var health_bar: ProgressBar = unit_root.get_node_or_null("HealthBar")

	if health_bar == null:
		return

	var wanted_width = base_pixel_size.x * health_bar_width_multiplier

	health_bar.position = Vector2(
		-wanted_width / 2.0,
		-base_pixel_size.y / 2.0 - 18.0
	)

	# ProgressBar has a minimum height, so size + scale makes it visually small.
	health_bar.size = Vector2(wanted_width * 2.0, 27.0)
	health_bar.scale = Vector2(0.5, 0.3)

func snap_unit_to_grid(unit_root: Node2D):
	var grid_manager = get_grid_manager()

	if grid_manager == null:
		return

	unit_root.global_position = grid_manager.snap_world_to_footprint_center(
		unit_root.global_position,
		tile_width,
		tile_height
	)

func get_grid_manager():
	if cached_grid_manager == null or not is_instance_valid(cached_grid_manager):
		cached_grid_manager = get_tree().get_first_node_in_group("grid_manager")

	return cached_grid_manager
