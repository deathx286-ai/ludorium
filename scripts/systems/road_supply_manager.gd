extends Node2D
class_name RoadSupplyManager

@export var grid_manager: Node
@export var grid_occupancy_manager: Node
@export var default_supply_radius_tiles: int = 12
@export var default_outpost_network_range_tiles: int = 50
@export var default_min_anchor_distance_tiles: int = 25

@export_group("Debug Overlay")
@export var debug_enabled: bool = true:
	set(value):
		debug_enabled = value
		queue_redraw()
@export var show_supply_radius: bool = true:
	set(value):
		show_supply_radius = value
		queue_redraw()
@export var show_road_network: bool = true:
	set(value):
		show_road_network = value
		queue_redraw()
@export var show_outpost_range: bool = false:
	set(value):
		show_outpost_range = value
		queue_redraw()
@export var show_valid_cells: bool = false:
	set(value):
		show_valid_cells = value
		queue_redraw()

var road_cells_by_nation: Dictionary = {}
var gate_cells_by_nation: Dictionary = {}
var anchor_cells_by_nation: Dictionary = {}
var anchors_by_nation: Dictionary = {}
var buildings_by_id: Dictionary = {}
var last_validation_result: Dictionary = {}

func _ready():
	add_to_group("road_supply_manager")

	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")
	if grid_occupancy_manager == null:
		grid_occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")

	rebuild_from_scene()

func _draw():
	if not debug_enabled or grid_manager == null:
		return

	if show_supply_radius:
		_draw_supply_radii()

	if show_outpost_range:
		_draw_outpost_ranges()

	if show_road_network:
		_draw_cell_network(road_cells_by_nation, Color(0.95, 0.78, 0.22, 0.5))
		_draw_cell_network(gate_cells_by_nation, Color(0.35, 0.75, 1.0, 0.45))

	if show_valid_cells:
		_draw_valid_debug_cells()

func rebuild_from_scene():
	road_cells_by_nation.clear()
	gate_cells_by_nation.clear()
	anchor_cells_by_nation.clear()
	anchors_by_nation.clear()
	buildings_by_id.clear()

	if not is_inside_tree():
		return

	for node in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("ally") + get_tree().get_nodes_in_group("enemy") + get_tree().get_nodes_in_group("neutral"):
		if is_instance_valid(node) and node is Node2D and _get_property_or_null(node, "building_data") != null:
			register_building(node)

	queue_redraw()

func register_building(building: Node2D, building_data: Resource = null, owner_nation: Resource = null):
	if building == null or not is_instance_valid(building):
		return

	if building_data == null:
		building_data = _get_property_or_null(building, "building_data")

	if building_data == null:
		return

	if owner_nation == null:
		owner_nation = _get_owner_nation(building)

	var nation_key = get_nation_key(owner_nation)
	if nation_key.is_empty():
		return

	if _is_under_construction(building):
		return

	var building_kind = EconomyTypes.get_building_kind_for_data(building_data)
	var footprint_cells = _get_footprint_cells_for_node(building)
	buildings_by_id[building.get_instance_id()] = {
		"node": building,
		"nation_key": nation_key,
		"building_kind": building_kind,
		"cells": footprint_cells
	}

	if building_kind == EconomyTypes.BuildingKind.ROAD:
		_ensure_cell_dictionary(road_cells_by_nation, nation_key)
		for cell in footprint_cells:
			road_cells_by_nation[nation_key][cell] = true
	elif building_kind == EconomyTypes.BuildingKind.GATE:
		_ensure_cell_dictionary(gate_cells_by_nation, nation_key)
		for cell in footprint_cells:
			gate_cells_by_nation[nation_key][cell] = true
	elif EconomyTypes.is_supply_anchor_kind(building_kind):
		_register_anchor(nation_key, building, building_data, footprint_cells, building_kind)

	queue_redraw()

func unregister_building(building: Node):
	if building == null:
		return

	var node_id = building.get_instance_id()
	if not buildings_by_id.has(node_id):
		return

	rebuild_from_scene()

