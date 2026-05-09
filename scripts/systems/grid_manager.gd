@tool

extends Node2D

@export var tile_size: int = 64:
	set(value):
		tile_size = value
		queue_redraw()

@export var grid_width: int = 50:
	set(value):
		grid_width = value
		queue_redraw()

@export var grid_height: int = 35:
	set(value):
		grid_height = value
		queue_redraw()

@export var show_grid: bool = true:
	set(value):
		show_grid = value
		queue_redraw()

@export var grid_color: Color = Color(1.0, 1.0, 1.0, 0.25):
	set(value):
		grid_color = value
		queue_redraw()

@export var major_grid_color: Color = Color(1.0, 1.0, 1.0, 0.45):
	set(value):
		major_grid_color = value
		queue_redraw()

@export var keep_grid_lines_screen_width: bool = true:
	set(value):
		keep_grid_lines_screen_width = value
		queue_redraw()

@export var max_pathfinding_cells: int = 500

const CARDINAL_DIRECTIONS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1)
]

const DIAGONAL_DIRECTIONS := [
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1)
]

var reserved_cells := {}
var reserved_nodes_by_id := {}
var occupancy_manager: Node = null

func _ready():
	occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")
	queue_redraw()

func get_map_width() -> int:
	return grid_width * tile_size

func get_map_height() -> int:
	return grid_height * tile_size

func get_left_bound() -> float:
	return -get_map_width() / 2.0

func get_right_bound() -> float:
	return get_map_width() / 2.0

func get_top_bound() -> float:
	return -get_map_height() / 2.0

func get_bottom_bound() -> float:
	return get_map_height() / 2.0

func _draw():
	if not show_grid:
		return

	var left = get_left_bound()
	var right = get_right_bound()
	var top = get_top_bound()
	var bottom = get_bottom_bound()
	var line_width = -1.0 if keep_grid_lines_screen_width else 1.0

	# Vertical grid lines
	for x in range(grid_width + 1):
		var line_x = left + x * tile_size
		var color = major_grid_color if x % 5 == 0 else grid_color
		draw_line(
			Vector2(line_x, top),
			Vector2(line_x, bottom),
			color,
			line_width
		)

	# Horizontal grid lines
	for y in range(grid_height + 1):
		var line_y = top + y * tile_size
		var color = major_grid_color if y % 5 == 0 else grid_color
		draw_line(
			Vector2(left, line_y),
			Vector2(right, line_y),
			color,
			line_width
		)

func world_to_cell(world_position: Vector2) -> Vector2i:
	var local_position = to_local(world_position)
	var left = get_left_bound()
	var top = get_top_bound()

	var local_x = local_position.x - left
	var local_y = local_position.y - top

	var cell_x = floori(local_x / tile_size)
	var cell_y = floori(local_y / tile_size)

	cell_x = clamp(cell_x, 0, grid_width - 1)
	cell_y = clamp(cell_y, 0, grid_height - 1)

	return Vector2i(cell_x, cell_y)

func cell_to_world(cell: Vector2i) -> Vector2:
	var left = get_left_bound()
	var top = get_top_bound()

	var local_position = Vector2(
		left + cell.x * tile_size + tile_size / 2.0,
		top + cell.y * tile_size + tile_size / 2.0
	)

	return to_global(local_position)

func snap_world_to_tile_center(world_position: Vector2) -> Vector2:
	var cell = world_to_cell(world_position)
	return cell_to_world(cell)

func get_footprint_anchor_cell(world_position: Vector2, footprint_width: int, footprint_height: int) -> Vector2i:
	footprint_width = maxi(footprint_width, 1)
	footprint_height = maxi(footprint_height, 1)

	var local_position = to_local(world_position)
	var left = get_left_bound()
	var top = get_top_bound()

	var local_x = (local_position.x - left) / tile_size
	var local_y = (local_position.y - top) / tile_size

	var anchor_x = roundi(local_x - float(footprint_width) / 2.0)
	var anchor_y = roundi(local_y - float(footprint_height) / 2.0)

	anchor_x = clampi(anchor_x, 0, grid_width - footprint_width)
	anchor_y = clampi(anchor_y, 0, grid_height - footprint_height)

	return Vector2i(anchor_x, anchor_y)

