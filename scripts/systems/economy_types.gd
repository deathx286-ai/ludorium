extends RefCounted
class_name EconomyTypes

enum WorkerType {
	NONE,
	LUMBER,
	FARM,
	MINE,
	GENERAL
}

enum BuildingKind {
	AUTO,
	CAPITAL,
	ROAD,
	HOUSE,
	BARRACKS,
	STABLES,
	HANGAR,
	WORKSHOP,
	ALTAR,
	TRADING_HALL,
	WATCH_TOWER,
	WALL,
	GATE,
	OUTPOST,
	RESOURCE_CAMP,
	OTHER
}

enum PlacementFailure {
	OK,
	NOT_ENOUGH_RESOURCES,
	NOT_ADJACENT_TO_ROAD,
	OUTSIDE_SUPPLY_RADIUS,
	ROAD_NOT_CONNECTED,
	OUTPOST_TOO_CLOSE_TO_ANCHOR,
	OCCUPIED_CELL,
	INVALID_TERRAIN,
	MISSING_REQUIRED_ROAD_CONNECTION,
	RESOURCE_NODE_COLLISION,
	INVALID_OWNER_NATION,
	UNSUPPORTED_BUILDING_TYPE,
	MISSING_BUILDING_DATA
}

const RESOURCE_TYPES := [
	BuildingData.ResourceType.WOOD,
	BuildingData.ResourceType.FOOD,
	BuildingData.ResourceType.GOLD,
	BuildingData.ResourceType.STONE,
	BuildingData.ResourceType.METAL
]

static func get_resource_name(resource_type: int) -> String:
	match resource_type:
		BuildingData.ResourceType.WOOD:
			return "Wood"
		BuildingData.ResourceType.FOOD:
			return "Food"
		BuildingData.ResourceType.GOLD:
			return "Gold"
		BuildingData.ResourceType.STONE:
			return "Stone"
		BuildingData.ResourceType.METAL:
			return "Metal"
		_:
			return "None"

static func get_resource_key(resource_type: int) -> String:
	return get_resource_name(resource_type).to_lower()

static func get_resource_type_from_key(resource_key: String) -> int:
	match resource_key.strip_edges().to_lower():
		"wood":
			return BuildingData.ResourceType.WOOD
		"food":
			return BuildingData.ResourceType.FOOD
		"gold":
			return BuildingData.ResourceType.GOLD
		"stone":
			return BuildingData.ResourceType.STONE
		"metal":
			return BuildingData.ResourceType.METAL
		_:
			return BuildingData.ResourceType.NONE

static func get_worker_type_name(worker_type: int) -> String:
	match worker_type:
		WorkerType.LUMBER:
			return "Lumber"
		WorkerType.FARM:
			return "Farm"
		WorkerType.MINE:
			return "Mine"
		WorkerType.GENERAL:
			return "General"
		_:
			return "None"

static func get_building_kind_name(building_kind: int) -> String:
	match building_kind:
		BuildingKind.CAPITAL:
			return "Capital"
		BuildingKind.ROAD:
			return "Road"
		BuildingKind.HOUSE:
			return "House"
		BuildingKind.BARRACKS:
			return "Barracks"
		BuildingKind.STABLES:
			return "Stables"
		BuildingKind.HANGAR:
			return "Hangar"
		BuildingKind.WORKSHOP:
			return "Workshop"
		BuildingKind.ALTAR:
			return "Altar"
		BuildingKind.TRADING_HALL:
			return "Trading Hall"
		BuildingKind.WATCH_TOWER:
			return "Watch Tower"
		BuildingKind.WALL:
			return "Wall"
		BuildingKind.GATE:
			return "Gate"
		BuildingKind.OUTPOST:
			return "Outpost"
		BuildingKind.RESOURCE_CAMP:
			return "Resource Camp"
		BuildingKind.OTHER:
			return "Other"
		_:
			return "Auto"

