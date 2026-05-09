extends Resource
class_name CombatCounterRules

enum CombatClass {
	INFANTRY,
	RANGED,
	CAVALRY,
	AIR,
	SIEGE,
	CHAMPION,
	BUILDING,
	UNKNOWN
}

@export var default_multiplier: float = 1.0
@export var champion_default_multiplier: float = 1.0
@export var rules: Array[CombatCounterRule] = []

var _rule_lookup: Dictionary = {}

func get_multiplier_for_nodes(attacker: Node, defender: Node) -> float:
	return get_multiplier(
		get_combat_class_for_node(attacker),
		get_combat_class_for_node(defender)
	)

func get_multiplier(attacker_class: int, defender_class: int) -> float:
	_rebuild_lookup_if_needed()

	var key = _get_rule_key(attacker_class, defender_class)

	if _rule_lookup.has(key):
		return _rule_lookup[key]

	if attacker_class == CombatClass.CHAMPION or defender_class == CombatClass.CHAMPION:
		return champion_default_multiplier

	return default_multiplier

func _rebuild_lookup_if_needed():
	if not _rule_lookup.is_empty():
		return

	for rule in rules:
		if rule == null:
			continue

		_rule_lookup[_get_rule_key(rule.attacker_class, rule.defender_class)] = rule.multiplier

func _get_rule_key(attacker_class: int, defender_class: int) -> String:
	return "%s:%s" % [int(attacker_class), int(defender_class)]

static func get_combat_class_for_node(node: Node) -> CombatClass:
	if node == null:
		return CombatClass.UNKNOWN

	var building_data = get_property_or_null(node, "building_data")
	if building_data != null:
		return CombatClass.BUILDING

	var unit_data = get_property_or_null(node, "unit_data")
	if unit_data != null:
		return get_combat_class_for_unit_data(unit_data)

	var classification = node.get_node_or_null("UnitClassification") as UnitClassification
	if classification != null:
		return get_combat_class_for_domain(classification.unit_domain)

	return CombatClass.UNKNOWN

static func get_combat_class_for_unit_data(unit_data) -> CombatClass:
	if unit_data == null:
		return CombatClass.UNKNOWN

	if bool(get_property_or_null(unit_data, "is_structure")):
		return CombatClass.BUILDING

	return get_combat_class_for_domain(int(get_property_or_null(unit_data, "unit_domain")))

static func get_combat_class_for_domain(unit_domain: int) -> CombatClass:
	match unit_domain:
		UnitClassification.UnitDomain.INFANTRY:
			return CombatClass.INFANTRY
		UnitClassification.UnitDomain.RANGED:
			return CombatClass.RANGED
		UnitClassification.UnitDomain.CAVALRY:
			return CombatClass.CAVALRY
		UnitClassification.UnitDomain.SIEGE:
			return CombatClass.SIEGE
		UnitClassification.UnitDomain.AIR:
			return CombatClass.AIR
		UnitClassification.UnitDomain.CHAMPION:
			return CombatClass.CHAMPION
		UnitClassification.UnitDomain.STRUCTURE:
			return CombatClass.BUILDING

	return CombatClass.UNKNOWN

static func get_combat_class_name(combat_class: int) -> String:
	match combat_class:
		CombatClass.INFANTRY:
			return "Infantry"
		CombatClass.RANGED:
			return "Ranged"
		CombatClass.CAVALRY:
			return "Cavalry"
		CombatClass.AIR:
			return "Air"
		CombatClass.SIEGE:
			return "Siege"
		CombatClass.CHAMPION:
			return "Champion"
		CombatClass.BUILDING:
			return "Building"
		_:
			return "Unknown"

static func get_property_or_null(object: Object, property_name: String):
	if object == null:
		return null

	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return object.get(property_name)

	return null
