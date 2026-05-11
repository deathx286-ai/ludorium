extends Node
class_name EconomyDebugManager

@export var debug_enabled: bool = true
@export var debug_active: bool = false
@export var resource_node_scene: PackedScene
@export var resource_manager: Node
@export var road_supply_manager: Node
@export var placement_manager: Node
@export var unit_spawner: Node
@export var building_spawner: Node
@export var grid_manager: Node
@export var run_diplomacy_manager: Node
@export var spawn_parent: Node
@export var nation_options: Array[Resource] = []
@export var selected_nation_index: int = 0
@export var free_build_mode: bool = false
@export var ignore_placement_rules_mode: bool = false

@export_group("Prototype Data")
@export var worker_unit_data: UnitData
@export var lumber_worker_unit_data: UnitData
@export var farm_worker_unit_data: UnitData
@export var mine_worker_unit_data: UnitData
@export var player_combat_unit_data: UnitData
@export var enemy_combat_unit_data: UnitData
@export var capital_data: Resource
@export var road_data: Resource
@export var house_data: Resource
@export var barracks_data: Resource
@export var stables_data: Resource
@export var hangar_data: Resource
@export var workshop_data: Resource
@export var altar_data: Resource
@export var trading_hall_data: Resource
@export var watch_tower_data: Resource
@export var wall_data: Resource
@export var gate_data: Resource
@export var outpost_data: Resource

var last_action: String = ""
var pending_resource_node_type: int = BuildingData.ResourceType.NONE
var _restore_placement_enabled: bool = false
var _has_placement_restore: bool = false

func _ready():
	add_to_group("economy_debug_manager")
	_discover_references()
	_load_default_resources()

func _unhandled_input(event):
	if not debug_enabled or pending_resource_node_type == BuildingData.ResourceType.NONE:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_pending_resource_node_placement()
		get_viewport().set_input_as_handled()
		return

	if not event is InputEventMouseButton or not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_pending_resource_node_placement()
		get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var spawned_node = spawn_resource_node_at_mouse(pending_resource_node_type)
	if spawned_node != null:
		_finish_pending_resource_node_placement()
	else:
		_record_action("Still placing %s node; click another open map cell or Esc/right-click to cancel" % EconomyTypes.get_resource_name(pending_resource_node_type))

	get_viewport().set_input_as_handled()

func set_debug_active(active: bool):
	debug_active = active

func get_debug_title() -> String:
	return "Spawning / Economy"

func handle_debug_input(event: InputEventKey) -> bool:
	if not debug_enabled or not event.pressed or event.echo:
		return false

	match event.keycode:
		KEY_F:
			set_free_build_mode(not is_free_build_mode())
			return true
		KEY_I:
			set_ignore_placement_rules_mode(not is_ignore_placement_rules_mode())
			return true
		KEY_N:
			cycle_selected_nation(1)
			return true
		KEY_1:
			add_resource_to_selected_nation(BuildingData.ResourceType.WOOD, 100)
			return true
		KEY_2:
			add_resource_to_selected_nation(BuildingData.ResourceType.FOOD, 100)
			return true
		KEY_3:
			add_resource_to_selected_nation(BuildingData.ResourceType.GOLD, 100)
			return true
		KEY_4:
			add_resource_to_selected_nation(BuildingData.ResourceType.STONE, 100)
			return true
		KEY_5:
			add_resource_to_selected_nation(BuildingData.ResourceType.METAL, 100)
			return true
		KEY_6:
			add_all_resources_to_selected_nation(500)
			return true
		KEY_R:
			arm_resource_node_placement(BuildingData.ResourceType.WOOD)
			return true
		KEY_T:
			spawn_enemy_combat_near_closest_resource_node()
			return true
		_:
			return false

func add_resource_to_selected_nation(resource_type: int, amount: int):
	if resource_manager == null or not resource_manager.has_method("add_resource"):
		_record_action("ResourceManager not connected")
		return

	resource_manager.call("add_resource", get_selected_nation(), resource_type, amount)
	_record_action("+%s %s to %s" % [amount, EconomyTypes.get_resource_name(resource_type), _get_display_name(get_selected_nation())])

