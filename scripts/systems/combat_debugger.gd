extends Node
class_name CombatDebugger

@export var debug_active: bool = false
@export var log_to_console: bool = false
@export var max_events: int = 5

var recent_events: Array[String] = []
var counter_verifier: CombatCounterVerifier = null

func _ready():
	CombatDamage.debug_listener = self
	counter_verifier = CombatCounterVerifier.new()

func _exit_tree():
	if CombatDamage.debug_listener == self:
		CombatDamage.debug_listener = null

func set_debug_active(active: bool):
	debug_active = active

func get_debug_title() -> String:
	return "Combat"

func handle_debug_input(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false

	if event.keycode == KEY_C:
		recent_events.clear()
		return true

	if event.keycode == KEY_V:
		verify_counter_system()
		return true

	return false

func verify_counter_system():
	"""Run counter system verification and print results to console."""
	if counter_verifier == null:
		counter_verifier = CombatCounterVerifier.new()

	counter_verifier.verify_all_counters()
	counter_verifier.print_counter_matrix()

func get_debug_text() -> String:
	if recent_events.is_empty():
		return "No attacks recorded yet | C clear | V verify counters"

	return "%s | C clear | V verify" % " || ".join(recent_events)

func get_current_debug_summary() -> String:
	if recent_events.is_empty():
		return "Combat | No attacks recorded"

	return "Combat | %s" % recent_events[0]

func get_debug_state() -> Dictionary:
	return {
		"recent_events": recent_events.duplicate(),
		"log_to_console": log_to_console,
		"max_events": max_events
	}

func get_debug_shortcuts() -> Array:
	return [
		{"keys": "C", "description": "Clear combat events"},
		{"keys": "V", "description": "Verify and print combat counter matrix"}
	]

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
