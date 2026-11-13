@tool

class_name CameraPreview
extends Control

const resize_icon_top_left: CompressedTexture2D = preload("./GuiResizerTopLeft.svg")
const resize_icon_top_right: CompressedTexture2D = preload("./GuiResizerTopRight.svg")
const pin_icon: CompressedTexture2D = preload("./Pin.svg")

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

const BUTTON_SIZE: Vector2 = Vector2(30, 30)
const MARGIN_3D: Vector2 = Vector2(10, 10)
const MARGIN_2D: Vector2 = Vector2(20, 15)
const PREVIEW_PANEL_MARGIN: float = 2
const MIN_PREVIEW_PANEL_SIZE: float = 250

var _preview_placeholder: Panel
var _preview_panel: Panel
var _sub_viewport: SubViewport
var _proxy_camera_3d: Camera3D
var _proxy_camera_2d: Camera2D
var _viewport_margin_container: MarginContainer
var _viewport_texture_rect: TextureRect
var _viewport_texture: ViewportTexture
var _gradient_texture_rect: TextureRect
var _overlay_margin_container: MarginContainer
var _overlay_container: Control
var _drag_handle: Button
var _resize_left_handle: Button
var _resize_right_handle: Button
var _lock_button: Button

var _camera_type: CameraType = CameraType.CAMERA_3D
var _pinned_position: PinnedPosition = PinnedPosition.RIGHT
var _editor_scale: float = EditorInterface.get_editor_scale()
var _is_locked: bool
var _show_controls: bool
var _selected_camera_3d: Camera3D
var _selected_camera_2d: Camera2D

var _state: InteractionState = InteractionState.NONE
var _initial_mouse_position: Vector2
var _initial_preview_panel_size: Vector2
var _initial_preview_panel_position: Vector2

func _ready() -> void:
	_build_ui()	

