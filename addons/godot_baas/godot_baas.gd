@tool
extends EditorPlugin

const AUTOLOAD_NAME = "GodotBaaS"

func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/godot_baas/godot_baas_client.gd")

func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)