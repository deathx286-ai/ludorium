extends RefCounted
class_name UnitArchetypeStatRules

const MIN_ATTACK_COOLDOWN := 0.05

const DEFAULT_RULE := {
	"range_bonus": 0,
	"damage_bonus": 0,
	"max_health": -1,
	"attack_speed_multiplier": 1.0,
	"move_speed_multiplier": 1.0,
	"can_target_air": false,
	"can_attack_over_blocking_structures": false,
	"can_move_over_blocking_structures": false
}

const DOMAIN_RULES := {
	UnitClassification.UnitDomain.INFANTRY: {
		"range_bonus": 1,
		"damage_bonus": 50,
		"max_health": 150,
		"attack_speed_multiplier": 1.5,
		"move_speed_multiplier": 0.75,
		"can_target_air": false,
		"can_attack_over_blocking_structures": false,
		"can_move_over_blocking_structures": false
	},
	UnitClassification.UnitDomain.RANGED: {
		"range_bonus": 3,
		"damage_bonus": 25,
		"max_health": 75,
		"attack_speed_multiplier": 1.0,
		"move_speed_multiplier": 1.25,
		"can_target_air": true,
		"can_attack_over_blocking_structures": false,
		"can_move_over_blocking_structures": false
	},
	UnitClassification.UnitDomain.CAVALRY: {
		"range_bonus": 1,
		"damage_bonus": 75,
		"max_health": 250,
		"attack_speed_multiplier": 0.5,
		"move_speed_multiplier": 1.75,
		"can_target_air": false,
		"can_attack_over_blocking_structures": false,
		"can_move_over_blocking_structures": false
	},
	UnitClassification.UnitDomain.AIR: {
		"range_bonus": 2,
		"damage_bonus": 25,
		"max_health": 150,
		"attack_speed_multiplier": 0.75,
		"move_speed_multiplier": 1.5,
		"can_target_air": true,
		"can_attack_over_blocking_structures": false,
		"can_move_over_blocking_structures": true
	},
	UnitClassification.UnitDomain.SIEGE: {
		"range_bonus": 10,
		"damage_bonus": 150,
		"max_health": 500,
		"attack_speed_multiplier": 0.5,
		"move_speed_multiplier": 0.5,
		"can_target_air": false,
		"can_attack_over_blocking_structures": true,
		"can_move_over_blocking_structures": false
	}
}

static func get_rule_for_domain(unit_domain: int) -> Dictionary:
	var rule = DEFAULT_RULE.duplicate()
	var domain_rule = DOMAIN_RULES.get(unit_domain, {})

	for key in domain_rule.keys():
		rule[key] = domain_rule[key]

	return rule

static func get_rule_for_unit_data(unit_data: UnitData) -> Dictionary:
	if unit_data == null:
		return DEFAULT_RULE.duplicate()

	return get_rule_for_domain(unit_data.unit_domain)

static func apply_health(base_health: int, rule: Dictionary) -> int:
	var rule_health = int(rule.get("max_health", -1))

	if rule_health > 0:
		return rule_health

	return base_health

static func apply_damage(base_damage: int, rule: Dictionary) -> int:
	return base_damage + int(rule.get("damage_bonus", 0))

static func apply_range(base_range_tiles: float, rule: Dictionary) -> float:
	return base_range_tiles + float(rule.get("range_bonus", 0))

static func apply_attack_cooldown(base_cooldown: float, rule: Dictionary) -> float:
	var speed_multiplier = maxf(float(rule.get("attack_speed_multiplier", 1.0)), MIN_ATTACK_COOLDOWN)
	return maxf(base_cooldown / speed_multiplier, MIN_ATTACK_COOLDOWN)

static func apply_move_speed(base_move_speed: float, rule: Dictionary) -> float:
	return base_move_speed * float(rule.get("move_speed_multiplier", 1.0))