func validate_building_placement(building_data: Resource, owner_nation: Resource, placement_cell: Vector2i, ignore_rules: bool = false, ignored_node: Node = null) -> Dictionary:
	if building_data == null:
		return _validation(false, EconomyTypes.PlacementFailure.MISSING_BUILDING_DATA)

	var nation_key = get_nation_key(owner_nation)
	if nation_key.is_empty():
		return _validation(false, EconomyTypes.PlacementFailure.INVALID_OWNER_NATION)

	if grid_manager == null:
		return _validation(false, EconomyTypes.PlacementFailure.INVALID_TERRAIN)

	var footprint_width = maxi(int(building_data.get("footprint_width")), 1)
	var footprint_height = maxi(int(building_data.get("footprint_height")), 1)
	var anchor_cell = _get_anchor_cell_for_placement_cell(placement_cell, footprint_width, footprint_height)
	var footprint_cells = _get_footprint_cells_from_anchor(anchor_cell, footprint_width, footprint_height)
	var building_kind = EconomyTypes.get_building_kind_for_data(building_data)

	if building_kind == EconomyTypes.BuildingKind.AUTO:
		return _validation(false, EconomyTypes.PlacementFailure.UNSUPPORTED_BUILDING_TYPE)

	if ignore_rules:
		return _validation(true, EconomyTypes.PlacementFailure.OK, anchor_cell, footprint_cells)

	if not _are_cells_in_bounds(footprint_cells):
		return _validation(false, EconomyTypes.PlacementFailure.INVALID_TERRAIN, anchor_cell, footprint_cells)

	if _is_footprint_occupied(footprint_cells, ignored_node):
		return _validation(false, EconomyTypes.PlacementFailure.OCCUPIED_CELL, anchor_cell, footprint_cells)

	if _does_footprint_overlap_resource_node(footprint_cells):
		return _validation(false, EconomyTypes.PlacementFailure.RESOURCE_NODE_COLLISION, anchor_cell, footprint_cells)

	match building_kind:
		EconomyTypes.BuildingKind.CAPITAL:
			return _validation(true, EconomyTypes.PlacementFailure.OK, anchor_cell, footprint_cells)
		EconomyTypes.BuildingKind.OUTPOST:
			return _validate_outpost(building_data, nation_key, anchor_cell, footprint_cells)
		EconomyTypes.BuildingKind.ROAD:
			return _validate_road(nation_key, anchor_cell, footprint_cells)
		EconomyTypes.BuildingKind.WALL:
			return _validate_inside_supply_only(nation_key, anchor_cell, footprint_cells)
		EconomyTypes.BuildingKind.GATE:
			return _validate_inside_supply_only(nation_key, anchor_cell, footprint_cells)
		_:
			return _validate_normal_building(nation_key, anchor_cell, footprint_cells)

func is_cell_inside_supply(nation, cell: Vector2i) -> bool:
	var nation_key = get_nation_key(nation)
	return is_cell_inside_supply_by_key(nation_key, cell)

func is_cell_inside_supply_by_key(nation_key: String, cell: Vector2i) -> bool:
	for anchor in anchors_by_nation.get(nation_key, []):
		var anchor_cell: Vector2i = anchor.get("cell", Vector2i(-999, -999))
		var radius = int(anchor.get("radius", default_supply_radius_tiles))
		if _get_tile_distance(anchor_cell, cell) <= radius:
			return true

	return false

func is_footprint_inside_supply(nation_key: String, footprint_cells: Array[Vector2i]) -> bool:
	for cell in footprint_cells:
		if not is_cell_inside_supply_by_key(nation_key, cell):
			return false

	return true

func is_adjacent_to_valid_road(nation, footprint_cells: Array[Vector2i]) -> bool:
	var nation_key = get_nation_key(nation)
	return _is_adjacent_to_cell_dictionary(footprint_cells, road_cells_by_nation.get(nation_key, {}))

func is_road_connected(nation, footprint_cells: Array[Vector2i]) -> bool:
	var nation_key = get_nation_key(nation)
	return _has_adjacent_connector(nation_key, footprint_cells)

func can_place_outpost_near_network(nation, anchor_cell: Vector2i, range_tiles: int = -1) -> bool:
	var nation_key = get_nation_key(nation)
	var effective_range = default_outpost_network_range_tiles if range_tiles < 0 else range_tiles
	return _is_within_connected_road_range(nation_key, anchor_cell, effective_range)

func is_outpost_too_close_to_anchor(nation, anchor_cell: Vector2i, min_distance_tiles: int = -1) -> bool:
	var nation_key = get_nation_key(nation)
	var effective_distance = default_min_anchor_distance_tiles if min_distance_tiles < 0 else min_distance_tiles
	return _is_too_close_to_anchor(nation_key, anchor_cell, effective_distance)

