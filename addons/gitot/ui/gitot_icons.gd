## gitot_icons.gd
## Single source for editor-theme icon lookup.
class_name GitotIcons
extends RefCounted


## @param icon_name: EditorIcons theme entry (e.g. "Loop", "Time").
static func get_icon(icon_name: String) -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(icon_name, &"EditorIcons")
