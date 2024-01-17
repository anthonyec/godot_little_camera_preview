@tool

class_name CameraPreview
extends Control

enum CameraType {
	CAMERA_2D,
	CAMERA_3D
}

enum PinnedPosition {
	LEFT,
	RIGHT,
}

enum InteractionState {
	NONE,
	RESIZE,
	DRAG,

	# Animation is split into 2 seperate states so that the tween is only 
	# invoked once in the "start" state. 
	START_ANIMATE_INTO_PLACE,
	ANIMATE_INTO_PLACE,
}

const margin_3d: Vector2 = Vector2(20, 20)
const margin_2d: Vector2 = Vector2(40, 30)
const min_panel_width: float = 250
const max_panel_width_ratio: float = 0.6

@onready var panel: Panel = %Panel
@onready var placeholder: Panel = %Placeholder
@onready var preview_camera_3d: Camera3D = %Camera3D
@onready var preview_camera_2d: Camera2D = %Camera2D
@onready var sub_viewport: SubViewport = %SubViewport
@onready var sub_viewport_text_rect: TextureRect = %TextureRect
@onready var resize_left_handle: Button = %ResizeLeftHandle
@onready var resize_right_handle: Button = %ResizeRightHandle
@onready var lock_button: Button = %LockButton
@onready var gradient: TextureRect = %Gradient

var camera_type: CameraType = CameraType.CAMERA_3D
var pinned_position: PinnedPosition = PinnedPosition.RIGHT
var viewport_ratio: float = 1
var screen_scale: float = 1
var is_locked: bool
var show_controls: bool
var selected_camera_3d: Camera3D
var selected_camera_2d: Camera2D
var remote_transform_3d: RemoteTransform3D
var remote_transform_2d: RemoteTransform2D

var state: InteractionState = InteractionState.NONE
var initial_mouse_position: Vector2
var initial_panel_size: Vector2
var initial_panel_position: Vector2

func _ready() -> void:
	screen_scale = DisplayServer.screen_get_scale()
	
	# Setting texture to viewport in code instead of directly in the editor 
	# because otherwise an error "Path to node is invalid: Panel/SubViewport"
	# on first load. This is harmless but doesn't look great.
	#
	# This is a known issue:
	# https://github.com/godotengine/godot/issues/27790#issuecomment-499740220
	sub_viewport_text_rect.texture = sub_viewport.get_texture()

