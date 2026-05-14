extends Node
class_name PlacementManager

enum PlacementMode {
	UNITS,
	BUILDINGS
}

enum UnitCategory {
	ALL,
	WORKERS,
	INFANTRY,
	RANGED,
	CAVALRY,
	SIEGE,
	AIR,
	CHAMPIONS
}

enum BuildingCategory {
	ALL,
	PRODUCTION,
	DEFENSE,
	ENEMY_CAMP
}

enum PlacementAllegianceOverride {
	AUTO,
	PLAYER,
	ALLY,
	ENEMY,
	NEUTRAL
}

const UNIT_CATEGORY_COUNT := 8
const BUILDING_CATEGORY_COUNT := 4
const PLACEMENT_ALLEGIANCE_OVERRIDE_COUNT := 5

@export var placement_enabled: bool = true
@export var placement_mode: PlacementMode = PlacementMode.UNITS
@export var selected_index: int = 0
@export var selected_nation_index: int = 0
@export var selected_unit_category: UnitCategory = UnitCategory.ALL
@export var selected_unit_archetype_index: int = 0
@export var selected_building_category: BuildingCategory = BuildingCategory.ALL
@export var selected_allegiance_override: PlacementAllegianceOverride = PlacementAllegianceOverride.AUTO
@export var placed_buildings_auto_spawn: bool = false
@export var placed_buildings_under_construction: bool = false

@export var nation_options: Array[Resource] = []
@export var unit_options: Array[Resource] = []
@export var building_options: Array[Resource] = []
@export var prototype_worker_options: Array[Resource] = []

@export var unit_spawner: Node
@export var building_spawner: Node
@export var run_diplomacy_manager: Node
@export var grid_manager: Node
@export var grid_occupancy_manager: Node
@export var resource_manager: Node
@export var road_supply_manager: Node
@export var status_label: Label
@export var debug_active: bool = true
@export var free_build_mode: bool = false
@export var ignore_placement_rules_mode: bool = false
@export var show_placement_ghost: bool = true
@export var show_valid_placement_cells: bool = false
@export var show_invalid_placement_cells: bool = false
@export var economy_building_options: Array[Resource] = []

var last_validation_result: Dictionary = {}
var last_action: String = ""

func _ready():
	if resource_manager == null:
		resource_manager = get_tree().get_first_node_in_group("resource_manager")
	if road_supply_manager == null:
		road_supply_manager = get_tree().get_first_node_in_group("road_supply_manager")

	_load_default_economy_building_options()
	_load_default_worker_options()
	_seed_run_diplomacy()
	_refresh_options_from_selected_nation()
	_update_status_label()

