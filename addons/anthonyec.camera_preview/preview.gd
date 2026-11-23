@tool

class_name CameraPreview
extends Control

const resize_icon_top_left: CompressedTexture2D = preload("./GuiResizerTopLeft.svg")
const resize_icon_top_right: CompressedTexture2D = preload("./GuiResizerTopRight.svg")
const pin_icon: CompressedTexture2D = preload("./Pin.svg")
const popout_icon: CompressedTexture2D = preload("./Popout.svg")

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
	FLOATING,
	RESIZE,
	DRAG,

	# Animation is split into 2 separate states so that the tween is only 
	# invoked once in the "start" state. 
	START_ANIMATE_INTO_PLACE,
	ANIMATE_INTO_PLACE,
	
	START_ANIMATE_POPOUT,
	ANIMATE_POPOUT,
	
	START_ANIMATE_POPIN,
	ANIMATE_POPIN
}

const BUTTON_SIZE: Vector2 = Vector2(30, 30)
const MARGIN_3D: Vector2i = Vector2i(10, 10)
const MARGIN_2D: Vector2i = Vector2i(20, 15)
const PREVIEW_PANEL_MARGIN: int = 2
const MIN_PREVIEW_PANEL_SIZE: int = 250
const POP_DURATION: float = 0.4
const POPOUT_SCREEN_MARGIN: Vector2i = Vector2i(50, 50)
const MIN_PULLOUT_DISTANCE: float = 500
const MIN_PULLOUT_VELOCITY: float = 5000

var _preview_placeholder: Panel
var _preview_panel: Window
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
var _popout_button: Button

var _camera_type: CameraType = CameraType.CAMERA_3D
var _pinned_position: PinnedPosition = PinnedPosition.RIGHT
var _editor_scale: float = EditorInterface.get_editor_scale()
var _is_locked: bool
var _is_popped_out: bool
var _show_controls: bool
var _selected_camera_3d: Camera3D
var _selected_camera_2d: Camera2D

var _state: InteractionState = InteractionState.NONE
var _initial_mouse_position: Vector2i
var _initial_preview_panel_size: Vector2i
var _initial_preview_panel_position: Vector2i

func _ready() -> void:
	_build_ui()	