func _process(_delta: float) -> void:
	if not visible: return
	
	match _state:
		InteractionState.NONE:
			_preview_panel.size = get_clamped_size(_preview_panel.size)
			_preview_panel.position = get_pinned_position(_pinned_position)
			
			# Ensure viewport UI can be interacted with.
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			
		InteractionState.RESIZE:
			var delta_mouse_position: Vector2 = _initial_mouse_position - get_global_mouse_position()
			var resized_size: Vector2 = _preview_panel.size
		
			if _pinned_position == PinnedPosition.LEFT:
				resized_size = _initial_preview_panel_size - delta_mouse_position
				
			if _pinned_position == PinnedPosition.RIGHT:
				resized_size = _initial_preview_panel_size + delta_mouse_position
			
			_preview_panel.size = get_clamped_size(resized_size)
			_preview_panel.position = get_pinned_position(_pinned_position)
			
			# Block mouse events from reaching the viewport so resizing isn't
			# interrupted if the cursor leaves the handle. It also prevents underlying
			# UI from highlighting.
			mouse_filter = Control.MOUSE_FILTER_STOP
			
		InteractionState.DRAG:
			_preview_placeholder.size = _preview_panel.size
			
			var global_mouse_position: Vector2 = get_global_mouse_position()
			var offset: Vector2 = _initial_mouse_position - _initial_preview_panel_position
			
			_preview_panel.global_position = global_mouse_position - offset
			_preview_panel.position = _preview_panel.position.clamp(Vector2.ZERO, size - _preview_panel.size)

			if global_mouse_position.x < global_position.x + size.x / 2:
				_pinned_position = PinnedPosition.LEFT
			else:
				_pinned_position = PinnedPosition.RIGHT
				
			_preview_placeholder.position = get_pinned_position(_pinned_position)
			
		InteractionState.START_ANIMATE_INTO_PLACE:
			var final_position: Vector2 = get_pinned_position(_pinned_position)
			var tween: Tween = get_tree().create_tween()
			
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(_preview_panel, "position", final_position, 0.3)
			
			tween.finished.connect(func() -> void:
				_preview_panel.position = final_position
				_state = InteractionState.NONE
			)
			
			_state = InteractionState.ANIMATE_INTO_PLACE
			
	# I couldn't get `mouse_entered` and `mouse_exited` events to work 
	# nicely, so I use rect method instead. Plus using this method it's easy to
	# grow the hit area size.
	var preview_panel_hover_rect: Rect2 = Rect2(_preview_panel.global_position, _preview_panel.size)
	preview_panel_hover_rect = preview_panel_hover_rect.grow(40)
	
	var mouse_position: Vector2 = get_global_mouse_position()
	
	_show_controls = _state != InteractionState.NONE or preview_panel_hover_rect.has_point(mouse_position)
	
	# UI visibility.
	_resize_left_handle.visible = _show_controls and _pinned_position == PinnedPosition.RIGHT
	_resize_right_handle.visible = _show_controls and _pinned_position == PinnedPosition.LEFT
	_lock_button.visible = _show_controls or _is_locked
	_preview_placeholder.visible = _state == InteractionState.DRAG or _state == InteractionState.ANIMATE_INTO_PLACE
	_gradient_texture_rect.visible = _show_controls
	
	# Sync camera settings.
	if _camera_type == CameraType.CAMERA_3D and _selected_camera_3d:
		_sub_viewport.size = _preview_panel.size
		
		# Sync position and rotation without using a `RemoteTransform` node 
		# because if you save a camera as a scene, the remote transform node will
		# be stored within the scene. Also it's harder to keep the remote 
		# transform `remote_path` up-to-date with scene changes, which causes 
		# many errors.
		_proxy_camera_3d.global_position = _selected_camera_3d.global_position
		_proxy_camera_3d.global_rotation = _selected_camera_3d.global_rotation
		
		_proxy_camera_3d.fov = _selected_camera_3d.fov
		_proxy_camera_3d.projection = _selected_camera_3d.projection
		_proxy_camera_3d.size = _selected_camera_3d.size
		_proxy_camera_3d.cull_mask = _selected_camera_3d.cull_mask
		_proxy_camera_3d.keep_aspect = _selected_camera_3d.keep_aspect
		_proxy_camera_3d.near = _selected_camera_3d.near
		_proxy_camera_3d.far = _selected_camera_3d.far
		_proxy_camera_3d.h_offset = _selected_camera_3d.h_offset
		_proxy_camera_3d.v_offset = _selected_camera_3d.v_offset
		_proxy_camera_3d.attributes = _selected_camera_3d.attributes
		_proxy_camera_3d.environment = _selected_camera_3d.environment
	
	if _camera_type == CameraType.CAMERA_2D and _selected_camera_2d:
		var project_window_size: Vector2 = get_project_window_size()
		var ratio: float = project_window_size.x / _preview_panel.size.x
		
		# TODO: Is there a better way to fix this?
		# The camera border is visible sometimes due to pixel rounding. 
		# Subtract 1px from right and bottom to hide this.
		var hide_camera_border_fix: Vector2 = Vector2(1, 1)
		
		_sub_viewport.size = _preview_panel.size
		_sub_viewport.size_2d_override = (_preview_panel.size - hide_camera_border_fix) * ratio
		_sub_viewport.size_2d_override_stretch = true
		
		_proxy_camera_2d.global_position = _selected_camera_2d.global_position
		_proxy_camera_2d.global_rotation = _selected_camera_2d.global_rotation

		_proxy_camera_2d.offset = _selected_camera_2d.offset
		_proxy_camera_2d.zoom = _selected_camera_2d.zoom
		_proxy_camera_2d.ignore_rotation = _selected_camera_2d.ignore_rotation
		_proxy_camera_2d.anchor_mode = _selected_camera_2d.anchor_mode
		_proxy_camera_2d.limit_left = _selected_camera_2d.limit_left
		_proxy_camera_2d.limit_right = _selected_camera_2d.limit_right
		_proxy_camera_2d.limit_top = _selected_camera_2d.limit_top
		_proxy_camera_2d.limit_bottom = _selected_camera_2d.limit_bottom
		
