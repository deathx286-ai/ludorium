extends Node
class_name ProductionComponent

signal production_started(unit_data: UnitData)
signal production_progress_updated(unit_data: UnitData, progress: float)
signal production_finished(unit_data: UnitData, spawned_unit: Node2D)
signal production_error(message: String)
signal queue_changed

@export var max_queue_size: int = 5
@export var spawn_radius: float = 120.0
@export var max_spawn_attempts: int = 15

var production_queue: Array[UnitData] = []
var current_unit_data: UnitData = null
var current_progress: float = 0.0
var training_time: float = 5.0 # Default fallback
var parent_building: Node2D

func _ready():
	parent_building = get_parent() as Node2D

func _process(delta: float):
	if _is_under_construction():
		return

	if current_unit_data == null:
		if not production_queue.is_empty():
			_start_next_in_queue()
		return

	current_progress += delta
	var progress_ratio = clampf(current_progress / training_time, 0.0, 1.0)
	production_progress_updated.emit(current_unit_data, progress_ratio)

	if current_progress >= training_time:
		_finish_current_production()

func add_to_queue(unit_data: UnitData) -> bool:
	if production_queue.size() >= max_queue_size:
		production_error.emit("Queue full")
		return false

	if not _can_afford(unit_data):
		production_error.emit("Not enough resources")
		return false

	_spend_resources(unit_data)
	production_queue.append(unit_data)
	queue_changed.emit()
	return true

func cancel_index(index: int):
	if index < 0 or index >= production_queue.size():
		return
		
	var unit_data = production_queue[index]
	_refund_resources(unit_data)
	production_queue.remove_at(index)
	queue_changed.emit()

func _start_next_in_queue():
	if production_queue.is_empty():
		return
		
	current_unit_data = production_queue.pop_front()
	current_progress = 0.0
	training_time = _get_training_time(current_unit_data)
	production_started.emit(current_unit_data)
	queue_changed.emit()

func _finish_current_production():
	var spawned_unit = _spawn_unit(current_unit_data)
	
	if spawned_unit != null:
		production_finished.emit(current_unit_data, spawned_unit)
		current_unit_data = null
		current_progress = 0.0
	else:
		# If spawn failed (e.g. blocked), we wait and try again next frame
		# but we should probably alert the user
		production_error.emit("Spawn location blocked")

func _get_training_time(unit_data: UnitData) -> float:
	# Check for training_time in unit_data, or use a default
	if "training_time" in unit_data:
		return unit_data.training_time
	return 5.0 # Default fallback

func _can_afford(unit_data: UnitData) -> bool:
	var resource_manager = _get_resource_manager()
	if resource_manager == null: return true
	
	var nation = _get_parent_nation()
	var cost = _get_unit_cost(unit_data)
	
	# The ResourceManager.gd expects a Dictionary for cost
	if resource_manager.has_method("has_resources"):
		return resource_manager.call("has_resources", nation, cost)
	return true

func _spend_resources(unit_data: UnitData):
	var resource_manager = _get_resource_manager()
	if resource_manager == null: return
	
	var nation = _get_parent_nation()
	var cost = _get_unit_cost(unit_data)
	
	if resource_manager.has_method("spend_resources"):
		resource_manager.call("spend_resources", nation, cost)

func _refund_resources(unit_data: UnitData):
	var resource_manager = _get_resource_manager()
	if resource_manager == null: return
	
	var nation = _get_parent_nation()
	var cost = _get_unit_cost(unit_data)
	
	for type in cost:
		if resource_manager.has_method("add_resource"):
			resource_manager.call("add_resource", nation, type, cost[type])

func _get_unit_cost(unit_data: UnitData) -> Dictionary:
	# Extract cost from UnitData. Assuming it has similar properties to BuildingData
	# or a dedicated resource_cost Dictionary
	if "resource_cost" in unit_data and not unit_data.resource_cost.is_empty():
		return unit_data.resource_cost
		
	var cost = {}
	if "wood_cost" in unit_data and unit_data.wood_cost > 0: cost[BuildingData.ResourceType.WOOD] = unit_data.wood_cost
	if "food_cost" in unit_data and unit_data.food_cost > 0: cost[BuildingData.ResourceType.FOOD] = unit_data.food_cost
	if "gold_cost" in unit_data and unit_data.gold_cost > 0: cost[BuildingData.ResourceType.GOLD] = unit_data.gold_cost
	if "stone_cost" in unit_data and unit_data.stone_cost > 0: cost[BuildingData.ResourceType.STONE] = unit_data.stone_cost
	if "metal_cost" in unit_data and unit_data.metal_cost > 0: cost[BuildingData.ResourceType.METAL] = unit_data.metal_cost
	
	return cost

