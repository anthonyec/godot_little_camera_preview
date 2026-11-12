@tool
extends EditorPlugin

const preview_scene = preload("res://addons/anthonyec.camera_preview/preview.tscn")

var preview_2d: CameraPreview
var preview_3d: CameraPreview

func _enter_tree() -> void:
	# Initialise preview for 2D and 3D editor and make it start invisible before
	# it is added so it does not flash visible for one frame.
	preview_3d = preview_scene.instantiate() as CameraPreview
	preview_3d.request_hide()
	
	preview_2d = preview_scene.instantiate() as CameraPreview
	preview_2d.request_hide()

	# Add previews to their respective subviewport containers. They are added to
	# the container so that they appear above UI elements, and for 3D, sit above
	# the optional split view.
	var viewport_3d: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	var viewport_3d_container: Control = find_parent_with_class_or_null(viewport_3d, "Node3DEditorViewportContainer")	
	viewport_3d_container.add_child(preview_3d)
	
	var viewport_2d: SubViewport = EditorInterface.get_editor_viewport_2d()
	var viewport_2d_container: Control = find_parent_with_class_or_null(viewport_2d, "Control")
	viewport_2d_container.add_child(preview_2d)
	
	# Setup signals.
	EditorInterface.get_selection().selection_changed.connect(_on_editor_selection_changed)
	_on_editor_selection_changed()

func _exit_tree() -> void:
	if preview_3d:
		preview_3d.queue_free()
		
	if preview_2d:
		preview_2d.queue_free()

func _on_editor_selection_changed() -> void:
	var selected_nodes: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	var selected_camera_3d: Camera3D = get_camera_3d_or_null(selected_nodes)
	var selected_camera_2d: Camera2D = get_camera_2d_or_null(selected_nodes)
	
	if selected_camera_3d:
		preview_3d.link_with_camera_3d(selected_camera_3d)
		preview_3d.request_show()
	else:
		preview_3d.request_hide()
		
	if selected_camera_2d:
		preview_2d.link_with_camera_2d(selected_camera_2d)
		preview_2d.request_show()
	else:
		preview_2d.request_hide()

func get_camera_3d_or_null(nodes: Array[Node]) -> Camera3D:
	var camera: Camera3D
	
	for node in nodes:
		if node is Camera3D:
			camera = node as Camera3D
			break
			
	return camera
	
func get_camera_2d_or_null(nodes: Array[Node]) -> Camera2D:
	var camera: Camera2D
	
	for node in nodes:
		if node is Camera2D:
			camera = node as Camera2D
			break
			
	return camera

func find_parent_with_class_or_null(node: Node, classname: String) -> Node:
	var current: Node = node
	
	while current != null:
		current = current.get_parent()
		
		if current.get_class() == classname:
			return current
			
	return null