func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	z_index = 999
	
	var preview_placeholder: Panel = Panel.new()
	preview_placeholder.modulate = Color(1.0, 1.0, 1.0, 0.7)
	_preview_placeholder = preview_placeholder
	
	var preview_panel: Panel = Panel.new()
	# Set initial width.
	preview_panel.size.x = MIN_PREVIEW_PANEL_SIZE * _editor_scale
	preview_panel.clip_contents = true
	_preview_panel = preview_panel
	
	var proxy_camera_3d: Camera3D = Camera3D.new()
	_proxy_camera_3d = proxy_camera_3d
	
	var proxy_camera_2d: Camera2D = Camera2D.new()
	proxy_camera_2d.ignore_rotation = false
	_proxy_camera_2d = proxy_camera_2d
	
	var viewport_margin_container: MarginContainer = MarginContainer.new()
	viewport_margin_container.clip_contents = true
	viewport_margin_container.set_anchors_preset(PRESET_FULL_RECT)
	viewport_margin_container.add_theme_constant_override("margin_left", PREVIEW_PANEL_MARGIN * _editor_scale)
	viewport_margin_container.add_theme_constant_override("margin_top", PREVIEW_PANEL_MARGIN * _editor_scale)
	viewport_margin_container.add_theme_constant_override("margin_right", PREVIEW_PANEL_MARGIN * _editor_scale)
	viewport_margin_container.add_theme_constant_override("margin_bottom", PREVIEW_PANEL_MARGIN * _editor_scale)
	_viewport_margin_container = viewport_margin_container
	
	var sub_viewport: SubViewport = SubViewport.new()
	sub_viewport.size_2d_override_stretch = true
	sub_viewport.handle_input_locally = false
	sub_viewport.gui_disable_input = true
	_sub_viewport = sub_viewport
	
	var viewport_texture: ViewportTexture = ViewportTexture.new()
	_viewport_texture = viewport_texture
	
	var viewport_texture_rect: TextureRect = TextureRect.new()
	viewport_texture_rect.texture = viewport_texture
	viewport_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_viewport_texture_rect = viewport_texture_rect
	
	var gradient: Gradient = Gradient.new()
	gradient.offsets = [0, 0.3, 0.6, 1.0]
	gradient.colors = [
		Color(0.0, 0.0, 0.0, 0.235),
		Color(0.0, 0.0, 0.0, 0.078),
		Color(0.0, 0.0, 0.0, 0.078),
		Color(0.0, 0.0, 0.0, 0.235)
	]
	
	var gradient_texture: GradientTexture2D = GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 256
	gradient_texture.height = 256
	gradient_texture.fill = GradientTexture2D.FILL_LINEAR
	gradient_texture.fill_from = Vector2(0, 0)
	gradient_texture.fill_to = Vector2(0, 1)
	
	var gradient_texture_rect: TextureRect = TextureRect.new()
	gradient_texture_rect.set_anchors_preset(PRESET_FULL_RECT)
	_gradient_texture_rect = gradient_texture_rect
	
	var overlay_margin_container: MarginContainer = MarginContainer.new()
	overlay_margin_container.add_theme_constant_override("margin_left", PREVIEW_PANEL_MARGIN * _editor_scale)
	overlay_margin_container.add_theme_constant_override("margin_top", PREVIEW_PANEL_MARGIN * _editor_scale)
	overlay_margin_container.add_theme_constant_override("margin_right", PREVIEW_PANEL_MARGIN * _editor_scale)
	overlay_margin_container.add_theme_constant_override("margin_bottom", PREVIEW_PANEL_MARGIN * _editor_scale)
	overlay_margin_container.set_anchors_preset(PRESET_FULL_RECT)
	_overlay_margin_container = overlay_margin_container
	
	var overlay_container: Control = Control.new()
	overlay_container.clip_contents = true
	overlay_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_container = overlay_container
	
	var drag_handle: Button = Button.new()
	drag_handle.flat = true
	drag_handle.focus_mode = Control.FOCUS_NONE
	drag_handle.set_anchors_preset(PRESET_FULL_RECT)
	drag_handle.button_down.connect(_on_drag_handle_button_down)
	drag_handle.button_up.connect(_on_drag_handle_button_up)
	_drag_handle = drag_handle
	
	var resize_left_handle: Button = Button.new()
	resize_left_handle.size = BUTTON_SIZE * _editor_scale
	resize_left_handle.icon = resize_icon_top_left
	resize_left_handle.flat = true
	resize_left_handle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resize_left_handle.expand_icon = true
	resize_left_handle.set_anchors_and_offsets_preset(PRESET_TOP_LEFT, PRESET_MODE_KEEP_SIZE, 0)
	resize_left_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	resize_left_handle.button_down.connect(_on_resize_handle_button_down)
	resize_left_handle.button_up.connect(_on_resize_handle_button_up)
	_resize_left_handle = resize_left_handle
	
	var resize_right_handle: Button = Button.new()
	resize_right_handle.size = BUTTON_SIZE * _editor_scale
	resize_right_handle.icon = resize_icon_top_right
	resize_right_handle.flat = true
	resize_right_handle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resize_right_handle.expand_icon = true
	resize_right_handle.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_KEEP_SIZE, 0)
	resize_right_handle.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	resize_right_handle.button_down.connect(_on_resize_handle_button_down)
	resize_right_handle.button_up.connect(_on_resize_handle_button_up)
	_resize_right_handle = resize_right_handle
	
	var lock_button: Button = Button.new()
	lock_button.size = BUTTON_SIZE * _editor_scale
	lock_button.icon = pin_icon
	lock_button.flat = true
	lock_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_button.expand_icon = true
	lock_button.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT, PRESET_MODE_KEEP_SIZE, 0)
	lock_button.toggle_mode = true
	lock_button.pressed.connect(_on_lock_button_pressed)
	_lock_button = lock_button
	
	add_children(self, [
		preview_placeholder,
		[preview_panel, [
			[sub_viewport, [
				proxy_camera_3d,
				# TODO: Disable 2D camera when not in use since it causes redraws by
				# just existing in the tree.
				proxy_camera_2d
			]],
			[viewport_margin_container, [
				viewport_texture_rect
			]],
			gradient_texture_rect,
			[overlay_margin_container, [
				[overlay_container, [
					drag_handle,
					resize_left_handle,
					resize_right_handle,
					lock_button
				]]
			]]
		]]
	])
	
	_viewport_texture.viewport_path = _sub_viewport.get_path()
	
