@tool

class_name CameraPreview
extends Control

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

const margin: Vector2 = Vector2(20, 20)
const min_panel_width: float = 150
const max_panel_width_ratio: float = 0.6

@onready var panel: Panel = %Panel
@onready var placeholder: Panel = %Placeholder
@onready var preview_camera: Camera3D = %Camera3D
@onready var sub_viewport: SubViewport = %SubViewport
@onready var resize_left_handle: Button = %ResizeLeftHandle
@onready var resize_right_handle: Button = %ResizeRightHandle
@onready var lock_button: Button = %LockButton

var pinned_position: PinnedPosition = PinnedPosition.RIGHT
var viewport_ratio: float = 1
var is_locked: bool
var show_controls: bool
var selected_camera: Camera3D
var remote_transform: RemoteTransform3D

var state: InteractionState = InteractionState.NONE
var initial_mouse_position: Vector2
var initial_panel_size: Vector2
var initial_panel_position: Vector2

func _ready() -> void:
	if not Engine.is_editor_hint(): return
	
	var resize_icon = EditorInterface.get_editor_theme().get_icon("GuiResizerTopLeft", "EditorIcons")
	resize_left_handle.icon = resize_icon
	resize_right_handle.icon = resize_icon
	
	var lock_icon = EditorInterface.get_editor_theme().get_icon("Pin", "EditorIcons")
	lock_button.icon = lock_icon

func _process(_delta: float) -> void:
	if not visible: return
	
	match state:
		InteractionState.NONE:
			# Constrain panel size to aspect ratio and min and max sizes.
			panel.size.y = panel.size.x * viewport_ratio
			panel.size = panel.size.clamp(
				Vector2(min_panel_width, min_panel_width * viewport_ratio),
				Vector2(size.x * max_panel_width_ratio, size.x * max_panel_width_ratio * viewport_ratio)
			)
			
			panel.position = get_pinned_position(pinned_position)
			
		InteractionState.RESIZE:
			var delta_mouse_position = initial_mouse_position - get_global_mouse_position()
		
			if pinned_position == PinnedPosition.LEFT:
				panel.size = initial_panel_size - delta_mouse_position
				
			if pinned_position == PinnedPosition.RIGHT:
				panel.size = initial_panel_size + delta_mouse_position
				
			# Constrain panel size to aspect ratio and min and max sizes.
			panel.size.y = panel.size.x * viewport_ratio
			panel.size = panel.size.clamp(
				Vector2(min_panel_width, min_panel_width * viewport_ratio),
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
			
	# TODO: I couldn't get `mouse_entered` and `mouse_exited` events to work 
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

	if not selected_camera: return
	
	# Sync camera settings to selected and to project window size.
	preview_camera.fov = selected_camera.fov
	preview_camera.projection = selected_camera.projection
	preview_camera.size = selected_camera.size
	
	# TODO: Should I use a viewport size here instead?
	var width = ProjectSettings.get_setting("display/window/size/viewport_width")
	var height = ProjectSettings.get_setting("display/window/size/viewport_height")
	
	viewport_ratio = float(height) / float(width)
	sub_viewport.size.y = sub_viewport.size.x * viewport_ratio

func link_with_camera(camera: Camera3D) -> void:
	# TODO: Camera may not be ready since this method is called in `_enter_tree` 
	# in the plugin because of a workaround for: 
	# https://github.com/godotengine/godot-proposals/issues/2081
	if not preview_camera:
		return request_hide()
		
	remote_transform = RemoteTransform3D.new()
	
	remote_transform.remote_path = preview_camera.get_path()
	remote_transform.use_global_coordinates = true
	
	camera.add_child(remote_transform)
	selected_camera = camera
	
	#if not selected_camera.tree_exited.is_connected(unlink_camera):
		#print("ADD EVENTO")
		#selected_camera.tree_exiting.connect(unlink_camera)
		#
	#print(selected_camera.tree_exited.get_connections())

	
func unlink_camera() -> void:
	if not selected_camera: return
	
	print("UNLINKO?", selected_camera)
	selected_camera.remove_child(remote_transform)
	selected_camera = null
	is_locked = false
	lock_button.toggle_mode = false
	
func request_hide() -> void:
	if is_locked: return
	visible = false
	
func request_show() -> void:
	visible = true
	
func get_pinned_position(pinned_position: PinnedPosition) -> Vector2:
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
