## gitot_ui.gd
## Shared editor-UI helpers: theme icon lookup and title-bar buttons.
class_name GitotUi
extends RefCounted


## Single source for editor-theme icon lookup.
## @param icon_name: EditorIcons theme entry (e.g. "Loop", "Time").
static func get_icon(icon_name: String) -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(icon_name, &"EditorIcons")


## Busy state for long-running op buttons: disabled + "Time" icon while running, idle icon after.
static func set_busy(button: Button, busy: bool, idle_icon: String) -> void:
	button.disabled = busy
	button.icon = get_icon("Time" if busy else idle_icon)


## Flat icon button added to a FoldableContainer's title bar.
## @param toggle: true -> toggle button (state = button_pressed).
static func add_title_button(
	fold: FoldableContainer,
	icon_name: String,
	tooltip: String,
	toggle: bool = false,
) -> Button:
	var button: Button = Button.new()
	button.flat = true
	button.toggle_mode = toggle
	button.icon = get_icon(icon_name)
	button.tooltip_text = tooltip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fold.add_title_bar_control(button)
	return button
