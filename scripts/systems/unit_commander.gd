extends Node
class_name UnitCommander

const GROUP_ORDER_NONE := 0
const GROUP_ORDER_MOVE := 1
const GROUP_ORDER_ATTACK_MOVE := 2
const GROUP_ORDER_ATTACK_TARGET := 3
const GROUP_ORDER_HARVEST := 4
const ATTACK_CELL_NONE := Vector2i(-1, -1)
const ATTACK_CELL_NO_SLOT_REQUIRED := Vector2i(-2, -2)

@export var grid_manager: Node
@export var defend_radius_tiles: int = 6

var active_group_order_type: int = GROUP_ORDER_NONE
var active_group_units: Array[Node2D] = []
var active_group_destinations := {}
var active_group_preferred_target: Node2D = null

func _ready():
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")

	set_physics_process(false)

func _physics_process(_delta):
	update_active_group_order()

func command_move_units(units: Array, destination: Vector2):
	var valid_units = get_valid_units(units)
	cancel_active_group_order()

	if valid_units.size() > 1:
		start_group_move_order(valid_units, destination, GROUP_ORDER_MOVE)
		return

	for unit in valid_units:
		if unit.has_method("command_move_to_position"):
			unit.call("command_move_to_position", destination)

func command_attack_units(units: Array, target: Node2D):
	var valid_units = get_valid_units(units)
	cancel_active_group_order()

	if target == null or not is_instance_valid(target):
		return

	if valid_units.size() > 1:
		start_group_attack_target_order(valid_units, target)
		return

	for unit in valid_units:
		if unit.has_method("command_attack_target"):
			unit.call("command_attack_target", target, true)

func command_attack_move_units(units: Array, destination: Vector2):
	var valid_units = get_valid_units(units)
	cancel_active_group_order()

	if valid_units.size() > 1:
		start_group_move_order(valid_units, destination, GROUP_ORDER_ATTACK_MOVE)
		return

	for unit in valid_units:
		if unit.has_method("command_attack_move_to_position"):
			unit.call("command_attack_move_to_position", destination)

func command_harvest_units(units: Array, resource_node: Node2D):
	var valid_units = get_valid_units(units)
	cancel_active_group_order()

	if resource_node == null or not is_instance_valid(resource_node):
		return

	for unit in valid_units:
		if unit.has_method("command_harvest_resource_node"):
			unit.call("command_harvest_resource_node", resource_node)

func command_stop_units(units: Array):
	cancel_active_group_order()

	for unit in get_valid_units(units):
		if unit.has_method("command_stop"):
			unit.call("command_stop")

func command_hold_units(units: Array):
	cancel_active_group_order()

	for unit in get_valid_units(units):
		if unit.has_method("command_hold_position"):
			unit.call("command_hold_position")

func command_defend_units(units: Array):
	cancel_active_group_order()

	for unit in get_valid_units(units):
		if unit.has_method("command_defend_area"):
			unit.call("command_defend_area", unit.global_position, defend_radius_tiles)

func cancel_orders_for_units(units: Array):
	for unit in units:
		if active_group_units.has(unit):
			cancel_active_group_order()
			return

func get_valid_units(units: Array) -> Array[Node2D]:
	var valid_units: Array[Node2D] = []

	for unit in units:
		if is_instance_valid(unit) and unit is Node2D:
			valid_units.append(unit)

	return valid_units

func start_group_move_order(units: Array[Node2D], destination: Vector2, order_type: int, preferred_target: Node2D = null):
	if units.is_empty():
		return

	var snapped_destination = destination
	if grid_manager != null and grid_manager.has_method("snap_world_to_tile_center"):
		snapped_destination = grid_manager.snap_world_to_tile_center(destination)

	active_group_order_type = order_type
	active_group_preferred_target = preferred_target
	active_group_units = units
	active_group_destinations.clear()
	set_physics_process(true)
	clear_group_reservations(units)

	if grid_manager == null:
		for unit in active_group_units:
			active_group_destinations[unit.get_instance_id()] = snapped_destination
			if unit.has_method("command_move_to_position"):
				unit.call("command_move_to_position", snapped_destination)
		return

	var group_plan = get_group_move_plan(units, snapped_destination)
	if group_plan.is_empty():
		finish_active_group_order()
		return

	active_group_destinations = group_plan.get("destinations", {})
	issue_group_path(group_plan)

func start_group_attack_target_order(units: Array[Node2D], target: Node2D):
	var destination = get_group_attack_target_destination(units, target)
	start_group_move_order(units, destination, GROUP_ORDER_ATTACK_TARGET, target)

