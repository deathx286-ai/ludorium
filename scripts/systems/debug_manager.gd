extends Node
class_name DebugManager

@export var debug_visible: bool = true
@export var active_tab_index: int = 0
@export var placement_manager: Node
@export var diplomacy_debugger: Node
@export var resources_debugger: Node
@export var combat_debugger: Node
@export var economy_debugger: Node
@export var debug_panel: Node
@export var status_label: Label
@export var show_status_bar: bool = true

var debug_tabs: Array[Node] = []
var _refresh_timer: float = 0.0

func _ready():
	debug_tabs.clear()

	for tab in [placement_manager, diplomacy_debugger, resources_debugger, combat_debugger, economy_debugger]:
		if tab != null:
			debug_tabs.append(tab)

	active_tab_index = clampi(active_tab_index, 0, maxi(debug_tabs.size() - 1, 0))
	_apply_active_tab()
	_update_status_label()

func _process(delta: float):
	if not debug_visible:
		return

	_refresh_timer -= delta

	if _refresh_timer > 0.0:
		return

	_refresh_timer = 0.2
	_update_status_label()

func _unhandled_input(event):
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.keycode == KEY_F1:
		debug_visible = not debug_visible
		_apply_active_tab()
		_update_status_label()
		get_viewport().set_input_as_handled()
		return

	if not debug_visible:
		return

	if event.keycode == KEY_TAB:
		cycle_tab(-1 if event.shift_pressed else 1)
		get_viewport().set_input_as_handled()
		return

	# Global placement toggle
	if event.keycode == KEY_P:
		var handled = false
		if placement_manager != null and placement_manager.has_method("toggle_placement_enabled"):
			placement_manager.call("toggle_placement_enabled")
			handled = true
		
		# Also cancel any specialized placements to ensure we truly return to gameplay
		if economy_debugger != null and economy_debugger.has_method("cancel_pending_resource_node_placement"):
			economy_debugger.call("cancel_pending_resource_node_placement")
		
		if handled:
			_update_status_label()
			get_viewport().set_input_as_handled()
			return

	var active_tab = get_active_tab()
	if active_tab != null and active_tab.has_method("handle_debug_input"):
		if bool(active_tab.call("handle_debug_input", event)):
			_update_status_label()
			get_viewport().set_input_as_handled()

func cycle_tab(direction: int):
	if debug_tabs.is_empty():
		return

	active_tab_index = wrapi(active_tab_index + direction, 0, debug_tabs.size())
	_apply_active_tab()
	_update_status_label()

func get_active_tab() -> Node:
	if debug_tabs.is_empty():
		return null

	active_tab_index = clampi(active_tab_index, 0, debug_tabs.size() - 1)
	return debug_tabs[active_tab_index]

func _apply_active_tab():
	for index in range(debug_tabs.size()):
		var tab = debug_tabs[index]

		if tab != null and tab.has_method("set_debug_active"):
			tab.call("set_debug_active", debug_visible and index == active_tab_index)

	if status_label != null:
		status_label.visible = false

	if debug_panel != null and debug_panel.has_method("set_debug_visible"):
		debug_panel.call("set_debug_visible", debug_visible)

func _update_status_label():
	if status_label == null:
		return

	if not show_status_bar or not debug_visible:
		status_label.visible = false
		return

	status_label.visible = true
	var active_tab = get_active_tab()

	if active_tab == null:
		status_label.text = "DEBUG | No tabs assigned | F1 hide/show"
		return

	var title = str(active_tab.call("get_debug_title")) if active_tab.has_method("get_debug_title") else active_tab.name
	var text = ""
	if active_tab.has_method("get_current_debug_summary"):
		text = str(active_tab.call("get_current_debug_summary"))
	elif active_tab.has_method("get_debug_text"):
		text = str(active_tab.call("get_debug_text"))

	status_label.text = "DEBUG: %s | %s | F1 hide/show | Tab switch" % [title, text]
