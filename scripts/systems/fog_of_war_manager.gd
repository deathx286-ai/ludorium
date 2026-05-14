extends CanvasLayer
class_name FogOfWarManager

@export var visible_radius_tiles: int = 50
@export var fog_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var transition_speed: float = 2.0

var grid_manager: Node
var shroud_rect: ColorRect
var reveal_material: ShaderMaterial
var last_screen_to_world: Transform2D = Transform2D()
var last_center: Vector2 = Vector2.INF
var last_half_size_px: float = -1.0

func _ready():
	add_to_group("fog_of_war_manager")
	grid_manager = get_tree().get_first_node_in_group("grid_manager")
	
	_setup_shroud()

@export var follow_camera: bool = false

func _setup_shroud():
	shroud_rect = ColorRect.new()
	shroud_rect.name = "Shroud"
	shroud_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shroud_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shroud_rect.color = fog_color
	
	# Use a shader to reveal a square area
	reveal_material = ShaderMaterial.new()
	reveal_material.shader = Shader.new()
	reveal_material.shader.code = """
shader_type canvas_item;

uniform vec2 center_world;
uniform float half_size_world;
uniform mat4 screen_to_world_matrix;

void fragment() {
    // Convert screen coordinates to world coordinates
    vec4 world_pos = screen_to_world_matrix * vec4(FRAGCOORD.xy, 0.0, 1.0);
    
    vec2 diff = abs(world_pos.xy - center_world);
    float max_diff = max(diff.x, diff.y);
    
    // Smooth square reveal
    float alpha = smoothstep(half_size_world - 32.0, half_size_world, max_diff);
    
    COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
"""
	shroud_rect.material = reveal_material
	add_child(shroud_rect)

func _process(_delta):
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager")
		return
		
	var tile_size = grid_manager.tile_size
	var half_size_px = visible_radius_tiles * tile_size
	
	# Pass camera info to shader
	var camera = get_viewport().get_camera_2d()
	if camera != null:
		var canvas_transform = get_viewport().get_canvas_transform()
		var screen_to_world = canvas_transform.affine_inverse()
		var center = camera.global_position if follow_camera else Vector2.ZERO

		if (
			screen_to_world == last_screen_to_world
			and center == last_center
			and half_size_px == last_half_size_px
		):
			return

		last_screen_to_world = screen_to_world
		last_center = center
		last_half_size_px = half_size_px

		reveal_material.set_shader_parameter("center_world", center)
		reveal_material.set_shader_parameter("half_size_world", half_size_px)
		reveal_material.set_shader_parameter("screen_to_world_matrix", screen_to_world)
