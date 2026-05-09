extends Node

var occupied_cells := {}
var occupied_cells_by_node := {}
var occupied_nodes_by_id := {}
var reserved_cells := {}
var reserved_cells_by_node := {}
var reserved_nodes_by_id := {}

@onready var grid_manager = get_tree().get_first_node_in_group("grid_manager")

func _ready():
	add_to_group("grid_occupancy_manager")

func register_node(node: Node2D):
	if node == null or not is_instance_valid(node):
		return

	update_node_occupancy(node)

func unregister_node(node: Node):
	release_node_occupancy(node)
	clear_node_reservations(node)

func update_node_occupancy(node: Node2D):
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")

	if grid_manager == null or node == null or not is_instance_valid(node):
		return

	release_node_occupancy(node)

	var node_id = get_node_reservation_id(node)
	var cells = grid_manager.get_footprint_cells_for_node(node)
	occupied_nodes_by_id[node_id] = node
	occupied_cells_by_node[node_id] = cells

	for cell in cells:
		occupied_cells[cell] = node_id

func release_node_occupancy(node: Node):
	var node_id = get_node_reservation_id(node)

	if node_id == -1 or not occupied_cells_by_node.has(node_id):
		return

	for cell in occupied_cells_by_node[node_id]:
		if occupied_cells.get(cell, -1) == node_id:
			occupied_cells.erase(cell)

	occupied_cells_by_node.erase(node_id)
	occupied_nodes_by_id.erase(node_id)

func get_node_reservation_id(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return -1

	return node.get_instance_id()

func get_cell_occupant_id(cell: Vector2i) -> int:
	return occupied_cells.get(cell, -1)

func is_cell_occupied(cell: Vector2i, ignored_node: Node = null) -> bool:
	var occupant_id = get_cell_occupant_id(cell)

	if occupant_id == -1:
		return false

	if occupant_id == get_node_reservation_id(ignored_node):
		return false

	return not _should_ignore_blocker(ignored_node, occupied_nodes_by_id.get(occupant_id, null))

func is_cell_reserved(cell: Vector2i, ignored_node: Node = null) -> bool:
	var owner_id = reserved_cells.get(cell, -1)

	if owner_id == -1:
		return false

	if _should_ignore_blocker(ignored_node, reserved_nodes_by_id.get(owner_id, null)):
		return false

	return owner_id != get_node_reservation_id(ignored_node)

func is_cell_blocked(cell: Vector2i, ignored_node: Node = null) -> bool:
	return is_cell_occupied(cell, ignored_node) or is_cell_reserved(cell, ignored_node)

func is_cell_blocked_for_destination(cell: Vector2i, ignored_node: Node = null) -> bool:
	return is_cell_occupied_for_destination(cell, ignored_node) or is_cell_reserved_for_destination(cell, ignored_node)

func is_cell_occupied_for_destination(cell: Vector2i, ignored_node: Node = null) -> bool:
	var occupant_id = get_cell_occupant_id(cell)

	if occupant_id == -1:
		return false

	var occupant = occupied_nodes_by_id.get(occupant_id, null)
	if _should_ignore_destination_blocker(ignored_node, cell, occupant):
		return false

	return occupant_id != get_node_reservation_id(ignored_node)

func is_cell_reserved_for_destination(cell: Vector2i, ignored_node: Node = null) -> bool:
	var owner_id = reserved_cells.get(cell, -1)

	if owner_id == -1:
		return false

	return owner_id != get_node_reservation_id(ignored_node)

func can_occupy_cells(cells: Array[Vector2i], ignored_node: Node = null) -> bool:
	for cell in cells:
		if is_cell_blocked(cell, ignored_node):
			return false

	return true

func can_occupy_world_position(world_position: Vector2, footprint_width: int, footprint_height: int, ignored_node: Node = null) -> bool:
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")

	if grid_manager == null:
		return true

	return can_occupy_cells(
		grid_manager.get_footprint_cells(world_position, footprint_width, footprint_height),
		ignored_node
	)

func reserve_cell(cell: Vector2i, node: Node):
	var node_id = get_node_reservation_id(node)

	if node_id == -1:
		return

	reserved_cells[cell] = node_id
	reserved_nodes_by_id[node_id] = node

	if not reserved_cells_by_node.has(node_id):
		reserved_cells_by_node[node_id] = []

	if not reserved_cells_by_node[node_id].has(cell):
		reserved_cells_by_node[node_id].append(cell)

func reserve_world_position(world_position: Vector2, node: Node):
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")

	if grid_manager == null:
		return

	clear_node_reservations(node)
	reserve_cell(grid_manager.world_to_cell(world_position), node)

func reserve_world_path(world_path: Array[Vector2], node: Node):
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")

	if grid_manager == null:
		return

	clear_node_reservations(node)

	for world_position in world_path:
		reserve_cell(grid_manager.world_to_cell(world_position), node)

func clear_node_reservations(node: Node):
	var node_id = get_node_reservation_id(node)

	if node_id == -1 or not reserved_cells_by_node.has(node_id):
		return

	for cell in reserved_cells_by_node[node_id]:
		if reserved_cells.get(cell, -1) == node_id:
			reserved_cells.erase(cell)

	reserved_cells_by_node.erase(node_id)
	reserved_nodes_by_id.erase(node_id)

func get_blocked_cell_lookup(ignored_node: Node = null) -> Dictionary:
	var blocked_cells := {}
	var ignored_node_id = get_node_reservation_id(ignored_node)

	for cell in occupied_cells.keys():
		if occupied_cells[cell] == ignored_node_id:
			continue

		if _should_ignore_blocker(ignored_node, occupied_nodes_by_id.get(occupied_cells[cell], null)):
			continue

		blocked_cells[cell] = true

	for cell in reserved_cells.keys():
		if reserved_cells[cell] == ignored_node_id:
			continue

		if _should_ignore_blocker(ignored_node, reserved_nodes_by_id.get(reserved_cells[cell], null)):
			continue

		if _can_move_over_blocking_occupancy(ignored_node):
			continue

		blocked_cells[cell] = true

	return blocked_cells

func get_cell_occupant_node(cell: Vector2i) -> Node2D:
	var occupant_id = get_cell_occupant_id(cell)

	if occupant_id == -1:
		return null

	return occupied_nodes_by_id.get(occupant_id, null) as Node2D

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
