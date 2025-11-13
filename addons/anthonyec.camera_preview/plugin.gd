@tool
extends EditorPlugin

const preview_scene = preload("res://addons/anthonyec.camera_preview/preview.tscn")

var preview: CameraPreview
var current_main_screen_name: String

func _enter_tree() -> void:
	main_screen_changed.connect(_on_main_screen_changed)
	EditorInterface.get_selection().selection_changed.connect(_on_editor_selection_changed)
	
	# Initialise preview panel and add to main screen.
	preview = preview_scene.instantiate() as CameraPreview
	preview.request_hide()
	
	var main_screen: Control = EditorInterface.get_editor_main_screen() as Control
	main_screen.add_child(preview)
	
func _exit_tree() -> void:
	if preview:
		preview.queue_free()
		
func _ready() -> void:
	# TODO: Currently there is no API to get the main screen name without 
	# listening to the `EditorPlugin.main_screen_changed` signal:
	# https://github.com/godotengine/godot-proposals/issues/2081
	EditorInterface.set_main_screen_editor("Script")
	EditorInterface.set_main_screen_editor("3D")
	
func _on_main_screen_changed(screen_name: String) -> void:
	current_main_screen_name = screen_name
	
	 # TODO: Bit of a hack to prevent pinned staying between view changes on the same scene.
	preview.unlink_camera()
	_on_editor_selection_changed()

func _on_editor_selection_changed() -> void:
	if not is_main_screen_viewport():
		# This hides the preview "container" and not the preview itself, allowing
		# any locked previews to remain visible once switching back to 3D tab.
		preview.visible = false
		return
		
	preview.visible = true
	
	var selected_nodes: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	
	if selected_nodes.is_empty():
		preview.request_hide()
		return
		
	var camera_3d: Camera3D
	var camera_2d: Camera2D
	
	if current_main_screen_name == "3D":
		for node in selected_nodes:
			camera_3d = find_camera_3d(node)
			if camera_3d:
				preview.link_with_camera_3d(camera_3d)
				preview.request_show()
				return
	elif current_main_screen_name == "2D":	
		for node in selected_nodes:
			camera_2d = find_camera_2d(node)
			if camera_2d:
				preview.link_with_camera_2d(camera_2d)
				preview.request_show()
				return
	
	preview.request_hide()
	
func is_main_screen_viewport() -> bool:
	return current_main_screen_name == "3D" or current_main_screen_name == "2D"
	
func find_camera_3d(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
		
	var children = node.find_children("*", "Camera3D")
	if not children.is_empty():
		return children[0] as Camera3D
		
	return null
	
func find_camera_2d(node: Node) -> Camera2D:
	if node is Camera2D:
		return node as Camera2D
		
	var children = node.find_children("*", "Camera2D")
	if not children.is_empty():
		return children[0] as Camera2D
		
	return null

func _on_selected_camera_3d_tree_exiting() -> void:
	preview.unlink_camera()
