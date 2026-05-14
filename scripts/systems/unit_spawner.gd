extends Node
class_name UnitSpawner

@export var base_unit_scene: PackedScene
@export var player_unit_scene: PackedScene
@export var ally_unit_scene: PackedScene
@export var enemy_unit_scene: PackedScene
@export var spawn_parent: Node
@export var run_diplomacy_manager: Node
@export var grid_manager: Node
@export var grid_occupancy_manager: Node

func _ready():
	add_to_group("unit_spawner")

func spawn_unit(unit_data: UnitData, owner_nation: Resource, cell: Vector2i, allegiance_override: int = 0) -> Node2D:
	if unit_data == null:
		return null

	var allegiance = _get_allegiance(owner_nation, allegiance_override)
	var scene = _get_scene_for_allegiance(allegiance)

	if scene == null:
		return null

	var unit = scene.instantiate() as Node2D

	if unit == null:
		return null

	unit.set("unit_data", unit_data)
	_set_cell_position(unit, cell, unit_data.footprint_width, unit_data.footprint_height)
	_assign_ownership(unit, owner_nation, allegiance)
	_assign_allegiance_groups(unit)
	_add_spawned_node(unit)
	_register_occupancy(unit)

	return unit

func _set_cell_position(unit: Node2D, cell: Vector2i, footprint_width: int, footprint_height: int):
	if grid_manager != null and grid_manager.has_method("cell_to_world"):
		unit.global_position = grid_manager.cell_to_world(cell)

	if grid_manager != null and grid_manager.has_method("snap_world_to_footprint_center"):
		unit.global_position = grid_manager.snap_world_to_footprint_center(unit.global_position, footprint_width, footprint_height)

func _get_scene_for_allegiance(allegiance: UnitOwnershipComponent.Allegiance) -> PackedScene:
	if allegiance == UnitOwnershipComponent.Allegiance.PLAYER and player_unit_scene != null:
		return player_unit_scene

	if allegiance == UnitOwnershipComponent.Allegiance.ALLY and ally_unit_scene != null:
		return ally_unit_scene

	if allegiance == UnitOwnershipComponent.Allegiance.ENEMY and enemy_unit_scene != null:
		return enemy_unit_scene

	return base_unit_scene

func _get_allegiance(owner_nation: Resource, allegiance_override: int = 0) -> UnitOwnershipComponent.Allegiance:
	var overridden_allegiance = _get_overridden_allegiance(allegiance_override)

	if overridden_allegiance != -1:
		return overridden_allegiance as UnitOwnershipComponent.Allegiance

	if run_diplomacy_manager != null and run_diplomacy_manager.has_method("get_allegiance_for_nation"):
		return int(run_diplomacy_manager.get_allegiance_for_nation(owner_nation)) as UnitOwnershipComponent.Allegiance

	if run_diplomacy_manager != null and run_diplomacy_manager.has_method("get_combat_allegiance_for_nation"):
		return int(run_diplomacy_manager.get_combat_allegiance_for_nation(owner_nation)) as UnitOwnershipComponent.Allegiance

	var owner_nation_id = str(owner_nation.get("nation_id")) if owner_nation != null else ""

	if owner_nation_id == "grimburrow":
		return UnitOwnershipComponent.Allegiance.ENEMY

	if owner_nation_id == "emberhold":
		return UnitOwnershipComponent.Allegiance.PLAYER

	return UnitOwnershipComponent.Allegiance.NEUTRAL

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

func _assign_ownership(unit: Node, owner_nation: Resource, allegiance: UnitOwnershipComponent.Allegiance):
	var ownership = unit.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

	if ownership == null:
		ownership = UnitOwnershipComponent.new()
		ownership.name = "UnitOwnershipComponent"
		unit.add_child(ownership)

	ownership.set_ownership(owner_nation, allegiance)

func _assign_allegiance_groups(unit: Node):
	var ownership = unit.get_node_or_null("UnitOwnershipComponent") as UnitOwnershipComponent

	if ownership == null:
		return

	for group_name in ["player", "enemy", "enemy_unit", "ally", "neutral"]:
		if unit.is_in_group(group_name):
			unit.remove_from_group(group_name)

	if ownership.is_player_owned():
		unit.add_to_group("player")
	elif ownership.is_enemy():
		unit.add_to_group("enemy")
		unit.add_to_group("enemy_unit")
	elif ownership.is_ally():
		unit.add_to_group("ally")
	else:
		unit.add_to_group("neutral")

func _add_spawned_node(unit: Node):
	if spawn_parent != null:
		spawn_parent.add_child(unit)
		return

	get_tree().current_scene.add_child(unit)

func _register_occupancy(unit: Node):
	if grid_occupancy_manager == null or not grid_occupancy_manager.has_method("register_node"):
		return

	if unit.get_node_or_null("TileMovementComponent") != null:
		return

	grid_occupancy_manager.register_node(unit)
