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

	# Animation is split into 2 separate states so that the tween is only 
	# invoked once in the "start" state. 
	START_ANIMATE_INTO_PLACE,
	ANIMATE_INTO_PLACE,
}

const margin_3d: Vector2 = Vector2(10, 10)
const margin_2d: Vector2 = Vector2(20, 15)
const panel_margin: float = 2
const min_panel_size: float = 250

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
@onready var viewport_margin_container: MarginContainer = %ViewportMarginContainer
@onready var overlay_margin_container: MarginContainer = %OverlayMarginContainer
@onready var overlay_container: Control = %OverlayContainer

var _camera_type: CameraType = CameraType.CAMERA_3D
var _pinned_position: PinnedPosition = PinnedPosition.RIGHT
var _editor_scale: float = EditorInterface.get_editor_scale()
var _is_locked: bool
var _show_controls: bool
var _selected_camera_3d: Camera3D
var _selected_camera_2d: Camera2D

var _state: InteractionState = InteractionState.NONE
var _initial_mouse_position: Vector2
var _initial_panel_size: Vector2
var _initial_panel_position: Vector2

func _ready() -> void:
	# Set initial width.
	panel.size.x = min_panel_size * _editor_scale
	
	# Setting texture to viewport in code instead of directly in the editor 
	# because otherwise an error "Path to node is invalid: Panel/SubViewport"
	# on first load. This is harmless but doesn't look great.
	#
	# This is a known issue:
	# https://github.com/godotengine/godot/issues/27790#issuecomment-499740220
	sub_viewport_text_rect.texture = sub_viewport.get_texture()
	
	# From what I can tell there's something wrong with how an editor theme
	# scales when used within a plugin. It seems to ignore the screen scale. 
	# For instance, a 30x30px button will appear tiny on a retina display.
	#
	# Someone else had the issue with no luck:
	# https://forum.godotengine.org/t/how-to-scale-plugin-controls-to-look-the-same-in-4k-as-1080p/36151
	#
	# And seems Dialogic also scales buttons manually:
	# https://github.com/dialogic-godot/dialogic/blob/master/addons/dialogic/Editor/Common/sidebar.gd#L25C6-L38
	#
	# Maybe I don't know the correct way to do it, so for now the workaround is
	# to set the correct size in code using screen scale.
	var button_size: Vector2 = Vector2(30, 30) * _editor_scale
	var margin_size: int = int(panel_margin * _editor_scale)
	
	resize_left_handle.size = button_size
	resize_left_handle.pivot_offset = Vector2(0, 0) * _editor_scale
	
	resize_right_handle.size = button_size
	resize_right_handle.pivot_offset = Vector2(30, 30) * _editor_scale
	
	lock_button.size = button_size
	lock_button.pivot_offset = Vector2(0, 30) * _editor_scale
	
	viewport_margin_container.add_theme_constant_override("margin_left", margin_size)
	viewport_margin_container.add_theme_constant_override("margin_top", margin_size)
	viewport_margin_container.add_theme_constant_override("margin_right", margin_size)
	viewport_margin_container.add_theme_constant_override("margin_bottom", margin_size)
	
	overlay_margin_container.add_theme_constant_override("margin_left", margin_size)
	overlay_margin_container.add_theme_constant_override("margin_top", margin_size)
	overlay_margin_container.add_theme_constant_override("margin_right", margin_size)
	overlay_margin_container.add_theme_constant_override("margin_bottom", margin_size)
	
	# Parent node overlay size is not available on first ready, need to wait a 
	# frame for it to be drawn.
	await get_tree().process_frame
	
	# Anchors are set in code because setting them in the editor UI doesn't take
	# editor scale into account.
	resize_left_handle.position = Vector2(0, 0)
	resize_right_handle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	
	resize_right_handle.position = Vector2(overlay_container.size.x - button_size.x, 0)
	resize_right_handle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	
	lock_button.position = Vector2(0, overlay_container.size.y - button_size.y)
	lock_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)