func get_debug_state() -> Dictionary:
	var anchor_count = 0
	var road_count = 0

	for nation_key in anchors_by_nation.keys():
		anchor_count += anchors_by_nation[nation_key].size()

	for nation_key in road_cells_by_nation.keys():
		road_count += road_cells_by_nation[nation_key].size()

	return {
		"anchors": anchor_count,
		"roads": road_count,
		"show_supply_radius": show_supply_radius,
		"show_road_network": show_road_network,
		"show_outpost_range": show_outpost_range,
		"show_valid_cells": show_valid_cells,
		"last_validation": last_validation_result.duplicate(true)
	}

func get_current_debug_summary() -> String:
	var state = get_debug_state()
	var last_reason = "none"
	if not last_validation_result.is_empty():
		last_reason = str(last_validation_result.get("reason", "valid"))

	return "Supply Anchors: %s | Roads: %s | Last: %s" % [
		int(state.get("anchors", 0)),
		int(state.get("roads", 0)),
		last_reason
	]

func get_nation_key(nation) -> String:
	if nation == null:
		return ""

	if nation is Resource:
		var nation_id = str(nation.get("nation_id"))
		if not nation_id.is_empty():
			return nation_id

	if nation is String:
		return str(nation)

	return str(nation)

func _validate_road(nation_key: String, anchor_cell: Vector2i, footprint_cells: Array[Vector2i]) -> Dictionary:
	if not is_footprint_inside_supply(nation_key, footprint_cells):
		return _validation(false, EconomyTypes.PlacementFailure.OUTSIDE_SUPPLY_RADIUS, anchor_cell, footprint_cells)

	if not _has_adjacent_connector(nation_key, footprint_cells):
		return _validation(false, EconomyTypes.PlacementFailure.ROAD_NOT_CONNECTED, anchor_cell, footprint_cells)

	return _validation(true, EconomyTypes.PlacementFailure.OK, anchor_cell, footprint_cells)

func _validate_normal_building(nation_key: String, anchor_cell: Vector2i, footprint_cells: Array[Vector2i]) -> Dictionary:
	if not is_footprint_inside_supply(nation_key, footprint_cells):
		return _validation(false, EconomyTypes.PlacementFailure.OUTSIDE_SUPPLY_RADIUS, anchor_cell, footprint_cells)

	if not _is_adjacent_to_cell_dictionary(footprint_cells, road_cells_by_nation.get(nation_key, {})):
		return _validation(false, EconomyTypes.PlacementFailure.NOT_ADJACENT_TO_ROAD, anchor_cell, footprint_cells)

	return _validation(true, EconomyTypes.PlacementFailure.OK, anchor_cell, footprint_cells)

func _validate_inside_supply_only(nation_key: String, anchor_cell: Vector2i, footprint_cells: Array[Vector2i]) -> Dictionary:
	if not is_footprint_inside_supply(nation_key, footprint_cells):
		return _validation(false, EconomyTypes.PlacementFailure.OUTSIDE_SUPPLY_RADIUS, anchor_cell, footprint_cells)

	return _validation(true, EconomyTypes.PlacementFailure.OK, anchor_cell, footprint_cells)

func _validate_outpost(building_data: Resource, nation_key: String, anchor_cell: Vector2i, footprint_cells: Array[Vector2i]) -> Dictionary:
	var min_anchor_distance = maxi(int(_get_property_or_default(building_data, "minimum_anchor_distance_tiles", default_min_anchor_distance_tiles)), 0)
	var network_range = maxi(int(_get_property_or_default(building_data, "outpost_network_range_tiles", default_outpost_network_range_tiles)), 0)

	if _is_too_close_to_anchor(nation_key, anchor_cell, min_anchor_distance):
		return _validation(false, EconomyTypes.PlacementFailure.OUTPOST_TOO_CLOSE_TO_ANCHOR, anchor_cell, footprint_cells)

	if not _is_within_connected_road_range(nation_key, anchor_cell, network_range):
		return _validation(false, EconomyTypes.PlacementFailure.MISSING_REQUIRED_ROAD_CONNECTION, anchor_cell, footprint_cells)

	return _validation(true, EconomyTypes.PlacementFailure.OK, anchor_cell, footprint_cells)

