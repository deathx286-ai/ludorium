extends Resource
class_name NationData

@export_group("Identity")
@export var nation_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var divine_faction_id: String = ""
@export var culture_tags: Array[String] = []
@export var nation_tags: Array[String] = []
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.BLACK
@export var banner_icon: Texture2D

@export_group("Units")
@export var available_units: Array[Resource] = []
@export var starting_units: Array[Resource] = []
@export var unique_units: Array[Resource] = []
@export var roster_categories: Array[Resource] = []

@export_group("Buildings")
@export var available_buildings: Array[Resource] = []
@export var resource_buildings: Array[Resource] = []
@export var military_buildings: Array[Resource] = []
@export var defense_buildings: Array[Resource] = []

func get_roster_category(category_id: String) -> Resource:
	for category in roster_categories:
		if category != null and category.get("category_id") == category_id:
			return category

	return null

func get_units_for_category(category_id: String) -> Array[Resource]:
	var category = get_roster_category(category_id)

	if category == null:
		return []

	if not category.has_method("get_all_units"):
		return []

	return category.call("get_all_units")

func get_unit_for_role(domain: UnitClassification.UnitDomain, archetype: UnitClassification.UnitArchetype, role: UnitClassification.UnitRole) -> Resource:
	for category in roster_categories:
		if category == null:
			continue

		if category.get("unit_domain") == domain and category.get("unit_archetype") == archetype and category.has_method("get_unit_for_role"):
			return category.call("get_unit_for_role", role)

	return null

func get_all_roster_units() -> Array[Resource]:
	var units: Array[Resource] = []

	for category in roster_categories:
		if category == null:
			continue

		if not category.has_method("get_all_units"):
			continue

		for unit_data in category.call("get_all_units"):
			if unit_data != null and not units.has(unit_data):
				units.append(unit_data)

	return units

func has_unit(unit_data: Resource) -> bool:
	if unit_data == null:
		return false

	return available_units.has(unit_data) or starting_units.has(unit_data) or unique_units.has(unit_data) or get_all_roster_units().has(unit_data)

func get_units_by_archetype(archetype: UnitClassification.UnitArchetype) -> Array[Resource]:
	var units: Array[Resource] = []

	for unit_data in get_all_roster_units():
		if unit_data != null and unit_data.get("unit_archetype") == archetype:
			units.append(unit_data)

	return units

func get_units_by_domain(domain: UnitClassification.UnitDomain) -> Array[Resource]:
	var units: Array[Resource] = []

	for unit_data in get_all_roster_units():
		if unit_data != null and unit_data.get("unit_domain") == domain:
			units.append(unit_data)

	return units

func get_buildings_by_resource_type(resource_type: int) -> Array[Resource]:
	var buildings: Array[Resource] = []

	for building_data in resource_buildings:
		if building_data != null and building_data.get("resource_type") == resource_type:
			buildings.append(building_data)

	return buildings

func get_resource_building(resource_type: int) -> Resource:
	var buildings = get_buildings_by_resource_type(resource_type)

	if buildings.is_empty():
		return null

	return buildings[0]

func get_all_buildings() -> Array[Resource]:
	var buildings: Array[Resource] = []

	for building_list in [available_buildings, resource_buildings, military_buildings, defense_buildings]:
		for building_data in building_list:
			if building_data != null and not buildings.has(building_data):
				buildings.append(building_data)

	return buildings

func has_building(building_data: Resource) -> bool:
	if building_data == null:
		return false

	return get_all_buildings().has(building_data)
