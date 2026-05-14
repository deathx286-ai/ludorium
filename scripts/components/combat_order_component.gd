extends Node
class_name CombatOrderComponent

signal order_changed(order_type: int, stance: int)

enum OrderType {
	IDLE,
	MOVE,
	ATTACK_TARGET,
	ATTACK_MOVE,
	DEFEND_AREA,
	HOLD_POSITION,
	HARVEST
}

enum Stance {
	PASSIVE,
	DEFENSIVE,
	AGGRESSIVE
}

@export var stance: int = Stance.AGGRESSIVE
@export var auto_acquire_range_tiles: int = 0
@export var defend_radius_tiles: int = 6
@export var chase_leash_tiles: int = 10
@export var hold_position_attacks_in_range: bool = true

var order_type: int = OrderType.IDLE
var target: Node2D = null
var destination: Vector2 = Vector2.ZERO
var anchor_position: Vector2 = Vector2.ZERO
var has_destination: bool = false
var has_anchor_position: bool = false
var chase_target: bool = true

func set_stance(new_stance: int):
	stance = new_stance
	order_changed.emit(order_type, stance)

func set_anchor_position(new_anchor_position: Vector2):
	anchor_position = new_anchor_position
	has_anchor_position = true

func set_idle_order():
	order_type = OrderType.IDLE
	target = null
	has_destination = false
	chase_target = true
	order_changed.emit(order_type, stance)

func set_move_order(new_destination: Vector2):
	order_type = OrderType.MOVE
	target = null
	destination = new_destination
	has_destination = true
	chase_target = false
	order_changed.emit(order_type, stance)

func set_attack_target_order(new_target: Node2D, should_chase: bool = true):
	order_type = OrderType.ATTACK_TARGET
	target = new_target
	has_destination = false
	chase_target = should_chase
	order_changed.emit(order_type, stance)

func set_attack_move_order(new_destination: Vector2):
	order_type = OrderType.ATTACK_MOVE
	target = null
	destination = new_destination
	has_destination = true
	chase_target = true
	order_changed.emit(order_type, stance)

func set_harvest_order(resource_node: Node2D):
	order_type = OrderType.HARVEST
	target = resource_node
	has_destination = false
	chase_target = false
	order_changed.emit(order_type, stance)

func set_defend_area_order(new_anchor_position: Vector2, radius_tiles: int = -1):
	order_type = OrderType.DEFEND_AREA
	target = null
	anchor_position = new_anchor_position
	has_anchor_position = true
	has_destination = false
	chase_target = true

	if radius_tiles > 0:
		defend_radius_tiles = radius_tiles

	order_changed.emit(order_type, stance)

func set_hold_position_order(new_anchor_position: Vector2):
	order_type = OrderType.HOLD_POSITION
	target = null
	anchor_position = new_anchor_position
	has_anchor_position = true
	has_destination = false
	chase_target = false
	order_changed.emit(order_type, stance)

func has_valid_target() -> bool:
	return target != null and is_instance_valid(target)

func get_target() -> Node2D:
	if has_valid_target():
		return target

	target = null
	return null

func clear_target():
	target = null

	if order_type == OrderType.ATTACK_TARGET:
		set_idle_order()

func complete_current_order():
	if order_type == OrderType.ATTACK_MOVE:
		set_idle_order()
		return

	if order_type == OrderType.MOVE:
		set_idle_order()
		return

func allows_auto_acquire() -> bool:
	if stance == Stance.PASSIVE:
		return false

	match order_type:
		OrderType.IDLE:
			return true
		OrderType.ATTACK_MOVE:
			return true
		OrderType.DEFEND_AREA:
			return true
		OrderType.HOLD_POSITION:
			return hold_position_attacks_in_range
		_:
			return false

func allows_chase_target() -> bool:
	if stance == Stance.PASSIVE:
		return false

	match order_type:
		OrderType.IDLE:
			return stance == Stance.AGGRESSIVE
		OrderType.ATTACK_TARGET:
			return chase_target
		OrderType.ATTACK_MOVE:
			return true
		OrderType.DEFEND_AREA:
			return true
		_:
			return false

func get_auto_acquire_range_pixels(default_range_pixels: float, tile_size: float) -> float:
	if auto_acquire_range_tiles > 0:
		return float(auto_acquire_range_tiles) * tile_size

	return default_range_pixels

func is_world_position_allowed(world_position: Vector2, tile_size: float) -> bool:
	if order_type == OrderType.DEFEND_AREA and has_anchor_position:
		var defend_radius := float(defend_radius_tiles) * tile_size
		return anchor_position.distance_squared_to(world_position) <= defend_radius * defend_radius

	if order_type == OrderType.HOLD_POSITION and has_anchor_position:
		var chase_radius := float(chase_leash_tiles) * tile_size
		return anchor_position.distance_squared_to(world_position) <= chase_radius * chase_radius

	return true

func get_order_name() -> String:
	match order_type:
		OrderType.IDLE:
			return "Idle"
		OrderType.MOVE:
			return "Move"
		OrderType.ATTACK_TARGET:
			return "Attack Target"
		OrderType.ATTACK_MOVE:
			return "Attack Move"
		OrderType.DEFEND_AREA:
			return "Defend Area"
		OrderType.HOLD_POSITION:
			return "Hold Position"
		OrderType.HARVEST:
			return "Harvest"
		_:
			return "Unknown"

func get_stance_name() -> String:
	match stance:
		Stance.PASSIVE:
			return "Passive"
		Stance.DEFENSIVE:
			return "Defensive"
		Stance.AGGRESSIVE:
			return "Aggressive"
		_:
			return "Unknown"