func _process(delta: float) -> void:
	if not visible: return
	
	match _state:
		InteractionState.NONE:
			# Ensure viewport UI can be interacted with.
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			if not _is_popped_out:
				_preview_panel.size = get_clamped_size(_preview_panel.size)
				_preview_panel.position = get_container_screen_position() + get_local_pinned_position(_pinned_position)
			
		InteractionState.RESIZE:
			var delta_mouse_position: Vector2i = _initial_mouse_position - DisplayServer.mouse_get_position()
			var resized_size: Vector2i = _preview_panel.size
		
			if _pinned_position == PinnedPosition.LEFT:
				resized_size = _initial_preview_panel_size - delta_mouse_position
				
			if _pinned_position == PinnedPosition.RIGHT:
				resized_size = _initial_preview_panel_size + delta_mouse_position
			
			_preview_panel.size = get_clamped_size(resized_size)
			_preview_panel.position = get_container_screen_position() + get_local_pinned_position(_pinned_position)
			
			# Block mouse events from reaching the viewport so resizing isn't
			# interrupted if the cursor leaves the handle. It also prevents underlying
			# UI from highlighting.
			mouse_filter = Control.MOUSE_FILTER_STOP
			
		InteractionState.DRAG:
			_drag_handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
			
			var mouse_position: Vector2i = DisplayServer.mouse_get_position()
			var mouse_to_panel_difference: Vector2i = _initial_mouse_position - _initial_preview_panel_position
			var desired_panel_position: Vector2i = mouse_position - mouse_to_panel_difference
			_preview_panel.position = mouse_position - mouse_to_panel_difference
			
			if not _is_popped_out:
				var clamped_panel_position: Vector2i = _preview_panel.position.clamp(
					get_container_screen_position(), 
					get_container_screen_position() + get_container_size() - _preview_panel.size
				)
				
				var clamped_to_desired_direction: Vector2 = Vector2(desired_panel_position - clamped_panel_position).normalized()
				var clamped_to_desired_distance: float = clamped_panel_position.distance_to(desired_panel_position)
				var pulled_out_percent: float = clamped_to_desired_distance / MIN_PULLOUT_DISTANCE
				var tension: float = 1 / (1 + pulled_out_percent * 20)				
				
				_preview_panel.position = Vector2(clamped_panel_position).lerp(Vector2(desired_panel_position), tension)
				
				if Input.get_last_mouse_velocity().length() < 1 and clamped_to_desired_distance > MIN_PULLOUT_DISTANCE:
					_is_popped_out = true

			if mouse_position.x < global_position.x + size.x / 2:
				_pinned_position = PinnedPosition.LEFT
			else:
				_pinned_position = PinnedPosition.RIGHT
				
			_preview_placeholder.size = _preview_panel.size	
			_preview_placeholder.position = get_local_pinned_position(_pinned_position)
			
		InteractionState.START_ANIMATE_INTO_PLACE:
			_drag_handle.mouse_default_cursor_shape = Control.CURSOR_CAN_DROP
			
			var final_position: Vector2i = get_container_screen_position() + get_local_pinned_position(_pinned_position)
			
			var window_tween: Tween = create_tween()
			window_tween.set_ease(Tween.EASE_OUT)
			window_tween.set_trans(Tween.TRANS_CUBIC)
			window_tween.tween_property(_preview_panel, "position", final_position, 0.3)
			
			window_tween.finished.connect(func() -> void:
				_preview_panel.position = final_position
				_state = InteractionState.NONE
			)
			
			_state = InteractionState.ANIMATE_INTO_PLACE
			
		InteractionState.START_ANIMATE_POPOUT:
			# Final position is slightly shifted to appear as if the the preview has
			# popped out, overlapping over bits of the UI. The final size is slightly
			# bigger too to give the affect of it coming forward.
			var final_size: Vector2i = Vector2i(Vector2(_preview_panel.size) * Vector2(1.2, 1.2))
			var final_position: Vector2i = get_container_screen_position() + get_local_pinned_position(_pinned_position, final_size)
			final_position += Vector2i(float(final_size.x) * 0.4, float(final_size.y) * 0.2)
			
			# Clamp final position to fit within the screen bounds plus and minus a margin.
			var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.SCREEN_OF_MAIN_WINDOW)
			var max_final_position: Vector2i = (screen_rect.end - final_size).max(screen_rect.position)
			final_position = final_position.clamp(screen_rect.position + POPOUT_SCREEN_MARGIN, max_final_position - POPOUT_SCREEN_MARGIN)
			
			# Define the bounce look by finding the highest point to offset the top of
			# the bounce arc.
			var highest_vertical_position: int = mini(_preview_panel.position.y, final_position.y)
			var bounce_vertical_apex: int = highest_vertical_position - (size.y * 0.05)
			
			var horizontal_tween: Tween = create_tween()
			horizontal_tween.set_ease(Tween.EASE_IN_OUT)
			horizontal_tween.set_trans(Tween.TRANS_CUBIC)
			horizontal_tween.tween_property(_preview_panel, "position:x", final_position.x, POP_DURATION)
			
			var vertical_tween: Tween = create_tween()
			vertical_tween.set_ease(Tween.EASE_IN_OUT)
			vertical_tween.set_trans(Tween.TRANS_CUBIC)
			vertical_tween.tween_property(_preview_panel, "position:y", bounce_vertical_apex, POP_DURATION / 2)
			vertical_tween.tween_property(_preview_panel, "position:y", final_position.y, POP_DURATION / 2)
			
			var size_tween: Tween = create_tween()
			size_tween.set_ease(Tween.EASE_IN_OUT)
			size_tween.set_trans(Tween.TRANS_CUBIC)
			size_tween.tween_property(_preview_panel, "size", final_size, POP_DURATION)
			
			size_tween.finished.connect(func() -> void:
				_preview_panel.transient = false
				_state = InteractionState.NONE	
			)
			
			_state = InteractionState.ANIMATE_POPOUT
			
		InteractionState.ANIMATE_POPOUT:
			pass
			
		InteractionState.START_ANIMATE_POPIN:
			var final_size: Vector2i = get_clamped_size(Vector2i(Vector2(_preview_panel.size) / Vector2(1.2, 1.2)))
			var final_position: Vector2i = get_container_screen_position() + get_local_pinned_position(_pinned_position, final_size)
			
			var highest_vertical_position: int = mini(_preview_panel.position.y, final_position.y)
			var bounce_vertical_apex: int = highest_vertical_position - (size.y * 0.05)
			
			var horizontal_tween: Tween = create_tween()
			horizontal_tween.set_ease(Tween.EASE_IN_OUT)
			horizontal_tween.set_trans(Tween.TRANS_CUBIC)
			horizontal_tween.tween_property(_preview_panel, "position:x", final_position.x, POP_DURATION)
			
			var vertical_tween: Tween = create_tween()
			vertical_tween.set_ease(Tween.EASE_IN_OUT)
			vertical_tween.set_trans(Tween.TRANS_CUBIC)
			vertical_tween.tween_property(_preview_panel, "position:y", bounce_vertical_apex, POP_DURATION / 2)
			vertical_tween.tween_property(_preview_panel, "position:y", final_position.y, POP_DURATION / 2)
			
			var size_tween: Tween = create_tween()
			size_tween.set_ease(Tween.EASE_IN_OUT)
			size_tween.set_trans(Tween.TRANS_CUBIC)
			size_tween.tween_property(_preview_panel, "size", final_size, POP_DURATION)
			
			size_tween.finished.connect(func() -> void:
				_preview_panel.transient = true
				_state = InteractionState.NONE	
			)
			
			_state = InteractionState.ANIMATE_POPIN
			
		InteractionState.ANIMATE_POPIN:
			pass
			
	# I couldn't get `mouse_entered` and `mouse_exited` events to work 
	# nicely, so I use rect method instead. Plus using this method it's easy to
	# grow the hit area size.
	var preview_panel_hover_rect: Rect2 = Rect2(_preview_panel.position, _preview_panel.size)
	preview_panel_hover_rect = preview_panel_hover_rect.grow(40)
	var mouse_position: Vector2i = DisplayServer.mouse_get_position()
	_show_controls = _state != InteractionState.NONE or preview_panel_hover_rect.has_point(mouse_position)
	
	# UI visibility.
	_resize_left_handle.visible = _show_controls and _pinned_position == PinnedPosition.RIGHT and not _is_popped_out
	_resize_right_handle.visible = _show_controls and _pinned_position == PinnedPosition.LEFT and not _is_popped_out
	_lock_button.visible = (_show_controls or _is_locked) and not _is_popped_out
	_preview_placeholder.visible = (_state == InteractionState.DRAG or _state == InteractionState.ANIMATE_INTO_PLACE) and not _is_popped_out
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
		var project_window_size: Vector2i = get_project_window_size()
		var ratio: float = project_window_size.x / _preview_panel.size.x
		
		# TODO: Is there a better way to fix this?
		# The camera border is visible sometimes due to pixel rounding. 
		# Subtract 1px from right and bottom to hide this.
		var hide_camera_border_fix: Vector2i = Vector2i(1, 1)
		
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
	
	# Update viewport render after proxy camera has moved into place to avoid a 
	# stale frame from being shown when switching cameras.
	if _selected_camera_2d or _selected_camera_3d:
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		
func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_KEEP_SIZE, 0)
	z_index = 999
	
	_preview_placeholder = Panel.new()
	_preview_placeholder.modulate = Color(1.0, 1.0, 1.0, 0.7)
	
	_preview_panel = Window.new()
	_preview_panel.size.x = MIN_PREVIEW_PANEL_SIZE * _editor_scale
	_preview_panel.minimize_disabled = true
	_preview_panel.maximize_disabled = true
	_preview_panel.borderless = true
	_preview_panel.transparent = true
	_preview_panel.transient = true
	
	_proxy_camera_3d = Camera3D.new()
	
	_proxy_camera_2d = Camera2D.new()
	_proxy_camera_2d.ignore_rotation = false
	
	_viewport_margin_container = MarginContainer.new()
	_viewport_margin_container.clip_contents = true
	_viewport_margin_container.set_anchors_preset(PRESET_FULL_RECT)
	_viewport_margin_container.add_theme_constant_override("margin_left", PREVIEW_PANEL_MARGIN * _editor_scale)
	_viewport_margin_container.add_theme_constant_override("margin_top", PREVIEW_PANEL_MARGIN * _editor_scale)
	_viewport_margin_container.add_theme_constant_override("margin_right", PREVIEW_PANEL_MARGIN * _editor_scale)
	_viewport_margin_container.add_theme_constant_override("margin_bottom", PREVIEW_PANEL_MARGIN * _editor_scale)
	
	_sub_viewport = SubViewport.new()
	_sub_viewport.size_2d_override_stretch = true
	_sub_viewport.handle_input_locally = false
	_sub_viewport.gui_disable_input = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	_viewport_texture = ViewportTexture.new()
	
	_viewport_texture_rect = TextureRect.new()
	_viewport_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
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
	
	_gradient_texture_rect = TextureRect.new()
	_gradient_texture_rect.texture = gradient_texture
	_gradient_texture_rect.set_anchors_preset(PRESET_FULL_RECT)
	
	_overlay_margin_container = MarginContainer.new()
	_overlay_margin_container.add_theme_constant_override("margin_left", PREVIEW_PANEL_MARGIN * _editor_scale)
	_overlay_margin_container.add_theme_constant_override("margin_top", PREVIEW_PANEL_MARGIN * _editor_scale)
	_overlay_margin_container.add_theme_constant_override("margin_right", PREVIEW_PANEL_MARGIN * _editor_scale)
	_overlay_margin_container.add_theme_constant_override("margin_bottom", PREVIEW_PANEL_MARGIN * _editor_scale)
	_overlay_margin_container.set_anchors_preset(PRESET_FULL_RECT)
	
	_overlay_container = Control.new()
	_overlay_container.clip_contents = true
	_overlay_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_drag_handle = Button.new()
	_drag_handle.flat = true
	_drag_handle.focus_mode = Control.FOCUS_NONE
	_drag_handle.set_anchors_preset(PRESET_FULL_RECT)
	_drag_handle.button_down.connect(_on_drag_handle_button_down)
	_drag_handle.button_up.connect(_on_drag_handle_button_up)
	_drag_handle.mouse_default_cursor_shape = Control.CURSOR_CAN_DROP
	
	_resize_left_handle = Button.new()
	_resize_left_handle.size = BUTTON_SIZE * _editor_scale
	_resize_left_handle.icon = resize_icon_top_left
	_resize_left_handle.flat = true
	_resize_left_handle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resize_left_handle.expand_icon = true
	_resize_left_handle.set_anchors_and_offsets_preset(PRESET_TOP_LEFT, PRESET_MODE_KEEP_SIZE, 0)
	_resize_left_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_left_handle.button_down.connect(_on_resize_handle_button_down)
	_resize_left_handle.button_up.connect(_on_resize_handle_button_up)
	
	_resize_right_handle = Button.new()
	_resize_right_handle.size = BUTTON_SIZE * _editor_scale
	_resize_right_handle.icon = resize_icon_top_right
	_resize_right_handle.flat = true
	_resize_right_handle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resize_right_handle.expand_icon = true
	_resize_right_handle.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_KEEP_SIZE, 0)
	_resize_right_handle.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	_resize_right_handle.button_down.connect(_on_resize_handle_button_down)
	_resize_right_handle.button_up.connect(_on_resize_handle_button_up)
	
	_lock_button = Button.new()
	_lock_button.size = BUTTON_SIZE * _editor_scale
	_lock_button.icon = pin_icon
	_lock_button.flat = true
	_lock_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_button.expand_icon = true
	_lock_button.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT, PRESET_MODE_KEEP_SIZE, 0)
	_lock_button.toggle_mode = true
	_lock_button.pressed.connect(_on_lock_button_pressed)
	
	_popout_button = Button.new()
	_popout_button.size = BUTTON_SIZE * _editor_scale
	_popout_button.icon = popout_icon
	_popout_button.flat = true
	_popout_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popout_button.expand_icon = true
	_popout_button.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT, PRESET_MODE_KEEP_SIZE, 0)
	_popout_button.toggle_mode = true
	_popout_button.pressed.connect(_on_popout_button_pressed)
	
	add_children(self, [
		_preview_placeholder,
		[_preview_panel, [
			[_sub_viewport, [
				_proxy_camera_3d,
				# TODO: Disable 2D camera when not in use since it causes redraws by
				# just existing in the tree.
				_proxy_camera_2d
			]],
			[_viewport_margin_container, [
				_viewport_texture_rect
			]],
			_gradient_texture_rect,
			[_overlay_margin_container, [
				[_overlay_container, [
					_drag_handle,
					_resize_left_handle,
					_resize_right_handle,
					_lock_button,
					_popout_button
				]]
			]]
		]]
	])
	
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
	if _is_locked or _is_popped_out: return
	
	# When Godot starts with a camera is selected, it has not created the 
	# window yet.
	if _preview_panel == null: return
	
	_preview_panel.visible = false
	
