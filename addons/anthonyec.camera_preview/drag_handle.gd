extends Button

func _get_drag_data(at_position: Vector2) -> Variant:
	var duplicate = get_parent().duplicate()
	set_drag_preview(duplicate)
	return {}