func _spawn_unit(unit_data: UnitData) -> Node2D:
	var unit_spawner = get_tree().get_first_node_in_group("unit_spawner")
	if unit_spawner == null:
		return null
		
	var spawn_cell = _find_valid_spawn_cell(unit_data)
	if spawn_cell == Vector2i(-1, -1):
		return null
		
	var nation = _get_parent_nation()
	var allegiance = _get_parent_allegiance()
	
	# Mapping internal allegiance to UnitSpawner override indices
	var override_index = 0
	if allegiance == UnitOwnershipComponent.Allegiance.PLAYER: override_index = 1
	elif allegiance == UnitOwnershipComponent.Allegiance.ALLY: override_index = 2
	elif allegiance == UnitOwnershipComponent.Allegiance.ENEMY: override_index = 3
	elif allegiance == UnitOwnershipComponent.Allegiance.NEUTRAL: override_index = 4
	
	return unit_spawner.call("spawn_unit", unit_data, nation, spawn_cell, override_index)

func _find_valid_spawn_cell(unit_data: UnitData) -> Vector2i:
	var grid_manager = get_tree().get_first_node_in_group("grid_manager")
	var occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")
	if grid_manager == null: return Vector2i(-1, -1)
	
	var base_cell = grid_manager.world_to_cell(parent_building.global_position)
	var fw = unit_data.footprint_width
	var fh = unit_data.footprint_height
	
	# Get parent footprint for search start
	var pw = 1
	var ph = 1
	if parent_building.has_method("get_tile_footprint_size"):
		var fsize = parent_building.call("get_tile_footprint_size")
		pw = fsize.x
		ph = fsize.y
	else:
		pw = int(parent_building.get("tile_width")) if parent_building.get("tile_width") != null else int(parent_building.get("footprint_width")) if parent_building.get("footprint_width") != null else 1
		ph = int(parent_building.get("tile_height")) if parent_building.get("tile_height") != null else int(parent_building.get("footprint_height")) if parent_building.get("footprint_height") != null else 1
	
	# Search in expanding rings
	for radius in range(maxi(pw, ph), 10):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if abs(x) != radius and abs(y) != radius: continue
				
				var cell = base_cell + Vector2i(x, y)
				if not grid_manager.is_cell_in_bounds(cell): continue
				
				var world_pos = grid_manager.cell_to_world(cell)
				if occupancy_manager != null:
					if occupancy_manager.call("can_occupy_world_position", world_pos, fw, fh, null):
						return cell
				elif not grid_manager.is_footprint_occupied(world_pos, fw, fh, null):
					return cell
					
	return Vector2i(-1, -1)

func _get_resource_manager():
	return get_tree().get_first_node_in_group("resource_manager")

func _get_parent_nation() -> Resource:
	if parent_building == null: return null
	var ownership = parent_building.get_node_or_null("UnitOwnershipComponent")
	if ownership != null:
		return ownership.get("owner_nation")
	return null

func _get_parent_allegiance() -> int:
	if parent_building == null: return UnitOwnershipComponent.Allegiance.NEUTRAL
	var ownership = parent_building.get_node_or_null("UnitOwnershipComponent")
	if ownership != null:
		return int(ownership.get("allegiance"))
	return UnitOwnershipComponent.Allegiance.NEUTRAL

func get_debug_summary() -> String:
	var text = "Queue: %d/%d" % [production_queue.size(), max_queue_size]
	if current_unit_data != null:
		text += "\nTraining: %s (%.1f%%)" % [current_unit_data.display_name, get_progress() * 100.0]
	return text

func get_progress() -> float:
	if current_unit_data == null or training_time <= 0: return 0.0
	return clampf(current_progress / training_time, 0.0, 1.0)

func _is_under_construction() -> bool:
	if parent_building == null: return false
	var construction = parent_building.get_node_or_null("ConstructionComponent")
	if construction != null:
		return bool(construction.get("is_under_construction"))
	return false