static func get_placement_failure_reason(failure: int) -> String:
	match failure:
		PlacementFailure.NOT_ENOUGH_RESOURCES:
			return "not enough resources"
		PlacementFailure.NOT_ADJACENT_TO_ROAD:
			return "not adjacent to road"
		PlacementFailure.OUTSIDE_SUPPLY_RADIUS:
			return "outside supply radius"
		PlacementFailure.ROAD_NOT_CONNECTED:
			return "road not connected"
		PlacementFailure.OUTPOST_TOO_CLOSE_TO_ANCHOR:
			return "outpost too close to another anchor"
		PlacementFailure.OCCUPIED_CELL:
			return "occupied cell"
		PlacementFailure.INVALID_TERRAIN:
			return "invalid terrain"
		PlacementFailure.MISSING_REQUIRED_ROAD_CONNECTION:
			return "missing required road connection"
		PlacementFailure.RESOURCE_NODE_COLLISION:
			return "resource node collision/overlap"
		PlacementFailure.INVALID_OWNER_NATION:
			return "invalid owner/nation"
		PlacementFailure.UNSUPPORTED_BUILDING_TYPE:
			return "unsupported building type"
		PlacementFailure.MISSING_BUILDING_DATA:
			return "missing building data"
		_:
			return "valid"

static func normalize_cost(cost: Dictionary) -> Dictionary:
	var normalized := {}

	for resource_type in RESOURCE_TYPES:
		normalized[resource_type] = 0

	for key in cost.keys():
		var resource_type = BuildingData.ResourceType.NONE

		if key is int:
			resource_type = int(key)
		else:
			resource_type = get_resource_type_from_key(str(key))

		if resource_type == BuildingData.ResourceType.NONE:
			continue

		normalized[resource_type] = maxi(int(cost[key]), 0)

	return normalized

static func format_cost(cost: Dictionary) -> String:
	var normalized = normalize_cost(cost)
	var parts: Array[String] = []

	for resource_type in RESOURCE_TYPES:
		var amount = int(normalized.get(resource_type, 0))
		if amount > 0:
			parts.append("%s %s" % [amount, get_resource_name(resource_type)])

	return "Free" if parts.is_empty() else ", ".join(parts)

static func get_cost_for_building_data(building_data: Resource) -> Dictionary:
	if building_data == null:
		return {}

	var data_cost = _get_property_or_default(building_data, "resource_cost", {})
	if data_cost is Dictionary and not data_cost.is_empty():
		return normalize_cost(data_cost)

	var cost := {}
	for resource_type in RESOURCE_TYPES:
		var property_name = "%s_cost" % get_resource_key(resource_type)
		var amount = int(_get_property_or_default(building_data, property_name, 0))
		if amount > 0:
			cost[resource_type] = amount

	if not cost.is_empty():
		return normalize_cost(cost)

	return get_default_cost_for_building_kind(get_building_kind_for_data(building_data))

static func get_default_cost_for_building_kind(building_kind: int) -> Dictionary:
	match building_kind:
		BuildingKind.ROAD:
			return normalize_cost({"wood": 5, "stone": 5})
		BuildingKind.HOUSE:
			return normalize_cost({"wood": 40})
		BuildingKind.BARRACKS:
			return normalize_cost({"wood": 120, "stone": 60})
		BuildingKind.STABLES:
			return normalize_cost({"wood": 120, "food": 80})
		BuildingKind.HANGAR:
			return normalize_cost({"wood": 120, "metal": 120, "gold": 80})
		BuildingKind.WORKSHOP:
			return normalize_cost({"stone": 120, "metal": 80})
		BuildingKind.ALTAR:
			return normalize_cost({"stone": 140, "gold": 120, "metal": 80})
		BuildingKind.TRADING_HALL:
			return normalize_cost({"wood": 100, "stone": 80, "gold": 80})
		BuildingKind.WATCH_TOWER:
			return normalize_cost({"wood": 40, "stone": 120})
		BuildingKind.WALL:
			return normalize_cost({"stone": 20})
		BuildingKind.GATE:
			return normalize_cost({"stone": 60, "metal": 30})
		BuildingKind.OUTPOST:
			return normalize_cost({"wood": 160, "stone": 120, "gold": 80})
		BuildingKind.CAPITAL:
			return normalize_cost({"wood": 500, "food": 250, "gold": 250, "stone": 250, "metal": 150})
		_:
			return normalize_cost({"wood": 80, "stone": 40})

