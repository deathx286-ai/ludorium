extends Node

@export var move_speed: float = 150.0
@export var waypoint_arrival_distance: float = 4.0
@export var snap_to_grid_on_ready: bool = true

var owner_body: Node2D = null
var movement_path: Array[Vector2] = []
var current_waypoint: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var last_completed_tile_position: Vector2 = Vector2.ZERO
var previous_tile_position: Vector2 = Vector2.ZERO
var active_waypoint_start_position: Vector2 = Vector2.ZERO
var is_moving: bool = false

@onready var grid_manager = get_tree().get_first_node_in_group("grid_manager")
@onready var occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")

func initialize(unit: Node2D, speed: float, arrival_distance: float):
	owner_body = unit
	move_speed = speed
	waypoint_arrival_distance = arrival_distance

	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")

	if occupancy_manager == null:
		occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")

	if owner_body == null:
		return

	if snap_to_grid_on_ready:
		owner_body.global_position = get_snapped_position(owner_body.global_position)

	current_waypoint = owner_body.global_position
	target_position = owner_body.global_position
	last_completed_tile_position = owner_body.global_position
	previous_tile_position = owner_body.global_position
	active_waypoint_start_position = owner_body.global_position

	register_occupancy()

func _exit_tree():
	clear_reservations()

	if occupancy_manager != null and owner_body != null:
		occupancy_manager.unregister_node(owner_body)

func physics_step(delta: float):
	if owner_body == null:
		return

	if not is_moving:
		set_owner_velocity(Vector2.ZERO)
		return

	if is_current_waypoint_blocked():
		redirect_to_blocked_waypoint_fallback()
		return

	if _is_within_arrival_distance(current_waypoint):
		complete_current_step()
		return

	move_axis_locked_to(current_waypoint, move_speed, delta)
	snap_to_current_waypoint_if_close()

func move_to_world_position(world_position: Vector2) -> bool:
	if owner_body == null or grid_manager == null:
		return false

	var resolved_position = get_resolved_move_destination(world_position)

	if resolved_position == Vector2.INF:
		return false

	var path = grid_manager.get_cardinal_cell_path(owner_body.global_position, resolved_position, owner_body)

	if path.is_empty():
		var current_cell = grid_manager.world_to_cell(owner_body.global_position)
		var resolved_cell = grid_manager.world_to_cell(resolved_position)

		if current_cell != resolved_cell:
			return false

		if not _is_within_arrival_distance(resolved_position):
			target_position = resolved_position
			set_path([resolved_position])
			return true

	target_position = resolved_position
	set_path(path)
	return true

func move_to_world_position_exact(world_position: Vector2) -> bool:
	if owner_body == null or grid_manager == null:
		return false

	var requested_cell = grid_manager.world_to_cell(world_position)

	if is_destination_cell_blocked(requested_cell):
		return false

	var resolved_position = grid_manager.cell_to_world(requested_cell)
	var path = grid_manager.get_cardinal_cell_path(owner_body.global_position, resolved_position, owner_body)

	if path.is_empty():
		var current_cell = grid_manager.world_to_cell(owner_body.global_position)

		if current_cell != requested_cell:
			return false

		if not _is_within_arrival_distance(resolved_position):
			target_position = resolved_position
			set_path([resolved_position])
			return true

	target_position = resolved_position
	set_path(path)
	return true

func move_one_step_to_world_position(world_position: Vector2) -> bool:
	var next_step = get_next_path_position_to(world_position)

	if next_step == Vector2.INF:
		return false

	return move_to_world_position(next_step)

func get_next_path_position_to(world_position: Vector2) -> Vector2:
	if owner_body == null or grid_manager == null:
		return world_position

	var path = grid_manager.get_cardinal_cell_path(owner_body.global_position, world_position, owner_body)

	if path.is_empty():
		if grid_manager.world_to_cell(owner_body.global_position) == grid_manager.world_to_cell(world_position):
			return grid_manager.snap_world_to_tile_center(world_position)

		return Vector2.INF

	return path[0]

