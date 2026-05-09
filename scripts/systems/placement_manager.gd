extends Node
class_name PlacementManager

enum PlacementMode {
	UNITS,
	BUILDINGS
}

enum UnitCategory {
	ALL,
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

const UNIT_CATEGORY_COUNT := 7
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

@export var nation_options: Array[Resource] = []
@export var unit_options: Array[Resource] = []
@export var building_options: Array[Resource] = []

@export var unit_spawner: Node
@export var building_spawner: Node
@export var run_diplomacy_manager: Node
@export var grid_manager: Node
@export var grid_occupancy_manager: Node
@export var status_label: Label
@export var debug_active: bool = true

func _ready():
	_seed_run_diplomacy()
	_refresh_options_from_selected_nation()
	_update_status_label()

func _unhandled_input(event):
	if not debug_active or not placement_enabled:
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
		placement_enabled = not placement_enabled
		_update_status_label()
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

func toggle_mode():
	placement_mode = PlacementMode.BUILDINGS if placement_mode == PlacementMode.UNITS else PlacementMode.UNITS
	selected_index = 0
	_update_status_label()

func cycle_category(direction: int):
	if placement_mode != PlacementMode.UNITS:
		return

	selected_unit_category = wrapi(selected_unit_category + direction, 0, UNIT_CATEGORY_COUNT)
	selected_unit_archetype_index = 0
	selected_index = 0
	_update_status_label()

func cycle_archetype(direction: int):
	if placement_mode == PlacementMode.BUILDINGS:
		selected_building_category = wrapi(selected_building_category + direction, 0, BUILDING_CATEGORY_COUNT)
		selected_index = 0
		_update_status_label()
		return

	var archetypes = _get_unit_archetypes_for_selected_category()

	if archetypes.size() <= 1:
		return

	selected_unit_archetype_index = wrapi(selected_unit_archetype_index + direction, 0, archetypes.size())
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
	)
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

	if grid_occupancy_manager != null and not grid_occupancy_manager.can_occupy_world_position(snapped_world_position, footprint_width, footprint_height):
		print("Placement blocked: ", _get_display_name(selected_data), " at cell ", cell)
		return

	var spawned_node: Node2D = null
	var owner_nation = get_selected_nation()

	if placement_mode == PlacementMode.UNITS:
		spawned_node = unit_spawner.spawn_unit(selected_data, owner_nation, cell, selected_allegiance_override) if unit_spawner != null else null
	else:
		spawned_node = building_spawner.spawn_building(selected_data, owner_nation, cell, placed_buildings_auto_spawn, selected_allegiance_override) if building_spawner != null else null

	if spawned_node != null:
		print("Placed ", _get_display_name(selected_data), " at cell ", cell)

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

	unit_options = _resource_array(selected_nation.get("available_units"))
	building_options = _resource_array(selected_nation.get("available_buildings"))

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

	return "%s | Place: %s | Category: %s | Type: %s %s | Nation: %s | As: %s | Selected: %s | P placement, M mode, O side, G category, H type, N nation, Q/E select, 1-9 quick, LMB place, RMB next" % [
		state_name,
		mode_name,
		category_name,
		archetype_name,
		selection_position,
		nation_name,
		override_name,
		data_name
	]

func _get_selected_category_name() -> String:
	if placement_mode == PlacementMode.BUILDINGS:
		return "Buildings"

	match selected_unit_category:
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