func add_all_resources_to_selected_nation(amount: int):
	if resource_manager == null or not resource_manager.has_method("add_all_resources"):
		_record_action("ResourceManager not connected")
		return

	resource_manager.call("add_all_resources", get_selected_nation(), amount)
	_record_action("+%s all resources to %s" % [amount, _get_display_name(get_selected_nation())])

func add_all_resources_to_enemy(amount: int = 500):
	var enemy_nation = get_enemy_nation()
	if enemy_nation == null:
		_record_action("No enemy nation available")
		return

	if resource_manager != null and resource_manager.has_method("add_all_resources"):
		resource_manager.call("add_all_resources", enemy_nation, amount)
		_record_action("+%s all resources to %s" % [amount, _get_display_name(enemy_nation)])

func set_free_build_mode(enabled: bool):
	free_build_mode = enabled
	if placement_manager != null and _has_property(placement_manager, "free_build_mode"):
		placement_manager.set("free_build_mode", enabled)
	_record_action("Free build %s" % ("On" if enabled else "Off"))

func set_ignore_placement_rules_mode(enabled: bool):
	ignore_placement_rules_mode = enabled
	if placement_manager != null and _has_property(placement_manager, "ignore_placement_rules_mode"):
		placement_manager.set("ignore_placement_rules_mode", enabled)
	_record_action("Ignore placement rules %s" % ("On" if enabled else "Off"))

func is_free_build_mode() -> bool:
	if placement_manager != null and _has_property(placement_manager, "free_build_mode"):
		return bool(placement_manager.get("free_build_mode"))

	return free_build_mode

func is_ignore_placement_rules_mode() -> bool:
	if placement_manager != null and _has_property(placement_manager, "ignore_placement_rules_mode"):
		return bool(placement_manager.get("ignore_placement_rules_mode"))

	return ignore_placement_rules_mode

func cycle_selected_nation(direction: int):
	if nation_options.is_empty():
		return

	selected_nation_index = wrapi(selected_nation_index + direction, 0, nation_options.size())
	_record_action("Selected owner: %s" % _get_display_name(get_selected_nation()))

func get_selected_nation() -> Resource:
	if nation_options.is_empty():
		return null

	selected_nation_index = clampi(selected_nation_index, 0, nation_options.size() - 1)
	return nation_options[selected_nation_index]

func get_enemy_nation() -> Resource:
	for nation in nation_options:
		if nation != null and str(nation.get("nation_id")) == "grimburrow":
			return nation

	if nation_options.size() > 1:
		return nation_options[1]

	return null

func arm_resource_node_placement(resource_type: int):
	pending_resource_node_type = resource_type
	_pause_normal_placement_for_pending_node()
	_record_action("Placing %s node: click an open map cell. Esc/right-click cancels." % EconomyTypes.get_resource_name(resource_type))

func cancel_pending_resource_node_placement():
	if pending_resource_node_type == BuildingData.ResourceType.NONE:
		return

	_record_action("Cancelled %s node placement" % EconomyTypes.get_resource_name(pending_resource_node_type))
	pending_resource_node_type = BuildingData.ResourceType.NONE
	_restore_normal_placement_after_pending_node()

func is_resource_node_placement_armed() -> bool:
	return pending_resource_node_type != BuildingData.ResourceType.NONE

func spawn_resource_node_at_mouse(resource_type: int) -> Node2D:
	if grid_manager == null:
		_record_action("GridManager not connected")
		return null

	return spawn_resource_node(resource_type, grid_manager.world_to_cell(_get_global_mouse_position()))