func request_show() -> void:
	# Setting the viewport texture here ensure's the viewport texture reference is
	# up-to-date. If this is setup during building the UI, if the plugin starts
	# when the Godot editor first starts up, Godot won't be fully initialized,
	# causing a broken texture.
	#
	# Ideally LCP is only added once the editor is fully ready:
	# https://github.com/godotengine/godot-proposals/issues/14502
	_viewport_texture_rect.texture = _viewport_texture
	_viewport_texture.viewport_path = _sub_viewport.get_path()
	
	# Wait for proxy camera transforms and sub_viewport render to happen once in
	# `_process` before showing the camera to avoid stale frames of previously
	# selected cameras.
	await get_tree().process_frame
	
	_preview_panel.visible = true
	
## Returns the position the preview would be at for a pinned position relative 
## to the container control that fills the 2D or 3D viewport.
func get_local_pinned_position(pinned_position: PinnedPosition, preview_panel_size: Vector2 = _preview_panel.size) -> Vector2i:
	var margin: Vector2i = MARGIN_3D * _editor_scale
	
	if _camera_type == CameraType.CAMERA_2D:
		margin = MARGIN_2D * _editor_scale
	
	match pinned_position:
		PinnedPosition.LEFT:
			return Vector2i(0, size.y) - Vector2i(0, preview_panel_size.y) - Vector2i(-margin.x, margin.y)
			
		PinnedPosition.RIGHT:
			return get_container_size() - Vector2i(preview_panel_size) - margin
			
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
	