static func get_building_kind_for_data(building_data: Resource) -> int:
	if building_data == null:
		return BuildingKind.AUTO

	var explicit_kind = int(_get_property_or_default(building_data, "building_kind", BuildingKind.AUTO))
	if explicit_kind != BuildingKind.AUTO:
		return explicit_kind

	var id_text = str(_get_property_or_default(building_data, "building_id", "")).to_lower()
	var name_text = str(_get_property_or_default(building_data, "display_name", "")).to_lower()
	var tags = _get_string_array(_get_property_or_default(building_data, "building_tags", []))
	var haystack = "%s %s %s" % [id_text, name_text, " ".join(tags)]

	if haystack.contains("capital") or haystack.contains("town_center") or haystack.contains("keep"):
		return BuildingKind.CAPITAL
	if haystack.contains("outpost"):
		return BuildingKind.OUTPOST
	if haystack.contains("road"):
		return BuildingKind.ROAD
	if haystack.contains("house") or haystack.contains("home"):
		return BuildingKind.HOUSE
	if haystack.contains("barracks"):
		return BuildingKind.BARRACKS
	if haystack.contains("stable"):
		return BuildingKind.STABLES
	if haystack.contains("hangar"):
		return BuildingKind.HANGAR
	if haystack.contains("workshop") or haystack.contains("forge") or haystack.contains("foundry"):
		return BuildingKind.WORKSHOP
	if haystack.contains("altar"):
		return BuildingKind.ALTAR
	if haystack.contains("trading") or haystack.contains("trade") or haystack.contains("exchange") or haystack.contains("market"):
		return BuildingKind.TRADING_HALL
	if haystack.contains("tower") or bool(_get_property_or_default(building_data, "is_defense_building", false)):
		return BuildingKind.WATCH_TOWER
	if bool(_get_property_or_default(building_data, "is_gate", false)) or haystack.contains("gate"):
		return BuildingKind.GATE
	if bool(_get_property_or_default(building_data, "is_wall", false)) or haystack.contains("wall"):
		return BuildingKind.WALL
	if bool(_get_property_or_default(building_data, "is_resource_building", false)):
		return BuildingKind.RESOURCE_CAMP
	if bool(_get_property_or_default(building_data, "is_production_building", false)):
		return BuildingKind.BARRACKS

	return BuildingKind.OTHER

static func is_supply_anchor_kind(building_kind: int) -> bool:
	return building_kind == BuildingKind.CAPITAL or building_kind == BuildingKind.OUTPOST

static func is_road_connector_kind(building_kind: int) -> bool:
	return building_kind == BuildingKind.ROAD or building_kind == BuildingKind.GATE or is_supply_anchor_kind(building_kind)

static func get_required_worker_for_resource(resource_type: int) -> int:
	match resource_type:
		BuildingData.ResourceType.WOOD:
			return WorkerType.LUMBER
		BuildingData.ResourceType.FOOD:
			return WorkerType.FARM
		BuildingData.ResourceType.GOLD, BuildingData.ResourceType.STONE, BuildingData.ResourceType.METAL:
			return WorkerType.MINE
		_:
			return WorkerType.NONE

static func worker_can_harvest(worker_type: int, required_worker_type: int) -> bool:
	return (
		worker_type == WorkerType.GENERAL
		or required_worker_type == WorkerType.NONE
		or worker_type == required_worker_type
	)

static func _get_string_array(value) -> Array[String]:
	var result: Array[String] = []

	if value == null:
		return result

	for item in value:
		result.append(str(item).to_lower())

	return result

static func _get_property_or_default(object: Object, property_name: String, default_value):
	if object == null:
		return default_value

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return object.get(property_name)

	return default_value
