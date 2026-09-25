## gitot_log_console.gd
## Renders GitotLogger output live inside the dock.
## + Reflog title-bar button. Result handling stays in the dock.
class_name GitotLogConsole
extends RefCounted

var _git_engine: GitEngine
var _log_list: VBoxContainer
var _scroll: ScrollContainer
var _base: Control


## @param log_list: VBoxContainer to append log lines into.
func _init(
	git_engine: GitEngine,
	log_list: VBoxContainer,
	scroll: ScrollContainer,
	fold: FoldableContainer,
) -> void:
	_git_engine = git_engine
	_log_list = log_list
	_scroll = scroll
	_base = EditorInterface.get_base_control()
	_setup_reflog_button(fold)
	_log_list.resized.connect(_scroll_to_bottom)
	# Backfill existing history so console isn't empty on dock (re)open.
	for line in GitotLogger.log_history:
		_append_line(line)
	GitotLogger.set_listener(_append_line)


## Unregisters from GitotLogger. Call from GitotDock.teardown().
func teardown() -> void:
	GitotLogger.set_listener(Callable())
	if _log_list.resized.is_connected(_scroll_to_bottom):
		_log_list.resized.disconnect(_scroll_to_bottom)


## Adds formatted (bbcode) log line, styled to match Godot's own Output panel.
func _append_line(formatted: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true

	var base: Control = EditorInterface.get_base_control()
	label.add_theme_font_override(
		"normal_font",
		base.get_theme_font("output_source", "EditorFonts"),
	)
	label.add_theme_font_size_override(
		"normal_font_size",
		_base.get_theme_font_size("output_source_size", "EditorFonts") - 2,
	)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())

	label.text = formatted
	_log_list.add_child(label)
	if _log_list.get_child_count() > GitotLogger.MAX_HISTORY:
		_log_list.get_child(0).queue_free()


## Adds the Reflog button to the fold's title bar (same pattern as the bulk buttons).
func _setup_reflog_button(fold: FoldableContainer) -> void:
	var button: Button = Button.new()
	button.icon = _base.get_theme_icon("NodeInfo", &"EditorIcons")
	button.flat = true
	button.tooltip_text = "Reflog (last 20)"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_git_engine.get_reflog)
	fold.add_title_bar_control(button)


## Deferred: scroll_vertical max isn't updated until after the new child's
## size is computed on the next layout pass.
func _scroll_to_bottom() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
