@tool
extends EditorScript

const plugin_config_path = "res://addons/anthonyec.camera_preview/plugin.cfg"

func _run() -> void:
	var plugin_config = ConfigFile.new()
	
	var load_error = plugin_config.load(plugin_config_path)
	assert(load_error == OK, "Failed to load plugin config")
	
	var version = plugin_config.get_value("plugin", "version") as String
	assert(version, "Expected version number to exist")
	
	var parts = version.split(".")
	assert(parts.size() == 2, "Expected major and minor parts of version")
	
	var major = int(parts[0])
	var minor = int(parts[1])
	
	var new_version := "%s.%s" % [str(major), str(minor + 1)]
	var tag_version := "v%s" % new_version
	
	plugin_config.set_value("plugin", "version", new_version)
	plugin_config.save(plugin_config_path)
	
	var commit_path = "../" + plugin_config_path.trim_prefix("res://")
	
	var output: Array
	
	# Used `git config --global gpg.program "$(which gpg)"` to ensure 
	# commit signing works.
	var commit_result = OS.execute("git", ["commit", "-m", tag_version, commit_path], output, true)
	if commit_result != 0: return print("Error: ", output)
	print("[✓] Created new commit")
	
	output.clear()
	
	var tag_result = OS.execute("git", ["tag", tag_version])
	if tag_result != 0: return print("Error: ", output)
	print("[✓] Tagged commit")
	
	print("Updated version to %s" % tag_version)
