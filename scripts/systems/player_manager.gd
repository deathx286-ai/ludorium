extends Node

@export var starting_level: int = 1
@export var starting_xp: int = 0
@export var base_xp_needed: int = 25
@export var starting_gold: int = 0

var level: int
var current_xp: int
var xp_needed: int
var gold: int

var selected_nation: String = "Veridion"

signal xp_changed(current_xp: int, xp_needed: int)
signal level_changed(level: int)
signal gold_changed(gold: int)
signal player_leveled_up(level: int)

func _ready():
	level = starting_level
	current_xp = starting_xp
	xp_needed = base_xp_needed
	gold = starting_gold

	print_player_stats()

func gain_xp(amount: int):
	current_xp += amount
	print("Player gained ", amount, " XP.")

	check_level_up()

	emit_signal("xp_changed", current_xp, xp_needed)
	print_player_stats()

func check_level_up():
	while current_xp >= xp_needed:
		current_xp -= xp_needed
		level += 1

		xp_needed = int(base_xp_needed * pow(1.35, level - 1))

		print("LEVEL UP! Player is now level ", level)

		emit_signal("level_changed", level)
		emit_signal("player_leveled_up", level)

		var upgrade_manager = get_tree().get_first_node_in_group("upgrade_manager")
		if upgrade_manager != null:
			upgrade_manager.offer_upgrade_choices()

func gain_gold(amount: int):
	gold += amount
	emit_signal("gold_changed", gold)
	print("Player gained ", amount, " gold. Total: ", gold)

func spend_gold(amount: int) -> bool:
	if gold < amount:
		print("Not enough gold.")
		return false

	gold -= amount
	emit_signal("gold_changed", gold)
	print("Spent ", amount, " gold. Remaining: ", gold)
	return true

func print_player_stats():
	print("Player Level: ", level, " | XP: ", current_xp, "/", xp_needed, " | Gold: ", gold)
