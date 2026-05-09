extends Node

var enemy_camps_total: int = 0
var enemy_camps_destroyed: int = 0

var enemies_killed: int = 0
var player_units_lost: int = 0

signal enemy_killed
signal camp_registered
signal camp_destroyed
signal victory_condition_met

func register_enemy_camp():
	enemy_camps_total += 1
	print("Enemy camp registered. Total camps: ", enemy_camps_total)
	emit_signal("camp_registered")

func register_enemy_kill():
	enemies_killed += 1
	print("Enemy killed. Total enemy kills: ", enemies_killed)
	emit_signal("enemy_killed")

func register_player_unit_lost():
	player_units_lost += 1
	print("Player unit lost. Total losses: ", player_units_lost)

func register_camp_destroyed():
	enemy_camps_destroyed += 1
	print("Camp destroyed: ", enemy_camps_destroyed, "/", enemy_camps_total)
	emit_signal("camp_destroyed")

	check_victory_condition()

func check_victory_condition():
	if enemy_camps_total > 0 and enemy_camps_destroyed >= enemy_camps_total:
		print("Victory condition met: all camps destroyed.")
		emit_signal("victory_condition_met")
