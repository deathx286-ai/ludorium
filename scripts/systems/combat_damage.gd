extends RefCounted
class_name CombatDamage

const DEFAULT_RULES_PATH := "res://data/combat/default_combat_counter_rules.tres"

static var _default_rules: CombatCounterRules
static var debug_listener: Node = null

static func calculate_damage(base_damage: int, attacker: Node, defender: Node, rules: CombatCounterRules = null) -> int:
	var multiplier = get_damage_multiplier(attacker, defender, rules)
	var final_damage = maxi(int(round(float(base_damage) * multiplier)), 0)
	_record_debug_event(attacker, defender, base_damage, multiplier, final_damage)
	return final_damage

static func get_damage_multiplier(attacker: Node, defender: Node, rules: CombatCounterRules = null) -> float:
	var active_rules = rules if rules != null else get_default_rules()
	var multiplier = active_rules.get_multiplier_for_nodes(attacker, defender)

	if attacker != null and attacker.has_method("get_combat_damage_multiplier_against"):
		multiplier *= float(attacker.call("get_combat_damage_multiplier_against", defender))

	if defender != null and defender.has_method("get_received_combat_damage_multiplier_from"):
		multiplier *= float(defender.call("get_received_combat_damage_multiplier_from", attacker))

	return multiplier

static func _record_debug_event(attacker: Node, defender: Node, base_damage: int, multiplier: float, final_damage: int):
	if debug_listener == null or not is_instance_valid(debug_listener):
		return

	if not debug_listener.has_method("record_damage_event"):
		return

	var attacker_class = CombatCounterRules.get_combat_class_for_node(attacker)
	var defender_class = CombatCounterRules.get_combat_class_for_node(defender)
	debug_listener.call(
		"record_damage_event",
		attacker,
		defender,
		attacker_class,
		defender_class,
		base_damage,
		multiplier,
		final_damage
	)

static func get_default_rules() -> CombatCounterRules:
	if _default_rules == null:
		_default_rules = load(DEFAULT_RULES_PATH) as CombatCounterRules

	if _default_rules == null:
		_default_rules = CombatCounterRules.new()

	return _default_rules