func _process(_delta: float) -> void:
	if not visible: return
	
	match _state:
		InteractionState.NONE:
			panel.size = get_clamped_size(panel.size)
			panel.position = get_pinned_position(_pinned_position)
			
		InteractionState.RESIZE:
			var delta_mouse_position: Vector2 = _initial_mouse_position - get_global_mouse_position()
			var resized_size: Vector2 = panel.size
		
			if _pinned_position == PinnedPosition.LEFT:
				resized_size = _initial_panel_size - delta_mouse_position
				
			if _pinned_position == PinnedPosition.RIGHT:
				resized_size = _initial_panel_size + delta_mouse_position
			
			panel.size = get_clamped_size(resized_size)
			panel.position = get_pinned_position(_pinned_position)
			
		InteractionState.DRAG:
			placeholder.size = panel.size
			
			var global_mouse_position: Vector2 = get_global_mouse_position()
			var offset: Vector2 = _initial_mouse_position - _initial_panel_position

			panel.global_position = global_mouse_position - offset

			if global_mouse_position.x < global_position.x + size.x / 2:
				_pinned_position = PinnedPosition.LEFT
			else:
				_pinned_position = PinnedPosition.RIGHT
				
			placeholder.position = get_pinned_position(_pinned_position)
			
		InteractionState.START_ANIMATE_INTO_PLACE:
			var final_position: Vector2 = get_pinned_position(_pinned_position)
			var tween: Tween = get_tree().create_tween()
			
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(panel, "position", final_position, 0.3)
			
			tween.finished.connect(func() -> void:
				panel.position = final_position
				_state = InteractionState.NONE
			)
			
			_state = InteractionState.ANIMATE_INTO_PLACE
			
	# I couldn't get `mouse_entered` and `mouse_exited` events to work 
	# nicely, so I use rect method instead. Plus using this method it's easy to
	# grow the hit area size.
	var panel_hover_rect: Rect2 = Rect2(panel.global_position, panel.size)
	panel_hover_rect = panel_hover_rect.grow(40)
	
	var mouse_position: Vector2 = get_global_mouse_position()
	
	_show_controls = _state != InteractionState.NONE or panel_hover_rect.has_point(mouse_position)
	
	# UI visibility.
	resize_left_handle.visible = _show_controls and _pinned_position == PinnedPosition.RIGHT
	resize_right_handle.visible = _show_controls and _pinned_position == PinnedPosition.LEFT
	lock_button.visible = _show_controls or _is_locked
	placeholder.visible = _state == InteractionState.DRAG or _state == InteractionState.ANIMATE_INTO_PLACE
	gradient.visible = _show_controls
	
	# Sync camera settings.
	if _camera_type == CameraType.CAMERA_3D and _selected_camera_3d:
		sub_viewport.size = panel.size
		
		# Sync position and rotation without using a `RemoteTransform` node 
		# because if you save a camera as a scene, the remote transform node will
		# be stored within the scene. Also it's harder to keep the remote 
		# transform `remote_path` up-to-date with scene changes, which causes 
		# many errors.
		preview_camera_3d.global_position = _selected_camera_3d.global_position
		preview_camera_3d.global_rotation = _selected_camera_3d.global_rotation
		
		preview_camera_3d.fov = _selected_camera_3d.fov
		preview_camera_3d.projection = _selected_camera_3d.projection
		preview_camera_3d.size = _selected_camera_3d.size
		preview_camera_3d.cull_mask = _selected_camera_3d.cull_mask
		preview_camera_3d.keep_aspect = _selected_camera_3d.keep_aspect
		preview_camera_3d.near = _selected_camera_3d.near
		preview_camera_3d.far = _selected_camera_3d.far
		preview_camera_3d.h_offset = _selected_camera_3d.h_offset
		preview_camera_3d.v_offset = _selected_camera_3d.v_offset
		preview_camera_3d.attributes = _selected_camera_3d.attributes
		preview_camera_3d.environment = _selected_camera_3d.environment
	
	if _camera_type == CameraType.CAMERA_2D and _selected_camera_2d:
		var project_window_size: Vector2 = get_project_window_size()
		var ratio: float = project_window_size.x / panel.size.x
		
		# TODO: Is there a better way to fix this?
		# The camera border is visible sometimes due to pixel rounding. 
		# Subtract 1px from right and bottom to hide this.
		var hide_camera_border_fix: Vector2 = Vector2(1, 1)
		
		sub_viewport.size = panel.size
		sub_viewport.size_2d_override = (panel.size - hide_camera_border_fix) * ratio
		sub_viewport.size_2d_override_stretch = true
		
		preview_camera_2d.global_position = _selected_camera_2d.global_position
		preview_camera_2d.global_rotation = _selected_camera_2d.global_rotation

		preview_camera_2d.offset = _selected_camera_2d.offset
		preview_camera_2d.zoom = _selected_camera_2d.zoom
		preview_camera_2d.ignore_rotation = _selected_camera_2d.ignore_rotation
		preview_camera_2d.anchor_mode = _selected_camera_2d.anchor_mode
		preview_camera_2d.limit_left = _selected_camera_2d.limit_left
		preview_camera_2d.limit_right = _selected_camera_2d.limit_right
		preview_camera_2d.limit_top = _selected_camera_2d.limit_top
		preview_camera_2d.limit_bottom = _selected_camera_2d.limit_bottom

