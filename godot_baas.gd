@tool
extends EditorPlugin

const AUTOLOAD_NAME = "GodotBaaS"

func _enter_tree() -> void:
	# Register the GodotBaaS client as an autoload singleton
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/godot_baas/godot_baas_client.gd")

func _exit_tree() -> void:
	# Unregister the autoload singleton when plugin is disabled
	remove_autoload_singleton(AUTOLOAD_NAME)