func get_path_to_world_position(world_position: Vector2, blocked_cells: Dictionary = {}) -> Array[Vector2]:
	if owner_body == null or grid_manager == null:
		return []

	if blocked_cells.is_empty():
		return grid_manager.get_cardinal_cell_path(owner_body.global_position, world_position, owner_body)

	return grid_manager.get_cardinal_cell_path_with_blocked_lookup(
		owner_body.global_position,
		world_position,
		owner_body,
		blocked_cells
	)

func set_path(path: Array[Vector2]):
	clear_reservations()
	movement_path = path.duplicate()
	active_waypoint_start_position = get_snapped_position(owner_body.global_position)
	last_completed_tile_position = active_waypoint_start_position
	previous_tile_position = active_waypoint_start_position

	if movement_path.is_empty():
		is_moving = false
		current_waypoint = target_position
		snap_to_tile_center_if_close()
		update_occupancy()
		clear_owner_movement_ignore()
		return

	if can_move_over_blocking_occupancy():
		release_occupancy()

	current_waypoint = movement_path.pop_front()
	is_moving = true
	var reservation_path: Array[Vector2] = [current_waypoint]
	reservation_path.append_array(movement_path)
	reserve_path(reservation_path)

func stop(clear_reserved_cells: bool = true, snap_to_center: bool = true):
	if snap_to_center:
		snap_to_tile_center_if_close()

	is_moving = false
	movement_path.clear()
	set_owner_velocity(Vector2.ZERO)
	update_occupancy()

	if clear_reserved_cells:
		clear_reservations()

	clear_owner_movement_ignore()

func is_settled() -> bool:
	if owner_body == null:
		return true

	if is_moving:
		return false

	return snap_to_tile_center_if_close()

func is_committed_step_in_progress() -> bool:
	if owner_body == null:
		return false

	return is_moving and not _is_within_arrival_distance(current_waypoint)

func is_on_tile_center() -> bool:
	if owner_body == null or grid_manager == null:
		return true

	return _is_within_arrival_distance(get_snapped_position(owner_body.global_position))

func snap_to_tile_center_if_close() -> bool:
	if owner_body == null or grid_manager == null:
		return true

	var snapped_position = get_snapped_position(owner_body.global_position)

	if not _is_within_arrival_distance(snapped_position):
		return false

	owner_body.global_position = snapped_position
	set_owner_velocity(Vector2.ZERO)
	update_occupancy()
	return true

func settle_to_nearest_tile():
	if owner_body == null or grid_manager == null:
		return

	var settle_position = get_snapped_position(owner_body.global_position)

	if _is_within_arrival_distance(settle_position):
		owner_body.global_position = settle_position
		stop()
		update_occupancy()
		return

	target_position = settle_position
	set_path([settle_position])

func get_resolved_move_destination(requested_position: Vector2) -> Vector2:
	if grid_manager == null:
		return requested_position

	var requested_cell = grid_manager.world_to_cell(requested_position)

	if not is_destination_cell_blocked(requested_cell):
		return grid_manager.cell_to_world(requested_cell)

	return get_nearest_free_cell_around_blocked_target(requested_cell)

func get_nearest_free_cell_around_blocked_target(blocked_cell: Vector2i) -> Vector2:
	if grid_manager == null or owner_body == null:
		return Vector2.INF

	var current_cell = grid_manager.world_to_cell(owner_body.global_position)
	var best_cell = Vector2i(-1, -1)
	var best_distance = INF

	for neighbor_cell in grid_manager.get_neighbor_cells(blocked_cell, false):
		if neighbor_cell == current_cell:
			continue

		if is_destination_cell_blocked(neighbor_cell):
			continue

		var world_pos = grid_manager.cell_to_world(neighbor_cell)
		var path = grid_manager.get_cardinal_cell_path(owner_body.global_position, world_pos, owner_body)

		if path.is_empty() and not can_move_over_blocking_occupancy():
			continue

		var distance = owner_body.global_position.distance_squared_to(world_pos)

		if distance < best_distance:
			best_distance = distance
			best_cell = neighbor_cell

	if best_cell == Vector2i(-1, -1):
		return Vector2.INF

	return grid_manager.cell_to_world(best_cell)