func link_with_camera_3d(camera_3d: Camera3D) -> void:
	# TODO: Camera may not be ready since this method is called in `_enter_tree` 
	# in the plugin because of a workaround for: 
	# https://github.com/godotengine/godot-proposals/issues/2081
	if not preview_camera_3d:
		return request_hide()
		
	var is_different_camera: bool = camera_3d != preview_camera_3d
	
	# TODO: A bit messy.
	if is_different_camera:
		if preview_camera_3d.tree_exiting.is_connected(unlink_camera):
			preview_camera_3d.tree_exiting.disconnect(unlink_camera)
		
		if not camera_3d.tree_exiting.is_connected(unlink_camera):
			camera_3d.tree_exiting.connect(unlink_camera)
		
	sub_viewport.disable_3d = false
	sub_viewport.world_3d = camera_3d.get_world_3d()
	
	_selected_camera_3d = camera_3d
	_camera_type = CameraType.CAMERA_3D
	
func link_with_camera_2d(camera_2d: Camera2D) -> void:
	if not preview_camera_2d:
		return request_hide()
	
	var is_different_camera: bool = camera_2d != preview_camera_2d
	
	# TODO: A bit messy.
	if is_different_camera:
		if preview_camera_2d.tree_exiting.is_connected(unlink_camera):
			preview_camera_2d.tree_exiting.disconnect(unlink_camera)
		
		if not camera_2d.tree_exiting.is_connected(unlink_camera):
			camera_2d.tree_exiting.connect(unlink_camera)
		
	sub_viewport.disable_3d = true
	sub_viewport.world_2d = camera_2d.get_world_2d()
		
	_selected_camera_2d = camera_2d
	_camera_type = CameraType.CAMERA_2D

func unlink_camera() -> void:
	if _selected_camera_3d:
		_selected_camera_3d = null
	
	if _selected_camera_2d:
		_selected_camera_2d = null
	
	_is_locked = false
	lock_button.button_pressed = false
	
func request_hide() -> void:
	if _is_locked: return
	visible = false
	
func request_show() -> void:
	visible = true
	