func update_active_group_order():
	if active_group_order_type == GROUP_ORDER_NONE:
		return

	prune_active_group_units()
	if active_group_units.is_empty():
		cancel_active_group_order(false)
		return

	if not are_group_units_finished_moving():
		return

	finish_active_group_order()

func finish_active_group_order():
	var completed_order_type = active_group_order_type
	var completed_units = active_group_units.duplicate()
	var preferred_target = active_group_preferred_target
	var assigned_attack_cells := {}

	cancel_active_group_order(false)

	if completed_order_type == GROUP_ORDER_MOVE:
		for unit in completed_units:
			if is_instance_valid(unit) and unit.has_method("clear_movement_ignore_nodes"):
				unit.call("clear_movement_ignore_nodes")
		return

	for unit in completed_units:
		if not is_instance_valid(unit):
			continue

		if unit.has_method("clear_movement_ignore_nodes"):
			unit.call("clear_movement_ignore_nodes")

		var target: Node2D = null
		var attack_cell: Vector2i = ATTACK_CELL_NONE
		if completed_order_type == GROUP_ORDER_ATTACK_TARGET and preferred_target != null:
			attack_cell = get_claimable_attack_cell_for_unit(unit, preferred_target, assigned_attack_cells)
			if attack_cell != ATTACK_CELL_NONE:
				target = preferred_target

		if target == null:
			var target_assignment = get_nearest_reachable_attack_target_assignment_for_unit(unit, assigned_attack_cells)
			var assigned_target = target_assignment.get("target", null)
			if assigned_target is Node2D:
				target = assigned_target

			var assigned_cell = target_assignment.get("attack_cell", ATTACK_CELL_NONE)
			if assigned_cell is Vector2i:
				attack_cell = assigned_cell

		if target != null and unit.has_method("command_attack_target"):
			if attack_cell != ATTACK_CELL_NONE and attack_cell != ATTACK_CELL_NO_SLOT_REQUIRED and unit.has_method("command_attack_target_from_position") and grid_manager != null:
				if bool(unit.call("command_attack_target_from_position", target, grid_manager.cell_to_world(attack_cell), true)):
					claim_attack_cell(attack_cell, assigned_attack_cells)
					continue

			if bool(unit.call("command_attack_target", target, true)):
				claim_attack_cell(attack_cell, assigned_attack_cells)
				continue

		if unit.has_method("command_hold_position"):
			unit.call("command_hold_position")
		elif unit.has_method("command_stop"):
			unit.call("command_stop")

func cancel_active_group_order(clear_ignore_nodes: bool = true):
	if clear_ignore_nodes:
		for unit in active_group_units:
			if is_instance_valid(unit) and unit.has_method("clear_movement_ignore_nodes"):
				unit.call("clear_movement_ignore_nodes")

	active_group_order_type = GROUP_ORDER_NONE
	active_group_units.clear()
	active_group_destinations.clear()
	active_group_preferred_target = null
	set_physics_process(false)

func clear_group_reservations(units: Array[Node2D]):
	for unit in units:
		if is_instance_valid(unit) and unit.has_method("clear_grid_reservations"):
			unit.call("clear_grid_reservations")

