extends "res://scripts/units/enemy_unit.gd"

func die():
	if debug_logging:
		print("Ally died")
	super.die()