func spawn_resource_node(resource_type: int, cell: Vector2i) -> Node2D:
	if resource_node_scene == null:
		resource_node_scene = load("res://scenes/resources/resource_node.tscn") as PackedScene

	if resource_node_scene == null or grid_manager == null:
		_record_action("ResourceNode scene or grid missing")
		return null

	var world_position = grid_manager.cell_to_world(cell)
	if grid_manager.has_method("snap_world_to_tile_center"):
		world_position = grid_manager.snap_world_to_tile_center(world_position)

	var occupancy_manager = get_tree().get_first_node_in_group("grid_occupancy_manager")
	if occupancy_manager != null and occupancy_manager.has_method("can_occupy_world_position"):
		if not occupancy_manager.can_occupy_world_position(world_position, 1, 1):
			_record_action("Resource node blocked at %s: occupied cell" % cell)
			print("Resource node placement blocked at ", cell, " - occupied cell")
			return null

	var node = resource_node_scene.instantiate() as Node2D
	if node == null:
		return null

	node.global_position = world_position
	node.set("resource_type", resource_type)
	node.set("required_worker_type", EconomyTypes.get_required_worker_for_resource(resource_type))
	_add_spawned_node(node)
	_record_action("Spawned %s node at %s" % [EconomyTypes.get_resource_name(resource_type), cell])
	print(last_action)
	return node

func spawn_building_kind_at_mouse(building_kind: int) -> Node2D:
	if grid_manager == null:
		_record_action("GridManager not connected")
		return null

	return spawn_building_kind(building_kind, grid_manager.world_to_cell(_get_global_mouse_position()), get_selected_nation())

func spawn_building_kind(building_kind: int, cell: Vector2i, owner_nation: Resource = null) -> Node2D:
	var building_data = get_building_data_for_kind(building_kind)
	if building_data == null:
		_record_action("Missing building data: %s" % EconomyTypes.get_building_kind_name(building_kind))
		return null

	if owner_nation == null:
		owner_nation = get_selected_nation()

	if placement_manager != null and placement_manager.has_method("validate_building_placement"):
		var previous_free_build = bool(placement_manager.get("free_build_mode")) if _has_property(placement_manager, "free_build_mode") else false
		var previous_ignore_rules = bool(placement_manager.get("ignore_placement_rules_mode")) if _has_property(placement_manager, "ignore_placement_rules_mode") else false
		if _has_property(placement_manager, "free_build_mode"):
			placement_manager.set("free_build_mode", is_free_build_mode())
		if _has_property(placement_manager, "ignore_placement_rules_mode"):
			placement_manager.set("ignore_placement_rules_mode", is_ignore_placement_rules_mode())

		var validation: Dictionary = placement_manager.call("validate_building_placement", building_data, owner_nation, cell)

		if _has_property(placement_manager, "free_build_mode"):
			placement_manager.set("free_build_mode", previous_free_build)
		if _has_property(placement_manager, "ignore_placement_rules_mode"):
			placement_manager.set("ignore_placement_rules_mode", previous_ignore_rules)

		if not bool(validation.get("valid", false)):
			_record_action("Building blocked: %s" % validation.get("reason", "invalid"))
			print("Building placement blocked: ", EconomyTypes.get_building_kind_name(building_kind), " at ", cell, " - ", validation.get("reason", "invalid"))
			return null
	elif not is_ignore_placement_rules_mode() and road_supply_manager != null and road_supply_manager.has_method("validate_building_placement"):
		var validation: Dictionary = road_supply_manager.call("validate_building_placement", building_data, owner_nation, cell, false)
		if not bool(validation.get("valid", false)):
			_record_action("Building blocked: %s" % validation.get("reason", "invalid"))
			return null

	if not is_free_build_mode() and resource_manager != null and resource_manager.has_method("spend_resources"):
		if not bool(resource_manager.call("spend_resources", owner_nation, EconomyTypes.get_cost_for_building_data(building_data))):
			_record_action("Building blocked: not enough resources")
			print("Building placement blocked: not enough resources")
			return null

	var override = PlacementManager.PlacementAllegianceOverride.AUTO
	if placement_manager != null and _has_property(placement_manager, "selected_allegiance_override"):
		override = int(placement_manager.get("selected_allegiance_override"))

	var building = building_spawner.spawn_building(building_data, owner_nation, cell, false, override) if building_spawner != null else null
	if building != null:
		_record_action("Spawned %s at %s" % [EconomyTypes.get_building_kind_name(building_kind), cell])
		print(last_action)

	return building

func spawn_player_worker_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(worker_unit_data, get_selected_nation(), PlacementManager.PlacementAllegianceOverride.PLAYER)