func _unhandled_input(event):
	if not placement_enabled:
		return

	if _is_resource_node_placement_armed():
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			place_selected_at(_get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cycle_selected(1)

func set_debug_active(active: bool):
	debug_active = active
	_update_status_label()

func get_debug_title() -> String:
	return "Placement"

func handle_debug_input(event: InputEventKey) -> bool:
	if event.keycode == KEY_P:
		toggle_placement_enabled()
		return true
	elif not placement_enabled:
		return false
	elif event.keycode == KEY_M:
		toggle_mode()
		return true
	elif event.keycode == KEY_N:
		cycle_nation(1)
		return true
	elif event.keycode == KEY_O:
		cycle_allegiance_override(-1 if event.shift_pressed else 1)
		return true
	elif event.keycode == KEY_G:
		cycle_category(-1 if event.shift_pressed else 1)
		return true
	elif event.keycode == KEY_H:
		cycle_archetype(-1 if event.shift_pressed else 1)
		return true
	elif event.keycode == KEY_F:
		free_build_mode = not free_build_mode
		_update_status_label()
		return true
	elif event.keycode == KEY_I:
		ignore_placement_rules_mode = not ignore_placement_rules_mode
		_update_status_label()
		return true
	elif event.keycode == KEY_Q or event.keycode == KEY_BRACKETLEFT:
		cycle_selected(-1)
		return true
	elif event.keycode == KEY_E or event.keycode == KEY_BRACKETRIGHT:
		cycle_selected(1)
		return true
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		select_index(event.keycode - KEY_1)
		return true

	return false

func toggle_placement_enabled():
	placement_enabled = not placement_enabled
	_update_status_label()
	
	# Signal other systems if needed, or just let them poll
	if not placement_enabled:
		print("Switched to GAMEPLAY mode")
	else:
		print("Switched to PLACEMENT mode")

func toggle_mode():
	if placement_mode == PlacementMode.UNITS:
		placement_mode = PlacementMode.BUILDINGS
	else:
		placement_mode = PlacementMode.UNITS
	selected_index = 0
	_update_status_label()

func set_placement_mode(new_mode: int):
	placement_mode = clampi(new_mode, PlacementMode.UNITS, PlacementMode.BUILDINGS) as PlacementMode
	selected_index = 0
	_update_status_label()

func cycle_category(direction: int):
	if placement_mode != PlacementMode.UNITS:
		return

	selected_unit_category = wrapi(selected_unit_category + direction, 0, UNIT_CATEGORY_COUNT) as UnitCategory
	selected_unit_archetype_index = 0
	selected_index = 0
	_update_status_label()

func set_unit_category(new_category: int):
	selected_unit_category = clampi(new_category, 0, UNIT_CATEGORY_COUNT - 1) as UnitCategory
	selected_unit_archetype_index = 0
	selected_index = 0
	_update_status_label()

func set_building_category(new_category: int):
	selected_building_category = clampi(new_category, 0, BUILDING_CATEGORY_COUNT - 1) as BuildingCategory
	selected_index = 0
	_update_status_label()

func cycle_archetype(direction: int):
	if placement_mode == PlacementMode.BUILDINGS:
		selected_building_category = wrapi(selected_building_category + direction, 0, BUILDING_CATEGORY_COUNT) as BuildingCategory
		selected_index = 0
		_update_status_label()
		return

	var archetypes = _get_unit_archetypes_for_selected_category()

	if archetypes.size() <= 1:
		return

	selected_unit_archetype_index = wrapi(selected_unit_archetype_index + direction, 0, archetypes.size())
	selected_index = 0
	_update_status_label()

func set_unit_archetype_index(index: int):
	var archetypes = _get_unit_archetypes_for_selected_category()

	if archetypes.is_empty():
		selected_unit_archetype_index = 0
	else:
		selected_unit_archetype_index = clampi(index, 0, archetypes.size() - 1)

	selected_index = 0
	_update_status_label()

func cycle_nation(direction: int):
	if nation_options.is_empty():
		return

	selected_nation_index = wrapi(selected_nation_index + direction, 0, nation_options.size())
	selected_index = 0
	_refresh_options_from_selected_nation()
	_update_status_label()

func cycle_allegiance_override(direction: int):
	selected_allegiance_override = wrapi(
		selected_allegiance_override + direction,
		0,
		PLACEMENT_ALLEGIANCE_OVERRIDE_COUNT
	) as PlacementAllegianceOverride
	_update_status_label()

func cycle_selected(direction: int):
	var options = _get_current_options()

	if options.is_empty():
		return

	selected_index = wrapi(selected_index + direction, 0, options.size())
	_update_status_label()

func select_index(index: int):
	var options = _get_current_options()

	if index < 0 or index >= options.size():
		return

	selected_index = index
	_update_status_label()

func select_option_index(index: int):
	select_index(index)

func place_selected_at(world_position: Vector2):
	var selected_data = get_selected_data()

	if selected_data == null or grid_manager == null:
		return

	var footprint_width = maxi(int(selected_data.get("footprint_width")), 1)
	var footprint_height = maxi(int(selected_data.get("footprint_height")), 1)
	var cell = grid_manager.world_to_cell(world_position)
	var snapped_world_position = grid_manager.snap_world_to_footprint_center(
		grid_manager.cell_to_world(cell),
		footprint_width,
		footprint_height
	)

	var spawned_node: Node2D = null
	var owner_nation = get_selected_nation()

	if placement_mode == PlacementMode.UNITS:
		if grid_occupancy_manager != null and not grid_occupancy_manager.can_occupy_world_position(snapped_world_position, footprint_width, footprint_height):
			_record_validation(false, EconomyTypes.PlacementFailure.OCCUPIED_CELL, cell)
			print("Placement blocked: ", _get_display_name(selected_data), " at cell ", cell, " - occupied cell")
			return

		spawned_node = unit_spawner.spawn_unit(selected_data, owner_nation, cell, selected_allegiance_override) if unit_spawner != null else null
	else:
		var validation = validate_building_placement(selected_data, owner_nation, cell)
		if not bool(validation.get("valid", false)):
			print("Placement blocked: ", _get_display_name(selected_data), " at cell ", cell, " - ", validation.get("reason", "invalid"))
			return

		if not free_build_mode and resource_manager != null and resource_manager.has_method("spend_resources"):
			if not bool(resource_manager.call("spend_resources", owner_nation, EconomyTypes.get_cost_for_building_data(selected_data))):
				_record_validation(false, EconomyTypes.PlacementFailure.NOT_ENOUGH_RESOURCES, cell)
				print("Placement blocked: ", _get_display_name(selected_data), " at cell ", cell, " - not enough resources")
				return

		spawned_node = building_spawner.spawn_building(selected_data, owner_nation, cell, placed_buildings_auto_spawn, selected_allegiance_override, placed_buildings_under_construction) if building_spawner != null else null

	if spawned_node != null:
		last_action = "Placed %s at %s" % [_get_display_name(selected_data), cell]
		print(last_action)
	else:
		_notify_player("Placement blocked: " + last_validation_result.get("reason", "invalid"))

func _notify_player(message: String):
	var gameplay_ui = get_tree().get_first_node_in_group("gameplay_ui")
	if gameplay_ui != null and gameplay_ui.has_method("show_notification"):
		gameplay_ui.call("show_notification", message)

func validate_building_placement(building_data: Resource, owner_nation: Resource, cell: Vector2i) -> Dictionary:
	if building_data == null:
		return _record_validation(false, EconomyTypes.PlacementFailure.MISSING_BUILDING_DATA, cell)

	if not free_build_mode and resource_manager != null and resource_manager.has_method("can_afford"):
		var cost = EconomyTypes.get_cost_for_building_data(building_data)
		if not bool(resource_manager.call("can_afford", owner_nation, cost)):
			return _record_validation(false, EconomyTypes.PlacementFailure.NOT_ENOUGH_RESOURCES, cell)

	if road_supply_manager != null and road_supply_manager.has_method("validate_building_placement"):
		var result = road_supply_manager.call(
			"validate_building_placement",
			building_data,
			owner_nation,
			cell,
			ignore_placement_rules_mode
		)
		
		# If road supply says it's invalid, return that
		if not bool(result.get("valid", false)):
			last_validation_result = result
			return result
		
		# If road supply says it's valid, we STILL need to check occupancy
		# unless ignore_placement_rules_mode is on
		if not ignore_placement_rules_mode:
			var road_supply_footprint_width = maxi(int(building_data.get("footprint_width")), 1)
			var road_supply_footprint_height = maxi(int(building_data.get("footprint_height")), 1)
			var road_supply_world_position = grid_manager.snap_world_to_footprint_center(grid_manager.cell_to_world(cell), road_supply_footprint_width, road_supply_footprint_height)
			
			if grid_occupancy_manager != null and not grid_occupancy_manager.can_occupy_world_position(road_supply_world_position, road_supply_footprint_width, road_supply_footprint_height):
				return _record_validation(false, EconomyTypes.PlacementFailure.OCCUPIED_CELL, cell)
		
		last_validation_result = result
		return result

	var footprint_width = maxi(int(building_data.get("footprint_width")), 1)
	var footprint_height = maxi(int(building_data.get("footprint_height")), 1)
	var snapped_world_position = grid_manager.snap_world_to_footprint_center(grid_manager.cell_to_world(cell), footprint_width, footprint_height)

	if not ignore_placement_rules_mode and grid_occupancy_manager != null and not grid_occupancy_manager.can_occupy_world_position(snapped_world_position, footprint_width, footprint_height):
		return _record_validation(false, EconomyTypes.PlacementFailure.OCCUPIED_CELL, cell)

	return _record_validation(true, EconomyTypes.PlacementFailure.OK, cell)

func get_current_mouse_cell() -> Vector2i:
	if grid_manager == null:
		return Vector2i(-1, -1)

	return grid_manager.world_to_cell(_get_global_mouse_position())

func validate_selected_at_mouse() -> Dictionary:
	if placement_mode != PlacementMode.BUILDINGS:
		return _record_validation(true, EconomyTypes.PlacementFailure.OK, get_current_mouse_cell())

	return validate_building_placement(get_selected_data(), get_selected_nation(), get_current_mouse_cell())

func get_selected_data() -> Resource:
	var options = _get_current_options()

	if options.is_empty():
		return null

	selected_index = clampi(selected_index, 0, options.size() - 1)
	return options[selected_index]

func get_selected_nation() -> Resource:
	if nation_options.is_empty():
		return null

	selected_nation_index = clampi(selected_nation_index, 0, nation_options.size() - 1)
	return nation_options[selected_nation_index]

func _refresh_options_from_selected_nation():
	var selected_nation = get_selected_nation()

	if selected_nation == null:
		return

	if selected_nation.has_method("get_all_roster_units"):
		unit_options = _resource_array(selected_nation.call("get_all_roster_units"))
	else:
		unit_options = _resource_array(selected_nation.get("available_units"))
		
	if selected_nation.has_method("get_all_buildings"):
		building_options = _resource_array(selected_nation.call("get_all_buildings"))
	else:
		building_options = _resource_array(selected_nation.get("available_buildings"))

	for unit_data in prototype_worker_options:
		if unit_data != null and not unit_options.has(unit_data):
			unit_options.append(unit_data)

	for building_data in economy_building_options:
		if building_data != null and not building_options.has(building_data):
			building_options.append(building_data)

func _resource_array(value) -> Array[Resource]:
	var resources: Array[Resource] = []

	if value == null:
		return resources

	for item in value:
		if item is Resource:
			resources.append(item)

	return resources

func _get_current_options() -> Array[Resource]:
	if placement_mode == PlacementMode.BUILDINGS:
		return _get_filtered_building_options()

	return _get_filtered_unit_options()

func _get_filtered_unit_options() -> Array[Resource]:
	if selected_unit_category == UnitCategory.ALL:
		return unit_options

	var filtered_options: Array[Resource] = []

	for unit_data in unit_options:
		if unit_data != null and _unit_matches_selected_category(unit_data):
			filtered_options.append(unit_data)

	return filtered_options

func _get_filtered_building_options() -> Array[Resource]:
	if selected_building_category == BuildingCategory.ALL:
		return building_options

	var filtered_options: Array[Resource] = []

	for building_data in building_options:
		if building_data != null and _building_matches_selected_category(building_data):
			filtered_options.append(building_data)

	return filtered_options

func _unit_matches_selected_category(unit_data: Resource) -> bool:
	var unit_domain = int(unit_data.get("unit_domain"))
	var unit_archetype = int(unit_data.get("unit_archetype"))
	var selected_archetype = _get_selected_unit_archetype()

	if selected_archetype != -1 and unit_archetype != selected_archetype:
		return false

	match selected_unit_category:
		UnitCategory.WORKERS:
			var tags = unit_data.get("unit_tags")
			return bool(unit_data.get("can_harvest")) or (tags is Array and tags.has("worker"))
		UnitCategory.INFANTRY:
			return unit_domain == UnitClassification.UnitDomain.INFANTRY
		UnitCategory.RANGED:
			return unit_domain == UnitClassification.UnitDomain.RANGED
		UnitCategory.CAVALRY:
			return unit_domain == UnitClassification.UnitDomain.CAVALRY
		UnitCategory.SIEGE:
			return unit_domain == UnitClassification.UnitDomain.SIEGE
		UnitCategory.AIR:
			return unit_domain == UnitClassification.UnitDomain.AIR
		UnitCategory.CHAMPIONS:
			return unit_domain == UnitClassification.UnitDomain.CHAMPION
		_:
			return true

func _building_matches_selected_category(building_data: Resource) -> bool:
	var building_archetype = int(building_data.get("unit_archetype"))

	match selected_building_category:
		BuildingCategory.PRODUCTION:
			return building_archetype == UnitClassification.UnitArchetype.PRODUCTION_STRUCTURE
		BuildingCategory.DEFENSE:
			return building_archetype == UnitClassification.UnitArchetype.DEFENSE_STRUCTURE
		BuildingCategory.ENEMY_CAMP:
			return building_archetype == UnitClassification.UnitArchetype.ENEMY_CAMP_STRUCTURE
		_:
			return true

func _seed_run_diplomacy():
	if run_diplomacy_manager == null:
		return

	if run_diplomacy_manager.has_method("seed_default_relationships"):
		run_diplomacy_manager.seed_default_relationships()

func _update_status_label():
	if status_label == null:
		return

	status_label.visible = debug_active
	status_label.text = "DEBUG [Placement] | %s" % get_debug_text()

func get_debug_text() -> String:
	var selected_data = get_selected_data()
	var selected_nation = get_selected_nation()
	var mode_name = "Units" if placement_mode == PlacementMode.UNITS else "Buildings"
	var data_name = _get_display_name(selected_data)
	var nation_name = _get_display_name(selected_nation)
	var override_name = _get_allegiance_override_name(selected_allegiance_override)
	var options = _get_current_options()
	var category_name = _get_selected_category_name()
	var archetype_name = _get_selected_archetype_name()
	var selection_position = "%s/%s" % [selected_index + 1, options.size()] if not options.is_empty() else "0/0"

	var state_name = "PLACEMENT" if placement_enabled else "GAMEPLAY"

	var validation_reason = str(last_validation_result.get("reason", "not checked")) if not last_validation_result.is_empty() else "not checked"

	return "%s | Place: %s | Category: %s | Type: %s %s | Nation: %s | As: %s | Selected: %s | Free: %s | Ignore rules: %s | Last: %s | P placement, M mode, O side, G category, H type, N nation, Q/E select, 1-9 quick, F free, I ignore, LMB place, RMB next" % [
		state_name,
		mode_name,
		category_name,
		archetype_name,
		selection_position,
		nation_name,
		override_name,
		data_name,
		"On" if free_build_mode else "Off",
		"On" if ignore_placement_rules_mode else "Off",
		validation_reason
	]

func get_current_debug_summary() -> String:
	var selected_data = get_selected_data()
	var mode_name = "Units" if placement_mode == PlacementMode.UNITS else "Buildings"
	var validity = "Valid"
	var reason = ""

	if placement_mode == PlacementMode.BUILDINGS:
		var validation = validate_selected_at_mouse()
		validity = "Yes" if bool(validation.get("valid", false)) else "No"
		reason = " - %s" % str(validation.get("reason", "invalid")) if validity == "No" else ""

	return "Placement | %s | %s | Valid: %s%s" % [
		mode_name,
		_get_display_name(selected_data),
		validity,
		reason
	]

func get_debug_state() -> Dictionary:
	var selected_data = get_selected_data()
	var selected_cost = EconomyTypes.get_cost_for_building_data(selected_data) if selected_data != null and placement_mode == PlacementMode.BUILDINGS else {}
	return {
		"placement_enabled": placement_enabled,
		"placement_mode": "Buildings" if placement_mode == PlacementMode.BUILDINGS else "Units",
		"category": _get_selected_category_name(),
		"archetype": _get_selected_archetype_name(),
		"selected_name": _get_display_name(selected_data),
		"selected_index": selected_index,
		"selected_nation": _get_display_name(get_selected_nation()),
		"allegiance_override": _get_allegiance_override_name(selected_allegiance_override),
		"mouse_cell": get_current_mouse_cell(),
		"free_build_mode": free_build_mode,
		"ignore_placement_rules_mode": ignore_placement_rules_mode,
		"show_placement_ghost": show_placement_ghost,
		"show_valid_placement_cells": show_valid_placement_cells,
		"show_invalid_placement_cells": show_invalid_placement_cells,
		"last_validation": last_validation_result.duplicate(true),
		"last_action": last_action,
		"cost": selected_cost,
		"cost_text": EconomyTypes.format_cost(selected_cost)
	}

func get_mode_tab_options() -> Array:
	return [
		{"label": "Units", "value": PlacementMode.UNITS, "selected": placement_mode == PlacementMode.UNITS},
		{"label": "Buildings", "value": PlacementMode.BUILDINGS, "selected": placement_mode == PlacementMode.BUILDINGS}
	]

func get_category_tab_options() -> Array:
	if placement_mode == PlacementMode.BUILDINGS:
		return [
			{"label": "All", "value": BuildingCategory.ALL, "selected": selected_building_category == BuildingCategory.ALL},
			{"label": "Production", "value": BuildingCategory.PRODUCTION, "selected": selected_building_category == BuildingCategory.PRODUCTION},
			{"label": "Defense", "value": BuildingCategory.DEFENSE, "selected": selected_building_category == BuildingCategory.DEFENSE},
			{"label": "Enemy Camp", "value": BuildingCategory.ENEMY_CAMP, "selected": selected_building_category == BuildingCategory.ENEMY_CAMP}
		]

	return [
		{"label": "All", "value": UnitCategory.ALL, "selected": selected_unit_category == UnitCategory.ALL},
		{"label": "Workers", "value": UnitCategory.WORKERS, "selected": selected_unit_category == UnitCategory.WORKERS},
		{"label": "Infantry", "value": UnitCategory.INFANTRY, "selected": selected_unit_category == UnitCategory.INFANTRY},
		{"label": "Ranged", "value": UnitCategory.RANGED, "selected": selected_unit_category == UnitCategory.RANGED},
		{"label": "Cavalry", "value": UnitCategory.CAVALRY, "selected": selected_unit_category == UnitCategory.CAVALRY},
		{"label": "Siege", "value": UnitCategory.SIEGE, "selected": selected_unit_category == UnitCategory.SIEGE},
		{"label": "Air", "value": UnitCategory.AIR, "selected": selected_unit_category == UnitCategory.AIR},
		{"label": "Champions", "value": UnitCategory.CHAMPIONS, "selected": selected_unit_category == UnitCategory.CHAMPIONS}
	]

func get_type_tab_options() -> Array:
	if placement_mode == PlacementMode.BUILDINGS:
		return []

	var options: Array = []
	var archetypes = _get_unit_archetypes_for_selected_category()

	for index in range(archetypes.size()):
		var archetype = archetypes[index]
		var label = "All" if archetype == -1 else UnitClassification.get_unit_archetype_name(archetype)
		options.append({
			"label": label,
			"value": index,
			"archetype": archetype,
			"selected": index == selected_unit_archetype_index
		})

	return options

func get_current_option_debug_list() -> Array:
	var options: Array = []
	var current_options = _get_current_options()

	for index in range(current_options.size()):
		var resource = current_options[index]
		var entry := {
			"index": index,
			"label": _get_display_name(resource),
			"selected": index == selected_index
		}

		if placement_mode == PlacementMode.BUILDINGS:
			entry["cost"] = EconomyTypes.get_cost_for_building_data(resource)
			entry["cost_text"] = EconomyTypes.format_cost(entry["cost"])
			entry["building_kind"] = EconomyTypes.get_building_kind_name(EconomyTypes.get_building_kind_for_data(resource))

		options.append(entry)

	return options

func get_debug_shortcuts() -> Array:
	return [
		{"keys": "F1", "description": "Show/hide debug UI"},
		{"keys": "Tab", "description": "Cycle active debug system"},
		{"keys": "P", "description": "Toggle placement input"},
		{"keys": "M", "description": "Switch unit/building placement"},
		{"keys": "N", "description": "Cycle placement nation"},
		{"keys": "O", "description": "Cycle allegiance override"},
		{"keys": "G", "description": "Cycle category"},
		{"keys": "H", "description": "Cycle archetype"},
		{"keys": "Q/E", "description": "Cycle selected placement item"},
		{"keys": "F", "description": "Toggle free-build mode"},
		{"keys": "I", "description": "Toggle ignore placement rules"}
	]

func _record_validation(valid: bool, failure: int, cell: Vector2i) -> Dictionary:
	last_validation_result = {
		"valid": valid,
		"failure": failure,
		"reason": EconomyTypes.get_placement_failure_reason(failure),
		"anchor_cell": cell,
		"footprint_cells": []
	}
	return last_validation_result.duplicate(true)

func _is_resource_node_placement_armed() -> bool:
	var economy_debugger = get_tree().get_first_node_in_group("economy_debug_manager")
	return economy_debugger != null and economy_debugger.has_method("is_resource_node_placement_armed") and bool(economy_debugger.call("is_resource_node_placement_armed"))

func _load_default_economy_building_options():
	if not economy_building_options.is_empty():
		return

	for path in [
		"res://data/buildings/economy/CapitalData.tres",
		"res://data/buildings/economy/RoadData.tres",
		"res://data/buildings/economy/OutpostData.tres",
		"res://data/buildings/economy/WatchTowerData.tres",
		"res://data/buildings/economy/BarracksData.tres",
		"res://data/buildings/economy/StablesData.tres",
		"res://data/buildings/economy/HangarData.tres",
		"res://data/buildings/economy/WorkshopData.tres",
		"res://data/buildings/economy/AltarData.tres",
		"res://data/buildings/economy/HouseData.tres",
		"res://data/buildings/economy/TradingHallData.tres",
		"res://data/buildings/economy/WallData.tres",
		"res://data/buildings/economy/GateData.tres"
	]:
		var resource = load(path)
		if resource is Resource:
			economy_building_options.append(resource)

func _load_default_worker_options():
	if not prototype_worker_options.is_empty():
		return

	for path in [
		"res://data/units/prototypes/GeneralWorkerData.tres",
		"res://data/units/prototypes/LumberWorkerData.tres",
		"res://data/units/prototypes/FarmWorkerData.tres",
		"res://data/units/prototypes/MineWorkerData.tres"
	]:
		var resource = load(path)
		if resource is Resource:
			prototype_worker_options.append(resource)

func _get_selected_category_name() -> String:
	if placement_mode == PlacementMode.BUILDINGS:
		return "Buildings"

	match selected_unit_category:
		UnitCategory.WORKERS:
			return "Workers"
		UnitCategory.INFANTRY:
			return "Infantry"
		UnitCategory.RANGED:
			return "Ranged"
		UnitCategory.CAVALRY:
			return "Cavalry"
		UnitCategory.SIEGE:
			return "Siege"
		UnitCategory.AIR:
			return "Air"
		UnitCategory.CHAMPIONS:
			return "Champions"
		_:
			return "All"

func _get_selected_archetype_name() -> String:
	if placement_mode == PlacementMode.BUILDINGS:
		return _get_building_category_name(selected_building_category)

	var selected_archetype = _get_selected_unit_archetype()

	if selected_archetype == -1:
		return "All"

	return UnitClassification.get_unit_archetype_name(selected_archetype)

func _get_building_category_name(building_category: BuildingCategory) -> String:
	match building_category:
		BuildingCategory.PRODUCTION:
			return "Production Structure"
		BuildingCategory.DEFENSE:
			return "Defense Structure"
		BuildingCategory.ENEMY_CAMP:
			return "Enemy Camp Structure"
		_:
			return "All"

func _get_allegiance_override_name(allegiance_override: PlacementAllegianceOverride) -> String:
	match allegiance_override:
		PlacementAllegianceOverride.PLAYER:
			return "Player"
		PlacementAllegianceOverride.ALLY:
			return "Ally"
		PlacementAllegianceOverride.ENEMY:
			return "Enemy"
		PlacementAllegianceOverride.NEUTRAL:
			return "Neutral"
		_:
			return "Auto"

func _get_selected_unit_archetype() -> int:
	var archetypes = _get_unit_archetypes_for_selected_category()

	if archetypes.is_empty():
		return -1

	selected_unit_archetype_index = clampi(selected_unit_archetype_index, 0, archetypes.size() - 1)
	return archetypes[selected_unit_archetype_index]

func _get_unit_archetypes_for_selected_category() -> Array[int]:
	match selected_unit_category:
		UnitCategory.WORKERS:
			return [-1]
		UnitCategory.INFANTRY:
			return [
				-1,
				UnitClassification.UnitArchetype.LIGHT_INFANTRY,
				UnitClassification.UnitArchetype.HEAVY_INFANTRY,
				UnitClassification.UnitArchetype.SPECIALIST_INFANTRY
			]
		UnitCategory.RANGED:
			return [
				-1,
				UnitClassification.UnitArchetype.LIGHT_RANGED,
				UnitClassification.UnitArchetype.HEAVY_RANGED,
				UnitClassification.UnitArchetype.ARCANE_RANGED
			]
		UnitCategory.CAVALRY:
			return [
				-1,
				UnitClassification.UnitArchetype.LIGHT_CAVALRY,
				UnitClassification.UnitArchetype.HEAVY_CAVALRY,
				UnitClassification.UnitArchetype.WAR_BEAST
			]
		UnitCategory.SIEGE:
			return [
				-1,
				UnitClassification.UnitArchetype.LIGHT_SIEGE,
				UnitClassification.UnitArchetype.HEAVY_SIEGE,
				UnitClassification.UnitArchetype.ARCANE_SIEGE
			]
		UnitCategory.AIR:
			return [
				-1,
				UnitClassification.UnitArchetype.LIGHT_AIR,
				UnitClassification.UnitArchetype.HEAVY_AIR,
				UnitClassification.UnitArchetype.ARCANE_AIR
			]
		UnitCategory.CHAMPIONS:
			return [
				-1,
				UnitClassification.UnitArchetype.MARTIAL_CHAMPION,
				UnitClassification.UnitArchetype.ARCANE_CHAMPION,
				UnitClassification.UnitArchetype.DIVINE_FALLEN_CHAMPION
			]
		_:
			return [-1]

func _get_display_name(resource: Resource) -> String:
	if resource == null:
		return "None"

	var display_name = str(resource.get("display_name"))
	if not display_name.is_empty():
		return display_name

	var unit_id = str(resource.get("unit_id"))
	if not unit_id.is_empty():
		return unit_id

	var building_id = str(resource.get("building_id"))
	if not building_id.is_empty():
		return building_id

	var nation_id = str(resource.get("nation_id"))
	if not nation_id.is_empty():
		return nation_id

	return resource.resource_path.get_file()

func _get_global_mouse_position() -> Vector2:
	var camera = get_viewport().get_camera_2d()

	if camera != null:
		return camera.get_global_mouse_position()

	return get_viewport().get_mouse_position()