func add_children(root: Node, tree: Array) -> void:
	for item: Variant in tree:
		# It's a standard leaf node.
		if item is Node:
			root.add_child(item)
			
		elif item is Array:
			# If it's exactly [Parent, [Children]].
			if item.size() == 2 and item[0] is Node and item[1] is Array:
				root.add_child(item[0])
				add_children(item[0] as Node, item[1] as Array)
				
			else:
				add_children(root, item as Array)

func link_with_camera_3d(camera_3d: Camera3D) -> void:
	# TODO: Camera may not be ready since this method is called in `_enter_tree` 
	# in the plugin because of a workaround for: 
	# https://github.com/godotengine/godot-proposals/issues/2081
	if not _proxy_camera_3d:
		return request_hide()
		
	var is_different_camera: bool = camera_3d != _proxy_camera_3d
	
	# TODO: A bit messy.
	if is_different_camera:
		if _proxy_camera_3d.tree_exiting.is_connected(unlink_camera):
			_proxy_camera_3d.tree_exiting.disconnect(unlink_camera)
		
		if not camera_3d.tree_exiting.is_connected(unlink_camera):
			camera_3d.tree_exiting.connect(unlink_camera)
		
	_sub_viewport.disable_3d = false
	_sub_viewport.world_3d = camera_3d.get_world_3d()
	
	_selected_camera_3d = camera_3d
	_camera_type = CameraType.CAMERA_3D
	
