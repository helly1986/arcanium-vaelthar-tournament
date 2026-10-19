extends Node
func _ready() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://arcanium/tools/_montaggio/vista.png")
	print("SCATTO FATTO")
	get_tree().quit()
