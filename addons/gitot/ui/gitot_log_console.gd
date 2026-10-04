## gitot_log_console.gd
## Renders GitotLogger output live inside the dock.
## + "Info" title-bar menu: Reflog, Repo size, Copy log, Clear log. Git results are logged by the router.
class_name GitotLogConsole
extends RefCounted

var _git_engine: GitEngine
var _log_list: VBoxContainer
var _scroll: ScrollContainer
var _base: Control

enum MenuItem { REFLOG, REPO_SIZE, COPY, CLEAR }


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
	_setup_info_menu(fold)
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


## Adds the Info menu to the fold's title bar: quick read-only git facts + log utilities.
func _setup_info_menu(fold: FoldableContainer) -> void:
	var menu: MenuButton = MenuButton.new()
	menu.icon = GitotUi.get_icon("NodeInfo")
	menu.flat = true
	menu.tooltip_text = "Quick git info and log tools"
	menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var popup: PopupMenu = menu.get_popup()
	popup.add_item("Reflog (last %d)" % GitEngine.REFLOG_COUNT, MenuItem.REFLOG)
	popup.add_item("Repo size", MenuItem.REPO_SIZE)
	popup.add_separator()
	popup.add_item("Copy log", MenuItem.COPY)
	popup.add_item("Clear log", MenuItem.CLEAR)
	popup.id_pressed.connect(_on_menu_item)
	fold.add_title_bar_control(menu)


func _on_menu_item(id: int) -> void:
	match id:
		MenuItem.REFLOG:
			_git_engine.get_reflog()
		MenuItem.REPO_SIZE:
			_git_engine.get_repo_size()
		MenuItem.COPY:
			DisplayServer.clipboard_set(_plain_text())
			EditorInterface.get_editor_toaster().push_toast("Gitot: log copied to the clipboard.")
		MenuItem.CLEAR:
			_clear()


## The console as plain text (BBCode stripped), one line per entry.
func _plain_text() -> String:
	var lines: PackedStringArray = []
	for child: Node in _log_list.get_children():
		if child is RichTextLabel and not child.is_queued_for_deletion():
			lines.append((child as RichTextLabel).get_parsed_text())
	return "\n".join(lines)


## Empties the console AND the history, so a dock reopen does not backfill the cleared lines.
func _clear() -> void:
	GitotLogger.log_history.clear()
	for child: Node in _log_list.get_children():
		child.queue_free()


## Deferred: scroll_vertical max isn't updated until after the new child's
## size is computed on the next layout pass.
func _scroll_to_bottom() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