func get_pinned_position(pinned_position: PinnedPosition) -> Vector2:
	var margin: Vector2 = margin_3d * _editor_scale
	
	if _camera_type == CameraType.CAMERA_2D:
		margin = margin_2d * _editor_scale
	
	match pinned_position:
		PinnedPosition.LEFT:
			return Vector2.ZERO - Vector2(0, panel.size.y) - Vector2(-margin.x, margin.y)
		PinnedPosition.RIGHT:
			return size - panel.size - margin
		_:
			assert(false, "Unknown pinned position %s" % str(pinned_position))
			
	return Vector2.ZERO
	
func get_clamped_size(desired_size: Vector2) -> Vector2:
	var viewport_ratio: float = get_project_window_ratio()
	var editor_viewport_size: Vector2 = get_editor_viewport_size()

	var max_bounds: Vector2 = Vector2(
		editor_viewport_size.x * 0.6,
		editor_viewport_size.y * 0.8
	)
	
	var clamped_size: Vector2 = desired_size
	
	# Apply aspect ratio.
	clamped_size = Vector2(clamped_size.x, clamped_size.x * viewport_ratio)
	
	# Clamp the max size while respecting the aspect ratio.
	if clamped_size.y >= max_bounds.y:
		clamped_size.x = max_bounds.y / viewport_ratio
		clamped_size.y = max_bounds.y
		
	if clamped_size.x >= max_bounds.x:
		clamped_size.x = max_bounds.x
		clamped_size.y = max_bounds.x * viewport_ratio
	
	# Clamp the min size based on if it's portrait or landscape. Portrait min
	# size should be based on it's height. Landscape min size is based on it's
	# width instead. Applying min width to a portrait size would make it too big.
	var is_portrait: bool = viewport_ratio > 1
	
	if is_portrait and clamped_size.y <= min_panel_size * _editor_scale:
		clamped_size.x = min_panel_size / viewport_ratio
		clamped_size.y = min_panel_size
		clamped_size = clamped_size * _editor_scale
		
	if not is_portrait and clamped_size.x <= min_panel_size * _editor_scale:
		clamped_size.x = min_panel_size
		clamped_size.y = min_panel_size * viewport_ratio
		clamped_size = clamped_size * _editor_scale
	
	# Round down to avoid sub-pixel artifacts, mainly seen around the margins.
	return clamped_size.floor()
	
func get_project_window_size() -> Vector2:
	var window_width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var window_height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	
	return Vector2(window_width, window_height)
	
func get_project_window_ratio() -> float:
	var project_window_size: Vector2 = get_project_window_size()
	
	return project_window_size.y / project_window_size.x
	
func get_editor_viewport_size() -> Vector2:
	var fallback_size: Vector2 = EditorInterface.get_editor_main_screen().size
	
	# There isn't an API for getting the viewport node. Instead it has to be
	# found by checking the parent's parent of the subviewport and find
	# the correct node based on name and class.
	var editor_sub_viewport_3d: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var editor_viewport_container: Control = editor_sub_viewport_3d.get_parent().get_parent().get_parent() as Control
	
	# Early return in case editor tree structure has changed.
	if not editor_viewport_container:
		return fallback_size
	
	if editor_viewport_container.get_class() != "Node3DEditorViewportContainer":
		return fallback_size
		
	return editor_viewport_container.size

func _on_resize_handle_button_down() -> void:
	if _state != InteractionState.NONE: return
	
	_state = InteractionState.RESIZE
	_initial_mouse_position = get_global_mouse_position()
	_initial_panel_size = panel.size

func _on_resize_handle_button_up() -> void:
	_state = InteractionState.NONE

func _on_drag_handle_button_down() -> void:
	if _state != InteractionState.NONE: return
		
	_state = InteractionState.DRAG
	_initial_mouse_position = get_global_mouse_position()
	_initial_panel_position = panel.global_position

func _on_drag_handle_button_up() -> void:
	if _state != InteractionState.DRAG: return
	
	_state = InteractionState.START_ANIMATE_INTO_PLACE

func _on_lock_button_pressed() -> void:
	_is_locked = !_is_locked