func spawn_enemy_worker_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(worker_unit_data, get_enemy_nation(), PlacementManager.PlacementAllegianceOverride.ENEMY)

func spawn_player_lumber_worker_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(lumber_worker_unit_data, get_selected_nation(), PlacementManager.PlacementAllegianceOverride.PLAYER)

func spawn_enemy_lumber_worker_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(lumber_worker_unit_data, get_enemy_nation(), PlacementManager.PlacementAllegianceOverride.ENEMY)

func spawn_player_farm_worker_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(farm_worker_unit_data, get_selected_nation(), PlacementManager.PlacementAllegianceOverride.PLAYER)

func spawn_enemy_farm_worker_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(farm_worker_unit_data, get_enemy_nation(), PlacementManager.PlacementAllegianceOverride.ENEMY)

func spawn_player_mine_worker_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(mine_worker_unit_data, get_selected_nation(), PlacementManager.PlacementAllegianceOverride.PLAYER)

func spawn_enemy_mine_worker_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(mine_worker_unit_data, get_enemy_nation(), PlacementManager.PlacementAllegianceOverride.ENEMY)

func spawn_player_combat_unit_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(player_combat_unit_data, get_selected_nation(), PlacementManager.PlacementAllegianceOverride.PLAYER)

func spawn_enemy_combat_unit_at_mouse() -> Node2D:
	return spawn_unit_at_mouse(enemy_combat_unit_data, get_enemy_nation(), PlacementManager.PlacementAllegianceOverride.ENEMY)

func spawn_unit_at_mouse(unit_data: UnitData, owner_nation: Resource, allegiance_override: int) -> Node2D:
	if grid_manager == null:
		_record_action("GridManager not connected")
		return null

	return spawn_unit(unit_data, owner_nation, grid_manager.world_to_cell(_get_global_mouse_position()), allegiance_override)

func spawn_unit(unit_data: UnitData, owner_nation: Resource, cell: Vector2i, allegiance_override: int) -> Node2D:
	if unit_data == null or unit_spawner == null:
		_record_action("Unit data or UnitSpawner missing")
		return null

	var unit = unit_spawner.spawn_unit(unit_data, owner_nation, cell, allegiance_override)
	if unit != null:
		_record_action("Spawned %s at %s" % [_get_display_name(unit_data), cell])
		print(last_action)

	return unit

func spawn_enemy_combat_near_closest_resource_node() -> Node2D:
	var node = get_closest_resource_node_to_mouse()
	if node == null or grid_manager == null:
		_record_action("No resource node available for contest test")
		return null

	var node_cell = grid_manager.world_to_cell(node.global_position)
	var spawn_cell = node_cell + Vector2i(2, 0)
	if not grid_manager.is_cell_in_bounds(spawn_cell):
		spawn_cell = node_cell + Vector2i(-2, 0)

	return spawn_unit(enemy_combat_unit_data, get_enemy_nation(), spawn_cell, PlacementManager.PlacementAllegianceOverride.ENEMY)