func _register_anchor(nation_key: String, building: Node2D, building_data: Resource, footprint_cells: Array[Vector2i], building_kind: int):
	if not anchors_by_nation.has(nation_key):
		anchors_by_nation[nation_key] = []
	if not anchor_cells_by_nation.has(nation_key):
		anchor_cells_by_nation[nation_key] = {}

	var anchor_cell = grid_manager.world_to_cell(building.global_position) if grid_manager != null else Vector2i.ZERO
	var radius = int(_get_property_or_default(building_data, "supply_radius_tiles", default_supply_radius_tiles))

	anchors_by_nation[nation_key].append({
		"cell": anchor_cell,
		"node": building,
		"radius": radius,
		"building_kind": building_kind
	})

	for cell in footprint_cells:
		anchor_cells_by_nation[nation_key][cell] = true

func _get_anchor_cell_for_placement_cell(cell: Vector2i, footprint_width: int, footprint_height: int) -> Vector2i:
	var world_position = grid_manager.cell_to_world(cell)
	return grid_manager.get_footprint_anchor_cell(world_position, footprint_width, footprint_height)

func _get_footprint_cells_for_node(node: Node2D) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if grid_manager == null:
		return cells

	for cell in grid_manager.get_footprint_cells_for_node(node):
		if cell is Vector2i:
			cells.append(cell)

	return cells

