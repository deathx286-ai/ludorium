extends Resource
class_name NationRosterCategory

@export var category_id: String = ""
@export var display_name: String = ""
@export var unit_domain: UnitClassification.UnitDomain = UnitClassification.UnitDomain.INFANTRY
@export var unit_archetype: UnitClassification.UnitArchetype = UnitClassification.UnitArchetype.LIGHT_INFANTRY
@export var slots: Array[Resource] = []

func get_slot_for_role(role: UnitClassification.UnitRole) -> Resource:
	for slot in slots:
		if slot != null and slot.get("unit_role") == role:
			return slot

	return null

func get_unit_for_role(role: UnitClassification.UnitRole) -> Resource:
	var slot = get_slot_for_role(role)

	if slot == null:
		return null

	return slot.get("unit_data")

func get_all_units() -> Array[Resource]:
	var units: Array[Resource] = []

	for slot in slots:
		var unit_data = slot.get("unit_data") if slot != null else null
		if unit_data != null and not units.has(unit_data):
			units.append(unit_data)

	return units

func has_role(role: UnitClassification.UnitRole) -> bool:
	return get_slot_for_role(role) != null