func get_group_move_plan(units: Array[Node2D], destination: Vector2) -> Dictionary:
	var selected_cells := {}
	var unit_cells := {}
	var min_cell = Vector2i(999999, 999999)
	var max_cell = Vector2i(-999999, -999999)

	for unit in units:
		if not is_instance_valid(unit):
			continue

		var cell = grid_manager.world_to_cell(unit.global_position)
		unit_cells[unit.get_instance_id()] = cell

		for footprint_cell in grid_manager.get_footprint_cells_for_node(unit):
			selected_cells[footprint_cell] = true
			min_cell.x = mini(min_cell.x, footprint_cell.x)
			min_cell.y = mini(min_cell.y, footprint_cell.y)
			max_cell.x = maxi(max_cell.x, footprint_cell.x)
			max_cell.y = maxi(max_cell.y, footprint_cell.y)

	if selected_cells.is_empty():
		return {}

	var start_anchor = min_cell
	var shape_offsets: Array[Vector2i] = []

	for selected_cell in selected_cells.keys():
		shape_offsets.append(selected_cell - start_anchor)

	var max_shape_offset = max_cell - start_anchor
	var anchor_unit = get_closest_unit_to_position(units, destination)
	var anchor_offset = Vector2i.ZERO

	if anchor_unit != null and unit_cells.has(anchor_unit.get_instance_id()):
		anchor_offset = unit_cells[anchor_unit.get_instance_id()] - start_anchor

	var requested_cell = grid_manager.world_to_cell(destination)
	var target_anchor = clamp_group_anchor_cell(requested_cell - anchor_offset, max_shape_offset)
	var blocked_cells = get_blocked_cells_for_group(units)
	var anchor_path = find_group_footprint_path(start_anchor, target_anchor, shape_offsets, max_shape_offset, blocked_cells)

	if anchor_path.is_empty() and start_anchor != target_anchor:
		target_anchor = find_nearest_reachable_group_anchor(start_anchor, target_anchor, shape_offsets, max_shape_offset, blocked_cells)
		if target_anchor == Vector2i(-1, -1):
			return {}

		anchor_path = find_group_footprint_path(start_anchor, target_anchor, shape_offsets, max_shape_offset, blocked_cells)
		if anchor_path.is_empty() and start_anchor != target_anchor:
			return {}

	var destinations := {}
	var paths := {}

	for unit in units:
		var unit_id = unit.get_instance_id()
		if not unit_cells.has(unit_id):
			continue

		var offset: Vector2i = unit_cells[unit_id] - start_anchor
		var unit_path: Array[Vector2] = []

		for anchor_cell in anchor_path:
			unit_path.append(grid_manager.cell_to_world(anchor_cell + offset))

		var destination_cell = target_anchor + offset
		destinations[unit_id] = grid_manager.cell_to_world(destination_cell)
		paths[unit_id] = unit_path

	return {
		"destinations": destinations,
		"paths": paths
	}

func issue_group_path(group_plan: Dictionary):
	var paths: Dictionary = group_plan.get("paths", {})
	var units_to_ignore = active_group_units.duplicate()

	for unit in active_group_units:
		if not is_instance_valid(unit):
			continue

		var unit_id = unit.get_instance_id()
		if not active_group_destinations.has(unit_id):
			continue

		var destination: Vector2 = active_group_destinations[unit_id]
		var path: Array[Vector2] = []

		if paths.has(unit_id):
			for path_position in paths[unit_id]:
				if path_position is Vector2:
					path.append(path_position)

		if unit.has_method("command_group_move_along_path"):
			unit.call("command_group_move_along_path", path, destination)
		elif unit.has_method("command_move_to_position"):
			unit.call("command_move_to_position", destination)

		if unit.has_method("set_movement_ignore_nodes"):
			unit.call("set_movement_ignore_nodes", units_to_ignore)

func find_group_footprint_path(start_anchor: Vector2i, target_anchor: Vector2i, shape_offsets: Array[Vector2i], max_shape_offset: Vector2i, blocked_cells: Dictionary) -> Array[Vector2i]:
	if start_anchor == target_anchor:
		return []

	var frontier: Array[Vector2i] = [start_anchor]
	var came_from := {}
	came_from[start_anchor] = start_anchor
	var frontier_index = 0
	var searched_cell_count = 0
	var search_limit = int(grid_manager.get("max_pathfinding_cells")) if has_property(grid_manager, "max_pathfinding_cells") else 500

	while frontier_index < frontier.size():
		searched_cell_count += 1
		if searched_cell_count > search_limit:
			break

		var current_anchor = frontier[frontier_index]
		frontier_index += 1

		if current_anchor == target_anchor:
			break

		for direction in get_cardinal_directions():
			var next_anchor = current_anchor + direction

			if came_from.has(next_anchor):
				continue

			if not is_group_footprint_anchor_walkable(next_anchor, shape_offsets, max_shape_offset, blocked_cells):
				continue

			came_from[next_anchor] = current_anchor
			frontier.append(next_anchor)

	if not came_from.has(target_anchor):
		return []

	var reversed_path: Array[Vector2i] = []
	var current = target_anchor

	while current != start_anchor:
		reversed_path.append(current)
		current = came_from[current]

	reversed_path.reverse()
	return reversed_path

