extends Node

var available_upgrades: Array[Dictionary] = [
	{
		"id": "militia_surge",
		"name": "Militia Surge",
		"description": "Spawn extra soldiers after choosing this upgrade.",
		"tags": ["Infantry", "Swarm"]
	},
	{
		"id": "flame_weapons",
		"name": "Flame Weapons",
		"description": "Soldier attacks are upgraded with fire later.",
		"tags": ["Fire", "Damage"]
	},
	{
		"id": "battle_training",
		"name": "Battle Training",
		"description": "Soldiers gain improved combat stats.",
		"tags": ["Infantry", "Training"]
	}
]

var chosen_upgrades: Array[String] = []

signal upgrade_choices_offered(choices: Array)
signal upgrade_chosen(upgrade_id: String)

func offer_upgrade_choices():
	var choices = get_random_upgrade_choices(3)

	print("Upgrade choices offered:")
	for choice in choices:
		print("- ", choice["name"], ": ", choice["description"])

	emit_signal("upgrade_choices_offered", choices)

func get_random_upgrade_choices(amount: int) -> Array:
	var shuffled = available_upgrades.duplicate()
	shuffled.shuffle()

	return shuffled.slice(0, min(amount, shuffled.size()))

func choose_upgrade(upgrade_id: String):
	chosen_upgrades.append(upgrade_id)

	var run_manager = get_tree().get_first_node_in_group("run_manager")
	if run_manager != null:
		run_manager.add_upgrade(upgrade_id)

	apply_upgrade(upgrade_id)

	print("Upgrade chosen: ", upgrade_id)
	emit_signal("upgrade_chosen", upgrade_id)

func apply_upgrade(upgrade_id: String):
	match upgrade_id:
		"militia_surge":
			print("TODO: Spawn extra soldiers.")
		"flame_weapons":
			print("TODO: Add burn to soldier attacks.")
		"battle_training":
			print("TODO: Improve soldier stats.")
		_:
			print("Unknown upgrade: ", upgrade_id)