func complete_current_step():
	previous_tile_position = active_waypoint_start_position
	owner_body.global_position = current_waypoint
	last_completed_tile_position = current_waypoint
	set_owner_velocity(Vector2.ZERO)

	if movement_path.is_empty():
		is_moving = false
		update_occupancy()
		clear_reservations()
		clear_owner_movement_ignore()
		return

	var next_waypoint = movement_path.front()

	if grid_manager != null and is_waypoint_blocked(next_waypoint, movement_path.size() == 1):
		movement_path.clear()
		is_moving = false
		update_occupancy()
		clear_reservations()
		return

	if not can_move_over_blocking_occupancy():
		update_occupancy()

	current_waypoint = movement_path.pop_front()
	active_waypoint_start_position = last_completed_tile_position

func is_current_waypoint_blocked() -> bool:
	if grid_manager == null or owner_body == null:
		return false

	var current_waypoint_cell = grid_manager.world_to_cell(current_waypoint)
	var current_cell = grid_manager.world_to_cell(owner_body.global_position)

	if current_waypoint_cell == current_cell:
		return false

	return is_waypoint_blocked(current_waypoint, movement_path.is_empty())

func redirect_to_blocked_waypoint_fallback():
	clear_reservations()
	movement_path.clear()
	set_owner_velocity(Vector2.ZERO)

	var fallback_position = get_best_blocked_move_fallback()

	if _is_within_arrival_distance(fallback_position):
		owner_body.global_position = fallback_position
		last_completed_tile_position = fallback_position
		active_waypoint_start_position = fallback_position
		is_moving = false
		update_occupancy()
		return

	current_waypoint = fallback_position
	target_position = fallback_position
	active_waypoint_start_position = get_snapped_position(owner_body.global_position)
	is_moving = true
	reserve_position(current_waypoint)

func get_best_blocked_move_fallback() -> Vector2:
	var candidates: Array[Vector2] = [
		last_completed_tile_position,
		active_waypoint_start_position,
		previous_tile_position,
		get_snapped_position(owner_body.global_position)
	]

	for candidate in candidates:
		var candidate_cell = grid_manager.world_to_cell(candidate)

		if not is_destination_cell_blocked(candidate_cell):
			return grid_manager.cell_to_world(candidate_cell)

	return previous_tile_position

func move_axis_locked_to(tile_target: Vector2, speed: float, delta: float):
	var offset = tile_target - owner_body.global_position
	var max_step = speed * delta
	var movement_axis = get_next_axis_to_target(tile_target, offset)

	if abs(offset.x) <= waypoint_arrival_distance:
		owner_body.global_position.x = tile_target.x
		offset.x = 0.0

	if abs(offset.y) <= waypoint_arrival_distance:
		owner_body.global_position.y = tile_target.y
		offset.y = 0.0

	if offset == Vector2.ZERO:
		set_owner_velocity(Vector2.ZERO)
		return

	if movement_axis == Vector2.RIGHT:
		owner_body.global_position.x += sign(offset.x) * min(abs(offset.x), max_step)
	else:
		owner_body.global_position.y += sign(offset.y) * min(abs(offset.y), max_step)

	set_owner_velocity(Vector2.ZERO)

func get_next_axis_to_target(tile_target: Vector2, offset: Vector2) -> Vector2:
	if grid_manager == null:
		if abs(offset.x) >= abs(offset.y):
			return Vector2.RIGHT

		return Vector2.DOWN

	var current_cell = grid_manager.world_to_cell(owner_body.global_position)
	var target_cell = grid_manager.world_to_cell(tile_target)
	var moving_horizontally = current_cell.x != target_cell.x
	var moving_vertically = current_cell.y != target_cell.y

	if moving_horizontally and abs(offset.y) > waypoint_arrival_distance:
		return Vector2.DOWN

	if moving_vertically and abs(offset.x) > waypoint_arrival_distance:
		return Vector2.RIGHT

	if abs(offset.x) > waypoint_arrival_distance:
		return Vector2.RIGHT

	return Vector2.DOWN

