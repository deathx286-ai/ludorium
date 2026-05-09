@tool
extends RefCounted
class_name NationVisuals

const DEFAULT_PRIMARY_COLOR := Color(0.78, 0.78, 0.78, 1.0)
const DEFAULT_SECONDARY_COLOR := Color(0.22, 0.22, 0.22, 1.0)

const NATION_COLOR_OVERRIDES := {
	"emberhold": {
		"primary": Color(0.82, 0.12, 0.06, 1.0),
		"secondary": Color(1.0, 0.48, 0.08, 1.0),
	},
	"veridion": {
		"primary": Color(0.78, 0.78, 0.74, 1.0),
		"secondary": Color(0.95, 0.72, 0.23, 1.0),
	},
	"grimburrow": {
		"primary": Color(0.42, 0.27, 0.16, 1.0),
		"secondary": Color(0.48, 0.47, 0.43, 1.0),
	},
}

static var _gradient_texture_cache: Dictionary = {}

static func apply_owner_or_data_to_node(node: Node, source_data: Resource = null) -> bool:
	if node == null:
		return false

	var ownership = node.get_node_or_null("UnitOwnershipComponent")
	if ownership != null:
		var owner_nation = ownership.get("owner_nation") as Resource
		if owner_nation != null:
			return apply_to_node(node, owner_nation)

		var owner_id = str(ownership.get("owner_id"))
		if not owner_id.is_empty():
			return apply_to_node_by_id(node, owner_id)

	if source_data != null:
		var origin_nation_id = _get_string_property(source_data, "origin_nation_id")
		if not origin_nation_id.is_empty():
			return apply_to_node_by_id(node, origin_nation_id)

	return false

static func apply_to_node(node: Node, nation_data: Resource) -> bool:
	if node == null or nation_data == null:
		return false

	var nation_id = _get_string_property(nation_data, "nation_id")
	var colors = get_colors_for_nation(nation_data)
	return apply_colors_to_node(node, colors["primary"], colors["secondary"], nation_id)

static func apply_to_node_by_id(node: Node, nation_id: String) -> bool:
	if node == null or nation_id.is_empty():
		return false

	var colors = get_colors_for_nation_id(nation_id)
	return apply_colors_to_node(node, colors["primary"], colors["secondary"], nation_id)

static func apply_colors_to_node(node: Node, primary_color: Color, secondary_color: Color, _nation_id: String = "") -> bool:
	var sprite := _get_sprite(node)
	if sprite == null:
		return false

	sprite.texture = get_gradient_texture(primary_color, secondary_color)
	return true

static func get_colors_for_nation(nation_data: Resource) -> Dictionary:
	var nation_id = _get_string_property(nation_data, "nation_id")
	var override_colors = _get_override_colors(nation_id)
	if not override_colors.is_empty():
		return override_colors

	return {
		"primary": _get_color_property(nation_data, "primary_color", DEFAULT_PRIMARY_COLOR),
		"secondary": _get_color_property(nation_data, "secondary_color", DEFAULT_SECONDARY_COLOR),
	}

static func get_colors_for_nation_id(nation_id: String) -> Dictionary:
	var override_colors = _get_override_colors(nation_id)
	if not override_colors.is_empty():
		return override_colors

	return {
		"primary": DEFAULT_PRIMARY_COLOR,
		"secondary": DEFAULT_SECONDARY_COLOR,
	}

static func get_gradient_texture(primary_color: Color, secondary_color: Color) -> GradientTexture2D:
	var cache_key = "%s:%s" % [primary_color.to_html(), secondary_color.to_html()]
	if _gradient_texture_cache.has(cache_key):
		return _gradient_texture_cache[cache_key]

	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([primary_color, secondary_color])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.ONE

	_gradient_texture_cache[cache_key] = texture
	return texture

static func _get_sprite(node: Node) -> Sprite2D:
	var sprite := node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		return sprite

	return node.find_child("Sprite2D", true, false) as Sprite2D

static func _get_override_colors(nation_id: String) -> Dictionary:
	var normalized_id = nation_id.strip_edges().to_lower()
	if NATION_COLOR_OVERRIDES.has(normalized_id):
		return NATION_COLOR_OVERRIDES[normalized_id]

	return {}

static func _get_string_property(object: Object, property_name: String) -> String:
	if object == null or not _has_property(object, property_name):
		return ""

	return str(object.get(property_name))

static func _get_color_property(object: Object, property_name: String, fallback_color: Color) -> Color:
	if object == null or not _has_property(object, property_name):
		return fallback_color

	var value = object.get(property_name)
	if value is Color:
		return value

	return fallback_color

static func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if str(property.get("name")) == property_name:
			return true

	return false