func get_project_window_size() -> Vector2i:
	var window_width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var window_height: int = int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	
	return Vector2i(window_width, window_height)
	
func get_project_window_ratio() -> float:
	var project_window_size: Vector2i = get_project_window_size()
	
	return float(project_window_size.y) / float(project_window_size.x)
	
func get_container_screen_position() -> Vector2i:
	return Vector2i(get_screen_position())
	
func get_container_size() -> Vector2i:
	return Vector2i(size)

func _on_resize_handle_button_down() -> void:
	if _state != InteractionState.NONE: return
	
	_state = InteractionState.RESIZE
	_initial_mouse_position = DisplayServer.mouse_get_position()
	_initial_preview_panel_size = _preview_panel.size

func _on_resize_handle_button_up() -> void:
	if _state != InteractionState.RESIZE: return
	
	_state = InteractionState.NONE

func _on_drag_handle_button_down() -> void:
	if _state != InteractionState.NONE: return
		
	_state = InteractionState.DRAG
	_initial_mouse_position = DisplayServer.mouse_get_position()
	_initial_preview_panel_position = _preview_panel.position

func _on_drag_handle_button_up() -> void:
	if _state != InteractionState.DRAG: return
	
	if _is_popped_out:
		_state = InteractionState.NONE
	else:
		_state = InteractionState.START_ANIMATE_INTO_PLACE

func _on_lock_button_pressed() -> void:
	_is_locked = !_is_locked

func _on_popout_button_pressed() -> void:
	if _state != InteractionState.NONE: return
	
	if _is_popped_out:
		_state = InteractionState.START_ANIMATE_POPIN
	else:
		_state = InteractionState.START_ANIMATE_POPOUT
		
	_is_popped_out = !_is_popped_out
	