func snap_to_current_waypoint_if_close():
	if not is_moving:
		return

	if not _is_within_arrival_distance(current_waypoint):
		return

	owner_body.global_position = current_waypoint
	set_owner_velocity(Vector2.ZERO)

func get_snapped_position(world_position: Vector2) -> Vector2:
	if grid_manager == null:
		return world_position

	return grid_manager.snap_world_to_tile_center(world_position)

func reserve_path(path: Array[Vector2]):
	if path.is_empty():
		return

	if can_move_over_blocking_occupancy():
		reserve_position(path.back())
		return

	if grid_manager != null:
		grid_manager.reserve_world_path(path, owner_body)
		return

	if occupancy_manager != null:
		occupancy_manager.reserve_world_path(path, owner_body)

func reserve_position(world_position: Vector2):
	if not uses_grid_occupancy():
		return

	if grid_manager != null:
		grid_manager.reserve_world_position(world_position, owner_body)
		return

	if occupancy_manager != null:
		occupancy_manager.reserve_world_position(world_position, owner_body)

func clear_reservations():
	if not uses_grid_occupancy():
		return

	if grid_manager != null:
		grid_manager.clear_node_reservations(owner_body)
		return

	if occupancy_manager != null:
		occupancy_manager.clear_node_reservations(owner_body)

func register_occupancy():
	if not uses_grid_occupancy():
		return

	if occupancy_manager != null and owner_body != null:
		occupancy_manager.register_node(owner_body)

func update_occupancy():
	if not uses_grid_occupancy():
		return

	if occupancy_manager != null and owner_body != null:
		occupancy_manager.update_node_occupancy(owner_body)

func release_occupancy():
	if occupancy_manager != null and owner_body != null and occupancy_manager.has_method("release_node_occupancy"):
		occupancy_manager.release_node_occupancy(owner_body)

func uses_grid_occupancy() -> bool:
	if owner_body == null:
		return true

	if owner_body.has_method("uses_grid_occupancy"):
		return bool(owner_body.call("uses_grid_occupancy"))

	return true

func can_move_over_blocking_occupancy() -> bool:
	if owner_body == null:
		return false

	if owner_body.has_method("can_move_over_blocking_structures"):
		return bool(owner_body.call("can_move_over_blocking_structures"))

	return false

func is_destination_cell_blocked(cell: Vector2i) -> bool:
	if grid_manager == null:
		return false

	if grid_manager.has_method("is_cell_blocked_for_destination"):
		return grid_manager.is_cell_blocked_for_destination(cell, owner_body)

	return grid_manager.is_cell_blocked(cell, owner_body)

func is_waypoint_blocked(world_position: Vector2, is_final_waypoint: bool) -> bool:
	if grid_manager == null:
		return false

	var cell = grid_manager.world_to_cell(world_position)

	if can_move_over_blocking_occupancy():
		return is_final_waypoint and is_destination_cell_blocked(cell)

	return grid_manager.is_cell_blocked(cell, owner_body)

func set_owner_velocity(new_velocity: Vector2):
	if owner_body != null and owner_body is CharacterBody2D:
		(owner_body as CharacterBody2D).velocity = new_velocity

func clear_owner_movement_ignore():
	if owner_body != null and owner_body.has_method("clear_movement_ignore_nodes"):
		owner_body.call("clear_movement_ignore_nodes")

func _is_within_arrival_distance(world_position: Vector2) -> bool:
	if owner_body == null:
		return true

	return owner_body.global_position.distance_squared_to(world_position) <= waypoint_arrival_distance * waypoint_arrival_distance