func get_closest_resource_node_to_mouse() -> ResourceNode:
	var mouse_position = _get_global_mouse_position()
	var closest_node: ResourceNode = null
	var closest_distance_squared = INF

	for node in get_tree().get_nodes_in_group("resource_node"):
		if not node is ResourceNode or not is_instance_valid(node):
			continue

		var distance_squared = (node as Node2D).global_position.distance_squared_to(mouse_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_node = node

	return closest_node

func get_building_data_for_kind(building_kind: int) -> Resource:
	match building_kind:
		EconomyTypes.BuildingKind.CAPITAL:
			return capital_data
		EconomyTypes.BuildingKind.ROAD:
			return road_data
		EconomyTypes.BuildingKind.HOUSE:
			return house_data
		EconomyTypes.BuildingKind.BARRACKS:
			return barracks_data
		EconomyTypes.BuildingKind.STABLES:
			return stables_data
		EconomyTypes.BuildingKind.HANGAR:
			return hangar_data
		EconomyTypes.BuildingKind.WORKSHOP:
			return workshop_data
		EconomyTypes.BuildingKind.ALTAR:
			return altar_data
		EconomyTypes.BuildingKind.TRADING_HALL:
			return trading_hall_data
		EconomyTypes.BuildingKind.WATCH_TOWER:
			return watch_tower_data
		EconomyTypes.BuildingKind.WALL:
			return wall_data
		EconomyTypes.BuildingKind.GATE:
			return gate_data
		EconomyTypes.BuildingKind.OUTPOST:
			return outpost_data
		_:
			return null

func trade_selected_resource(from_resource_type: int, to_resource_type: int, from_amount: int = 100, to_amount: int = 50):
	if resource_manager == null or not resource_manager.has_method("spend_resources"):
		_record_action("ResourceManager not connected")
		return

	var nation = get_selected_nation()
	if not bool(resource_manager.call("spend_resources", nation, {from_resource_type: from_amount})):
		_record_action("Trade failed: not enough %s" % EconomyTypes.get_resource_name(from_resource_type))
		return

	resource_manager.call("add_resource", nation, to_resource_type, to_amount)
	_record_action("Traded %s %s for %s %s" % [
		from_amount,
		EconomyTypes.get_resource_name(from_resource_type),
		to_amount,
		EconomyTypes.get_resource_name(to_resource_type)
	])

func get_debug_text() -> String:
	var pending_text = " | Pending %s node" % EconomyTypes.get_resource_name(pending_resource_node_type) if is_resource_node_placement_armed() else ""
	return "%s%s | Owner %s | Free %s | Ignore %s | 1-5 +100 resources, 6 +500 all, F free, I ignore, N owner, R wood node, T contest" % [
		last_action if not last_action.is_empty() else "Economy debug ready",
		pending_text,
		_get_display_name(get_selected_nation()),
		"On" if is_free_build_mode() else "Off",
		"On" if is_ignore_placement_rules_mode() else "Off"
	]

func get_current_debug_summary() -> String:
	var pending_text = " | Pending %s node" % EconomyTypes.get_resource_name(pending_resource_node_type) if is_resource_node_placement_armed() else ""
	return "Economy | %s%s | Owner: %s | Free: %s | Ignore: %s" % [
		last_action if not last_action.is_empty() else "Ready",
		pending_text,
		_get_display_name(get_selected_nation()),
		"On" if is_free_build_mode() else "Off",
		"On" if is_ignore_placement_rules_mode() else "Off"
	]

func get_debug_state() -> Dictionary:
	var closest_node = get_closest_resource_node_to_mouse()
	var node_state = closest_node.get_debug_state() if closest_node != null and closest_node.has_method("get_debug_state") else {}
	return {
		"selected_nation": _get_display_name(get_selected_nation()),
		"free_build_mode": is_free_build_mode(),
		"ignore_placement_rules_mode": is_ignore_placement_rules_mode(),
		"last_action": last_action,
		"closest_resource_node": node_state,
		"pending_resource_node_type": pending_resource_node_type,
		"pending_resource_node_name": EconomyTypes.get_resource_name(pending_resource_node_type) if is_resource_node_placement_armed() else "None"
	}

func get_debug_shortcuts() -> Array:
	return [
		{"keys": "1-5", "description": "Add +100 Wood/Food/Gold/Stone/Metal"},
		{"keys": "6", "description": "Add +500 all resources"},
		{"keys": "F", "description": "Toggle free build"},
		{"keys": "I", "description": "Toggle ignore placement rules"},
		{"keys": "N", "description": "Cycle debug owner"},
		{"keys": "R", "description": "Spawn wood resource node"},
		{"keys": "T", "description": "Spawn enemy combat unit near closest resource node"}
	]

func _discover_references():
	if resource_manager == null:
		resource_manager = get_tree().get_first_node_in_group("resource_manager")
	if road_supply_manager == null:
		road_supply_manager = get_tree().get_first_node_in_group("road_supply_manager")
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")
	if run_diplomacy_manager == null:
		run_diplomacy_manager = get_tree().get_first_node_in_group("run_diplomacy_manager")

	if nation_options.is_empty() and placement_manager != null and _has_property(placement_manager, "nation_options"):
		for nation in placement_manager.get("nation_options"):
			if nation is Resource:
				nation_options.append(nation)

	if nation_options.is_empty() and run_diplomacy_manager != null and _has_property(run_diplomacy_manager, "known_nations"):
		for nation in run_diplomacy_manager.get("known_nations"):
			if nation is Resource:
				nation_options.append(nation)

func _load_default_resources():
	if resource_node_scene == null:
		resource_node_scene = load("res://scenes/resources/resource_node.tscn") as PackedScene
	if worker_unit_data == null:
		worker_unit_data = load("res://data/units/prototypes/GeneralWorkerData.tres") as UnitData
	if lumber_worker_unit_data == null:
		lumber_worker_unit_data = load("res://data/units/prototypes/LumberWorkerData.tres") as UnitData
	if farm_worker_unit_data == null:
		farm_worker_unit_data = load("res://data/units/prototypes/FarmWorkerData.tres") as UnitData
	if mine_worker_unit_data == null:
		mine_worker_unit_data = load("res://data/units/prototypes/MineWorkerData.tres") as UnitData
	if player_combat_unit_data == null:
		player_combat_unit_data = load("res://data/units/SoldierData.tres") as UnitData
	if enemy_combat_unit_data == null:
		enemy_combat_unit_data = load("res://data/units/GoblinData.tres") as UnitData

	capital_data = _load_resource_if_null(capital_data, "res://data/buildings/economy/CapitalData.tres")
	road_data = _load_resource_if_null(road_data, "res://data/buildings/economy/RoadData.tres")
	house_data = _load_resource_if_null(house_data, "res://data/buildings/economy/HouseData.tres")
	barracks_data = _load_resource_if_null(barracks_data, "res://data/buildings/economy/BarracksData.tres")
	stables_data = _load_resource_if_null(stables_data, "res://data/buildings/economy/StablesData.tres")
	hangar_data = _load_resource_if_null(hangar_data, "res://data/buildings/economy/HangarData.tres")
	workshop_data = _load_resource_if_null(workshop_data, "res://data/buildings/economy/WorkshopData.tres")
	altar_data = _load_resource_if_null(altar_data, "res://data/buildings/economy/AltarData.tres")
	trading_hall_data = _load_resource_if_null(trading_hall_data, "res://data/buildings/economy/TradingHallData.tres")
	watch_tower_data = _load_resource_if_null(watch_tower_data, "res://data/buildings/economy/WatchTowerData.tres")
	wall_data = _load_resource_if_null(wall_data, "res://data/buildings/economy/WallData.tres")
	gate_data = _load_resource_if_null(gate_data, "res://data/buildings/economy/GateData.tres")
	outpost_data = _load_resource_if_null(outpost_data, "res://data/buildings/economy/OutpostData.tres")

func _load_resource_if_null(current_resource: Resource, path: String) -> Resource:
	return current_resource if current_resource != null else load(path)

func _add_spawned_node(node: Node):
	if spawn_parent != null:
		spawn_parent.add_child(node)
		return

	get_tree().current_scene.add_child(node)

func _get_global_mouse_position() -> Vector2:
	var camera = get_viewport().get_camera_2d()

	if camera != null:
		return camera.get_global_mouse_position()

	return get_viewport().get_mouse_position()

func _record_action(text: String):
	last_action = text
	print("EconomyDebug: ", text)

func _pause_normal_placement_for_pending_node():
	if placement_manager == null or not _has_property(placement_manager, "placement_enabled"):
		return

	if not _has_placement_restore:
		_restore_placement_enabled = bool(placement_manager.get("placement_enabled"))
		_has_placement_restore = true

	# Keep placement input reserved so selection/gameplay clicks do not eat the pending node placement.
	placement_manager.set("placement_enabled", true)

func _restore_normal_placement_after_pending_node():
	if placement_manager != null and _has_property(placement_manager, "placement_enabled") and _has_placement_restore:
		placement_manager.set("placement_enabled", _restore_placement_enabled)

	_has_placement_restore = false

func _finish_pending_resource_node_placement():
	pending_resource_node_type = BuildingData.ResourceType.NONE
	_restore_normal_placement_after_pending_node()

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

func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return true

	return false