func _process(_delta: float) -> void:
	if not visible: return
	
	var window_width = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var window_height = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	viewport_ratio = window_height / window_width
	
	match state:
		InteractionState.NONE:
			# Constrain panel size to aspect ratio.
			panel.size.y = panel.size.x * viewport_ratio
			
			# Clamp size.
			panel.size = panel.size.clamp(
				Vector2(min_panel_width * screen_scale, min_panel_width * screen_scale * viewport_ratio),
				Vector2(size.x * max_panel_width_ratio, size.x * max_panel_width_ratio * viewport_ratio)
			)
			
			panel.position = get_pinned_position(pinned_position)
			
		InteractionState.RESIZE:
			var delta_mouse_position = initial_mouse_position - get_global_mouse_position()
		
			if pinned_position == PinnedPosition.LEFT:
				panel.size = initial_panel_size - delta_mouse_position
				
			if pinned_position == PinnedPosition.RIGHT:
				panel.size = initial_panel_size + delta_mouse_position
				
			# Constrain panel size to aspect ratio.
			panel.size.y = panel.size.x * viewport_ratio
			
			# Clamp size.
			panel.size = panel.size.clamp(
				Vector2(min_panel_width * screen_scale, min_panel_width * screen_scale * viewport_ratio),
				Vector2(size.x * max_panel_width_ratio, size.x * max_panel_width_ratio * viewport_ratio)
			)
			
			panel.position = get_pinned_position(pinned_position)
			
		InteractionState.DRAG:
			placeholder.size = panel.size
			
			var global_mouse_position = get_global_mouse_position()
			var offset = initial_mouse_position - initial_panel_position

			panel.global_position = global_mouse_position - offset

			if global_mouse_position.x < global_position.x + size.x / 2:
				pinned_position = PinnedPosition.LEFT
			else:
				pinned_position = PinnedPosition.RIGHT
				
			placeholder.position = get_pinned_position(pinned_position)
			
		InteractionState.START_ANIMATE_INTO_PLACE:
			var final_position: Vector2 = get_pinned_position(pinned_position)
			var tween = get_tree().create_tween()
			
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(panel, "position", final_position, 0.3)
			
			tween.finished.connect(func():
				panel.position = final_position
				state = InteractionState.NONE
			)
			
			state = InteractionState.ANIMATE_INTO_PLACE
			
	# I couldn't get `mouse_entered` and `mouse_exited` events to work 
	# nicely, so I use rect method instead. Plus using this method it's easy to
	# grow the hit area size.
	var panel_hover_rect = Rect2(panel.global_position, panel.size)
	panel_hover_rect = panel_hover_rect.grow(40)
	
	var mouse_position = get_global_mouse_position()
	
	show_controls = state != InteractionState.NONE or panel_hover_rect.has_point(mouse_position)
	
	# UI visibility.
	resize_left_handle.visible = show_controls and pinned_position == PinnedPosition.RIGHT
	resize_right_handle.visible = show_controls and pinned_position == PinnedPosition.LEFT
	lock_button.visible = show_controls or is_locked
	placeholder.visible = state == InteractionState.DRAG or state == InteractionState.ANIMATE_INTO_PLACE
	gradient.visible = show_controls
	
	# Sync camera settings.
	if camera_type == CameraType.CAMERA_3D and selected_camera_3d:
		# TODO: Don't think this is needed and can just assign `panel.size` directly.
		var viewport_size = Vector2(panel.size.x, panel.size.x * viewport_ratio)
		sub_viewport.size = viewport_size
		
		preview_camera_3d.fov = selected_camera_3d.fov
		preview_camera_3d.projection = selected_camera_3d.projection
		preview_camera_3d.size = selected_camera_3d.size
		preview_camera_3d.cull_mask = selected_camera_3d.cull_mask
		preview_camera_3d.keep_aspect = selected_camera_3d.keep_aspect
		preview_camera_3d.near = selected_camera_3d.near
		preview_camera_3d.far = selected_camera_3d.far
		preview_camera_3d.h_offset = selected_camera_3d.h_offset
		preview_camera_3d.v_offset = selected_camera_3d.v_offset
		preview_camera_3d.attributes = selected_camera_3d.attributes
		preview_camera_3d.environment = selected_camera_3d.environment
	
	if camera_type == CameraType.CAMERA_2D and selected_camera_2d:
		var ratio = window_width / panel.size.x
		
		# TODO: Is there a better way to fix this?
		# The camera border is visible sometimes due to pixel rounding. 
		# Subtract 1px from right and bottom to hide this.
		var hide_camera_border_fix = Vector2(1, 1)
		
		sub_viewport.size = panel.size
		sub_viewport.size_2d_override = (panel.size - hide_camera_border_fix) * ratio
		sub_viewport.size_2d_override_stretch = true

		preview_camera_2d.offset = selected_camera_2d.offset
		preview_camera_2d.zoom = selected_camera_2d.zoom
		preview_camera_2d.ignore_rotation = selected_camera_2d.ignore_rotation
		preview_camera_2d.anchor_mode = selected_camera_2d.anchor_mode
		preview_camera_2d.limit_left = selected_camera_2d.limit_left
		preview_camera_2d.limit_right = selected_camera_2d.limit_right
		preview_camera_2d.limit_top = selected_camera_2d.limit_top
		preview_camera_2d.limit_bottom = selected_camera_2d.limit_bottom

