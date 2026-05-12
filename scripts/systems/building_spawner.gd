extends Node
class_name BuildingSpawner

@export var base_building_scene: PackedScene
@export var unit_spawner_building_scene: PackedScene
@export var spawn_parent: Node
@export var run_diplomacy_manager: Node
@export var grid_manager: Node
@export var grid_occupancy_manager: Node
@export var road_supply_manager: Node

func spawn_building(building_data: Resource, owner_nation: Resource, cell: Vector2i, auto_spawn_enabled: bool = false, allegiance_override: int = 0, under_construction: bool = false) -> Node2D:
	if building_data == null:
		return null

	var scene = _get_scene_for_building_data(building_data)

	if scene == null:
		return null

	var building = scene.instantiate() as Node2D

	if building == null:
		return null

	building.set("building_data", building_data)

	if _has_property(building, "auto_spawn_enabled"):
		building.set("auto_spawn_enabled", auto_spawn_enabled or bool(building_data.get("is_enemy_camp")))
		
	if under_construction and _has_property(building, "start_under_construction"):
		building.set("start_under_construction", true)

	_set_cell_position(
		building,
		cell,
		int(building_data.get("footprint_width")),
		int(building_data.get("footprint_height"))
	)
	_assign_ownership(building, owner_nation, allegiance_override)
	_assign_allegiance_groups(building)
	_add_spawned_node(building)
	_register_occupancy(building)
	_register_road_supply(building, building_data, owner_nation)

	return building

func _get_scene_for_building_data(building_data: Resource) -> PackedScene:
	if bool(building_data.get("is_enemy_camp")) and unit_spawner_building_scene != null:
		return unit_spawner_building_scene

	return base_building_scene

func _set_cell_position(building: Node2D, cell: Vector2i, footprint_width: int, footprint_height: int):
	if grid_manager != null and grid_manager.has_method("cell_to_world"):
		building.global_position = grid_manager.cell_to_world(cell)

	if grid_manager != null and grid_manager.has_method("snap_world_to_footprint_center"):
		building.global_position = grid_manager.snap_world_to_footprint_center(building.global_position, footprint_width, footprint_height)

func _assign_ownership(building: Node, owner_nation: Resource, allegiance_override: int = 0):
	var ownership = building.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

	if ownership == null:
		ownership = UnitOwnershipComponent.new()
		ownership.name = "UnitOwnershipComponent"
		building.add_child(ownership)

	var allegiance = _get_overridden_allegiance(allegiance_override)

	if allegiance != -1:
		pass
	elif run_diplomacy_manager != null and run_diplomacy_manager.has_method("get_allegiance_for_nation"):
		allegiance = run_diplomacy_manager.get_allegiance_for_nation(owner_nation)
	elif run_diplomacy_manager != null and run_diplomacy_manager.has_method("get_combat_allegiance_for_nation"):
		allegiance = run_diplomacy_manager.get_combat_allegiance_for_nation(owner_nation)
	else:
		allegiance = UnitOwnershipComponent.Allegiance.NEUTRAL

	ownership.set_ownership(owner_nation, allegiance)

func _get_overridden_allegiance(allegiance_override: int) -> int:
	match allegiance_override:
		1:
			return UnitOwnershipComponent.Allegiance.PLAYER
		2:
			return UnitOwnershipComponent.Allegiance.ALLY
		3:
			return UnitOwnershipComponent.Allegiance.ENEMY
		4:
			return UnitOwnershipComponent.Allegiance.NEUTRAL
		_:
			return -1

func _assign_allegiance_groups(building: Node):
	var ownership = building.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

	if ownership == null:
		return

	for group_name in ["player", "enemy", "ally", "neutral"]:
		if building.is_in_group(group_name):
			building.remove_from_group(group_name)

	if ownership.is_player_owned():
		building.add_to_group("player")
	elif ownership.is_enemy():
		building.add_to_group("enemy")
	elif ownership.is_ally():
		building.add_to_group("ally")
	else:
		building.add_to_group("neutral")

func _add_spawned_node(building: Node):
	if spawn_parent != null:
		spawn_parent.add_child(building)
		return

	get_tree().current_scene.add_child(building)

func _register_occupancy(building: Node):
	if grid_occupancy_manager == null or not grid_occupancy_manager.has_method("register_node"):
		return

	if building is BaseBuilding or building is UnitSpawnerBuilding:
		return

	grid_occupancy_manager.register_node(building)

func _register_road_supply(building: Node2D, building_data: Resource, owner_nation: Resource):
	if road_supply_manager == null or not is_instance_valid(road_supply_manager):
		road_supply_manager = get_tree().get_first_node_in_group("road_supply_manager")

	if road_supply_manager == null or not road_supply_manager.has_method("register_building"):
		return

	road_supply_manager.register_building(building, building_data, owner_nation)

func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return true

	return false