func _get_footprint_cells_from_anchor(anchor_cell: Vector2i, footprint_width: int, footprint_height: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for y in range(maxi(footprint_height, 1)):
		for x in range(maxi(footprint_width, 1)):
			cells.append(anchor_cell + Vector2i(x, y))

	return cells

func _are_cells_in_bounds(cells: Array[Vector2i]) -> bool:
	if grid_manager == null:
		return false

	for cell in cells:
		if not grid_manager.is_cell_in_bounds(cell):
			return false

	return true

func _is_footprint_occupied(cells: Array[Vector2i], ignored_node: Node = null) -> bool:
	if grid_occupancy_manager == null:
		grid_occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")

	for cell in cells:
		if grid_occupancy_manager != null and grid_occupancy_manager.has_method("is_cell_blocked"):
			if grid_occupancy_manager.is_cell_blocked(cell, ignored_node):
				return true
		elif grid_manager != null and grid_manager.has_method("is_cell_blocked"):
			if grid_manager.is_cell_blocked(cell, ignored_node):
				return true

	return false

func _does_footprint_overlap_resource_node(cells: Array[Vector2i]) -> bool:
	if grid_manager == null:
		return false

	for resource_node in get_tree().get_nodes_in_group("resource_node"):
		if not resource_node is Node2D:
			continue

		for resource_cell in grid_manager.get_footprint_cells_for_node(resource_node):
			if cells.has(resource_cell):
				return true

	return false

func _has_adjacent_connector(nation_key: String, footprint_cells: Array[Vector2i]) -> bool:
	var connector_cells := {}

	for source in [
		road_cells_by_nation.get(nation_key, {}),
		gate_cells_by_nation.get(nation_key, {}),
		anchor_cells_by_nation.get(nation_key, {})
	]:
		for cell in source.keys():
			connector_cells[cell] = true

	return _is_adjacent_to_cell_dictionary(footprint_cells, connector_cells)

func _is_adjacent_to_cell_dictionary(footprint_cells: Array[Vector2i], cell_dictionary: Dictionary) -> bool:
	if cell_dictionary.is_empty():
		return false

	var cardinal_directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for cell in footprint_cells:
		for direction in cardinal_directions:
			var neighbor = cell + direction
			if footprint_cells.has(neighbor):
				continue
			if cell_dictionary.has(neighbor):
				return true

	return false

func _is_within_connected_road_range(nation_key: String, anchor_cell: Vector2i, range_tiles: int) -> bool:
	var road_cells = road_cells_by_nation.get(nation_key, {})
	var gate_cells = gate_cells_by_nation.get(nation_key, {})

	for road_cell in road_cells.keys():
		if _get_tile_distance(anchor_cell, road_cell) <= range_tiles:
			return true

	for gate_cell in gate_cells.keys():
		if _get_tile_distance(anchor_cell, gate_cell) <= range_tiles:
			return true

	return false

func _is_too_close_to_anchor(nation_key: String, anchor_cell: Vector2i, min_distance_tiles: int) -> bool:
	for anchor in anchors_by_nation.get(nation_key, []):
		var existing_cell: Vector2i = anchor.get("cell", Vector2i.ZERO)
		if _get_tile_distance(existing_cell, anchor_cell) < min_distance_tiles:
			return true

	return false

func _get_tile_distance(a: Vector2i, b: Vector2i) -> int:
	var offset = a - b
	return maxi(abs(offset.x), abs(offset.y))

func _validation(valid: bool, failure: int, anchor_cell: Vector2i = Vector2i(-1, -1), footprint_cells: Array[Vector2i] = []) -> Dictionary:
	last_validation_result = {
		"valid": valid,
		"failure": failure,
		"reason": EconomyTypes.get_placement_failure_reason(failure),
		"anchor_cell": anchor_cell,
		"footprint_cells": footprint_cells
	}

	return last_validation_result.duplicate(true)

func _ensure_cell_dictionary(source: Dictionary, nation_key: String):
	if not source.has(nation_key):
		source[nation_key] = {}

func _draw_supply_radii():
	for nation_key in anchors_by_nation.keys():
		var color = _get_nation_debug_color(nation_key, 0.12)
		var outline_color = _get_nation_debug_color(nation_key, 0.55)
		for anchor in anchors_by_nation[nation_key]:
			var anchor_cell: Vector2i = anchor.get("cell", Vector2i.ZERO)
			var radius = int(anchor.get("radius", default_supply_radius_tiles))
			var world_position = to_local(grid_manager.cell_to_world(anchor_cell))
			draw_circle(world_position, float(radius * grid_manager.tile_size), color)
			draw_arc(world_position, float(radius * grid_manager.tile_size), 0.0, TAU, 64, outline_color, 2.0)

func _draw_outpost_ranges():
	for nation_key in road_cells_by_nation.keys():
		var color = _get_nation_debug_color(nation_key, 0.08)
		for road_cell in road_cells_by_nation[nation_key].keys():
			var world_position = to_local(grid_manager.cell_to_world(road_cell))
			draw_arc(world_position, float(default_outpost_network_range_tiles * grid_manager.tile_size), 0.0, TAU, 48, color, 1.0)

func _draw_cell_network(source: Dictionary, color: Color):
	for nation_key in source.keys():
		var nation_color = _get_nation_debug_color(nation_key, color.a)
		for cell in source[nation_key].keys():
			_draw_cell(cell, nation_color)

func _draw_valid_debug_cells():
	for nation_key in anchors_by_nation.keys():
		for y in range(int(grid_manager.get("grid_height"))):
			for x in range(int(grid_manager.get("grid_width"))):
				var cell = Vector2i(x, y)
				if is_cell_inside_supply_by_key(nation_key, cell):
					_draw_cell(cell, Color(0.2, 0.8, 0.4, 0.05))

func _draw_cell(cell: Vector2i, color: Color):
	var center = to_local(grid_manager.cell_to_world(cell))
	var size = Vector2.ONE * float(grid_manager.tile_size)
	draw_rect(Rect2(center - size / 2.0, size), color, true)
	draw_rect(Rect2(center - size / 2.0, size), Color(color.r, color.g, color.b, minf(color.a + 0.25, 1.0)), false, 1.0)

func _get_nation_debug_color(nation_key: String, alpha: float) -> Color:
	match nation_key:
		"emberhold":
			return Color(1.0, 0.28, 0.1, alpha)
		"veridion":
			return Color(0.95, 0.78, 0.22, alpha)
		"grimburrow":
			return Color(0.55, 0.8, 0.22, alpha)
		_:
			return Color(0.45, 0.75, 1.0, alpha)

func _get_owner_nation(node: Node):
	var ownership = node.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent if node != null else null
	return ownership.owner_nation if ownership != null else null

func _get_property_or_null(object: Object, property_name: String):
	if object == null:
		return null

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return object.get(property_name)

	return null

func _get_property_or_default(object: Object, property_name: String, default_value):
	var value = _get_property_or_null(object, property_name)
	return default_value if value == null else value

func _is_under_construction(node: Node) -> bool:
	var construction = node.get_node_or_null("ConstructionComponent")
	if construction != null:
		return bool(construction.get("is_under_construction"))
	return false
