extends Node

var defeated_gods: Array[String] = []
var active_echo_blessing: String = ""
var active_divine_scar: String = ""

signal god_defeated(god_id: String)
signal divine_scar_added(god_id: String)

func register_god_defeated(god_id: String):
	if not defeated_gods.has(god_id):
		defeated_gods.append(god_id)

	print("God defeated: ", god_id)
	emit_signal("god_defeated", god_id)

func choose_echo_blessing(god_id: String):
	if defeated_gods.has(god_id):
		active_echo_blessing = god_id
		print("Echo blessing chosen from god: ", god_id)
	else:
		print("Cannot choose blessing. God not defeated: ", god_id)

func add_divine_scar(god_id: String):
	active_divine_scar = god_id
	print("Divine scar added from god: ", god_id)
	emit_signal("divine_scar_added", god_id)
