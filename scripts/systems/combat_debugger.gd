extends Node
class_name CombatDebugger

@export var debug_active: bool = false
@export var log_to_console: bool = false
@export var max_events: int = 5

var recent_events: Array[String] = []

func _ready():
	CombatDamage.debug_listener = self

func _exit_tree():
	if CombatDamage.debug_listener == self:
		CombatDamage.debug_listener = null

func set_debug_active(active: bool):
	debug_active = active

func get_debug_title() -> String:
	return "Combat"

func handle_debug_input(event: InputEventKey) -> bool:
	if event.keycode == KEY_C:
		recent_events.clear()
		return true

	return false

func get_debug_text() -> String:
	if recent_events.is_empty():
		return "No attacks recorded yet | C clear"

	return "%s | C clear" % " || ".join(recent_events)

func record_damage_event(
	attacker: Node,
	defender: Node,
	attacker_class: int,
	defender_class: int,
	base_damage: int,
	multiplier: float,
	final_damage: int
):
	var event_text = "%s %s -> %s %s | base %s | x%.2f | final %s" % [
		_get_node_display_name(attacker),
		CombatCounterRules.get_combat_class_name(attacker_class),
		_get_node_display_name(defender),
		CombatCounterRules.get_combat_class_name(defender_class),
		base_damage,
		multiplier,
		final_damage
	]

	recent_events.push_front(event_text)

	while recent_events.size() > max_events:
		recent_events.pop_back()

	if log_to_console:
		print(event_text)

func _get_node_display_name(node: Node) -> String:
	if node == null:
		return "Unknown"

	var unit_data = CombatCounterRules.get_property_or_null(node, "unit_data")
	if unit_data != null:
		var unit_name = str(CombatCounterRules.get_property_or_null(unit_data, "display_name"))
		if not unit_name.is_empty():
			return unit_name

	var building_data = CombatCounterRules.get_property_or_null(node, "building_data")
	if building_data != null:
		var building_name = str(CombatCounterRules.get_property_or_null(building_data, "display_name"))
		if not building_name.is_empty():
			return building_name

	return node.name