func find_nearest_reachable_group_anchor(start_anchor: Vector2i, preferred_anchor: Vector2i, shape_offsets: Array[Vector2i], max_shape_offset: Vector2i, blocked_cells: Dictionary) -> Vector2i:
	if is_group_footprint_anchor_walkable(preferred_anchor, shape_offsets, max_shape_offset, blocked_cells):
		return preferred_anchor

	var frontier: Array[Vector2i] = [start_anchor]
	var came_from := {}
	came_from[start_anchor] = start_anchor
	var frontier_index = 0
	var searched_cell_count = 0
	var search_limit = int(grid_manager.get("max_pathfinding_cells")) if has_property(grid_manager, "max_pathfinding_cells") else 500
	var best_anchor = start_anchor
	var best_distance = get_cell_distance_squared(start_anchor, preferred_anchor)

	while frontier_index < frontier.size():
		searched_cell_count += 1
		if searched_cell_count > search_limit:
			break

		var current_anchor = frontier[frontier_index]
		frontier_index += 1
		var distance = get_cell_distance_squared(current_anchor, preferred_anchor)

		if distance < best_distance:
			best_distance = distance
			best_anchor = current_anchor

		for direction in get_cardinal_directions():
			var next_anchor = current_anchor + direction

			if came_from.has(next_anchor):
				continue

			if not is_group_footprint_anchor_walkable(next_anchor, shape_offsets, max_shape_offset, blocked_cells):
				continue

			came_from[next_anchor] = current_anchor
			frontier.append(next_anchor)

	return best_anchor

func get_cell_distance_squared(a: Vector2i, b: Vector2i) -> int:
	var offset = a - b
	return offset.x * offset.x + offset.y * offset.y

func is_group_footprint_anchor_walkable(anchor_cell: Vector2i, shape_offsets: Array[Vector2i], max_shape_offset: Vector2i, blocked_cells: Dictionary) -> bool:
	if anchor_cell.x < 0 or anchor_cell.y < 0:
		return false

	if anchor_cell.x + max_shape_offset.x >= int(grid_manager.get("grid_width")):
		return false

	if anchor_cell.y + max_shape_offset.y >= int(grid_manager.get("grid_height")):
		return false

	for offset in shape_offsets:
		if blocked_cells.has(anchor_cell + offset):
			return false

	return true

func get_blocked_cells_for_group(units: Array[Node2D]) -> Dictionary:
	var blocked_cells = grid_manager.get_blocked_cell_lookup()

	for unit in units:
		if not is_instance_valid(unit):
			continue

		for cell in grid_manager.get_footprint_cells_for_node(unit):
			blocked_cells.erase(cell)

	return blocked_cells

func clamp_group_anchor_cell(anchor_cell: Vector2i, max_shape_offset: Vector2i) -> Vector2i:
	var max_x = int(grid_manager.get("grid_width")) - max_shape_offset.x - 1
	var max_y = int(grid_manager.get("grid_height")) - max_shape_offset.y - 1

	return Vector2i(
		clampi(anchor_cell.x, 0, maxi(max_x, 0)),
		clampi(anchor_cell.y, 0, maxi(max_y, 0))
	)