func link_with_camera_2d(camera_2d: Camera2D) -> void:
	if not _proxy_camera_2d:
		return request_hide()
	
	var is_different_camera: bool = camera_2d != _proxy_camera_2d
	
	# TODO: A bit messy.
	if is_different_camera:
		if _proxy_camera_2d.tree_exiting.is_connected(unlink_camera):
			_proxy_camera_2d.tree_exiting.disconnect(unlink_camera)
		
		if not camera_2d.tree_exiting.is_connected(unlink_camera):
			camera_2d.tree_exiting.connect(unlink_camera)
		
	_sub_viewport.disable_3d = true
	_sub_viewport.world_2d = camera_2d.get_world_2d()
		
	_selected_camera_2d = camera_2d
	_camera_type = CameraType.CAMERA_2D

func unlink_camera() -> void:
	if _selected_camera_3d:
		_selected_camera_3d = null
	
	if _selected_camera_2d:
		_selected_camera_2d = null
	
	_is_locked = false
	_lock_button.button_pressed = false
	
func request_hide() -> void:
	if _is_locked: return
	visible = false
	
func request_show() -> void:
	visible = true
	
func get_pinned_position(pinned_position: PinnedPosition) -> Vector2:
	var margin: Vector2 = MARGIN_3D * _editor_scale
	
	if _camera_type == CameraType.CAMERA_2D:
		margin = MARGIN_2D * _editor_scale
	
	match pinned_position:
		PinnedPosition.LEFT:
			return Vector2(0, size.y) - Vector2(0, _preview_panel.size.y) - Vector2(-margin.x, margin.y)
			
		PinnedPosition.RIGHT:
			return size - _preview_panel.size - margin
			
		_:
			assert(false, "Unknown pinned position %s" % str(pinned_position))
			
	return Vector2.ZERO
	
func get_clamped_size(desired_size: Vector2) -> Vector2:
	var viewport_ratio: float = get_project_window_ratio()
	var max_bounds: Vector2 = Vector2(size.x * 0.6, size.y * 0.8)
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
	
	if is_portrait and clamped_size.y <= MIN_PREVIEW_PANEL_SIZE * _editor_scale:
		clamped_size.x = MIN_PREVIEW_PANEL_SIZE / viewport_ratio
		clamped_size.y = MIN_PREVIEW_PANEL_SIZE
		clamped_size = clamped_size * _editor_scale
		
	if not is_portrait and clamped_size.x <= MIN_PREVIEW_PANEL_SIZE * _editor_scale:
		clamped_size.x = MIN_PREVIEW_PANEL_SIZE
		clamped_size.y = MIN_PREVIEW_PANEL_SIZE * viewport_ratio
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

func _on_resize_handle_button_down() -> void:
	if _state != InteractionState.NONE: return
	
	_state = InteractionState.RESIZE
	_initial_mouse_position = get_global_mouse_position()
	_initial_preview_panel_size = _preview_panel.size

func _on_resize_handle_button_up() -> void:
	_state = InteractionState.NONE

func _on_drag_handle_button_down() -> void:
	if _state != InteractionState.NONE: return
		
	_state = InteractionState.DRAG
	_initial_mouse_position = get_global_mouse_position()
	_initial_preview_panel_position = _preview_panel.global_position

func _on_drag_handle_button_up() -> void:
	if _state != InteractionState.DRAG: return
	
	_state = InteractionState.START_ANIMATE_INTO_PLACE

func _on_lock_button_pressed() -> void:
	_is_locked = !_is_locked
