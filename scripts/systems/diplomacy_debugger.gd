extends Node
class_name DiplomacyDebugger

@export var debugger_enabled: bool = true
@export var run_diplomacy_manager: Node
@export var status_label: Label
@export var selected_pair_index: int = 0
@export var debug_active: bool = false

var _pair_cache: Array = []
var _refresh_timer: float = 0.0

func _ready():
	_refresh_pair_cache()
	_update_status_label()

func _process(delta: float):
	if not debugger_enabled:
		return

	_refresh_timer -= delta

	if _refresh_timer > 0.0:
		return

	_refresh_timer = 0.5
	_refresh_pair_cache()
	_update_status_label()

func set_debug_active(active: bool):
	debug_active = active
	_update_status_label()

func get_debug_title() -> String:
	return "Diplomacy"

func handle_debug_input(event: InputEventKey) -> bool:
	if event.keycode == KEY_Q or event.keycode == KEY_BRACKETLEFT:
		cycle_pair(-1)
		return true
	elif event.keycode == KEY_E or event.keycode == KEY_BRACKETRIGHT:
		cycle_pair(1)
		return true
	elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
		cycle_selected_pair_relationship()
		return true

	return false

func cycle_pair(direction: int):
	_refresh_pair_cache()

	if _pair_cache.is_empty():
		return

	selected_pair_index = wrapi(selected_pair_index + direction, 0, _pair_cache.size())
	_update_status_label()

func cycle_selected_pair_relationship():
	var selected_pair = _get_selected_pair()

	if selected_pair.is_empty() or run_diplomacy_manager == null:
		return

	var current_relationship = UnitOwnershipComponent.Allegiance.NEUTRAL

	if run_diplomacy_manager.has_method("get_pairwise_relationship"):
		current_relationship = run_diplomacy_manager.get_pairwise_relationship(selected_pair[0], selected_pair[1])

	var next_relationship = _get_next_pairwise_relationship(current_relationship)

	if run_diplomacy_manager.has_method("set_pairwise_relationship"):
		run_diplomacy_manager.set_pairwise_relationship(selected_pair[0], selected_pair[1], next_relationship)

	_update_status_label()

func _refresh_pair_cache():
	_pair_cache.clear()

	if run_diplomacy_manager == null:
		return

	var nations: Array = run_diplomacy_manager.get("known_nations")

	for nation_a_index in range(nations.size()):
		var nation_a = nations[nation_a_index]

		if nation_a == null:
			continue

		for nation_b_index in range(nation_a_index + 1, nations.size()):
			var nation_b = nations[nation_b_index]

			if nation_b == null:
				continue

			_pair_cache.append([nation_a, nation_b])

	if not _pair_cache.is_empty():
		selected_pair_index = clampi(selected_pair_index, 0, _pair_cache.size() - 1)

func _update_status_label():
	if status_label == null:
		return

	status_label.visible = debug_active

	if not debug_active:
		return

	status_label.text = "DEBUG [Diplomacy] | %s" % get_debug_text()

func get_debug_text() -> String:
	if run_diplomacy_manager == null:
		return "No RunDiplomacyManager assigned"

	var player_nation = run_diplomacy_manager.get("selected_player_nation")
	var relationship_summaries: Array[String] = []
	var nations: Array = run_diplomacy_manager.get("known_nations")

	for nation in nations:
		if nation == null:
			continue

		var allegiance = run_diplomacy_manager.get_allegiance_for_nation(nation)
		relationship_summaries.append("%s %s" % [
			_get_display_name(nation),
			run_diplomacy_manager.get_allegiance_name(allegiance)
		])

	return "Player: %s | Nations: %s | Pair: %s | Q/E pair, Space relation" % [
		_get_display_name(player_nation),
		", ".join(relationship_summaries),
		_get_selected_pair_summary()
	]

func get_current_debug_summary() -> String:
	if run_diplomacy_manager == null:
		return "Diplomacy | Not connected"

	return "Diplomacy | %s | %s" % [
		_get_display_name(run_diplomacy_manager.get("selected_player_nation")),
		_get_selected_pair_summary()
	]

func get_debug_state() -> Dictionary:
	return {
		"selected_player_nation": _get_display_name(run_diplomacy_manager.get("selected_player_nation")) if run_diplomacy_manager != null else "Not connected",
		"selected_pair": _get_selected_pair_summary(),
		"relationship_summary": run_diplomacy_manager.get_relationship_summary() if run_diplomacy_manager != null and run_diplomacy_manager.has_method("get_relationship_summary") else "",
		"pairwise_summary": run_diplomacy_manager.get_pairwise_relationship_summary() if run_diplomacy_manager != null and run_diplomacy_manager.has_method("get_pairwise_relationship_summary") else ""
	}

func get_debug_shortcuts() -> Array:
	return [
		{"keys": "Q/E", "description": "Cycle diplomacy pair"},
		{"keys": "Space", "description": "Cycle selected relationship"}
	]

func _get_selected_pair() -> Array:
	if _pair_cache.is_empty():
		_refresh_pair_cache()

	if _pair_cache.is_empty():
		return []

	selected_pair_index = clampi(selected_pair_index, 0, _pair_cache.size() - 1)
	return _pair_cache[selected_pair_index]

func _get_selected_pair_summary() -> String:
	var selected_pair = _get_selected_pair()

	if selected_pair.is_empty():
		return "None"

	var relationship = UnitOwnershipComponent.Allegiance.NEUTRAL

	if run_diplomacy_manager != null and run_diplomacy_manager.has_method("get_pairwise_relationship"):
		relationship = run_diplomacy_manager.get_pairwise_relationship(selected_pair[0], selected_pair[1])

	return "%s <-> %s = %s" % [
		_get_display_name(selected_pair[0]),
		_get_display_name(selected_pair[1]),
		run_diplomacy_manager.get_allegiance_name(relationship)
	]

func _get_next_pairwise_relationship(current_relationship: UnitOwnershipComponent.Allegiance) -> UnitOwnershipComponent.Allegiance:
	match current_relationship:
		UnitOwnershipComponent.Allegiance.NEUTRAL:
			return UnitOwnershipComponent.Allegiance.ALLY
		UnitOwnershipComponent.Allegiance.ALLY:
			return UnitOwnershipComponent.Allegiance.ENEMY
		_:
			return UnitOwnershipComponent.Allegiance.NEUTRAL

func _get_display_name(resource: Resource) -> String:
	if resource == null:
		return "None"

	var display_name = str(resource.get("display_name"))
	if not display_name.is_empty():
		return display_name

	var nation_id = str(resource.get("nation_id"))
	if not nation_id.is_empty():
		return nation_id

	return resource.resource_path.get_file()
