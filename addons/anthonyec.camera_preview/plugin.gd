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
	
	# TODO: Currently there is no API to get the main screen name without 
	# listening to the `EditorPlugin.main_screen_changed` signal:
	# https://github.com/godotengine/godot-proposals/issues/2081
	EditorInterface.set_main_screen_editor("Script")
	EditorInterface.set_main_screen_editor("3D")
	
	var main_screen = EditorInterface.get_editor_main_screen()
	main_screen.add_child(preview)
	
func _exit_tree() -> void:
	if preview:
		preview.queue_free()
	
func _on_main_screen_changed(screen_name: String) -> void:
	current_main_screen_name = screen_name
	_on_editor_selection_changed()

func _on_editor_selection_changed() -> void:
	if not is_main_screen_viewport():
		# This hides the preview "container" and not the preview itself, allowing
		# any locked previews to remain visible once switching back to 3D tab.
		preview.visible = false
		return

	preview.visible = true
		
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	var selected_camera: Camera3D
	
	for node in selected_nodes:
		if node is Camera3D:
			selected_camera = node as Camera3D
			break
	
	# Show the preview panel and create a remote transform in the selected cam.
	if selected_camera:
		var is_different_camera = selected_camera != preview.selected_camera
		
		# TODO: A bit messy.
		if is_different_camera:
			if preview.selected_camera and preview.selected_camera.tree_exiting.is_connected(_on_selected_camera_tree_exiting):
				preview.selected_camera.tree_exiting.disconnect(_on_selected_camera_tree_exiting)
			
			if not selected_camera.tree_exiting.is_connected(_on_selected_camera_tree_exiting):
				selected_camera.tree_exiting.connect(_on_selected_camera_tree_exiting)
		
		preview.link_with_camera(selected_camera)
		preview.request_show()
		
	else:
		preview.request_hide()
	
func is_main_screen_viewport() -> bool:
	return current_main_screen_name == "3D"

func _on_selected_camera_tree_exiting() -> void:
	preview.unlink_camera()