func footprint_anchor_to_world(anchor_cell: Vector2i, footprint_width: int, footprint_height: int) -> Vector2:
	footprint_width = maxi(footprint_width, 1)
	footprint_height = maxi(footprint_height, 1)

	var left = get_left_bound()
	var top = get_top_bound()

	var local_position = Vector2(
		left + (float(anchor_cell.x) + float(footprint_width) / 2.0) * tile_size,
		top + (float(anchor_cell.y) + float(footprint_height) / 2.0) * tile_size
	)

	return to_global(local_position)

func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height

func get_neighbor_cells(cell: Vector2i, include_diagonals: bool = true) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []

	for direction in CARDINAL_DIRECTIONS:
		var neighbor = cell + direction

		if is_cell_in_bounds(neighbor):
			neighbors.append(neighbor)

	if include_diagonals:
		for direction in DIAGONAL_DIRECTIONS:
			var neighbor = cell + direction

			if is_cell_in_bounds(neighbor):
				neighbors.append(neighbor)

	return neighbors

func get_cells_in_tile_range(center_cell: Vector2i, range_tiles: int, include_center: bool = false) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	range_tiles = maxi(range_tiles, 0)

	for y in range(-range_tiles, range_tiles + 1):
		for x in range(-range_tiles, range_tiles + 1):
			if x == 0 and y == 0 and not include_center:
				continue

			if maxi(abs(x), abs(y)) > range_tiles:
				continue

			var cell = center_cell + Vector2i(x, y)

			if is_cell_in_bounds(cell):
				cells.append(cell)

	return cells

func get_occupying_nodes() -> Array[Node2D]:
	var unique_nodes := {}
	var occupying_nodes: Array[Node2D] = []
	var groups = ["player", "enemy"]

	for group_name in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue

			if not node is Node2D:
				continue

			var node_id = node.get_instance_id()

			if unique_nodes.has(node_id):
				continue

			unique_nodes[node_id] = true
			occupying_nodes.append(node)

	return occupying_nodes

func get_node_footprint_size(node: Node2D) -> Vector2i:
	if node.has_method("get_tile_footprint_size"):
		var footprint_size = node.get_tile_footprint_size()
		return Vector2i(
			maxi(footprint_size.x, 1),
			maxi(footprint_size.y, 1)
		)

	var tile_sizer = node.get_node_or_null("UnitTileSizer")

	if tile_sizer != null:
		var tile_width = int(tile_sizer.get("tile_width"))
		var tile_height = int(tile_sizer.get("tile_height"))

		return Vector2i(
			maxi(tile_width, 1),
			maxi(tile_height, 1)
		)

	return Vector2i.ONE

func get_footprint_cells_for_node(node: Node2D) -> Array[Vector2i]:
	var footprint_size = get_node_footprint_size(node)
	return get_footprint_cells(node.global_position, footprint_size.x, footprint_size.y)