func get_cardinal_directions() -> Array[Vector2i]:
	return [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

func get_closest_unit_to_position(units: Array[Node2D], position: Vector2) -> Node2D:
	var closest_unit: Node2D = null
	var closest_distance_squared = INF

	for unit in units:
		if not is_instance_valid(unit):
			continue

		var distance_squared = unit.global_position.distance_squared_to(position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_unit = unit

	return closest_unit

func get_group_attack_target_destination(units: Array[Node2D], target: Node2D) -> Vector2:
	var anchor_unit = get_closest_unit_to_position(units, target.global_position)
	if anchor_unit != null and anchor_unit.has_method("get_best_chase_cell_near_target") and grid_manager != null:
		var chase_cell: Vector2i = anchor_unit.call("get_best_chase_cell_near_target", target)
		if chase_cell != Vector2i(-1, -1):
			return grid_manager.cell_to_world(chase_cell)

	if grid_manager != null and grid_manager.has_method("snap_world_to_tile_center"):
		return grid_manager.snap_world_to_tile_center(target.global_position)

	return target.global_position

func prune_active_group_units():
	var valid_units: Array[Node2D] = []

	for unit in active_group_units:
		if is_instance_valid(unit) and active_group_destinations.has(unit.get_instance_id()):
			valid_units.append(unit)

	active_group_units = valid_units

func are_group_units_finished_moving() -> bool:
	for unit in active_group_units:
		if not is_instance_valid(unit):
			continue

		var movement_component = unit.get_node_or_null("TileMovementComponent")
		if movement_component != null and bool(movement_component.get("is_moving")):
			return false

	return true

func get_nearest_reachable_attack_target_for_unit(unit: Node2D) -> Node2D:
	var assignment = get_nearest_reachable_attack_target_assignment_for_unit(unit, {})
	var target = assignment.get("target", null)
	if target is Node2D:
		return target

	return null

func get_nearest_reachable_attack_target_assignment_for_unit(unit: Node2D, assigned_attack_cells: Dictionary) -> Dictionary:
	var closest_target: Node2D = null
	var closest_distance_squared = INF
	var closest_attack_cell = ATTACK_CELL_NONE

	for candidate in get_attack_candidates_for_unit(unit):
		if not candidate is Node2D:
			continue

		var target = candidate as Node2D
		if not is_attack_candidate_valid_for_unit(unit, target):
			continue

		var attack_cell = get_claimable_attack_cell_for_unit(unit, target, assigned_attack_cells)
		if attack_cell == ATTACK_CELL_NONE:
			continue

		var distance_squared = unit.global_position.distance_squared_to(target.global_position)
		if distance_squared >= closest_distance_squared:
			continue

		closest_distance_squared = distance_squared
		closest_target = target
		closest_attack_cell = attack_cell

	return {
		"target": closest_target,
		"attack_cell": closest_attack_cell
	}

func get_claimable_attack_cell_for_unit(unit: Node2D, target: Node2D, assigned_attack_cells: Dictionary) -> Vector2i:
	if target == null or not is_instance_valid(target):
		return ATTACK_CELL_NONE

	if not is_attack_candidate_valid_for_unit(unit, target):
		return ATTACK_CELL_NONE

	if unit.has_method("is_target_in_attack_tile_range") and bool(unit.call("is_target_in_attack_tile_range", target)):
		var current_cell = get_unit_cell(unit)
		if current_cell == ATTACK_CELL_NONE:
			return ATTACK_CELL_NO_SLOT_REQUIRED

		return current_cell

	if unit.has_method("get_best_chase_cell_near_target"):
		var attack_cell: Vector2i = unit.call("get_best_chase_cell_near_target", target)
		if attack_cell == ATTACK_CELL_NONE:
			return ATTACK_CELL_NONE

		if assigned_attack_cells.has(attack_cell):
			return get_alternate_attack_cell_for_unit(unit, target, assigned_attack_cells)

		return attack_cell

	return ATTACK_CELL_NO_SLOT_REQUIRED

func get_alternate_attack_cell_for_unit(unit: Node2D, target: Node2D, assigned_attack_cells: Dictionary) -> Vector2i:
	if grid_manager == null:
		return ATTACK_CELL_NONE

	var target_cells = grid_manager.get_footprint_cells_for_node(target)
	if target_cells.is_empty():
		return ATTACK_CELL_NONE

	var range_tiles = 1
	if unit.has_method("get_attack_range_tile_count"):
		range_tiles = maxi(int(unit.call("get_attack_range_tile_count")), 1)

	var blocked_cells = grid_manager.get_blocked_cell_lookup(unit)
	var candidate_cells := {}

	for target_cell in target_cells:
		for candidate_cell in grid_manager.get_cells_in_tile_range(target_cell, range_tiles, false):
			if blocked_cells.has(candidate_cell):
				continue

			if assigned_attack_cells.has(candidate_cell):
				continue

			candidate_cells[candidate_cell] = true

	if candidate_cells.is_empty():
		return ATTACK_CELL_NONE

	return grid_manager.find_nearest_reachable_cell_in_lookup(
		grid_manager.world_to_cell(unit.global_position),
		candidate_cells,
		blocked_cells
	)

func claim_attack_cell(attack_cell: Vector2i, assigned_attack_cells: Dictionary):
	if attack_cell == ATTACK_CELL_NONE or attack_cell == ATTACK_CELL_NO_SLOT_REQUIRED:
		return

	assigned_attack_cells[attack_cell] = true

func get_unit_cell(unit: Node2D) -> Vector2i:
	if grid_manager == null or unit == null or not is_instance_valid(unit):
		return ATTACK_CELL_NONE

	return grid_manager.world_to_cell(unit.global_position)

func get_attack_candidates_for_unit(unit: Node2D) -> Array[Node]:
	if unit.has_method("get_attack_target_candidates"):
		var candidates: Array[Node] = []

		for candidate in unit.call("get_attack_target_candidates"):
			if candidate is Node:
				candidates.append(candidate)

		return candidates

	return get_tree().get_nodes_in_group("enemy")

func is_attack_candidate_valid_for_unit(unit: Node2D, target: Node2D) -> bool:
	if unit.has_method("is_valid_attack_candidate"):
		return bool(unit.call("is_valid_attack_candidate", target))

	return target != null and is_instance_valid(target) and target.has_method("take_damage")

func can_unit_reach_attack_target(unit: Node2D, target: Node2D) -> bool:
	if unit.has_method("is_target_in_attack_tile_range") and bool(unit.call("is_target_in_attack_tile_range", target)):
		return true

	if unit.has_method("get_best_chase_cell_near_target"):
		return unit.call("get_best_chase_cell_near_target", target) != Vector2i(-1, -1)

	return true

func has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return true

	return false
