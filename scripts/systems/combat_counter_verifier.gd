extends RefCounted
class_name CombatCounterVerifier

const COMBAT_CLASS_NAMES = [
	"Infantry",
	"Ranged",
	"Cavalry",
	"Air",
	"Siege",
	"Champion",
	"Building",
	"Unknown"
]

var rules: CombatCounterRules = null
var test_results: Array[Dictionary] = []

func _init():
	rules = CombatDamage.get_default_rules()

func _ensure_rules() -> bool:
	if rules == null:
		rules = CombatDamage.get_default_rules()

	if rules == null:
		push_error("CombatCounterVerifier: Could not get CombatDamage default rules.")
		return false

	return true

func get_class_name(class_index: int) -> String:
	if class_index >= 0 and class_index < COMBAT_CLASS_NAMES.size():
		return COMBAT_CLASS_NAMES[class_index]

	return "Unknown"

func verify_all_counters():
	if not _ensure_rules():
		return

	print("\n" + "=".repeat(80))
	print("COMBAT COUNTER SYSTEM VERIFICATION")
	print("=".repeat(80) + "\n")

	test_results.clear()

	print("[CORE COUNTER CYCLE]")
	verify_counter("Infantry beats Ranged", 0, 1, 1.3)
	verify_counter("Ranged beats Air", 1, 3, 1.3)
	verify_counter("Air beats Cavalry", 3, 2, 1.3)
	verify_counter("Cavalry beats Infantry", 2, 0, 1.3)

	print("\n[REVERSE COUNTERS]")
	verify_counter("Ranged weak to Infantry", 1, 0, 0.8)
	verify_counter("Air weak to Ranged", 3, 1, 0.8)
	verify_counter("Cavalry weak to Air", 2, 3, 0.8)
	verify_counter("Infantry weak to Cavalry", 0, 2, 0.8)

	print("\n[SIEGE UNIT COUNTERS]")
	verify_counter("Infantry beats Siege", 0, 4, 1.2)
	verify_counter("Ranged beats Siege", 1, 4, 1.2)
	verify_counter("Cavalry beats Siege", 2, 4, 1.2)
	verify_counter("Air beats Siege", 3, 4, 1.2)

	print("\n[SIEGE WEAK AGAINST UNITS]")
	verify_counter("Siege weak vs Infantry", 4, 0, 0.5)
	verify_counter("Siege weak vs Ranged", 4, 1, 0.5)
	verify_counter("Siege weak vs Cavalry", 4, 2, 0.5)
	verify_counter("Siege weak vs Air", 4, 3, 0.5)

	print("\n[SIEGE STRONG VS BUILDINGS]")
	verify_counter("Siege strong vs Buildings", 4, 6, 2.0)

	print("\n[CHAMPION MULTIPLIERS]")
	verify_counter("Champion strong vs Infantry", 5, 0, 2.0)
	verify_counter("Champion strong vs Ranged", 5, 1, 2.0)
	verify_counter("Champion strong vs Cavalry", 5, 2, 2.0)
	verify_counter("Champion strong vs Air", 5, 3, 2.0)
	verify_counter("Champion strong vs Siege", 5, 4, 2.0)
	verify_counter("Champion neutral vs Champion", 5, 5, 1.0)
	verify_counter("Champion neutral vs Building", 5, 6, 1.0)

	
	print("\n" + "=".repeat(80))
	print_summary()
	print("=".repeat(80) + "\n")
func verify_counter(
	description: String,
	attacker_class: int,
	defender_class: int,
	expected_multiplier: float
):
	if not _ensure_rules():
		return

	var actual_multiplier = rules.get_multiplier(attacker_class, defender_class)
	var is_correct = abs(actual_multiplier - expected_multiplier) < 0.01

	var attacker_name = get_class_name(attacker_class)
	var defender_name = get_class_name(defender_class)

	var result = {
		"description": description,
		"attacker": attacker_class,
		"defender": defender_class,
		"expected": expected_multiplier,
		"actual": actual_multiplier,
		"correct": is_correct
	}

	test_results.append(result)

	if is_correct:
		print("  ✓ %s -> %s: %.2fx" % [attacker_name, defender_name, actual_multiplier])
	else:
		print("  ✗ %s -> %s: WRONG! Expected %.2fx, got %.2fx" % [
			attacker_name,
			defender_name,
			expected_multiplier,
			actual_multiplier
		])

func verify_champion_multiplier():
	if not _ensure_rules():
		return

	print("  Champion default multiplier: %.2fx" % rules.champion_default_multiplier)
	print("  Champions use this when not covered by specific rules.")

func print_summary():
	var passed := 0
	var failed := 0

	for result in test_results:
		if result.correct:
			passed += 1
		else:
			failed += 1

	print("SUMMARY: %d passed, %d failed" % [passed, failed])

	if failed > 0:
		print("\nFAILED TESTS:")
		for result in test_results:
			if not result.correct:
				print("  - %s: expected %.2fx, got %.2fx" % [
					result.description,
					result.expected,
					result.actual
				])

func print_counter_matrix():
	if not _ensure_rules():
		return

	print("\n" + "=".repeat(100))
	print("FULL COUNTER MATRIX")
	print("=".repeat(100))

	var classes = [0, 1, 2, 3, 4, 5, 6]

	var header = "%-12s" % "Attacker"

	for defender_class in classes:
		header += "%-12s" % get_class_name(defender_class)

	print(header)

	for attacker_class in classes:
		var row = "%-12s" % get_class_name(attacker_class)

		for defender_class in classes:
			var multiplier = rules.get_multiplier(attacker_class, defender_class)
			var marker = ""

			if multiplier > 1.1:
				marker = "+"
			elif multiplier < 0.9:
				marker = "-"

			var cell = "%.2f%s" % [multiplier, marker]
			row += "%-12s" % cell

		print(row)

	print("\nLegend: + = advantage, - = disadvantage, no symbol = neutral")