func get_footprint_cells(world_position: Vector2, footprint_width: int, footprint_height: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var anchor_cell = get_footprint_anchor_cell(world_position, footprint_width, footprint_height)

	for y in range(footprint_height):
		for x in range(footprint_width):
			var cell = anchor_cell + Vector2i(x, y)

			if is_cell_in_bounds(cell):
				cells.append(cell)

	return cells

func get_cell_occupant(cell: Vector2i, ignored_node: Node = null) -> Node2D:
	for node in get_occupying_nodes():
		if node == ignored_node:
			continue

		if _should_ignore_blocker(ignored_node, node):
			continue

		if get_footprint_cells_for_node(node).has(cell):
			return node

	return null

func get_cell_occupant_for_destination(cell: Vector2i, ignored_node: Node = null) -> Node2D:
	for node in get_occupying_nodes():
		if node == ignored_node:
			continue

		if not get_footprint_cells_for_node(node).has(cell):
			continue

		if _should_ignore_destination_blocker(ignored_node, cell, node):
			continue

		return node

	return null

func is_cell_occupied(cell: Vector2i, ignored_node: Node = null) -> bool:
	var occupancy = get_occupancy_manager()

	if occupancy != null:
		return occupancy.is_cell_occupied(cell, ignored_node)

	return get_cell_occupant(cell, ignored_node) != null

func get_node_reservation_id(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return -1

	return node.get_instance_id()

func clear_node_reservations(node: Node):
	var occupancy = get_occupancy_manager()

	if occupancy != null:
		occupancy.clear_node_reservations(node)

	var reservation_id = get_node_reservation_id(node)

	if reservation_id == -1:
		return

	var cells_to_remove: Array[Vector2i] = []

	for cell in reserved_cells.keys():
		if reserved_cells[cell] == reservation_id:
			cells_to_remove.append(cell)

	for cell in cells_to_remove:
		reserved_cells.erase(cell)

	reserved_nodes_by_id.erase(reservation_id)

func reserve_cell(cell: Vector2i, node: Node):
	var occupancy = get_occupancy_manager()

	if occupancy != null:
		occupancy.reserve_cell(cell, node)

	var reservation_id = get_node_reservation_id(node)

	if reservation_id == -1:
		return

	reserved_cells[cell] = reservation_id
	reserved_nodes_by_id[reservation_id] = node

func reserve_world_path(world_path: Array[Vector2], node: Node):
	var occupancy = get_occupancy_manager()

	if occupancy != null:
		occupancy.reserve_world_path(world_path, node)

	clear_node_reservations(node)

	for world_position in world_path:
		reserve_cell(world_to_cell(world_position), node)

func reserve_world_position(world_position: Vector2, node: Node):
	var occupancy = get_occupancy_manager()

	if occupancy != null:
		occupancy.reserve_world_position(world_position, node)

	clear_node_reservations(node)
	reserve_cell(world_to_cell(world_position), node)

func get_cell_reservation_owner(cell: Vector2i) -> int:
	return reserved_cells.get(cell, -1)

func is_cell_reserved(cell: Vector2i, ignored_node: Node = null) -> bool:
	var occupancy = get_occupancy_manager()

	if occupancy != null:
		return occupancy.is_cell_reserved(cell, ignored_node)

	var owner_id = get_cell_reservation_owner(cell)

	if owner_id == -1:
		return false

	if _should_ignore_blocker(ignored_node, reserved_nodes_by_id.get(owner_id, null)):
		return false

	return owner_id != get_node_reservation_id(ignored_node)

func is_cell_blocked(cell: Vector2i, ignored_node: Node = null) -> bool:
	return is_cell_occupied(cell, ignored_node) or is_cell_reserved(cell, ignored_node)

func is_cell_blocked_for_destination(cell: Vector2i, ignored_node: Node = null) -> bool:
	var occupancy = get_occupancy_manager()

	if occupancy != null and occupancy.has_method("is_cell_blocked_for_destination"):
		return occupancy.is_cell_blocked_for_destination(cell, ignored_node)

	return get_cell_occupant_for_destination(cell, ignored_node) != null or is_cell_reserved_for_destination(cell, ignored_node)

func is_cell_reserved_for_destination(cell: Vector2i, ignored_node: Node = null) -> bool:
	var owner_id = get_cell_reservation_owner(cell)

	if owner_id == -1:
		return false

	return owner_id != get_node_reservation_id(ignored_node)

func is_footprint_occupied(world_position: Vector2, footprint_width: int, footprint_height: int, ignored_node: Node = null) -> bool:
	for cell in get_footprint_cells(world_position, footprint_width, footprint_height):
		if is_cell_blocked(cell, ignored_node):
			return true

	return false

func get_direct_cell_path(
	from_world_position: Vector2,
	to_world_position: Vector2,
	include_diagonals: bool = false,
	ignored_node: Node = null,
	stop_before_occupied: bool = false
) -> Array[Vector2]:
	var from_cell = world_to_cell(from_world_position)
	var to_cell = world_to_cell(to_world_position)
	var path: Array[Vector2] = []
	var current_cell = from_cell
	var prefer_horizontal = true

	while current_cell != to_cell:
		var step_x = int(sign(to_cell.x - current_cell.x))
		var step_y = int(sign(to_cell.y - current_cell.y))

		if not include_diagonals:
			var can_step_horizontal = step_x != 0
			var can_step_vertical = step_y != 0

			if prefer_horizontal and can_step_horizontal:
				step_y = 0
			elif can_step_vertical:
				step_x = 0
			elif can_step_horizontal:
				step_y = 0

			prefer_horizontal = not prefer_horizontal

		current_cell += Vector2i(step_x, step_y)

		if stop_before_occupied and is_cell_blocked(current_cell, ignored_node):
			break

		path.append(cell_to_world(current_cell))

	return path

func get_cardinal_cell_path(
	from_world_position: Vector2,
	to_world_position: Vector2,
	ignored_node: Node = null
) -> Array[Vector2]:
	return get_cardinal_cell_path_with_blocked_lookup(
		from_world_position,
		to_world_position,
		ignored_node,
		get_blocked_cell_lookup(ignored_node)
	)

func get_cardinal_cell_path_with_blocked_lookup(
	from_world_position: Vector2,
	to_world_position: Vector2,
	_ignored_node: Node,
	blocked_cells: Dictionary
) -> Array[Vector2]:
	var start_cell = world_to_cell(from_world_position)
	var target_cell = world_to_cell(to_world_position)

	return cell_path_to_world_path(
		find_cardinal_cell_path_with_blocked_lookup(start_cell, target_cell, blocked_cells)
	)

func find_cardinal_cell_path(start_cell: Vector2i, target_cell: Vector2i, ignored_node: Node = null) -> Array[Vector2i]:
	return find_cardinal_cell_path_with_blocked_lookup(
		start_cell,
		target_cell,
		get_blocked_cell_lookup(ignored_node)
	)

func find_cardinal_cell_path_with_blocked_lookup(
	start_cell: Vector2i,
	target_cell: Vector2i,
	blocked_cells: Dictionary
) -> Array[Vector2i]:
	if start_cell == target_cell:
		return []

	var frontier: Array[Vector2i] = [start_cell]
	var came_from := {}
	var searched_cell_count = 0
	came_from[start_cell] = start_cell

	var frontier_index = 0

	while frontier_index < frontier.size():
		searched_cell_count += 1

		if searched_cell_count > max_pathfinding_cells:
			break

		var current_cell = frontier[frontier_index]
		frontier_index += 1

		if current_cell == target_cell:
			break

		for direction in CARDINAL_DIRECTIONS:
			var next_cell = current_cell + direction

			if not is_cell_in_bounds(next_cell):
				continue

			if came_from.has(next_cell):
				continue

			if next_cell != target_cell and blocked_cells.has(next_cell):
				continue

			came_from[next_cell] = current_cell
			frontier.append(next_cell)

	if not came_from.has(target_cell):
		return []

	var reversed_path: Array[Vector2i] = []
	var current_cell = target_cell

	while current_cell != start_cell:
		reversed_path.append(current_cell)
		current_cell = came_from[current_cell]

	reversed_path.reverse()
	return reversed_path

func find_nearest_reachable_cell_in_lookup(
	start_cell: Vector2i,
	candidate_cells: Dictionary,
	blocked_cells: Dictionary
) -> Vector2i:
	if candidate_cells.is_empty():
		return Vector2i(-1, -1)

	if candidate_cells.has(start_cell) and not blocked_cells.has(start_cell):
		return start_cell

	var frontier: Array[Vector2i] = [start_cell]
	var came_from := {}
	var searched_cell_count = 0
	came_from[start_cell] = start_cell

	var frontier_index = 0

	while frontier_index < frontier.size():
		searched_cell_count += 1

		if searched_cell_count > max_pathfinding_cells:
			break

		var current_cell = frontier[frontier_index]
		frontier_index += 1

		for direction in CARDINAL_DIRECTIONS:
			var next_cell = current_cell + direction

			if not is_cell_in_bounds(next_cell):
				continue

			if came_from.has(next_cell):
				continue

			if blocked_cells.has(next_cell):
				continue

			if candidate_cells.has(next_cell):
				return next_cell

			came_from[next_cell] = current_cell
			frontier.append(next_cell)

	return Vector2i(-1, -1)

func get_blocked_cell_lookup(ignored_node: Node = null) -> Dictionary:
	var occupancy = get_occupancy_manager()

	if occupancy != null:
		return occupancy.get_blocked_cell_lookup(ignored_node)

	var blocked_cells := {}

	for node in get_occupying_nodes():
		if node == ignored_node:
			continue

		if _should_ignore_blocker(ignored_node, node):
			continue

		for cell in get_footprint_cells_for_node(node):
			blocked_cells[cell] = true

	var ignored_reservation_id = get_node_reservation_id(ignored_node)

	for cell in reserved_cells.keys():
		if reserved_cells[cell] == ignored_reservation_id:
			continue

		if _should_ignore_blocker(ignored_node, reserved_nodes_by_id.get(reserved_cells[cell], null)):
			continue

		if _can_move_over_blocking_occupancy(ignored_node):
			continue

		blocked_cells[cell] = true

	return blocked_cells

func has_blocking_structure_between_nodes(attacker: Node2D, defender: Node2D) -> bool:
	if attacker == null or defender == null:
		return false

	var attacker_cells = get_footprint_cells_for_node(attacker)
	var defender_cells = get_footprint_cells_for_node(defender)

	if attacker_cells.is_empty() or defender_cells.is_empty():
		return false

	var attacker_cell = _get_closest_cell_to_cells(attacker_cells, defender_cells)
	var defender_cell = _get_closest_cell_to_cells(defender_cells, attacker_cells)
	var excluded_cells := {}

	for cell in attacker_cells:
		excluded_cells[cell] = true

	for cell in defender_cells:
		excluded_cells[cell] = true

	for cell in get_line_cells(attacker_cell, defender_cell):
		if excluded_cells.has(cell):
			continue

		var occupant = get_cell_occupant_node(cell)
		if _is_structure_blocker(occupant):
			return true

	return false

func get_cell_occupant_node(cell: Vector2i) -> Node2D:
	var occupancy = get_occupancy_manager()

	if occupancy != null and occupancy.has_method("get_cell_occupant_node"):
		return occupancy.get_cell_occupant_node(cell)

	return get_cell_occupant(cell)

func get_line_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var step_count = maxi(abs(to_cell.x - from_cell.x), abs(to_cell.y - from_cell.y))

	if step_count == 0:
		var single_cell: Array[Vector2i] = [from_cell]
		return single_cell

	for step in range(step_count + 1):
		var t = float(step) / float(step_count)
		var cell = Vector2i(
			roundi(lerpf(from_cell.x, to_cell.x, t)),
			roundi(lerpf(from_cell.y, to_cell.y, t))
		)

		if cells.is_empty() or cells.back() != cell:
			cells.append(cell)

	return cells

func _get_closest_cell_to_cells(cells: Array[Vector2i], target_cells: Array[Vector2i]) -> Vector2i:
	var closest_cell = cells[0]
	var closest_distance = INF

	for cell in cells:
		for target_cell in target_cells:
			var distance = abs(cell.x - target_cell.x) + abs(cell.y - target_cell.y)

			if distance < closest_distance:
				closest_distance = distance
				closest_cell = cell

	return closest_cell

func _should_ignore_blocker(moving_node: Node, blocker_node: Node) -> bool:
	if moving_node == null or blocker_node == null or not is_instance_valid(blocker_node):
		return false

	if moving_node.has_method("should_ignore_movement_blocker"):
		if bool(moving_node.call("should_ignore_movement_blocker", blocker_node)):
			return true

	return _can_move_over_blocking_occupancy(moving_node)

func _should_ignore_destination_blocker(moving_node: Node, cell: Vector2i, blocker_node: Node) -> bool:
	if moving_node == null or blocker_node == null or not is_instance_valid(blocker_node):
		return false

	if moving_node.has_method("should_ignore_destination_blocker"):
		if bool(moving_node.call("should_ignore_destination_blocker", cell, blocker_node)):
			return true

	return false

func _can_move_over_blocking_occupancy(node: Node) -> bool:
	if node == null:
		return false

	if not node.has_method("can_move_over_blocking_structures"):
		return false

	return bool(node.call("can_move_over_blocking_structures"))

func _is_structure_blocker(node: Node) -> bool:
	if node == null:
		return false

	var building_data = _get_property_or_null(node, "building_data")
	if building_data != null:
		return true

	var unit_data = _get_property_or_null(node, "unit_data")
	if unit_data != null and bool(unit_data.get("is_structure")):
		return true

	var classification = node.get_node_or_null("UnitClassification") as UnitClassification
	return classification != null and classification.is_structure()

func _get_property_or_null(object: Object, property_name: String):
	if object == null:
		return null

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return object.get(property_name)

	return null

func cell_path_to_world_path(cell_path: Array[Vector2i]) -> Array[Vector2]:
	var world_path: Array[Vector2] = []

	for cell in cell_path:
		world_path.append(cell_to_world(cell))

	return world_path

func snap_world_to_footprint_center(world_position: Vector2, footprint_width: int, footprint_height: int) -> Vector2:
	var anchor_cell = get_footprint_anchor_cell(world_position, footprint_width, footprint_height)
	return footprint_anchor_to_world(anchor_cell, footprint_width, footprint_height)

func get_occupancy_manager():
	if occupancy_manager == null or not is_instance_valid(occupancy_manager):
		occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")

	return occupancy_manager