func link_with_camera_3d(camera_3d: Camera3D) -> void:
	# TODO: Camera may not be ready since this method is called in `_enter_tree` 
	# in the plugin because of a workaround for: 
	# https://github.com/godotengine/godot-proposals/issues/2081
	if not preview_camera_3d:
		return request_hide()
		
	var is_different_camera = camera_3d != preview_camera_3d
	
	# TODO: A bit messy.
	if is_different_camera:
		if preview_camera_3d.tree_exiting.is_connected(unlink_camera):
			preview_camera_3d.tree_exiting.disconnect(unlink_camera)
		
		if not camera_3d.tree_exiting.is_connected(unlink_camera):
			camera_3d.tree_exiting.connect(unlink_camera)
		
	sub_viewport.disable_3d = false
	sub_viewport.world_3d = camera_3d.get_world_3d()
		
	remote_transform_3d = RemoteTransform3D.new()
	
	remote_transform_3d.remote_path = preview_camera_3d.get_path()
	remote_transform_3d.use_global_coordinates = true
	
	camera_3d.add_child(remote_transform_3d)
	selected_camera_3d = camera_3d
	
	camera_type = CameraType.CAMERA_3D
	
func link_with_camera_2d(camera_2d: Camera2D) -> void:
	if not preview_camera_2d:
		return request_hide()
	
	var is_different_camera = camera_2d != preview_camera_2d
	
	# TODO: A bit messy.
	if is_different_camera:
		if preview_camera_2d.tree_exiting.is_connected(unlink_camera):
			preview_camera_2d.tree_exiting.disconnect(unlink_camera)
		
		if not camera_2d.tree_exiting.is_connected(unlink_camera):
			camera_2d.tree_exiting.connect(unlink_camera)
		
	sub_viewport.disable_3d = true
	sub_viewport.world_2d = camera_2d.get_world_2d()
		
	remote_transform_2d = RemoteTransform2D.new()
	
	remote_transform_2d.remote_path = preview_camera_2d.get_path()
	remote_transform_2d.use_global_coordinates = true
	
	camera_2d.add_child(remote_transform_2d)
	selected_camera_2d = camera_2d
	
	camera_type = CameraType.CAMERA_2D

func unlink_camera() -> void:
	if selected_camera_3d:
		selected_camera_3d.remove_child(remote_transform_3d)
		selected_camera_3d = null
	
	if selected_camera_2d:
		selected_camera_2d.remove_child(remote_transform_2d)
		selected_camera_2d = null
	
	is_locked = false
	lock_button.button_pressed = false
	
func request_hide() -> void:
	if is_locked: return
	visible = false
	
func request_show() -> void:
	visible = true
	
func get_pinned_position(pinned_position: PinnedPosition) -> Vector2:
	var margin: Vector2 = margin_3d
	
	if camera_type == CameraType.CAMERA_2D:
		margin = margin_2d
	
	match pinned_position:
		PinnedPosition.LEFT:
			return Vector2.ZERO - Vector2(0, panel.size.y) - Vector2(-margin.x, margin.y)
		PinnedPosition.RIGHT:
			return size - panel.size - margin
		_:
			assert(false, "Unknown pinned position %s" % str(pinned_position))
			
	return Vector2.ZERO

func _on_resize_handle_button_down() -> void:
	if state != InteractionState.NONE: return
	
	state = InteractionState.RESIZE
	initial_mouse_position = get_global_mouse_position()
	initial_panel_size = panel.size

func _on_resize_handle_button_up() -> void:
	state = InteractionState.NONE

func _on_drag_handle_button_down() -> void:
	if state != InteractionState.NONE: return
		
	state = InteractionState.DRAG
	initial_mouse_position = get_global_mouse_position()
	initial_panel_position = panel.global_position

func _on_drag_handle_button_up() -> void:
	if state != InteractionState.DRAG: return
	
	state = InteractionState.START_ANIMATE_INTO_PLACE

func _on_lock_button_pressed() -> void:
	is_locked = !is_locked
