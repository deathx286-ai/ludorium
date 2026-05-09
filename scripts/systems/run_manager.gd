extends Node

@export var selected_player_nation: Resource

var run_number: int = 1
var map_number: int = 1
var difficulty_level: int = 1

var active_upgrade_ids: Array[String] = []
var active_blessing_id: String = ""
var active_curse_id: String = ""

signal run_started
signal map_advanced(map_number: int)
signal run_ended

func start_new_run():
	map_number = 1
	difficulty_level = 1
	active_upgrade_ids.clear()
	active_blessing_id = ""
	active_curse_id = ""

	print("New run started.")
	emit_signal("run_started")

func advance_to_next_map():
	map_number += 1
	difficulty_level += 1

	print("Advanced to map ", map_number, ". Difficulty: ", difficulty_level)
	emit_signal("map_advanced", map_number)

func add_upgrade(upgrade_id: String):
	active_upgrade_ids.append(upgrade_id)
	print("Added run upgrade: ", upgrade_id)

func end_run():
	print("Run ended.")
	emit_signal("run_ended")
